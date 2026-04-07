# Analytics Foundation: Final Polish

- `[x]` Fix Return Tax Formula Alignment (Match GL `so.tax_amount / so.subtotal`)
- `[x]` Fix Customer Health Recency Null Semantics (`recency_days = NULL`, strictly handle `is_dormant`)
- `[x]` Add Explicit `REVOKE` on Sensitive Dimensional Tables (`dim_product`, `dim_customer`, etc.)
- `[x]` Document Phase 1 Output Scopes (Only Revenues, AR, Treasury, Health)
- `[x]` Standardize Semantic Contract of `VERIFIED`

## UI Phase 1 Boundaries:
- **INCLUDED:** Sales Revenue views, AR creation / receivables views, Treasury cashflow views, Customer health views, System Trust/Freshness states.
- **EXCLUDED:** Accounting P&L, Managerial P&L, Financial-ledger-driven executive profitability surfaces.
