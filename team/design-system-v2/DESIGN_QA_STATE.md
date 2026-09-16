# Design QA State

## Reviewed baseline

- Review date: `2026-09-17`
- Development branch: `design-system-v2-development`
- Exact Development HEAD inspected before this review/state write: `6421c0396d13e04217defda724e2e925b447d2a9`
- Active slice: `DS2-PROC-002 — Purchase Invoice form decomposition`
- Active implementation PR: `#37 — DS2-PROC-002: establish purchase invoice form V2 shell`
- PR base: `design-system-v2-development`
- PR base SHA: `e4866c9350c507bce260beb07d880fbce55718f3`
- Exact PR HEAD reviewed: `751d54278b120ad560981b9f019ec0a0135b3061`
- Live PR state at disposition: `OPEN / DRAFT / mergeable`
- Changed-file scope at reviewed HEAD: 6 files — Purchase Stepper adapter/test, live Purchase Invoice form, focused page source-contract test, Workstream state, UI Implementation state.
- Current disposition: `AGENT-REVIEW: BLOCKED`
- Blocking severity: `P2 — visual hierarchy / inter-section spacing regression`
- Source evidence: `SOURCE_REVIEW_PASS` withheld.
- Test evidence: `TESTS_AUTHORED_NOT_EXECUTED`.
- Exact-head build/test/lint/runtime/preview evidence: not claimed.

## Independent QA disposition

**BLOCKED on exact HEAD `751d54278b120ad560981b9f019ec0a0135b3061`.**

The previous implementation-completeness blocker is closed. The Director-bounded Purchase Invoice shell is now wired into the live form and remains functionally isolated. Independent review found one new source-level system-fit regression at the migrated basic-information surface: the migration removes the previous external vertical separation and leaves the shared `FormSection` directly adjacent to following content in modes where deliberate spacing is required.

## Source review — PASS except the single spacing blocker

### Shared Stepper / workflow reachability — PASS

`PurchaseInvoiceDraftStepper` remains a thin adapter over shared V2 `Stepper` and projects existing Purchase-owned reachability without moving validation/workflow truth:
- previous steps remain reachable;
- step 0 remains reachable;
- step 1 unlocks only after supplier + warehouse eligibility (`canProceedStep0`);
- step 2 unlocks only after basic eligibility + at least one valid item (`canProceedStep0 && canProceedStep1`);
- review/final step is not newly unlocked by direct navigation;
- shared Stepper is mounted only for `new` and editable draft (`mode === 'draft' && !showReceivePanel`);
- receive/bill/readonly modes do not receive editable wizard UX;
- local mobile `.stepper-label { display: none; }` collision is removed.

Shared Stepper owns `aria-current`, accessible current/completed/future labels, disabled-step semantics, visible focus and mobile wrap behavior.

### Basic-information composition — functional/layout contract PASS, spacing FAIL

The live **بيانات الفاتورة** surface now uses shared `FormSection + FormGrid columns={3}`. The shared CSS contract correctly yields `3 Desktop / 2 Tablet / 1 Mobile`. Supplier and notes remain full-span. Warehouse/date/supplier-reference/landed-cost values, conditional visibility and disabled rules remain unchanged.

However, the wrapper replacement drops the legacy `sCard` external `marginBottom: 16`. Shared `FormSection` delegates to shared `Card`, and the shared Card/FormSection contracts intentionally own no external sibling margin. `PurchaseInvoiceForm` is not wrapped in a parent stack/gap container. Therefore the new basic-information card has no vertical separation from:
- the wizard `FormActions` on editable step 0; and
- the following items card when `showReceivePanel`, `bill`, or `readonly` renders multiple sections simultaneously.

This is a PR-introduced hierarchy/spacing regression across real Purchase Invoice modes, not deferred legacy debt. It violates the North-Star spacing/system-fit requirement and blocks GREEN-DEV until bounded locally.

### Wizard actions — PASS

The editable bottom surface now composes shared `FormActions + Button` while preserving page-owned truth:
- cancel/list navigation callback unchanged;
- previous still decrements the existing step;
- next still calls the same `goNext` validation/toast path;
- final save still calls `handleSaveDraft`;
- save-disabled expression is unchanged;
- touch targets are explicit;
- `ChevronRight` for previous and `ChevronLeft` for next are correct RTL-native cues;
- buttons remain native focusable controls.

### Semantic status — PASS

The local raw-color status badge is removed. The live form now uses shared `StatusBadge` with the same labels and the same semantic vocabulary already integrated on the Purchase list:
- `draft -> neutral / مسودة`
- `received -> info / مستلمة`
- `billed -> warning / معتمدة`
- `paid -> success / مدفوعة`
- `cancelled -> danger / ملغاة`

Status truth/transitions remain page/domain-owned.

### Functional isolation / scope — PASS

The exact six-file diff is UI/Test/Governance-owned only. No DB/migration/RPC/service/query/cache/RBAC/RLS/permission/route/accounting calculation/workflow transition/validation semantic/deployment file is changed. Source-contract checks preserve the material create/update/receive/landed-cost/bill/cancel service calls, permission checks, `ResponsiveModal` and `DocumentActions`.

No unresolved inline PR review thread exists at this disposition.

## Blocking finding — basic FormSection loses required sibling separation

### Location

`src/pages/purchases/PurchaseInvoiceForm.tsx`, the migrated **بيانات الفاتورة** `FormSection` boundary and its adjacency to the following wizard actions / item section.

