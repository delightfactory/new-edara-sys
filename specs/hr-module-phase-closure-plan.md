# HR Module Phase Closure Plan

**Date:** 2026-04-01  
**Source:** Consolidated from direct senior review plus Gemini advisory review, with local-code verification.

## Strategic Direction

This closure program should be executed as a **product maturation phase**, not as a broad refactor.

### Adopted Product Decisions

1. `/hr` should become the **Admin Workspace** only.
2. `/hr/my-profile` should become the **Self-Service Hub** only.
3. We should prefer **thin route pages + feature slices/components** over keeping giant pages alive.
4. We should not introduce large schema changes unless a workflow absolutely requires them.
5. We should fix journey boundaries first, then lifecycle depth, then structural cleanup.

## Answers to Gemini Open Questions

### 1. Dashboard Routing Strategy

**Decision:** split the surfaces.

- `/hr` = admin/supervisor workspace
- `/hr/my-profile` = employee self-service hub

Reason:

- cleaner role mental model
- fewer mixed permissions on one screen
- easier navigation design
- easier route enforcement

We should not keep a single dynamic `/hr` surface that tries to be everything to everyone.

### 2. Page Dismantling Strategy

**Decision:** yes, align with a feature-slice structure.

Recommended direction:

- keep route entry pages in `src/pages/hr/...`
- move reusable workflow/tab slices into `src/features/hr/...`

This is better than leaving `EmployeeProfile.tsx` and `HRSettingsPage.tsx` as giant files.

### 3. Attendance / Contract Permissions

**Decision:**

- `hr.attendance.read` already exists in permissions constants and should be adopted in routes/sidebar immediately.
- `hr.contracts.manage` does **not** appear as an existing permission constant and should only be introduced if Wave 2 creates a dedicated contract-management surface.

### 4. Document Storage

**Decision:** do not mock uploads.

`hr-documents` is already used in services and leave upload flow, so the bucket is an assumed part of the system.

Action:

- keep using the real bucket
- add bucket/policy verification to implementation checklist

### 5. Offboarding Account Disable Strategy

**Decision:** do not add a new revocation system in Wave 2.

Current backend already deactivates the linked profile when employee status becomes `terminated`.

Therefore Wave 2 should:

- build a real offboarding UX/workflow
- rely on current backend deactivation behavior
- postpone deeper auth revocation redesign unless a real gap appears during implementation

## Wave 1 — Route / Permission / Journey Cleanup

### Goal

Make the HR module role-clean and navigation-clean before expanding features.

### Scope

#### 1. Tighten HR routes

Files:

- `src/App.tsx`
- `src/components/layout/Sidebar.tsx`

Required work:

- gate `/hr` with explicit HR/admin-oriented permission
- switch `/hr/attendance` to attendance-specific permissioning
- review `/hr/permissions` access matrix
- ensure self-service routes remain reachable without over-broad admin permissions

#### 2. Separate admin tools from self-service in navigation

Files:

- `src/components/layout/Sidebar.tsx`

Required work:

- keep HR admin cluster distinct
- create a clearer “My Space” mental model around `/hr/my-profile`
- remove navigation ambiguity for employees

#### 3. Refactor permissions surface by role intent

Files:

- `src/pages/hr/permissions/PermissionsPage.tsx`

Required work:

- split request flow from review flow
- use tab or segmented surfaces by role intent
- avoid mixing employee request actions with approval workspace in one flat screen

#### 4. Upgrade My Profile from portal to workspace

Files:

- `src/pages/hr/MyProfilePage.tsx`

Required work:

- strengthen self-service structure
- improve unlinked-account state
- prepare placeholders/contracts for upcoming payslip/history additions

### Exit Criteria

- HR routes use precise permissions
- self-service routes are coherent
- `/hr` and `/hr/my-profile` no longer represent mixed identities
- permissions screen is role-aware

## Wave 2 — Employee Lifecycle Maturity

### Goal

Turn employee administration from record-editing into complete lifecycle workflows.

### Scope

#### 1. Employee form redesign into guided flow

Files:

- `src/pages/hr/employees/EmployeeForm.tsx`
- supporting new components under `src/features/hr/employees/...`

Recommended step groups:

