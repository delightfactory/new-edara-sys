# 14 — Route & Page Inventory

Source of truth: `src/App.tsx` on `main`. This inventory exists so the UI refactor cannot silently omit a screen. `Deep` means representative source has already been inspected in this audit; `Mapped` means the route is registered for its module wave and requires representative source/runtime review before migration.

## Shell / Auth
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/login` | Login | Auth form | Mapped |
| `/unauthorized` | Unauthorized | Permission state | Mapped |
| `/` | Dashboard | Dashboard / action center | Deep |
| `*` | Not Found | Error state | Mapped |

## Products
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/products` | Products | Entity list | Mapped |
| `/products/new` | Product create | Form | Mapped |
| `/products/:id` | Product detail | Entity detail | Mapped |
| `/products/:id/edit` | Product edit | Form | Mapped |
| `/products/categories` | Categories | Master-data list/manage | Mapped |
| `/products/price-lists` | Price lists | Master-data / pricing | Mapped |
| `/products/bundles` | Bundles | Master-data / composite product | Mapped |
| `/products/brands` | Brands | Master-data list/manage | Mapped |

## Customers & Credit
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/customers` | Customers | Responsive entity list | Deep |
| `/customers/new` | Customer create | Complex form | Deep representative form |
| `/customers/:id` | Customer detail | Entity detail | Mapped |
| `/customers/:id/edit` | Customer edit | Complex form | Deep representative form |
| `/credit` | Credit management | Operational/financial queue | Mapped |
| `/credit/overdue` | Overdue invoices | Risk/collection queue | Mapped |

## Suppliers
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/suppliers` | Suppliers | Entity list | Mapped |
| `/suppliers/new` | Supplier create | Form | Mapped |
| `/suppliers/:id` | Supplier detail | Entity detail | Mapped |
| `/suppliers/:id/edit` | Supplier edit | Form | Mapped |

## Inventory
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/inventory/warehouses` | Warehouses | Master-data / operational list | Mapped |
| `/inventory/stock` | Stock | Dense inventory list | Mapped |
| `/inventory/transfers` | Transfers | Transaction list + create | Deep |
| `/inventory/transfers/:id` | Transfer detail | Transaction detail | Mapped |
| `/inventory/adjustments` | Adjustments | Transaction list + create | Mapped |
| `/inventory/adjustments/:id` | Adjustment detail | Transaction detail | Mapped |
| `/inventory/movements` | Stock movements | Audit/ledger list | Mapped |
| `/inventory/valuation` | Inventory valuation | Financial inventory report | Mapped |

## Sales
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/sales/orders` | Sales orders | Responsive transaction list | Deep |
| `/sales/orders/new` | Sales order create | Multi-step transaction form | Deep |
| `/sales/orders/:id` | Sales order detail | Transaction detail | Mapped |
| `/sales/orders/:id/edit` | Sales order edit | Multi-step transaction form | Deep |
| `/sales/returns` | Sales returns | Transaction list | Mapped |
| `/sales/returns/new` | Sales return create | Transaction form | Mapped |
| `/sales/returns/:id` | Sales return detail | Transaction detail | Mapped |
| `/sales/shipping` | Shipping companies | Master-data/manage | Mapped |

## Procurement
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/purchases/invoices` | Purchase invoices | Transaction list | Mapped |
| `/purchases/invoices/new` | Purchase invoice create | Multi-step transaction form | Deep |
| `/purchases/invoices/:id` | Purchase invoice lifecycle/detail | Transaction form/detail hybrid | Deep representative form |
| `/purchases/returns` | Purchase returns | Transaction list | Mapped |
| `/purchases/returns/new` | Purchase return create | Transaction form | Mapped |
| `/purchases/returns/:id` | Purchase return lifecycle | Transaction form/detail hybrid | Mapped |

## Finance
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/finance/vaults` | Vaults | Financial entity/action list | Mapped |
| `/finance/custody` | Custody | Financial operational list | Mapped |
| `/finance/payments` | Payment receipts | Responsive financial transaction list/create | Deep |
| `/finance/payments/:id` | Payment detail | Financial transaction detail | Mapped |
| `/finance/expenses` | Expenses | Financial list/create | Mapped |
| `/finance/accounts` | Chart of accounts | Accounting tree/list | Mapped |
| `/finance/journals` | Journals | Accounting transaction list | Mapped |
| `/finance/ledger` | Ledger | Accounting dense report | Mapped |
| `/finance/approval-rules` | Approval rules | Configuration / approval matrix | Mapped |
| `/finance/balance-sheet` | Financial balance sheet | Accounting report | Mapped |

## Branches
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/branches` | Branches | Master-data / organization list | Mapped |

## HR
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/hr` | HR dashboard | Dashboard | Mapped |
| `/hr/employees` | Employees | Entity list | Mapped |
| `/hr/employees/:id` | Employee profile | Complex entity profile | Mapped; file-size risk identified |
| `/hr/attendance/checkin` | Attendance check-in/out | Mobile operational task | Deep |
| `/hr/attendance` | Attendance admin | Monitoring/admin list | Mapped |
| `/hr/leaves` | Leaves | Request/approval queue | Mapped |
| `/hr/advances` | Advances | Financial request/approval queue | Mapped |
| `/hr/payroll` | Payroll runs | Payroll list | Mapped |
| `/hr/payroll/:runId` | Payroll run detail | Financial detail | Mapped |
| `/hr/payroll/target-payouts` | Target payouts | Payroll/commission list | Mapped |
| `/hr/permissions` | HR permissions/requests | Request/approval queue | Mapped |
| `/hr/commissions` | Commissions | Financial HR list/form | Mapped |
| `/hr/settings` | HR settings | Configuration | Mapped |
| `/hr/delegations` | Delegations | Approval/delegation list | Mapped |
| `/hr/adjustments` | Rewards/deductions adjustments | Financial HR transaction list | Mapped |
| `/hr/my-profile` | My profile | Self-service entity detail | Mapped |

