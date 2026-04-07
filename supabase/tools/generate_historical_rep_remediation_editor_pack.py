#!/usr/bin/env python3
"""
Generate SQL Editor friendly remediation batches for historical sales rep backfill.

This variant keeps the same mapping logic as the original generator, but emits:
- a full monolithic SQL script
- a JSON preview summary
- a folder of smaller self-contained SQL batch files for Supabase SQL Editor

Each batch file is rerun-safe:
- it only targets imported HIST- orders
- it allows rows already updated to the same target profile
- it aborts if any mapped order is missing or points to a conflicting rep
"""

from __future__ import annotations

import argparse
import json
import sys
import zipfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from xml.etree import ElementTree as ET


NS = {"a": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}

IMPORTER_PROFILE_ID = "410c04bc-b571-49f8-89cf-8b78b7305fd6"
FALLBACK_PROFILE_ID = "410c04bc-b571-49f8-89cf-8b78b7305fd6"
HISTORICAL_CUTOFF = "2026-03-31"

DIRECT_PROFILE_MAP = {
    "كريم شيتوس": {
        "profile_id": "de780710-d773-4450-8586-a75582741ad7",
        "profile_name": "كريم شيتوس",
    },
    "داليا مخلوف": {
        "profile_id": "3f68609d-f498-4e67-bb77-b87b2991a2d8",
        "profile_name": "داليا مخلوف",
    },
    "أحمد سلامة": {
        "profile_id": "410c04bc-b571-49f8-89cf-8b78b7305fd6",
        "profile_name": "أحمد سلامة",
    },
}


@dataclass(frozen=True)
class LegacyOrder:
    excel_order_id: str
    creator_legacy_id: str | None
    creator_name: str | None

    @property
    def order_number(self) -> str:
        return f"HIST-{self.excel_order_id[:12]}"


def sql_quote(value: str | None) -> str:
    if value is None:
        return "NULL"
    return "'" + value.replace("'", "''") + "'"


def chunked(items: list[LegacyOrder], size: int) -> Iterable[list[LegacyOrder]]:
    for i in range(0, len(items), size):
        yield items[i : i + size]


def load_shared_strings(xlsx_path: Path) -> list[str]:
    with zipfile.ZipFile(xlsx_path) as zf:
        if "xl/sharedStrings.xml" not in zf.namelist():
            return []
        root = ET.fromstring(zf.read("xl/sharedStrings.xml"))
        strings: list[str] = []
        for si in root.findall("a:si", NS):
            parts: list[str] = []
            for text_node in si.iterfind(".//a:t", NS):
                parts.append(text_node.text or "")
            strings.append("".join(parts))
        return strings


def cell_value(cell: ET.Element, shared_strings: list[str]) -> str | None:
    cell_type = cell.attrib.get("t")
    inline = cell.find("a:is", NS)
    if inline is not None:
        return "".join((t.text or "") for t in inline.iterfind(".//a:t", NS))

    value_node = cell.find("a:v", NS)
    if value_node is None:
        return None

    raw = value_node.text
    if raw is None:
        return None

    if cell_type == "s":
        return shared_strings[int(raw)]
    return raw


def parse_first_sheet_orders(xlsx_path: Path) -> list[LegacyOrder]:
    with zipfile.ZipFile(xlsx_path) as zf:
        shared_strings = load_shared_strings(xlsx_path)
        sheet_xml = ET.fromstring(zf.read("xl/worksheets/sheet1.xml"))

    rows = sheet_xml.findall(".//a:sheetData/a:row", NS)
    if not rows:
        raise RuntimeError("No rows found in sheet1.xml")

    deduped: dict[str, LegacyOrder] = {}

    for row in rows[1:]:
        row_num = row.attrib.get("r", "")
        values: dict[str, str | None] = {}
        for cell in row.findall("a:c", NS):
            ref = cell.attrib.get("r")
            if not ref:
                continue
            values[ref] = cell_value(cell, shared_strings)

        excel_order_id = values.get(f"A{row_num}")
        if not excel_order_id or excel_order_id in deduped:
            continue

        deduped[excel_order_id] = LegacyOrder(
            excel_order_id=excel_order_id,
            creator_legacy_id=values.get(f"C{row_num}"),
            creator_name=(values.get(f"D{row_num}") or "").strip() or None,
        )

    return list(deduped.values())


