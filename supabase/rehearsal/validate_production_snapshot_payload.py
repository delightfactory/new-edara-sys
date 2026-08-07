#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
FUNCTION_DIR = ROOT / "supabase" / "rehearsal" / "production_snapshot" / "functions"

# Only functions that are actually restored/used by the Batch 1->4A rehearsal
# belong in this payload gate. Payroll wrapper/approval functions are outside
# Batch 4A and are not part of the isolated restore surface.
EXPECTED = {
    "settle_attendance_day_against_leave.sql.b64": "f0cd9bc5b6787e76aa970de6a9ce9370",
    "is_employee_work_day.sql.b64": "561f564a44537961e799f5826cbf865b",
    "mark_daily_absences.sql.b64": "45983089033bddad79c682d5b58f122e",
    "run_auto_checkout.sql.b64": "d13869f50592c2dc31c63e9212183c81",
    "upsert_attendance_and_reprocess.sql.b64": "e00a7617452d6b2796366b9e9be12e90",
    "record_attendance_gps_v2.sql.b64": "12e9b106ce2992fd3268cadfde21558b",
}
PENALTY_EXPECTED = "c05f834d11387ab8312965c16a065a0a"
EMPLOYEE_PAYROLL_EXPECTED = "c24e182e9088e1a219d40aafb9e8c43a"


def extract_body(definition: bytes) -> bytes:
    marker = b"AS $function$"
    end_marker = b"$function$"
    start = definition.find(marker)
    if start < 0:
        raise ValueError("missing opening $function$ marker")
    body_start = start + len(marker)
    body_end = definition.rfind(end_marker)
    if body_end < body_start:
        raise ValueError("missing closing $function$ marker")
    return definition[body_start:body_end]


def normalized_md5(body: bytes) -> str:
    return hashlib.md5(body.replace(b"\r\n", b"\n")).hexdigest()


def decode_file(path: pathlib.Path) -> bytes:
    encoded = b"".join(path.read_bytes().split())
    return base64.b64decode(encoded, validate=True)


def decode_parts(stem: str, parts: tuple[int, ...]) -> bytes:
    encoded = b"".join(
        (FUNCTION_DIR / f"{stem}.part{i}").read_bytes().strip()
        for i in parts
    )
    return base64.b64decode(encoded, validate=True)


def validate(name: str, definition: bytes, expected: str) -> bool:
    actual = normalized_md5(extract_body(definition))
    print(f"{name}: {actual}")
    if actual != expected:
        print(f"ERROR {name}: expected production body hash {expected}", file=sys.stderr)
        return False
    return True


def main() -> int:
    failed = False

    for filename, expected in EXPECTED.items():
        try:
            if not validate(filename, decode_file(FUNCTION_DIR / filename), expected):
                failed = True
        except Exception as exc:
            print(f"ERROR {filename}: {exc}", file=sys.stderr)
            failed = True

    split_payloads = (
        (
            "process_attendance_penalties",
            "process_attendance_penalties.sql.b64",
            (1, 2, 3, 4),
            PENALTY_EXPECTED,
        ),
        (
            "calculate_employee_payroll",
            "calculate_employee_payroll.sql.b64",
            (1, 2, 3),
            EMPLOYEE_PAYROLL_EXPECTED,
        ),
    )

    for name, stem, parts, expected in split_payloads:
        try:
            if not validate(name, decode_parts(stem, parts), expected):
                failed = True
        except Exception as exc:
            print(f"ERROR {name}: {exc}", file=sys.stderr)
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