## Work Management
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/work` | Work hub | Action center / operational queue | Deep |
| `/work/new` | Create task | Form | Mapped |
| `/work/manage` | Work administration | Configuration/management | Mapped |
| `/work/team` | Supervisor/team work | Management queue | Mapped |
| `/work/:id` | Work detail | Stateful operational detail | Mapped with shell/pattern review |

## Notifications
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/notifications` | Notifications | Feed/queue | Mapped |

## Reports / Analytics
All child routes share `/reports` and `ReportsLayout`, whose shell has been deeply inspected.

| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/reports` | Reports redirect | Navigation redirect | Deep shell |
| `/reports/overview` | Overview | Analytics dashboard | Mapped |
| `/reports/sales` | Sales report | Analytics/report | Mapped |
| `/reports/receivables` | Receivables | Financial report | Mapped |
| `/reports/treasury` | Treasury | Financial report | Mapped |
| `/reports/customers` | Customer health | Analytics/report | Mapped |
| `/reports/reps` | Rep performance | Analytics/report | Mapped |
| `/reports/visits` | Visit reports | Operational analytics | Mapped |
| `/reports/products` | Product performance | Analytics/report | Mapped |
| `/reports/churn-risk` | Churn risk | Risk analytics | Mapped |
| `/reports/geography` | Geography | Geographic analytics | Mapped |
| `/reports/target-attainment` | Target attainment | Target analytics | Mapped |
| `/reports/credit-commitment` | Rep credit commitment | Risk/compliance analytics | Mapped |
| `/reports/reengagement` | Customer re-engagement | Operational report/action surface | Mapped |
| `/reports/profitability` | Profitability dashboard | Financial analytics shell | Mapped |
| `/reports/profitability/products` | Product profitability | Financial analytics | Mapped |
| `/reports/profitability/customers` | Customer profitability | Financial analytics | Mapped |
| `/reports/profitability/reps` | Rep profitability | Financial analytics | Mapped |
| `/reports/profitability/branch-direct` | Branch direct profit | Financial analytics | Mapped |
| `/reports/profitability/branch-final` | Branch final profit | Financial analytics | Mapped |
| `/reports/profitability/quality` | Allocation quality | Data-quality analytics | Mapped |

## Settings / Administration
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/settings/users` | Users | Admin list | Mapped |
| `/settings/users/new` | Create user | Admin form | Mapped |
| `/settings/users/:id/edit` | Edit user | Admin form | Mapped |
| `/settings/roles` | Roles | Admin list | Mapped |
| `/settings/roles/new` | Create role | Permission form | Mapped |
| `/settings/roles/:id/edit` | Edit role | Permission form | Mapped |
| `/settings/company` | Company settings | Settings form/list | Mapped |
| `/settings/audit` | Audit log | Audit/ledger table | Mapped |

## Activities / Field Operations
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/activities` | Activities dashboard | Dashboard/action center | Mapped |
| `/activities/list` | Activities | Responsive operational list | Mapped |
| `/activities/new` | Create activity | Form | Mapped |
| `/activities/:id` | Activity detail | Operational detail/timeline | Mapped |
| `/activities/:id/edit` | Edit activity | Form | Mapped |
| `/activities/types` | Activity types | Configuration | Mapped |
| `/activities/target-types` | Target types | Configuration | Mapped |
| `/activities/visit-plans` | Visit plans | Plan list | Mapped |
| `/activities/visit-plans/new` | Create visit plan | Planning form | Mapped |
| `/activities/visit-plans/:id` | Visit plan detail | Plan detail | Mapped |
| `/activities/visit-plans/:id/execute` | Visit execution | Mobile operational task | Deep |
| `/activities/call-plans` | Call plans | Plan list | Mapped |
| `/activities/call-plans/new` | Create call plan | Planning form | Mapped |
| `/activities/call-plans/:id` | Call plan detail | Plan detail | Mapped |
| `/activities/targets` | Targets | Target list | Mapped |
| `/activities/targets/new` | Create/assign target | Complex form | Mapped |
| `/activities/targets/:id` | Target detail | Target analytics/detail | Mapped |
| `/activities/checklists` | Checklist templates | Configuration/form builder | Mapped |
| `/activities/plan-templates` | Plan templates | Configuration | Mapped |

## Output / Documents
| Route | Surface | Archetype | Audit |
|---|---|---|---|
| `/documents/:kind/:id/preview` | Document preview | Document/output viewer | Mapped |

## Inventory rule for implementation
Before a migration wave is marked complete:
1. every route in that module must have an explicit status: migrated / intentionally unchanged / blocked with issue;
2. create/edit/detail variants must be checked independently even when they share one React component;
3. mobile, tablet and desktop evidence is required according to the device role of that surface;
4. no route may disappear from navigation or lose permission behavior as a side effect of the refactor.
