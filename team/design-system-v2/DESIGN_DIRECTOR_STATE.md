# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-23 02:01 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD inspected immediately before this state write: `70b11522aadea90e3300944e32d788729e7d765a`.
- Latest integrated product slice: `DS2-REPORT-030 — Rep Performance summary metric-grid convergence`, merge `b5f3d49cbc2f68431573174ee2b653b269ee5d2c`.
- Active slice: `DS2-REPORT-031 — Customer Health as-of-date field convergence`.
- Active implementation PR: `NONE`.
- Product Design disposition: `READY — BOUNDED`.
- Workstream bounding commit: `70b11522aadea90e3300944e32d788729e7d765a`.

## Independent Product Design judgment

**REPORT031 should converge only the Customer Health report-header as-of-date control onto the existing shared V2 `DateField -> Input -> Field` grammar.**

Fresh source review shows `CustomerHealthPage.tsx` is already substantially converged: its three KPI cards use `MetricGrid columns={3}`, its details use `ResponsiveCollection + Card + KeyValueList` for Tablet/Mobile while retaining a semantic five-column Desktop table, and its trust/loading/blocked/empty behavior already has focused regression coverage. The remaining header date control is still a page-local `<label>` plus styled native `<input type="date">`.

The repository already contains the exact domain-agnostic primitive needed: `DateField` owns date-control presentation and accessible Field plumbing while explicitly leaving parsing, normalization, range ordering and business meaning to the caller. REPORT027 also established the same report-header `DateField label="بتاريخ:"` composition on Churn Risk. The Component System and Control/Form contracts prohibit a page-local replacement when an approved shared primitive exists.

This is smaller and safer than widening `MetricGrid` for Churn Risk or Customer Re-engagement's five-card summaries. Those five-card surfaces remain legitimate follow-up debt but are explicitly outside REPORT031 because their shared-layout contract needs a separate design decision.

## Exact bounded contract

Representative product/test surface:
- `src/pages/reports/CustomerHealthPage.tsx`
- `src/pages/reports/CustomerHealthPage.test.tsx`

Implementation boundary:
- replace only the local `بتاريخ:` label + native date-input presentation with shared `DateField`;
- preserve `value={asOfDate}`, `max={today}` and `onChange={e => setAsOfDate(e.target.value)}` exactly;
- preserve the existing `today` derivation and initial `asOfDate` state exactly; REPORT031 does not redefine date/timezone semantics;
- preserve `useCustomerHealthSummary({ asOfDate })` propagation exactly;
- preserve the surrounding report-header title/subtitle and responsive wrapping behavior;
- do not change any shared component API, CSS, token or breakpoint.

Acceptance:
- the date control has the programmatic accessible label `بتاريخ:` through shared Field anatomy;
- it remains a native `type="date"` input and keeps the same max/value constraint;
- changing the date reaches `useCustomerHealthSummary` with the same caller-owned value;
- shared Field/control sizing remains readable on Desktop and touch-safe on Tablet/Mobile without new ordinary horizontal overflow or Arabic-label clipping;
- existing Customer Health summary remains `MetricGrid columns={3}` with the exact three KPI cards and three 150px loading skeletons;
- existing blocked-state priority, Desktop table, Tablet two-column cards, Mobile one-column cards, five 44px detail skeletons, trust/freshness actions, long-Arabic wrapping, LTR numeric values, fallback identity and exact empty/footer copy remain unchanged;
- focused tests cover shared Field/date-control adoption, accessible labeling, native date type, max/value preservation and date-change hook propagation while preserving all existing responsive/detail tests.

## Explicit exclusions / functional isolation

REPORT031 must not change:
- `DateField`, `Input`, `Field`, shared CSS/tokens/breakpoints or any other shared primitive;
- KPI cards, summary layout, detail table/cards, state priority, trust/freshness or status visual grammar;
- customer-health hooks, query/cache/calculation, snapshot/watermark semantics, permissions/RBAC/RLS, routing, backend/business logic, export/print, deployment or preview behavior;
- Churn Risk five-KPI or Customer Re-engagement five-KPI layout contracts.

