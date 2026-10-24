# 31 — Visual Direction Concept (Claude)

**Status:** Proposed — pending owner approval and Codex review. Not a runtime audit; does not close the gate in `19_RUNTIME_AUDIT_BLOCKER_AND_HANDOFF.md`.

**Visual boards (private to the owner until shared):** https://claude.ai/artifact/9nKKz3m6bQbYgDu9DXSqFg
**Board sources (readable without access):** `docs/design-system-v2/visual-concept/*.dc.html` — design-canvas templates (they need the canvas runtime to render, so open them as text). Every color, size and label is inline; repeated rows and computed brand shades are in each file's `renderVals()` script.

## What this is
A concrete visual direction for the V2 program: exact token values, the shell layout and seven screens drawn from the real code (routes, fields, columns, statuses, permissions, document number formats). It is the "visual freeze candidate" that the Blueprint (`17`, `20`) says should follow source audit.

It does **not** change the program's architecture, boundaries or sequencing. Everything here maps onto the existing `--ds-*` alias layer (`src/styles/design-system-v2-foundations.css`) and the no-functional-change contract (`06`).

## Grounding rules used
- Every label, column, filter, tab, step, status and action in the screen boards is copied from source (`SalesOrdersPage`, `SalesOrderForm`, `SalesOrderDetail`, `CustomerDetailPage`, `CustomerIntelligenceTab`, `DashboardPage`, `GoalCommandCenter`, `WorkHubPage`, `VisitExecutionMode`, `navigation/registry.ts`, `navigation/sidebar.ts`, `navigation/mobile.ts`, `lib/types/*`).
- Anything not present today carries a purple **«مقترح»** badge in the boards. Values in `[ ]` are placeholders for data the existing queries already return.
- Customer names and amounts are illustrative; formats are real (`SO-YYYYMMDD-NNNN` from `04_sales_system.sql`, `CUS-NNNNN`).

## Board index
| # | Board file | Content |
|---|---|---|
| 00 | `Main.dc.html` | Source-audit metrics and principles |
| 00b | `SystemMap.dc.html` | Real IA (8 registry groups → 12 sidebar menus → 75 pages), sales-order lifecycle, status dictionary → 5 semantic tones, white-label gap |
| 01 | `Foundations.dc.html` | Color, type, spacing, radius, elevation, density |
| 02 | `Components.dc.html` | Button, StatusBadge, Field family, DataTable, StatCard, Tabs, AlertPanel, Toast, EmptyState, Dialog |
| 03 | `Dashboard.dc.html` | Shell + Dashboard (GoalCommandCenter, KPIs, revenue, follow-up) |
| 04 | `OrdersList.dc.html` | Sales orders list (real columns/filters/KPIs, Smart Transfer) |
| 05 | `OrderForm.dc.html` | Sales order create — existing 4-step flow |
| 06 | `OrderDetail.dc.html` | Order detail + Deliver dialog (payment terms, collection method/destination, proof) |
| 07 | `CustomerDetail.dc.html` | Customer 360 tab, aging buckets, recommendation chips |
| 08 | `Mobile.dc.html` | Work Hub, Visit Execution, Orders cards, BottomNav/FAB |

## Proposed values → existing token layer
Physical tokens in `tokens.css` change value; `--ds-*` aliases keep their names. Components keep consuming `--ds-*`.

### Color (light)
| Role (`--ds-*`) | Current physical | Proposed |
|---|---|---|
| `action-primary` (`--color-primary`) | `#2563eb` | `#0F6E7A` (tenant-overridable) |
| `action-primary-hover` | `#1d4ed8` | brand shaded 20% (`#0C5862`) |
| `action-primary-subtle` | `rgba(37,99,235,.1)` | brand tinted 90% (`#E7F1F2`) |
| `surface-app` | `#f0f2f5` | `#F3F5F7` |
| `surface-default` | `#ffffff` | `#FFFFFF` |
| `surface-subtle` | `#f8f9fc` | `#F9FAFB` |
| `text-primary` | `#111827` | `#0F1A23` |
| `text-secondary` | `#6b7280` | `#5B6875` (5.7:1 on white) |
| `text-muted` | `#9ca3af` (≈2.5:1 on white — fails AA for text) | `#5B6875` for text; `#8994A0` (≈3.1:1) only for non-text marks |
| `border-default` | `#e5e7eb` | `#E7EBEF`; field border `#D5DBE1` |
| shell rail (new) | — | `#0D1B24`, rail text `#A9B8C0`, accent `#C9962B` (decorative only) |

