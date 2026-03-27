---
description: Global development rules and standards for EDARA v2 — Distribution ERP
---

# EDARA v2 — Global Development Rules

## Project Overview
EDARA is a comprehensive ERP system for a multi-branch distribution company in Egypt.
Tech stack: **Vite + React 18 + TypeScript + Supabase + Vanilla CSS**
Arabic-first, RTL, multi-role, designed for 5,000+ customers and 50,000+ orders.

---

## 🔴 Critical Rules (NEVER Violate)

### 1. Security Rules (HIGHEST PRIORITY)

- **RLS on EVERY table** — no exceptions. Every policy MUST call `check_permission(auth.uid(), '...')`
- **NEVER** use `auth.uid() IS NOT NULL` alone as an RLS policy — this is a security hole
- **NEVER** store permissions in localStorage — always fetch from DB on session start
- **NEVER** use `service_role` key in frontend code
- **Business logic belongs in DB functions** (SECURITY DEFINER + FOR UPDATE locks)
- Frontend permission checks (`can()`) are UX guidance only — DB is the real guard
- Always use `SECURITY DEFINER` for RPC functions that modify data
- **`check_permission()` function is the ONLY gate for access control** — see security-rls skill

### 2. Database Migration Rules

- **One migration file per phase** — idempotent (safe to re-run twice without error)
- All migrations MUST use `CREATE OR REPLACE`, `IF NOT EXISTS`, `DO $$ BEGIN...END $$`
- **Every migration includes**: tables + indexes + RLS + triggers + functions + seed data
- File naming: `NN_phase_name.sql` (e.g., `01_foundation.sql`)
- **Never store `current_balance` as a static number** — always compute from ledger

### 3. Development Order (STRICT — per module)
1. **Schema** → DB tables, functions, triggers, RLS policies
2. **Types** → TypeScript types matching schema exactly
3. **Validation** → Zod schemas for forms
4. **Service Layer** → Supabase queries in `lib/services/`
5. **Components** → Reusable UI components
6. **Pages** → Assemble using components
7. **Verification** → Test the complete flow

### 4. Performance Rules

- **NEVER load all rows** — cursor-based pagination (max 25 rows per page)
- For search comboboxes: fetch on demand (min 2 chars) — NEVER preload 500 items
- **ALWAYS index**: FK columns, search columns, ORDER BY columns, composite queries
- Use DB-level aggregation — never calculate sums in JavaScript
- Use `React Query` with `staleTime` to avoid redundant refetches
- Materialized views for heavy reports — refresh on demand
- `EXPLAIN ANALYZE` any query that touches > 1000 rows
- Use `select` specific columns in Supabase — never `select('*')` on large tables

### 5. Component Design Rules

- **Reusable first** — extract to `shared/` if used in 2+ places
- **Single Responsibility** — one component, one purpose
- Component hierarchy:
  - `ui/` → primitives (Button, Input, Select, Modal, Badge...)
  - `shared/` → business-agnostic (DataTable, FormField, EmptyState, PageHeader...)
  - `modules/[name]/` → module-specific compositions
- Extract all data-fetching logic into custom hooks (`useSalesOrders`, `useCustomers`...)

### 6. UI/UX Excellence Rules

- **Premium design is MANDATORY** — see design-rules workflow
- Every interaction must have visual feedback (loading, success, error)
- **Skeleton loaders** during data fetching — never blank screens
- Mobile-first responsive: test at 375px, 768px, 1024px, 1440px
- Arabic RTL is PRIMARY — see arabic-rtl skill
- Dark mode support from day one via CSS Variables only
- Accessibility: ARIA labels, keyboard navigation, focus management
- Confirmation dialogs for ALL destructive actions (delete, cancel, reverse)

### 7. Sales Order Rules (CRITICAL BUSINESS LOGIC)

- `sales_rep_id` is NEVER null on a confirmed/delivered order
- Credit check happens in DB function — NEVER in JavaScript
- Stock deduction happens in `deliver_sales_order()` RPC — not before
- Stock RESERVATION happens in `confirm_sales_order()` RPC
- Partial returns: always link to `order_item_id` + validate quantity ≤ remaining
- `payment_method` and `payment_terms` are ALWAYS visible fields — never hidden

### 8. Financial Integrity Rules

- **Ledger pattern**: all balances computed from transaction history, not stored numbers
- Every financial operation creates a journal entry automatically
- Vault/custody balance updates are ATOMIC with their source operation
- `approval_rules` are enforced in DB `approve_expense()` function — not just UI

