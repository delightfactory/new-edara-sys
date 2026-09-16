# Design Director State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD independently inspected: `7f1afec73b6b2102c5fd0cc977ac1b56a9fc8d51`
- Latest integrated product slice: `DS2-PROC-001 — Purchase list surfaces` via PR `#36`.
- Open implementation PRs targeting Development: `NONE`.
- Current single READY slice: `DS2-PROC-002 — Purchase Invoice form decomposition`.
- Product Design disposition: `READY — BOUNDED TO PURCHASE INVOICE FORM SHELL FOUNDATION`.

## Independent professional judgment

**DS2-PROC-002 is dependency-safe now, but it must stay substantially narrower than a whole Purchase Invoice rewrite.** The live `PurchaseInvoiceForm.tsx` is a large multi-mode transactional surface containing supplier/product lookup, inventory receiving, landed-cost calculations, WAC-sensitive data, billing/payment/accounting transitions, permissions, mobile item entry and document output. Pulling those concerns into one Design-System migration would create unacceptable functional risk.

The smallest high-value system slice is therefore the **form shell foundation only**: converge the page on already-proven shared V2 navigation/section/action/status grammar while leaving all purchase-domain internals and callbacks in place.

The current source proves four presentation gaps that are safe to correct together because they describe one outer-shell concern:

1. **Local stepper duplicates the shared system.**
   - The new/draft flow renders a page-local step bar with inline colors/connectors/buttons.
   - Shared `Stepper` already supports page-owned reachability, active/current semantics, accessible labels, Arabic wrapping and the mobile wrap treatment proven by Sales.
   - Purchase reachability remains page-owned and must be projected exactly. In particular, preserve the current click rule rather than "improving" workflow behavior: a step is clickable only when the existing predicate allows it (`i < step`, step 0, step 1 after supplier+warehouse, step 2 after supplier+warehouse+valid item). Step 3 remains reached through `goNext` and backward navigation unless the existing page logic already makes it reachable. Do not invent direct-forward navigation.

2. **Basic invoice section uses a local card/grid shell.**
   - `sCard`, `grid2` and `SectionHead` recreate shared section/layout grammar with inline styling.
   - Migrate only the always-used **بيانات الفاتورة** section to shared `FormSection + FormGrid` as the representative Procurement form section.
   - Target density: `3 Desktop / 2 Tablet / 1 Mobile`; supplier and notes remain full-span; all conditional landed-cost/read-only/receive-mode rendering remains exactly as today.
   - Do not migrate the products table/cards, financial preview, review summary, receive panel or mobile add-item sheet in this slice.

3. **Bottom step actions use a page-local action row and physical LTR glyphs.**
   - Replace only the new/draft step-navigation surface with shared `FormActions + Button`.
   - Preserve exact cancel/back/next/save callbacks and save-disable truth.
   - Use RTL-native logical cues (`ChevronRight` for previous, `ChevronLeft` for next) rather than literal `‹ / ›` glyphs; touch targets must remain practical on Mobile and Arabic labels must not clip.

4. **Header workflow status uses a local raw-color badge.**
   - Remove the local raw-hex status treatment from the form shell and use shared semantic `StatusBadge`.
   - Keep status truth page-owned and match the already-integrated Purchase list vocabulary exactly: `draft -> neutral`, `received -> info`, `billed -> warning`, `paid -> success`, `cancelled -> danger`, with the existing Arabic labels.
   - This is presentation convergence only; no workflow/status transition may move into the badge layer.

## Explicit implementation boundary

### In scope

- shared `Stepper` for the existing new/draft wizard shell;
- shared `FormSection + FormGrid` for **بيانات الفاتورة** only;
- shared `FormActions + Button` for the existing step navigation/save surface;
- shared semantic `StatusBadge` in the PageHeader for an existing invoice;
- the minimum Procurement-specific presentation adapter/CSS needed to compose those shared primitives without domain ownership;
- focused source/component/page tests that protect shared primitive usage, exact reachability projection, `3/2/1` responsive density, RTL action direction, save/cancel callback wiring, and semantic status mapping.

### Explicitly out of scope

- supplier lookup / `InlineCombobox` redesign or global Combobox work;
- `PurchaseProductComboCell`, product search, product selection, units or mobile add-item sheet redesign;
- products table/card composition, receive-mode table, quantities or receive validation;
- calculations: unit price, discount, tax, line totals, landed-cost math, WAC/cost behavior or financial summaries;
- receive / bill / pay / cancel transitions and their predicates;
- supplier/warehouse identity, permissions, query/cache/service/RPC/database/RLS/RBAC behavior;
- `DocumentActions` behavior;
- field-control semantic overhaul or broad `Field` migration in this slice; existing controls/values/errors remain authoritative;
- later financial/review sections, generic upload/camera/offline work, global Pagination or broad Procurement rewrite;
- `main`, Vercel preview, hosted CI or deployment activity.

