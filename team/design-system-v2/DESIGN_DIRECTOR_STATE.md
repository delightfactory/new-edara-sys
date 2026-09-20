# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-20`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD immediately before this state write: `85a5dfc08c7b5edb63465a0aee9d17a4bbbf2845`.
- Current integrated product baseline: `DS2-REPORT-012` / PR #59, squash merge `7935e461e3c212eb187fe56bbb14ebe3e427f874`.
- Current single READY slice: `DS2-REPORT-013 — Churn Risk responsive detail-collection convergence`.
- Active implementation PR at final recheck: none targeting `design-system-v2-development`.
- Representative surface: `src/pages/reports/ChurnRiskPage.tsx`, section `تفاصيل العملاء — مرتب: معرض للخطر أولاً` only.
- Build/test/lint/runtime/preview/release PASS: not claimed.

## Material correction this run

**The previous Product Design REPORT013 acceptance contract was factually wrong and is superseded by this state.**

UI Production correctly stopped before branch creation because the prior Director boundary described fields that do not exist in the current Churn Risk source/data contract (`آخر تعامل`, invoice count, total spend, average invoice and `row.invoice_count` / `row.spend_90d`). Development Integration independently confirmed that implementing those requirements would violate the UI-only functional-isolation rule.

I independently re-inspected the latest Development source before synthesizing peer states. The live Churn Risk ready-state truth is exactly six facts in this order: `العميل`, `التصنيف`, `RFM Score`, `أيام منذ آخر شراء`, `تكرار (90 يوم)`, `قيمة (90 يوم)`. `CustomerRiskRow` contains only `customer_id`, `customer_name`, `risk_label`, `rfm_score`, `recency_days`, `frequency_l90d`, and `monetary_l90d`.

The responsive-system objective remains valid; only the factual Product Design contract was wrong. REPORT013 is therefore re-bounded around the actual current RFM row truth and is again dependency-safe `READY`.

## Independent Product Design judgment

**READY — DS2-REPORT-013: Churn Risk responsive detail-collection convergence, corrected source contract.**

This is still the smallest high-value next slice. `ResponsiveCollection + Card + KeyValueList` is already proven on Product Performance and Customer Health, while the Churn Risk detail table still relies on a desktop table as its only ready-state composition. Extending the same presentation-only grammar to the actual Churn Risk RFM facts improves Mobile/Tablet quality without changing data meaning, queries, calculations, classification, trust or permissions.

The device strategy requires adaptive composition rather than compressed desktop tables, and the component decision matrix explicitly places device orchestration in `ResponsiveCollection` while preserving caller-owned query/business semantics.

## Corrected exact bounded contract

### Surface / hierarchy

- Scope is only the customer-detail section titled `تفاصيل العملاء — مرتب: معرض للخطر أولاً` in `src/pages/reports/ChurnRiskPage.tsx`.
- Preserve the existing section shell/header and Trust/Freshness cluster.
- The page shell, KPI grid, REPORT010 pie `ChartPanel`, filters/date controls and all other report sections remain unchanged.

### Desktop

- Keep the dense semantic table as the management comparison surface.
- Preserve the exact current six columns and order: `العميل`, `التصنيف`, `RFM Score`, `أيام منذ آخر شراء`, `تكرار (90 يوم)`, `قيمة (90 يوم)`.
- Preserve row order, values, existing formatting and local table overflow behavior.
- Add/retain `th scope="col"` for all six headers; this is accessibility hardening only.

### Tablet / Mobile

- Use the already-integrated presentation-only `ResponsiveCollection + Card + KeyValueList` grammar; do not create a page-local responsive system.
- Tablet uses deliberate card composition with a compact two-column `KeyValueList`; Mobile uses a single-column card stack.
- Exactly one renderer is mounted at a time.
- Customer identity remains the card lead using the exact current display rule: show resolved `customer_name` when present, otherwise the existing truncated `customer_id` fallback. Do **not** introduce a second visible ID or any new identity content.
- The five non-identity facts map exactly to the current source: `RiskBadge(row.risk_label)`, `row.rfm_score`, `RecencyCell(row.recency_days)`, `row.frequency_l90d` with `×`, and `fmtCur(row.monetary_l90d)`.
- Long Arabic names must wrap safely with `min-width: 0` / safe wrapping; no ordinary page-level horizontal drift.
- RFM/frequency/monetary/recency values retain appropriate LTR treatment inside the Arabic-first RTL composition.
- Dark mode inherits shared semantic Card/KeyValueList tokens; no local palette fork.

### State / truth preservation

- Preserve current priority: blocked first, then loading, then empty, then ready content.
- Preserve exact blocked copy: `بيانات الخطر محجوبة` and `snapshot_customer_risk يحتاج تشغيل ناجح أولاً`.
- Preserve loading as five `SkeletonCard` rows at height `44`.
- Preserve exact empty copy: `لا توجد بيانات — شغّل watermark sweep أولاً`.
- Preserve current `SystemHealthBar`, `riskTrust`, `TrustStateBadge`, `FreshnessIndicator` and all page-level trust/freshness behavior.
- Preserve caller ownership of customer identity, RFM score, risk classification, recency, frequency, monetary values, sorting/order and all query/data semantics.
- There is no invoice-count, total-spend or average-invoice fact in this slice.

