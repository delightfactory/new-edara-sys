# EDARA Engineering Review Report

Date: 2026-04-03

Scope: current uncommitted changes plus surrounding implementation paths reviewed during security, correctness, scalability, performance, and UX analysis.

Audience: engineering leads, reviewers, maintainers, and implementation owners.

## 1. Executive Summary

This review found critical issues in three areas:

- Security and authorization: there are direct privilege-boundary failures in the notification dispatch flow.
- Data correctness and scale readiness: several list flows apply filtering after pagination or keep stale data too long, which will break behavior under large datasets.
- Mobile UX and operational flow safety: a few recently changed screens now hide important actions or make touch interaction error-prone.

The highest-risk issue is the `dispatch-notification` edge function, which currently allows a forged JWT-shaped token to enter the internal privileged path. That is a release-blocking security defect.

The most important scalability pattern found is repeated client-side filtering after paginating unfiltered rows. With tens of thousands of customers and hundreds of thousands of transactional rows, that pattern causes empty pages, misleading counters, and unnecessary network/CPU waste.

The most important UX issue in the current UI changes is that key actions on `VisitPlanDetail` are no longer reachable on mobile because they are hidden with a global `.desktop-only-btn` rule and no replacement interaction exists.

## 2. Review Method

This report was derived from:

- Review of uncommitted UI changes.
- Review of affected service-layer and edge-function code.
- Review of query hooks, realtime invalidation, and notification state flows.
- Build verification.
- Architecture review focused on authorization, pagination correctness, and mobile task completion paths.

The goal was not stylistic feedback. The findings below focus on concrete defects, scalability risks, and operationally significant UX failures.

## 3. Severity Model

- `P0`: release-blocking or major security boundary failure.
- `P1`: urgent defect affecting correctness, authorization, or scale-sensitive behavior.
- `P2`: important but non-blocking defect with meaningful operational impact.

## 4. Findings and Engineering Guidance

### 4.1 Security and Authorization

#### F-SEC-01

Severity: `P0`

Location: `supabase/functions/dispatch-notification/index.ts`

Title: forged `service_role` tokens are accepted as internal privileged calls.

Problem:

The function decodes the JWT payload and trusts `role === "service_role"` without validating the token signature. That means a caller can forge a JWT-shaped string and enter the internal path that uses the admin Supabase client.

Risk:

- Unauthorized creation of notifications.
- Unauthorized push delivery to arbitrary users.
- Full break of the trust boundary between browser-originated calls and internal/server-originated calls.

Professional technical solution:

- Remove all role inference based on an unverified JWT payload.
- Split the function into two explicit trust paths:
  - External path: browser/user session path, always validated with `auth.getUser()` and explicit permission checks.
  - Internal path: server-to-server path authenticated with a dedicated shared secret or an internal-only signed request header.
- If JWT-based internal auth is kept, validate the token signature and issuer/audience server-side before trusting claims.

No-break implementation strategy:

- Keep the current request/response schema unchanged.
- Introduce a new helper such as `assertInternalRequest(req)` and switch only the internal authorization logic first.
- Add integration tests covering:
  - valid internal call
  - forged token
  - valid user token
  - missing token
- Deploy behind logging first for rejected internal calls if there are unknown callers.

Best-practice target:

- Never infer privileged trust from decoded but unverified claims.
- Separate internal system actions from public edge routes when possible.

#### F-SEC-02

Severity: `P1`

Location: `supabase/functions/dispatch-notification/index.ts`

Title: authenticated browser users can dispatch notifications to arbitrary recipients.

Problem:

The external path verifies that the caller is signed in, but does not verify whether that caller is allowed to trigger the requested event or target the provided `user_ids`.

Risk:

- Cross-user spam or abuse.
- False operational notifications.
- Escalation from normal user to workflow manipulation actor.

Professional technical solution:

- Introduce event-level authorization, for example:
  - `event_key` allowlist per role/permission.
  - recipient scoping rules derived on the server.
- Stop accepting arbitrary recipient lists from browser callers unless the caller holds an explicit permission such as `notifications.dispatch`.
- Prefer a server-side RPC or policy-controlled mapping from domain event to recipients.

No-break implementation strategy:

- Keep the same endpoint contract temporarily.
- Add server-side validation that rejects disallowed combinations with structured error messages.
- Migrate client callers incrementally to domain-specific trigger functions if needed.

Best-practice target:

- Browser clients should request business actions, not direct recipient routing.

#### F-SEC-03

Severity: `P1`

Location: `src/sw.ts`

Title: authenticated Supabase traffic is cached in a shared service-worker cache.

Problem:

All `*.supabase.co` traffic is routed through one `NetworkFirst` cache. Cache matching does not vary by session identity, so protected responses can be replayed across users on the same device when offline or during fallback.

Risk:

