# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-19`.
- Authoritative branch: `design-system-v2-development`.
- Development HEAD immediately before this Director-state write: `c08947b512c2a1995424283c1acc6f5e2405fbb2`.
- Latest integrated product slice: `DS2-REPORT-002 — Report date-preset selector convergence`, PR #49, squash merge `cc91792263d9fc606b9c2f28a531daa826997c75`.
- Open implementation PRs targeting Development at the pre-write check: `NONE`.
- Active slice: `DS2-REPORT-003 — Report custom-date field convergence`.
- Product Design disposition: `READY — DEPENDENCY-SAFE PRESENTATION BOUNDARY RECORDED`.
- No runtime/build/test/lint/preview/release PASS is claimed.

## Independent Product Design judgment

**The next smallest system-level concern is the remaining custom-date editor inside `ReportFilterBar`, and it is safe to activate as `DS2-REPORT-003`.**

The exact Development source still renders the report range's `from` and `to` editors as two raw, inline-styled `<input type="date">` controls. Their visual contract is local to Reports: local padding, radius, border, background, text size/family and removed native outline. They also do not currently expose independent programmatic Arabic names; the adjacent calendar icon and em dash are presentation cues rather than sufficient field naming.

This is not a reason to redesign Reports or move date meaning into the Design System. It is a proven shared-field gap. The V2 component architecture already declares `DateField / DateTimeField` as form composites, and the decision matrix explicitly directs date variants to compose the shared `Field` system. Current `Input` already composes `Field`, uses canonical `.form-input`, forwards native input props and accessible Field metadata, while V2 form CSS owns standard/touch control heights.

Therefore the correct boundary is one shared, domain-agnostic `DateField` presentation composite plus adoption by the two custom date controls in `ReportFilterBar`. `DateField` may own native date-input presentation and Field/Input accessibility plumbing only. Reports must continue to own every range, preset, normalization, local-date, query and analytics semantic.

## System-pattern intent

REPORT003 must reduce independent visual implementations rather than beautify one page:
- establish the blueprint-declared V2 `DateField` from the existing Field/Input grammar;
- retain native `<input type="date">` behavior instead of introducing a custom calendar/date picker;
- make the shared system own control surface, semantic tokens, typography, focus/invalid/disabled treatment, standard geometry and touch geometry;
- give each report date editor an independent Arabic accessible name (`من تاريخ` / `إلى تاريخ`) so meaning does not depend on icon position, separator or color;
- allow the ReportFilterBar date-pair composition to wrap/stack deliberately on constrained widths without creating a Reports-only date primitive or viewport overflow.

The shared DateField must **not** parse, normalize, compare, reorder or calculate dates; it must not know about `DateRange`, presets, analytics hooks, cache keys or report routes.

## Scope / functional-isolation boundary

In scope:
- one shared `DateField` form composite built from the existing V2 `Field` / `Input` anatomy;
- migration of only the two custom native date inputs in `src/components/reports/ReportFilterBar.tsx`;
- local composition/layout adjustment only as needed to keep the date pair contained and deliberate across devices;
- removal only of obsolete raw-input visual styling made redundant by the shared contract;
- focused tests for DateField presentation/accessibility forwarding and ReportFilterBar custom-date callback behavior.

Preserve exactly:
- `ReportFilterBar` external `value: DateRange` / `onChange(DateRange)` contract;
- current `normalizeDateRange(...)` use and from/to behavior;
- current local-date/current-month/preset calculations;
- exact four REPORT002 preset labels/order/meaning and shared `SegmentedControl` behavior;
- REPORT001 `SubNav` behavior;
- all report query/cache/service/hook/calculation/metric/chart/table/export/print/permission/routing/`AnalyticsGate` truth;
- native browser date-input semantics.

Explicitly excluded:
- generic FilterBar decomposition or Mobile filter-sheet work;
- custom date picker/calendar implementation;
- timezone reinterpretation, locale parsing, new date validation or range business rules;
- metrics/charts/tables/responsive report composition, now retained as `DS2-REPORT-004` backlog;
- loading/empty/error/offline/sync report-state work;
- backend, DB/RPC, RBAC/RLS, permissions, routing, deployment, preview, hosted CI or `main` work.

If implementation cannot satisfy the visual/accessibility goal without changing date normalization, range semantics, query inputs or business meaning, REPORT003 becomes `BLOCKED` rather than widening.

## Device / RTL / accessibility acceptance

