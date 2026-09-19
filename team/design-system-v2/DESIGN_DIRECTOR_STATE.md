# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-19`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before REPORT007 selection: `14dc8d3947b4a39ce4a8c9dc11c6b4d9712bc98d`.
- Development HEAD after the Workstream boundary write and before this owned-state write: `3b9a51f9c93a4e015f51e04291833b68bac1bc7f`.
- Product UI is integrated through `DS2-REPORT-006` / PR #53 / product merge `ffda5aeb23684ea981c341761d1dde2cef7c3283`.
- Open implementation PRs targeting Development at selection time: `0`.
- Active single READY slice: `DS2-REPORT-007 — Geography analysis-level selector convergence`.
- Representative surface: `src/pages/reports/GeographyPage.tsx`, header control that selects `GeoLevel`.
- Current Product Design disposition: `READY — BOUNDED / IMPLEMENTATION AUTHORIZED WITHIN EXACT SCOPE`.
- Exact-head build/test/lint/runtime/preview/release PASS: not claimed.

## What changed since the previous state

REPORT006 is now merged and its Product Design acceptance has been consumed by Integration. The queue advanced one slot to REPORT007 with no implementation PR active.

This run independently inspected the remaining Reports surfaces and existing V2 component contracts, then converted the generic REPORT007 placeholder into one concrete, dependency-safe implementation boundary. The Workstream now authorizes only the Geography analysis-level selector convergence.

## Independent Product Design judgment

**REPORT007 should converge the Geography analysis-level selector onto the existing shared V2 `Select -> Field` contract, and nothing else.**

The current Geography report still creates the `GeoLevel` control as a raw `<select>` with page-local inline padding, radius, border, surface, typography and focus behavior. That is a direct system-coherence gap: the V2 component system already defines `Select` as a primitive/form composite path, the Component Decision Matrix explicitly directs `Input / Select` into the Field system, and the shared `Select` already composes `Field` while preserving native select semantics.

This is the smallest useful next slice because it removes a genuine local primitive rather than cosmetically restyling a page. It advances Reports filter/control grammar, shared control sizing, focus, dark-mode and accessibility behavior without introducing a new abstraction or touching analytics semantics.

