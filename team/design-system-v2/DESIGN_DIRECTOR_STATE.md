# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-22`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD inspected before REPORT027 bounding: `9e55bea48e0ae2c2a8cd9292f4514f0eadf7c73e`.
- Latest integrated product baseline: `DS2-REPORT-026 — Product Performance summary metric-grid convergence` / PR #74 / squash merge `9ac63ca20baaeefa6fe5cb3e87a9734f59847ac5`.
- Workstream boundary commit produced this run: `88a01704d2db5405123434d2ee461c93091b0c8b`.
- Active single READY slice: `DS2-REPORT-027 — Churn Risk filter-control field convergence`.
- Active implementation PR: none at selection/recheck time.
- Product Design disposition: `READY — BOUNDED`.
- Current blocker classification: `NONE`.

## Independent Product Design judgment

**REPORT027 should converge the Churn Risk page-header filter controls onto the existing V2 Field grammar, and nothing else.**

I formed this judgment from the current report surfaces and shared control contracts before comparing peer states. `src/pages/reports/ChurnRiskPage.tsx` already uses the accepted shared `ChartPanel` and `ResponsiveCollection + Card + KeyValueList` grammar, but its page-header scope controls still recreate a native `<select>` and native `<input type="date">` with page-local inline styling. Existing shared `Select` and `DateField` already own exactly this presentation/accessibility responsibility through `Field`; filter values, date semantics and hook inputs can remain caller-owned.

This is the smallest dependency-safe system move available after REPORT026. It advances the report/filter and Field-convergence roadmap without creating another local visual language and without changing business truth.

## Why this slice is preferred over adjacent debt

- **Churn Risk five-card KPI summary:** deliberately deferred. Shared `MetricGrid` currently supports only 2/3/4 columns. Extending it to five columns would widen a shared contract and needs a separately bounded design decision with responsive evidence rather than being smuggled into a page migration.
- **Customer Reengagement responsive collection/Table/Card cleanup:** important debt, especially because its custom CSS leaves Tablet on the Desktop table path, but it is materially broader than two header controls and should be a later explicit slice rather than bundled into REPORT027.
- **Geography two-card metric grid:** safe but lower-value at this point because recent REPORT021-026 work already proved MetricGrid convergence repeatedly, while Churn Risk still exposes a direct shared-Field adoption gap.

## REPORT027 bounded contract

Representative surface:
- `src/pages/reports/ChurnRiskPage.tsx` → risk classification select and the single `بتاريخ` as-of-date control in the page header only.

Required implementation intent:
- replace the inline-styled native risk `<select>` with existing shared V2 `Select`;
- replace the inline-styled native date `<input type="date">` with existing shared V2 `DateField`;
- preserve exact `riskLabel ?? ''` value semantics and `setRiskLabel(e.target.value || undefined)` behavior;
- preserve exact option order/values and copy: all classifications, `VIP`, `LOYAL`, `ENGAGED`, `AT_RISK`, `DORMANT`;
- preserve `asOfDate`, `max={today}`, and `setAsOfDate(e.target.value)` exactly;
- give the risk control an accessible name and preserve the visible `بتاريخ` meaning through shared Field/accessibility plumbing;
- retain the current wrapped report-header composition and caller-owned filtering logic.

Device / accessibility acceptance:
- Mobile remains contained, touch-safe and free of ordinary horizontal overflow;
- Tablet inherits touch-first V2 control sizing and must not behave as a compact Desktop-only toolbar;
- Desktop retains a compact report-management header;
- Arabic/RTL labels and option copy remain first-class;
- keyboard focus, label association and standard control sizing come from existing shared Field/Input/Select contracts;
- no loading/blocked/chart/detail state changes are introduced.

Focused evidence expectation:
- extend `src/pages/reports/ChurnRiskPage.test.tsx` only as needed to prove accessible shared risk/date controls plus preserved selected values / hook-filter propagation;
- existing ChartPanel and ResponsiveCollection tests remain intact;
- normal expected evidence remains `TESTS_AUTHORED_NOT_EXECUTED` unless an approved execution route actually runs the tests.

## Explicit exclusions / stop boundary

REPORT027 must not change:
- the five-card Churn Risk KPI summary or create a five-column `MetricGrid` variant;
- ChartPanel, pie-chart geometry/data/colors/tooltip/legend, Trust/Freshness or SystemHealthBar;
- responsive customer details, Desktop table, Tablet/Mobile cards, RiskBadge or RecencyCell;
- shared `Select`, `DateField`, `Field`, Input APIs/CSS/tokens/breakpoints;
- any second report, including Customer Reengagement;
- hooks, queries, cache, calculations, RPC/DB, permissions, RBAC/RLS, routing, validation, export/print, workflow, backend or business semantics.

If correct implementation requires any excluded shared or functional change, REPORT027 becomes `BLOCKED` and returns to Product Design for re-bounding instead of widening the PR.

## Peer-state synthesis

I formed the Product Design direction above first, then compared repository memory and peer states.

- **Development Integrator / Team Memory:** lifecycle-current through merged REPORT026 and explicitly hand the unbounded REPORT027 placeholder to Product Design. Aligned; no blocker.
- **UI Production Engineer:** lifecycle-stale at the now-merged REPORT026 implementation. No competing implementation or contradictory rule exists.
- **Design QA:** lifecycle-stale at the now-consumed REPORT026 GREEN-DEV approval. No REPORT027 contradiction exists.
- **Previous Product Design state:** lifecycle-stale at REPORT026 pre-integration closeout and superseded by this direction.
- **Decision Log / North Star / component and device guidance:** aligned with shared-system-before-local-invention, V2 Field adoption, Arabic-first composition, touch-safe Tablet/Mobile behavior and strict functional isolation.
- **Open PR recheck:** no PR targeting `design-system-v2-development` existed when REPORT027 was selected or immediately after the Workstream boundary write.

Current contradiction classification: `NONE`.

## What changed this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Confirmed REPORT026 is integrated and no implementation PR is active.
- Inspected exact Development HEAD, issue #27, remaining report surfaces, current Churn Risk tests, and relevant shared Field/Select/DateField/ResponsiveCollection/MetricGrid contracts plus component/page/device/migration guidance.
- Concretely bounded REPORT027 as Churn Risk header filter-control Field convergence.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` in commit `88a01704d2db5405123434d2ee461c93091b0c8b`.
- Did not update `TEAM_MEMORY.md` because the overall system direction did not change.
- Did not update `DECISION_LOG.md` because no durable rule changed.
- Did not implement product code, merge, touch `main`, deploy Vercel, modify preview branches, or trigger/rerun GitHub Actions/hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after implementation.
- **What changed:** REPORT027 is now concretely `READY — BOUNDED` to the Churn Risk page-header risk-select and as-of-date controls, consuming existing `Select` + `DateField` only.
- **Preserve:** exact risk option values/order/copy/state wiring; exact `asOfDate` / `max={today}` / onChange behavior; current KPI/chart/detail/trust contracts; all query/calculation/permission/backend/business semantics; unchanged shared control APIs/CSS/tokens/breakpoints.
- **Need from you:** start from the exact latest Development HEAD after this governance write, implement only REPORT027 in one PR targeting `design-system-v2-development`, add focused accessible-control/filter-propagation tests, and stop as `BLOCKED` if any shared or functional widening is required. Design QA must then review the future exact stable PR HEAD independently.
- **Blocker level:** `NONE`.
- **Baseline:** Development source baseline inspected `9e55bea48e0ae2c2a8cd9292f4514f0eadf7c73e`; Workstream boundary commit `88a01704d2db5405123434d2ee461c93091b0c8b`.