### Violated gate / principle

- North Star: visual hierarchy, spacing/alignment, deliberate device/state composition and system fit.
- Development gate: source-level fit must not introduce a known visible regression while converging onto shared primitives.

### Minimum required fix

Restore one bounded, token-based logical block separation at the Purchase Invoice composition boundary so the migrated basic-information `FormSection` is separated from its next sibling in both editable step 0 and simultaneous receive/bill/readonly layouts.

Acceptable direction: a narrow Procurement shell class/wrapper using the shared spacing token such as `var(--space-4)` / logical block spacing. Do **not** add a global external margin to shared `FormSection`, and do not change Purchase logic or widen into other sections. Extend the focused source contract so local spacing ownership is explicit and cannot disappear silently.

## Device / state / accessibility judgment

- **Desktop:** 3-column basic-info density is correct and dense item review is preserved; current blocker is missing vertical separation around the migrated card.
- **Tablet:** shared grid correctly caps at 2 columns and Stepper/actions remain deliberate/touch-safe; same spacing boundary applies.
- **Mobile:** one-column basic-info, wrapped shared Stepper and touch-target actions are directionally correct; no page-local label suppression remains. Missing separation between the card and actions on step 0 remains a hierarchy defect.
- **Receive existing draft:** no editable Stepper overlay; workflow truth preserved; migrated basic card can touch the following items card.
- **Bill/read-only:** no editable Stepper; semantic status is correct and domain behavior unchanged; migrated basic card can touch the following items card.
- **Accessibility:** shared Stepper/button semantics, focus and status textual meaning are sound at source level. No new accessibility blocker found in the bounded shell.
- **Dark/semantic color:** shared semantic tokens are used for workflow status; no new page-local status palette introduced.

## Test / execution evidence

Evidence is **`TESTS_AUTHORED_NOT_EXECUTED`**.

Focused artifacts exist for:
- Purchase-owned guarded Stepper reachability and locked review step;
- current/completed/future ARIA semantics + shared Mobile wrap;
- live editable-only Stepper wiring;
- shared 3/2/1 `FormSection + FormGrid` composition and preserved disabled rules;
- shared FormActions with cancel/previous/next/save wiring and RTL cues;
- semantic Purchase status mapping;
- preservation of material service/permission/modal/output boundaries.

No approved environment executed `npm test`, `npm run build` or `npm run lint`; no GitHub Actions/hosted CI or Vercel was used. No executed PASS is claimed. No known real build/type failure is recorded for this exact HEAD. The new spacing blocker should receive focused source-contract coverage as part of the minimum fix.

## Peer-state comparison / contradiction handling

The disposition above was formed from the exact moved PR diff and current shared primitives/product contracts before peer comparison.

- **Product Design Director:** its current state predates the moved complete PR HEAD, but the bounded shell specification is aligned. It explicitly requires deliberate multi-mode composition and gives no rule that external spacing should be lost.
- **UI Production Engineer:** fresh on this moved implementation and declares the shell complete / no implementation blocker. QA agrees the prior completeness blocker is closed but independently finds the newly exposed basic-section spacing regression. This is a material **BLOCKING** contradiction on system-fit completeness until fixed or explicitly bounded.
- **Development Integrator:** state is stale on prior HEAD `1e825c...` and correctly remains `NO_MERGE`; it must not integrate the moved HEAD while the fresh QA blocker is current.
- **Team Memory / Decision Log:** durable functional isolation/shared-system/device rules remain aligned; no durable-rule change is required.

## Remaining WATCH / release boundary

- `InlineCombobox` / product chooser keyboard/accessibility debt remains real but explicitly outside this slice.
- Product item tables/cards, mobile add-item sheet and receive/accounting surfaces remain later bounded concerns.
- Raw Stepper surface chrome can be reassessed in controlled visual/runtime review; it is not the current source-level blocker.
- Runtime/browser/build/test/lint evidence remains unclaimed and belongs to later controlled validation gates.

### Cross-role handoff
- **To:** UI Production Engineer, Development Integrator, Product Design Director
- **What changed:** Design QA reviewed moved PR #37 exact HEAD `751d54278b120ad560981b9f019ec0a0135b3061`. The prior completeness blocker is closed and the bounded live shell is otherwise source-level sound, but the new `FormSection` replacement dropped external sibling spacing and creates a visual hierarchy regression on editable step 0 and simultaneous receive/bill/readonly layouts.
- **Preserve:** exact step reachability/progression, all supplier/warehouse/product identity, pricing/tax/discount/landed-cost/WAC/accounting/payment/workflow/validation/permission/query/service/route truth, status mapping, posted/read-only stability, and the Director-bounded shell-only scope.
- **Need from you:** UI Production Engineer should restore bounded logical `var(--space-4)` separation at the Purchase Invoice composition boundary (not globally on shared FormSection), protect it with focused source coverage, then hand off a new stable exact HEAD. Integrator remains `NO_MERGE`; any moved HEAD requires fresh QA.
- **Blocker level:** `BLOCKING`.
- **Baseline:** Development `6421c0396d13e04217defda724e2e925b447d2a9`; PR #37 reviewed HEAD `751d54278b120ad560981b9f019ec0a0135b3061`.
- **Evidence:** `TESTS_AUTHORED_NOT_EXECUTED`; `SOURCE_REVIEW_PASS` withheld; runtime/release gates remain separate.
