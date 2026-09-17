# Design QA State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD inspected before this review/state write: `def098978efbe796306f882014e69652f014efa6`
- Active slice: `DS2-FIELD-001 — Activities/visit/call/target lists`
- Active representative concern: `ActivitiesPage` list presentation only
- Active implementation PR: `#42 — DS2-FIELD-001: Activities list V2 foundation`
- PR base: `design-system-v2-development`
- PR base SHA: `def098978efbe796306f882014e69652f014efa6`
- Exact current PR HEAD independently reviewed: `823c89d10201a8db68e7189803bd003c3fd9fd2f`
- Live PR state at disposition: `OPEN / DRAFT / mergeable=true`
- Changed-file scope: 7 files — Activities live page, thin Field presentation adapter, focused tests, bounded Field CSS, workstream state and UI Implementation owned state.
- Current disposition: `AGENT-REVIEW: BLOCKED`
- Severity: `P2 / NO_MERGE`
- `SOURCE_REVIEW_PASS`: **withheld** pending the bounded fixes below.
- Test evidence: `TESTS_AUTHORED_NOT_EXECUTED`.
- Exact-head build/test/lint/runtime/preview evidence: not claimed.

## Independent QA disposition

**BLOCKED on exact PR HEAD `823c89d10201a8db68e7189803bd003c3fd9fd2f`.**

I formed this judgment from the exact PR diff and the current Activities/shared-component contracts before comparing peer states. The migration is directionally strong and functionally isolated, but it introduces one real Tablet information-parity regression and one bounded hierarchy defect that should be corrected before GREEN-DEV.

## Exact-head findings

### Scope / functional isolation — PASS

No DB/migration/RPC/service/RBAC/RLS/route-guard/business-calculation/query-cache/validation/deployment file is changed.

Preserved product/domain truth includes:
- `useActivities(queryParams)` still receives `typeCategory`, `outcomeType`, `dateFrom`, `dateTo`, `employeeId`, `customerId`, `page`, `pageSize: 25` from page-owned state;
- client-side text search remains immediate and still matches customer name, activity type name and outcome notes on the current server page;
- search/filter changes still reset `page` to 1;
- team-employee visibility remains `ACTIVITIES_READ_TEAM || ACTIVITIES_READ_ALL`;
- create remains `ACTIVITIES_CREATE`;
- delete eligibility remains `ACTIVITIES_UPDATE_OWN || ACTIVITIES_READ_TEAM || ACTIVITIES_READ_ALL`;
- deletion still delegates to `useSoftDeleteActivity().mutate(deleteTarget.id)` and backend time-window authority is not duplicated in UI code;
- detail/create routes remain `/activities/${activity.id}` and `/activities/new`;
- customer deep-link filtering still initializes from `customerId` and can be cleared;
- GPS remains read-only list metadata; no acquisition/verification semantics moved into presentation;
- `useActivityTypes()` invocation remains unchanged.

### P2-1 — Tablet information/capability parity regression — BLOCKING

**Locations:**
- `src/pages/activities/ActivitiesPage.tsx` — `renderActivityCards` summary projection;
- `src/components/activities/ActivityOverviewPresentation.tsx` — `ActivityCard` metadata.

On the exact Development baseline, Tablet (`769–1024px`) still received the DataTable composition because the legacy mobile-card switch occurred only at `<=768px`. That table showed `start_time` beneath the activity date whenever present.

The new Tablet card receives only `date`, `notes`, `gpsVerified` and `outcome`; `start_time` is not projected or rendered. Therefore the migration drops an existing operational datum specifically when Tablet moves from the table to cards.

This violates the North-Star responsive-composition rule that business meaning and available capability remain equivalent while device composition changes, and the requirement for deliberate Tablet information density.

**Minimum required fix:** preserve the existing start-time datum in Tablet card composition when `activity.start_time` exists, using the same existing formatting semantics and without changing any query/service/workflow/data contract. Add a focused authored regression assertion covering this Tablet parity risk.

### P2-2 — redundant category representation weakens card hierarchy — BLOCKING

**Location:** `src/components/activities/ActivityOverviewPresentation.tsx` — `ActivityCard` header.

The same categorical value is currently rendered twice in the same header:
- `.ds-activity-card__category` beneath the title; and
- neutral `Badge` beside the outcome status.

This can produce a hierarchy such as `زيارة متابعة` + `زيارة` + another `زيارة` badge. Category is correctly neutral metadata, but duplicate exposure adds noise and gives supporting metadata unnecessary visual weight.

This conflicts with the North-Star strong-hierarchy/progressive-disclosure bar.

**Minimum required fix:** expose category once in the card header/composition, preserving neutral categorical treatment and leaving the semantic outcome `StatusBadge` unchanged. Add/update the focused presentation contract so the duplicate does not return.

