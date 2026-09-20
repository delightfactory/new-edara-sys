# UI Implementation State

## Reviewed baseline

- Run date: `2026-09-20`.
- Development branch: `design-system-v2-development`.
- Exact Development HEAD inspected before this owned-state write: `2f7649c6e528a756c00cc52878fa98d62e82bf82`.
- Active slice: `DS2-REPORT-013 — Churn Risk responsive detail-collection convergence`.
- Representative surface: `src/pages/reports/ChurnRiskPage.tsx` → customer detail collection only.
- Active implementation PR targeting Development: none.
- Disposition: `BLOCKED — PRODUCT DESIGN BOUNDARY DOES NOT MATCH CURRENT SOURCE/DATA CONTRACT`.
- Product code/test branch: not created.
- Test/build/lint/runtime/preview/release PASS: not claimed.

## Independent implementation judgment

REPORT013 cannot be implemented safely from the current Development baseline without violating the UI-only isolation contract.

On exact Development HEAD `2f7649c6e528a756c00cc52878fa98d62e82bf82`, the live Churn Risk table and `CustomerRiskRow` contract do not contain the six facts Product Design bounded for REPORT013.

Current source truth in `ChurnRiskPage.tsx` is six columns in this order:
- `العميل`
- `التصنيف`
- `RFM Score`
- `أيام منذ آخر شراء`
- `تكرار (90 يوم)`
- `قيمة (90 يوم)`

Current `CustomerRiskRow` fields exposed by `src/lib/services/analyticsClient.ts` are:
- `customer_id`
- `customer_name`
- `risk_label`
- `rfm_score`
- `recency_days`
- `frequency_l90d`
- `monetary_l90d`

By contrast, the current Product Design boundary/workstream requires preserving a different six-fact shape:
- `العميل`
- `آخر تعامل`
- `عدد الفواتير`
- `إجمالي الإنفاق`
- `متوسط الفاتورة`
- `حالة الخطر`

It also requires preserving the expression `row.invoice_count ? formatCurrency(row.spend_90d / row.invoice_count) : '—'`, but neither `invoice_count` nor `spend_90d` exists on the current `CustomerRiskRow`, and that expression is not present in the current Churn Risk page.

Therefore implementing the recorded boundary would require inventing new row semantics or changing query/service/data behavior, which is explicitly forbidden for this UI workstream. The safe action is to stop before branch creation and return the slice to Product Design for corrected bounding against the exact current source.

## Material implementation progress

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, current Development HEAD, all open PRs targeting Development, current Churn Risk page source and the actual `CustomerRiskRow` service type.
- Confirmed no implementation PR targets `design-system-v2-development`.
- Formed implementation judgment from current source/data contracts, then compared it with Product Design/workstream handoff.
- Detected a material cross-role/source contradiction before creating a feature branch.
- Did **not** create a branch, PR, product-code change or test artifact because the current bounded acceptance contract cannot be satisfied without crossing the functional boundary.

## Preserve / verified boundaries

- Do not modify DB/migrations/RPC/services/query contracts to manufacture the Product Design facts.
- Do not reinterpret `rfm_score`, `frequency_l90d` or `monetary_l90d` as invoice-count/spend/average-order semantics.
- Do not alter churn classification, recency, monetary calculations, row ordering, SystemHealth/trust/freshness, filters, REPORT010 pie chart, KPI grid, permissions/RBAC/RLS/routing/export/print/business behavior.
- Keep `ResponsiveCollection`, `Card` and `KeyValueList` APIs/CSS unchanged unless a future corrected Product Design boundary explicitly proves a legitimate shared need.
- No GitHub Actions, hosted CI, Vercel, preview branch or `main` activity.

## Evidence / blocker

Source evidence only; no implementation exists yet.

Known blocking contradiction:
- Product Design/workstream REPORT013 acceptance criteria describe fields and an average-order expression that are absent from the exact current Churn Risk source and `CustomerRiskRow` contract.
- Proceeding would force forbidden functional/data-contract invention rather than presentation-only convergence.

No test artifact was authored because product implementation did not start. No `SOURCE_REVIEW_PASS`, `TESTS_AUTHORED_NOT_EXECUTED`, local execution, runtime, preview or release PASS is claimed for REPORT013.

## Peer-state comparison / current risk

- **Product Design Director:** current and implementation-authorizing, but its REPORT013 source assumptions conflict materially with the exact Development source/data contract.
- **Design QA:** lifecycle-stale at completed REPORT012; no REPORT013 approval exists.
- **Development Integrator:** lifecycle-stale at completed REPORT012; must remain `NO_MERGE` because no REPORT013 implementation PR exists.
- **Team Memory:** still carries the generic REPORT013 placeholder and does not resolve the source mismatch.
- **Decision Log / North Star:** aligned with stopping here; UI-only isolation and caller-owned business truth prohibit inventing the missing facts.

Current contradiction classification: **BLOCKING**.

### Cross-role handoff
- **To:** Product Design Director.
- **What changed:** UI Production found that the authorized REPORT013 six-fact contract does not match the exact current `ChurnRiskPage.tsx` / `CustomerRiskRow` source truth, so implementation was stopped before branch creation.
- **Preserve:** exact current Churn Risk data/query/calculation/trust semantics; UI-only functional boundary; no shared API/CSS widening; no Actions/Vercel/preview/`main` activity.
- **Need from you:** re-inspect exact latest Development source and either (a) re-bound REPORT013 around the actual existing six-column RFM row shape for presentation-only responsive convergence, or (b) explicitly move any desired data-shape change into a separate approved functional workstream. Do not ask UI Production to synthesize `invoice_count`, `spend_90d` or average-order semantics from unrelated RFM fields.
- **Blocker level:** `BLOCKING`.
- **Baseline:** `2f7649c6e528a756c00cc52878fa98d62e82bf82`.