Status families (fg / bg), each ≥4.5:1 for 12px text:
| Tone | fg | bg |
|---|---|---|
| neutral | `#4A5763` | `#F0F2F5` |
| info | `#175CD3` | `#EAF1FD` |
| success | `#13774A` | `#E7F4EC` |
| warning | `#A15C07` | `#FDF3E2` |
| danger | `#B42318` | `#FDECEA` |

Status → tone mapping for every domain status type is in `SystemMap.dc.html` (sales orders, returns, purchase invoices, transfers, adjustments, expenses, payment receipts, visit plans, leave, advances, payroll, users). This is intended to become the single `StatusBadge` mapping table.

### Type
| Role | Size / line / weight |
|---|---|
| page-title | 24 / 32 / 700 |
| section-title | 16 / 24 / 600 |
| body | 14 / 22 / 400 |
| label | 13 / 20 / 600 |
| helper / caption | 12 / 16 / 500 |
| numeric-kpi | 20–26 / 700, tabular-nums |

Font: concept uses **IBM Plex Sans Arabic** (+ IBM Plex Mono for codes/document numbers). `02_FOUNDATIONS.md` currently says Cairo — see decision D1.

### Shape / density
- Radius: badge 4, control 6, card 8, dialog 12, pill 999 (tighter than current 6/10/14/20).
- Control height: 36 desktop (= `--ds-control-height-compact`), 44 touch, 48 task CTA. Table row 44 standard.
- Elevation: borders first; shadows only for dropdowns (e1), dialogs/drawers (e2).

## Shell proposal
- Desktop: dark 76px **module rail** = the 8 `NavigationGroupId`s already in `registry.ts` (home, operations, inventory, finance, field, people, insights, settings) + white **context panel** listing that group's `sidebar.ts` menus. No route/permission change; it is a renderer over the existing model (`26`, `27`).
- Tablet: rail only; context panel as overlay.
- Mobile: unchanged contract from `mobile.ts` (الرئيسية / العمل / المبيعات / العملاء / القائمة) + route-scoped FAB from `CREATION_ACTIONS`.

## Proposed additions (each needs its own decision/PR — not part of a visual migration)
- Global search / command palette (navigation-only first; entity search would be a functional epic).
- Persistent key-info side panel on Customer detail.
- Multi-select on DataTable (bulk print only; no bulk mutations).
- Tenant UI branding keys in `company_settings`: `ui.brand_color`, `ui.app_name`, `ui.density`. Data/config change → separate PR per `06`.

## Open decisions (owner)
| ID | Question | Concept position |
|---|---|---|
| D1 | Cairo vs IBM Plex Sans Arabic | Plex; validate with runtime A/B on Dashboard + Orders list before freeze |
| D2 | Default brand color + tenant override mechanism | `#0F6E7A`; CSS vars set at boot from `company_settings` |
| D3 | Module rail of 8 registry groups vs the 7-group IA sketched in `04` | Use the 8 groups that already exist in code; revisit after runtime IA validation |
| D4 | Dark rail vs current light SidebarV2 | Dark rail |
| D5 | Tighter radius scale | Yes |

## Known factual caveats
- `partially_delivered` exists in the DB constraint and is counted as pending on the Dashboard, but no partial-delivery UI path was found.
- Arabic labels for transfer/adjustment/expense/visit-plan/HR statuses in `SystemMap` were authored from the type values; no label maps were found in those pages. Verify before adopting.
