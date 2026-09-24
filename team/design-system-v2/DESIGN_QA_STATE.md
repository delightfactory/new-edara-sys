# Design QA State

## Reviewed baseline

- Review date/time: `2026-09-24 09:46 Africa/Cairo`.
- Development branch: `design-system-v2-development`.
- Exact Development HEAD before this QA-state write: `44c4324a2733d770d031862b4f207fcc18a9f2e9`.
- Active slice: `DS2-REPORT-047 — Sales shared chart-tooltip adoption`.
- Representative surface: `src/pages/reports/SalesPage.tsx` → page-local Recharts `CustomTooltip` used by both Sales charts.
- Active implementation PR: `#95 — DS2-REPORT-047: adopt shared Sales chart tooltip`.
- Feature baseline / PR base: `44c4324a2733d770d031862b4f207fcc18a9f2e9`.
- Exact PR HEAD independently reviewed and rechecked immediately before disposition: `1f0a76bd5922d90b245c11297446681d48f89d54`.
- Changed-file scope: exactly 3 files — `src/pages/reports/SalesPage.tsx`, focused `src/pages/reports/SalesPage.test.tsx`, and UI Production Engineer owned state.
- Current disposition: `AGENT-REVIEW: BLOCKED`.
- Blocker severity: `P1 / BLOCKING for GREEN-DEV` — focused test-artifact correctness.
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`; `SOURCE_REVIEW_PASS` is **not** issued while the test artifact is known-invalid.
- Executed build/test/lint/runtime/visual/preview/release PASS: not claimed.
- Current peer contradiction classification: `NONE`.

## Independent QA disposition

**BLOCKED on exact PR HEAD `1f0a76bd5922d90b245c11297446681d48f89d54`.**

The REPORT047 product implementation itself is presentation-only and source-aligned with the bounded Design direction: Sales keeps the local Recharts adapter and delegates only neutral tooltip presentation/anatomy to the already-proven shared `ChartTooltip`. No shared API/CSS/token/breakpoint or business/backend contract changed.

However, the newly authored focused Sales tooltip test contains a deterministic DOM-representation mismatch that is inconsistent with the existing shared `ChartTooltip` test contract. That makes the material-risk protection artifact invalid as written, so GREEN-DEV cannot be issued on this HEAD.

## Exact-head findings

### Scope / functional isolation — PASS

Exact PR scope:
- `src/pages/reports/SalesPage.tsx`
- `src/pages/reports/SalesPage.test.tsx`
- `team/design-system-v2/UI_IMPLEMENTATION_STATE.md`

The product diff:
- imports existing shared `ChartTooltip`;
- leaves `CustomTooltip` as the Recharts adapter with the same `!active || !payload?.length` guard;
- maps existing payload order to caller-owned `p.name`, `p.color`, `${fmt(p.value)} ج.م` and explicit `ltr` value direction;
- preserves both existing `Tooltip content={<CustomTooltip />}` integrations;
- exports the local adapter only for focused test inspection;
- does not modify shared `ChartTooltip`, shared CSS, tokens, breakpoints, `ChartPanel`, `StatePanel`, data hooks, queries, calculations, permissions, RBAC/RLS, routing, export/print, validation or backend/business semantics.

Preserved chart contracts are source-visible:
- first chart `isBlocked -> dailyLoading -> empty -> ready`, exact blocked/empty Arabic copy, Trust/Freshness and 240px geometry;
- second chart `dailyLoading -> empty -> ready`, exact empty copy and 200px geometry with no new BLOCKED/trust semantics;
- existing AreaChart/BarChart data mapping, margins, axes, gradients, series names/colors/strokes/fills/radii/`maxBarSize` remain unchanged.

### System fit / device / RTL / accessibility — PASS at source level

- Reusing shared `ChartTooltip` removes the remaining Sales page-local tooltip mini-system instead of inventing another visual grammar.
- Shared tooltip remains RTL-native, viewport-constrained, long-Arabic-wrap tolerant and caller-directed for mixed-direction values.
- Mobile 390 / Tablet 900 / Desktop 1440 share one passive tooltip grammar; no device-specific fork or breakpoint was introduced.
- Existing series colors remain caller-owned chart identity, not Design System status semantics.
- Tooltip remains informational only: no action, focus target, tab stop, role, live region or keyboard-only behavior was introduced.
- Loading/empty/blocked branches continue not to mount ready chart/tooltip content.

### Test Artifact Gate — BLOCKED

Blocking location:
- `src/pages/reports/SalesPage.test.tsx`
- test: `delegates Sales tooltip presentation to shared ChartTooltip while preserving caller label, row order, colors, currency formatting, and LTR values`

The test asserts:
- `rows.map(row => row.style.color)` equals the original payload hex strings such as `#2563eb`, `#dc2626`, `#0284c7`.