1. personal + emergency data
2. organizational assignment + attendance setup
3. compensation + employment context

#### 2. Contract management surface

Files:

- `src/pages/hr/employees/EmployeeProfile.tsx`
- new contract workflow components under `src/features/hr/employees/contracts/...`

Required work:

- add real create/renew contract UX
- elevate contracts from embedded read surface to operational flow

#### 3. Offboarding workflow

Files:

- new `OffboardingModal` / workflow surface
- employee profile integration

Required work:

- capture final work date
- capture reason
- make system effects explicit
- rely on current backend status/termination trigger

#### 4. Employee self-service maturity

Files:

- `src/pages/hr/MyProfilePage.tsx`
- payroll-related service/query surfaces

Required work:

- add payslip/history visibility
- expose finalized payroll information professionally

### Exit Criteria

- employee lifecycle includes guided create/edit/offboarding
- contracts become a real management surface
- self-service includes real payroll visibility

## Wave 3 — Surface Utilization & Structural Cleanup

### Goal

Exploit backend depth better while reducing structural risk in the frontend.

### Scope

#### 1. Dismantle `EmployeeProfile.tsx`

Target structure suggestion:

- `src/features/hr/employee-profile/ProfileOverviewTab.tsx`
- `src/features/hr/employee-profile/ProfileDocumentsTab.tsx`
- `src/features/hr/employee-profile/ProfileContractsTab.tsx`
- `src/features/hr/employee-profile/ProfileSalaryHistoryTab.tsx`
- `src/features/hr/employee-profile/ProfileAttendanceTab.tsx`
- `src/features/hr/employee-profile/ProfileDelegationsTab.tsx`

#### 2. Dismantle `HRSettingsPage.tsx`

Target structure suggestion:

- `src/features/hr/settings/SettingsTab.tsx`
- `src/features/hr/settings/DepartmentsTab.tsx`
- `src/features/hr/settings/PositionsTab.tsx`
- `src/features/hr/settings/LocationsTab.tsx`
- `src/features/hr/settings/HolidaysTab.tsx`
- `src/features/hr/settings/PenaltiesTab.tsx`

#### 3. Complete settings CRUD where backend already supports it

Required work:

- expose position update/delete properly
- review holiday editing strategy
- align settings surface with service capability

#### 4. Expose attendance/penalty operational depth

Files:

- `src/pages/hr/attendance/AttendancePage.tsx`
- attendance-related feature slices

Required work:

- make penalty processing more visible and operational
- surface review/waive/process logic in a more professional way

### Exit Criteria

- the largest files are decomposed
- settings CRUD is more complete
- attendance review surface better reflects backend depth

## Recommended Execution Order

1. Wave 1 first
2. Wave 2 second
3. Wave 3 third

Do **not** start with giant file decomposition before route/permission cleanup.

## Suggested Implementation Sequence

### Phase 1A

- tighten `App.tsx`
- tighten `Sidebar.tsx`
- define `/hr` vs `/hr/my-profile` role separation

### Phase 1B

- rebuild `PermissionsPage` surface by role intent
- improve `MyProfilePage` guided states

### Phase 2A

- employee form stepper
- employee lifecycle data grouping

### Phase 2B

- contract management flow
- offboarding flow

### Phase 2C

- payslip and payroll-history self-service

### Phase 3A

- split `EmployeeProfile.tsx`

### Phase 3B

- split `HRSettingsPage.tsx`
- complete settings CRUD

### Phase 3C

- expose attendance penalties and advanced review surfaces

## Verification Program

### Role / Access Verification

- employee user
- manager/supervisor user
- HR admin user

Verify:

- route access
- sidebar visibility
- no direct URL gaps
- self-service/admin boundary clarity

### Workflow Verification

- employee create/edit
- leave request / approval
- permission request / approval
- attendance check-in and attendance review
- advance request and approval
- payroll run review and approval
- offboarding
- contract creation/renewal
- payslip access

### Structural Verification

- build passes
- routes remain reachable
- permissions remain correct
- no regressions in existing payroll/attendance flows

## Final Recommendation

Start implementation with **Wave 1 only**.

That wave produces the highest product clarity with the lowest structural risk, and it creates the correct foundation for the lifecycle work that follows.
