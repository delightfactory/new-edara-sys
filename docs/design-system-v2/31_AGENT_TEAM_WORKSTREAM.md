# 31 — Design System V2 Agent Team Workstream

## Purpose

Shared operating board for the autonomous EDARA Design System V2 team.

Authoritative branch: `design-system-v2-development`.
`main` remains frozen until explicit owner approval.

Authorities:
- Product quality: `32_DESIGN_SYSTEM_NORTH_STAR.md`
- Test/evidence: `33_TEST_AND_VALIDATION_POLICY.md`
- Communication: `34_AGENT_TEAM_COMMUNICATION_PROTOCOL.md`

## Team and state machine

| Role | Responsibility | Cadence | Product code | Merge | Deploy |
|---|---|---|---:|---:|---:|
| Product Design Director | System identity, architecture, next slice, design quality | every 2 hours | No | No | No |
| UI Production Engineer | Implement/repair the single active UI slice | hourly | UI-only | No | No |
| Design QA | Independent exact-head review | hourly | No | No | No |
| Development Integrator | Merge GREEN-DEV PR and advance queue | hourly | No feature work | Development only | No |

`BACKLOG -> READY -> IN_PROGRESS -> REVIEW -> GREEN-DEV -> DONE`

Exceptional state: `BLOCKED`.
Only one implementation slice may be active. A role with nothing actionable must no-op.

## Repository-native communication

Before material action every role reads Team Memory, all four role states, the Decision Log, this workstream, issue #27, and the active PR. Each role owns only its own state file. Integrator updates Team Memory after successful merge. Issue #27 is the concise event stream.

## GitHub Actions / preview policy

Hosted GitHub Actions remain forbidden while quota protection is active. Focused tests are still authored. Normal development evidence is exact-head `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + an honest execution label. A known real build/type failure blocks integration.

Vercel preview remains owner-requested only. Scheduled agents never merge to `main`.

## Current integrated baseline

Product UI is integrated through `DS2-FIN-001`.

Latest product integration:
- PR: `#38 — DS2-FIN-001: establish vault overview V2 presentation`
- Exact reviewed PR HEAD: `b2450e22f9cf58d06780b608dbe6a7b871b53639`
- Squash merge commit: `7a70beccaf961b248f0df045f6bf610df4dfdc84`
- Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
- Runtime/preview/release evidence: not claimed

The development branch now includes semantic foundations, responsive shell/navigation/form/collection/action patterns, Dashboard V2, Customers migrations, Sales list/form/detail foundations, Inventory list/transfer migrations, Procurement list/form-shell migrations, bounded shared DataTable pagination hardening, and the first Finance overview migration using shared `MetricGrid`, `ResponsiveCollection`, neutral categorical metadata, semantic status, and canonical `AppAction + resolveActionSet` device placement.

## Completed slices

- `DS2-UI-001 — Customer Form: basic-info composition` — `DONE` — PR #28 — merge `cdcc1a57cc3367fdd161fddb3d9e5b42e92e4829` — `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-002 — Customer detail secondary tabs/patterns` — `DONE` — PR #29 — merge `773085994502401a7368eded20926b1308b62e3f` — `SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-003 — Sales Orders list V2` — `DONE` — PR #30 — merge `e42910fb2bb7c945e67262f610d9e0b630d960a6` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-004 — Sales Order form V2 foundation` — `DONE` — PR #31 — merge `d00faf8e36d40c9dde9df0b2de6dc89737419c5d` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-UI-005 — Sales transaction detail V2` — `DONE` — PR #32 — merge `58b0f3f8f54f04636d3a35dd7d658edb7bcf5068` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-INV-001 — Inventory list surfaces` — `DONE` — PR #34 — merge `805995a5c0d9a118c415d647ed34e63dee326527` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-INV-002 — Transfer/adjustment operational flows` — `DONE` — PR #35 — merge `9328464542b1ca429fd1ec134667f45244215b67` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.
- `DS2-PROC-001 — Purchase list surfaces` — `DONE` — PR #36 — merge `936129c69a51237ceeefc7880d9735aa5f584879` — `GREEN-DEV + SOURCE_REVIEW_PASS + TESTS_AUTHORED_NOT_EXECUTED`.

