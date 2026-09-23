# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-23 19:00 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-039`.
- Integrated product merge: `035558bb3e86026742d3658d7c1928ee75f09215` from PR #87.
- Exact Development HEAD before Product Design bounding: `d7ac8b8cf68a1cc4a15522c2f4fa0f7731197fa7`.
- Workstream bounding commit: `739beedd30526959276064d4a85b6f9afa8c5c0c`.
- Active slice: `DS2-REPORT-040 — Churn Risk responsive-detail empty-state convergence`.
- Current slice state: `READY — BOUNDED`.
- Active implementation PR: none at review/recheck time.
- Representative surface: `src/pages/reports/ChurnRiskPage.tsx` → `تفاصيل العملاء — مرتب: معرض للخطر أولاً` → `ResponsiveCollection` empty branch only.
- Current contradiction classification: `NONE`.

## Independent Product Design judgment

REPORT040 should converge the Churn Risk responsive-detail **empty branch only** onto the already-proven shared collection state grammar.

I formed this judgment from the current Development source before comparing peer conclusions. Churn Risk is already substantially aligned with V2: shared `MetricGrid + StatCard`, shared `ChartPanel`, shared V2 filter controls, and `ResponsiveCollection + Card + KeyValueList` for the customer detail collection. The remaining bounded inconsistency is a bespoke page-local `emptyState` wrapper that recreates padding, typography, color and alignment even though `ResponsiveCollection` already owns the generic empty-state path through `emptyTitle -> compact StatePanel kind="empty"`.

This is the smallest dependency-safe concern because it removes one duplicated state mini-system without touching business truth, chart semantics, risk classification, trust gating or responsive ready composition. It also extends the exact pattern just proven by REPORT039 rather than inventing a new abstraction.

I also inspected other representative remaining Reports surfaces before selection. `OverviewPage` still contains broader navigation-card/local-color debt, while `CustomerReengagementPage` contains much larger filter/drawer/output interaction debt. Those are real future concerns but materially broader and carry more interaction/semantic risk than this state-only slice, so they should not displace the safer REPORT040 boundary.

## REPORT040 bounded contract

### Scope / system intent

Only:
- remove the Churn Risk `ResponsiveCollection.emptyState` bespoke wrapper;
- pass the exact existing copy through `emptyTitle="لا توجد بيانات — شغّل watermark sweep أولاً"`;
- consume the existing built-in compact passive shared `StatePanel kind="empty"` without changing shared component contracts.

The page continues to own state precedence and business meaning. `ResponsiveCollection` continues to own generic loading/empty/ready orchestration and single-device ready-renderer selection.

### State hierarchy — must remain exact

Preserve:
- `isBlocked -> listLoading -> empty -> ready`;
- current BLOCKED renderer completely unchanged, including `بيانات الخطر محجوبة` and `snapshot_customer_risk يحتاج تشغيل ناجح أولاً`;
- exactly five `SkeletonCard height={44}` detail loading rows;
- empty mounts no Desktop table, Tablet cards or Mobile cards;
- ready state mounts no empty/loading state.

BLOCKED is deliberately outside the Design System convergence in this slice. It represents caller-owned trust/data semantics and must not be reinterpreted merely to make the page visually uniform.

### Device / hierarchy acceptance

Preserve:
- Desktop dense semantic six-column table;
- Tablet two-column `Card + KeyValueList` composition;
- Mobile one-column `Card + KeyValueList` composition;
- exactly one ready renderer per device through `ResponsiveCollection`;
- representative empty-state verification at 390 / 900 / 1440px with no ready-renderer leakage;
- customer name/fallback identity, row order and all six facts;
- long Arabic wrapping and LTR numeric/currency treatment;
- TrustStateBadge / FreshnessIndicator placement and meaning.

### Accessibility / interaction acceptance

The empty state remains passive:
- no action slot;
- no click handler;
- no button/link/focus target;
- no live announcement introduced for `kind="empty"`;
- no new keyboard/touch interaction.

### Explicit exclusions

