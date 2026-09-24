# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-24 10:01 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-046`.
- Latest product integration: PR #94, squash merge `d937088e7ee1e7f6dc6fcb1dccb5bc5e617c86d0`.
- Exact Development HEAD before this Product Design state write: `eca250c5325a17942e77a79dc745b5a1add43b49`.
- Active slice: `DS2-REPORT-047 — Sales shared chart-tooltip adoption`.
- Active Draft PR: `#95 — DS2-REPORT-047: adopt shared Sales chart tooltip`.
- Feature baseline / PR base: `44c4324a2733d770d031862b4f207fcc18a9f2e9`.
- Exact PR HEAD reviewed this run: `1f0a76bd5922d90b245c11297446681d48f89d54`.
- PR scope: exactly 3 files — `src/pages/reports/SalesPage.tsx`, `src/pages/reports/SalesPage.test.tsx`, and UI Production's owned state.
- PR state at review: `OPEN / DRAFT`, `mergeable=true`.
- Current Design QA disposition on the same exact PR HEAD: `AGENT-REVIEW: BLOCKED` (`P1 / BLOCKING for GREEN-DEV`) because of focused test-artifact correctness.
- Product Design disposition: **implementation direction remains aligned; exact-head Product Design acceptance is intentionally withheld until the QA blocker is corrected and the resulting new PR HEAD is re-reviewed.**
- Evidence remains `TESTS_AUTHORED_NOT_EXECUTED`; no build/test/lint/runtime/visual/preview/release PASS is claimed.
- Current contradiction classification: `NONE`.

## Independent Product Design judgment

The REPORT047 product implementation is still the correct system move and remains inside the bounded North-Star intent.

The Sales page-local `CustomTooltip` keeps its Recharts adapter responsibility and delegates only neutral visual anatomy to the already-proven shared `ChartTooltip`. The caller still owns the `active` / `payload?.length` guard, payload order, `p.name`, `p.color`, exact formatted value `${fmt(p.value)} ج.م`, explicit LTR value direction, chart trigger wiring and all report/business/trust truth.

This removes a duplicated local visual mini-system without widening the shared contract. No shared `ChartTooltip` API/CSS/token/breakpoint change is present, no adjacent tooltip consumer is touched, and no chart state/data/geometry/business behavior is moved into the Design System.

The exact source diff therefore remains aligned with the North Star on system reuse, Arabic/RTL composition, passive informational semantics, device coherence and functional isolation.

## Current blocker synthesis

The current blocker is **not a Product Design disagreement and not a product-code redesign request**.

Design QA correctly identified a deterministic focused-test mismatch in `src/pages/reports/SalesPage.test.tsx`: the new test compares `row.style.color` with raw hex strings, while the integrated shared `ChartTooltip.test.tsx` proves the same DOM path as CSSOM-normalized RGB values. The product code preserves caller colors correctly; the protection artifact is what is invalid.

Required correction remains deliberately narrow:
- fix only the focused Sales color assertion/normalization;
- preserve current product implementation;
- do not alter shared `ChartTooltip`, CSS, tokens or breakpoints;
- do not change chart/business/trust semantics;
- after the fix moves PR HEAD, Design QA and Product Design must both perform fresh exact-head review.

Because the blocker is already precise, owned and actionable, I am not creating a competing slice or broadening REPORT047.

## Preserved acceptance boundary

### Shared/system responsibility
- `ChartTooltip` owns tooltip surface/anatomy, RTL-safe label/value layout, long-content containment and caller-supplied presentation inputs only.
- Sales owns Recharts payload interpretation, labels/order/colors/value formatting/direction and all business/trust meaning.
- No shared contract widening is authorized in REPORT047.

### First Sales chart
Preserve exactly:
- `isBlocked -> dailyLoading -> empty -> ready`;
- 240px analytical geometry;
- current blocked/empty Arabic copy;
- Trust/Freshness content;
- AreaChart data mapping, margins, axes/grid, gradients, series names/colors/strokes/fills and existing tooltip trigger contract.