If the bounded replacement proves to require any shared-contract or functional/date-semantics change, UI Production must mark REPORT031 `BLOCKED` rather than widen the PR.

## Device / accessibility intent

- **Desktop:** retain the current compact management header and existing dense report/detail composition; shared DateField supplies the same control family as other V2 report headers.
- **Tablet:** retain touch-first sizing and wrapping; no forced one-line header or new horizontal scroll.
- **Mobile:** the date control must remain usable at the shared Field touch height with a readable Arabic label; the rest of Customer Health's one-column detail composition is untouched.
- **RTL / mixed content:** Arabic label remains source/reading-order correct; native date value remains browser-owned and no bidi/date-format semantics are introduced by the slice.
- **Keyboard/accessibility:** Field must programmatically associate the label with the native date input; no new custom interaction model is introduced.

## Peer-state synthesis / contradictions

I formed the Product Design judgment from the current Customer Health and Churn Risk source, existing Customer Health tests, shared `DateField`/`Input` contract and current component/device/report guidance, then compared peer states.

- Development Integrator is lifecycle-current through REPORT030 and explicitly handed REPORT031 to Product Design for exact bounding.
- UI Implementation state remains lifecycle-stale on the already-merged REPORT030 branch and does not conflict with this new slice.
- Design QA state is lifecycle evidence for prior work, not a competing REPORT031 approval.
- Team Memory / Decision Log contain no rule contradicting reuse of the existing Field/DateField grammar.
- There is no open implementation PR targeting `design-system-v2-development` at the pre-bounding check.

Current contradiction classification: `NONE`.

## Risks / constraints to preserve

- Do not opportunistically redesign the Customer Health header or convert unrelated report surfaces in the same PR.
- Do not change date derivation/timezone semantics merely because the current helper may deserve a separate functional review.
- Do not widen shared primitives when the existing `DateField` already satisfies the bounded need.
- Tests must remain honestly labeled according to actual execution; authored coverage is not execution evidence.
- Any PR-head movement after independent review invalidates exact-head approvals and requires fresh review.

## What changed since previous Product Design state

REPORT030 has been integrated. Product Design replaced the generic REPORT031 placeholder with one exact dependency-safe presentation slice: Customer Health's local as-of-date control convergence onto existing shared `DateField`. `31_AGENT_TEAM_WORKSTREAM.md` now records scope, exclusions, device/state/accessibility acceptance and evidence intent. No durable design-system rule changed, so `TEAM_MEMORY.md` and `DECISION_LOG.md` were intentionally left unchanged. No product code, `main`, preview branch, deployment or hosted CI was touched.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** `DS2-REPORT-031 — Customer Health as-of-date field convergence` is now `READY — BOUNDED`; the only authorized product change is replacing the page-local Customer Health `بتاريخ:` native date-control presentation with existing shared `DateField`.
- **Preserve:** exact `asOfDate` state/value/max/onChange and hook propagation; existing three-KPI MetricGrid and loading; complete Desktop/Tablet/Mobile detail/state/trust contracts; unchanged shared APIs/CSS/tokens/breakpoints; all query/calculation/snapshot/permission/backend/business semantics.
- **Need from you:** start from the exact latest Development HEAD, implement REPORT031 only, add focused regression coverage for shared Field/date adoption + accessible label + native type/max/value + date-change hook propagation, update only your owned state, and open one PR targeting `design-system-v2-development`. If any shared or functional widening is required, mark the slice `BLOCKED` instead.
- **Blocker level:** `NONE`.
- **Baseline:** Development pre-state-write `70b11522aadea90e3300944e32d788729e7d765a`; workstream bounding commit `70b11522aadea90e3300944e32d788729e7d765a`.