Do not change:
- BLOCKED renderer/copy/trust meaning;
- `RiskBadge`, `RecencyCell`, `RISK_CONFIG`, risk classification or category semantics;
- KPI summary;
- pie chart visibility/data/colors/geometry/tooltip/legend;
- filter/date controls or SystemHealthBar;
- hooks, queries, cache behavior, sorting, calculations, formatting truth;
- permission/RBAC/RLS/routing/export/print/backend/business/workflow semantics;
- shared `ResponsiveCollection`, `StatePanel`, `ChartPanel`, `MetricGrid`, `StatCard`, CSS, tokens or breakpoints;
- any second report surface.

If implementation requires any excluded shared or functional change, REPORT040 becomes `BLOCKED` rather than widening.

## Focused evidence expectation

Update the existing `ChurnRiskPage.test.tsx` only as needed to protect the presentation risk:
- exact empty copy;
- shared `.ds-state-panel[data-state-kind="empty"]` anatomy;
- compact/passive semantics;
- BLOCKED higher priority than loading/empty/ready;
- loading higher priority than empty/ready with exactly 5×44px skeletons;
- no ready table/card renderer while empty at representative Mobile/Tablet/Desktop widths;
- existing ready-state and chart/filter/business assertions remain intact.

Under the current quota policy, authored tests may remain `TESTS_AUTHORED_NOT_EXECUTED` unless an approved execution environment actually runs them. No source review may be represented as build/test/runtime PASS.

## Peer-state synthesis / contradiction handling

After forming the independent judgment:

- **Team Memory:** current through REPORT039 and explicitly hands REPORT040 to Product Design for one smallest safe bounding; aligned.
- **Development Integrator:** current through REPORT039 merge and likewise delegates REPORT040 bounding; aligned.
- **UI Production Engineer:** implementation state is lifecycle-stale because it still records REPORT039 before merge; informative only, not contradictory.
- **Design QA:** QA state is lifecycle-stale because its REPORT039 exact-head approval was consumed by integration; informative only, not contradictory.
- **Previous Product Design state:** lifecycle-stale through REPORT039 exact-head review and superseded by this REPORT040 direction.
- **Decision Log / North Star / Component System / Migration Matrix / Device Strategy / QA Guardrails:** aligned with shared state-family consolidation, deliberate device composition and strict presentation-only ownership.
- **Open PRs targeting Development:** none at final recheck, so no competing implementation slice exists.

Current contradiction classification: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27 latest coordination events, exact Development HEAD and all open PRs targeting Development.
- Inspected relevant Component System, Migration Matrix, QA Guardrails, Device Strategy and Component Decision Matrix documents.
- Inspected representative remaining Reports source, including Churn Risk, Overview and Customer Re-engagement, plus current `ResponsiveCollection` / `StatePanel` contracts and focused Churn Risk tests.
- Bounded exactly one implementation slice and updated `31_AGENT_TEAM_WORKSTREAM.md` in commit `739beedd30526959276064d4a85b6f9afa8c5c0c`.
- Did not modify product code, peer role states, Team Memory or Decision Log.
- Did not merge, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after implementation reaches a stable exact PR HEAD.
- **What changed:** REPORT040 is now bounded and READY as the Churn Risk responsive-detail empty-state convergence only; no implementation PR existed at final recheck.
- **Preserve:** exact empty copy; `isBlocked -> listLoading -> empty -> ready`; unchanged BLOCKED copy/meaning; 5×44px detail loading; dense six-column Desktop table; Tablet two-column and Mobile one-column cards; one ready renderer per device; customer-risk facts/fallbacks; Arabic wrapping; LTR facts; Trust/Freshness; KPI/chart/filter contracts; all excluded shared/data/query/permission/backend/business semantics.
- **Need from you:** UI Production should start from the latest Development HEAD, implement only the bounded empty-state convergence, update focused tests, and open exactly one Draft PR targeting `design-system-v2-development`. If any shared-contract or functional-semantic widening is required, stop and mark the slice `BLOCKED`. Design QA should review only the future stable exact PR HEAD.
- **Blocker level:** `NONE`.
- **Baseline:** Product Design inspection baseline `d7ac8b8cf68a1cc4a15522c2f4fa0f7731197fa7`; workstream bounding commit `739beedd30526959276064d4a85b6f9afa8c5c0c`.
