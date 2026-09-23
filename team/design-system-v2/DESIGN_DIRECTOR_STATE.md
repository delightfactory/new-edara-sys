# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-23 05:00 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before REPORT032 bounding: `eee09daf4f57702a3cdb2c5492bda49ca3307dba`.
- REPORT031 is integrated; no implementation PR was open against Development at selection time.
- Active READY slice: `DS2-REPORT-032 — Customer Re-engagement KPI summary shared metric convergence`.
- Representative surface: `src/pages/reports/CustomerReengagementPage.tsx` → `KpiStrip` only.
- Product Design disposition: `READY — BOUNDED`.
- Workstream bounding commit: `88f7e965ba0675ff0f32f3fe272a2dc86f92d021`.

## Independent Product Design judgment

**REPORT032 should converge the Customer Re-engagement five-card KPI strip onto the already-proven shared metric grammar, without widening that grammar.**

The exact Development source still carries a page-local KPI mini-system: `rp-kpi-grid`, `rp-kpi-card`, page-local label/value/icon/context styling, arbitrary per-card accent borders and a custom responsive grid. That is now the clearest small Reports/Analytics divergence because V2 already owns both pieces required to express the same responsibility: `MetricGrid` for responsive summary layout and `StatCard` for semantic KPI hierarchy.

The correct system move is **not** to add `columns={5}` to `MetricGrid`. Five dense Desktop columns would reduce long-Arabic/currency tolerance and would widen a shared API/CSS/breakpoint contract without a demonstrated system need. Existing `MetricGrid columns={3}` already composes five children safely as Desktop 3 + 2, Tablet 2 + 2 + 1 and Mobile one per row. This gives the page an intentional multi-device composition while preserving the shared contract unchanged.

The current arbitrary KPI color accents should also not be carried forward as a new page-specific StatCard variant. Existing business meaning can map onto the small semantic vocabulary already owned by V2: Champion Lost=`danger`; تراجع عالي=`warning`; متوسط خامد=`warning`; إجمالي العملاء=`info`; صافي الأرصدة=`success` only when the current total is credit (`total_outstanding < 0`), otherwise `info`. This mirrors existing urgency/credit-vs-debt meaning without moving any calculation or priority classification into the Design System.

## REPORT032 acceptance boundary

Implementation is authorized only for the Customer Re-engagement summary `KpiStrip`.

Preserve exactly:
- five-card order: `Champion Lost` → `تراجع عالي` → `متوسط خامد` → `إجمالي العملاء` → `صافي الأرصدة`;
- all current labels, sublabels/context and emoji/icon identity;
- `summary?.champion_lost_count`, `declining_high_count`, `mid_lost_count`, `total_customers` and `total_outstanding` sources;
- `FMT` / `fmtCur` formatting, `Math.abs(summary.total_outstanding)` and exact `إجمالي مديونية` / `رصيد دائن صاف` conditional copy;
- summary loading precedence: five metric identities/context remain present and only five values become skeleton placeholders;
- passive/non-interactive KPI behavior and no focus/hover-dependent meaning.

Shared presentation contract:
- consume existing `MetricGrid columns={3}` and existing `StatCard` unchanged;
- Desktop: three-column shared metric layout with five cards wrapping 3 + 2;
- Tablet: shared two-column layout;
- Mobile: shared one-column layout, no ordinary horizontal overflow, long Arabic/currency tolerance;
- semantic tone is presentation only; page/domain continues to own every count, balance sign and priority meaning;
- remove only KPI-specific local CSS made orphaned by this migration. Do not use REPORT032 as a general cleanup vehicle.

Accessibility/state intent:
- KPI cards remain static information surfaces, not pseudo-buttons;
- visible labels/context remain the accessible meaning; decorative emoji/icon presentation must not become an accessible-name dependency;
- loading must preserve meaningful metric identity rather than replace the whole summary with anonymous cards;
- no new permission, destructive, validation, offline or workflow state is introduced.

