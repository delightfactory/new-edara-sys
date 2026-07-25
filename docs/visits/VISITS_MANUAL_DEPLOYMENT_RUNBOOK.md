# Manual visits deployment runbook

Date: 2026-07-24
Target project: NEW-EDARA-SYS
Mode: supervised, manual, one migration at a time.

## Non-negotiable controls

- Obtain the user's explicit approval before applying the first migration.
- Confirm a current recoverable backup / PITR state before starting.
- Use a low-traffic maintenance window.
- Keep `VITE_VISITS_ATOMIC_EXECUTION=false` throughout database migration.
- Stop immediately on any SQL error, unexpected contract row, lock timeout, or user-facing regression.
- Never use `db push` for this rollout.
- Never include the excluded payroll or maintenance files.
- Each migration already has its own transaction boundary; do not combine migrations into one batch.

## Pre-application evidence

Read-only production preflight on 2026-07-24 found:

- No invalid GPS ranges.
- No duplicate sequences or active visit activities.
- No concurrent in-progress visit conflicts.
- No orphan visit items, activities, or checklist responses.
- No counter/status mismatches.
- No base64 image payloads.
- One historical rescheduled item without a reason.
- One historical pending item dated 2026-07-08.
- Customer GPS is missing or zero on 1,153 customer/customer-branch records; this does not block schema installation, but those visits require the documented GPS exception flow.
- `sales_orders.customer_branch_id` and `payment_receipts.customer_branch_id` are absent. The visit completion RPC reads only customer/representative/status fields and does not write to or lock either table.
- The 28 planned columns across the visit migrations and the two private idempotency tables are expected to be absent before their owning phases.

The two historical visit rows require a business decision, not an automatic data rewrite. Current migrations do not add a constraint that would make either row fail Foundation.

Production schema checks also confirmed that pgcrypto exposes `extensions.digest(text,text)` rather than `public.digest`; all atomic visit migrations now use the actual qualified function. The field-execution migration now creates/normalizes `reschedule_reason` before its first ACL or policy reference.

## Manual sequence

### Gate 0 — read-only preflight

Run `supabase/verification/visits_preflight_audit.sql`.

Expected informational findings before Foundation:
- planned columns absent;
- `private.visit_operation_requests` absent;
- `private.visit_sync_conflicts` absent.

Stop for new structural or data-integrity findings not listed above.

### Gate 1 — Foundation

Apply only:
`supabase/migrations/20260703134100_visits_foundation_schema.sql`

Then run:
`supabase/verification/visits_phase_b_schema_contract.sql`

Acceptance: zero violation rows. Record execution time and result before proceeding.

### Gate 2 — RLS and state machine

Apply only:
`supabase/migrations/20260704103808_visits_rls_state_machine.sql`

Then run:
`supabase/verification/visits_phase_c_rls_state_contract.sql`

Acceptance: zero violation rows. Verify an existing non-visit activity can still be read and updated by its normal owner/manager permissions.

### Gate 3 — plan RPCs

Apply only:
`supabase/migrations/20260704145447_visits_plan_atomic_rpcs.sql`

Then run:
`supabase/verification/visits_phase_d_plan_rpcs_contract.sql`

Acceptance: zero violation rows; wrappers executable only by authenticated; private implementations inaccessible directly.

### Gate 4 — field execution RPCs

Apply only:
`supabase/migrations/20260705103803_visits_field_execution_atomic_rpcs.sql`

Then run:
`supabase/verification/visits_phase_e_execution_rpcs_contract.sql`

Acceptance: zero violation rows. Reconfirm no INSERT/UPDATE/DELETE or FOR UPDATE targets `sales_orders` or `payment_receipts`.

### Gate 5 — detail gap RPCs

Apply only:
`supabase/migrations/20260708114440_visits_plan_detail_gap_rpcs.sql`

Then run:
`supabase/verification/visits_phase_gap_plan_detail_rpcs_contract.sql`

Acceptance: zero violation rows.

### Gate 6 — proof storage

Apply only:
`supabase/migrations/20260713134745_visit_proofs_storage.sql`

Then run:
`supabase/verification/visits_phase_photo_storage_contract.sql`

Acceptance: zero violation rows; bucket remains private and paths are user/plan/item scoped.

### Gate 7 — draft item RPCs

Apply only:
`supabase/migrations/20260724105031_visits_draft_item_atomic_rpcs.sql`

Then run:
`supabase/verification/visits_draft_item_atomic_rpcs_contract.sql`

Acceptance: zero violation rows.

## Smoke test before enabling atomic mode

With a nominated sales representative and supervisor:

1. Create a draft plan with two customers.
2. Add, delete, and reorder an item.
3. Confirm the plan.
4. Start one visit with GPS.
5. Complete its mandatory checklist and attach a proof photo.
6. Complete the visit and verify the activity link.
7. Skip or reschedule the second visit with a reason.
8. Verify double-click replay does not duplicate work.
9. Verify a supervisor can see team plans but another branch cannot mutate them.
10. Verify a normal non-visit activity still creates/updates normally.
11. Verify opening a sales order and a confirmed payment receipt is unaffected.
12. Test offline start/complete, reconnect, and confirm queue synchronization.

## Frontend activation

Only after all gates and smoke tests pass:

1. Set `VITE_VISITS_ATOMIC_EXECUTION=true`.
2. Build the exact manifested source bundle.
3. Deploy the frontend.
4. Force service-worker/PWA refresh for pilot devices.
5. Pilot with a small sales group first, then expand.
6. Monitor RPC errors, sync conflicts, storage failures, and lock timeouts.

## Rollback decision

- Before frontend activation: leave the flag false and stop; existing operational flows remain on their prior path.
- After frontend activation: first disable the flag and redeploy the frontend if the fault is in atomic execution.
- Database migrations are forward-only operational changes. Do not improvise destructive down migrations on production; restore from the approved recovery point or use a separately reviewed compensating migration.
