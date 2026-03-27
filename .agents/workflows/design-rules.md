---
description: Design rules and UI standards for EDARA v2 — mandatory for all components
---

# EDARA Design Rules — v2

## 1. Design Philosophy
EDARA's UI must feel **premium, trustworthy, and purposeful**.
Users are enterprise workers who need clarity and speed over creativity.
Every screen should reduce cognitive load, not add to it.

**3 guiding principles:**
1. **Clarity first** — what is the most important action? Make it obvious
2. **Feedback always** — every user action gets a response (loading, success, error)
3. **Role-aware** — each role sees ONLY what they need (no clutter)

---

## 2. Color Palette

```css
/* Primary — Trust Blue */
--color-primary: #2563eb;          /* actions, links, focus */
--color-primary-hover: #1d4ed8;
--color-primary-light: rgba(37,99,235,0.1);

/* Success */
--color-success: #16a34a;
--color-success-light: rgba(22,163,74,0.1);

/* Warning */
--color-warning: #d97706;
--color-warning-light: rgba(217,119,6,0.1);

/* Danger */
--color-danger: #dc2626;
--color-danger-light: rgba(220,38,38,0.1);

/* Info */
--color-info: #0284c7;
--color-info-light: rgba(2,132,199,0.1);

/* Neutrals — light mode */
--neutral-50: #f8fafc;
--neutral-100: #f1f5f9;
--neutral-200: #e2e8f0;
--neutral-300: #cbd5e1;
--neutral-500: #64748b;
--neutral-700: #334155;
--neutral-900: #0f172a;
```

---

## 3. Typography Scale

```css
--text-xs: 0.75rem;    /* 12px — hints, captions */
--text-sm: 0.875rem;   /* 14px — table cells, labels */
--text-base: 0.9375rem; /* 15px — body text (Arabic baseline) */
--text-lg: 1.0625rem;  /* 17px — card titles */
--text-xl: 1.25rem;    /* 20px — page subtitles */
--text-2xl: 1.5rem;    /* 24px — page titles */
--text-3xl: 1.875rem;  /* 30px — dashboard stats */
```

---

## 4. Spacing System

```css
/* Base unit: 4px */
--space-1: 0.25rem;   /* 4px */
--space-2: 0.5rem;    /* 8px */
--space-3: 0.75rem;   /* 12px */
--space-4: 1rem;      /* 16px */
--space-5: 1.25rem;   /* 20px */
--space-6: 1.5rem;    /* 24px */
--space-8: 2rem;      /* 32px */
--space-10: 2.5rem;   /* 40px */
--space-12: 3rem;     /* 48px */
```

---

## 5. Component Standards

### Page Header
```tsx
<PageHeader
  title="طلبات البيع"
  subtitle="إدارة ومتابعة أوامر البيع"
  icon={<ShoppingCart />}
  actions={<Button onClick={handleNew}>طلب جديد</Button>}
  stats={[
    { label: 'إجمالي الطلبات', value: '1,234' },
    { label: 'معلقة', value: '23', variant: 'warning' }
  ]}
/>
```

### Data Tables
- Always paginated (25 rows default, options: 10/25/50)
- Search bar always present for large datasets
- Status badges with consistent colors across all modules
- Row actions in a compact menu (not individual buttons)
- Empty state with icon + message + CTA

### Forms
- Group related fields in cards
- Required fields marked with `*` in the label
- Inline validation (on blur, not on submit only)
- Submit button: always bottom-right, with loading state
- Cancel button: always bottom-left
- For complex forms: use a step indicator

### Modals
- Use for: confirmation dialogs, small single-field edits
- Use full page for: complex forms with multiple sections
- Always include: title, content, clear action buttons
- Destructive actions: danger-colored button, confirmation text

---

## 6. Status Badge Colors

| Status | Arabic | Color |
|--------|--------|-------|
| `draft` | مسودة | neutral |
| `pending` | معلق | warning |
| `approved` | معتمد | info |
| `confirmed` | مؤكد | primary |
| `delivered` | مُسلّم | success |
| `completed` | مكتمل | success |
| `cancelled` | ملغي | danger |
| `rejected` | مرفوض | danger |
| `overdue` | متأخر | danger |

---

## 7. Loading States

```tsx
// Page loading: skeleton cards, not spinner
const PageSkeleton = () => (
  <div className="space-y-4">
    {[1,2,3,4,5].map(i => (
      <div key={i} className="skeleton-row" />
    ))}
  </div>
)

// Button loading: spinner inline
<Button disabled={loading}>
  {loading ? <Spinner className="h-4 w-4 animate-spin" /> : null}
  {loading ? 'جاري الحفظ...' : 'حفظ'}
</Button>
```

```css
.skeleton-row {
  height: 48px;
  border-radius: 8px;
  background: linear-gradient(90deg, 
    var(--bg-surface-2) 25%, 
    var(--bg-hover) 50%,
    var(--bg-surface-2) 75%
  );
  background-size: 200% 100%;
  animation: shimmer 1.5s infinite;
}

@keyframes shimmer {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}
```

---

## 8. Micro-Animations

