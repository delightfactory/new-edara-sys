# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-23 06:02 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before REPORT033 bounding: `f9688fb8414d82e9eec2be67b2cb3a2ae0c64dd1`.
- REPORT032 is integrated via PR #80 / squash `e7088ed6d683b4cc714059cd7f3d07831f9485b5`; no implementation PR was open against Development at REPORT033 selection time.
- Active READY slice: `DS2-REPORT-033 — Target Attainment individual-rep chart-panel convergence`.
- Representative surface: `src/pages/reports/TargetAttainmentPage.tsx` → `نسبة الإنجاز — المندوبون الفرديون` chart shell only.
- Product Design disposition: `READY — BOUNDED`.
- Workstream bounding commit: `b0ed41ed54151ee38248dcf8c63a1431411b21b2`.

## Independent Product Design judgment

**REPORT033 should retire the remaining page-local Target Attainment analytical chart shell onto the existing shared `ChartPanel` composition, without touching the chart itself or widening any shared contract.**

The exact Development source already uses the shared responsive collection grammar for Target Attainment details, but the individual-rep achievement chart still builds its own surface with inline background, border, radius, padding, shadow and a page-local title/action header. This is a clean system-level gap because `ChartPanel` already owns exactly that neutral analytical responsibility through `Card + SectionHeader`, while explicitly leaving chart data, visualization semantics, trust/freshness and business truth to the caller.

The migration should therefore be structural rather than cosmetic: replace only the local chart frame/header with `ChartPanel`, keep the existing conditional presence and Recharts tree intact, and reuse the existing title, explanatory copy and Trust/Freshness action. No new chart abstraction, color contract, tooltip contract or shared API is justified by this slice.

## REPORT033 acceptance boundary

Implementation is authorized only for the Target Attainment individual-rep chart shell.

Preserve exactly:
- the existing `chartData.length > 0` visibility condition;
- title `نسبة الإنجاز — المندوبون الفرديون`;
- explanatory copy `الخط المنقط عند 100% هو الهدف`;
- `TrustStateBadge` + `FreshnessIndicator` conditional action content and all current status/domain/timestamp/staleness wiring;
- `ResponsiveContainer width="100%"` and `height={Math.max(chartData.length * 40, 200)}`;
- the vertical `BarChart`, `chartData` order, axes, tooltip formatter, `ReferenceLine x={100}`, `Bar` radius/max size and per-row `Cell` fill from `barColor`;
- existing percentage formatting and all target-attainment calculation/status meaning.

Shared presentation contract:
- consume existing `ChartPanel` unchanged;
- map the current chart title to `title`, the current 100% explanation to `description`, and the existing Trust/Freshness cluster to `action`;
- Desktop/Tablet/Mobile inherit the shared ChartPanel neutral card surface, semantic section hierarchy and heading/action wrapping;
- Arabic-first title/description wrapping must remain safe and the percentage chart keeps its existing numeric presentation;
- the chart remains a data visualization, not a new interactive card/action surface.

## Explicit exclusions / stop boundary

REPORT033 must not change:
- Target Attainment header scope/date controls or their state/query wiring;
- the four KPI summary cards or current `report-grid` wrapper;
- `تفاصيل الأهداف` ResponsiveCollection/Desktop table/Tablet-Mobile cards, TrendBadge or detail-state handling;
- `individualRows`, `chartData`, `achievementColor`, `barColor`, formatting functions, target calculations, trend/status classification or Trust/Freshness semantics;
- shared `ChartPanel`, `Card`, `SectionHeader`, CSS, token or breakpoint APIs;
- hooks, queries/cache, RBAC/RLS/permissions, routing, export/print, backend, business/workflow semantics or any other report surface.

If implementation needs any excluded shared or functional change, REPORT033 becomes `BLOCKED` rather than broadening the PR.

## Device / state / accessibility acceptance

