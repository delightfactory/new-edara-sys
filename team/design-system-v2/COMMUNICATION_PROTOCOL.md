# Design System V2 — Agent Communication Protocol

## Purpose

The repository is the Design System team's shared room, memory, evidence base and handoff surface.

Scheduled agents are not independent cron jobs. They operate as one continuous product-design team with different authorities. Communication must therefore be durable, exact-head aware, low-noise and readable by every role on its next run.

This protocol follows the proven operating principle used by the Garment Ops autonomous team: specialist evidence is persisted in role-owned state, a coordinating role maintains shared truth, one implementation work item stays active, and every handoff is grounded in repository evidence rather than transient chat context.

## Canonical communication surfaces

### 1. `TEAM_MEMORY.md` — shared current truth

Purpose: concise synthesis of what every role needs to know now.

Contains only:
- current branch/baseline truth;
- active slice and intent;
- latest material role positions;
- invariants to preserve;
- known risks/evidence;
- reusable Design System learnings;
- next cross-role handoff.

It is not a chronological log and must not accumulate stale history.

Normal writers:
- Product Design Director when system direction materially changes;
- Development Integrator after a completed merge changes the integrated baseline.

### 2. Role-owned state files — professional position and handoff

- `DESIGN_DIRECTOR_STATE.md`
- `UI_IMPLEMENTATION_STATE.md`
- `DESIGN_QA_STATE.md`
- `INTEGRATION_STATE.md`

Each role owns only its own state file during normal operation.

A role state records the latest material professional position for that role, not every scheduled heartbeat.

Peer roles read all state files, but do not rewrite another role's conclusions.

### 3. `DECISION_LOG.md` — durable decisions

Use only for decisions future agents must preserve unless explicitly superseded.

Examples:
- device contract;
- branch/deployment/CI policy;
- component ownership rule;
- a long-lived system architecture decision.

Do not use it for transient implementation status, review comments or temporary blockers.

### 4. `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md` — queue and WIP truth

Owns:
- active slice;
- state machine;
- scope/exclusions/acceptance;
- backlog sequencing;
- completion evidence after integration.

Exactly one implementation slice may be active.

### 5. Issue #27 — chronological event stream

Issue #27 is the concise team event stream, not the primary memory store.

Write there only for material events such as:
- slice claimed / PR opened;
- material architectural correction;
- review BLOCKED;
- exact-head GREEN-DEV;
- merge completed / next slice READY;
- cross-role contradiction requiring attention;
- real owner-decision blocker.

Do not post hourly no-op/status chatter.

### 6. Active PR — implementation/review evidence

The active PR is the authoritative surface for:
- exact changed code;
- implementation description;
- exact-head review findings;
- `AGENT-REVIEW: BLOCKED` / `AGENT-REVIEW: GREEN-DEV`;
- focused technical discussion tied to the diff.

## Mandatory read order before material action

Every scheduled role must read the latest versions from `design-system-v2-development` in this order:

1. `AGENTS.md`
2. `docs/design-system-v2/32_DESIGN_SYSTEM_NORTH_STAR.md`
3. `docs/design-system-v2/33_TEST_AND_VALIDATION_POLICY.md`
4. `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md`
5. `team/design-system-v2/COMMUNICATION_PROTOCOL.md`
6. `team/design-system-v2/TEAM_MEMORY.md`
7. every role-owned state file
8. `team/design-system-v2/DECISION_LOG.md`
9. issue #27
10. active PR and relevant Design System/source evidence

This makes every agent aware of the other agents' current professional positions before it acts.

## Independent-judgment rule

Shared state provides context, not consensus-by-copying.

Each specialist remains accountable for independent judgment from current evidence:
- Design QA must inspect the exact PR HEAD and cannot inherit the UI Engineer's self-assessment.
- UI Engineer may use Director/QA handoffs but must verify the current branch and code before changing it.
- Integrator may use QA disposition only when it references the exact current HEAD and all merge gates still hold.
- Product Design Director synthesizes peer evidence but must judge against the North Star and current product, not by vote.

If peer state conflicts with current evidence, current evidence wins and the contradiction is recorded.

## Standard cross-role handoff

Every material role-state update ends with a compact handoff containing:

- **From:** role
- **To:** intended next role(s)
- **Slice:** slice ID
- **Baseline:** exact development SHA or PR HEAD
- **What changed:** material delta only
- **Evidence:** source/runtime/test evidence label(s)
- **Preserve:** invariants/contracts that must not move
- **Need next:** exact next action or decision
- **Blocker:** `NONE`, `P1`, or `P0` plus reason
- **Freshness:** what change would make this handoff stale

Handoffs must be actionable. Avoid generic statements such as "continue work" when a more exact next action is known.

## Freshness and invalidation

State without a baseline is advisory only.

Rules:
- implementation state references the feature baseline and exact PR HEAD;
- QA disposition is valid only for the exact reviewed PR HEAD;
- integration disposition is valid only while PR HEAD and base remain unchanged;
- a material development-branch change can invalidate an unstarted slice baseline;
- after merge, Integrator updates Workstream and Team Memory so later roles do not operate from a pre-merge worldview;
- stale peer state remains historical context but must not authorize action.

## WIP synchronization contract

The following must agree:
- active slice in `31_AGENT_TEAM_WORKSTREAM.md`;
- active slice in `TEAM_MEMORY.md`;
- UI implementation state when implementation has started;
- active PR title/body when a PR exists.

If they materially disagree, do not start a second slice. Product Design Director resolves queue/design intent; Integrator resolves post-merge queue state.

## Communication flow

Normal loop:

`Director intent -> UI implementation -> QA disposition -> Integration -> shared-memory refresh -> next Director/Engineer cycle`

### Product Design Director

Publishes:
- system/design direction;
- scope and acceptance corrections;
- missing shared-pattern requirements;
- next READY slice when no valid one exists;
- durable decisions when needed.

Does not micromanage implementation details already covered by the shared contracts.

### UI Production Engineer

Publishes:
- claimed baseline / branch / PR;
- files and shared patterns changed;
- device/state coverage;
- tests authored and honest evidence label;
- remaining risk;
- exact review handoff.

### Design QA

Publishes:
- exact reviewed HEAD;
- independent functional-isolation and North-Star judgment;
- device/RTL/accessibility/state findings;
- evidence label;
- minimum fixes or GREEN-DEV disposition.

### Development Integrator

Publishes:
- exact merge/no-merge decision;
- merged SHA when applicable;
- completed slice evidence;
- reusable system learning;
- next READY slice;
- refreshed integrated Team Memory.

## Contradiction handling

- Business/domain semantic ambiguity: STOP and surface owner/product decision; Design System agents do not invent business truth.
- Design-system architecture disagreement: Product Design Director decides after reading evidence.
- Review blocker disagreement: QA blocker remains blocking until the exact HEAD changes or QA explicitly clears it.
- Merge-state mismatch: Integrator does not merge until exact-head evidence is reconciled.

Never resolve contradiction by silently overwriting another role's state file.

## Noise control

A scheduled run with no new material evidence should no-op.

Do not create commits merely to say:
- still waiting;
- nothing changed;
- PR remains open;
- previous conclusion still stands.

Durable team communication should increase shared understanding, not repository churn.

## Boundaries

This communication system does not authorize:
- edits to `main`;
- Vercel preview/deployment;
- GitHub Actions/hosted CI;
- backend/business changes;
- multiple concurrent implementation slices.

Those remain governed by `AGENTS.md`, the North Star and test policy.
