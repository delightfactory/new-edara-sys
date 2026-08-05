# Employee Work Schedules — Regression Matrix

> Test plan only. No production database changes are authorized by this document.

## 1. Test strategy

The feature must pass four layers:

1. **Static validation** — schema constraints, TypeScript validation, permissions, and migration linting.
2. **Legacy parity** — employees without custom schedules must produce the same result as the current implementation.
3. **Custom schedule correctness** — schedule-specific attendance, absence, penalties, overtime, and payroll.
4. **Historical and operational safety** — no reinterpretation of old rows, no closed-payroll mutation, and no false cron actions.

Any monetary mismatch for a legacy-fallback employee is blocking, even if small, until explained and approved.

## 2. Canonical controlled schedules

### S0 — Company fallback

- Saturday–Thursday: company start/end settings.
- Friday: company weekly off.
- Current production reference: 11:00–19:00, 8 hours, 15-minute late grace.

### S1 — Ahmed Neamatallah

| Day | Working | Start | End | Minutes |
|---|---:|---:|---:|---:|
| Saturday | Yes | 15:00 | 21:00 | 360 |
| Sunday | Yes | 10:00 | 16:00 | 360 |
| Monday | Yes | 15:00 | 21:00 | 360 |
| Tuesday | Yes | 15:00 | 21:00 | 360 |
| Wednesday | Yes | 10:00 | 16:00 | 360 |
| Thursday | Yes | 10:00 | 16:00 | 360 |
| Friday | No | — | — | 0 |

### S2 — Sales official schedule

- Six configured workdays.
- A nine-hour official work window on each configured day.
- Exact start/end values are employee configuration data, not inferred from role name.
- No break calculation.

### S3 — Individual customer-service schedule

- Employee-specific subset of weekdays.
- Shorter or full daily windows entered directly.
- No separate part-time flag or payroll engine.

## 3. Resolver tests

| ID | Scenario | Expected result |
|---|---|---|
| R-001 | Employee has no custom schedule on normal day | Identical company/employee-off-day fallback to current `is_employee_work_day` |
| R-002 | Employee has no custom schedule on employee-specific off day | `weekly_off`; no working window |
| R-003 | Employee has no custom schedule on public holiday | `public_holiday`; no working window |
| R-004 | S1 Saturday | Work day, 15:00–21:00, 360 minutes, employee source |
| R-005 | S1 Sunday | Work day, 10:00–16:00, 360 minutes, employee source |
| R-006 | S1 Friday | Weekly off; no working window |
| R-007 | Custom schedule begins tomorrow | Today uses fallback; tomorrow uses custom schedule |
| R-008 | Custom schedule ends | First date after end uses next valid version or fallback |
| R-009 | Overlapping active versions | Save rejected atomically |
| R-010 | Missing weekday row | Activation rejected; attendance mutation must not continue |
| R-011 | Working day missing start/end | Validation rejected |
| R-012 | End time equal to or earlier than start | Validation rejected in v1 |
| R-013 | Malformed company time during fallback | Clear error; no absence row created |
| R-014 | Concurrent schedule saves for same employee/range | One succeeds; overlap cannot be committed |

## 4. Attendance check-in tests

Assume the existing 15-minute late grace remains unchanged unless a separate policy change is approved.

| ID | Schedule | Punch-in | Expected |
|---|---|---:|---|
| AIN-001 | S0, 11:00 | 11:00 | Present, 0 late minutes; exact fallback parity |
| AIN-002 | S0, 11:00 | 11:15 | Present, 0 late minutes; exact fallback parity |
| AIN-003 | S0, 11:00 | 11:16 | Late according to the existing minute-rounding contract |
| AIN-004 | S1 Saturday, 15:00 | 15:00 | Present, 0 late minutes |
| AIN-005 | S1 Saturday, 15:00 | 15:15 | Present, 0 late minutes |
| AIN-006 | S1 Saturday, 15:00 | 15:20 | Late based on 15:00, not company 11:00 |
| AIN-007 | S1 Sunday, 10:00 | 10:10 | Present |
| AIN-008 | S1 Friday off | Any punch | Must not silently create normal-work penalties; behavior requires explicit review state |
| AIN-009 | Public holiday | Any punch | Holiday status/working behavior remains consistent with current policy; no late penalty |
| AIN-010 | Approved leave day with punch | Existing leave-settlement behavior preserved |
| AIN-011 | Existing attendance row has snapshot | Check-in retry reuses snapshot |
| AIN-012 | Existing legacy row lacks snapshot in open period | Authorized mutation snapshots once, then calculates |
| AIN-013 | Existing row belongs to approved/paid payroll | Mutation rejected before any snapshot or punch change |