### DS2-PROC-002 — Purchase Invoice form decomposition
Status: `DONE`
Merged PR: `#37`
Reviewed HEAD: `4fa613edad180de140b9c7a1c41ceeb9b7e55ee3`
Squash merge: `5b10b9fb578c91798d28526d8de407f63ffcc417`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- new/editable-draft Purchase Invoice flow uses a thin `PurchaseInvoiceDraftStepper` over the shared V2 `Stepper`, preserving page-owned reachability and validation and not unlocking review/final direct navigation;
- **بيانات الفاتورة** uses shared `FormSection + FormGrid` with deliberate `3 Desktop / 2 Tablet / 1 Mobile` composition while preserving supplier/warehouse/date/reference/landed-cost/notes truth and disabled rules;
- editable wizard actions use shared `FormActions + Button`, preserving cancel/back/next/save callbacks, save-disabled truth and RTL-native cues;
- Purchase workflow status uses shared semantic `StatusBadge` with the same Procurement vocabulary as the list surface;
- consumer-owned logical `margin-block-end: var(--space-4)` restores inter-section hierarchy at the Purchase Invoice composition boundary without adding external margin to shared `FormSection`/`Card`;
- supplier/product/warehouse identity, quantities, pricing, discounts, taxes, totals, landed costs/WAC/accounting/payment, receive/bill/cancel transitions, permissions, services/query/cache, routes, validation semantics, `ResponsiveModal`, mobile item flow and `DocumentActions` remain unchanged and page/domain-owned;
- `InlineCombobox`, item-table/card convergence, receive/accounting presentation, Purchase Returns and broad form-field convergence remain outside this completed slice.

### DS2-FIN-001 — Finance lists and summaries
Status: `DONE`
Merged PR: `#38`
Reviewed HEAD: `b2450e22f9cf58d06780b608dbe6a7b871b53639`
Squash merge: `7a70beccaf961b248f0df045f6bf610df4dfdc84`
Evidence: `AGENT-REVIEW: GREEN-DEV` + `SOURCE_REVIEW_PASS` + `TESTS_AUTHORED_NOT_EXECUTED`
Runtime/preview/release evidence: not claimed

System result:
- representative live Finance surface is the `VaultsPage` overview only; Finance calculations, balances, posting, services, permissions and workflow truth remain page/domain-owned;
- shared `MetricGrid + StatCard` projects the existing page-owned summary values with deliberate `3 Desktop / 2 Tablet / 1 Mobile` composition and no inferred semantic tone for factual active-count;
- one live `ResponsiveCollection<Vault>` replaces CSS-hidden Desktop/Mobile interaction trees while preserving dense Desktop `DataTable`, deliberate two-column Tablet cards, one-column Mobile cards, loading/empty/create behavior and one mounted interaction tree;
- vault type remains neutral categorical `Badge`; active/inactive remains semantic `StatusBadge`; total-balance sign tone remains caller/page-owned;
- page-owned `AppAction` eligibility/order feeds shared `resolveActionSet`: Mobile max one direct action, Tablet max two, remaining authorized actions stay available in accessible RTL native-details overflow; Desktop keeps dense direct row actions;
- `finance.vaults.create/transact/update`, `current_balance === 0`, statement `pageSize: 25`, create/update/manual-adjustment/transfer services, query/cache/invalidation, validation/toasts, modal workflows, routes and accounting/posting semantics remain unchanged;
- focused component/live-page tests were authored for summary semantics, device renderer selection, permissions/action parity, overflow, opening-balance eligibility, empty/create behavior, statement paging and service isolation.

