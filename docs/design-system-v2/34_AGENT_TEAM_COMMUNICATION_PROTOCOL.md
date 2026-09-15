# 34 — Design System V2 Agent Team Communication Protocol

## Why this exists

The Design System V2 team is intended to operate as one autonomous product-design cell, not as isolated scheduled jobs.

The repository is the team's shared room, durable memory, evidence base, design language, and handoff surface.

The operating loop is:

`Design direction -> bounded implementation -> independent design QA -> integration -> shared-memory update -> next slice`

Every agent must know what the other roles currently believe, what changed, what is blocked, and what must be preserved before acting.

## Communication surfaces

### 1. Role state files — current professional view

Each role owns exactly one state file under `team/design-system-v2/`:

- `DESIGN_DIRECTOR_STATE.md`
- `UI_IMPLEMENTATION_STATE.md`
- `DESIGN_QA_STATE.md`
- `INTEGRATION_STATE.md`

Only the owning role normally writes its file. All roles read all four at the start of every run.

Each state file must contain:

1. reviewed development baseline / exact SHA
2. active slice / PR / current state
3. latest material findings or work completed
4. current professional judgment
5. constraints or truths that must be preserved
6. blockers / risks / unknowns
7. cross-role handoff
8. what changed since the previous state

No update is required when nothing material changed.

### 2. Team memory — synthesized current truth

`team/design-system-v2/TEAM_MEMORY.md`

This is the compact shared brain of the workstream. It contains only current truth, not every historical detail:

- North Star summary
- authoritative branch and current integrated HEAD
- current active/ready slice
- latest Design Director direction
- latest implementation position
- latest QA disposition
- latest integration position
- known product-design invariants
- current blockers/risks
- reusable patterns learned from recent slices
- next handoff

Ownership:
- Design Director may update it when design/system direction materially changes.
- Integrator updates it after a successful merge.
- Implementer and QA read it but do not normally mutate it.

TEAM_MEMORY is not a decision log and must remain compact.

### 3. Decision log — durable decisions

`team/design-system-v2/DECISION_LOG.md`

Use only for decisions that future agents must not accidentally reverse, for example:

- Mobile-primary device strategy
- tablet breakpoint/composition decisions
- long-lived branch policy
- Vercel preview policy
- GitHub Actions quota policy
- component ownership decisions
- semantic status/action rules
- accepted design-language principles

Each decision records:
- ID
- date
- decision
- reason/evidence
- affected area
- owner
- status (`ACTIVE`, `SUPERSEDED`)

Do not use the log for routine progress.

### 4. GitHub issue #27 — chronological coordination/event stream

Issue #27 is the team's event feed for concise material events:

- implementation PR opened
- material blocker
- QA BLOCKED / GREEN-DEV
- merge completed
- next READY slice
- owner decision needed

Do not spam it on every scheduled no-op.

### 5. Pull request — slice-specific technical conversation

The PR owns exact-line implementation review and current-slice discussion.

Do not put long-lived product-design decisions only in a PR comment. Promote durable decisions into the Decision Log / Team Memory.

## Mandatory read order for every agent run

Before deciding or writing anything:

1. `AGENTS.md`
2. `docs/design-system-v2/32_DESIGN_SYSTEM_NORTH_STAR.md`
3. `docs/design-system-v2/33_TEST_AND_VALIDATION_POLICY.md`
4. this communication protocol
5. `team/design-system-v2/TEAM_MEMORY.md`
6. all four role state files
7. `team/design-system-v2/DECISION_LOG.md` when the task can affect a durable rule
8. `docs/design-system-v2/31_AGENT_TEAM_WORKSTREAM.md`
9. issue #27
10. current open PR / exact development HEAD as relevant

An agent must form its own professional judgment first, then compare against other role states to identify alignment or contradiction.

## Cross-role disagreement protocol

Agents are expected to disagree when their professional lenses reveal different risks.

When a material disagreement exists:

1. the role records its independent judgment in its own state file;
2. identify the exact contradiction, evidence, and affected slice;
3. do not overwrite another role's state;
4. do not resolve by vote;
5. Design Director synthesizes design/product-system disagreements;
6. Integrator never merges while a material unresolved contradiction is marked BLOCKING;
7. anything requiring product/business behavior change is escalated as a separate user/functional decision, never solved inside UI scope.

## Handoff format

Every material state update ends with:

### Cross-role handoff
- **To:** role(s)
- **What changed:** one concise statement
- **Preserve:** invariants/decisions that must not drift
- **Need from you:** explicit next evidence/action
- **Blocker level:** `NONE`, `WATCH`, `BLOCKING`
- **Baseline:** exact SHA / PR head

This makes the next scheduled agent able to continue without reconstructing context from chat history.

## Freshness

Every state file must show its reviewed baseline and date/time or run date.

A state is stale when:
- its reviewed executable/PR HEAD moved materially;
- another merge changed the relevant shared component/pattern;
- the active slice changed;
- a blocker it relied on was resolved or superseded.

Stale state may be informative, but cannot be used as current approval evidence.

## Noise control

The goal is shared intelligence, not documentation inflation.

Do not write a state update for:
- no-op scheduled runs
- unchanged opinions
- routine polling
- duplicate blockers already current in the file

Prefer one high-value current state over an append-only wall of logs.

## Communication outcome

At any time, a newly started agent should be able to read the repository and answer:

- What are we building toward?
- What is the exact current development baseline?
- What slice is active and why?
- What did each role most recently conclude?
- What must not be broken?
- What is blocked?
- What does the next role need to do?
- Which decisions are already settled?

If these questions cannot be answered from the repository, the team communication system is not healthy.
