# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-20`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD immediately before this state write: `4a8152ad7aac09237366fe6ca892f9f795fe2ac0`.
- Current integrated product HEAD: `9433ec1623a812d1b47d93bffad7e1c537caaa91` from completed `DS2-REPORT-011` / PR #58.
- Active slice: `DS2-REPORT-012 — Customer Health responsive detail-collection convergence`.
- Slice state: `READY`.
- Active implementation PR: none at final Product Design recheck before the boundary was recorded.
- Representative surface: `src/pages/reports/CustomerHealthPage.tsx`, section `تفاصيل العملاء — أعلى 50 حسب القيمة` only.
- Product Design disposition: `READY — IMPLEMENTATION BOUNDARY AUTHORIZED`.
- Build/test/lint/runtime/preview/release PASS: not claimed.

## What changed since the previous state

REPORT011 is now integrated. With no implementation PR active, I inspected the exact latest Development baseline and bounded the previously generic REPORT012 queue item to one concrete dependency-safe presentation concern: Customer Health's desktop-only top-50 detail table.

The workstream now authorizes UI Production to migrate only that collection to the existing `ResponsiveCollection + Card + KeyValueList` device-composition grammar while preserving all customer-health data, trust, status and snapshot semantics.

## Independent Product Design judgment

**READY — Customer Health responsive detail-collection convergence is the correct next system slice.**

The Reports workstream has now proved `ChartPanel` across four analytical pages. Repeating another chart-shell migration would add less system depth than addressing an obvious cross-device collection gap: `CustomerHealthPage` still exposes a dense desktop table behind horizontal overflow with no deliberate Tablet/Mobile composition.

REPORT006 already proved the correct domain-agnostic mechanism: `ResponsiveCollection` mounts exactly one device renderer while callers retain their data/state/business truth. Reusing that contract on a different row shape advances the North Star at the shared grammar level rather than beautifying a page in isolation.

No shared component change is required by source inspection. If implementation proves otherwise, the slice must stop as `BLOCKED` instead of widening scope.

## Exact REPORT012 boundary

### In scope

Only the section `تفاصيل العملاء — أعلى 50 حسب القيمة` in `src/pages/reports/CustomerHealthPage.tsx`:

- preserve the current outer section title and Trust/Freshness cluster;
- keep `isBlocked` as the higher-priority branch with the exact current blocked semantics/copy;
- put the non-blocked loading/empty/ready collection path behind `ResponsiveCollection<CustomerHealthRow>` using the existing `rows` and `isLoading` truth;
- keep the existing loading skeleton and exact empty-state copy;
- Desktop keeps the current five-column order/value semantics and `RecencyCell`, with proper `th scope="col"` semantics;
- Tablet/Mobile use shared `Card + KeyValueList` composition for the same row truth: customer identity, recency, frequency, 90-day monetary value and active/dormant status;
- preserve current customer-name fallback behavior and all numeric/currency/status formatting/meaning;
- preserve the `stats.total > 50` informational footer and exact count/copy meaning without per-device duplication;
- add focused source-level tests covering device selection, single-renderer behavior, blocked/loading/empty precedence, row mapping and footer behavior.

### Device / RTL / dark / accessibility acceptance

- **Desktop:** retain the compact five-column comparison density and all values; local table overflow only when necessary.
- **Tablet:** shared two-column card grid is acceptable; no page-level horizontal scrolling; identity remains primary and supporting facts remain scan-friendly.
- **Mobile:** single-column card stack; desktop table is not mounted; long Arabic customer names/fallback IDs remain contained and readable.
- **RTL/Arabic:** logical RTL labels/layout; long names wrap; existing LTR number/currency semantics remain explicit.
- **Dark mode:** mobile/tablet cards and key/value composition use existing shared semantic V2 tokens only.
- **Accessibility:** one renderer in the DOM; semantic desktop column headers; explicit card label/value pairs; singular blocked/loading/empty states; no new interactive or touch target is introduced.

### Explicit exclusions

REPORT012 must not change:
- page header or raw `asOfDate` date control;
- `SystemHealthBar`, KPI cards, Trust/Freshness rules, `RecencyCell` thresholds/colors or active/dormant meaning;
- outer detail-section shell/header;
- snapshot/date selection, hooks, row order/top-50 logic, query/cache/calculation/trust/permission/RBAC/RLS/routing/export/print/business semantics;
- `ResponsiveCollection`, `Card`, `KeyValueList` APIs/CSS or any other shared component;
- any second Reports page;
- backend/schema/RPC/deployment/workflow behavior.

## Peer-state synthesis / contradiction handling

Independent judgment was formed from the exact Customer Health source, existing Product Performance responsive-collection proof, shared `ResponsiveCollection` contract, component-system guidance and migration roadmap, then compared with peer states.

- **Development Integrator:** fresh and aligned; REPORT011 is merged and REPORT012 is the sole next READY queue item.
- **Team Memory:** correct on REPORT011 integration and overall direction; its generic REPORT012 wording is lifecycle-stale after this exact boundary but not contradictory. It does not need a direction-level rewrite for this routine slice selection.
- **UI Production Engineer / Design QA:** prior-slice states are expectedly stale because no REPORT012 implementation exists yet; neither records a conflicting active implementation or blocker.
- **Decision Log / North Star / component and migration docs:** aligned; no durable design rule changed.

Current contradiction classification: **NONE**.

## Risks / stop conditions

- The current Customer Health blocked state sits outside loading/empty/ready presentation and must remain higher priority; do not force it into `ResponsiveCollection` by changing that shared API.
- The top-50 informational footer is part of report meaning and must remain visible under the same ready-data condition without being duplicated across renderers.
- Do not turn the slice into a Customer Health page redesign, DateField migration, DataTable abstraction effort, state-grammar rewrite or cross-report cleanup.
- If exact preservation requires shared API/CSS widening or functional/data/business semantic change, mark `BLOCKED` and return to Product Design.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, current Development HEAD, open PRs targeting Development, REPORT011 integration state, current Reports workstream, component/migration guidance, `CustomerHealthPage`, the prior Product Performance collection proof and shared `ResponsiveCollection` contract.
- Confirmed there was no active implementation PR and no blocking cross-role contradiction before selecting the exact REPORT012 concern.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` with the exact representative surface, system-pattern intent, device/state/accessibility acceptance, exclusions and block condition.
- Did not update `TEAM_MEMORY.md` or `DECISION_LOG.md` because no overall design direction or durable rule changed.
- Did not implement product code, modify peer states, merge a PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** REPORT012 is now exactly bounded and implementation-authorized as Customer Health responsive detail-collection convergence on `src/pages/reports/CustomerHealthPage.tsx` section `تفاصيل العملاء — أعلى 50 حسب القيمة` only.
- **Preserve:** blocked/loading/empty/ready precedence and exact copy; five existing row facts/order/formatting/status meaning; Trust/Freshness and >50 footer semantics; one mounted renderer per device; all snapshot/query/cache/trust/permission/routing/export/print/business truth; unchanged shared component APIs/CSS; no Actions/Vercel/preview/`main` activity.
- **Need from you:** branch from the latest Development HEAD after this state write, implement only the bounded collection migration plus focused tests, open one PR targeting `design-system-v2-development`, and mark BLOCKED rather than widening scope if shared/API or functional semantics would need to change.
- **Blocker level:** `NONE`.
- **Baseline:** Development boundary commit `4a8152ad7aac09237366fe6ca892f9f795fe2ac0`; integrated product merge `9433ec1623a812d1b47d93bffad7e1c537caaa91`.