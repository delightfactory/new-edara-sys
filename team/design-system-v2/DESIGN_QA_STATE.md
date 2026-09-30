# Design QA State

## Reviewed baseline

- Review date/time: `2026-09-30`.
- Development branch: `design-system-v2-development`.
- Exact Development HEAD / PR base before this QA-state write: `186db3679f08e00550959cedf64cddaf4af65ac2`.
- Active slice: `DS2-REPORT-051 — Churn Risk shared chart-tooltip adoption`.
- Representative surface: `src/pages/reports/ChurnRiskPage.tsx` → `توزيع تصنيف العملاء` Pie-chart tooltip.
- Active implementation PR: `#100 — DS2-REPORT-051: adopt shared Churn Risk chart tooltip`.
- Exact PR HEAD independently reviewed and rechecked before disposition: `8af587a2b6ecf03fde3903290d8bbfab3cf8b0a5`.
- Changed-file scope: exactly 3 files — Churn Risk page, focused Churn Risk test, and UI Production owned state.
- Current disposition: `AGENT-REVIEW: GREEN-DEV`.
- Evidence: `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- Executed build/test/lint/runtime/visual/preview/release PASS: not claimed.
- Current peer contradiction classification: `NONE`.

## Independent QA disposition

**GREEN-DEV on exact PR HEAD `8af587a2b6ecf03fde3903290d8bbfab3cf8b0a5`.**

REPORT051 is correctly bounded to one presentation-only adoption. Churn Risk retains Recharts payload interpretation, category/count/color/value-direction and every chart/trust/business contract while the already-proven shared `ChartTooltip` owns only neutral tooltip presentation/anatomy. The PR does not widen shared APIs/CSS/tokens/breakpoints or move domain/business truth into the Design System.

## Exact-head findings

### Scope / functional isolation — PASS

Exact PR scope:
- `src/pages/reports/ChurnRiskPage.tsx`
- `src/pages/reports/ChurnRiskPage.test.tsx`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md`

Product code:
- imports the existing shared `ChartTooltip`;
- introduces a local `CustomTooltip` adapter that preserves `!active || !payload?.length` gating;
- uses the caller category as tooltip heading;
- preserves the exact row label `عملاء`;
- preserves the existing `FMT` count formatter;
- passes through the caller Pie color and explicit `ltr` numeric direction;
- preserves Recharts `<Tooltip content={<CustomTooltip />} />` wiring;
- leaves shared `ChartTooltip` implementation/API/tests/CSS/tokens/breakpoints unchanged.

Preserved Churn Risk contracts remain source-visible:
- exact chart presence rule `!statsLoading && pieData.length > 0`;
- no loading or empty chart surface was added;
- exact `ResponsiveContainer width="100%" height={260}`;
- exact filtered Pie data/order and `dataKey="value"` / `nameKey="name"`;
- exact `cx="50%"`, `cy="50%"`, `innerRadius={60}`, `outerRadius={100}`, `paddingAngle={2}`;
- exact five caller colors `#f59e0b`, `#10b981`, `#3b82f6`, `#f97316`, `#ef4444`;
- existing `Legend`, ChartPanel title and Trust/Freshness action behavior;
- header filters, KPI summary, responsive customer detail collection/table/cards and state precedence are unchanged.

No DB/migration/RPC/service/query-cache/RBAC/RLS/permission/route/calculation/trust/validation/export/print/backend/workflow/business contract changed.

### System fit / device / RTL / accessibility — PASS at source level

- Reuse of shared `ChartTooltip` removes a remaining library-default/local presentation island without introducing a second tooltip grammar.
- Mobile 390 / Tablet 900 / Desktop 1440 use the same shared RTL tooltip presentation with no device-specific fork or breakpoint change.
- Long Arabic category content is kept within shared tooltip anatomy; no page-local truncation rule was introduced.
- Numeric count values are explicitly `dir="ltr"` while the shared tooltip remains RTL-native.
- Tooltip remains passive/informational: no action, focus target, tab stop, role, live region or keyboard/action contract was added.
- Caller-provided Pie colors remain chart-series/category identity and are not reclassified as Design System semantic statuses.
- No ordinary overflow source, hierarchy regression, state-semantic drift or page-local mini design system was introduced.

### Test Artifact Gate — PASS by source inspection

The stale Recharts `formatter`-based harness is removed and focused coverage now protects:
- inactive and empty-payload adapter guards;
- exact category heading, one-row `عملاء` label, existing count formatting and caller color;
- browser/CSSOM-normalized `#f59e0b -> rgb(245, 158, 11)`;
- explicit LTR numeric value direction;
- long Arabic / RTL / passive anatomy;
- shared-tooltip adoption at representative 390 / 900 / 1440 widths;
- no chart/tooltip leakage while stats are loading or every Pie value is zero;
- exact 260px responsive geometry;
- preserved filtered Pie data/order, keys, center/radii/padding, exact five colors, shared tooltip wiring and Legend.

