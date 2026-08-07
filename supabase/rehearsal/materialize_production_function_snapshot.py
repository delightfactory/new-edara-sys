#!/usr/bin/env python3
"""Materialize the HR V2 production function baseline without replaying migration history.

The script scans SQL already versioned in this repository and selects only a function
body whose normalized MD5 exactly matches the read-only production catalog capture.
It never connects to production and never guesses based on migration order.
"""

from __future__ import annotations

import hashlib
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / "supabase" / "migrations"
OUT = ROOT / "supabase" / "rehearsal" / "production_snapshot" / "03_production_guard_functions.sql"

EXPECTED = {
    "record_attendance_gps_v2": "12e9b106ce2992fd3268cadfde21558b",
    "upsert_attendance_and_reprocess": "e00a7617452d6b2796366b9e9be12e90",
    "is_employee_work_day": "561f564a44537961e799f5826cbf865b",
    "mark_daily_absences": "45983089033bddad79c682d5b58f122e",
    "run_auto_checkout": "d13869f50592c2dc31c63e9212183c81",
    "process_attendance_penalties": "c05f834d11387ab8312965c16a065a0a",
    "settle_attendance_day_against_leave": "f0cd9bc5b6787e76aa970de6a9ce9370",
    "calculate_employee_payroll": "c24e182e9088e1a219d40aafb9e8c43a",
}


def normalized_md5(body: str) -> str:
    return hashlib.md5(body.replace("\r\n", "\n").encode("utf-8")).hexdigest()


def candidates(text: str, name: str):
    marker = f"CREATE OR REPLACE FUNCTION public.{name}"
    start = 0
    while True:
        pos = text.find(marker, start)
        if pos < 0:
            return
        as_pos = text.find("AS $function$", pos)
        if as_pos < 0:
            start = pos + len(marker)
            continue
        body_start = as_pos + len("AS $function$")
        end_marker = "$function$;"
        body_end = text.find(end_marker, body_start)
        if body_end < 0:
            start = pos + len(marker)
            continue
        statement_end = body_end + len(end_marker)
        yield text[pos:statement_end], text[body_start:body_end]
        start = statement_end


def main() -> int:
    sql_files = sorted(MIGRATIONS.glob("*.sql"))
    selected: dict[str, tuple[str, pathlib.Path]] = {}
    seen_hashes: dict[str, list[tuple[str, str]]] = {k: [] for k in EXPECTED}

    for path in sql_files:
        text = path.read_text(encoding="utf-8")
        for name, expected_hash in EXPECTED.items():
            for statement, body in candidates(text, name):
                digest = normalized_md5(body)
                seen_hashes[name].append((digest, path.name))
                if digest == expected_hash:
                    # Multiple identical historical copies are harmless; the body
                    # identity, not filename chronology, is the authority.
                    selected[name] = (statement, path)

    missing = [name for name in EXPECTED if name not in selected]
    if missing:
        for name in missing:
            observed = ", ".join(f"{h}@{p}" for h, p in seen_hashes[name][-8:]) or "none"
            print(f"ERROR: no repository definition matches production hash for {name}: {EXPECTED[name]}", file=sys.stderr)
            print(f"  observed candidates: {observed}", file=sys.stderr)
        return 1

    header = [
        "-- GENERATED FOR ISOLATED HR V2 REHEARSAL ONLY.",
        "-- Source selection authority: exact normalized production prosrc MD5 captured read-only on 2026-08-07.",
        "-- No migration ordering is replayed and no production connection is used by the rehearsal.",
        "",
    ]
    parts = header
    for name in EXPECTED:
        statement, path = selected[name]
        parts.append(f"-- {name} | production body md5={EXPECTED[name]} | repository source={path.name}")
        parts.append(statement)
        parts.append("")

    OUT.write_text("\n".join(parts), encoding="utf-8")
    print(f"materialized {len(selected)} production-matched functions -> {OUT}")
    for name in EXPECTED:
        print(f"  {name}: {EXPECTED[name]} ({selected[name][1].name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
