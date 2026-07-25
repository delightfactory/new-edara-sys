# Visits release manifest

Date: 2026-07-24
Scope: visit planning, field execution, offline queue, GPS, checklists, and visit proof photos.

## Hard safety boundary

This release must not include payroll, finance maintenance, sales, collection, returns, stock, or accounting changes. Do not stage, commit, deploy, or execute any file listed under Exclusions.

The database migrations in this manifest must be applied only after the user's direct approval, manually, one file at a time, under the user's supervision.

## Frontend and client scope

- `.env.example`
- `package.json`
- `package-lock.json`
- `src/components/shared/ActivityStatusBadge.tsx`
- `src/components/shared/ChecklistForm.tsx`
- `src/hooks/useCustomerBranches.ts`
- `src/hooks/useQueryHooks.ts`
- `src/hooks/useVisitExecutionSession.ts`
- `src/lib/config/features.ts`
- `src/lib/db/visitsDb.ts`
- `src/lib/permissions/constants.ts`
- `src/lib/services/activities.ts`
- `src/lib/services/photoSyncService.ts`
- `src/lib/types/activities.ts`
- `src/lib/utils/imageCompressor.ts`
- `src/pages/activities/ActivityForm.tsx`
- `src/pages/activities/VisitExecutionMode.tsx`
- `src/pages/activities/VisitPlanDetail.tsx`
- `src/pages/activities/VisitPlanForm.tsx`
- `src/pages/activities/VisitPlansPage.tsx`
- `src/pages/activities/components/CancelGuardModal.tsx`
- `src/pages/activities/components/VisitPlanItemEditor.tsx`
- `src/pages/activities/visitPlanFormTypes.ts`
- `src/pages/activities/visitPlanFormValidation.ts`
- `src/styles/components.css`

All visit-related test files under the same folders are included in the source bundle.

## Database migration scope and order

1. `supabase/migrations/20260703134100_visits_foundation_schema.sql`
2. `supabase/migrations/20260704103808_visits_rls_state_machine.sql`
3. `supabase/migrations/20260704145447_visits_plan_atomic_rpcs.sql`
4. `supabase/migrations/20260705103803_visits_field_execution_atomic_rpcs.sql`
5. `supabase/migrations/20260708114440_visits_plan_detail_gap_rpcs.sql`
6. `supabase/migrations/20260713134745_visit_proofs_storage.sql`
7. `supabase/migrations/20260724105031_visits_draft_item_atomic_rpcs.sql`

## Verification scope

- `supabase/verification/visits_preflight_audit.sql`
- `supabase/verification/visits_phase_b_schema_contract.sql`
- `supabase/verification/visits_phase_c_rls_state_contract.sql`
- `supabase/verification/visits_phase_d_plan_rpcs_contract.sql`
- `supabase/verification/visits_phase_e_execution_rpcs_contract.sql`
- `supabase/verification/visits_phase_gap_plan_detail_rpcs_contract.sql`
- `supabase/verification/visits_phase_photo_storage_contract.sql`
- `supabase/verification/visits_draft_item_atomic_rpcs_contract.sql`

## Explicit exclusions

- `src/pages/hr/payroll/PayrollRunDetail.tsx`
- `supabase/migrations/20260613103203_fix_payroll_subcent_deficit_carryover.sql`
- `supabase/migrations/20260613121500_fix_payroll_deficit_journal_balance.sql`
- `supabase/migrations/20260703112500_optimize_non_operational_database_storage.sql`
- `supabase/maintenance/`

## Feature flag rule

Keep `VITE_VISITS_ATOMIC_EXECUTION=false` until migrations 1–7 and their contracts have completed successfully. Enabling the flag and deploying the rebuilt frontend is a separate, explicit production decision.