## 5. Attendance checkout tests

| ID | Schedule | Checkout | Expected |
|---|---|---:|---|
| AOUT-001 | S0 ends 19:00 | 19:00 | No early leave or overtime; fallback parity |
| AOUT-002 | S0 ends 19:00 | 19:31 | Existing overtime threshold/rounding behavior preserved |
| AOUT-003 | S1 Saturday ends 21:00 | 20:30 | Early leave 30 minutes before permission coverage |
| AOUT-004 | S1 Saturday ends 21:00 | 21:00 | Normal checkout |
| AOUT-005 | S1 Saturday ends 21:00 | 21:45 | 45 overtime minutes, subject to existing threshold contract |
| AOUT-006 | S1 Sunday ends 16:00 | 16:30 | Overtime based on 16:00, not company 19:00 |
| AOUT-007 | Valid early-leave permission | Only uncovered minutes remain penalizable |
| AOUT-008 | Approved leave overlap | Existing leave-settlement behavior preserved |
| AOUT-009 | Schedule edited after check-in | Checkout uses stored snapshot from check-in, not edited schedule |
| AOUT-010 | Duplicate checkout attempt | Existing duplicate/closed-day guard preserved |

## 6. Manual attendance tests

| ID | Scenario | Expected |
|---|---|---|
| MAN-001 | Insert full attendance for S1 Saturday | Calculates against 15:00–21:00 and stores snapshot |
| MAN-002 | Insert check-in only | Uses scheduled start; leaves day open under existing rules |
| MAN-003 | Correct punch times without schedule refresh | Original snapshot retained |
| MAN-004 | Explicit authorized refresh on open period | New snapshot applied in same transaction, calculations reprocessed |
| MAN-005 | Refresh on approved/paid payroll date | Rejected |
| MAN-006 | Manual absence on non-working custom day | Rejected or converted to weekly-off according to frozen rule; never monetary absence |
| MAN-007 | Manual attendance for fallback employee | Exact existing result |
| MAN-008 | Reprocess clears/rebuilds penalties | No duplicate penalty instances; overrides remain respected |

## 7. Automatic absence tests

| ID | Scenario | Expected |
|---|---|---|
| ABS-001 | Fallback employee misses normal workday | Same absence row and timing as current system |
| ABS-002 | Fallback employee on Friday | No absence |
| ABS-003 | S1 Saturday, no punch after 21:00 plus configured delay | One unauthorized-absence row with S1 snapshot |
| ABS-004 | S1 Sunday, no punch after 16:00 plus delay | Absence timing follows 16:00, not 19:00 |
| ABS-005 | S1 Friday | No absence |
| ABS-006 | Customer-service employee not scheduled that weekday | No absence |
| ABS-007 | Approved leave | No unauthorized absence |
| ABS-008 | Public holiday | No unauthorized absence |
| ABS-009 | Existing valid attendance | No overwrite |
| ABS-010 | Manually locked row | No overwrite |
| ABS-011 | Closed payroll coverage | No mutation |
| ABS-012 | Invalid custom schedule | Job records diagnosable failure/alert; does not mark absence |
| ABS-013 | Job rerun | Idempotent; no duplicate or destructive change |

## 8. Auto-checkout tests