def target_profile_for_creator(creator_name: str | None) -> tuple[str, str, bool]:
    cleaned = (creator_name or "").strip()
    match = DIRECT_PROFILE_MAP.get(cleaned)
    if match:
        return match["profile_id"], match["profile_name"], False
    return FALLBACK_PROFILE_ID, "Ahmed Salama (fallback)", True


def build_preview(orders: list[LegacyOrder]) -> dict:
    by_creator = Counter()
    by_target = Counter()
    fallback_creators = Counter()

    for order in orders:
        creator = order.creator_name or "<missing>"
        target_id, target_name, is_fallback = target_profile_for_creator(order.creator_name)
        by_creator[creator] += 1
        by_target[(target_name, target_id)] += 1
        if is_fallback:
            fallback_creators[creator] += 1

    return {
        "historical_cutoff": HISTORICAL_CUTOFF,
        "importer_profile_id": IMPORTER_PROFILE_ID,
        "distinct_legacy_orders": len(orders),
        "creator_counts": [
            {"creator_name": name, "orders": count}
            for name, count in sorted(by_creator.items(), key=lambda x: (-x[1], x[0]))
        ],
        "target_counts": [
            {"target_profile_name": name, "target_profile_id": pid, "orders": count}
            for (name, pid), count in sorted(by_target.items(), key=lambda x: (-x[1], x[0][0]))
        ],
        "fallback_creators": [
            {"creator_name": name, "orders": count}
            for name, count in sorted(fallback_creators.items(), key=lambda x: (-x[1], x[0]))
        ],
    }


