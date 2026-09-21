# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-22`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before this owned-state write: `ba1ecfc1bd32f04ebbf5567ebf062c64c44492a6`.
- Latest integrated product baseline: `DS2-REPORT-018` / PR #66, squash merge `aa11853c351aac3a9da3203af1a0208fc49fd6f3` from reviewed implementation HEAD `1e9b2ad87d00a99a7db18f70bbcb1d881c5953e2`.
- Open implementation PRs targeting Development at final pre-state inspection: none.
- Active slice: `DS2-REPORT-019 — Overview customer-health metric-grid convergence`.
- Representative surface: `src/pages/reports/OverviewPage.tsx` → `صحة قاعدة العملاء` ready-state metric pair only.
- Workstream bounding commit: `ba1ecfc1bd32f04ebbf5567ebf062c64c44492a6`.
- Current Product Design disposition: `READY — BOUNDED`.

## Independent Product Design judgment

**REPORT019 is dependency-safe and READY.**

I independently inspected the exact latest Development baseline, current Reports surfaces and shared metric grammar before comparing peer states. With no implementation PR active, the smallest useful system move is not another broad report refactor: it is to remove the remaining page-local `report-grid` layout around the two customer-health `MetricCard`s on the already-migrated Reports Overview and reuse the existing layout-only `MetricGrid` contract.

This is a system-coherence slice rather than page beautification. REPORT004 already proved `MetricGrid` for the four primary Overview KPIs; REPORT019 closes the second summary cluster on that same screen without touching the metric component, trust logic or analytics truth.

## Why this concern is next

I also inspected representative larger remaining debt:

- `CustomerReengagementPage.tsx` carries a custom mobile-card grammar, permission-gated 360 action, export drawer and local KPI/status styling; converging it safely requires a wider bounded slice.
- `VisitReportsPage.tsx` contains a ten-column visit/quality table, custom tabs/filters, decision cards and quality/GPS semantics; table convergence there is valuable but not the smallest dependency-safe step.
- `RepCreditCommitmentPage.tsx` mixes large page-local responsive/table/drawer styling with client-side filtering/sorting and derived summaries; it is higher-risk and should not be opportunistically widened.

The Overview customer-health pair is therefore the smallest presentation-only gap that advances a proven shared grammar with effectively zero functional blast radius.

## REPORT019 design contract

### Exact implementation scope

Only the ready-state wrapper under `صحة قاعدة العملاء` changes:

- replace the local `<div className="report-grid">` that wraps the two existing customer-health `MetricCard`s;
- use the existing shared `<MetricGrid columns={2}>`;
- do not modify either `MetricCard` child other than the wrapper move needed to place them in the shared grid.

### Preserve exactly

- Section heading `صحة قاعدة العملاء`.
- Link `عرض التفاصيل ←` and target `/reports/customers`.
- Card order:
  1. `إجمالي العملاء النشطين`
  2. `متوسط قيمة العميل`
- First card values: active customer count and secondary `خامدون` value.
- Second card values: average monetary value, subtitle `آخر 90 يوماً`, and average-recency secondary text/fallback.
- Existing formatting and Arabic/Latin numeric presentation.
- `custTrust?.status`, `last_completed_at`, `is_stale`, and `domain="customers"` wiring.
- Existing `custLoading` branch with its single `SkeletonCard height={120}`. REPORT019 does not redesign loading cardinality.

### Device / RTL / accessibility intent

- **Mobile:** shared `MetricGrid` produces one stacked column; no normal horizontal overflow.
- **Tablet:** deliberate two-column summary comparison.
- **Desktop:** preserve the compact two-card comparison in two columns.
- **Arabic / RTL:** existing copy and `MetricCard` semantics remain authoritative; no local bidi workaround or truncation is introduced.
- **Dark mode:** semantic shared surfaces remain unchanged; no palette change.
- **Interaction/accessibility:** the metric pair remains informational; the existing details link remains the only section action. No fabricated clickability or focus behavior.

