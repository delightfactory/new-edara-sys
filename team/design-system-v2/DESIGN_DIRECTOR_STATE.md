# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-23 16:58 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-038`.
- Integrated product merge: `5325d99fcc3d047f1fc6aa3dac39a5423d9376e4` from PR #86.
- Exact latest Development HEAD before Product Design bounding: `2b11afacf0a5871859a53a461bc46db048d78dec`.
- Workstream boundary commit created this run: `08797bcfb83731edfb021ca3e6e93375a2dc2b9c`.
- Open implementation PRs targeting Development at selection time: `0`.
- Current single READY slice: `DS2-REPORT-039 — Geography responsive-detail empty-state convergence`.
- Representative surface: `src/pages/reports/GeographyPage.tsx` → `ResponsiveCollection` under `التوزيع حسب {LEVEL_LABELS[level]}` → empty branch only.
- Current disposition: `READY — BOUNDED`.
- Current contradiction classification: `NONE`.

## Independent Product Design judgment

**REPORT039 is correctly bounded to the Geography responsive-detail empty branch only.**

I formed this judgment from the exact post-REPORT038 Development source before comparing peer states. Geography is already materially converged onto the V2 report grammar: shared `MetricGrid`, shared `Select`, `ResponsiveCollection`, `Card`, `KeyValueList`, semantic Desktop table headers and Trust/Freshness are in place. The remaining local inconsistency in this surface is the collection empty branch, which still recreates state typography/spacing as a bespoke page-local block.

The existing `ResponsiveCollection` contract already solves this concern without any shared change: when `emptyState` is omitted it renders the shared passive compact `StatePanel kind="empty"`, and it exposes `emptyTitle` specifically so the caller can preserve domain copy. Therefore the smallest system-coherent change is to remove only the bespoke Geography empty renderer, pass the exact existing Arabic copy through `emptyTitle`, and leave every data, filter, heatmap, trust and ready-renderer contract caller-owned.

I also inspected the adjacent Churn Risk report, which contains a similar local empty branch, but Geography is the safer next proof because it has no separate BLOCKED branch to preserve or reinterpret. That makes Geography the smaller dependency-safe concern and avoids combining state-semantics work with presentation convergence.

## REPORT039 bounded acceptance

### Shared-system intent

- Replace only the custom Geography collection empty block.
- Use `ResponsiveCollection`'s existing built-in empty renderer via `emptyTitle="لا توجد بيانات — شغّل watermark sweep أولاً"`.
- The built-in renderer remains the existing passive compact `StatePanel kind="empty"`.
- Do not import or create a new page-local state primitive and do not widen `ResponsiveCollection` / `StatePanel`.

### State / device acceptance

- Preserve exact collection precedence: `tableLoading -> empty -> ready renderer`.
- Loading remains exactly five `SkeletonCard height={44}` rows for the detail collection.
- Existing summary loading remains intact, including the current two-card `MetricGrid columns={2}` / 160px skeleton behavior when the page loading contract requires it.
- Empty mounts no ready renderer on any device.
- Desktop ready state preserves the dense semantic table.
- Tablet ready state preserves two-column `Card + KeyValueList` composition.
- Mobile ready state preserves one-column `Card + KeyValueList` composition and no ordinary table overflow.
- Exactly one ready renderer remains mounted per device through `ResponsiveCollection`.

### Arabic / accessibility / hierarchy acceptance

- Preserve exact Arabic copy: `لا توجد بيانات — شغّل watermark sweep أولاً`.
- Empty remains passive: no action slot, click handler, keyboard/focus target or live announcement.
- Shared StatePanel anatomy owns state hierarchy/spacing; the page must not reproduce state color/type rules locally.
- No new fixed-width text, truncation or overflow source is introduced.
- Existing long Arabic geography/parent wrapping remains unchanged.

### Data / ready-renderer invariants

Preserve unchanged:
- geography level labels and controlled level selector values;
- ReportFilterBar/date semantics;
- hooks, query/cache semantics and filters;
- all row ordering and row facts;
- conditional parent table column / card item behavior by level;
- parent fallback `—`;
- net revenue, customer count, transaction count and revenue-share formatting;
- LTR numeric/currency/percentage presentation;
- heatmap `maxRev` / opacity / zero-row treatment and current hover behavior;
- TrustStateBadge / FreshnessIndicator presence and meaning;
- summary KPI cards and metric calculations.

## Explicit exclusions / stop rule