def build_sql_lines(
    orders: list[LegacyOrder],
    *,
    title: str,
    include_next_steps: bool,
) -> list[str]:
    lines: list[str] = []
    lines.append(f"-- {title}")
    lines.append("-- Generated automatically from legacy Excel export.")
    lines.append("-- Scope is strictly limited to imported HIST- orders")
    lines.append("-- with business date <= 2026-03-31.")
    lines.append("")
    lines.append("BEGIN;")
    lines.append("")
    lines.append("CREATE TEMP TABLE tmp_historical_rep_map (")
    lines.append("  excel_order_id text PRIMARY KEY,")
    lines.append("  order_number text NOT NULL UNIQUE,")
    lines.append("  creator_legacy_id text,")
    lines.append("  creator_name text,")
    lines.append("  target_profile_id uuid NOT NULL,")
    lines.append("  target_profile_name text NOT NULL,")
    lines.append("  used_fallback boolean NOT NULL DEFAULT false")
    lines.append(") ON COMMIT DROP;")
    lines.append("")

    for batch in chunked(orders, 250):
        lines.append("INSERT INTO tmp_historical_rep_map (")
        lines.append("  excel_order_id, order_number, creator_legacy_id, creator_name,")
        lines.append("  target_profile_id, target_profile_name, used_fallback")
        lines.append(") VALUES")
        value_lines: list[str] = []
        for order in batch:
            target_profile_id, target_profile_name, used_fallback = target_profile_for_creator(order.creator_name)
            value_lines.append(
                "("
                + ", ".join(
                    [
                        sql_quote(order.excel_order_id),
                        sql_quote(order.order_number),
                        sql_quote(order.creator_legacy_id),
                        sql_quote(order.creator_name),
                        sql_quote(target_profile_id),
                        sql_quote(target_profile_name),
                        "TRUE" if used_fallback else "FALSE",
                    ]
                )
                + ")"
            )
        lines.append(",\n".join(value_lines) + ";")
        lines.append("")

    lines.append("-- Preview 1: staged creator -> target distribution")
    lines.append(
        "SELECT creator_name, target_profile_name, target_profile_id, used_fallback, COUNT(*) AS orders"
    )
    lines.append("FROM tmp_historical_rep_map")
    lines.append("GROUP BY creator_name, target_profile_name, target_profile_id, used_fallback")
    lines.append("ORDER BY orders DESC, creator_name;")
    lines.append("")

    lines.append("-- Guard 1: every target profile id must exist in profiles")
    lines.append("DO $$")
    lines.append("DECLARE")
    lines.append("  v_missing integer;")
    lines.append("BEGIN")
    lines.append("  SELECT COUNT(*) INTO v_missing")
    lines.append("  FROM (")
    lines.append("    SELECT DISTINCT target_profile_id")
    lines.append("    FROM tmp_historical_rep_map")
    lines.append("  ) t")
    lines.append("  LEFT JOIN public.profiles p ON p.id = t.target_profile_id")
    lines.append("  WHERE p.id IS NULL;")
    lines.append("")
    lines.append("  IF v_missing > 0 THEN")
    lines.append("    RAISE EXCEPTION 'Missing profile ids in target mapping: %', v_missing;")
    lines.append("  END IF;")
    lines.append("END $$;")
    lines.append("")

    lines.append("-- Candidate rows limited to imported historical orders only")
    lines.append("-- Rerun-safe rule: allow rows already updated to the same target profile.")
    lines.append("CREATE TEMP TABLE tmp_historical_rep_candidates AS")
    lines.append("SELECT")
    lines.append("  so.id AS sales_order_id,")
    lines.append("  so.order_number,")
    lines.append("  DATE(COALESCE(so.delivered_at, so.order_date)) AS business_date,")
    lines.append("  so.created_by_id,")
    lines.append("  so.status,")
    lines.append("  so.rep_id,")
    lines.append("  m.excel_order_id,")
    lines.append("  m.creator_legacy_id,")
    lines.append("  m.creator_name,")
    lines.append("  m.target_profile_id,")
    lines.append("  m.target_profile_name,")
    lines.append("  m.used_fallback,")
    lines.append("  CASE WHEN so.rep_id IS NULL THEN TRUE ELSE FALSE END AS needs_update")
    lines.append("FROM public.sales_orders so")
    lines.append("JOIN tmp_historical_rep_map m ON m.order_number = so.order_number")
    lines.append(f"WHERE so.created_by_id = {sql_quote(IMPORTER_PROFILE_ID)}")
    lines.append("  AND so.order_number LIKE 'HIST-%'")
    lines.append("  AND so.status IN ('completed', 'delivered')")
    lines.append("  AND (so.rep_id IS NULL OR so.rep_id = m.target_profile_id)")
    lines.append(f"  AND DATE(COALESCE(so.delivered_at, so.order_date)) <= DATE {sql_quote(HISTORICAL_CUTOFF)};")
    lines.append("")

    lines.append("-- Preview 2: candidate counts before update")
    lines.append("SELECT COUNT(*) AS candidate_rows FROM tmp_historical_rep_candidates;")
    lines.append("SELECT COUNT(*) AS rows_needing_update FROM tmp_historical_rep_candidates WHERE needs_update;")
    lines.append("")
    lines.append(
        "SELECT target_profile_name, target_profile_id, used_fallback, COUNT(*) AS candidate_orders"
    )
    lines.append("FROM tmp_historical_rep_candidates")
    lines.append("GROUP BY target_profile_name, target_profile_id, used_fallback")
    lines.append("ORDER BY candidate_orders DESC, target_profile_name;")
    lines.append("")

    lines.append("-- Preview 3: any staged orders that did not match the imported system rows")
    lines.append("SELECT COUNT(*) AS unmatched_staged_orders")
    lines.append("FROM tmp_historical_rep_map m")
    lines.append("LEFT JOIN tmp_historical_rep_candidates c ON c.order_number = m.order_number")
    lines.append("WHERE c.order_number IS NULL;")
    lines.append("")
    lines.append("SELECT m.order_number, m.creator_name")
    lines.append("FROM tmp_historical_rep_map m")
    lines.append("LEFT JOIN tmp_historical_rep_candidates c ON c.order_number = m.order_number")
    lines.append("WHERE c.order_number IS NULL")
    lines.append("ORDER BY m.order_number")
    lines.append("LIMIT 50;")
    lines.append("")

    lines.append("-- Guard 2: every staged order must match an imported row safely")
    lines.append("DO $$")
    lines.append("DECLARE")
    lines.append("  v_expected integer;")
    lines.append("  v_candidates integer;")
    lines.append("  v_unmatched integer;")
    lines.append("BEGIN")
    lines.append("  SELECT COUNT(*) INTO v_expected FROM tmp_historical_rep_map;")
    lines.append("  SELECT COUNT(*) INTO v_candidates FROM tmp_historical_rep_candidates;")
    lines.append("  SELECT COUNT(*) INTO v_unmatched")
    lines.append("  FROM tmp_historical_rep_map m")
    lines.append("  LEFT JOIN tmp_historical_rep_candidates c ON c.order_number = m.order_number")
    lines.append("  WHERE c.order_number IS NULL;")
    lines.append("")
    lines.append("  IF v_expected <> v_candidates OR v_unmatched <> 0 THEN")
    lines.append(
        "    RAISE EXCEPTION 'Historical rep remediation aborted: expected %, candidates %, unmatched %',"
    )
    lines.append("      v_expected, v_candidates, v_unmatched;")
    lines.append("  END IF;")
    lines.append("END $$;")
    lines.append("")

    lines.append("-- Apply update")
    lines.append("UPDATE public.sales_orders so")
    lines.append("SET rep_id = c.target_profile_id")
    lines.append("FROM tmp_historical_rep_candidates c")
    lines.append("WHERE so.id = c.sales_order_id")
    lines.append("  AND so.rep_id IS NULL;")
    lines.append("")

    lines.append("-- Verification 1: rows in this batch aligned to expected target profiles")
    lines.append("SELECT COUNT(*) AS aligned_candidate_rows")
    lines.append("FROM public.sales_orders so")
    lines.append("JOIN tmp_historical_rep_candidates c ON c.sales_order_id = so.id")
    lines.append("WHERE so.rep_id = c.target_profile_id;")
    lines.append("")

    lines.append("-- Verification 2: distribution after update")
    lines.append(
        "SELECT c.target_profile_name, c.target_profile_id, c.used_fallback, COUNT(*) AS updated_orders"
    )
    lines.append("FROM public.sales_orders so")
    lines.append("JOIN tmp_historical_rep_candidates c ON c.sales_order_id = so.id")
    lines.append("WHERE so.rep_id = c.target_profile_id")
    lines.append("GROUP BY c.target_profile_name, c.target_profile_id, c.used_fallback")
    lines.append("ORDER BY updated_orders DESC, c.target_profile_name;")
    lines.append("")

    lines.append("-- Verification 3: remaining historical null reps globally after this batch")
    lines.append("SELECT COUNT(*) AS remaining_null_historical_rep_rows")
    lines.append("FROM public.sales_orders")
    lines.append(f"WHERE created_by_id = {sql_quote(IMPORTER_PROFILE_ID)}")
    lines.append("  AND rep_id IS NULL")
    lines.append("  AND order_number LIKE 'HIST-%'")
    lines.append("  AND status IN ('completed', 'delivered')")
    lines.append(f"  AND DATE(COALESCE(delivered_at, order_date)) <= DATE {sql_quote(HISTORICAL_CUTOFF)};")
    lines.append("")

    if include_next_steps:
        lines.append("-- Optional next steps after verification:")
        lines.append("-- CALL analytics.run_historical_backfill_chunk('2022-09-29', '2022-10-28');")
        lines.append("-- Then resume the remaining chunks and finally:")
        lines.append("-- CALL analytics.run_analytics_watermark_sweep(1);")
        lines.append("")

    lines.append("COMMIT;")
    lines.append("")
    return lines