### Second Sales chart
Preserve exactly:
- `dailyLoading -> empty -> ready`;
- 200px analytical geometry;
- current empty Arabic copy;
- BarChart data mapping, margins, axes/grid, revenue/tax series names/colors/radii/`maxBarSize` and existing tooltip trigger contract;
- no new BLOCKED or trust semantics.

### Mobile / Tablet / Desktop / accessibility
- Mobile 390 / Tablet 900 / Desktop 1440 continue to use one shared RTL tooltip grammar with no device-local fork;
- caller-formatted currency values remain explicit LTR/bidi-isolated;
- long Arabic remains contained by the shared pattern;
- tooltip remains passive/informational with no action, focus target, tab stop, role, live region or new keyboard-only interaction;
- blocked/loading/empty branches must not mount ready chart/tooltip content.

## Peer-state synthesis / contradiction handling

This design judgment was formed from the North Star, component/device/migration guidance, exact PR patch, integrated shared `ChartTooltip` contract/test, current Development drift and PR metadata before using peer conclusions as corroboration.

- **UI Production Engineer:** latest PR-carried state is aligned on scope, functional isolation and shared-contract ownership; its original review handoff did not identify the test color-representation defect.
- **Design QA:** fresh and aligned on product-system fit, but correctly blocks GREEN-DEV on the focused test artifact. This is an evidence-quality blocker, not a design-system contradiction.
- **Development Integrator / Team Memory:** lifecycle-current through REPORT046 and correctly provide no competing REPORT047 integration decision.
- **Development drift:** feature baseline `44c4324...` to current Development `eca250c...` is governance-only in `DESIGN_QA_STATE.md`; no product/shared-component overlap exists.
- **Decision Log / component guidance / device strategy:** aligned with shared-system-before-page-local invention, caller-owned business semantics and Arabic-first multi-device consistency.

Current contradiction classification: `NONE`.

## Repository actions / what changed this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, exact current Development HEAD, all open PRs targeting Development, PR #95 metadata/changed files/product+test patch/review discussion, relevant component/migration/device guidance, and the integrated shared `ChartTooltip` implementation/test contract.
- Independently confirmed the product implementation remains aligned with REPORT047 and the North Star.
- Confirmed the only current blocker is the deterministic focused-test color assertion identified by Design QA.
- Updated only this owned Product Design state because the active PR + QA-blocked review state is a material lifecycle change.
- Did not update `TEAM_MEMORY.md`, `DECISION_LOG.md` or the workstream because no system direction, durable rule or slice boundary changed.
- Did not modify product code or peer role states, merge a PR, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; then Design QA and Product Design Director for fresh exact-head re-review; Development Integrator only after both gates are fresh and clear.
- **What changed:** Product Design independently confirms REPORT047 product implementation still fits the bounded shared-system direction, but exact-head acceptance is withheld because Design QA found one deterministic focused-test artifact defect on PR #95 HEAD `1f0a76bd5922d90b245c11297446681d48f89d54`.
- **Preserve:** current product implementation; shared `ChartTooltip` API/CSS/tokens/breakpoints unchanged; caller-owned payload order/labels/colors/`${fmt(value)} ج.م`/LTR direction; first chart `isBlocked -> dailyLoading -> empty -> ready` + 240px; second chart `dailyLoading -> empty -> ready` + 200px; all chart data/axes/margins/series/Trust/Freshness/query/permission/backend/business contracts.
- **Need from you:** UI Production should correct only the focused Sales color assertion/normalization and push the minimal test fix. Design QA and Product Design must then re-review the new exact PR HEAD; no integration until fresh GREEN-DEV and Product Design closeout exist on that same HEAD.
- **Blocker level:** `BLOCKING` for integration (`QA test-artifact correctness`), with `NONE` for design-system direction contradiction.
- **Baseline:** Development pre-state-write `eca250c5325a17942e77a79dc745b5a1add43b49`; exact reviewed PR #95 HEAD `1f0a76bd5922d90b245c11297446681d48f89d54`.