- Cross-session data exposure.
- Stale auth/session state replay.
- Hard-to-debug support incidents where data shown does not belong to the active user.

Professional technical solution:

- Do not cache authenticated API/auth responses in the service worker.
- Restrict caching to static assets and truly public resources.
- If specific GET endpoints must be cached, isolate them by route and cache only explicitly public data.

No-break implementation strategy:

- Remove only the Supabase route from Workbox caching first.
- Keep all static asset caching intact.
- Validate offline behavior on key screens afterward and add targeted skeleton/empty offline states where needed.

Best-practice target:

- Treat authenticated API responses as non-cacheable unless cache partitioning is explicit and proven safe.

#### F-SEC-04

Severity: `P1`

Location: `src/lib/services/auth.ts`

Title: transient profile-loading failures force valid users to sign out.

Problem:

`loadSession()` signs the user out when `get_my_profile()` returns any error, not only when the account is actually inactive.

Risk:

- Users lose sessions during transient backend/network issues.
- Login appears unstable under infrastructure hiccups.
- Temporary backend degradation becomes a user-facing auth outage.

Professional technical solution:

- Split error handling into:
  - authenticated + inactive account
  - authenticated + profile lookup failed
- Sign out only for explicit inactive/suspended decisions.
- For transport/RPC failure, keep the session and surface a retryable degraded state.

No-break implementation strategy:

- Preserve the current store API.
- Add an `auth_bootstrap_error` state or equivalent UI fallback instead of `reset()`.
- Keep `reset()` only for missing user or explicit account-state rejection.

Best-practice target:

- Authentication state and profile-loading state must be modeled separately.

### 4.2 Data Correctness, Scalability, and Performance

#### F-SCALE-01

Severity: `P1`

Location: `src/lib/services/activities.ts`

Title: `typeCategory` is filtered after paginating activities.

Problem:

The query paginates first, then removes rows client-side by category.

Risk:

- Sparse or empty pages even when matching rows exist.
- Wrong `count` and `totalPages`.
- Unnecessary network transfer and client work.

Professional technical solution:

- Move filtering into SQL before pagination.
- Recommended implementation options:
  - database view joining `activities` to `activity_types`
  - RPC function returning paginated rows plus accurate count
  - query rewrite using a filterable relation if supported safely

No-break implementation strategy:

- Keep the same return shape: `{ data, count, page, pageSize, totalPages }`.
- Swap only the underlying query implementation.
- Add regression tests for:
  - category-only pages
  - count correctness
  - empty vs non-empty page transitions

Best-practice target:

- All user-visible filters affecting page membership must execute before pagination.

#### F-SCALE-02

Severity: `P1`

Location: `src/lib/services/activities.ts`

Title: `branchId` is filtered after paginating visit plans.

Problem:

The service fetches a page of `visit_plans`, then filters by `employee.branch_id` in memory.

Risk:

- Incorrect pages for supervisors browsing branch plans.
- Overstated totals.
- More round trips and repeated retries by users.

Professional technical solution:

- Push branch filtering into the DB layer through a view or RPC that joins employee records and paginates only matching rows.

No-break implementation strategy:

- Keep hook and UI contracts unchanged.
- Replace only service internals.
- Validate sorting parity with the old implementation.

Best-practice target:

- Joined attributes used as filters should be queryable at the database layer, not post-processed in the client.

#### F-SCALE-03

Severity: `P1`

Location: `src/lib/services/activities.ts`

Title: `branchId` is filtered after paginating call plans.

Problem:

The same issue exists for `getCallPlans()`.

Risk:

- Branch-specific call-plan pages become unreliable under scale.
- Performance cost rises with data growth.

Professional technical solution:

- Same remediation pattern as visit plans: DB-side filtering before pagination.

No-break implementation strategy:

- Reuse the same response contract and tests across both services.

Best-practice target:

- Avoid duplicated client-side filtering patterns in list services.

#### F-SCALE-04

Severity: `P2`

Location: `src/lib/services/users.ts`

Title: role filtering is applied after paginating profiles.

Problem:

The service loads a page of profiles, enriches them with roles, then filters by role in memory.

Risk:

- Admins cannot reliably page through users by role.
- Counts and totals do not reflect the active filter.
- Work increases with user growth.

Professional technical solution:

- Move role filtering into a DB query or RPC that joins `profiles`, `user_roles`, and `roles` before pagination.

No-break implementation strategy:

- Preserve current DTO shape for `UserWithRoles`.
- Add a role-filtered query path internally and leave the hook interface unchanged.

Best-practice target:

- Filtered administrative indexes must return count metadata from the same filtered source.

#### F-DATA-01

Severity: `P2`

Location: `supabase/functions/create-user/index.ts`

Title: user creation succeeds even when role assignment fails.

Problem:

The function logs `rolesErr` and still returns success.