def generate_sql(orders: list[LegacyOrder]) -> str:
    return "\n".join(
        build_sql_lines(
            orders,
            title="Historical sales rep remediation",
            include_next_steps=True,
        )
    )


def write_chunk_pack(orders: list[LegacyOrder], chunk_dir: Path, batch_size: int) -> dict:
    chunk_dir.mkdir(parents=True, exist_ok=True)
    total_batches = (len(orders) + batch_size - 1) // batch_size
    manifest_files: list[dict] = []

    for index, batch in enumerate(chunked(orders, batch_size), start=1):
        filename = f"{index:02d}_historical_rep_remediation_batch.sql"
        file_path = chunk_dir / filename
        file_path.write_text(
            "\n".join(
                build_sql_lines(
                    batch,
                    title=f"Historical sales rep remediation batch {index} of {total_batches}",
                    include_next_steps=False,
                )
            ),
            encoding="utf-8",
        )

        batch_preview = build_preview(batch)
        manifest_files.append(
            {
                "batch_num": index,
                "file": filename,
                "orders": len(batch),
                "target_counts": batch_preview["target_counts"],
            }
        )

    manifest = {
        "chunk_batch_size": batch_size,
        "total_batches": total_batches,
        "total_orders": len(orders),
        "files": manifest_files,
        "post_steps": [
            "After all remediation batches succeed, rerun the failed backfill chunk:",
            "CALL analytics.run_historical_backfill_chunk('2022-09-29', '2022-10-28');",
            "Then resume remaining backfill chunks only.",
            "After all chunks finish, run: CALL analytics.run_analytics_watermark_sweep(1);",
        ],
    }
    (chunk_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate SQL Editor friendly remediation batches for historical rep backfill."
    )
    parser.add_argument(
        "--xlsx",
        default=r"C:\Users\HP\OneDrive\Desktop\analyise-v2\export result.xlsx",
        help="Path to the legacy export XLSX file.",
    )
    parser.add_argument(
        "--output-sql",
        default=r"C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\.temp\historical_rep_remediation.sql",
        help="Where to write the generated monolithic SQL script.",
    )
    parser.add_argument(
        "--output-preview",
        default=r"C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\.temp\historical_rep_remediation_preview.json",
        help="Where to write the JSON preview summary.",
    )
    parser.add_argument(
        "--chunk-dir",
        default=r"C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\.temp\historical_rep_remediation_chunks",
        help="Where to write SQL Editor batch files.",
    )
    parser.add_argument(
        "--editor-batch-size",
        type=int,
        default=250,
        help="Orders per SQL Editor batch file.",
    )
    args = parser.parse_args()

    xlsx_path = Path(args.xlsx)
    output_sql = Path(args.output_sql)
    output_preview = Path(args.output_preview)
    chunk_dir = Path(args.chunk_dir)

    if not xlsx_path.exists():
        print(f"XLSX file not found: {xlsx_path}", file=sys.stderr)
        return 1

    orders = parse_first_sheet_orders(xlsx_path)
    if not orders:
        print("No historical orders were extracted from the XLSX file.", file=sys.stderr)
        return 1

    output_sql.parent.mkdir(parents=True, exist_ok=True)
    output_preview.parent.mkdir(parents=True, exist_ok=True)
    chunk_dir.mkdir(parents=True, exist_ok=True)

    preview = build_preview(orders)
    output_preview.write_text(json.dumps(preview, ensure_ascii=False, indent=2), encoding="utf-8")
    output_sql.write_text(generate_sql(orders), encoding="utf-8")
    manifest = write_chunk_pack(orders, chunk_dir, args.editor_batch_size)

    summary = {
        "distinct_orders": len(orders),
        "sql_path": str(output_sql),
        "preview_path": str(output_preview),
        "chunk_dir": str(chunk_dir),
        "chunk_manifest": str(chunk_dir / "manifest.json"),
        "chunk_batch_size": args.editor_batch_size,
        "total_batches": manifest["total_batches"],
        "target_counts": preview["target_counts"],
        "fallback_creators": preview["fallback_creators"],
    }
    sys.stdout.buffer.write((json.dumps(summary, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
