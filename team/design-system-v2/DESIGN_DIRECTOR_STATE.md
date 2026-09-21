# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-21`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before REPORT016 governance writes: `0598553517f0e9ee37f55a85c62d8fba4a189070`.
- Latest integrated product baseline: `DS2-REPORT-015` / PR #63, squash merge `fae25c2962f01aefc988b3e3ec8e0532e1c491f8`.
- Product Design boundary commit written before this owned-state update: `cc3551e8c6342bc2aa957e706cd4697db1b66d8b`.
- Open implementation PRs targeting Development at inspection time: none.
- Active single READY slice: `DS2-REPORT-016 — Rep Performance responsive detail-collection convergence`.
- Representative surface: `src/pages/reports/RepPerformancePage.tsx` → `تفصيل الأداء — جميع المندوبين` collection only.
- Implementation PR: none yet.
- Product Design disposition: `READY — BOUNDED / UI PRODUCTION MAY IMPLEMENT ONE SLICE`.
- Exact-head build/test/lint/runtime/preview/release PASS: not claimed or required at this design-bounding stage.

## Independent Product Design judgment

**READY — REPORT016 is bounded to one presentation-only Rep Performance collection concern.**

I independently inspected the latest Development baseline and representative remaining Reports surfaces before comparing peer role states. `RepPerformancePage.tsx` contains a particularly clean next system gap: REPORT014 already converged its comparison chart to shared `ChartPanel`, but the adjacent `تفصيل الأداء — جميع المندوبين` section still presents a wide Desktop table with ordinary horizontal overflow on smaller devices.

This is a better next slice than opening a new chart-only migration or a multi-concern legacy report page because:
- the system already has a proven `ResponsiveCollection + Card + KeyValueList` grammar across Product Performance, Customer Health, Churn Risk and Geography;
- the Rep Performance row already exposes all facts required for compact device composition, so no data/query/business widening is needed;
- Desktop comparison density remains valuable and should be preserved rather than replaced;
- Tablet/Mobile currently inherit an avoidable wide-table experience, which is directly contrary to the Mobile/Tablet device strategy;
- the neighboring REPORT014 chart can remain untouched, making the slice dependency-safe and independently reviewable.

I also inspected `TargetAttainmentPage.tsx` and `TreasuryPage.tsx`. Both have legitimate future convergence debt, but Target Attainment combines raw controls, chart-shell and wide-table concerns, while Treasury is mainly another already-proven chart-shell candidate. Neither is a better smallest next system step than completing Rep Performance's responsive detail collection.

## REPORT016 exact design boundary

### System intent

Converge only the Rep Performance detail collection onto the established responsive collection grammar while preserving the existing caller-owned ranking and performance truth.

The slice must reduce local device fragmentation, not redesign the page.

### Data / business truth to preserve

Preserve exactly:
- `useRepPerformanceTable(filters)` and existing row order;
- `rank`;
- `rep_name`;
- `branch_name`;
- `net_revenue`;
- `returns_value`;
- `return_rate_pct`;
- `distinct_customers`;
- all existing formatting and ranking/calculation semantics.

No new labels may reinterpret business ranking, and no data may be dropped on compact devices.

### Desktop acceptance

Desktop keeps one dense semantic seven-column table in the existing order:
1. `#`
2. `المندوب`
3. `الفرع`
4. `صافى الإيراد`
5. `المرتجعات`
6. `نسبة المرتجع`
7. `عملاء`

Preserve current row density, row hover, first-row success emphasis, last-row danger emphasis, positive-return danger tone, muted zero-return tone, and exact return-rate thresholds (`>10` danger, `>5` warning, otherwise success).

Add semantic `scope="col"` to table headers. Do not otherwise redesign the Desktop table.

### Tablet acceptance

Tablet uses the existing shared `ResponsiveCollection` with a deliberate two-column `Card + KeyValueList` renderer.

Every Desktop row fact remains visible. `rep_name` is the primary identity; rank and branch remain visible context. The current first/last ranking emphasis may remain on relevant rank/identity text, but must not become a colored whole-card treatment or a newly invented business status.

### Mobile acceptance

Mobile uses the same shared grammar with one-column `Card + KeyValueList` composition and no ordinary horizontal table scrolling.

Every row fact remains visible. Long Arabic representative and branch names must wrap safely. Compact cards remain passive information surfaces with no fabricated navigation or click semantics.

### RTL / numeric direction / accessibility / dark mode

