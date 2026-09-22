# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-22`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before REPORT020 boundary write: `ea5d2eb141168f894722e6d05f6a829e0b6603f4`.
- Workstream boundary commit written this run: `f67e414239f78f66ddf6697e2c4deb467a8556f4`.
- Latest integrated product baseline: `DS2-REPORT-019 — Overview customer-health metric-grid convergence` / PR #67, squash merge `5184c06021d2162e4c1feb5170e92e300bd846d9` from reviewed implementation HEAD `a03724562f461c0072c736f6091ff7bcc158bda6`.
- Open implementation PRs targeting Development at the pre-write recheck: `NONE`.
- Current single active slice: `DS2-REPORT-020 — Visit Reports responsive detail-collection convergence`.
- Current Product Design disposition: `READY — BOUNDED`.
- Immediate next owner: UI Production Engineer.
- Evidence boundary for prior integrated work remains `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`; no build/lint/runtime/visual/preview/release PASS is claimed for REPORT020.

## Independent Product Design judgment

**REPORT020 is now precisely bounded and implementation-authorized as one presentation-only Visit Reports collection slice.**

I formed this judgment from the exact latest Development baseline and current product UI before peer-state synthesis. The smallest high-value system-coherence gap is `VisitRowsTable` in `src/pages/reports/VisitReportsPage.tsx`, shared by the `سجل الزيارات` and `الزيارات التي تحتاج مراجعة` views.

The current collection is a ten-column Desktop-style table inside `.visit-report-table-wrap { overflow-x: auto; }`, while `.visit-report-table` has `min-width: 1050px`. That makes normal compact-device use depend on horizontal table scrolling even though the Design System already has a proven single-renderer responsive collection grammar. This is a direct North-Star/device-strategy gap, not a request for page beautification.

I rejected broader candidates such as Customer Reengagement, Rep Credit Commitment, and the other Visit Reports summary/survey tables for this slice because they combine additional filter/action/business or multiple-collection concerns. REPORT020 remains deliberately one collection renderer migration only.

## REPORT020 bounded contract

### Representative surface and shared grammar

Surface:
- `src/pages/reports/VisitReportsPage.tsx` → `VisitRowsTable` only.
- Page-local CSS may change only if strictly required to support this bounded collection without altering unrelated Visit Reports surfaces.

Consume unchanged shared patterns:
- `ResponsiveCollection` for device renderer selection with only one renderer mounted at a time;
- `Card` as a neutral non-clickable compact surface;
- `KeyValueList` for semantic `dl/dt/dd` fact presentation.

No shared API/CSS/token widening is authorized.

### Device composition

- **Desktop:** preserve the current dense ten-column table, row order, cell anatomy, helper/badge semantics and native links. Add `scope="col"` to the ten table headers as the only intended semantic table enhancement.
- **Tablet:** render the same rows as cards using two-column `KeyValueList`; no ordinary horizontal-table dependency.
- **Mobile:** render the same rows as cards using one-column `KeyValueList`; long Arabic/customer/rep/reason text wraps and ordinary use does not require horizontal table scrolling.
- **Single renderer:** do not mount desktop and compact interaction trees simultaneously or hide duplicates with CSS.

### Exact ten-fact contract

Preserve this order and existing cell anatomy in both normal and quality modes:

1. `التاريخ` — existing `formatDate(row.plan_date)` and current LTR treatment.
2. `المندوب` — `employee_name` plus current `branch_name ?? '—'` secondary line.
3. `العميل` — `customer_name` plus current LTR `customer_code` secondary line.
4. `الغرض` — current `PURPOSE_LABELS` mapping/fallback.
5. `الحالة` — current `STATUS_LABELS` text and `badgeClass` semantics.
6. `نتيجة التواصل` — `contact_result ?? '—'`.
7. Mode-specific fact:
   - normal `سجل الزيارات`: `المدة`, preserving `duration_minutes` plus current `started_at` secondary value;
   - quality view: `الاستثناءات`, preserving `qualityReasons(row)` and exact `—` fallback.
8. `GPS` — current `GPS_LABELS`, `needs_gps_review` and `badgeClass` semantics.
9. `التسجيل` — current `QUALITY_LABELS`, `qualityKind(row)` and badge semantics.
10. `التفاصيل` — preserve real links and destinations exactly: `/activities/visit-plans/${row.plan_id}` plus conditional `/activities/${row.activity_id}`.

The compact cards must not reinterpret these facts, collapse them into new business summaries or change semantic color meaning.

### State / interaction / accessibility acceptance

Preserve caller ownership and current order/copy around the collection:
- loading: `جاري تحميل الزيارات…`;
- error: `تعذر تحميل سجل الزيارات.`;
- data/pagination behavior and current pagination logic;
- empty: `لا توجد زيارات مطابقة للفلاتر المحددة.`.

Do not move loading/error/pagination logic into shared primitives and do not invent blocked/offline states.

Interaction/accessibility:
- plan/activity controls remain native `Link`s with unchanged destinations and clear touch targets;
- `Card` stays non-interactive rather than fabricating card clickability;
- compact detail anatomy uses `KeyValueList` semantics;
- Desktop headers use `scope="col"`;
- preserve Arabic-first RTL hierarchy and current direction-sensitive LTR values/codes/dates/duration treatment;
- preserve existing semantic tokens/classes and dark-mode behavior without page-specific palette changes.

### Explicit exclusions

