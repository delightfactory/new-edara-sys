# 17 — Blueprint Index & Status

## Program status

**Source architecture/design audit:** substantially complete for Blueprint purposes.

**Runtime visual audit:** required and intentionally open. Source inspection cannot validate actual hierarchy, rendered density, contrast, clipping, browser/device behavior or interaction feel.

**Implementation:** not started in this Blueprint PR. This branch remains documentation/audit + deployment-control configuration only.

## Document map

| Doc | Purpose | Status |
|---|---|---|
| `README.md` | Program charter and boundaries | Established |
| `01_CURRENT_UI_AUDIT.md` | Initial source-backed current-state audit | Established |
| `02_FOUNDATIONS.md` | Typography/color/spacing/RTL/responsive/accessibility foundations | Draft ready for runtime validation |
| `03_COMPONENT_SYSTEM.md` | Layered component taxonomy and migration rules | Established |
| `04_PAGE_PATTERNS_AND_IA.md` | Shared page grammar and proposed IA | Requires runtime IA validation |
| `05_MIGRATION_MATRIX.md` | Wave-based module rollout | Established |
| `06_QA_AND_GUARDRAILS.md` | No-functional-change contract and QA gates | Established |
| `07_IMPLEMENTATION_ROADMAP.md` | High-level sequence | Established |
| `08_RUNTIME_VISUAL_AUDIT.md` | Required runtime capture/evaluation plan | Open gate |
| `09_DEVICE_STRATEGY.md` | Mobile-primary operational, tablet hybrid, desktop management strategy | Established |
| `10_SOURCE_AUDIT_FINDINGS.md` | Concrete code-grounded debt and strengths | Established |
| `11_GOLDEN_FLOW_ACCEPTANCE.md` | Device-specific acceptance for shell/dashboard/customers/sales | Established |
| `12_COMPONENT_DECISION_MATRIX.md` | Retain/evolve/decompose/replace decisions | Established |
| `13_MODULE_UI_AUDIT_MATRIX.md` | Module-level device/debt/risk map | Established; mapped modules require pre-wave representative audit |
| `14_ROUTE_PAGE_INVENTORY.md` | Route-level completeness checklist | Established |
| `15_CONTROL_AND_FORM_CONTRACTS.md` | Button/field/badge/dialog/table/filter/action contracts | Established |
| `16_CURRENT_COMPONENT_INVENTORY_AND_GAPS.md` | Actual current components vs V2 gaps | Established |
| `18_IMPLEMENTATION_EPICS.md` | Executable PR/epic sequence | Established when present |

## Source-audit evidence coverage

### Deeply inspected
- tokens/global component styling
- AppLayout / Sidebar / BottomNav / FAB
- core UI directory and key primitives
- PageHeader / DataTable / FilterBar
- Dashboard
- Customers list + create/edit representative
- Sales list + create/edit representative
- Inventory Transfers
- Finance Payments
- Purchase Invoice form/lifecycle representative
- HR Attendance Check-in
- Visit Execution Mode
- Work Hub + responsive work styles
- Reports shell
- Product form
- Supplier form representative
- Role/permission form
- Notifications tabs wrapper

### Mapped but not runtime-approved
All remaining routes are inventoried in `14_ROUTE_PAGE_INVENTORY.md`. A module does not require every source file to be exhaustively audited now; it requires representative source/runtime inspection immediately before its migration wave.

## Confirmed program-level findings

1. Edara already has meaningful design infrastructure; the UI problem is primarily **fragmentation and incomplete adoption**, not absence of all foundations.
2. Mobile is already treated seriously in several domains, but device behavior is inconsistent across modules and the global shell has an explicit tablet gap.
3. The product currently contains several locally successful design systems: Work, Attendance, Visit Execution, Reports, and the Customers/Sales responsive collections. V2 should extract the strongest ideas and make them shared infrastructure.
4. Critical forms frequently bypass shared UI primitives; this is the primary source of form inconsistency.
5. Repeated local FABs, tabs, status maps, alerts, KPI cards, sections and comboboxes demonstrate clear missing system patterns.
6. A visual refactor can be done without touching business rules if PR boundaries are enforced.

## Open gate: runtime visual audit

Before the visual direction and shell IA are considered final, capture and inspect the running product at minimum:
- phone 360–390
- phone 430
- tablet portrait ~768/834
- tablet landscape ~1024
- desktop 1280
- wide desktop 1440+

Representative flows are listed in `08_RUNTIME_VISUAL_AUDIT.md` and `11_GOLDEN_FLOW_ACCEPTANCE.md`.

This gate can adjust visual values, hierarchy and component composition. It must not silently change domain behavior.

## Blueprint exit criteria

The Blueprint may be marked ready for implementation when:
- source audit documents are complete enough to guide the first implementation waves;
- no-functional-change boundary is explicit;
- device strategy is explicit;
- current components have retain/evolve/decompose decisions;
- routes are inventoried;
- Golden Flow acceptance exists;
- implementation epics/PR boundaries exist;
- runtime audit is either completed or explicitly carried as a pre-implementation/pre-visual-freeze gate.

## Current recommendation
The source Blueprint is sufficient to define and start **Foundations and low-level component hardening**, because those decisions are code-grounded and low visual-risk. Broad visual redesign of App Shell and Golden Flow page composition should wait for runtime evidence before final visual freeze.
