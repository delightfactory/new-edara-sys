# EDARA Design System V2 — Agent Operating Contract

This file is authoritative for any automated or human-assisted agent working on the Design System V2 workstream.

## 1. Mission

Improve EDARA's UI architecture, design system, responsive experience, and page composition without changing product behavior.

EDARA is a multi-device operational application. Mobile is the primary daily operating surface for many users. Tablet is a deliberate intermediate mode. Desktop is optimized for dense management and review workflows.

## 2. Authoritative branch

- Integration branch: `design-system-v2-development`
- `main` is frozen for this workstream until the user explicitly approves final rollout.
- Never commit, merge, rebase, or force-push Design System V2 work directly onto `main`.
- Every implementation slice starts from the latest `design-system-v2-development` HEAD.
- Every implementation PR targets `design-system-v2-development`.

## 3. Deployment rule

- Never trigger Vercel automatically from development work.
- Never change `vercel.json` to enable deployments on the development branch.
- Preview deployment is user-requested only.
- Preview work uses a dedicated temporary preview branch created from the current development HEAD.
- Agents must not create, redeploy, promote, alias, or publish a preview unless the user explicitly asks to see the current version.
- Production deployment is forbidden in this workstream.

## 4. Hard functional isolation boundary

Design System V2 work MUST NOT change:

- database schema or migrations
- RPCs or stored procedures
- Supabase queries or service contracts unless a separate explicitly-approved functional task exists
- RBAC, RLS, route guards, permission values, or ownership rules
- accounting, inventory, credit, payroll, attendance, sales, procurement, or HR business calculations
- workflow states or state transitions
- API contracts
- business responsibilities
- validation semantics
- transaction behavior
- cache/query semantics

If a UI task exposes a functional defect, log it separately. Do not fix it inside the UI PR.

## 5. Architecture rules

Prefer the existing V2 layers before inventing new ones:

1. semantic tokens/foundations
2. `src/components/ui` primitives
3. `src/components/patterns` application patterns
4. domain/page composition

Do not create a page-local replacement for an existing shared V2 primitive or pattern without documenting why the shared contract is insufficient.

Keep styling layered:

`tokens -> V2 semantic aliases -> primitives -> patterns -> page composition`

Avoid large inline-style blocks in migrated pages.

## 6. Device rules

Canonical modes:

- Mobile: `<= 768px`
- Tablet: `769px–1024px`
- Desktop: `>= 1025px`

Every migrated screen must preserve functional parity and be intentionally composed for all three modes.

Mobile requirements:

- touch targets must be appropriate for operational use
- no horizontal overflow for ordinary task flows
- primary task must be obvious
- do not mount hidden desktop interaction trees when a mobile composition is active

Tablet requirements:

- must not be treated as compressed desktop
- use deliberate density/layout decisions

Desktop requirements:

- preserve dense information and management efficiency

## 7. Work slicing

- One implementation slice at a time.
- One coherent concern per PR.
- Do not combine unrelated page migrations.
- A slice is not done until the exact PR HEAD is reviewed against the quality gates.
- Do not start the next implementation slice while the current slice has an unresolved blocker.

## 8. Agent roles

### Design Architect

Owns scope selection and acceptance criteria.

May:
- inspect the development branch
- inspect open PRs and docs
- update the work queue / architecture notes
- define the next small slice

Must not:
- implement product code for the selected slice
- merge PRs
- deploy previews

### UI Implementer

Owns one READY slice.

May:
- create a feature branch from the exact current development HEAD
- modify presentation code, tests, and Design System documentation
- open a PR targeting `design-system-v2-development`

Must not:
- modify backend/business behavior
- target `main`
- merge its own PR
- deploy previews
- begin a second slice while its current PR is unresolved

### Quality Reviewer

Owns independent review of the implementation PR.

Must verify:
- changed-file scope
- functional-isolation boundary
- TypeScript/build risks visible from source or available gates
- tests protect the migrated behavior
- mobile/tablet/desktop contracts
- RTL/accessibility/focus/touch considerations
- no hidden new design-system fork inside a page

May request changes or mark a PR GREEN.

Must not merge the PR or deploy.

### Integrator

Owns controlled merge into `design-system-v2-development` only.

May merge only when:
- PR base is `design-system-v2-development`
- reviewer state is GREEN
- no unresolved review blocker exists
- diff contains no forbidden backend/functional change
- exact reviewed HEAD has not moved

After merge:
- update the work queue
- stop; do not deploy
- never merge development to `main`

## 9. Quality gates

For each slice, record at minimum:

1. Scope Gate — changed files match intended UI slice.
2. Functional Isolation Gate — no backend/business behavior changes.
3. Device Gate — explicit Mobile/Tablet/Desktop behavior.
4. State Gate — relevant loading/empty/error/disabled/permission states preserved.
5. Accessibility Gate — labels, focus, keyboard/touch behavior considered.
6. Test Gate — focused tests added/updated where the migration changes composition.
7. Build Gate — when a build is available, it must pass on the exact HEAD. A build failure blocks merge.
8. Review Gate — reviewer marks the exact HEAD GREEN.

No gate may be bypassed by weakening tests or changing unrelated behavior.

## 10. Preview policy

Visual preview is a controlled evidence step, not part of normal agent cadence.

When the user requests a preview:

1. freeze the current development HEAD
2. create/update a dedicated preview branch from that HEAD
3. apply preview-only switches there if needed
4. allow one Vercel preview build
5. inspect build result before sharing the URL
6. never merge preview-only commits back into development

## 11. Current direction

The active rollout sequence remains:

App Shell / navigation -> Dashboard -> Customers -> Sales -> Inventory -> Procurement -> Finance -> HR -> Activities/Targets -> Work Management -> Reports/Analytics -> Settings/Admin -> cleanup.

Manufacturing readiness comes after the shared visual/product grammar is stable.

## 12. Stop conditions

Stop and mark BLOCKED rather than guessing when:

- a task requires backend/business changes
- a required permission or workflow meaning is unclear
- the development branch moved in a way that invalidates the current slice
- another active PR overlaps the same files substantially
- build/test evidence reveals a functional regression
- a preview/deploy would be needed without explicit user request