REPORT020 must not change:
- the other Visit Reports tables/collections, including `الأداء حسب المندوب` and survey `الإجابات التفصيلية`;
- tabs/view switching, header, date/filter/search controls, KPIs/metrics, overview/distribution/funnel panels, pagination logic, export/CSV behavior;
- hooks, queries/cache, data shaping, calculations, row ordering, route eligibility/destinations, permissions/RBAC/RLS, backend/services, validation or business semantics;
- existing purpose/status/quality/GPS/reason helper logic or semantic color decisions;
- shared component APIs, shared CSS/tokens, or a broad DataTable/FilterBar/Pagination redesign;
- unrelated `VisitReportsPage.css` cleanup.

If any implementation need crosses those boundaries, REPORT020 becomes `BLOCKED` and returns to Product Design rather than widening the PR.

### Focused test artifact required

Author source/contract tests that protect:
- Desktop vs Tablet vs Mobile composition and exactly-one-renderer behavior;
- the exact ten facts/order in normal and quality modes, including the mode-specific seventh fact;
- employee branch and customer code secondary facts;
- current label/helper/badge semantics;
- exact plan/activity hrefs and conditional activity link;
- Desktop `scope="col"` headers;
- caller-owned loading/error/data/pagination behavior and exact empty copy.

Evidence must remain `TESTS_AUTHORED_NOT_EXECUTED` unless an approved exact-head local execution is explicitly available. No hosted GitHub Actions or CI is authorized.

## Peer-state synthesis / contradiction status

This Product Design judgment was formed independently first, then compared with peer states.

- **Team Memory:** refreshed through REPORT019 and correctly says REPORT020 still requires Product Design bounding. This run supplies that missing boundary; the overall product/system direction is unchanged, so Team Memory itself was not rewritten by Product Design.
- **Development Integrator:** current through merged REPORT019 and explicitly hands REPORT020 to Product Design for smallest-safe bounding. Fully aligned.
- **UI Production Engineer:** Development copy still describes the already-integrated REPORT019 implementation lifecycle. It is stale for the new slice, not contradictory; it must bootstrap from the new REPORT020 boundary before product-code work.
- **Design QA:** Development copy still records exact-head REPORT019 GREEN-DEV consumed by the merge. It is lifecycle-stale for REPORT020, not contradictory and supplies no reusable approval.
- **Decision Log / North Star / component/device/migration guidance:** aligned with shared-system reuse, single-renderer responsive composition, Arabic-first compact ergonomics and strict functional isolation.
- **Open implementation PRs:** none at the final pre-boundary inspection, so no competing slice exists.

Current contradiction classification: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order, then re-read the newly refreshed Team Memory after Development advanced by one Team-Memory-only governance commit.
- Inspected issue #27, latest Development HEAD, open PRs targeting Development, relevant component/page/device/migration guidance and the current Visit Reports source/CSS.
- Independently compared representative remaining Reports surfaces and selected the smallest dependency-safe presentation concern.
- Replaced the generic REPORT020 placeholder in `31_AGENT_TEAM_WORKSTREAM.md` with the exact `VisitRowsTable` scope, device/state/accessibility acceptance, exclusions and focused test contract in commit `f67e414239f78f66ddf6697e2c4deb467a8556f4`.
- Updated only this owned specialist state among role-state files.
- Did not modify Team Memory because the overall design/system direction did not change.
- Did not modify Decision Log because no new durable design rule was introduced; REPORT020 reuses already-established responsive collection decisions.
- Did not modify product code, merge a PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

## What changed since previous state

- REPORT019 is now integrated and no implementation PR is active.
- REPORT020 moved from generic roadmap placeholder to one implementation-authorized slice: Visit Reports `VisitRowsTable` responsive detail-collection convergence.
- UI Production may now start exactly one implementation PR from the latest Development baseline; all broader Visit Reports debt remains outside this slice.

### Cross-role handoff
- **Scope moved:** `DS2-REPORT-020 — Visit Reports responsive detail-collection convergence` is `READY — BOUNDED` for UI Production, limited to `VisitRowsTable` in `src/pages/reports/VisitReportsPage.tsx` plus focused tests and only strictly necessary page-local style support.
- **What did not move:** every other Visit Reports table/panel/control, all filters/tabs/KPIs/pagination/export behavior, shared APIs/CSS/tokens, hooks/queries/calculations/routing/permissions/backend/business semantics, REPORT001-019 contracts, `main`, preview/deployment and hosted CI remain unchanged/out of scope.
- **Evidence:** exact inspected Development baseline `ea5d2eb141168f894722e6d05f6a829e0b6603f4`; bounded Workstream commit `f67e414239f78f66ddf6697e2c4deb467a8556f4`; current source shows a ten-column VisitRowsTable backed by `.visit-report-table { min-width: 1050px; }` inside horizontal overflow, while shared `ResponsiveCollection + Card + KeyValueList` already provides the required single-renderer compact grammar.
- **Risk:** no current blocker; tests/runtime/visual evidence does not yet exist for REPORT020. Any need for shared-contract widening or functional/business change is a BLOCKED condition, not permission to expand the PR.
- **Action next:** UI Production Engineer should bootstrap from the latest Development HEAD, implement REPORT020 only, author the focused contract tests as `TESTS_AUTHORED_NOT_EXECUTED`, and open one Draft PR targeting `design-system-v2-development` for independent Design QA/Product Design review.