- **Desktop (`>=1025px`)**: preserve compact report-review density; shared date controls must not become arbitrary full-width fields when space is available.
- **Tablet (`769–1024px`)**: each control retains the shared touch height and the pair may wrap deliberately rather than compressing into ambiguous controls.
- **Mobile (`<=768px`)**: no page-level horizontal overflow; both date editors remain independently readable/reachable with shared touch geometry, with wrapping/stacking allowed when constrained.
- **RTL/Arabic**: `from` / `to` remain unambiguous through independent Arabic accessible names and logical flow; no physical left/right assumptions.
- **Dark mode**: consume existing semantic input tokens; no report-local hard-coded light input surface/border/text styling.
- **Focus/keyboard**: preserve native input focusability and shared visible focus treatment; no new keyboard interaction model.
- **States**: any disabled/read-only/error support forwards existing Field/Input behavior only; REPORT003 does not invent report validation/state semantics.
- **Behavior**: editing either date must still emit the same normalized `DateRange`; custom ranges must not falsely select a preset.

No `RUNTIME_VISUAL_PASS` is claimed.

## Peer-state synthesis / contradiction handling

This boundary was formed from current Development source and V2 blueprint/component contracts before applying peer conclusions.

- **Development Integrator:** current and aligned. It records REPORT002 as merged and hands the next custom-date/filter presentation concern to Product Design for exact bounding before UI implementation.
- **UI Production Engineer:** its repository state is lifecycle-stale and still describes the repaired REPORT002 PR. That staleness is non-blocking because REPORT002 is already integrated; it does not assert a competing active implementation slice.
- **Design QA:** similarly lifecycle-stale on the final REPORT002 exact-head review. Its shared-system-first and evidence-honesty conclusions remain compatible with this next boundary; it has no current REPORT003 blocker.
- **Previous Director State:** superseded. It closed REPORT002 and intentionally left the two custom date inputs for a later bounded date-field slice; REPORT003 is that bounded follow-on.
- **Team Memory / Decision Log:** no durable design rule changes. This slice applies the existing Field-system, shared-component-first, Mobile/touch, RTL/Arabic and functional-isolation rules, so no mutation is warranted.

There is **no material cross-role contradiction blocking REPORT003 activation**.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap from `design-system-v2-development` in the required order.
- Inspected issue #27, current Development HEAD, open PRs targeting Development, exact `ReportFilterBar` source, representative Reports consumers, shared `Field` / `Input` contracts, V2 form CSS, component blueprint and decision matrix.
- Confirmed there was no open implementation PR before activation.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` to make exactly one implementation-ready slice: `DS2-REPORT-003 — Report custom-date field convergence`, commit `c08947b512c2a1995424283c1acc6f5e2405fbb2`.
- Deferred metrics/charts/tables responsive composition to `DS2-REPORT-004` rather than mixing it into the date-field slice.
- Did not implement product code, modify peer specialist states, merge, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.
- Did not update Team Memory or Decision Log because no durable system direction changed.

### Cross-role handoff
- **To:** UI Production Engineer first; Design QA after a stable PR HEAD; Development Integrator after same-head QA + Product Design gates.
- **What changed:** Product Design bounded and activated exactly one next slice, `DS2-REPORT-003 — Report custom-date field convergence`: establish a shared presentation-only V2 `DateField` from existing Field/Input grammar and migrate only the two custom date inputs in `ReportFilterBar`.
- **Preserve:** external `DateRange value/onChange`; `normalizeDateRange(...)`; local-date/current-month/preset calculations; exact four REPORT002 presets and shared SegmentedControl; REPORT001 SubNav; all report query/cache/service/calculation/metric/chart/table/export/print/permission/routing/`AnalyticsGate` truth; native date input semantics; no custom calendar/date picker.
- **Need from you:** UI Production Engineer should open one PR from the latest `design-system-v2-development` HEAD and implement only REPORT003, including focused DateField + ReportFilterBar behavior/accessibility tests. Do not start REPORT004 or generic FilterBar work. Design QA and Product Design should wait for one stable exact PR HEAD.
- **Blocker level:** `NONE`.
- **Baseline:** Development immediately before this state write `c08947b512c2a1995424283c1acc6f5e2405fbb2`; latest integrated product merge `cc91792263d9fc606b9c2f28a531daa826997c75`.
- **Evidence:** source/architecture inspection only; no executed build/test/lint/runtime/preview/release PASS claimed.