Risk:

- Partially provisioned users.
- Misleading admin feedback.
- Support burden from “user exists but cannot access anything”.

Professional technical solution:

- Make user creation atomic.
- Recommended options:
  - move the full flow into a transactional server-side function
  - explicitly compensate by deleting the created user/profile if role insert fails

No-break implementation strategy:

- Keep the same success payload on the happy path.
- On failure, return a structured error code such as `ROLE_ASSIGNMENT_FAILED`.
- Add monitoring for partial-provision events during rollout.

Best-practice target:

- Provisioning flows must be transactional or compensating, never partially successful.

#### F-DATA-02

Severity: `P2`

Location: `src/hooks/useNotificationQueries.ts`

Title: archiving one unread notification can decrement the badge more than once.

Problem:

The unread count mutation happens inside a cache update callback that runs per matching list cache.

Risk:

- Badge count drifts temporarily below the true value.
- User trust in notification state decreases.

Professional technical solution:

- Compute whether a decrement is needed once per mutation, outside per-cache callbacks.
- Alternatively deduplicate by notification id before mutating unread state.

No-break implementation strategy:

- Keep optimistic list removal.
- Change only the unread-store mutation location.
- Add tests covering multiple cached pages/filters containing the same notification.

Best-practice target:

- Shared state side effects should run once per domain action, not once per cache entry.

#### F-DATA-03

Severity: `P2`

Location: `src/components/shared/GlobalRealtimeManager.tsx`

Title: sales query invalidation is incomplete.

Problem:

Realtime invalidation does not cover `sales_orders`, `sales_returns`, and related cache keys such as `sales-stats`.

Risk:

- Users see stale order lists or counters after remote updates.
- Cross-tab/cross-user coordination degrades.

Professional technical solution:

- Expand `TABLE_QUERY_MAP` to cover all domain tables with active query consumers.
- Review all query keys systematically, not ad hoc.

No-break implementation strategy:

- Add missing mappings without changing existing query keys.
- Verify with a small invalidation matrix:
  - table
  - expected keys
  - affected screens

Best-practice target:

- Realtime invalidation should be maintained as a domain map, not a partial convenience list.

#### F-PERF-01

Severity: `P2`

Location: `src/hooks/useQueryHooks.ts`

Title: payroll calculation is orchestrated one employee at a time from the browser.

Problem:

The browser loops over all active employees and calls payroll RPCs sequentially.

Risk:

- Very long processing time as headcount grows.
- Job failure if the tab closes or connectivity blips.
- Poor operator experience during payroll runs.

Professional technical solution:

- Move payroll orchestration to the server:
  - one batch RPC that calculates all employees
  - or background job table plus worker/cron processor
- Expose progress through polling or realtime updates.

No-break implementation strategy:

- Keep the current button and UI contract.
- Replace `useCalculatePayrollRun()` internals to trigger a batch job and poll status.
- Preserve progress UI by reading from server-side job state rather than local loop counters.

Best-practice target:

- Long-running, business-critical batch work must not depend on a live browser loop.

#### F-DOMAIN-01

Severity: `P2`

Location: `src/pages/sales/SalesOrderDetail.tsx`

Title: edit action is gated by a permission identifier that is not actually available.

Problem:

The detail page checks `sales.orders.update`, but that permission does not appear to be defined consistently in the frontend permission model.

Risk:

- Legitimate users cannot access expected editing flows.
- UI behavior diverges from backend/domain intent.

Professional technical solution:

- Normalize permission identifiers across:
  - constants
  - role grants
  - UI checks
  - backend permission checks

No-break implementation strategy:

- Introduce a permission audit list and reconcile existing aliases first.
- Add a small permission contract test if the project supports it.

Best-practice target:

- Permission names must be centrally defined and consumed, never handwritten in isolated screens.

### 4.3 UX, Mobile Flow, and Dead-End Journeys

#### F-UX-01

Severity: `P1`

Location: `src/styles/components.css`, `src/pages/activities/VisitPlanDetail.tsx`

Title: key visit-plan actions are unreachable on mobile.

Problem:

The global mobile rule hides `.desktop-only-btn`, and `VisitPlanDetail` uses that class for:

- bulk close remaining day items
- clone plan
- save as template

No mobile replacement exists.

Risk:

- Supervisors hit a dead end on phone/tablet.
- Operational end-of-day flows cannot be completed in the field.
- Users may assume the feature does not exist or that permissions are broken.

Professional technical solution:

- Do not hide operationally important actions without a replacement.
- Recommended mobile replacement patterns:
  - “More actions” bottom sheet
  - overflow menu
  - sticky segmented action bar for the current plan state

No-break implementation strategy:

- Keep the desktop buttons.
- On mobile, move the same action handlers into a compact action sheet.
- Reuse existing modal handlers and mutation flows so only the trigger surface changes.

