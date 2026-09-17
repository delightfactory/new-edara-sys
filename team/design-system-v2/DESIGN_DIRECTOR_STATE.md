# Design Director State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD used for the final boundary record: `d164d03886da97bd8976722866b6732244587ef5`
- Product source baseline independently inspected before the Workstream-only boundary write: `e7a93678b9726301e7a4d2d3bdb3aecf4cf7eb5b`
- Product UI integrated through: `DS2-FIN-002`
- Current single READY slice: `DS2-HR-001`
- Open implementation PRs targeting Development at review: none.
- Current Product Design disposition: `READY — HR001 BOUNDED TO ATTENDANCE CHECK-IN PRIMARY ACTION + PROCESS PROGRESS + TRANSIENT FEEDBACK`
- Evidence level: source inspection only; no build/test/lint/runtime/preview PASS claimed.

## Independent professional judgment

**The correct representative HR001 proof is `AttendanceCheckin`, but only its operational task-control band — not the whole Attendance page and not a generic HR redesign.**

The source confirms why this is the strongest first HR/People slice: it is a true Mobile-primary Operational Task with one context-dependent next action, GPS permission gating, online/offline context, locating/submitting progress, transient success/error feedback and safe-area-aware composition. The design audit already identifies it as a `~48KB` page-local UI/CSS island whose strongest local ideas should become system patterns while workflow truth remains untouched.

I also inspected the Employee self-service Leave Request surface. It is a conventional modal form already consuming shared `ResponsiveModal + Button`; it has real form/attachment/balance debt, but it is not as strong a proof of the missing operational-task grammar. Attendance therefore advances a system-wide pattern that can later serve Field Activities without inventing an HR-specific mini-system.

The present Attendance screen is functionally sophisticated and visually focused, but the control layer still owns three local system concepts independently: a custom animated circular task button, local process-step presentation, and local success/error feedback cards. Extracting exactly those concerns is dependency-safe because the page can continue to own all eligibility, GPS, RPC, tracking and timing semantics.

## DS2-HR-001 READY boundary

### Implement in one PR only

1. **Shared `ProcessProgress` presentation pattern.**
   - Add a domain-agnostic V2 pattern under `src/components/patterns`.
   - The Attendance page/thin HR adapter supplies the existing two steps only: `تحديد الموقع GPS` and `تسجيل الحضور`, plus their explicit pending/current/completed state and optional accuracy metadata.
   - The pattern owns layout, semantic current/completed presentation, RTL and accessibility only. It must not import/understand `FlowState`, attendance services, GPS permission state, RPC result codes or transition rules.
   - Replace the local `ProgressSteps` renderer without changing when the progress surface appears.

2. **Shared `PrimaryTaskAction` composed on the existing `Button`.**
   - This is a task-surface composition, not a second button primitive and not a business-action registry.
   - It receives label, icon, disabled/loading state and callback from the page.
   - Preserve page-owned action selection exactly: no check-in record -> `بدء الدوام`; checked in and not checked out -> `إنهاء الدوام`; completed day -> no task action.
   - Both labels continue through the existing `handleAction` path and therefore the same offline/GPS/permission/RPC behavior.
   - Use the shared Button focus/loading/disabled/touch contract. Remove the page-local giant ring/pulse/button implementation for the migrated action.

3. **Reuse existing `AlertPanel` for transient task feedback.**
   - Current transient success remains success feedback with the same Arabic message and optional returned location name.
   - Current error remains danger feedback with title `تعذر التسجيل` and the same page-owned `errorMsg`.
   - Preserve the existing `SUCCESS_RESET_MS = 2500` lifecycle exactly; `AlertPanel` only renders what the page supplies.
   - Dynamic success uses polite announcement; dynamic error uses assertive alert semantics through the existing shared contract.

4. **Retire only dead local visual code and add focused protection.**
   - Remove only `ci-action-*`, local progress-step, feedback-card/spinner animation CSS made dead by this slice after source search proves there is no remaining consumer.
   - Keep every unrelated Attendance class/composition untouched.
   - Focused tests/source contracts must cover step-state semantics, current-step accessibility, Arabic labels, action callback/disabled parity, transient success/error copy + live-announcement behavior, and preservation of the page-owned attendance/GPS service boundary.

### Action hierarchy decision

Do **not** route Attendance's single task action through `AppAction / resolveActionSet`. That shared registry solves placement of multiple authorized peer actions; this screen has exactly one context-dependent operational next action. `PrimaryTaskAction` is a thin presentation composition over shared `Button`, while the page remains the sole owner of whether that next action exists and whether it means check-in or check-out.

Do not preserve the current red/green page-local action-color rule as business semantics. `إنهاء الدوام` is the current primary task, not a destructive operation merely because it ends the workday. Meaning stays explicit through Arabic label + icon + page state. Success/danger semantic tones remain appropriate for feedback/status. Do not add a confirmation step because that would change interaction/workflow semantics.

Keep the action in the current document flow. Do not make it sticky/fixed in HR001; safe interaction with GPS banners, BottomNav/safe areas and the rest of the task composition should be proven in a later controlled runtime slice before adopting `StickyTaskAction` behavior.

### Explicit exclusions

Do **not** include in HR001:

