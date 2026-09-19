# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-19`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development product/governance HEAD independently inspected before REPORT009 selection: `e893339de9c43b9b3a3006a743a100dcb09ea0e7`.
- Workstream boundary commit created this run: `15aea3009dbc0e74340ed2ad90d2f5115e9efd8d`.
- Product UI is integrated through `DS2-REPORT-008` / PR #55 / squash merge `cdacc180e1e163b6dcb3d16cb80ff0beee1e701f`.
- No open implementation PR currently targets `design-system-v2-development`.
- Current single READY slice: `DS2-REPORT-009 — Sales secondary revenue/tax chart-panel convergence`.
- Representative surface: `src/pages/reports/SalesPage.tsx` → second chart section `توزيع الإيرادات اليومي (إيراد + ضريبة)` only.
- Current Product Design disposition: `READY — IMPLEMENTATION AUTHORIZED WITH BOUNDED PRESENTATION-ONLY SCOPE`.
- Build/test/lint/runtime/preview/release PASS: not claimed.

## What changed since the previous state

REPORT008 has been integrated and the generic REPORT009 roadmap placeholder is now decomposed into one smallest dependency-safe concern. I inspected the exact latest Development baseline, remaining Sales report analytical composition, the existing `ChartPanel` contract, the focused `SalesPage.test.tsx` proof from REPORT005, current Team Memory/peer states, issue #27, and the relevant component/page/migration/source-audit decision documents.

The Sales report currently has one analytical section already on shared `ChartPanel` and an immediately adjacent second chart still using a page-local card/title shell. That inconsistency is a clean system-convergence target: the shared analytical pattern is already proven on Sales and Receivables, so REPORT009 can retire the remaining local shell without inventing a new component or moving chart/report semantics into the Design System.

## Independent Product Design judgment

**READY — implement the second Sales chart shell only through the existing shared `ChartPanel`.**

This is preferable to opening a broader table/filter/report cleanup because it advances one coherent analytical grammar with minimal regression surface. It also corrects the page hierarchy from a styled title `div` to the existing shared semantic `h2` path while preserving the current chart body and all domain behavior.

The existing `ChartPanel` contract is sufficient as-is: `title` is required, while `description` and `action` are optional. REPORT009 therefore must not add copy, trust metadata or new state semantics just to fill optional slots.

## REPORT009 exact scope

### In scope

- `src/pages/reports/SalesPage.tsx` → only the second chart titled `توزيع الإيرادات اليومي (إيراد + ضريبة)`.
- Replace its page-local outer analytical card/header shell with the existing shared V2 `ChartPanel`.
- Keep the exact Arabic title and use the default semantic `h2` hierarchy.
- Keep the current body contract exactly:
  - loading: `SkeletonCard height={200}`;
  - data: `ResponsiveContainer width="100%" height={200}`;
  - same `chartData`;
  - same `BarChart` margin `{ top: 4, left: -10, right: 4, bottom: 0 }`;
  - same grid, axes, tick formatting and `CustomTooltip`;
  - same Bars: `revenue / الإيراد / #2563eb` and `tax / الضريبة / #0284c7`, each `radius={[3,3,0,0]}` and `maxBarSize={24}`.
- Update focused `SalesPage.test.tsx` only as needed to protect this convergence and preserved chart contracts.

### Explicitly preserve / exclude

- The first Sales `ChartPanel` `تطور الإيراد اليومي` remains unchanged in product code.
- Its exact description, trust/freshness action cluster, blocked/loading/empty/data branches and 240px body remain unchanged.
- Do not add description/action/trust/freshness/blocked/empty semantics to the second chart; the current second-chart behavior is preserved, not reinterpreted.
- All four `MetricCard`s, `report-grid`, page header, `ReportFilterBar`, `SystemHealthBar`, `CustomTooltip`, hooks, date range/filter state, trust calculations and chart-data mapping remain unchanged.
- No `ChartPanel` API/CSS change, no Recharts abstraction, no chart legend/tooltip primitive, no second page/report, no DB/RPC/service/query/cache/RBAC/RLS/permission/route/business-calculation/validation/workflow/export/print/deployment change.
- If preserving exact semantics requires any of the excluded changes, REPORT009 becomes `BLOCKED` and returns to Product Design rather than widening the PR.

## Device / state / accessibility acceptance

