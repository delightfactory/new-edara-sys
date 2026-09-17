# Design QA State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD inspected before this review/state write: `988d7651cda4ecb828bf1dc54a9617fec8ae3edc`
- Active slice: `DS2-HR-002 — HR admin lists/forms` — representative concern: Employees administration list
- Active implementation PR: `#41 — DS2-HR-002: Employees admin list V2`
- PR base: `design-system-v2-development`
- PR base SHA: `988d7651cda4ecb828bf1dc54a9617fec8ae3edc`
- Exact PR HEAD reviewed: `1c0ad8b220ac81630d122242b9d4917343ae08cc`
- Live PR state at disposition: `OPEN / DRAFT / mergeable=true`
- Changed-file scope: 11 files — Employees live page/presentation/tests/styles, shared Pagination/tests/CSS, DataTable pagination extraction, workstream state, and UI Implementation owned state.
- Current disposition: `AGENT-REVIEW: BLOCKED`
- Blocking severity: `P2 — Tablet touch ergonomics / canonical device contract`
- Source evidence: `SOURCE_REVIEW_PASS` withheld pending fix.
- Test evidence: `TESTS_AUTHORED_NOT_EXECUTED`.
- Exact-head build/test/lint/runtime/preview evidence: not claimed.

## Independent QA disposition

**BLOCKED on exact HEAD `1c0ad8b220ac81630d122242b9d4917343ae08cc`.**

I formed this judgment from the exact PR diff and current live product/shared contracts before comparing peer states. The migration is otherwise well bounded and moves HR toward the V2 North Star, but the newly introduced Tablet list surface violates the established touch-first device contract in two controls that are part of the migrated slice.

## Exact-head findings

### Scope / functional isolation — PASS

No DB/migration/RPC/service/RBAC/RLS/route/business-calculation/query-cache/validation/deployment file is changed.

Preserved domain truth includes:
- `useHREmployees` with the same `search`, `departmentId`, `status`, `page`, `pageSize: 25` inputs;
- page reset to 1 on search/department/status changes;
- active/on-leave stats query behavior and the pre-existing current-page field-employee metric;
- profile route `/hr/employees/${employee.id}`;
- salary visibility through `hr.payroll.read`;
- create/edit visibility through `hr.employees.create` / `hr.employees.edit`;
- `EmployeeForm` as the existing create/edit boundary.

The HR service search contract still matches the UI copy: employee search is by `full_name` or `employee_number`.

### Shared-system fit / hierarchy — PASS

- One live `ResponsiveCollection<HREmployee>` replaces duplicated hidden Desktop/Mobile interaction trees.
- Desktop remains a dense `DataTable`; Tablet is a deliberate two-column card composition; Mobile is one-column.
- Employee workflow status uses semantic `StatusBadge`; field/office categorical metadata is neutral.
- Cards reuse shared `Card`, `KeyValueList`, `MetricGrid`, `StatCard`, `Button` and `AppAction/resolveActionSet` rather than inventing a page-local mini-system.
- Initial empty and filtered empty are distinct without changing query truth.
- Shared `Pagination` is a presentation extraction from DataTable and preserves the established five-page window, callback targets, disabled boundaries, Arabic labels and `aria-current="page"` semantics.
- Long employee names/key-value content are wrap-safe at source level; LTR employee number/phone handling is retained.

### P2 blocker — Tablet touch targets FAIL

Two newly active Tablet controls remain below the canonical V2 `--ds-icon-hit-target` / 44px touch contract:

1. `src/styles/design-system-v2-pagination.css`
   - 44px pagination sizing is scoped only to `@media (max-width: 768px)`.
   - Tablet (`769–1024px`) therefore inherits legacy `.pagination-btn { width: 32px; height: 32px; }` from `components.css`.
   - PR #41 actively renders this shared Pagination below Tablet employee cards, so numbered controls are 32×32 and previous/next remain 32px high on a touch-first device class.

2. `src/styles/hr-admin-v2.css`
   - `.ds-employee-card__identity` receives `min-height: var(--ds-icon-hit-target)` only inside the Mobile media query.
   - On Tablet the new explicit identity/open button is normally driven by the 40px avatar and has no canonical 44px minimum.
   - Adjacent Employee action buttons correctly opt into shared `touchTarget`; the primary identity/open control should meet the same Tablet contract.