## Current single READY slice

### DS2-FIN-002 — Payment Receipt transaction-detail header/action foundation
Status: `READY`
Owner role: Product Design Director -> UI Production Engineer
Design Director baseline: `45cf7998c90254e022258d91a6debfe7179d935d`
Representative live surface: `src/pages/finance/PaymentReceiptDetail.tsx`

System intent:
Prove that Finance transaction-detail identity, workflow status and guarded review actions reuse the same shared V2 `TransactionHeader + StatusBadge + AppAction/resolveActionSet` grammar already proven in Sales, while every receipt/payment/accounting rule remains page/domain/service-owned.

Implement only:
- replace the current ad-hoc sticky receipt header with a thin Finance adapter over shared `TransactionHeader`;
- preserve receipt number identity plus existing customer/date context and links;
- map `pending / confirmed / rejected` to shared `StatusBadge` using the current Arabic labels and semantic tones; Finance owns the mapping;
- use shared `Button` for back navigation to `/finance/payments` with RTL-native direction and touch-safe target;
- declare only the existing eligible review actions through canonical `AppAction`: confirm remains present only under existing `canConfirm` truth; reject remains present only under existing `isAdmin` truth; existing callbacks/modal openings remain unchanged;
- keep `DocumentActions kind="payment-receipt" entityId={receipt.id}` in the header tools slot as output tooling, without duplicating its capabilities inside the action registry;
- author focused tests/source contracts for status mapping, back navigation, permission/action parity, callback wiring, Mobile/Tablet registry placement and preserved output tooling.

Device/state/accessibility acceptance:
- Mobile `<=768px`: readable sticky identity/status with long Arabic customer names and mixed Latin receipt number; max one direct review action, remaining authorized review action in accessible RTL overflow; practical 44px back/action targets; no horizontal header overflow.
- Tablet `769–1024px`: deliberate wrapped header with max two direct review actions; output tooling remains visually secondary to workflow action hierarchy.
- Desktop `>=1025px`: efficient review actions remain visible through the shared header; existing page body/modals are preserved. This slice does not claim to solve the page's broader `maxWidth: 640` body-density debt.
- RTL/Arabic: correct back direction, receipt-number directionality, Arabic status/customer/date wrapping and overflow placement.
- Loading/not-found: preserve current skeleton and not-found behavior exactly; do not mount transaction header before a receipt exists.
- Permission/workflow: no unauthorized confirm/reject appears and no authorized action disappears.
- Accessibility: meaningful banner/action labels, shared focus/touch semantics and text-backed semantic status.

Explicit exclusions:
- no `getPaymentReceipt`, `confirmPaymentReceipt`, `rejectPaymentReceipt`, direct custody query, service/query/cache/invalidation changes;
- no changes to `isSelfCashCustody`, `isAdmin`, `canConfirm`, `finance.payments.confirm`, vault filtering/destination selection, cheque/custody handling, validation, toasts, route semantics or accounting/posting truth;
- no confirm/reject modal redesign, receipt amount/hero redesign, proof image/PDF/file redesign, upload/output subsystem changes, detail-card/`SectionHead`/`InfoRow` convergence, timeline/audit work, Payments list migration, statements/journals/ledger/expenses/reports redesign or speculative Finance framework;
- no DB/migration/RPC/RBAC/RLS/route-guard/backend business changes;
- no deployment/preview/main changes.

Stop condition:
If correct implementation would require changing Finance eligibility/workflow semantics, creating a Finance-specific parallel action model, or modifying output capabilities, mark `BLOCKED` instead of expanding the slice.

## Product migration roadmap

The Product Design Director may decompose an item further, but exactly one dependency-safe implementation slice becomes READY at a time.

