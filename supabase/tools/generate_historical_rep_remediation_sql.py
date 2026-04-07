#!/usr/bin/env python3
"""
Generate a safe SQL remediation script to backfill historical sales_orders.rep_id
from a legacy Excel export.

This script:
- reads the XLSX directly from its OOXML zip structure
- extracts one order-level row per legacy order
- maps creator_name -> target profile id
- emits:
  1. a SQL script with preview + guarded update + verification
  2. a JSON preview file with summary counts

It does NOT connect to the database and does NOT mutate any data by itself.
"""

from __future__ import annotations

import argparse
import json
import re
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
    created_at_text: str | None
    serial: str | None
    code: str | None
    number: str | None
    customer_legacy_id: str | None
    customer_name: str | None
    final_total: str | None
    status_name: str | None

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
        if not excel_order_id:
            continue
        if excel_order_id in deduped:
            continue

        deduped[excel_order_id] = LegacyOrder(
            excel_order_id=excel_order_id,
            creator_legacy_id=values.get(f"C{row_num}"),
            creator_name=(values.get(f"D{row_num}") or "").strip() or None,
            created_at_text=values.get(f"B{row_num}"),
            serial=values.get(f"H{row_num}"),
            code=values.get(f"I{row_num}"),
            number=values.get(f"J{row_num}"),
            customer_legacy_id=values.get(f"K{row_num}"),
            customer_name=values.get(f"O{row_num}"),
            final_total=values.get(f"AK{row_num}"),
            status_name=values.get(f"AG{row_num}"),
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


def generate_sql(orders: list[LegacyOrder]) -> str:
    lines: list[str] = []
    lines.append("-- Historical sales rep remediation")
    lines.append("-- Generated automatically from legacy Excel export.")
    lines.append("-- Scope is strictly limited to imported HIST- orders with rep_id IS NULL")
    lines.append("-- and business date <= 2026-03-31.")
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

    for batch in chunked(orders, 500):
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
    lines.append("  m.used_fallback")
    lines.append("FROM public.sales_orders so")
    lines.append("JOIN tmp_historical_rep_map m ON m.order_number = so.order_number")
    lines.append(f"WHERE so.created_by_id = {sql_quote(IMPORTER_PROFILE_ID)}")
    lines.append("  AND so.rep_id IS NULL")
    lines.append("  AND so.order_number LIKE 'HIST-%'")
    lines.append("  AND so.status IN ('completed', 'delivered')")
    lines.append(f"  AND DATE(COALESCE(so.delivered_at, so.order_date)) <= DATE {sql_quote(HISTORICAL_CUTOFF)};")
    lines.append("")

    lines.append("-- Preview 2: candidate counts before update")
    lines.append("SELECT COUNT(*) AS candidate_rows FROM tmp_historical_rep_candidates;")
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

    lines.append("-- Guard 2: expected staged orders must match candidate imported rows exactly")
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
    lines.append("WHERE so.id = c.sales_order_id;")
    lines.append("")

    lines.append("-- Verification 1: all candidate rows now have rep_id")
    lines.append("SELECT COUNT(*) AS updated_candidate_rows")
    lines.append("FROM public.sales_orders")
    lines.append("WHERE id IN (SELECT sales_order_id FROM tmp_historical_rep_candidates)")
    lines.append("  AND rep_id IS NOT NULL;")
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

    lines.append("-- Verification 3: no historical imported rows should remain null after cutoff")
    lines.append("SELECT COUNT(*) AS remaining_null_historical_rep_rows")
    lines.append("FROM public.sales_orders")
    lines.append(f"WHERE created_by_id = {sql_quote(IMPORTER_PROFILE_ID)}")
    lines.append("  AND rep_id IS NULL")
    lines.append("  AND order_number LIKE 'HIST-%'")
    lines.append("  AND status IN ('completed', 'delivered')")
    lines.append(f"  AND DATE(COALESCE(delivered_at, order_date)) <= DATE {sql_quote(HISTORICAL_CUTOFF)};")
    lines.append("")

    lines.append("-- Optional next steps after verification:")
    lines.append("-- CALL analytics.run_historical_backfill_chunk('2022-09-29', '2022-10-28');")
    lines.append("-- Then resume the remaining chunks and finally:")
    lines.append("-- CALL analytics.run_analytics_watermark_sweep(1);")
    lines.append("")
    lines.append("COMMIT;")
    lines.append("")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate a guarded SQL remediation script for historical rep backfill."
    )
    parser.add_argument(
        "--xlsx",
        default=r"C:\Users\HP\OneDrive\Desktop\analyise-v2\export result.xlsx",
        help="Path to the legacy export XLSX file.",
    )
    parser.add_argument(
        "--output-sql",
        default=r"C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\.temp\historical_rep_remediation.sql",
        help="Where to write the generated SQL script.",
    )
    parser.add_argument(
        "--output-preview",
        default=r"C:\Users\HP\OneDrive\Desktop\new-edara-sys\supabase\.temp\historical_rep_remediation_preview.json",
        help="Where to write the JSON preview summary.",
    )
    args = parser.parse_args()

    xlsx_path = Path(args.xlsx)
    output_sql = Path(args.output_sql)
    output_preview = Path(args.output_preview)

    if not xlsx_path.exists():
        print(f"XLSX file not found: {xlsx_path}", file=sys.stderr)
        return 1

    orders = parse_first_sheet_orders(xlsx_path)
    if not orders:
        print("No historical orders were extracted from the XLSX file.", file=sys.stderr)
        return 1

    output_sql.parent.mkdir(parents=True, exist_ok=True)
    output_preview.parent.mkdir(parents=True, exist_ok=True)

    preview = build_preview(orders)
    output_preview.write_text(json.dumps(preview, ensure_ascii=False, indent=2), encoding="utf-8")
    output_sql.write_text(generate_sql(orders), encoding="utf-8")

    summary = json.dumps(
        {
            "distinct_orders": len(orders),
            "sql_path": str(output_sql),
            "preview_path": str(output_preview),
            "target_counts": preview["target_counts"],
            "fallback_creators": preview["fallback_creators"],
        },
        ensure_ascii=False,
        indent=2,
    )
    sys.stdout.buffer.write((summary + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