Best-practice target:

- Mobile may compress actions, but must not silently remove business-critical flows.

#### F-UX-02

Severity: `P2`

Location: `src/pages/notifications/NotificationsPage.tsx`

Title: notification tabs can become unreachable on narrow mobile layouts.

Problem:

Mobile styling removes horizontal scrolling, but the tabs still use icon + label + no wrapping.

Risk:

- Last tab becomes partially or fully clipped.
- Accessibility worsens with larger text sizes.

Professional technical solution:

- Keep a mobile fallback:
  - allow horizontal scroll, or
  - collapse labels/icons more aggressively, or
  - switch to a stacked segmented control with shorter labels

No-break implementation strategy:

- Restore `overflow-x: auto` first as the safest fix.
- If a richer redesign is desired, do it afterward with responsive QA.

Best-practice target:

- If content may overflow on mobile, keep a reachable fallback instead of relying on ideal-width assumptions.

#### F-UX-03

Severity: `P2`

Location: `src/components/notifications/NotificationItem.tsx`

Title: mobile notification actions are too small and compete with row click behavior.

Problem:

Archive/delete buttons were reduced to `26x26`, while the row remains clickable for read/navigate.

Risk:

- Tap misses trigger the row action.
- Users unintentionally navigate instead of archiving/deleting.
- Destructive and navigational affordances become easy to confuse.

Professional technical solution:

- Increase touch target size to a safer mobile minimum.
- Add stronger separation between row-click and action-click zones.
- Consider using swipe actions or a dedicated overflow action button on mobile.

No-break implementation strategy:

- Keep current component API.
- Change only mobile CSS first.
- Add manual QA for:
  - archive
  - delete
  - open notification
  - mark as read

Best-practice target:

- Touch targets for primary or destructive mobile actions should not drop below practical accessibility thresholds.

## 5. Cross-Cutting Engineering Themes

### Theme A: Move filter logic to the database layer

Affected areas:

- activities
- visit plans
- call plans
- users by role

Why this matters:

- prevents incorrect pagination
- improves count accuracy
- reduces payload size
- scales with data growth

Recommended standard:

- For any paginated list with relational filters, use a DB view or RPC returning:
  - filtered rows
  - total count
  - stable sort order

### Theme B: Keep trust boundaries explicit

Affected areas:

- edge functions
- service worker
- auth bootstrap

Why this matters:

- prevents accidental privilege escalation
- prevents cross-session leakage
- preserves user trust during transient failures

Recommended standard:

- Verify privileged claims cryptographically.
- Do not cache authenticated API responses by default.
- Separate account-state enforcement from network failure handling.

### Theme C: Do not remove mobile capability when optimizing layout

Affected areas:

- visit plan detail
- notifications page
- notification items

Why this matters:

- mobile users still need full operational completion paths
- layout fixes must not create dead ends

Recommended standard:

- every hidden desktop action must have a mobile replacement
- every compressed touch action must pass a practical tap-target review

## 6. Recommended Delivery Plan

### Phase 1: Immediate Security Remediation

Target:

- `dispatch-notification` internal auth
- browser authorization on notification dispatch
- service worker authenticated caching

Goal:

- close release-blocking trust issues first

### Phase 2: Correctness and State Integrity

Target:

- `create-user`
- `loadSession`
- unread badge optimistic updates
- sales permission mismatch
- realtime invalidation coverage

Goal:

- stop misleading UI states and partial writes

### Phase 3: Scale Readiness

Target:

- server-side filtered pagination for activities/plans/users
- payroll batch execution

Goal:

- make high-volume operational screens behave correctly under load

### Phase 4: Mobile UX Hardening

Target:

- restore visit-plan action reachability
- notification tabs fallback
- larger mobile action targets

Goal:

- remove dead-end journeys and reduce operator friction

## 7. Verification Checklist

Before considering the remediation complete, verify:

- forged JWT payloads are rejected
- only authorized actors can trigger notification events
- offline mode does not replay protected Supabase responses between sessions
- temporary profile RPC failure does not sign users out
- filtered paginated lists return correct counts and stable pages
- user creation fails atomically if roles fail
- sales dashboards update after realtime changes from another session
- payroll run works without depending on a live browser loop
- all visit-plan actions remain reachable on mobile
- notification tabs remain reachable on narrow devices and large-text settings
- notification action buttons are easy to tap without accidental navigation

## 8. Final Recommendation

The current state should not be treated as production-ready until the Phase 1 items are resolved. After that, the project should prioritize the pagination/filtering corrections and payroll batching work, because those are the areas most likely to fail under the scale profile expected for this application.

The safest implementation strategy is to keep external interfaces stable while replacing unsafe or non-scalable internals behind the same hooks, services, and response contracts. That approach minimizes regression risk while aligning the system with professional engineering practices.