### Accessibility / interaction

- Desktop headers expose proper column scope.
- Tablet/Mobile facts use shared `KeyValueList` `dl/dt/dd` semantics.
- Responsive switching must not duplicate ready/loading/empty content in the accessibility tree.
- No new interactive control, focus path, keyboard behavior, hover dependency or touch target is introduced.

## Focused validation intent

Tests should protect, without falsely claiming execution:

- Desktop/Tablet/Mobile renderer selection and exactly-one-renderer behavior;
- exact blocked/loading/empty precedence and copy, including five 44px loading skeletons;
- exact six-column Desktop label/order and row/card fact mapping;
- current customer-name versus truncated-ID fallback behavior, with no invented extra identity field;
- unchanged `RiskBadge`, `rfm_score`, `RecencyCell`, `frequency_l90d` and `fmtCur(monetary_l90d)` semantics;
- Desktop `scope="col"`, Tablet/Mobile key-value anatomy, LTR numeric treatment and long-Arabic containment.

## Explicit exclusions / stop conditions

Out of scope: REPORT010 pie chart; KPI grid; filters/date controls; SystemHealth/trust/freshness redesign; `RiskBadge` / `RecencyCell` semantic redesign; `CustomerRiskRow` type; query hooks; RPC/service/backend/schema/cache contracts; calculations; RFM/churn classification; sorting/order; permissions/RBAC/RLS; routing/export/print/business behavior; invoice-count/spend/average-order additions; any second report page; shared `ResponsiveCollection` / `Card` / `KeyValueList` API or CSS widening; Settings/Admin; Work/Field debt; Global convergence; Actions/Vercel/preview/`main` activity.

If implementation needs a new data field/calculation, material shared API/CSS widening, simultaneous hidden duplicate device surfaces, or any functional/data/trust semantic change, REPORT013 becomes `BLOCKED` and returns to Product Design instead of widening the PR.

## Peer-state synthesis / contradiction resolution

Independent source judgment was formed first, then peer states were compared.

- **UI Production:** blocker was valid. Stopping before branch creation prevented a functional-semantics leak.
- **Development Integrator:** blocker confirmation was valid; its `NO_MERGE — BLOCKED_ON_PRODUCT_DESIGN_SOURCE_CONTRACT_MISMATCH` reflects the superseded contract and should be considered resolved only by this corrected boundary, not ignored.
- **Design QA:** current state remains lifecycle-stale at REPORT012 because no REPORT013 implementation exists yet; there is no QA contradiction to resolve at this stage.
- **Team Memory / Decision Log / North Star:** durable direction is unchanged and aligns with the correction: responsive presentation may adapt, business/data meaning may not.

Current contradiction classification after correction: **RESOLVED / no remaining Product Design BLOCKING contradiction**. There is still no implementation PR, so the next role may safely start only the corrected REPORT013 slice from the latest Development HEAD.

## Repository actions this run

- Completed the mandatory bootstrap in the prescribed order and inspected issue #27, current Development HEAD, open Development-targeting PRs, current Churn Risk source/type contract and the relevant device/responsive/component guidance.
- Confirmed no implementation PR targets `design-system-v2-development`.
- Corrected `31_AGENT_TEAM_WORKSTREAM.md` so REPORT013 now matches the actual live RFM row contract; workstream correction commit: `85a5dfc08c7b5edb63465a0aee9d17a4bbbf2845`.
- Did not update `TEAM_MEMORY.md` or `DECISION_LOG.md` because no durable system direction or long-lived rule changed.
- Did not implement product code, modify peer-owned states, merge a PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

### Cross-role handoff
- **To:** UI Production Engineer; Development Integrator should treat its prior blocker as bounded by this corrected contract, not as authorization to merge anything without the normal later gates.
- **What changed:** Product Design accepted the peer blocker, superseded the incorrect REPORT013 fact model, and re-bounded the single READY slice to the actual current Churn Risk six-fact RFM contract in `ChurnRiskPage.tsx`.
- **Preserve:** exact section title and shell; exact six-column/field truth and row order; current name-or-truncated-ID fallback; `RiskBadge`, `rfm_score`, `RecencyCell`, `frequency_l90d`, `fmtCur(monetary_l90d)`; exact blocked/loading/empty precedence and copy; current SystemHealth/trust/freshness behavior; dense semantic Desktop table; deliberate Tablet/Mobile `ResponsiveCollection + Card + KeyValueList`; exactly one mounted renderer; Arabic wrapping/RTL with appropriate LTR numeric treatment; unchanged shared APIs/CSS and all query/type/calculation/classification/permission/routing/export/print/business semantics.
- **Need from you:** UI Production should branch from the latest `design-system-v2-development` HEAD and open one implementation PR for corrected REPORT013 only, with focused source-level tests matching the corrected contract. If any excluded functional/data/shared-contract change becomes necessary, stop and mark `BLOCKED`.
- **Blocker level:** `NONE` after Product Design correction; prior source-contract blocker is explicitly resolved by rebounding, not by changing data semantics.
- **Baseline:** Development HEAD immediately before this state write `85a5dfc08c7b5edb63465a0aee9d17a4bbbf2845`; integrated product merge `7935e461e3c212eb187fe56bbb14ebe3e427f874`; no active implementation PR at final recheck.