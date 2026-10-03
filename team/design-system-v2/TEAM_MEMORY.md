# Design System V2 — Team Memory

## Current truth

- Authoritative integration branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-052 — Target Attainment shared chart-tooltip adoption`.
- Latest product integration: PR #103, reviewed HEAD `c6d3f940e69451b0e80e68cc17dbc7c7c9bbd5ab`, squash merge `0c858b7b71ae1142f53cf7a152533f94ca7d8a13`.
- Current single active implementation slice: `DS2-REPORT-053 — Visit Reports filter-field convergence` (`REVIEW — BOUNDED`) on Draft PR #104.
- Exact REPORT053 PR HEAD: `02d17d9adcb79ff15b5cbd6b1546c80d1e7b0da5`.
- Product Design disposition on that exact HEAD: `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Fresh same-head Design QA is still pending; no REPORT053 `AGENT-REVIEW: GREEN-DEV` exists yet and integration is not authorized.
- Development coordination baseline observed before this memory reconciliation: `103708dfc1fc55bf0af8c775d83ed165a5c7518f`.
- PR #101 (`ci: validate explicit final candidates on DS2 development`) remains a separate governance/CI Draft and does not overlap the REPORT053 product surface.
- `main` remains frozen until explicit owner approval.
- Vercel preview remains user-requested only.
- Hosted GitHub Actions remain forbidden for normal Design System development under the currently integrated policy.
- Product target remains one complete, premium, Arabic-first operational Design System across Mobile, Tablet and Desktop.

## Current integrated system

Development includes:
- semantic foundations and V2 primitives/patterns;
- responsive shell/navigation/form/collection/action composition foundations;
- Dashboard V2 and representative Customers, Sales, Inventory, Procurement, Finance, HR, Field and Work migrations;
- Reports route/date/filter convergence;
- shared `ChartPanel`, `ChartTooltip`, `MetricGrid`, `StatePanel`, `AlertPanel`, `SectionHeader`, Field controls and responsive collection grammar;
- shared `ChartTooltip` adoption in Receivables, Sales, Treasury, Product Performance, Rep Performance, Churn Risk and Target Attainment while each caller retains chart-library/domain/business semantics.

## Latest completed slice

`DS2-REPORT-052 — Target Attainment shared chart-tooltip adoption`

Result:
- exact reviewed PR #103 HEAD `c6d3f940e69451b0e80e68cc17dbc7c7c9bbd5ab`;
- `AGENT-REVIEW: GREEN-DEV + SOURCE_REVIEW_PASS`;
- Product Design `PASS — NO DESIGN-SYSTEM BLOCKER`;
- bounded focused evidence: 23/23 tests and focused source-closure TypeScript PASS;
- squash merge `0c858b7b71ae1142f53cf7a152533f94ca7d8a13`;
- Target Attainment now delegates tooltip presentation/anatomy to shared `ChartTooltip` while preserving caller payload interpretation, representative heading, percentage formatting, threshold colors, LTR values, chart geometry, presence, Trust/Freshness and business semantics;
- full Reports source inventory found no remaining chart-tooltip adoption candidate in the audited Reports TSX set, so that bounded tooltip-adoption track is closed;
- no full-app build/lint/runtime/visual/release qualification is inferred.

## Current active slice

`DS2-REPORT-053 — Visit Reports filter-field convergence`

Current lifecycle:
- Status: `REVIEW — BOUNDED`.
- Draft PR: #104 targeting `design-system-v2-development`.
- Exact HEAD: `02d17d9adcb79ff15b5cbd6b1546c80d1e7b0da5`.
- PR is currently open, draft and mergeable; four changed files only.
- Product Design exact-head review: `PASS — NO DESIGN-SYSTEM BLOCKER`.
- Design QA exact-head review: pending.

System intent:
- converge only the six Visit Reports native filter selectors onto existing shared `Select`/`Field`;
- remove only the obsolete page-local label/select rules inside `.visit-report-filter-grid`;
- do not widen shared component APIs or create a new filter primitive.

Preserve exactly:
- Arabic labels, option text/order/values and empty-string “all” options;
- six controlled filter states, setters and every `resetPage()` call;
- empty-string to `undefined` conversion in the existing caller filter object;
- tab-specific visibility and clearing rules;
- date range, query keys/functions/enabled conditions, page size 25, `exceptionsOnly`, employee/branch lookups, export permission/payload and survey-specific selectors;
- loading/error/empty/ready report composition and all backend/business semantics;
- existing responsive grid composition across Mobile/Tablet/Desktop;
- native select keyboard/focus behavior, one associated visible label per control and shared V2 standard/touch sizing.

