# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-21`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD independently inspected before this run's governance writes: `2032a714b2d406b31374ea8e0ef66a5fd85957ab`.
- Latest integrated product baseline: `DS2-REPORT-016` / PR #64, reviewed PR HEAD `d6f257c4060aa25a2c4ce46abe621fe76f031826`, squash merge `ce3db886a3eaaae15025998186cc62e1e841410e`.
- Open implementation PRs targeting Development at selection time: none.
- Current single READY slice: `DS2-REPORT-017 — Target Attainment responsive detail-collection convergence`.
- Representative surface: `src/pages/reports/TargetAttainmentPage.tsx` → `تفاصيل الأهداف` collection only.
- Workstream bounding commit: `c39ba697a8c1ede820abf7d6d5c0fc2c7a913a23`.

## Independent Product Design judgment

**READY — REPORT017 is the smallest dependency-safe next slice and advances system coherence without widening functional scope.**

I independently inspected remaining Reports surfaces on the latest integrated baseline before comparing peer states. Target Attainment is the better next system move than another local chart-shell conversion because its eight-column detail table still depends on horizontal scrolling on compact devices while the repository already has a proven responsive collection grammar from Product Performance, Customer Health, Churn Risk, Geography and Rep Performance.

The intended change is not page beautification. It is another consumer proof of the same shared rule: preserve dense comparison on Desktop, but use `ResponsiveCollection + Card + KeyValueList` for deliberate Tablet/Mobile composition when the wide table materially degrades compact-device usability.

## REPORT017 exact acceptance boundary

### Desktop

Preserve the current dense semantic table and existing row ordering/hover behavior with the same eight facts in this exact order:

`الهدف / النوع / المسؤول / الفرع / المستهدف / المحقق / إنجاز% / الاتجاه`.

Add/retain `scope="col"` on the eight headers as semantic-only accessibility hardening. Do not redesign Desktop density or change data meaning.

### Tablet / Mobile

- Tablet: shared passive Card/KeyValueList composition with a deliberate two-column detail layout.
- Mobile: same shared grammar with a one-column detail layout and no ordinary horizontal table overflow.
- Exactly one ready-state renderer is mounted for the active device class; the Desktop table must not remain mounted behind compact layouts.
- Cards remain non-interactive; do not invent navigation, click, keyboard or focus behavior.
- Long Arabic target/type/responsible/branch values must wrap safely; money and percentage values preserve intentional LTR presentation inside RTL composition.

### Data and semantic truth to preserve

Preserve exactly:
- `target_name`;
- `type_code`;
- `rep_name ?? '—'`;
- `branch_name ?? '—'`;
- `fmtCur(target_value)`;
- `fmtCur(achieved_value)`;
- `fmtPct(achievement_pct)` with current semantic color thresholds: `>= 100` success, `>= 80` warning, otherwise danger;
- `TrendBadge(row.trend)` including its established trend labels/colors and unknown-trend fallback.

No new field, aggregation, ordering, target logic, achievement logic or trend interpretation is authorized.

### State / trust / accessibility truth to preserve

- Trust/Freshness section context remains unchanged.
- State precedence remains `BLOCKED/FAILED -> loading -> empty -> ready`.
- Blocked copy remains unchanged.
- Loading remains exactly five `SkeletonCard height={44}` rows.
- Empty copy remains exactly `لا توجد بيانات — شغّل watermark sweep أولاً`.
- Compact detail semantics should use the established `KeyValueList` definition-list contract; semantic color is not the sole information carrier.
- Shared semantic surfaces/tokens remain responsible for dark mode; no page-local palette or global CSS widening.

## Explicit exclusions / stop rule

Out of scope:
- page title/header controls, scope selector and date input;
- KPI/MetricCard summary area;
- `نسبة الإنجاز — المندوبون الفرديون` chart, chart shell/data mapping/axes/tooltip/reference line/bar colors;
- `useTargetAttainmentSummary`, `useTargetAttainmentTable`, filters/date semantics, row ordering, query/cache/calculation/status/business logic;
- backend, permissions, RBAC/RLS, routing, validation, export/print or workflow behavior;
- shared `ResponsiveCollection`, `Card`, `KeyValueList`, token or global CSS changes;
- any other Reports page.

