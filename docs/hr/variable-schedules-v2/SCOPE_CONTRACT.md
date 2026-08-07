# HR Variable Schedules V2 — Scope Contract

## Purpose

Add employee-specific weekly work schedules to the existing HR system without rebuilding the HR module and without changing legacy behavior for employees who do not have an effective custom schedule.

This document is a hard scope boundary for V2. A change that does not directly serve this purpose must not enter this branch.

## Non-negotiable compatibility rule

For any employee/date with no effective custom schedule:

- attendance behavior must remain the current production behavior;
- absence behavior must remain the current production behavior;
- auto-checkout behavior must remain the current production behavior;
- penalties must remain the current production behavior;
- leave behavior must remain the current production behavior;
- payroll calculation must remain the current production behavior;
- reports and accounting must remain the current production behavior.

Installing V2 schema or enabling V2 capability must not by itself change the result for a legacy employee.

## Activation model

V2 is employee-and-date scoped, not company-wide behavior switching.

Decision rule for every schedule-dependent path:

1. If V2 is globally disabled: execute the exact legacy path.
2. If V2 is enabled but the employee has no effective custom schedule for the target date/period: execute the exact legacy path.
3. Only when the employee has an effective custom schedule for that date/period may the schedule-aware path run.

A pilot employee must therefore be possible without moving all employees to new attendance, leave, or payroll logic.

## V1 functional scope

Only the following capabilities are in scope:

1. Store versioned employee-specific weekly schedules with a future effective date.
2. Support a different start/end time by weekday.
3. Support different official daily duration between employees.
4. Support non-working weekdays per employee.
5. Resolve whether a custom schedule exists for a specific employee and date.
6. Use custom times only where necessary in attendance, absence, auto-checkout, penalties, and payroll for that employee/date.
7. Preserve historical interpretation of attendance that was actually processed using a custom schedule.
8. Provide a simple schedule editor/history inside the existing employee profile without rewriting the legacy employee profile.

## Explicitly out of scope

The following must not be implemented in this branch unless a later review proves one item is strictly required to prevent a direct correctness defect in V2:

- rebuilding the HR module;
- company work-schedule versioning;
- redesigning generic HR settings;
- changing generic settings save behavior;
- rebuilding the leave engine;
- changing leave-balance policy for legacy employees;
- redesigning attendance notifications;
- rebuilding HR reports;
- changing accounting journal logic;
- changing advances, commissions, taxes, insurance, or payroll adjustments;
- split shifts;
- overnight shifts;
- break tracking;
- department/role automatic schedule assignment;
- historical attendance backfill;
- historical payroll recalculation;
- changing approved or paid payroll runs;
- bulk migration of existing employees to custom schedules.

Existing unrelated production bugs discovered during V2 work are documented separately and are not fixed in this branch unless they block V2 correctness for a custom-schedule employee.

## Historical-data safety

- Custom schedules are future-effective only.
- No existing attendance row is backfilled merely because V2 is installed.
- No existing payroll line is recalculated merely because V2 is installed.
- No approved or paid payroll run is mutated by schedule creation or editing.
- A custom schedule version that has affected attendance cannot be edited retroactively; a new future version is required.

## Design preference

Prefer a small compatibility layer over replacement engines.

Where possible:

- keep existing public function signatures;
- preserve the exact legacy implementation;
- detect whether a custom schedule applies;
- call legacy logic unchanged when it does not;
- alter only schedule-dependent values when it does.

Do not duplicate complete attendance, leave, or payroll engines unless static and runtime evidence proves a small adapter is impossible.

## Data model target

The initial data model should be limited to:

- employee schedule version header;
- seven weekday rows per version;
- effective-from/effective-to lifecycle;
- audit metadata;
- minimal attendance schedule snapshot fields only for attendance processed under a custom schedule.

No company schedule history table is part of V2.

## Payroll rule

An employee with no custom schedule during the payroll calculation interval must execute the legacy payroll function with no schedule-derived changes.

For an employee with a custom schedule, only schedule-dependent inputs may change, for example:

- expected workdays;
- scheduled minutes/hours;
- late/early/overtime interpretation;
- absence determination where it depends on scheduled workdays.

All non-schedule payroll components remain legacy behavior.

## Leave rule

Legacy employees continue through the legacy leave flow unchanged.

For a custom-schedule employee, V2 may adapt only the minimum schedule-dependent interpretation required to prevent a leave/workday mismatch. It must not redesign balances, approval states, or generic leave policy.

Any required leave adapter must be separately reviewed before implementation.

## Rollout rule

First activation is one pilot employee with a future effective date.

Before expanding beyond the pilot, prove:

- legacy employees remain numerically identical to legacy behavior;
- pilot attendance calculations are correct;
- pilot non-working days produce no false absence/penalty;
- pilot payroll preview is correct;
- disabling V2 stops further custom-schedule processing;
- reconciliation requirements for any pilot rows already written are understood before activation.

## Development batches

Implementation must stop for review after every batch.

### Batch 0 — baseline and dependency map

Read-only inspection only. Freeze current production function definitions, signatures, grants, relevant triggers, cron jobs, and consumers. Produce a dependency matrix. No functional code.

### Batch 1 — additive schedule schema + resolver

Add only schedule tables, validation, resolver, RLS, and future-only lifecycle. No attendance/payroll callers changed.

Gate: installing Batch 1 changes zero current runtime results.

### Batch 2 — attendance adapter

Integrate custom schedule only for an employee/date that actually has a custom schedule. Legacy employees call exact legacy attendance paths.

Gate: parity tests for legacy employees plus custom-schedule attendance simulations.

### Batch 3 — absence/auto-checkout/penalty adapter

Modify only schedule-dependent timing decisions for custom-schedule employee/dates.

Gate: no off-day false absence, no custom-day false penalty, legacy parity remains exact.

### Batch 4 — payroll adapter

Use custom scheduled workdays/minutes only when the employee has a custom schedule in the calculation interval. Keep all other payroll logic frozen.

Gate: legacy payroll parity + custom pilot payroll simulations + accounting output unchanged except values intentionally driven by the pilot schedule.

### Batch 5 — UI

Add schedule editor/history to the existing employee profile. Do not rewrite the legacy profile.

Gate: legacy profile remains byte-identical where practical and all existing tabs/functions remain accessible.

### Batch 6 — release gate

No new product behavior. Add final diagnostics, pilot checklist, rollback/reconciliation checklist, and activation guard.

## Stop conditions

Stop implementation immediately if any batch requires one of the following without prior explicit review:

- modifying generic company settings behavior;
- changing all employees to a new payroll/attendance path;
- rewriting a major legacy function when a narrow adapter is possible;
- touching approved/paid payroll data;
- backfilling historical attendance;
- changing unrelated HR business policy;
- adding multiple new subsystems to solve one schedule requirement.

## Definition of done

V2 is not done because custom schedules work.

V2 is done only when both statements are true:

1. A custom-schedule employee is calculated correctly across the required HR flows.
2. An employee without a custom schedule is demonstrably unaffected by the existence or activation of V2.

Production application, deployment, global enablement, and pilot data entry each require separate explicit approval after all gates pass.
