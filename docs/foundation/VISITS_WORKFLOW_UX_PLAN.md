# Visits Workflow — UX Slice Plan

Scope: one bounded UX pass over the rep-facing visit-plan workflow. No business logic,
RPC, DB, RLS, permission, or feature-flag changes — labels, layout, and contextual
guidance only, reusing existing design tokens and shared components.

## Workflow steps (actor vs admin)

| Step | Screen | Rep (own plan) | Admin / Manager |
|---|---|---|---|
| 1. Build | `VisitPlanForm.tsx` (wizard) | Creates own draft plan: settings → customers → order/details → review | Can assign plan to a team member if `VISIT_PLANS_READ_TEAM/ALL` |
| 2. Review list | `VisitPlansPage.tsx` | Sees own plans, filters by status/date | Sees team plans, filters by employee too |
| 3. Approve | `VisitPlanDetail.tsx` | Confirms/cancels own draft if permitted | Confirms/cancels, closes remaining pending items administratively |
| 4. Execute | `VisitExecutionMode.tsx` | Only the assigned rep executes, strictly in plan sequence | Admin cannot execute; can only view/administratively close |
| 5. Follow up | `VisitPlanDetail.tsx` | Sees own progress, skip/reschedule reasons | Sees team completion %, clones/saves templates |

Execution always targets the plan's **current pending/in-progress item in sequence**,
never a specific row — this existing behavior is preserved and now called out
explicitly in the UI instead of being implicit.

## Acceptance list (finite)

1. `VisitPlanDetail.tsx` row-level start action keeps its existing handler, permission
   gates, and route (`/execute`); label may read **"فتح تنفيذ الخطة"** via a new
   optional `startLabel` prop on `PlanItemCard`, with a visible note that execution
   follows the ordered current/next item — no new ability to start out of order.
2. `VisitPlanDetail.tsx` primary header CTA reads **"متابعة التنفيذ"** when
   `plan.status === 'in_progress'` and **"بدء التنفيذ"** otherwise, using the existing
   `canExecute` gate with no guard changes.
3. `VisitExecutionMode.tsx` shows the current customer's identity (name/code/phone)
   regardless of which tab (`checklists`/`customer`) is active — previously only
   visible on the `customer` tab.
4. `VisitExecutionMode.tsx` shows one concise contextual instruction line that differs
   pre-start vs. active-visit, computed from existing state only (no new conditions).
5. The "إنهاء الزيارة" disabled state is paired with a one-line reason derived strictly
   from the existing `isCompleteDisabled` gating inputs (loading/error/mandatory
   checklist/pending photos) — no new disablement logic.
6. The GPS-exception block moves out of the tab-hidden `#vem-tab-checklists` panel so
   it renders once and is visible on both tabs during an active visit — no change to
   when it appears (`isGpsInvalid`) or to `saveGpsExceptionReason`.
7. `ChecklistForm` instances stay mounted via the `hidden` attribute (not conditional
   unmount) so in-progress draft answers are never lost when switching tabs.
8. Calls, maps, skip, reschedule, and admin bulk-close actions remain fully usable and
   unchanged in behavior.
9. Responsive targets: 44px minimum touch targets on interactive row controls, full
   width primary controls on phone, deliberate grid on tablet, denser desktop layout,
   `min-width: 0` + wrapping-safe containers for long Arabic customer names, no
   safe-area overlap on sticky bars.
10. No changes to hooks, services, RPC payloads, caches, queues, photo sync, feature
    flags, or permissions. No production data read or mutated by this change.

## Out of scope

`VisitReportsPage*` (active PR #104), DB/RLS/RPC, branch merges, deploys, CI.

## Delivered extension

The bounded UX acceptance items above are implemented. Codex added scoped responsive
composition, destination-plan toast navigation with regression coverage, and suppression
of a misleading daily-conflict warning before employee selection. Functional consent and
generated-column guard repairs are separate from this design-only plan. See
[qualification and evidence](VISITS_WORKFLOW_QUALIFICATION.md) for exact verified scope
and the remaining real-device UAT boundary.
