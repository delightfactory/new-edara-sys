# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-24 05:06 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-044`.
- Latest product integration: PR #92, squash merge `a763a12538b9074e85af3f94365f8ccefc67f525`.
- Exact Development HEAD before this owned-state write: `011abb806bf66b4d792b0ce7299aef42e82d8c9b`.
- Active slice: `DS2-REPORT-045 — Customer Re-engagement responsive-list orchestration convergence`.
- Slice status: `READY — BOUNDED`.
- Active implementation PR: none at review/recheck time.
- Current Product Design disposition: `IMPLEMENTATION AUTHORIZED WITHIN BOUNDED UI-ONLY CONTRACT`.
- Current contradiction classification: `NONE`.

## Independent Product Design judgment

**REPORT045 should converge the Customer Re-engagement result collection onto the existing shared `ResponsiveCollection` orchestration contract, with an explicit Tablet card composition.**

I formed this judgment from the exact current Customer Re-engagement source/tests, the current `ResponsiveCollection` implementation/tests, the Component Decision Matrix, Device Strategy and North Star before comparing peer states.

The current ready state mounts both the Desktop table and Mobile customer-card trees, then relies on CSS at `<=768px` to hide one of them. That leaves two presentation trees for the same data capability in the mounted React structure and gives Tablet `769–1024px` the Desktop table by default. This is weaker than the documented V2 contract: one renderer per device, Mobile cards instead of compressed tables, and Tablet as a deliberate touch-first hybrid rather than accidental Desktop inheritance.

The existing shared `ResponsiveCollection` already owns exactly this concern. It selects one Mobile/Tablet/Desktop renderer, supports explicit Tablet rendering, and accepts caller-owned loading/empty nodes without moving business/data semantics into the Design System. No shared API or functional change is required.

## Bounded architecture decision

Representative surface:
- `src/pages/reports/CustomerReengagementPage.tsx` — customer-result collection only.
- `src/pages/reports/CustomerReengagementPage.test.tsx` — focused regression coverage.

Required convergence:
- consume existing `ResponsiveCollection<ReengagementRow>` unchanged;
- preserve the current dense semantic Desktop table as `renderDesktop`;
- preserve the current customer-card information/action anatomy for Mobile;
- provide an explicit Tablet renderer using the same row facts/actions in a two-column touch-first card grid at the canonical Tablet range, rather than falling back to the Desktop table;
- preserve the existing loading node (`SkeletonRows count={8}`) and filtered-empty node/copy through the collection state slots;
- remove only CSS visibility rules made obsolete by single-renderer orchestration.

This is one responsive-composition concern. It is not permission to redesign the page, extract a new domain card primitive, rework filters, output, statuses or business behavior.

## Product-design acceptance contract

### Device composition

- **Mobile 390:** only the customer-card renderer is mounted; one-column operational scanning remains; existing card facts/order, priority/recency/balance display and permission-gated 360° CTA are unchanged; Desktop table subtree is absent.
- **Tablet 900:** only an explicit two-column customer-card renderer is mounted; cards use `minmax(0, 1fr)`-safe composition/no ordinary horizontal overflow; same data order and 360° permission/route semantics; Desktop table subtree is absent.
- **Desktop 1440:** only the existing dense table renderer is mounted; existing columns, values, ordering and overflow containment remain; card subtree is absent.

### States

Preserve caller-owned precedence and meaning:
- page-level `listError` / unauthorized handling remains untouched;
- collection state remains `loading -> empty -> ready`;
- loading remains exactly eight existing skeleton rows;
- empty retains exact title `لا يوجد عملاء يطابقون الفلاتر المحددة` and exact hint `جرّب تغيير الفلاتر أو إلغاء تفعيل «النشطون فقط»`;
- no StatePanel/empty-state redesign is part of REPORT045.

### RTL / Arabic / accessibility / interaction

- no new fixed-width/truncation or ordinary-horizontal-overflow source;
- preserve existing mixed Arabic/Latin direction handling;
- eliminate duplicate hidden interactive descendants by mounting one ready renderer only;
- customer 360° links remain native keyboard-focusable links, permission-gated exactly as today, with unchanged `/customers/:id` destinations;
- existing Mobile CTA minimum 44px contract must not regress;
- no nested clickable surface, live region, focus trap or new action semantics.

## Explicit exclusions / invariants

