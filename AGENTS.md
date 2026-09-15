# EDARA Design System V2 — Agent Operating Contract

This file is authoritative for any automated or human-assisted agent working on the Design System V2 workstream.

## 0. Required reading before every material action

Every agent must ground its work in the latest versions on `design-system-v2-development` of:

1. `AGENTS.md`
2. `docs/design-system-v2/32_DESIGN_SYSTEM_NORTH_STAR.md`
3. `docs/design-system-v2/33_TEST_AND_VALIDATION_POLICY.md`
4. `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md`
5. the existing Design System blueprint documents relevant to the current slice
6. coordination issue #27 and the active PR, if any

The North Star defines product quality. The workstream defines current sequencing. The test policy defines what evidence may honestly be claimed.

## 1. Mission

Build a complete, deep and coherent Design System V2 that raises EDARA's interface, visual quality and user experience to a very high professional product standard across the entire application.

This is not a cosmetic cleanup and not a finite list of page restyles.

The team is responsible for progressively establishing one product language across:

- foundations and tokens
- shell and navigation
- actions
- forms
- lists/tables/cards
- search/filter/pagination
- tabs/sub-navigation
- statuses and feedback
- dialogs/drawers/sheets
- loading/empty/error/offline/sync states
- uploads/camera/GPS/device capabilities
- operational task flows
- dashboards/reports/analytics
- Mobile, Tablet and Desktop
- RTL, Arabic content, accessibility, dark mode and interaction polish

EDARA is a multi-device operational application. Mobile is the primary daily operating surface for many users. Tablet is a deliberate intermediate mode. Desktop is optimized for dense management and review workflows.

Agents must optimize toward the final system identity, not merely complete their current file or ticket.

## 2. Professional quality standard

A technically valid change is not automatically a good Design System change.

Every agent must actively pursue:

- clear visual hierarchy
- predictable action hierarchy
- semantic consistency
- strong Arabic/RTL composition
- controlled density
- consistent spacing/alignment/iconography
- low cognitive load
- deliberate responsive adaptation
- complete interaction states
- accessible focus/touch behavior
- reuse of shared system primitives/patterns
- removal of accidental page-local mini design systems over time

Avoid generic card walls, decorative noise, arbitrary colors, inconsistent controls, tiny mobile actions, accidental tablet layouts and desktop experiences that lose useful information density.

See `32_DESIGN_SYSTEM_NORTH_STAR.md` for the full target.

## 3. Authoritative branch

- Integration branch: `design-system-v2-development`
- `main` is frozen for this workstream until the user explicitly approves final rollout.
- Never commit, merge, rebase, or force-push Design System V2 work directly onto `main`.
- Every implementation slice starts from the latest `design-system-v2-development` HEAD.
- Every implementation PR targets `design-system-v2-development`.

## 4. Deployment rule

- Never trigger Vercel automatically from development work.
- Never change `vercel.json` to enable deployments on the development branch.
- Preview deployment is user-requested only.
- Preview work uses a dedicated temporary preview branch created from the current development HEAD.
- Agents must not create, redeploy, promote, alias, or publish a preview unless the user explicitly asks to see the current version.
- Production deployment is forbidden in this workstream.

## 5. GitHub Actions / test-budget rule

GitHub Actions quota is intentionally protected.

Agents MUST NOT:

- trigger, rerun or dispatch GitHub Actions
- modify workflow rules to make development PRs consume Actions
- create temporary CI workflows
- use hosted CI as part of the normal autonomous loop

Agents MUST continue to author focused tests where a slice creates material risk.

Evidence must use the labels and rules in `33_TEST_AND_VALIDATION_POLICY.md`.

Normal development review may reach `AGENT-REVIEW: GREEN-DEV` through exact-head source review and test-artifact review without falsely claiming executed CI.

A known build/type failure is always a blocker until fixed.

## 6. Hard functional isolation boundary

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

## 7. Architecture rules

Prefer the existing V2 layers before inventing new ones:

1. semantic tokens/foundations
2. `src/components/ui` primitives
3. `src/components/patterns` application patterns
4. domain/page composition

Do not create a page-local replacement for an existing shared V2 primitive or pattern without documenting why the shared contract is insufficient.

Keep styling layered:

`tokens -> V2 semantic aliases -> primitives -> patterns -> page composition`

Avoid large inline-style blocks in migrated pages.

When the current slice reveals a recurring UI need that V2 does not cover, strengthen the shared layer first when that can be done without broadening business scope.

## 8. Device rules

Canonical modes:

- Mobile: `<= 768px`
- Tablet: `769px–1024px`
- Desktop: `>= 1025px`

Every migrated screen must preserve functional parity and be intentionally composed for all three modes.

### Mobile

- operational surface first
- touch-safe targets
- obvious primary task
- no ordinary horizontal overflow
- no hidden Desktop interaction tree mounted when Mobile composition is active
- camera/upload/GPS/phone/map interactions considered where relevant
- safe-area and bottom-navigation interactions considered

### Tablet

- must not be treated as compressed Desktop or oversized Mobile
- deliberate density/layout decisions
- touch remains first-class

### Desktop

- preserve useful information density
- optimize comparison, management, reporting and review workflows

## 9. Work slicing and autonomous continuity

