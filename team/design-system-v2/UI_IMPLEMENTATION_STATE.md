# UI Implementation State

## Reviewed baseline

- Run date/time: `2026-09-24 19:16 Africa/Cairo`.
- Development branch: `design-system-v2-development`.
- Exact feature baseline / Development HEAD at branch creation: `a5fe116aa3bda27b0ddc71cb60c4b1cf458d7122`.
- Active slice: `DS2-REPORT-051 — Churn Risk shared chart-tooltip adoption`.
- Feature branch: `ds2-report-051-churn-risk-chart-tooltip-adoption`.
- Draft PR: not opened yet.
- Disposition: `IN_PROGRESS`.
- Evidence: `TESTS_AUTHORED_NOT_EXECUTED`.
- Build/test/lint/runtime/preview/release PASS: not claimed.

## Independent implementation judgment

REPORT051 is a narrow presentation-only convergence. The existing Churn Risk pie chart already has the correct business/data/trust contract; the only duplicated concern is Recharts' default tooltip presentation.

The correct implementation is to add a caller-owned Churn Risk tooltip adapter that keeps the active/payload guard, segment/category heading, exact one-row label `عملاء`, existing `FMT` count formatting, caller-provided pie color and explicit LTR numeric direction in the page, while delegating only passive RTL tooltip anatomy to the existing shared `ChartTooltip`.

No shared tooltip API/CSS/token/breakpoint change is required.

## Material progress this run

- Completed the mandatory shared-memory bootstrap and inspected issue #27, current Development HEAD and all open PRs targeting Development.
- Formed implementation judgment from the current Churn Risk source/tests and shared `ChartTooltip` contract before peer-state comparison.
- Confirmed no implementation PR targets `design-system-v2-development`.
- Confirmed the current Workstream at Development HEAD `a5fe116aa3bda27b0ddc71cb60c4b1cf458d7122` bounds REPORT051 to the Churn Risk pie tooltip only.
- Created this feature branch from that exact Development HEAD.
- Peer states are lifecycle-stale on merged REPORT050, but contain no conflicting design or functional rule. The newer Workstream boundary is authoritative for the current slice.

## Scope / preservation contract

Allowed product/test scope:
- `src/pages/reports/ChurnRiskPage.tsx`;
- `src/pages/reports/ChurnRiskPage.test.tsx`;
- this owned state file.

Preserve exactly:
- chart presence rule `!statsLoading && pieData.length > 0`;
- `ResponsiveContainer width="100%" height={260}`;
- pie data/order, keys, geometry, padding, five caller colors and Legend;
- ChartPanel title and Trust/Freshness action behavior;
- report filters, KPI summary, responsive detail collection/table/cards and blocked/loading/empty precedence;
- all hooks/query/cache/RPC/Supabase/calculation/trust/permission/RBAC/RLS/routing/validation/backend/business semantics.

Excluded:
- shared `ChartTooltip` implementation/API/tests/CSS/tokens/breakpoints;
- Target Attainment or any other report tooltip;
- any other shared pattern or product surface.

## Device / state / accessibility target

- Mobile 390 / Tablet 900 / Desktop 1440: same shared RTL passive tooltip grammar.
- Long Arabic category text must remain contained/wrappable.
- Count value remains explicit LTR/bidi-safe.
- Tooltip stays informational only: no focus target, tab stop, role, aria-live or keyboard/action semantics.
- No chart/tooltip surface is added during stats loading or when all pie values are zero.

## Evidence / execution honesty

Evidence remains `TESTS_AUTHORED_NOT_EXECUTED` until an approved local project runtime actually executes tests/build/lint. Hosted GitHub Actions and Vercel are forbidden and will not be used.

## Risks / blocker status

- UI blocker: `NONE`.
- Product Design Director / Design QA / Integrator state files are stale on REPORT050, but the current Workstream boundary commit is newer and introduces no contradiction with their durable rules.
- If the existing shared `ChartTooltip` cannot serve unchanged, REPORT051 must be marked `BLOCKED` rather than widening scope.

### Cross-role handoff
- **To:** UI Production Engineer continuation in this same slice.
- **What changed:** REPORT051 branch created from exact Development HEAD and bounded implementation contract recorded.
- **Preserve:** all contracts listed above; shared `ChartTooltip` unchanged.
- **Need from you:** implement only the Churn Risk tooltip adoption, author focused tests, then open one Draft PR to `design-system-v2-development`.
- **Blocker level:** `NONE`.
- **Baseline:** `a5fe116aa3bda27b0ddc71cb60c4b1cf458d7122`.