Minimum fix: preserve Desktop density, extend the 44px canonical minimum through the active Tablet range (`<=1024px`) for shared Pagination controls and the employee identity/open control, without changing paging/query/action semantics. Add focused authored protection for the Tablet touch boundary.

### Device / RTL / accessibility judgment

- **Desktop:** PASS at source level; dense table behavior and pagination semantics remain intact.
- **Mobile:** PASS at source level; one-column cards, explicit identity control, one direct view action, touch-safe action buttons, 44px Pagination and wrap-safe layout.
- **Tablet:** composition and capability are correct, but touch-target sizing is **BLOCKING P2** as above.
- **RTL:** PASS at source level; logical properties, Arabic labels and LTR numeric/phone islands are appropriate.
- **Focus/keyboard:** native button controls and shared focus-visible treatment are present. Generic DataTable clickable-row keyboard debt is pre-existing broader system debt, not introduced by this slice.
- **States:** loading, initial-empty, filtered-empty, one-page pagination suppression and permission-projected salary/actions are source-covered. Broader query error/offline state convergence remains program-level debt, not a new HR002 regression.

No runtime visual PASS is claimed.

### Test Artifact Gate / evidence honesty — PASS for artifacts, not execution

Focused artifacts exist for:
- employee semantic summary/card composition and permission-projected metadata;
- Mobile versus Tablet action eligibility;
- explicit identity opening;
- shared Pagination current-page semantics, five-page window, callbacks and boundaries;
- live-page source contracts for responsive composition, query/page reset, permission gates, semantic status/type treatment, empty-state distinction and `EmployeeForm` preservation.

The missing risk-specific protection is the Tablet 44px touch boundary identified above; it must be added with the fix.

Evidence remains **`TESTS_AUTHORED_NOT_EXECUTED`**. No approved environment executed tests/build/lint; no hosted CI/Actions or Vercel preview was used. No known real build/type failure was found by source inspection, which is not an executed PASS claim.

## Peer-state comparison / contradiction handling

The independent disposition above was formed first.

- **Product Design Director state on Development:** lifecycle-stale at HR001; no conflicting HR002 design judgment is recorded. `WATCH`, not an additional blocker.
- **UI Production Engineer state on Development:** lifecycle-stale at HR001. The implementer-owned state changed on the feature branch and is aligned with the HR002 scope/evidence claim, but its Tablet touch-hardening claim is incomplete relative to the actual CSS. `WATCH`; the QA P2 finding governs disposition.
- **Integration state on Development:** current through HR001 and correctly leaves HR002 as the next isolated slice / `NO_MERGE` pending review gates.
- **Previous QA state:** lifecycle-stale at HR001 and replaced by this material review.
- PR review threads were empty before this review; no material contradictory peer finding existed.

No separate cross-role `BLOCKING` contradiction is present. The current blocker is the independent QA device/touch finding.

## System-fit judgment

The HR002 direction is strong: one responsive collection, shared semantic status/action/card grammar, preserved functional truth and a useful shared Pagination extraction. It should integrate cleanly after the two Tablet touch targets are brought up to the existing V2 44px contract. This is a bounded hardening correction, not a request for redesign or wider HR scope.

### Cross-role handoff
- **To:** UI Production Engineer; Development Integrator after fresh QA; Product Design Director for awareness.
- **What changed:** Design QA reviewed PR #41 exact HEAD `1c0ad8b220ac81630d122242b9d4917343ae08cc` and found one P2 Tablet touch-contract blocker spanning shared Pagination and the Employee identity/open control.
- **Preserve:** all employee query/stats/permissions/profile-route/EmployeeForm/service/workflow truth; keep Desktop density and current responsive collection/action semantics unchanged.
- **Need from you:** extend canonical `var(--ds-icon-hit-target)` sizing through Tablet (`<=1024px`) for the two identified controls and add focused authored protection; then request fresh exact-head QA.
- **Blocker level:** `P2 / BLOCKING` for GREEN-DEV on this exact HEAD.
- **Baseline:** Development inspected `988d7651cda4ecb828bf1dc54a9617fec8ae3edc`; exact reviewed PR HEAD `1c0ad8b220ac81630d122242b9d4917343ae08cc`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`; `SOURCE_REVIEW_PASS` withheld; no executed build/test/lint/runtime/preview/release PASS claimed.