```css
/* Page entry */
@keyframes fade-in {
  from { opacity: 0; transform: translateY(8px); }
  to { opacity: 1; transform: translateY(0); }
}
.animate-enter { animation: fade-in 0.3s ease-out; }

/* Card hover */
.edara-card {
  transition: box-shadow 0.2s, transform 0.2s;
}
.edara-card:hover {
  box-shadow: var(--shadow-md);
  transform: translateY(-1px);
}

/* Button press */
.btn:active { transform: scale(0.98); }
```

---

## 9. Dashboard StatCards

```tsx
<StatCard
  label="إجمالي المبيعات"
  value="124,500 ج.م"
  change={+12.4}  // percentage change from last period
  trend="up"
  icon={<TrendingUp />}
  color="success"
  period="هذا الشهر"
/>
```

---

## 10. Role-Based UI Adaptation

The sidebar and available features MUST adapt to the user's role:

| Role | Sidebar Modules |
|------|----------------|
| super_admin / CEO | كل الوحدات |
| branch_manager | المبيعات + المشتريات + المالية + HR (فرعه) |
| sales_rep | طلباتي + عملائي + أهدافي + أنشطتي |
| warehouse_keeper | المخازن + الاستلام + التحويلات |
| accountant | المالية + التقارير المالية |
| hr_manager | الموارد البشرية + الرواتب |

The sidebar should show ONLY the sections the user has permissions to access.
No need to show "Coming Soon" items — just hide what's not permitted.

---

## 11. PWA & Mobile-First Architecture

EDARA v2 is a Progressive Web App. Mobile experience has the SAME priority as desktop.

### App Bar (Mobile Top Bar)
```
┌─────────────────────────┐
│  [Page Title]   🔔  │  ← height: var(--app-bar-height) = 56px
└─────────────────────────┘
```
- Sticky `position: fixed; top: 0`
- Background: `var(--app-bar-bg)` + `backdrop-filter: var(--app-bar-blur)`
- Z-index: `var(--z-app-bar)` = 140
- Title: injected via `PageTitleContext` (each page sets its own title)
- NO hamburger icon — menu access is via BottomNav "القائمة" tab

### Bottom Navigation (Mobile)
```
┌─────────────────────────┐
│ 🏠 | 🛒 | 👥 | ☰     │  ← height: var(--bottom-nav-height) = 64px
│ Home Sales Cust Menu  │
└─────────────────────────┘
```
- `position: fixed; bottom: 0; left: 0; right: 0`
- Z-index: `var(--z-bottom-nav)` = 150
- Background: `var(--bottom-nav-bg)` + `backdrop-filter: var(--bottom-nav-blur)`
- Active tab indicator: 2px top border + primary-colored icon
- Each tab: min 44px × 64px

### Thumb Zone
Primary actions (FAB, BottomNav) are placed in the thumb-reachable zone (bottom 40% of screen). Secondary actions can be in the App Bar.

---

## 12. Data Cards (Mobile Transformation Pattern)

Every data table row MUST become a card on mobile:

```
┌─────────────────────────┐
│ [Icon] Title       [Badge] │  ← Primary info row
│        subtitle    Value   │  ← Secondary detail
│ [Action 1]  [Action 2]     │  ← Quick actions (44px tap)
└─────────────────────────┘
```
- Use `@media (max-width: 768px)` to switch from `.data-table` to `.mobile-card-list`
- Always show: status badge, primary identifier, date, amount
- Quick actions: max 2 buttons, 44px tall, clearly labeled

---

## 13. PermissionGuard Pattern

```tsx
// Mode: "hide" (default) — element disappears if no permission
<PermissionGuard permission="procurement.invoices.bill">
  <Button>إنشاء فاتورة دفع</Button>
</PermissionGuard>

// Mode: "disable" — grayed-out + lock icon + accessible tooltip
<PermissionGuard permission="sales.orders.delete" mode="disable">
  <Button variant="danger">حذف الطلب</Button>
</PermissionGuard>
```

**Rules:**
- `permission` can be `string | string[]` (array = any-of logic)
- `mode="hide"` renders `null` — element is invisible
- `mode="disable"` wraps in a div with `aria-disabled="true"` + `title="ليس لديك صلاحية"` + lock icon overlay
- NEVER show an interactive element that, when clicked, shows "ليس لديك صلاحية" — guard it first

---

## 14. FAB (Floating Action Button)

- **Mobile only** (`display: none` on ≥769px)
- Size: `var(--fab-size)` = 56px × 56px
- Position: `fixed; bottom: calc(var(--bottom-nav-height) + var(--space-4)); inset-inline-end: var(--space-4)`
- Z-index: `var(--z-fab)` = 160
- Context-aware: reads current route and maps to primary create action
- Shows only if user has `create` permission for that route
- Animation: scale-in `transform: scale(0) → scale(1)` on mount
- Icon: `Plus` by default, route-specific icon optionally

| Route | FAB Label | Permission |
|-------|-----------|------------|
| `/sales/orders` | + طلب بيع | `sales.orders.create` |
| `/customers` | + عميل | `customers.create` |
| `/purchases/invoices` | + فاتورة | `procurement.invoices.create` |
| `/inventory/transfers` | + تحويل | `inventory.transfers.create` |
| `/finance/expenses` | + مصروف | `finance.expenses.create` |
| Other routes | hidden | — |