If implementation proves that any of those changes is required, REPORT017 becomes `BLOCKED`; the PR must not silently widen.

## Focused validation contract

The implementation test artifact must protect:
- Desktop exact eight-column order plus `scope="col"`;
- Tablet two-column and Mobile one-column rendering with one active renderer only and no compact dependence on horizontal table scrolling;
- all eight facts, responsible/branch fallbacks and current row ordering;
- exact achievement thresholds and TrendBadge semantics/fallback;
- money/percentage formatting, LTR numeric presentation and Arabic wrap safety;
- blocked/loading/empty precedence, five × 44px skeleton rows and exact blocked/empty copy;
- passive Card semantics and unchanged Trust/Freshness context.

Evidence remains subject to `33_TEST_AND_VALIDATION_POLICY.md`; authored-but-unexecuted tests must remain labeled honestly and do not constitute runtime/visual PASS.

## Peer-state synthesis / contradiction status

This judgment was formed from current Development source and system guidance first, then compared with peer states.

- **Integration / repository facts:** REPORT016 is integrated and there is no open implementation PR targeting `design-system-v2-development` at selection time.
- **UI Production / Design QA specialist states:** still describe REPORT016 exact-head implementation/review evidence. They are historically valid but lifecycle-stale after merge; they create no current blocker.
- **Integration State:** operationally stale relative to the current integrated baseline; current GitHub branch/PR facts and the refreshed Team Memory supersede it for lifecycle status. This is bounded and non-blocking because no implementation PR is active.
- **Team Memory:** refreshed after REPORT016 integration; its generic next-slice position is superseded for REPORT017 scope by the newly bounded Workstream and this owned Design Director state. Overall North Star/system direction did not change, so no Team Memory mutation is warranted from this role.
- **North Star / component / device / migration guidance:** aligned with shared responsive grammar, Arabic-first wrapping, semantic color discipline, compact-device ergonomics, one renderer per device, dense Desktop preservation and functional isolation.

Current contradiction classification: **NONE / non-blocking stale peer lifecycle state only.**

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the prescribed order.
- Inspected issue #27, current Development HEAD, open PRs targeting Development, relevant component/device/migration guidance, and representative remaining report surfaces including Target Attainment and Treasury.
- Verified REPORT016 integration and zero active implementation PRs before selecting the next slice.
- Re-inspected `TargetAttainmentPage.tsx` directly and corrected the acceptance contract to its actual current eight-column data truth rather than relying on stale assumptions.
- Bounded exactly one READY implementation slice in `31_AGENT_TEAM_WORKSTREAM.md`: REPORT017 Target Attainment detail collection only.
- Updated only this owned specialist state file among role states.
- Did not modify Team Memory or Decision Log because no overall design-system direction or durable rule changed.
- Did not modify product code, merge any PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

## What changed since previous state

- REPORT016 moved from accepted-but-awaiting-integration to integrated on Development.
- The generic REPORT017 placeholder is now concretely bounded as Target Attainment responsive detail-collection convergence.
- The exact implementation contract is anchored to the live eight-column source truth and compact-device collection grammar.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** REPORT016 is integrated; with no implementation PR active, REPORT017 is now the single dependency-safe READY slice, bounded to `TargetAttainmentPage.tsx` → `تفاصيل الأهداف` responsive detail collection only.
- **Preserve:** exact eight facts/order and current row order; `rep_name`/`branch_name` fallbacks; achievement color thresholds and `TrendBadge` semantics; blocked/loading/empty/trust/freshness behavior; Desktop dense table plus `scope="col"`; Tablet two-column and Mobile one-column shared Card/KeyValueList composition; one renderer per device; Arabic wrapping/LTR money-percent presentation; no shared API/CSS/token or functional/business widening.
- **Need from you:** start from the latest Development HEAD, implement only REPORT017 in one PR with the focused validation artifact above, and mark the slice `BLOCKED` instead of widening if any excluded shared or functional dependency appears.
- **Blocker level:** `NONE`.
- **Baseline:** product/design inspection baseline `2032a714b2d406b31374ea8e0ef66a5fd85957ab`; Workstream bounding commit `c39ba697a8c1ede820abf7d6d5c0fc2c7a913a23`.