### 9. UX Constitution (ABSOLUTE — No Exceptions)

These rules apply to EVERY component, EVERY screen. Non-negotiable.

#### 9.1 Mobile-First & Native-Feel
- **Bottom Navigation** is the primary routing mechanism on mobile (≤768px) — NEVER hamburger+drawer as primary nav
- **Bottom Sheets** for mobile modals/filters (slide from bottom, swipe to close) — NEVER centered modals on mobile
- All interactive elements (buttons, inputs, tabs) MUST have a minimum touch target of **44px height** (`--touch-target`)
- Mobile App Bar: glassmorphism sticky top bar showing page title + bell — no hamburger

#### 9.2 Data Presentation
- **Desktop**: Advanced Data Tables with sortable columns, row actions
- **Mobile**: Transform every table row into a **Data Card** with status badge, key fields, and swipe actions
- Use `var(--bottom-nav-height)` padding-bottom on all mobile pages to prevent BottomNav overlap

#### 9.3 Data Entry & Forms
- Long forms (≥4 sections) MUST use a **Stepper/Wizard** pattern with a step indicator
- Numeric inputs MUST use `inputmode="decimal"` and `enterkeyhint="done"` or `"next"`
- Phone inputs: `type="tel"` + `inputmode="numeric"` + `dir="ltr"`

#### 9.4 Micro-interactions
- **Skeleton Loaders** during all fetch states — NEVER blank screens or spinners alone
- **Empty States** with icon + Arabic message + CTA button — NEVER blank lists
- **Toasts** (sonner) for all feedback — position `top-center`, never blocking alerts

#### 9.5 Permission-Driven UI
- Use `<PermissionGuard>` wrapper for ANY action that requires a permission
- `mode="hide"` → renders null if no permission (default)
- `mode="disable"` → renders grayed-out element with lock icon + aria-disabled + tooltip
- Frontend permission checks are UX ONLY — DB is always the real guard

#### 9.6 Settings-Driven UI
- Components MUST react to `company_settings` dynamically
- Example: if `sales.tax_enabled === false` → hide tax fields entirely
- Load settings once at app start via `useCompanySettings()` hook — never refetch per component

---

## 📁 Project Architecture

```
src/
├── components/
│   ├── ui/             # Primitive components (Button, Input, Dialog...)
│   ├── shared/         # Reusable business components (DataTable, StatCard...)
│   └── modules/        # Module-specific compositions
├── lib/
│   ├── supabase/       # client.ts, hooks.ts
│   ├── hooks/          # Custom React hooks
│   ├── services/       # Data access layer (one file per module)
│   ├── types/          # TypeScript interfaces
│   ├── validations/    # Zod schemas
│   ├── permissions/    # Permission constants + helpers
│   └── utils/          # currency, dates, formatting
├── pages/              # Route pages (organized by module)
├── stores/             # Zustand (auth, ui — no persistence for permissions)
└── styles/             # CSS tokens + design system
```

---

## 🔄 Workflow Per Module

1. Review `implementation_plan.md` for the module spec
2. Write SQL migration (idempotent) — run it twice to verify
3. Write TypeScript types in `lib/types/[module].ts`
4. Write Zod validation schemas in `lib/validations/[module].ts`
5. Build service layer in `lib/services/[module].ts`
6. Create custom hooks in `lib/hooks/use[Module].ts`
7. Build shared components if needed
8. Build module pages
9. Test full business flow (happy path + error cases)
10. Run performance check with realistic data volume

---

## 🌐 RTL & Arabic

- See `arabic-rtl` skill for full details
- Font: **Cairo** from Google Fonts — mandatory
- Direction: `<html lang="ar" dir="rtl">`
- Use CSS logical properties (`margin-inline-start` not `margin-left`)
- Numbers: Western Arabic (0-9), Currency: `1,500.00 ج.م`
- LTR for: email, password, phone, technical codes

---

## 📦 Allowed Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| react + react-dom | 18.x | UI framework |
| react-router-dom | 6.x | Routing |
| @supabase/supabase-js | 2.x | Database |
| @tanstack/react-query | 5.x | Server state |
| zustand | 4.x | Client state |
| react-hook-form | 7.x | Forms |
| zod | 3.x | Validation |
| sonner | latest | Toasts |
| recharts | 2.x | Charts |
| lucide-react | latest | Icons |
| date-fns | 3.x | Date utils |

**NO**: Tailwind, shadcn, MUI, Ant Design, or any heavy UI library
