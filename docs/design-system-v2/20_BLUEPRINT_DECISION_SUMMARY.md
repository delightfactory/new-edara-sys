# 20 — Blueprint Decision Summary

This file is the short decision record for the Delight Design System V2 source audit.

## Approved direction

1. **Refactor Edara; do not visually rewrite it from zero.** Existing tokens, mobile patterns and several shared components are strong enough to evolve.
2. **Mobile is the primary operational surface.** Tablet is a deliberate hybrid surface. Desktop is the primary dense management/analysis surface.
3. **Three screen families are supported:** Operational Task, Operational Transaction, Management/Analysis. One universal layout is explicitly rejected.
4. **No-functional-change contract is mandatory.** UI PRs do not change DB/RPC, business calculations, workflow/status transitions, RBAC/RLS, API/data contracts or responsibility rules.
5. **Tablet receives its own shell behavior.** The current binary `<=768 mobile / >768 desktop` approach is insufficient.
6. **The Design System expands beyond the current 13 core UI components.** Missing formal contracts such as Field, Tabs, Card/Section, StatusBadge, AlertPanel, ResponsiveCollection, ActionRegistry and task/report patterns will be introduced incrementally.
7. **Existing successful local patterns become shared standards.** Work responsiveness, Attendance task focus, Visit offline/sync states, Customers/Sales mobile cards and Reports overflow handling are reference implementations.
8. **Shared components are evolved before replacement.** Button, Input/Select, AsyncCombobox, ResponsiveModal, DataCard, DataTable, FilterBar, PageHeader, Stepper and ProofUpload are not discarded blindly.
9. **Local visual systems are retired progressively.** Page-local comboboxes, FABs, KPI cards, tabs, section headers, alert banners and repeated form grids move to approved patterns only after parity is proven.
10. **Actions are declared, not positioned by pages.** ActionRegistry coordinates PageHeader/toolbar/FAB/sticky/overflow presentation by device.
11. **Collections are device-aware.** Desktop tables and mobile cards are legitimate different presentations of the same capability; ResponsiveCollection standardizes their states and orchestration.
12. **Critical high-risk domains migrate after the primitives are stable.** Inventory, procurement, finance, HR/payroll, field execution and Work state-machine screens require explicit regression evidence.
13. **Vercel deployments are manual checkpoints only.** Git auto-deploy is disabled; commits do not consume deployment quota.
14. **Runtime screenshots remain a formal gate.** Source audit is sufficient to start low-risk foundations/component hardening, but broad visual shell/page composition is not called visually validated until runtime capture is completed.
15. **Manufacturing enters later as a V2 consumer.** It must reuse Edara’s product/inventory/transaction/task design grammar rather than arrive as a separate visual application.

## First implementation slice after runtime evidence

Foundations → core primitive hardening → shared patterns → App Shell/Tablet strategy → Dashboard → Customers → Sales.

This slice is intentionally chosen because it exercises almost every shared UI requirement before high-risk financial/inventory/manufacturing expansion.