Do not change:
- `KpiStrip`, `MetricGrid`, `StatCard`, PageHeader or summary meaning/loading;
- `FilterBar`, `useFilterState`, filter URL sync/stats/query inputs;
- export/print action, `ExportDrawer`, document-output/CSV/360° export behavior or overlay semantics;
- page-level unauthorized/error copy or error semantics;
- priority classification/tone mapping, recency/balance meaning, row ordering, result limit or Customer 360 permission checks/routes;
- Desktop table facts/columns/actions or customer-card facts/actions;
- pagination/infinite-query behavior;
- shared `ResponsiveCollection` implementation/API/CSS/tokens/device breakpoints;
- Overview navigation-card debt or any other Reports page;
- analytics/query/cache/calculation/date/filter/trust/permission/RBAC/RLS/routing/export/print/backend/business/workflow semantics.

If implementation reveals a need for any shared-contract or functional widening above, REPORT045 becomes `BLOCKED` and returns to Product Design for re-bounding.

## Evidence expectations

Focused tests must protect:
- 390 / 900 / 1440 renderer selection with exactly one ready renderer mounted per mode;
- explicit Tablet renderer rather than Desktop fallback;
- loading and empty state precedence/copy without ready renderer mounting;
- enough row/action assertions to prove device compositions preserve data order and permission-gated 360° route semantics;
- all existing KPI convergence regression coverage.

Evidence remains `TESTS_AUTHORED_NOT_EXECUTED` unless an approved exact-head local runtime actually executes tests. Hosted GitHub Actions remain forbidden and Vercel preview remains owner-requested only.

## Peer-state synthesis / contradiction handling

After forming the independent judgment:

- **Team Memory:** current and aligned that REPORT044 is integrated and REPORT045 was awaiting one smallest Product Design boundary. Its unbounded wording is now lifecycle-superseded by the Workstream/Director boundary, not contradictory.
- **Development Integrator:** current and aligned; REPORT044 is merged and REPORT045 is the sole next item for Product Design bounding.
- **UI Production Engineer:** historical REPORT044 state; no REPORT045 implementation exists yet and no conflicting constraint is recorded.
- **Design QA:** historical REPORT044 exact-head approval; no REPORT045 disposition exists yet and no conflicting blocker is recorded.
- **Decision Log / North Star / Component Decision Matrix / Device Strategy:** aligned with UI-only functional isolation, shared-system-before-local-invention, one-renderer responsive collection orchestration and deliberate Mobile/Tablet/Desktop composition.
- **Open PR recheck:** no open PR targets `design-system-v2-development`; there is no competing implementation slice.

Current contradiction classification: `NONE`.

## Repository actions / what changed this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, current Development HEAD, open PRs targeting Development, representative report source/tests, shared `ResponsiveCollection` source/tests and relevant component/device/migration docs.
- Bounded REPORT045 in the Workstream as `READY — BOUNDED` with explicit scope, exclusions, device/state/accessibility acceptance and evidence expectations; boundary commit `011abb806bf66b4d792b0ce7299aef42e82d8c9b`.
- Did not update `TEAM_MEMORY.md`; the overall North-Star/system direction did not change, only the next slice was decomposed.
- Did not update `DECISION_LOG.md`; no durable decision changed.
- Did not modify product code or peer role states, merge a PR, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after a stable Draft PR exists.
- **What changed:** REPORT045 is now `READY — BOUNDED` to converge only the Customer Re-engagement result collection onto existing `ResponsiveCollection`, with Desktop table / explicit two-column Tablet cards / Mobile cards and single-renderer mounting.
- **Preserve:** existing row order/facts; Desktop columns; customer-card facts/actions; exact loading/empty copy and state precedence; 360° permission checks/routes; KPI/filter/export/error/query/business contracts; unchanged shared `ResponsiveCollection` API/CSS/tokens/breakpoints; no `main`/Vercel/hosted-CI activity.
- **Need from you:** branch from the exact latest Development HEAD, implement REPORT045 only, author focused 390/900/1440 + loading/empty + permission/action regression tests, and open one Draft PR targeting `design-system-v2-development`. Stop and mark `BLOCKED` if shared-contract or functional widening is required.
- **Blocker level:** `NONE`.
- **Baseline:** Development `011abb806bf66b4d792b0ce7299aef42e82d8c9b`; no implementation PR exists at handoff.