Evidence boundary:
- baseline focused suite: 8/8 PASS;
- candidate focused suite: 22/22 PASS;
- focused source-closure TypeScript PASS;
- no full-app build/lint PASS and no browser/runtime visual/RTL/overflow PASS.

## Latest role positions

### Product Design Director
- REPORT053 is aligned with the North Star and the Reports/Analytics filter-grammar roadmap.
- Exact-head disposition: `PASS — NO DESIGN-SYSTEM BLOCKER`.
- No competing implementation slice should start while PR #104 remains active.
- Automatic Vercel Preview presence is governance `WATCH` only and is not accepted runtime/visual evidence.

### UI Production Engineer
- REPORT053 product/test artifact is published on PR #104.
- Shared `Select`/`Field` is unchanged; only the six filters and two obsolete local CSS rules are touched in product code.
- Bounded focused execution evidence is recorded; full-app/lint/runtime evidence remains unqualified.

### Design QA
- Repository state still records consumed REPORT052 approval and is stale for REPORT053.
- Fresh exact-head review of PR #104 HEAD `02d17d9...` is required before integration.

### Development Integrator
- Repository state correctly closes REPORT052 but predates REPORT053.
- For REPORT053, Integrator must wait for same-head `GREEN-DEV`, then revalidate exact HEAD/base/mergeability/drift/scope/review threads and functional isolation before any Development-only merge.

## Invariants to preserve

- UI work must not alter business behavior or backend contracts.
- Shared visual primitives/patterns own presentation and interaction mechanics, never business eligibility, calculations, workflow or state-machine meaning.
- `Select` remains the approved native selector for small stable option sets; `Field` owns label/help/error relationships and shared field anatomy.
- `ChartTooltip` owns presentation/anatomy only; callers retain chart-library payload interpretation, domain labels/order, value formatting/direction, series colors, data, trust and business meaning.
- `ChartPanel` owns neutral analytical surface/frame and section hierarchy only.
- `ResponsiveCollection` owns device renderer selection/orchestration and generic collection states only.
- Mobile is primary operational; Tablet is deliberate touch-first; Desktop preserves dense management/review workflows.
- Arabic/RTL and long real-world values are first-class acceptance conditions.
- Durable decisions belong in the Decision Log; routine progress belongs in role states / Team Memory / issue #27.
- No normal hosted CI, Vercel preview or `main` activity from scheduled agents.

## Known evidence / risks

- REPORT053 still lacks fresh same-head Design QA; this is the next real gate.
- PR #104 is behind current Development only by coordination/state documentation; current comparison shows no overlap with its product/test files.
- A Vercel bot created a Preview for PR #104 despite `DS2-DEC-004 — Manual preview only`. Product Design did not trigger or use it as evidence. Treat as governance `WATCH`, not runtime/visual qualification.
- PR #101 remains separate governance work and must not be used to trigger normal hosted CI or broaden REPORT053.
- Runtime visual acceptance remains milestone-based and owner-requested.
- Remaining Reports/Analytics convergence still includes filter/search grammar, dense tables, state/error/offline convergence, export/print and other bounded shared-pattern adoption.
- Settings/Admin and global Dark/RTL/accessibility/legacy cleanup remain future roadmap phases.

## Reusable patterns learned

- Repeated page-local form-control grammar should converge onto existing shared `Select`/`Field` when the native control contract already fits; do not invent a new page-local selector or widen shared APIs unnecessarily.
- Form convergence must preserve caller-owned query/filter semantics, state resets, permission/export behavior and tab-specific eligibility.
- Simulated viewport tests are source/DOM evidence only, not runtime visual geometry proof.
- A representative proof consumer is preferable to mass migration.
- Shared state presentation must not homogenize caller-owned state truth.
- Agent communication remains: independent judgment -> peer-state comparison -> structured handoff -> synthesis/integration.

## Next handoff

Design QA should perform a fresh independent exact-head review of PR #104 HEAD `02d17d9adcb79ff15b5cbd6b1546c80d1e7b0da5` and record evidence honestly. If and only if that exact HEAD receives `AGENT-REVIEW: GREEN-DEV`, Development Integrator should perform the final Development-only integration checks. No second product slice should start before REPORT053 is resolved.