But the already-integrated shared `src/components/patterns/ChartTooltip.test.tsx` proves the same React inline-style path through the project test DOM as CSSOM-normalized RGB, e.g.:
- `#2563eb` -> `rgb(37, 99, 235)`
- `#dc2626` -> `rgb(220, 38, 38)`
- `#16a34a` -> `rgb(22, 163, 74)`

Therefore the new Sales color assertion is internally inconsistent with the established component test contract and is expected to fail when executed, even though the product implementation preserves the correct caller colors.

Minimum required fix:
- update the Sales test to assert CSSOM-normalized RGB values, including `#0284c7` -> `rgb(2, 132, 199)`, or normalize expected colors before comparison;
- do not change product code or widen shared `ChartTooltip` to satisfy the test.

Other newly authored coverage is directionally correct and protects tooltip label/order/currency/LTR semantics, both ready chart integrations at 390/900/1440, loading/empty/blocked isolation, 240px/200px geometry and existing ready chart data/series contracts.

Tests/build/lint were **not executed** in an approved exact-head project runtime. Evidence remains `TESTS_AUTHORED_NOT_EXECUTED`. No Build/Test/Lint/Runtime/Visual/Preview/Release PASS is claimed.

## Peer-state comparison / contradiction handling

This QA judgment was formed from exact PR metadata, changed filenames/patches, exact-head Sales source/test, existing shared `ChartTooltip` implementation/CSS/test contract, chart/state contracts and PR discussion before peer conclusions were used as corroboration.

- **Product Design Director:** fresh and aligned on REPORT047 scope: Sales adoption only, no shared-contract widening, preserve both chart/state/business contracts.
- **UI Production Engineer:** PR-carried state is aligned on scope/evidence but did not identify the CSSOM color-assertion defect; this is a fresh QA blocker, not a design disagreement.
- **Development Integrator / Team Memory:** lifecycle-current through REPORT046; no competing REPORT047 integration decision exists.
- **PR discussion/review threads before QA disposition:** no prior PR comments, submitted reviews or inline review threads existed.

Current contradiction classification: **NONE**. The blocker is test-artifact correctness, not cross-role disagreement.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27 and confirmed PR #95 as the single active implementation PR targeting Development.
- Inspected exact PR metadata/head/base, changed filenames and patches, exact-head Sales source/test, existing shared `ChartTooltip` implementation/CSS/test contract, Development HEAD and PR comments/reviews/threads.
- Reconfirmed immediately before disposition that PR #95 remained `OPEN / DRAFT`, exact HEAD `1f0a76bd5922d90b245c11297446681d48f89d54`, base `design-system-v2-development`, `mergeable=true`, with Development at exact feature baseline `44c4324a2733d770d031862b4f207fcc18a9f2e9`.
- Left `AGENT-REVIEW: BLOCKED` on PR #95 anchored to exact HEAD and added a material-blocker note to issue #27.
- Updated only this owned Design QA state file; peer states, Team Memory and Decision Log were not modified.
- Did not modify product code, merge, deploy, touch `main`, trigger/rerun GitHub Actions, use hosted CI or modify preview branches.

## What changed since the previous state

- REPORT046 is integrated and its prior QA approval is consumed.
- REPORT047 exact PR HEAD `1f0a76bd5922d90b245c11297446681d48f89d54` was independently reviewed.
- Disposition is `AGENT-REVIEW: BLOCKED` pending one focused test-assertion correction; no product-code redesign is required.

### Cross-role handoff
- **To:** UI Production Engineer; then Design QA for fresh exact-head re-review. Product Design/Integrator should not consume this HEAD as GREEN-DEV.
- **What changed:** QA found one deterministic focused-test defect: Sales expects raw hex from `row.style.color`, while the established shared tooltip DOM contract exposes normalized RGB.
- **Preserve:** current product implementation; shared `ChartTooltip` API/CSS/tokens unchanged; caller-owned payload order/labels/colors/currency formatting/LTR direction; both Sales tooltip integrations; first chart `isBlocked -> dailyLoading -> empty -> ready` + 240px; second chart `dailyLoading -> empty -> ready` + 200px; all data/query/trust/permission/backend/business contracts.
- **Need from you:** correct only the focused color assertion/normalization, push the minimal test fix, and hand the new exact PR HEAD back to Design QA. Any HEAD movement invalidates this review baseline and requires fresh review.
- **Blocker level:** `BLOCKING` for GREEN-DEV.
- **Baseline:** Development pre-state-write `44c4324a2733d770d031862b4f207fcc18a9f2e9`; exact reviewed PR #95 HEAD `1f0a76bd5922d90b245c11297446681d48f89d54`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`; no `SOURCE_REVIEW_PASS` or executed build/test/lint/runtime/visual/preview/release PASS claimed.