The color assertion is consistent with the established shared `ChartTooltip.test.tsx` CSSOM representation.

Tests/build/lint were **not executed** in an approved exact-head project runtime. Evidence is therefore `TESTS_AUTHORED_NOT_EXECUTED`; no executed Build/Test/Lint/Runtime/Visual/Preview/Release PASS is claimed. Exact-head combined commit status contains zero statuses, which is expected under the hosted-CI quota freeze and is not itself a blocker.

## Peer-state comparison / contradiction handling

This QA judgment was formed from the exact PR diff/source/tests, current Churn Risk contracts, shared `ChartTooltip` implementation/test contract, current issue #27 handoff and PR discussion state before peer conclusions were used as corroboration.

- **Product Design Director:** direction is aligned and materially fresh for REPORT051; it explicitly bounded the same Churn Risk Pie tooltip adoption, unchanged shared contract, 260px geometry, exact colors, guard/RTL/device expectations and test coverage.
- **UI Production Engineer:** Development-branch role state is lifecycle-stale from REPORT050, but the PR-carried owned-state update is fresh and aligned with the exact REPORT051 implementation/evidence.
- **Development Integrator:** state is stale/superseded; it records the earlier no-PR/repository-write blocker. PR #100 now exists, the product/test implementation is present, and the current PR base is identical to current Development. The stale blocker is not a current contradiction.
- **Team Memory / Workstream:** current REPORT051 boundary and system invariants are aligned; lifecycle text that anticipated future implementation is superseded by the current PR.
- **Prior Design QA state:** lifecycle-stale from integrated REPORT050 and superseded by this review.
- **PR discussion/reviews/threads before QA disposition:** no prior PR comment, submitted review or inline blocker existed.

Current contradiction classification: **NONE**. Fresh Product Design exact-head closeout remains a separate integration prerequisite, not a QA blocker.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, current Development truth, exact PR #100 metadata/base/head, full three-file patch, exact-head Churn Risk source/test, shared `ChartTooltip` source/test and current PR discussion.
- Confirmed current Development is identical to PR base `186db3679f08e00550959cedf64cddaf4af65ac2`.
- Reconfirmed immediately before disposition that PR #100 remained `OPEN / DRAFT / mergeable=true` on exact HEAD `8af587a2b6ecf03fde3903290d8bbfab3cf8b0a5`.
- Left `AGENT-REVIEW: GREEN-DEV` anchored to that exact HEAD with `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- Updated only this owned Design QA state file; peer states, Team Memory and Decision Log were not modified.
- Did not modify product code, merge, deploy, touch `main`, trigger/rerun GitHub Actions, use hosted CI or modify preview branches.

## What changed since the previous state

- Design QA lifecycle advanced from integrated REPORT050 to active REPORT051.
- PR #100 exact HEAD `8af587a2b6ecf03fde3903290d8bbfab3cf8b0a5` received fresh independent exact-head QA review.
- The previous REPORT051 no-PR/tooling blocker recorded by Integration is superseded by the actual Draft PR and exact implementation/test evidence.
- REPORT051 has no Design QA blocker and is now `GREEN-DEV`, pending independent Product Design exact-head closeout and later Integrator revalidation.

### Cross-role handoff
- **To:** Product Design Director for exact-head closeout; then Development Integrator after all same-head gates are current.
- **What changed:** REPORT051 now has exact-head `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS` on `8af587a2b6ecf03fde3903290d8bbfab3cf8b0a5`.
- **Preserve:** shared `ChartTooltip` API/CSS/tokens/breakpoints unchanged; caller-owned active/payload guard, category heading, exact `عملاء` label, existing `FMT` count formatting, Pie color and LTR numeric direction; exact ready-only chart presence, 260px geometry, Pie data/order/keys/radii/padding/colors, Legend and Trust/Freshness; all header/KPI/detail/query/permission/backend/business contracts.
- **Need from you:** Product Design should independently accept or block this same exact HEAD. Integrator should act only after that same-head closeout, no new blocker and normal base-drift/mergeability/review-thread revalidation.
- **Blocker level:** `NONE` from Design QA.
- **Baseline:** Development / PR base `186db3679f08e00550959cedf64cddaf4af65ac2`; exact reviewed PR #100 HEAD `8af587a2b6ecf03fde3903290d8bbfab3cf8b0a5`.
- **Evidence:** `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`; no executed build/test/lint/runtime/visual/preview/release PASS claimed.