### Shared-system fit — otherwise PASS at source level

- One live `ResponsiveCollection<ActivityRow>` replaces the legacy duplicated table/mobile-card interaction path.
- Desktop keeps the dense DataTable management surface.
- Tablet intentionally becomes a two-column card composition; Mobile becomes one column.
- Outcome uses shared semantic `StatusBadge`; category remains neutral metadata.
- Page/domain code owns view/delete eligibility and callbacks; `resolveActionSet` owns device placement only.
- Mobile exposes one direct view action with delete overflow when permitted; Tablet exposes both eligible actions directly.
- Shared `Pagination` sits outside device renderers and remains caller-owned for page/query truth.
- Initial empty and filtered empty are distinct; authorized create remains available.
- Canonical Mobile `<=768px` / Tablet-through-`1024px` boundaries and card identity touch target are present.
- The former page-local inline style block is replaced with bounded Field CSS; the existing immediate filter semantics are intentionally retained instead of adopting a debounced shared FilterBar.

### Device / RTL / accessibility / state judgment

- **Desktop:** dense list content/actions remain intact, including date + optional start time; table overflow remains contained.
- **Tablet:** touch/action/card composition is directionally correct, but GREEN is blocked by the lost `start_time` datum.
- **Mobile:** one-column cards, touch-safe identity/actions, authorized create path and canonical overflow placement pass source review. Mobile did not previously expose start time in the legacy DataCard, so P2-1 is specifically a Tablet parity regression.
- **RTL/accessibility:** logical layout, Arabic labels, explicit filter/action accessible labels, native identity button and visible focus treatment are present.
- **States:** loading, initial-empty, filtered-empty, permission-projected create/delete and destructive confirmation are preserved. Broader query error/offline convergence remains program debt rather than a new regression.

No runtime visual PASS is claimed.

### Test Artifact Gate / evidence honesty

Focused authored artifacts cover responsive renderer selection, query/search preservation, permission/delete boundaries, semantic outcomes, action placement/callback delegation, paging visibility, canonical breakpoints/touch sizing and neutral GPS/category treatment.

Evidence remains **`TESTS_AUTHORED_NOT_EXECUTED`**. No approved environment executed tests/build/lint; no hosted CI/Actions or Vercel preview was used. No known real build/type failure is recorded. This is not an executed PASS claim.

The current artifacts do **not** yet protect the two QA findings above; the next HEAD should add bounded regression coverage for Tablet start-time parity and single category representation.

## Peer-state comparison / contradiction handling

The independent disposition above was formed first.

- **UI Production Engineer feature-head state:** fresh and aligned on scope/evidence but still explicitly marks the slice `IN_PROGRESS` with a post-correction exact-diff pass pending. It did not identify the Tablet time loss or duplicate category. No contradiction; the two QA findings remain blocking.
- **Product Design Director state on Development:** lifecycle-stale from the prior HR slice and contains no FIELD001 exact-head judgment. `WATCH`, not an additional blocker.
- **Integration state on Development:** correctly records HR002 merged and FIELD001 as the next slice; it has no exact-head FIELD001 merge decision yet. `WATCH`, not a contradiction.
- **PR review threads/comments before this review:** none.

No peer-state disagreement supersedes the independent findings. The active blockers are the exact-head source defects above.

## System-fit judgment

FIELD001 is moving EDARA in the correct direction: shared responsive collection, semantic status grammar, canonical action placement and a deliberate Tablet/Mobile collection are the right architecture. It is not yet GREEN because responsive migration cannot silently reduce Tablet operational information, and the card header should not duplicate categorical metadata.

Any new PR HEAD requires fresh exact-head QA.

### Cross-role handoff
- **To:** UI Production Engineer; Product Design Director for awareness; Development Integrator remains `NO_MERGE`.
- **What changed:** Design QA reviewed PR #42 exact HEAD `823c89d10201a8db68e7189803bd003c3fd9fd2f` and recorded `AGENT-REVIEW: BLOCKED` with two bounded P2 presentation findings.
- **Preserve:** every existing activity query/search/filter input and timing; team/create/delete permissions; delete RPC/mutation authority; routes/customer deep-link; GPS/device/workflow/validation/service/query-cache truth; one `ResponsiveCollection`; shared Pagination; semantic outcome status and shared action placement.
- **Need from implementation:** restore optional start-time information in the Tablet card composition; remove duplicate category exposure while keeping one neutral category representation; add focused authored regression protection; then request fresh exact-head QA.
- **Blocker level:** `P2 / BLOCKING`.
- **Baseline:** Development `def098978efbe796306f882014e69652f014efa6`; reviewed PR HEAD `823c89d10201a8db68e7189803bd003c3fd9fd2f`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`; `SOURCE_REVIEW_PASS` withheld; no executed build/test/lint/runtime/preview/release PASS claimed.
