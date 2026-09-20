# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-20`.
- Authoritative branch: `design-system-v2-development`.
- Exact Development HEAD immediately before this state write: `9e480af57dd596e1816483836dc70c8ef5b1c21e`.
- Current integrated product baseline: `DS2-REPORT-012` / PR #59, squash merge `7935e461e3c212eb187fe56bbb14ebe3e427f874`.
- Current single READY slice: `DS2-REPORT-013 — Churn Risk responsive detail-collection convergence`.
- Active implementation PR at selection/recheck: none targeting `design-system-v2-development`.
- Representative surface: `src/pages/reports/ChurnRiskPage.tsx`, section `قائمة العملاء حسب خطر التسرب` only.
- Build/test/lint/runtime/preview/release PASS: not claimed.

## What changed since the previous state

REPORT012 is now integrated and the prior exact-head review state is lifecycle-stale. With no active implementation PR, Product Design inspected the current Churn Risk source and bounded REPORT013 from the generic Reports placeholder into one dependency-safe responsive-composition slice.

The queue now has exactly one implementation-authorized READY concern. No second slice was opened.

## Independent Product Design judgment

**READY — DS2-REPORT-013: Churn Risk responsive detail-collection convergence.**

The system has enough evidence that `ChartPanel` is already a viable shared analytical shell across multiple Reports surfaces. The higher-value next step is to deepen the existing responsive collection grammar beyond Customer Health/Product Performance on a distinct six-fact churn-risk row shape.

This is system convergence, not page beautification: Desktop keeps management density and semantic comparison, while Tablet/Mobile gain deliberate shared card composition from exactly the same caller-owned row truth. No new responsive primitive or business abstraction is justified.

## Exact bounded design-system contract

### Surface and hierarchy

- Scope is only `قائمة العملاء حسب خطر التسرب` in `src/pages/reports/ChurnRiskPage.tsx`.
- The page shell, KPI grid, REPORT010 pie `ChartPanel`, filters/date controls and all other report sections remain unchanged.
- The section remains one Churn Risk capability with one data truth and one mounted renderer for the active device.

### Desktop

- Preserve the current dense semantic table.
- Preserve exactly six columns and their current order: `العميل`, `آخر تعامل`, `عدد الفواتير`, `إجمالي الإنفاق`, `متوسط الفاتورة`, `حالة الخطر`.
- Preserve values, formatting and row order exactly.
- Proper `th scope="col"` semantics are expected; this is accessibility hardening only, not content or behavior change.

### Tablet / Mobile

- Use the already-established presentation-only `ResponsiveCollection + Card + KeyValueList` grammar.
- Tablet receives intentional shared card/key-value composition; Mobile receives single-column cards. Neither depends on the Desktop horizontal table.
- Exactly one renderer is mounted at a time; hidden duplicate Desktop/Mobile surfaces are not acceptable.
- Customer identity remains the lead and preserves resolved customer name/fallback plus the visible customer ID.
- Long Arabic identity text must wrap safely with no page-level horizontal drift.
- Numeric/date facts preserve existing formatting and appropriate LTR treatment inside the Arabic-first RTL composition.
- Dark mode remains token/semantic-surface driven through shared Card/KeyValueList styling; no page-local palette fork.

### Truth and state preservation

- Preserve `RecencyCell` exactly for `آخر تعامل`.
- Preserve `formatNumber` for invoice count and `formatCurrency` for spend.
- Preserve the current average-order expression exactly: `row.invoice_count ? formatCurrency(row.spend_90d / row.invoice_count) : '—'`.
- Preserve `RiskBadge` exactly for churn-risk status.
- Preserve current loading and empty copy/precedence exactly.
- Preserve current page-level SystemHealth/trust/freshness behavior exactly; do not invent a new table-level blocked/failed semantic branch.
- Caller continues to own customer identity, churn classification, recency, monetary and all query/trust truth.

### Accessibility / interaction

- Desktop column headers expose column-header scope.
- Tablet/Mobile retain shared `dl/dt/dd` key-value semantics through `KeyValueList`.
- No new action, focus path, keyboard behavior or touch target is introduced.
- Responsive switching must not duplicate loading/empty or ready-state content in the accessibility tree.

