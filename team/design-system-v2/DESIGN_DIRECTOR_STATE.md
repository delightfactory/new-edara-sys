# Product Design Director State

## Reviewed baseline

- Review date/time: `2026-09-24 01:05 Africa/Cairo`.
- Authoritative branch: `design-system-v2-development`.
- Product UI is integrated through `DS2-REPORT-042`.
- Latest product integration: PR #90, squash merge `f7479859fe5c3233c3082bad2e97c0a004213f4c`.
- Exact Development HEAD immediately before this Product Design state write: `9bed2a597392437b9389783e19f2bbfedd7ffd1b`.
- Current single READY slice: `DS2-REPORT-043 — Treasury semantic-contract notice AlertPanel convergence`.
- Slice status: `READY — BOUNDED`.
- Active implementation PR targeting Development at selection time: none.
- Product Design disposition: `IMPLEMENTATION AUTHORIZED WITHIN BOUNDARY`.
- Current contradiction classification: `NONE`.
- Build/test/lint/runtime/visual/preview/release evidence for REPORT043: not yet applicable; no implementation exists yet.

## Independent Product Design judgment

**REPORT043 should converge only the static Treasury semantic-contract information notice onto the existing shared `AlertPanel` information grammar.**

I formed this judgment from the exact latest Development baseline, current Treasury/Overview report sources and tests, existing shared `AlertPanel` / `StatePanel` / `Card` contracts, component decision matrix, migration matrix and device strategy before comparing peer states.

The current Treasury notice is a page-local information surface: custom rgba background/border/radius/padding plus an emoji information icon. Its responsibility already maps cleanly to the established shared `AlertPanel`: static semantic information with no action and no live-announcement requirement. The Design System should own that presentation/accessibility anatomy while Treasury continues to own the disclosure copy and trust/data-source meaning.

This is smaller and safer than opening the broader Reports Overview navigation-card debt, which involves interactive navigation-card semantics, arbitrary domain colors, focus/touch behavior and a potentially reusable navigation pattern. REPORT043 therefore advances shared feedback grammar without inventing a new component, widening shared contracts or turning the run into page-wide beautification.

## Bounded design direction

### Representative surface

`src/pages/reports/TreasuryPage.tsx` → the static semantic-contract notice immediately below the page header/filter area and above `SystemHealthBar`.

### System-pattern intent

- Replace only the bespoke notice surface with the existing shared `AlertPanel`.
- Use `tone="info"`.
- Keep it static/non-live: `announce` omitted/false.
- Prefer the shared default information icon; it is decorative/`aria-hidden`, while the notice text carries the meaning.
- Do not change `AlertPanel` API, CSS, tokens or breakpoints for this slice.

### Content / hierarchy acceptance

Preserve the notice in the same hierarchy position and preserve its full disclosure meaning, including the exact technical literals:
- `مطابق لسجلات الخزينة`
- `vault_transactions / custody_transactions`
- `net_cashflow`

The technical literals must retain inline code treatment. Do not rewrite the business/trust definition, data-source meaning or audit disclaimer merely to fit the component.

### Device / RTL / accessibility acceptance

At representative Mobile 390, Tablet 900 and Desktop 1440:
- Arabic + Latin/code content must wrap without ordinary horizontal overflow, clipping or truncation;
- the notice remains passive: no action slot, click target or explicit focus target;
- no live-region announcement is introduced for this static explanatory content;
- icon semantics remain decorative and the textual disclosure remains sufficient without color/icon dependence.

### Explicit exclusions

REPORT043 must not change:
- Treasury chart state precedence `isBlocked -> dailyLoading -> empty -> ready`;
- current Treasury blocked/empty renderers, 280px geometry or Recharts data/margins/tooltip/series/colors;
- TrustStateBadge/FreshnessIndicator action area;
- Treasury KPI `MetricGrid` / `MetricCard` contracts;
- header/filter composition, `SystemHealthBar`, hooks, query/calculation/trust resolution;
- any other report/page notice;
- shared `AlertPanel` implementation, shared CSS, tokens or breakpoints;
- query/cache/aggregation/calculation/trust/permission/RBAC/RLS/routing/export/print/backend/business/workflow semantics.