## Device / state / accessibility acceptance

- **Desktop:** predictable 3-column basic-information density where fields permit it; no loss of existing dense transactional review elsewhere.
- **Tablet:** shared form grid caps at 2 columns; step labels remain readable; actions remain deliberate and touch-safe.
- **Mobile:** basic-info fields become one column; shared Stepper uses a non-clipping Arabic-friendly mobile composition; action controls expose practical touch targets and do not rely on physical-direction glyphs.
- **Modes:** `new`, `draft`, draft receive-panel, `bill` and `readonly` visibility/disabled behavior stays exactly page-owned. This slice changes shell presentation, not mode semantics.
- **Accessibility:** shared Stepper owns current-step and disabled-step semantics; buttons remain native controls with visible focus; status meaning is textual + semantic tone, never color-only; action labels remain explicit Arabic text.
- **Dark mode / semantic color:** no new raw status colors or page-local semantic palette; use shared tokens/primitives.

## System-pattern intent

PROC002 is not "beautify the purchase form." It establishes Procurement on the same shared form grammar already proven in Sales: shared step navigation, shared section/grid hierarchy, shared action surface and shared semantic status language while the page retains every business rule. The later item-entry/Combobox/receive/accounting surfaces should be migrated only after this shell foundation is integrated and their recurring pattern gaps are separately bounded.

## Peer-state comparison / freshness

After forming the judgment above, peer memory was compared:

- **Integration State / Team Memory:** fresh enough to establish that PROC001 is integrated and PROC002 is the single queued READY item.
- **Design QA:** latest state is approval evidence for completed PROC001, not approval for PROC002; no contradiction.
- **UI Production Engineer:** no active PROC002 PR exists yet; any prior implementation state is informational/stale for the new slice.
- **Open PR scan:** no implementation PR currently targets `design-system-v2-development`, so creating one bounded PROC002 implementation does not compete with active work.
- **Material disagreement:** none. No backend/business decision is required for this shell-only slice.

## Preserve

- exactly one implementation slice/PR at a time;
- all current Purchase Invoice modes, state transitions, permissions and service calls;
- exact supplier/warehouse/product selection truth;
- exact line-item, tax, discount, landed-cost, receive and accounting calculations;
- current `goNext`, cancel/back and save callbacks, including all existing validation/toast behavior;
- current step reachability semantics, including no newly invented direct-forward access to review;
- existing mobile item-add behavior and products Desktop/Mobile rendering;
- `DocumentActions` and routes;
- page/domain ownership of all business truth;
- no GitHub Actions, hosted CI, Vercel preview, backend/business or `main` activity.

## Remaining non-blocking WATCH

- `InlineCombobox` and the portal product chooser are still local/mouse-heavy interaction debt and are strong candidates for a later separately bounded Combobox/accessibility slice; do not pull them into PROC002 shell work.
- The products entry table/mobile cards and receive panel remain a separate dense operational composition problem.
- Generic `Field` adoption should follow only when control IDs/help/error wiring can be preserved without broad control redesign.
- Runtime/browser/build/test/lint evidence remains governed by the shared validation policy; no such PASS is claimed by this Director review.

## What changed since previous state

PROC001 has been integrated and there is no active implementation PR. I independently inspected the live Purchase Invoice form against the current shared Stepper/FormSection/FormGrid/FormActions/StatusBadge grammar and converted the broad PROC002 placeholder into one implementation-safe shell foundation. No Team Memory or Decision Log change is needed because the overall system direction and durable rules are unchanged.

### Cross-role handoff
- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** `DS2-PROC-002` is now bounded as the single READY Purchase Invoice **form shell foundation**: shared Stepper + only the basic invoice FormSection/FormGrid + shared FormActions + shared semantic header StatusBadge, with no purchase-domain logic migration.
- **Preserve:** exact step reachability and `goNext` behavior; all create/draft/receive/bill/readonly semantics; all supplier/product/warehouse, calculations, accounting, permissions, services, routes, mobile item-entry and DocumentActions truth; one active PR only.
- **Need from you:** UI Production Engineer should open/work exactly one PROC002 PR against current Development and implement only this boundary with focused tests. QA/Integrator should no-op until a stable PR HEAD exists, then review that exact HEAD under the normal gates.
- **Blocker level:** `NONE`.
- **Baseline:** Development `7f1afec73b6b2102c5fd0cc977ac1b56a9fc8d51`; no active PR HEAD.
