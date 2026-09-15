# 12 — Component Decision Matrix

This matrix decides whether current UI assets should be retained, evolved, decomposed or replaced. The default bias is preservation where the contract is sound.

| Current asset | Decision | V2 direction |
|---|---|---|
| `tokens.css` | Evolve | Preserve compatibility, add semantic aliases and explicit device/density roles. |
| `Button` | Evolve | Keep API shape; enforce action hierarchy, 44px operational mobile hit area, focus/loading/icon rules. |
| `Input` / `Select` | Evolve into Field system | Retain native controls where appropriate; standardize label/help/error/read-only/prefix/suffix and numeric/money/date variants. |
| `Badge` | Evolve | Keep generic Badge; add domain-facing `StatusBadge` mapping business statuses to semantic visual states. |
| `AsyncCombobox` | Audit/Evolve | Become the approved autocomplete base; retire page-local comboboxes after compatibility proof. |
| `ResponsiveModal` | Evolve | Keep desktop modal/mobile sheet adaptation; add focus trap, trigger-focus restoration, unique ids, action/footer standards. |
| `DataCard` | Evolve | Preserve mobile-card idea; fix nested interactive semantics, keyboard activation and standardized metadata/action slots. |
| `DataTable` | Evolve | Keep desktop table/pagination role; move device orchestration into `ResponsiveCollection`. |
| `FilterBar` | Decompose internally | Preserve compound public behavior initially; split Search/Select/DateRange/Stats/Panel primitives and mobile filter-sheet composition. |
| `PageHeader` | Evolve | Add responsive title wrapping/truncation policy, breadcrumbs/context, action-registry integration and device-aware layout. |
| `EmptyState` / loading skeletons | Consolidate | One system state family used by table/card/form/queue patterns. |
| `Sidebar` | Redesign implementation | Extract navigation model/permission resolution from renderer; consume semantic tokens; add tablet renderer/compact mode. |
| `BottomNav` | Evolve | Make shortcut set role/task configurable, not a permanently hard-coded list; keep full menu access. |
| Global `FAB` | Replace with action orchestration | Keep route-aware intent but move to an Action Registry/Slot model shared with page header/sticky/overflow actions. |
| Page-local FABs | Retire | Express as primary/secondary page actions through the central action system. |
| Dashboard local `KpiCard` | Retire into shared pattern | Use `StatCard`/Metric variants with semantic emphasis. |
| Local `SectionHead` variants | Consolidate | Use shared `SectionHeader`. |
| Sales local Combobox | Retire after parity | Move onto approved Combobox/AsyncCombobox without altering customer/pricing logic. |
| Sales Stepper | Extract/Evolve | Create accessible responsive `Stepper`; preserve current four-step business workflow. |
| Customer/Sales mobile list wrappers | Consolidate | Use `ResponsiveCollection` and shared infinite/loading/end-state patterns. |
| `components.css` broad responsive selectors | Refactor | Replace semantic-by-guessing selectors with named component rules; remove only after consumer coverage is proven. |

## New V2 patterns required

### `ResponsiveCollection`
Owns presentation only:
- desktop table slot
- tablet mode slot
- mobile card slot
- loading/empty/error/end states
- pagination/infinite UI contract

It must not silently change query semantics in the initial visual migration.

### `ActionRegistry` / `ActionSlot`
A page declares actions with:
- id
- label/icon
- semantic priority: primary / secondary / destructive
- permission already resolved by existing permission layer
- optional device preference

Renderers choose:
- desktop PageHeader/toolbar
- tablet toolbar/overflow
- mobile FAB/sticky button/overflow

### `Field`
A consistent wrapper for:
- label
- required/read-only/disabled
- help text
- validation message
- prefix/suffix/unit
- mobile input hints
- accessible description ids

Specialized variants compose Field instead of duplicating it: MoneyField, QuantityField, PercentageField, DateField, PhoneField, SearchField.

### `FormSection`
Standard section title, optional description, spacing and responsive field grid. Avoid every page building its own card/title/gap system.

### `StatusBadge`
Domain status remains domain-owned; visual meaning maps to neutral/info/success/warning/danger with text/icon support.

### `StatCard`
Consistent KPI label/value/context/trend/action. Emphasis variants are semantic, not arbitrary colors passed from pages.

### `SectionHeader`
Shared heading/icon/action grammar for card/page sections.

### `AlertPanel`
Info/warning/danger/success operational messages with optional next action and accessible icon/text semantics.

### `Stepper`
Responsive, keyboard-visible, current/completed/upcoming state, compact-label behavior on mobile, and no business transition logic inside the visual primitive.

## Adoption rule
A page migration is incomplete if it looks new but still recreates system primitives locally. The goal is fewer independent visual implementations after each wave, not merely updated colors.
