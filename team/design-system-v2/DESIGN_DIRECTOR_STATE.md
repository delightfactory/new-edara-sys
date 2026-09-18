# Product Design Director State

## Reviewed baseline

- Review date: `2026-09-18`.
- Authoritative branch: `design-system-v2-development`.
- Development HEAD at start of this Product Design run: `a364d2a1e0600c2502a8780af4199c6506ff3009`.
- Development HEAD immediately before this owned-state write: `f88e62c41474d699e59677001a72e17c9e01d606` (`31_AGENT_TEAM_WORKSTREAM.md` bounding commit only).
- Latest completed product slice: `DS2-WORK-001 — Create Task form composition foundation`, merged as `57747123643d0dd846cbda3ef340e9463a5f7647`.
- Open implementation PRs targeting Development: none at review time.
- Current single implementation-ready slice: `DS2-WORK-002 — Work Hub view-mode selector convergence`.
- Representative live surface: `/work` / `src/pages/work/WorkHubPage.tsx`.
- Product Design disposition: `READY — BOUNDED PRESENTATION-ONLY SLICE`.

## Independent Product Design judgment

The next safe Work Management step should not be a broad Work Hub/detail/management rewrite. Work Detail and management surfaces are tightly coupled to acknowledgement, assignment, waiting/resume, completion review, approval, triage, attachment and other state-machine behaviors. The smallest useful system-level proof is instead the Work Hub view-mode selector.

`WorkHubPage` currently owns a local `.work-segmented` control for the three presentation modes `actions | work | attention`. That control duplicates the already-established shared `SegmentedControl`, which is explicitly designed for single-choice filter/view-mode selection. The local implementation also uses a 36px minimum button height, while the shared control owns the canonical touch-height token, focus-visible behavior, `aria-pressed` selection semantics and Mobile horizontal containment.

This is therefore a real Design System convergence step rather than page beautification: retire the duplicate local selector and consume the shared V2 pattern while leaving Work filtering/query/workflow truth where it is.

## WORK002 bounded scope

### In scope

- Replace only the Work Hub local `work-segmented` renderer with shared `SegmentedControl`.
- Preserve exactly the existing three values, Arabic labels and order:
  - `actions` — `مطلوب مني الآن`
  - `work` — `كل الأعمال`
  - `attention` — `يحتاج انتباه`
- Preserve default `actions`, current `mode` state ownership and the same `setMode` callback behavior.
- Preserve the surrounding `work-toolbar` and existing search placement/behavior.
- Remove only selector-specific CSS proven dead after migration; no broad `work.css` cleanup.
- Add focused source/component tests for exact option order/labels, current `aria-pressed` state, mode switching and presentation-only ownership.

### Explicit exclusions

- Work Hub summary cards/metrics and their click-to-filter behavior.
- Search input, SearchField or FilterBar convergence.
- Action-inbox cards, `WorkItemCard`, loading skeletons and empty/error/offline state convergence.
- Mobile create action placement.
- Work Detail, Supervisor/Team, management/configuration and Submit Request surfaces.
- Any change to `useMyActionInbox`, `useVisibleWorkItems`, operational flags, `filteredItems`, `filteredActions`, permissions, routing, query/cache/service contracts, ownership/responsibility, validation, workflow or Work state-machine semantics.

If exact behavior cannot be preserved without changing one of those functional contracts, WORK002 becomes `BLOCKED`; scope must not expand to make the migration convenient.

## Device / RTL / accessibility acceptance

- **Mobile (`<=768px`)**: selector options retain the shared 44px touch-height contract; long Arabic labels remain readable; horizontal containment must not create page-level overflow; the mode selector stays subordinate to the page's primary task/create actions.
- **Tablet (`769–1024px`)**: touch-first 44px geometry remains and the three view modes retain clear selected/unselected hierarchy without reverting to compressed desktop-only buttons; the adjacent search composition is preserved.
- **Desktop (`>=1025px`)**: toolbar remains efficient and balanced; shared selector adoption must not change search position, Work Hub hierarchy or the data shown for each mode.
- **RTL**: existing Arabic order and labels are preserved; no LTR-only layout assumption is introduced.
- **Accessibility**: group accessible name remains `نوع العرض`; each option remains a native `button type="button"` with `aria-pressed` derived from `mode`; shared visible focus treatment is preserved; selected state remains visually distinguishable beyond text color through the shared surface/elevation treatment.
- **States**: all three selected modes remain representable; loading/empty/error/permission behavior is explicitly unchanged in this slice.

## System-pattern intent

- Canonical pattern: shared `SegmentedControl` for Work Hub view-mode selection.
- Page/domain ownership: Work mode value, filtering calculations and data/query semantics.
- This proof advances the broader Tabs/SubNav/SegmentedControl adoption cleanup already documented in the shared component-depth roadmap.
- Adjacent Work Hub search, metrics, cards and state surfaces remain explicit later debt rather than being opportunistically folded into WORK002.

## Peer-state synthesis

The independent judgment above was formed from the current Work Hub source and shared pattern contracts before relying on peer conclusions.

- **Development Integrator:** current and aligned. It records WORK001 merged and explicitly hands WORK002 to Product Design for one smallest bounded concern.
- **UI Production Engineer:** lifecycle-stale to the completed PR #44; no contradiction because there is no active implementation PR.
- **Design QA:** lifecycle-stale to the completed PR #44; no contradiction because there is no active review HEAD.
- **Team Memory:** current overall direction is aligned but intentionally broad at WORK002; this run narrows the implementation boundary in the Workstream without changing durable system direction.
- **Decision Log:** no durable rule is changed; no update warranted.

No current cross-role `BLOCKING` contradiction exists.

## Material repository action this run

- Updated `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md` in commit `f88e62c41474d699e59677001a72e17c9e01d606` so WORK002 is a genuinely implementation-ready single concern rather than a broad placeholder.
- No product code, peer specialist state, Team Memory or Decision Log was modified.
- No GitHub Actions, Vercel, preview branch, `main`, merge or deployment action was performed.

### Cross-role handoff
- **To:** UI Production Engineer; Design QA after an exact stable implementation HEAD exists; Development Integrator only after Product Design + QA gates are satisfied.
- **What changed:** `DS2-WORK-002` is now bounded to one dependency-safe presentation concern on `/work`: replace the local Work Hub `work-segmented` mode selector with shared `SegmentedControl`, preserving all mode/filter/query/workflow semantics and excluding the rest of Work Hub/detail/management convergence.
- **Preserve:** exact `actions | work | attention` values, Arabic labels/order/default, `mode` + `setMode` page ownership, search/filter calculations, summary-card behavior, query/service/permission/route/ownership/workflow/state-machine truth, Mobile-primary / Tablet-touch / Desktop-density contracts, and the one-active-slice rule.
- **Need from you:** UI Production Engineer should open exactly one Development-targeted WORK002 PR from the latest Development HEAD and implement only this selector convergence with focused tests. QA and Product Design should independently review the exact stable PR HEAD afterward.
- **Blocker level:** `NONE`.
- **Baseline:** initial Development `a364d2a1e0600c2502a8780af4199c6506ff3009`; WORK002 boundary commit `f88e62c41474d699e59677001a72e17c9e01d606`.
- **Evidence:** `SOURCE_REVIEW_ONLY`; no implementation/test/build/lint/runtime/preview evidence exists yet for WORK002.