If implementation demonstrates that any excluded semantic/shared-contract change is necessary, REPORT043 becomes `BLOCKED` pending Product Design reassessment rather than widening silently.

## Evidence expectations

Focused `TreasuryPage` tests should protect:
- shared `.ds-alert-panel` anatomy and `data-tone="info"` / equivalent semantic evidence;
- exact disclosure content and technical literals/code treatment;
- static/passive semantics: no action and no live announcement;
- hierarchy placement relative to the header and `SystemHealthBar` where source-testable;
- no regression to the already-covered Treasury MetricGrid/ChartPanel/loading/blocked/empty/ready contracts.

Execution evidence must follow `33_TEST_AND_VALIDATION_POLICY.md`; authored-but-unexecuted tests must remain labeled `TESTS_AUTHORED_NOT_EXECUTED` unless an approved execution route actually runs them.

## Peer-state synthesis / contradiction handling

After the independent judgment:

- **Team Memory:** fresh for the integrated REPORT042 truth and explicitly delegates REPORT043 bounding to Product Design; aligned.
- **Development Integrator:** fresh through REPORT042 integration and delegates exactly one next REPORT043 concern to Product Design; aligned.
- **UI Production Engineer:** Development copy is lifecycle-historical for completed REPORT042; no REPORT043 implementation claim exists yet. Not a contradiction.
- **Design QA:** Development copy is lifecycle-historical for completed REPORT042; no REPORT043 review claim exists yet. Not a contradiction.
- **Decision Log / North Star / component/migration/device docs:** aligned with shared-system-before-local-invention, presentation-only ownership, Arabic-first responsive composition and feedback/state completeness.
- **Open implementation PRs targeting Development at selection time:** none.

Current contradiction classification: `NONE`.

## Repository actions / what changed since the previous state

- Completed the mandatory shared-memory bootstrap in the prescribed order and inspected issue #27, exact current Development HEAD, open PRs targeting Development and relevant blueprint/component/migration/device docs.
- Confirmed REPORT042 is integrated and REPORT043 was the sole READY unbounded placeholder.
- Inspected current report evidence and selected the smallest dependency-safe concern: Treasury static semantic-contract notice → existing shared `AlertPanel` info grammar.
- Bounded REPORT043 in `31_AGENT_TEAM_WORKSTREAM.md` at commit `9bed2a597392437b9389783e19f2bbfedd7ffd1b`.
- Deliberately deferred the broader Reports Overview navigation-card debt because it carries a larger interactive/shared-pattern decision surface.
- Did not update Team Memory or Decision Log because no overall system direction or durable rule changed.
- Did not modify product code or peer role states, merge, touch `main`, deploy Vercel, modify preview branches, trigger/rerun GitHub Actions or use hosted CI.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** REPORT043 is now `READY — BOUNDED` to the Treasury static semantic-contract information notice only, converging its page-local presentation onto the existing shared `AlertPanel tone="info"` grammar.
- **Preserve:** exact disclosure meaning and technical literals/code treatment; same hierarchy position; static/non-live/passive semantics; all Treasury chart/KPI/filter/SystemHealthBar/trust/query/business contracts; unchanged shared `AlertPanel` API/CSS/tokens/breakpoints.
- **Need from you:** start from the exact latest `design-system-v2-development` HEAD, implement only this concern, add focused Treasury tests and open one Draft PR targeting Development with honest evidence labeling; if shared contracts or Treasury trust/business semantics must change, mark the slice `BLOCKED` instead of widening it.
- **Blocker level:** `NONE`.
- **Baseline:** Development pre-state-write `9bed2a597392437b9389783e19f2bbfedd7ffd1b`; REPORT042 product merge `f7479859fe5c3233c3082bad2e97c0a004213f4c`.