### A. Golden flows
- `DS2-UI-001` Customer Form basic-info — `DONE`
- `DS2-UI-002` Customer detail secondary tabs/patterns — `DONE`
- `DS2-UI-003` Sales Orders list V2 — `DONE`
- `DS2-UI-004` Sales Order form V2 foundation — `DONE`
- `DS2-UI-005` Sales transaction detail V2 — `DONE`

### B. Shared component-depth program
Open only when a real migrated screen proves the recurring gap:
- FilterBar decomposition and Mobile filter-sheet contract
- DataTable V2 hardening and table action/accessibility/overflow-region contract
- shared Pagination convergence
- MobileDataCard semantic migration from legacy DataCard
- Modal/ResponsiveSheet/ConfirmDialog convergence
- Combobox/AsyncCombobox keyboard/focus hardening
- Tabs/SubNav/SegmentedControl adoption cleanup
- EntityHeader / TransactionHeader
- Timeline / ActivityFeed / AuditTimeline
- FinancialSummary / InventorySummary / ApprovalPanel
- BulkActionBar / CommandBar
- progress/accessibility contract
- upload/camera/GPS interaction grammar
- toast/alert/inline-validation convergence
- Loading/Empty/Error/Permission/Offline/Sync state grammar
- chart/report legend/metric grammar

### C. Inventory
- `DS2-INV-001` Inventory list surfaces — `DONE`
- `DS2-INV-002` Transfer/adjustment operational flows — `DONE`

### D. Procurement
- `DS2-PROC-001` Purchase list surfaces — `DONE`
- `DS2-PROC-002` Purchase Invoice form decomposition — `DONE`

### E. Finance
- `DS2-FIN-001` Finance lists and summaries — `DONE`
- `DS2-FIN-002` Payment Receipt transaction-detail header/action foundation — `READY`

### F. HR / People
- `DS2-HR-001` Mobile operational tasks — `BACKLOG`
- `DS2-HR-002` HR admin lists/forms — `BACKLOG`

### G. Field Activities / Targets
- `DS2-FIELD-001` Activities/visit/call/target lists — `BACKLOG`
- `DS2-FIELD-002` Field create/detail flows — `BACKLOG`

### H. Work Management
- `DS2-WORK-001` Reconcile Work UI island with V2 — `BACKLOG`

### I. Reports / Analytics
- `DS2-REPORT-001` Report shell/navigation/filter grammar — `BACKLOG`
- `DS2-REPORT-002` Metrics/charts/tables and responsive report composition — `BACKLOG`

### J. Settings / Administration
- `DS2-ADMIN-001` Users/roles/settings/audit surfaces — `BACKLOG`

### K. Global convergence and cleanup
- `DS2-GLOBAL-001` Global style debt and inline-style reduction — `BACKLOG`
- `DS2-GLOBAL-002` Dark mode / RTL / long Arabic / numeric stress pass — `BACKLOG`
- `DS2-GLOBAL-003` Accessibility/focus/touch/motion pass — `BACKLOG`
- `DS2-GLOBAL-004` Legacy component/CSS retirement — `BACKLOG`
- `DS2-GLOBAL-005` Final visual/system consistency audit — `BACKLOG`

## Integrator development gate

Before merge:
- exact current PR HEAD has `AGENT-REVIEW: GREEN-DEV`;
- reviewer records `SOURCE_REVIEW_PASS` and honest test evidence;
- no known build/type failure;
- no unresolved material blocker or current `BLOCKING` role-state contradiction;
- PR base is `design-system-v2-development`;
- diff contains no forbidden backend/business/query/permission/deployment change.

After merge:
- completed slice becomes DONE with reviewed/merge SHA and evidence;
- exactly one next dependency-safe roadmap item becomes READY;
- Integration State and Team Memory are synchronized;
- no preview deployment;
- no merge to `main`.

## End condition

The autonomous workstream continues until the North Star completion definition is met across major modules, shared component grammar, device behavior, RTL/dark/state/accessibility convergence and final controlled runtime review.
