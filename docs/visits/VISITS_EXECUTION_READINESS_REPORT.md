# Visits execution readiness report

Date: 2026-07-24
Database project inspected: NEW-EDARA-SYS
Database actions performed: read-only SELECT statements only.

## Decision

The reviewed source bundle is buildable and the visit migrations are now suitable to begin the supervised, file-by-file rollout procedure after the user's explicit approval.

This is not an unconditional production sign-off. Final activation still depends on:
1. applying each migration manually and passing its contract;
2. completing the smoke-test matrix;
3. an authenticated visual check on real mobile widths;
4. explicitly enabling and deploying the atomic feature flag.

No migration has been applied and the atomic flag remains unset/false.

## Production preflight

Blocking integrity findings: none in duplicate sequences, concurrent in-progress visits, orphan links, counters, status alignment, base64 payloads, customer linkage, or sales/collection customer mismatch.

Known data findings:
- 1 historical rescheduled item has no reason;
- 1 historical pending item is dated 2026-07-08;
- 1,153 customer/customer-branch rows have missing or zero GPS coordinates;
- sales orders and payment receipts have no customer-branch column.

Interpretation:
- the two historical visit rows do not violate a new Foundation constraint;
- missing GPS does not block rollout and is handled by the GPS exception/review flow;
- visit RPCs only read customer/representative/status from sales and collection records and do not write to or lock those tables.

## Blocking defects found and fixed in this pass

1. Production exposes pgcrypto as `extensions.digest(text,text)`; `public.digest` does not exist. All atomic visit migrations now use the real qualified function and contracts guard the qualification.
2. Production does not yet have `visit_plan_items.reschedule_reason`. The field-execution migration now creates/normalizes that column before any ACL or policy references it.
3. The preflight previously reported expected pre-migration structures as generic missing-table failures and listed unused `activities_media`. It now labels planned structures as informational and checks `extensions.digest` explicitly.
4. One remaining physical RTL margin in ChecklistForm was changed to a logical property.

## Verification completed

- Targeted ChecklistForm test: 3/3 passed.
- Production build: passed (`tsc -b && vite build`).
- All seven visit migrations: exactly one `BEGIN` and one `COMMIT`.
- No visit migration contains `public.digest`.
- No DDL/DML targets sales, collections, returns, stock, vaults, custody, or journals.
- No `FOR UPDATE` targets sales orders or payment receipts.
- `git diff --check`: clean; line-ending notices are informational.
- Local development server responded HTTP 200.
- Atomic environment flag: unset, therefore false.

## Visual review limitation

The automated in-app browser runtime failed to start because of a Windows sandbox helper error. Static RTL/responsive checks passed for the visit pages, and the app builds, but this run does not claim a completed visual sign-off at 320/360/390/768 px.

The final human visual pass should cover:
- visit plans list;
- create-plan wizard and customer item editor;
- plan detail modals and action bars;
- field execution, keyboard-open state, sticky sync banner, checklist, camera/photo states;
- RTL overflow and safe-area behavior.

## Release controls

Use:
- `docs/visits/VISITS_RELEASE_MANIFEST.md`
- `docs/visits/VISITS_RELEASE_SHA256.txt`
- `docs/visits/VISITS_MANUAL_DEPLOYMENT_RUNBOOK.md`

Excluded payroll and maintenance files must remain outside the visits release.