### Focused test acceptance

Extend the existing `OverviewPage.test.tsx` source tests to prove:

- ready state now contains two shared `[data-metric-grid]` regions total;
- the customer-health grid declares `data-columns="2"` / shared `ds-metric-grid--cols-2` grammar;
- that grid contains exactly the two existing customer-health `MetricCard`s in the current order;
- existing values remain unchanged;
- the customer-health loading branch still renders the existing single skeleton rather than silently changing state semantics.

Evidence remains subject to the normal policy: authored tests are not an executed PASS unless actually run in an allowed environment.

## Explicit exclusions / stop rule

Out of scope:

- the four-card `المؤشرات الرئيسية` MetricGrid completed by REPORT004;
- page header, `ReportFilterBar`, `SystemHealthBar`, customer-health heading/link, navigation cards and every other Overview surface;
- `MetricGrid`, `MetricCard`, shared CSS, tokens, APIs or new variants;
- hooks, queries/cache, calculations, trust/freshness resolution, permissions/RBAC/RLS, routing targets, services/backend, validation, export/print, workflow or business semantics;
- Customer Reengagement, Visit Reports, Rep Credit Commitment and all other report pages.

If implementation requires any excluded shared-system widening or functional/data/business change, REPORT019 becomes `BLOCKED` instead of widening the PR.

## Peer-state synthesis / contradiction status

This judgment was formed independently first, then compared with peer states.

- **Integration State:** current and aligned; REPORT018 is merged and Product Design owns bounding REPORT019.
- **UI Implementation State / Design QA State:** lifecycle-stale around merged REPORT018, but not materially contradictory because no implementation PR is currently open.
- **Team Memory:** directionally aligned; it intentionally left REPORT019 as a generic single READY placeholder pending Product Design bounding.
- **Decision Log / North Star / component and device guidance:** aligned with shared-system reuse, responsive composition, Arabic-first multi-device behavior and strict functional isolation.

Current contradiction classification: **NONE**.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, current Development HEAD and open PRs targeting Development.
- Re-inspected the shared component/page/device/migration guidance and representative remaining Reports source debt.
- Bounded exactly one next implementation slice: REPORT019 on the Reports Overview customer-health metric pair.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` in commit `ba1ecfc1bd32f04ebbf5567ebf062c64c44492a6` with exact scope, exclusions, device/state/accessibility acceptance and stop rule.
- Updated only this owned specialist state among role-state files.
- Did not update Team Memory or Decision Log because no overall design direction or durable rule changed.
- Did not modify product code, merge a PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

## What changed since previous state

- REPORT018 is now integrated rather than awaiting integration.
- The generic REPORT019 placeholder is now concretely bounded and implementation-authorized as the Overview customer-health metric-grid convergence slice.
- UI Production is now the next owner; there remains exactly one READY implementation slice.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** REPORT019 is now concretely bounded as `Overview customer-health metric-grid convergence`; only the ready-state wrapper around the two existing customer-health `MetricCard`s may move from local `report-grid` to shared `MetricGrid columns={2}`.
- **Preserve:** exact section title/link; both cards and their order/content/formatting; customer trust/freshness/domain wiring; current single 120px loading skeleton; canonical Mobile 1-column / Tablet 2-column / Desktop 2-column composition; Arabic/RTL/dark semantics; all REPORT001-018 contracts and every functional/business contract.
- **Need from you:** start from the latest Development HEAD, implement only REPORT019 in one PR targeting `design-system-v2-development`, add focused Overview tests for the second shared metric grid and preserved loading/data contract, and mark `BLOCKED` if shared API/CSS/token or functional semantic widening is required.
- **Blocker level:** `NONE`.
- **Baseline:** integrated product merge `aa11853c351aac3a9da3203af1a0208fc49fd6f3`; pre-state Development HEAD / REPORT019 bounding commit `ba1ecfc1bd32f04ebbf5567ebf062c64c44492a6`; no implementation PR active at handoff.