- Desktop, Tablet and Mobile use the existing shared ChartPanel hierarchy; no duplicate device renderer is introduced.
- The panel must tolerate long Arabic title/description text and the existing Trust/Freshness action without ordinary horizontal overflow.
- Chart visibility remains data-driven exactly as today: no individual-rep chart data means no chart panel.
- Visible title/description remain semantic through ChartPanel/SectionHeader; Trust/Freshness accessibility semantics remain owned by their existing components.
- No pseudo-button semantics, new focus target, hover-only meaning, destructive state, permission state, offline state or workflow state is introduced.

## Focused validation expectation

Focused Target Attainment coverage should guard the material migration risk:
- shared `.ds-chart-panel` is present when individual-rep chart data exists and absent when it does not;
- exact title and description remain visible;
- existing Trust/Freshness action content remains associated with the shared panel header with unchanged inputs;
- individual-rep chart data/order and the 100% reference-line semantics remain unchanged;
- no local replacement chart-shell styling or excluded Target Attainment surface change is introduced.

Under the current quota policy, authored coverage remains `TESTS_AUTHORED_NOT_EXECUTED` unless an approved execution environment actually runs it. No build/test/lint/runtime/preview/release PASS is implied by this Product Design direction.

## Peer-state synthesis

I formed the direction from the exact Development source and the existing `ChartPanel` contract first, then compared current team memory and peer states.

- **Development Integrator:** fresh and aligned; REPORT032 is merged and it handed exactly one REPORT033 placeholder to Product Design for bounding.
- **Team Memory:** fresh through REPORT032 and intentionally still describes REPORT033 at roadmap-placeholder level. This run does not alter durable system direction, so Team Memory is not rewritten for routine slice bounding; the Workstream and this owned state now carry the exact REPORT033 boundary.
- **UI Production Engineer:** REPORT032 lifecycle is consumed by integration and there is no active competing implementation PR.
- **Design QA:** REPORT032 exact-head approval is consumed by integration; no REPORT033 approval or contradiction exists yet.
- **Decision Log / North Star / component blueprint:** aligned with shared-system-before-local-invention, Arabic-first responsive composition and strict functional isolation.

Current contradiction classification: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, the current Development HEAD, PR #80 and current open PRs targeting Development, relevant Reports/component/device/migration docs, and representative remaining report sources.
- Observed REPORT032 integration complete and confirmed zero open implementation PRs targeting `design-system-v2-development` before REPORT033 selection.
- Independently compared remaining Reports debt and selected one smallest dependency-safe chart-composition concern rather than broad page beautification or shared-contract widening.
- Bounded REPORT033 in Workstream commit `b0ed41ed54151ee38248dcf8c63a1431411b21b2`.
- Did not change Team Memory or Decision Log because no durable/overall design-system rule changed.
- Did not modify product code, merge, deploy, touch `main`, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after one REPORT033 PR reaches stable REVIEW.
- **What changed:** REPORT033 is now `READY — BOUNDED` to the Target Attainment individual-rep chart shell only, replacing its page-local analytical frame/header with existing `ChartPanel` while leaving the Recharts visualization and domain truth untouched.
- **Preserve:** exact chart visibility condition/title/description/Trust-Freshness action; chart data/order/height/axes/tooltip/100% ReferenceLine/bar colors and thresholds; header controls, KPI summary, detail collection and all query/calculation/permission/backend/business semantics; shared ChartPanel/Card/SectionHeader APIs, CSS, tokens and breakpoints.
- **Need from you:** UI Production should start from the exact latest Development HEAD after this governance write, implement only REPORT033, add focused tests for shared ChartPanel adoption plus preserved visibility/title/description/action/reference semantics, and open one PR targeting `design-system-v2-development`; mark BLOCKED rather than widen scope if a shared or functional change proves necessary.
- **Blocker level:** `NONE`.
- **Baseline:** Product Design selection baseline `f9688fb8414d82e9eec2be67b2cb3a2ae0c64dd1`; Workstream bounding commit `b0ed41ed54151ee38248dcf8c63a1431411b21b2`.