| ID | Scenario | Expected |
|---|---|---|
| AUTO-001 | Fallback open day | Same checkout time and calculations as current system |
| AUTO-002 | S1 Saturday open day without tracking ping | Uses stored 21:00 scheduled end under existing auto-checkout rule |
| AUTO-003 | S1 Sunday open day without tracking ping | Uses stored 16:00 end |
| AUTO-004 | Last valid tracking ping after punch-in | Existing ping preference preserved |
| AUTO-005 | Last ping before scheduled end | Early-leave result uses snapshot end |
| AUTO-006 | Last ping after scheduled end | Overtime uses snapshot end |
| AUTO-007 | Schedule edited while day open | Stored snapshot remains authoritative |
| AUTO-008 | Manually locked day | Existing lock behavior preserved |
| AUTO-009 | Closed payroll date | No mutation |
| AUTO-010 | Job rerun | Idempotent |

## 9. Penalty tests

| ID | Scenario | Expected |
|---|---|---|
| PEN-001 | Fallback late record | Same penalty type, occurrence count, and deduction days as baseline |
| PEN-002 | S1 late record | Penalty uses late minutes calculated from employee start |
| PEN-003 | S1 early checkout | Permission coverage ends at employee scheduled end, not company end |
| PEN-004 | Unauthorized absence on scheduled workday | Existing absence penalty rule applies |
| PEN-005 | Non-working custom day | No absence or time penalty |
| PEN-006 | Overtime-only day | No late/early penalty introduced by schedule conversion |
| PEN-007 | Existing overridden penalty | Remains overridden after reprocess |
| PEN-008 | Reprocess same day repeatedly | No duplicate active penalties |
| PEN-009 | Variable scheduled durations | Minute-to-day conversion follows the frozen employee/day rule and is documented |
| PEN-010 | Legacy row without snapshot | Legacy-safe behavior; no reinterpretation from later custom schedule |

## 10. Payroll tests

### 10.1 Legacy parity

Use at least three historical-style, unapproved simulation periods with employees who have no custom schedule.

Compare old and new outputs field by field:

- `total_working_days`;
- `actual_work_days`;
- `absent_days`;
- `deducted_days`;
- `overtime_hours`;
- `gross_earned`;
- `absence_deduction`;
- `penalty_deduction`;
- `overtime_amount`;
- `total_deductions`;
- `net_salary`;
- `deficit_carryover`.

Expected: exact equality under the current production settings and numeric rounding.

### 10.2 Custom schedule scenarios

| ID | Scenario | Expected |
|---|---|---|
| PAY-001 | S1 full month | Working-day count derives from S1 days minus public holidays |
| PAY-002 | S1 hire mid-month | Entitled workdays derive from S1 between hire date and period end |
| PAY-003 | S1 termination mid-month | Entitled workdays derive from S1 through termination date |
| PAY-004 | S1 interim run | Future dates after calculation date are not treated as absence |
| PAY-005 | S2 nine-hour sales schedule | OT hourly divisor uses scheduled period minutes, not global 8 hours |
| PAY-006 | S3 fewer weekly days | Non-scheduled days do not become absences |
| PAY-007 | Variable six-/nine-hour weekdays | Scheduled period minutes equal the sum of actual configured windows |
| PAY-008 | Public holiday on custom workday | Removed from entitled workdays/minutes |
| PAY-009 | Public holiday on custom off day | Not double-subtracted |
| PAY-010 | Approved leave | Existing paid-day behavior preserved |
| PAY-011 | Authorized absence | Existing treatment preserved |
| PAY-012 | Manual payroll adjustment | Unchanged linkage and amount |
| PAY-013 | Advance deduction | Unchanged |
| PAY-014 | Commission | Unchanged |
| PAY-015 | Approved payroll | Schedule save or attendance refresh cannot mutate it |
| PAY-016 | Paid payroll | Fully immutable |
| PAY-017 | Feature switch off | New payroll output equals legacy implementation |

### 10.3 Accounting validation

For every payroll simulation:

- run the same accounting-balance check used before approval;
- verify payroll line totals equal run totals;
- verify no new journal/payment is created during calculation tests;
- approval testing occurs only on a disposable database with controlled data.

## 11. Historical stability tests