- **Desktop:** preserve compact reporting density; the second chart body remains 200px and must not become a decorative oversized surface.
- **Tablet:** shared panel/header composition must remain deliberate with no fixed-width pressure or ordinary page horizontal overflow.
- **Mobile:** Arabic title wraps safely; chart containment remains width-safe through the shared panel; no duplicate interaction/render tree is introduced.
- **RTL / Arabic:** retain the exact title and use shared logical spacing/surface rules.
- **Dark mode:** surface/border/title presentation comes from the existing V2 semantic-token path through `ChartPanel`.
- **Accessibility:** page hierarchy becomes `h1 -> h2` for both analytical sections; no new interactive control is introduced, so no synthetic focus/touch behavior is added.
- **States:** preserve exactly the second chart's current loading/data branching and current absence of additional blocked/empty gating; changing trust/state meaning is outside this presentation slice.
- **Evidence:** focused tests are required for material composition/chart-contract risk; execution evidence must remain honestly labeled under the quota policy.

## Test intent

Existing `SalesPage.test.tsx` currently proves that exactly one shared `ChartPanel` exists and explicitly asserts that the second chart is not inside one. REPORT009 must update that contract rather than layering a new test around stale expectations.

Focused coverage should prove at minimum:
- exactly two shared `.ds-chart-panel` surfaces on Sales after the migration;
- second panel has semantic `h2` with exact title `توزيع الإيرادات اليومي (إيراد + ضريبة)`;
- first panel's existing title/description/trust/freshness/blocked/empty contract remains intact;
- second chart keeps 200px loading/data height and exact two-series Bar configuration/margins;
- no accidental shared API or domain-semantic widening is introduced.

## Peer-state synthesis

This Product Design judgment is grounded in the current source and shared component contracts, then compared with repository team state.

- **Team Memory:** fresh after REPORT008 merge; it correctly requires Product Design to bound exactly one smallest REPORT009 concern. This state now fulfills that handoff.
- **Development Integrator:** fresh and aligned; REPORT008 is merged and exactly one generic REPORT009 item was advanced for Product Design decomposition.
- **UI Production Engineer:** Development-branch state is lifecycle-stale at the completed REPORT008 implementation, as expected before REPORT009 begins; no conflicting current constraint exists.
- **Design QA:** Development-branch state is lifecycle-stale at completed REPORT008 review; its durable evidence rules remain aligned and no REPORT009 approval exists yet.
- **Previous Design Director state:** lifecycle-stale at REPORT008 pre-merge closeout and superseded by this new selection.
- **Decision Log / North Star / Component System / Page Patterns / Migration Matrix / Source Audit / Component Decision Matrix:** aligned. REPORT009 applies existing shared-system-first, UI-only isolation, Arabic-first, semantic hierarchy and multi-device rules; no durable decision changes.

Current contradiction classification: **NONE**.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, exact current Development HEAD, open PRs targeting Development (none), relevant blueprint/component/migration/source-audit docs, `SalesPage.tsx`, `SalesPage.test.tsx` and shared `ChartPanel`.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` to replace the generic REPORT009 placeholder with one exact READY implementation boundary.
- Updated only the owned `team/design-system-v2/DESIGN_DIRECTOR_STATE.md` among specialist states.
- Did not update `TEAM_MEMORY.md` because overall system direction did not materially change; this is a bounded queue decomposition.
- Did not update `DECISION_LOG.md` because no durable rule changed.
- Did not implement product code, modify peer states, merge a PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after a stable implementation PR exists.
- **What changed:** REPORT009 is now concretely bounded to the second Sales chart `توزيع الإيرادات اليومي (إيراد + ضريبة)`; implementation may replace only its local analytical shell/title with existing shared `ChartPanel`.
- **Preserve:** exact title; current loading/data behavior and 200px body; `chartData`; BarChart margins/grid/axes/tooltip; both revenue/tax series contracts; first Sales ChartPanel and all trust/state/metric/filter/query/business semantics; existing `ChartPanel` API/CSS; no Actions/Vercel/preview/`main` activity.
- **Need from you:** branch from the latest `design-system-v2-development`, open exactly one REPORT009 PR for this second chart shell, update focused Sales tests to the new two-panel contract, and stop as `BLOCKED` rather than widening scope if exact existing semantics cannot be preserved. Design QA should review only the future exact stable PR HEAD.
- **Blocker level:** `NONE`.
- **Baseline:** Product/source selection baseline `e893339de9c43b9b3a3006a743a100dcb09ea0e7`; Workstream boundary commit/current pre-state-write Development HEAD `15aea3009dbc0e74340ed2ad90d2f5115e9efd8d`.