## Explicit exclusions / stop boundary

REPORT032 must not change:
- `FilterBar`, URL-synced filter state, governorate/city/profile reference data, query inputs or filter stats;
- customer list/table/mobile-card/detail composition, `PriorityBadge`, `RecencyBadge`, non-summary balance cells, Customer 360 links/actions or permission checks;
- Export Drawer, print/PDF/CSV behavior or document-output contracts;
- `PRIORITY` configuration still required outside the KPI summary;
- broader Customer Re-engagement scoped-style cleanup or its existing Desktop/Mobile collection switching;
- shared `MetricGrid`, `StatCard`, `Card`, CSS, token or breakpoint APIs;
- hooks, calculations, query/cache semantics, RBAC/RLS, routes, exports, backend, business/workflow behavior or any other report surface.

If implementation needs any excluded shared/functional change, REPORT032 becomes `BLOCKED` rather than broadening the PR.

## Focused validation expectation

A focused `CustomerReengagementPage` test artifact should guard the material migration risk:
- shared `[data-metric-grid][data-columns="3"]` adoption;
- five shared StatCard surfaces in exact business order;
- preserved label/context/value formatting and both net-balance sign outcomes;
- declared semantic-tone mapping;
- summary loading retains five metric identities and five value-level skeletons.

Under the current quota policy, authored coverage remains `TESTS_AUTHORED_NOT_EXECUTED` unless an approved execution environment actually runs it. No build/test/lint/runtime/preview PASS is implied by this Product Design direction.

## Peer-state synthesis

I formed the direction from the exact Development source and existing `MetricGrid` / `StatCard` contracts first, then compared peer state.

- **Development Integrator:** fresh and aligned; REPORT031 is merged and it explicitly handed REPORT032 to Product Design for one smallest bounded concern.
- **Team Memory:** lifecycle-current through REPORT031 but its REPORT032 text is intentionally still the pre-bounding placeholder; the Workstream and this owned state now carry the material current boundary. No durable system direction changed, so Team Memory is not rewritten for routine slice progress.
- **UI Production Engineer / Design QA:** lifecycle-stale from REPORT031 and contain no competing REPORT032 implementation, approval or blocker.
- **Decision Log / North Star / component blueprint:** aligned with shared-system-before-local-invention, semantic variants, Arabic-first multi-device composition and strict functional isolation.

Current contradiction classification: `NONE`.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, current Development HEAD, open PRs targeting Development and relevant Reports/component/device/migration source.
- Confirmed zero open implementation PRs targeting `design-system-v2-development` before selection.
- Bounded exactly one dependency-safe REPORT032 concern and updated the Workstream in `88f7e965ba0675ff0f32f3fe272a2dc86f92d021`.
- Did not change Team Memory or Decision Log because no durable/overall design-system rule changed.
- Did not modify product code, merge, deploy, touch `main`, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after one REPORT032 PR reaches stable REVIEW.
- **What changed:** REPORT032 is now `READY — BOUNDED` to Customer Re-engagement `KpiStrip` only, converging five local KPI cards onto existing `MetricGrid columns={3}` + `StatCard` with semantic tones and no shared-contract widening.
- **Preserve:** exact five metrics/order/copy/value sources/formatting/loading semantics; all filters/list/export/permission/query/business behavior; existing shared MetricGrid/StatCard/Card APIs, CSS, tokens and breakpoints.
- **Need from you:** UI Production should start from the exact latest Development HEAD after this governance write, implement only REPORT032, add focused tests for the declared metric/tone/loading contract and open one PR targeting `design-system-v2-development`; mark BLOCKED rather than widen scope if a shared or functional change proves necessary.
- **Blocker level:** `NONE`.
- **Baseline:** Product Design selection baseline `eee09daf4f57702a3cdb2c5492bda49ca3307dba`; Workstream bounding commit `88f7e965ba0675ff0f32f3fe272a2dc86f92d021`.