Out of scope for REPORT039:
- summary KPI redesign or MetricCard changes;
- geography query/filter/date/business semantics;
- heatmap semantics or calculation changes;
- ready Desktop/Tablet/Mobile renderer redesign beyond regression protection;
- Trust/Freshness semantics;
- shared `ResponsiveCollection`, `StatePanel`, `Card`, `KeyValueList`, `MetricGrid`, `Select`, CSS, token or breakpoint changes;
- permissions/RBAC/RLS/routing/export/print/backend/workflow/business changes;
- any second report surface.

If any excluded shared or functional change proves necessary, REPORT039 becomes `BLOCKED` rather than widening the implementation PR.

## Focused test expectation

Update the existing `GeographyPage.test.tsx` only as needed to protect the material risks:
- shared empty `StatePanel` anatomy is rendered through the collection contract;
- exact Arabic copy is preserved;
- compact/passive semantics are preserved with no action/live/focus target;
- loading remains ahead of empty with exactly five 44px detail skeletons;
- ready table/card renderers do not mount during loading or empty;
- existing Desktop/Tablet/Mobile ready-state assertions, conditional parent truth, wrapping, LTR values, Trust/Freshness and summary contracts remain green as authored artifacts.

Evidence must remain `TESTS_AUTHORED_NOT_EXECUTED` unless an approved runtime actually executes the exact implementation HEAD. No hosted CI or preview may be used by the normal autonomous loop.

## Peer-state synthesis / contradiction handling

After forming the independent judgment:

- **Team Memory:** current through REPORT038 and explicitly hands REPORT039 to Product Design for one smallest presentation-only bound; aligned.
- **Development Integrator:** current through REPORT038 integration and likewise requires Product Design bounding before implementation; aligned.
- **UI Production Engineer:** lifecycle-stale on the now-integrated REPORT038 implementation; no REPORT039 implementation exists and no competing PR is open.
- **Design QA:** lifecycle-stale on the consumed REPORT038 exact-head review; no REPORT039 judgment exists yet.
- **Previous Product Design state:** lifecycle-stale because it still describes REPORT038 before integration; superseded by this state.
- **North Star / test policy / communication protocol / Component Decision Matrix / Device Strategy / Migration Matrix:** aligned with consolidating one collection-state mini-system onto existing shared presentation while keeping business truth caller-owned.
- **Decision Log:** no durable decision changes; no update warranted.

Current contradiction classification: `NONE`.

## What changed since previous Product Design state

- REPORT038 completed integration and the queue advanced to REPORT039.
- No implementation PR is active.
- REPORT039 moved from roadmap placeholder / Product Design bounding required to exactly one bounded implementation concern: Geography responsive-detail empty-state convergence.
- Implementation is now authorized only within the recorded boundary.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, exact latest Development HEAD and open PRs targeting Development.
- Inspected relevant component/migration/device architecture documents and current shared `StatePanel` / `ResponsiveCollection` contracts.
- Independently inspected representative remaining Reports surfaces, including Geography and Churn Risk, and selected Geography as the smaller dependency-safe concern.
- Inspected current Geography source and focused test artifacts.
- Updated `31_AGENT_TEAM_WORKSTREAM.md` to bound REPORT039; workstream commit `08797bcfb83731edfb021ca3e6e93375a2dc2b9c`.
- Updated only this owned specialist state file after that boundary.
- Did not modify Product code, peer specialist states, Team Memory or Decision Log.
- Did not merge, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer; then Design QA and Product Design Director for independent exact-head review after implementation.
- **What changed:** `DS2-REPORT-039 — Geography responsive-detail empty-state convergence` is now `READY — BOUNDED` on the post-REPORT038 Development baseline.
- **Preserve:** exact empty copy; `tableLoading -> empty -> ready` precedence; five 44px detail loading skeletons; current summary loading; dense Desktop table; Tablet two-column cards; Mobile one-column cards; one ready renderer per device; conditional parent truth/fallback; long Arabic wrapping; LTR numeric presentation; heatmap behavior; Select + ReportFilterBar; Trust/Freshness; all query/filter/business/shared contracts.
- **Need from you:** start from the latest Development HEAD, implement only the Geography collection empty branch using the existing `ResponsiveCollection` built-in empty contract (`emptyTitle` -> passive compact shared `StatePanel`), update focused Geography tests, and open exactly one PR targeting `design-system-v2-development`. Stop as `BLOCKED` if any shared-contract or functional widening is required.
- **Blocker level:** `NONE`.
- **Baseline:** pre-bound Development HEAD `2b11afacf0a5871859a53a461bc46db048d78dec`; workstream boundary commit `08797bcfb83731edfb021ca3e6e93375a2dc2b9c`; current slice `DS2-REPORT-039`.