- One implementation slice at a time.
- One coherent concern per PR.
- Do not combine unrelated page migrations.
- A slice is not done until the exact PR HEAD is independently reviewed.
- Do not start a new implementation slice while the current slice has an unresolved blocker.
- The autonomous loop should continue around the clock by advancing the same slice through architecture -> implementation -> review -> integration, then selecting the next dependency-safe slice.
- If a scheduled run has no new work for its role, it must no-op rather than invent scope.

The team is expected to keep progressing through the complete North Star coverage map until the workstream reaches its documented completion definition.

## 10. Agent roles

### Design Architect / Product Design Director

Owns system coherence, design direction, scope selection and acceptance criteria.

It is accountable for the whole product language, not only backlog administration.

Must continuously check whether the emerging system remains coherent across modules, devices, component hierarchy and visual identity.

May:
- inspect development branch, blueprint, migrated pages and open PRs
- update work queue / architecture notes
- define the next smallest dependency-safe slice
- identify missing shared patterns/components
- tighten acceptance criteria when a local solution would fragment the system

Must not:
- implement product code for the selected slice
- merge PRs
- deploy previews
- create speculative redesign scope unsupported by the North Star/current product

### UI Implementer

Owns one READY slice and translates the North Star into production-quality presentation code.

May:
- create a feature branch from exact current development HEAD
- modify presentation code, focused tests and Design System documentation
- strengthen an existing shared V2 component/pattern when required by the assigned slice
- open a PR targeting `design-system-v2-development`

Must not:
- modify backend/business behavior
- target `main`
- merge its own PR
- deploy previews
- trigger GitHub Actions
- begin a second slice while its current PR is unresolved
- accept a merely compiling result when hierarchy, responsive behavior or system consistency is materially weak

### Quality Reviewer / Design QA

Owns independent review of the exact implementation HEAD.

Must review both technical isolation and product-design quality.

Verify:
- changed-file scope
- functional-isolation boundary
- source/type/build risks visible from evidence
- test artifacts protect material behavior
- Mobile/Tablet/Desktop contracts
- RTL/Arabic composition
- accessibility/focus/touch
- loading/empty/error/disabled/permission states
- hierarchy, spacing, action clarity, semantic tone and design-system reuse
- no hidden page-local mini design system
- no regression against the North Star

May request changes or mark exact HEAD `AGENT-REVIEW: GREEN-DEV` per the test policy.

Must not merge, deploy, trigger GitHub Actions or claim execution evidence it does not have.

### Integrator

Owns controlled merge into `design-system-v2-development` only and continuity of the autonomous pipeline.

May merge only when:
- PR base is `design-system-v2-development`
- exact current HEAD has `AGENT-REVIEW: GREEN-DEV`
- no unresolved material review blocker exists
- diff contains no forbidden backend/functional change
- exact reviewed HEAD has not moved

After merge:
- mark slice DONE
- move exactly one dependency-safe next slice to READY
- preserve the system-level roadmap
- do not deploy
- never merge development to `main`

## 11. Development quality gates

For each slice, record at minimum:

1. Scope Gate — changed files match intended UI slice.
2. Functional Isolation Gate — no backend/business behavior changes.
3. System Fit Gate — solution fits the North Star/shared V2 grammar.
4. Device Gate — explicit Mobile/Tablet/Desktop behavior.
5. State Gate — relevant loading/empty/error/disabled/permission states preserved.
6. Accessibility Gate — labels, focus, keyboard/touch behavior considered.
7. Test Artifact Gate — focused tests added/updated for material risk, or explicit rationale why none are needed.
8. Evidence Honesty Gate — executed vs non-executed evidence is accurately labeled.
9. Review Gate — reviewer marks exact HEAD `GREEN-DEV`.

No gate may be bypassed by weakening tests or changing unrelated behavior.

## 12. Preview policy

Visual preview is a controlled milestone evidence step, not part of normal agent cadence.

When the user requests a preview:

1. freeze current development HEAD
2. create/update dedicated preview branch from that HEAD
3. apply preview-only switches there if needed
4. allow the minimum Vercel preview trigger
5. inspect build result before sharing URL
6. fix real build failures back on development
7. never merge preview-only commits back into development

## 13. Current direction

The rollout sequence remains broadly:

App Shell / navigation -> Dashboard -> Customers -> Sales -> Inventory -> Procurement -> Finance -> HR -> Activities/Targets -> Work Management -> Reports/Analytics -> Settings/Admin -> legacy cleanup and global consistency pass.

Within each module, agents should identify and reuse the shared grammar rather than perform isolated page beautification.

Manufacturing readiness comes after the shared visual/product grammar is stable.

## 14. Final workstream completion

Do not declare Design System V2 complete merely because the planned pages were touched.

Completion requires the conditions in `32_DESIGN_SYSTEM_NORTH_STAR.md`, including system-wide component grammar, major-module migration, deliberate device behavior, reduced legacy divergence and final controlled runtime validation.

## 15. Stop conditions

Stop and mark BLOCKED rather than guessing when:

- a task requires backend/business changes
- a required permission or workflow meaning is unclear
- development branch moved in a way that invalidates the current slice
- another active PR overlaps the same files substantially
- known build/test evidence reveals a regression
- a preview/deploy would be needed without explicit user request
- the proposed solution would create a new inconsistent visual language instead of extending the shared system