I also inspected representative remaining chart/table debt (`ReceivablesPage`, `RepPerformancePage`, Geography's table). Those remain valid later convergence targets, but widening REPORT007 to a chart/table or a broader FilterBar redesign would combine independent concerns. The raw Geography selector is the narrower dependency-safe boundary now.

## REPORT007 exact boundary

### In scope

- `src/pages/reports/GeographyPage.tsx` only, plus focused test coverage and UI Production's owned state.
- Replace only the raw `<select>` that edits `level` with the existing shared V2 `Select` from `src/components/ui/Select.tsx`.
- Preserve controlled state ownership in `GeographyPage`: `level` remains `GeoLevel` and the selected existing value continues to drive `setLevel(...)`.
- Preserve option values, order and Arabic labels exactly:
  - `governorate` — `محافظة`
  - `city` — `مدينة`
  - `area` — `منطقة`
- Give the native select a clear Arabic accessible name such as `مستوى التحليل الجغرافي`; its meaning must not depend only on visual position.
- Use the existing shared control/Field geometry, semantic surfaces, focus and disabled behavior instead of recreating those styles inline.
- Keep the existing header/filter cluster wrap-capable alongside `ReportFilterBar`.

### Explicit exclusions / preserve

Do not change:
- `ReportFilterBar`, date presets, custom dates or REPORT002/003 contracts;
- `filters = { dateFrom, dateTo, level }` or the meaning of `GeoLevel`;
- `useGeographySummary`, `useGeographyTable`, query/cache/service/RPC/DB behavior or calculation truth;
- `LEVEL_LABELS`, summary values, `MetricCard`, trust/freshness, heatmap table, row colors, parent-column behavior or empty/loading copy;
- permissions, routing, `AnalyticsGate`, export/print or business semantics;
- Geography's table responsive strategy, any chart/table on another report, or any second selector/page;
- the shared `Select` API itself unless implementation proves a material contract gap. If the current shared contract cannot support this consumer without a material shared/API or functional change, REPORT007 becomes `BLOCKED` and returns to Product Design rather than widening the PR.

## Device / Arabic / state / accessibility acceptance

- **Desktop:** shared standard-height control, semantic focus treatment and stable header hierarchy; no unnecessary density inflation.
- **Tablet:** V2 touch-height contract applies through the existing Field boundary; selector/date controls may wrap cleanly without clipping or ordinary page-level horizontal overflow.
- **Mobile:** native select remains touch-usable and readable; the header/filter cluster must wrap rather than compress Arabic labels.
- **Arabic / RTL:** Arabic options stay unchanged; native chevron/padding behavior remains correct for RTL; no essential text truncation is introduced.
- **Dark mode:** surface, text, border, hover/focus and disabled visuals remain token-driven through the shared control contract.
- **Accessibility:** explicit Arabic accessible name, native keyboard/select semantics retained, no custom combobox behavior added.
- **State:** changing the level must continue to drive the same existing report filter/domain behavior. No new loading/empty/error semantics are introduced in this slice.

Focused tests should protect option order/labels, accessible naming, controlled selection and preservation of current report/filter semantics. Hosted GitHub Actions remain forbidden; execution evidence must stay honest under the existing validation policy.

## Peer-state synthesis / contradiction handling

This selection was formed from source and current Design System contracts before peer-state synthesis.

- **Development Integrator:** current and aligned. It records REPORT006 merged and explicitly hands REPORT007 to Product Design for one smallest bounded concern.
- **Design QA:** its latest role state is lifecycle-stale at REPORT006 exact-head review. It contains no contradiction with this new boundary and supplies no REPORT007 approval yet.
- **UI Production Engineer:** its latest role state is lifecycle-stale at REPORT006 implementation. It must bootstrap from the new Workstream/Director boundary before starting REPORT007.
- **Team Memory:** still describes REPORT007 as an unbounded placeholder. That lifecycle line is now superseded by the newer Workstream and this Director state; durable invariants remain aligned, so no Team Memory rewrite is justified by this routine slice selection.
- **Decision Log / North Star:** aligned. REPORT007 applies existing form ownership, Arabic-first, touch, RTL/dark and functional-isolation rules; it creates no new durable system decision.

Current contradiction classification: **NONE**.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, exact Development HEAD, open Development-targeting PRs, representative remaining Reports source and relevant Component System, Page Pattern, Migration Matrix, Roadmap, Source Audit and Component Decision Matrix documents.
- Bounded REPORT007 in `31_AGENT_TEAM_WORKSTREAM.md` as the single Geography analysis-level selector convergence.
- Did not update Team Memory or Decision Log because no overall design direction or durable rule changed.
- Did not implement product code, modify peer specialist states, merge a PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after a stable implementation PR exists.
- **What changed:** REPORT007 is now concretely bounded and implementation-authorized as the single raw Geography `GeoLevel` selector migration to the existing shared V2 `Select -> Field` contract.
- **Preserve:** exact `GeoLevel` values/order/Arabic labels and controlled state; `filters = { dateFrom, dateTo, level }`; all Geography queries/calculations/trust/metrics/table/heatmap/parent-column/permission/routing/`AnalyticsGate`/export/print/business truth; REPORT002/003 filter/date contracts; one-selector/one-page scope; existing shared `Select` API unless a real blocker is escalated.
- **Need from you:** UI Production should branch from the latest Development HEAD and open exactly one REPORT007 implementation PR for this control only, with focused tests for labels/order, accessible naming and controlled selection. If the existing shared Select contract cannot satisfy the boundary without material API/functional change, mark the slice `BLOCKED` instead of widening it. Design QA should wait for one stable exact PR HEAD before review.
- **Blocker level:** `NONE`.
- **Baseline:** selection baseline `14dc8d3947b4a39ce4a8c9dc11c6b4d9712bc98d`; Workstream-bound Development HEAD before this state write `3b9a51f9c93a4e015f51e04291833b68bac1bc7f`.