| ID | Scenario | Expected |
|---|---|---|
| HIST-001 | Create future schedule | Past attendance and payroll hashes unchanged |
| HIST-002 | Edit future draft schedule | Past data unchanged |
| HIST-003 | Replace active schedule with later version | Earlier attendance snapshots unchanged |
| HIST-004 | Query old legacy attendance without snapshot | No database mutation on read |
| HIST-005 | Attempt backdated activation through normal RPC | Rejected |
| HIST-006 | Attempt schedule deletion referenced by attendance | Rejected |
| HIST-007 | Disable feature switch | Stored schedules remain; runtime returns legacy behavior for new resolution |

## 12. Permissions and RLS tests

| ID | Actor | Expected |
|---|---|---|
| SEC-001 | Employee | Can read own effective schedule only if policy allows; cannot edit |
| SEC-002 | Sales representative | Cannot edit own or others’ schedules |
| SEC-003 | Supervisor without HR management permission | Read scope only as currently authorized; no mutation |
| SEC-004 | Authorized HR/admin user | Can create future schedule through RPC |
| SEC-005 | Authorized user supplies another employee ID | Permission and scope checks still enforced |
| SEC-006 | Direct table insert from client | Rejected unless intentionally allowed by reviewed RLS |
| SEC-007 | Invalid seven-day payload | Transaction rejected with no partial rows |
| SEC-008 | Concurrent overlapping saves | Database prevents overlap |
| SEC-009 | Resolver execution | Minimum required grant only; no unintended table exposure |

## 13. UI tests

| ID | Scenario | Expected |
|---|---|---|
| UI-001 | Employee has no custom schedule | Clearly displays “company schedule” without creating data |
| UI-002 | Load S1 | All seven days and effective dates display correctly in RTL |
| UI-003 | Toggle working day off | Time inputs clear/disable; payload has null times and zero minutes |
| UI-004 | Working day missing time | Save blocked with precise validation |
| UI-005 | End before start | Save blocked |
| UI-006 | Duplicate/missing weekday in client state | Save blocked |
| UI-007 | Effective date in protected past | Save blocked before RPC and revalidated by database |
| UI-008 | Save failure | Existing screen state preserved; no false success toast |
| UI-009 | Permission denied | Editor hidden/disabled; direct request still rejected |
| UI-010 | Mobile layout | Seven-day editor remains usable without horizontal overflow |
| UI-011 | RTL time fields | Times remain unambiguous and are not reversed |
| UI-012 | Feature switch off | No active editing path is exposed |

## 14. Operational scan tests

- Run `run_attendance_operational_scan()` against controlled dates.
- Verify no false absent/open-day alerts for custom off days.
- Verify S1 open-day alerts use the correct end time.
- Verify fallback employees’ alert set is identical to baseline.
- Verify reruns are idempotent.
- Verify one invalid schedule does not incorrectly mutate other employees.

## 15. Migration and rollback rehearsal

### Forward rehearsal

1. Restore a disposable schema matching production.
2. Capture object definitions and baseline test outputs.
3. Apply draft migrations in order.
4. Keep feature switch false.
5. Run legacy parity tests.
6. Add controlled schedules.
7. Enable only in the disposable environment.
8. Run all custom scenarios.

### Fallback rehearsal

1. Set feature switch false.
2. Confirm new attendance resolution returns legacy behavior.
3. Confirm stored snapshots remain readable.
4. Confirm no destructive schema rollback is required for operational recovery.

### Full rollback rehearsal

Only on the disposable environment:

- restore original function definitions;
- remove unreferenced draft data if needed;
- retain historical snapshots if any test rows reference them;
- prove baseline outputs match the pre-migration capture.

## 16. Release blockers

Release is blocked by any of:

- a legacy fallback mismatch;
- an affected function still reading global times independently;
- a false absence or penalty on a custom off day;
- a schedule edit changing an old attendance result;
- mutation of approved/paid payroll data;
- unresolved RLS exposure;
- overlapping schedule ranges possible under concurrency;
- unbalanced payroll accounting simulation;
- missing rollback/fallback evidence;
- build, lint, or test failure;
- unrelated branch changes.