- `recordAttendanceGPS`, `recordAttendanceLocationPing`, `getAttendanceDays`, query keys/cache/refetch, RPC error-code mapping, event timestamps, location/range/accuracy rules or attendance calculations;
- `useGeoPermission`, explain-before-ask behavior, prompt/denied/granted/unavailable handling, `GeoPermissionBanner`, `GeoPermissionDialog` or browser permission guidance;
- tracking enablement/settings, periodic ping scheduling, movement thresholds, focus/resume/reconnect behavior, outside-zone/stale state or tracking copy;
- `LiveClock`, `TodayStatus`, the top online/offline header chip, employee card, tracking card, terminal day-done summary, weak-GPS warning or privacy note;
- Attendance Admin (`AttendancePage`), Leaves, Advances, Delegations, Payroll, Employee/Profile/Admin surfaces;
- broad `OperationalTaskScreen`, `ConnectionStatus`, `StickyTaskAction`, Offline/Sync framework creation or an HR shell rewrite;
- DB/migration/RPC/RBAC/RLS/service/route/business/workflow changes;
- Vercel, preview branches, GitHub Actions or `main`.

## Device / state / accessibility acceptance

- **Mobile (`<=768px`):** remains the primary completion surface. There is exactly one obvious practical `44px+` task action when eligible; no horizontal overflow; long Arabic labels remain intact; the progress/feedback band fits the current narrow operational column; safe-area behavior stays unchanged.
- **Tablet (`769–1024px`):** remains touch-first and deliberately constrained rather than becoming an oversized phone control. The task band stays aligned with the existing narrow operational content column.
- **Desktop (`>=1025px`):** remains capability-equivalent with a focused task control. This slice does not turn Attendance into an HR management surface.
- **RTL / mixed values:** use logical spacing/order; Arabic labels remain first-class; GPS accuracy/time metadata may preserve appropriate LTR/tabular presentation.
- **State completeness:** preserve `idle -> locating -> submitting -> success/error` presentation behavior. The terminal completed-day surface remains exactly outside this slice.
- **Progress accessibility:** current step is expressed semantically (`aria-current="step"` or equivalent); completion/current/pending are distinguishable by text/icon/state, not color alone.
- **Action accessibility:** shared Button focus, loading, disabled and touch semantics apply. The migrated task action must retain an accessible label.
- **Dynamic feedback:** success/error updates use the existing `AlertPanel` live-announcement contract; visual tone is never the sole meaning.
- **Motion:** any decorative motion in the shared task control is non-essential and respects reduced-motion preferences. The current continuous pulse is not required for parity.
- **Offline/GPS blocking:** existing page logic continues to prevent/suppress submission exactly as today; no shared pattern may infer those rules.

## System-pattern intent

HR001 establishes the first reusable V2 **Operational Task control grammar** from a real production workflow: page/domain code owns eligibility, device capabilities and workflow semantics; shared patterns own a clear primary task action, visible process progress and accessible transient feedback. This intentionally complements — rather than abuses — `ActionRegistry`, which remains the correct grammar for multi-action transaction/detail surfaces.

The slice should reduce independent visual implementations after migration. If implementation needs an HR-specific generic button, hard-coded Attendance states inside shared patterns, or business-aware GPS/RPC logic in the pattern layer, it is architecturally wrong.

## Peer-state comparison / freshness synthesis

After forming the judgment above, I compared the current repository states:

- **Team Memory / Integration State:** both correctly record FIN002 as integrated and HR001 as the sole next READY roadmap item. Their instruction that the Director still needed to bound HR001 is now consumed by this state + the updated Workstream; that text is stale process guidance, not a blocking contradiction.
- **UI Production Engineer:** its FIN002 feature-head state is consumed by PR #39 merge; there is no active implementation PR and no competing slice.
- **Design QA:** its FIN002 GREEN-DEV exact-head record is consumed by merge and cannot be reused for HR001.
- **Previous Design Director state:** FIN002 boundary is consumed/stale and is superseded by this HR001 state.
- **No material contradiction:** there is no current BLOCKING peer-state disagreement. HR001 can start from the latest Development HEAD with exactly this boundary.

## What changed since previous state

FIN002 is integrated. I inspected current HR/People operational source and the relevant Mobile/Operational Task blueprints, compared Attendance Check-in with self-service form surfaces, and explicitly bounded HR001 to the smallest high-value system concern: Attendance's primary task action, process progress and transient feedback only. Workstream scope was updated first on Development in `d164d03886da97bd8976722866b6732244587ef5`.

### Cross-role handoff
- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** `DS2-HR-001` is dependency-safe and explicitly bounded to `AttendanceCheckin` primary task action + process progress + transient success/error feedback, using new domain-agnostic `ProcessProgress` and `PrimaryTaskAction` patterns plus existing `AlertPanel`; no implementation PR is currently open.
- **Preserve:** every attendance/time/GPS permission/RPC/query/cache/error-code/tracking/timing/outside-zone/service/device-capability rule and callback; existing GeoPermission surfaces; LiveClock/TodayStatus/header/employee/tracking/day-done/privacy composition; no confirmation or sticky behavior is introduced.
- **Need from you:** UI Production Engineer should open exactly one HR001 PR from the latest Development HEAD and implement only this bounded presentation concern + focused tests. Design QA must independently review the stable exact PR HEAD across source/device/state/accessibility/system-fit gates. Integrator remains no-op until exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` exists.
- **Blocker level:** `NONE`.
- **Baseline:** Workstream-bounded Development `d164d03886da97bd8976722866b6732244587ef5`; active PR: none.