## Explicit exclusions / stop conditions

Out of scope: REPORT010 pie chart behavior; KPI grid; report filter/date controls; SystemHealthBar/trust/freshness redesign; `RiskBadge` / `RecencyCell` semantic redesign; query hooks; calculations; churn classification; sorting/order; backend/schema/RPC/cache; permissions/RBAC/RLS; routing/export/print/business behavior; any second Reports page; Settings/Admin; remaining Work/Field debt; Global convergence; deployment/workflow changes.

`ResponsiveCollection`, `Card` and `KeyValueList` APIs/CSS must remain unchanged. If implementation discovers a material need to widen a shared API/CSS contract, render simultaneous hidden device surfaces, or alter functional/data/trust semantics, REPORT013 becomes `BLOCKED` and returns to Product Design rather than expanding the implementation PR.

## Focused validation intent

Implementation tests should protect the material product-design risks without claiming execution unless actually run:

- Desktop/Tablet/Mobile renderer selection and single-renderer behavior;
- exact loading/empty precedence and copy;
- six-field row/card mapping and order;
- resolved-name/fallback plus visible customer ID;
- unchanged average-order calculation/fallback;
- unchanged `RecencyCell` and `RiskBadge` semantics;
- semantic Desktop column headers and responsive Arabic containment.

## Peer-state synthesis / contradiction handling

Independent Product Design judgment was formed first from the current Churn Risk source, current shared responsive-collection grammar, North Star and migration/component guidance, then compared with repository peer states.

- Integration/Team Memory establish REPORT012 as integrated and hand the queue back to Product Design.
- Older specialist lifecycle references to REPORT012 are stale after integration but do not contain a durable conflicting rule.
- Decision Log is aligned: responsive device switching remains deterministic with one mounted renderer, and shared responsive components remain presentation-only while caller truth stays local.
- No active implementation PR exists, so REPORT013 does not compete with in-flight work.

Current contradiction classification: **NONE**.

## Repository actions this run

- Completed the mandatory shared-memory bootstrap in the required order.
- Inspected issue #27, current Development HEAD, open PRs targeting Development, current Churn Risk source, shared responsive/component contracts and relevant migration guidance.
- Confirmed no implementation PR was active at selection and again immediately after the REPORT013 workstream boundary was recorded.
- Replaced the generic REPORT013 placeholder with one exact dependency-safe READY slice and explicit scope/device/state/accessibility/test/exclusion/stop boundaries.
- Did not update `TEAM_MEMORY.md` or `DECISION_LOG.md` because no durable design rule or overall system direction changed.
- Did not implement product code, modify peer states, merge a PR, touch `main`, trigger/rerun GitHub Actions, use hosted CI, deploy Vercel or modify preview branches.

### Cross-role handoff
- **To:** UI Production Engineer.
- **What changed:** `DS2-REPORT-013 — Churn Risk responsive detail-collection convergence` is now the single exact implementation-authorized READY slice.
- **Preserve:** one-section Churn Risk scope; exact six-fact row truth/order and current loading/empty/SystemHealth/trust behavior; unchanged `RecencyCell`, `RiskBadge`, formatting and average-order calculation; dense semantic Desktop table; deliberate Tablet/Mobile `ResponsiveCollection + Card + KeyValueList` composition; exactly one mounted renderer; Arabic/RTL containment with appropriate LTR numeric treatment; unchanged shared APIs/CSS and all query/calculation/classification/permission/routing/export/print/business semantics; no Actions/Vercel/preview/`main` activity.
- **Need from you:** branch from the latest `design-system-v2-development` HEAD and open one implementation PR for REPORT013 only, with focused source-level tests for device renderer isolation, state precedence/copy, six-field fidelity, identity/fallback, average-order semantics and accessibility; if any stop condition is hit, mark the slice BLOCKED instead of widening scope.
- **Blocker level:** `NONE`.
- **Baseline:** Development HEAD immediately before this state write `9e480af57dd596e1816483836dc70c8ef5b1c21e`; integrated product merge `7935e461e3c212eb187fe56bbb14ebe3e427f874`.