- Arabic identity/context remains RTL-first and wrap-safe.
- Rank, currency, percentage and customer-count values retain intentional LTR presentation where appropriate.
- Compact renderers inherit `dl/dt/dd` semantics from `KeyValueList`.
- Generic Cards remain non-interactive; no keyboard/focus contract is invented.
- Explicit numeric/text values remain visible, so existing semantic tones are never the sole information carrier.
- Reuse existing semantic Card/KeyValueList surfaces and tokens for dark mode; no new page-local palette.
- Exactly one device renderer mounts through `ResponsiveCollection`; no CSS-hidden duplicate table/card tree.

### State acceptance

Preserve exact state precedence and content:
- loading before ready composition;
- exactly five `SkeletonCard height={44}` rows;
- exact empty copy `لا توجد بيانات فى النطاق الزمني المحدد`;
- neither loading nor empty state mounts a ready device renderer.

### Explicit exclusions

Do not modify:
- the REPORT014 `ChartPanel` or its title/description/trust/freshness/chart body;
- chart top-15 mapping, axes, tooltip, series or dynamic height;
- KPIs or summary calculation;
- `ReportFilterBar` / date range;
- `SystemHealthBar` or trust lookup;
- `CustomTooltip`;
- hooks, queries, cache semantics, rankings or calculations;
- permissions/RBAC/RLS, routing, backend contracts, validation, export/print or business workflow;
- shared component APIs, CSS or tokens.

If the implementation discovers that a shared API/CSS change or functional semantic change is required, REPORT016 becomes `BLOCKED` and returns the exact gap to Product Design rather than widening the PR.

### Focused test expectations

Preserve all existing REPORT014 chart-panel tests and add focused REPORT016 coverage for:
- Desktop/Tablet/Mobile single-renderer behavior;
- all seven row facts and row/rank ordering;
- first/last identity emphasis and current returns/return-rate tone thresholds;
- long Arabic rep/branch wrapping;
- LTR numeric/currency/percentage presentation;
- Desktop `scope="col"` headers;
- exact five × 44px loading state and exact empty copy/precedence.

Evidence remains `TESTS_AUTHORED_NOT_EXECUTED` unless an approved runtime actually executes the tests. Hosted GitHub Actions remain forbidden.

## Peer-state synthesis / contradiction status

This design judgment was formed independently first, then compared with shared memory and peer states.

- **Team Memory:** current and aligned; explicitly hands REPORT016 to Product Design for exact bounding after REPORT015 integration.
- **Development Integrator:** current and aligned; REPORT015 is merged and REPORT016 is `READY_FOR_PRODUCT_DESIGN_BOUNDING`.
- **UI Production:** lifecycle-stale at REPORT015, as expected after integration; it contains no contradictory current implementation claim.
- **Design QA:** lifecycle-stale at REPORT015, as expected; fresh exact-head review will be required only after a REPORT016 implementation PR exists.
- **Prior Design Director state:** lifecycle-stale after REPORT015 merge and superseded by this state.
- **Decision Log / North Star / device and component guidance:** aligned with shared-system reuse, one renderer per device, Arabic-first composition and UI-only functional isolation.

Current contradiction classification: **NONE**.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, exact latest Development HEAD, open PRs targeting Development, Reports page inventory, current Rep Performance source/test surface, representative Target Attainment and Treasury alternatives, `ResponsiveCollection`, `Card`, `KeyValueList`, device strategy and component decision guidance.
- Confirmed there was no active implementation PR before bounding a new slice.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` to make REPORT016 one exact READY implementation concern.
- Updated only this owned specialist state file; did not overwrite peer states.
- Did not update Team Memory because the overall system direction did not change; this is a bounded continuation of the existing Reports roadmap.
- Did not update Decision Log because no durable rule changed.
- Did not modify product code, merge any PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after implementation PR opens.
- **What changed:** REPORT016 is now exactly bounded as the Rep Performance `تفصيل الأداء — جميع المندوبين` responsive detail-collection convergence and is READY for one implementation PR.
- **Preserve:** REPORT014 chart untouched; exact seven Rep Performance facts/order/ranking and existing tone thresholds; Desktop dense table; Tablet two-column and Mobile one-column shared Card/KeyValueList composition; one renderer per device; exact five × 44px loading state and exact empty copy; Arabic wrapping/LTR numeric direction; unchanged shared APIs/CSS and all query/calculation/trust/permission/routing/export/print/business semantics.
- **Need from you:** start from the latest `design-system-v2-development` HEAD, implement REPORT016 only, author focused device/state/semantic tests, open one Draft PR targeting Development, and hand the exact stable PR HEAD to Design QA and Product Design. If shared-contract or functional widening is required, stop and mark the slice BLOCKED instead.
- **Blocker level:** `NONE`.
- **Baseline:** product/source baseline inspected `0598553517f0e9ee37f55a85c62d8fba4a189070`; Product Design boundary commit before this state write `cc3551e8c6342bc2aa957e706cd4697db1b66d8b`.
