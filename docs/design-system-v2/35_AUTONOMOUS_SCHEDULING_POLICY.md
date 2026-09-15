# 35 — Autonomous Scheduling Policy

## Purpose

Prevent scheduled-agent collisions across the EDARA Design System V2 workstream and the separately running Garment Ops autonomous team while still using the minimum supported one-hour cadence where it adds real value.

Timezone: `Africa/Cairo`.

## Global scheduling principle

Do not schedule two active autonomous roles at the same minute when they can be phase-shifted safely.

The system is designed as a pipeline, not a burst:

`previous review -> integration -> implementation -> review -> next integration`

Exact start-time separation does not guarantee that long-running jobs never overlap in wall-clock time, so repository ownership, one-slice WIP, exact-head checks, no-op gates and role-state ownership remain mandatory. Different projects use different repositories, which removes cross-repository write conflict, but we still avoid same-minute starts to reduce tool/runtime contention.

## Design System V2 reserved slots

### Product Design Director
- Minute: `:00`
- Cadence: every 2 hours
- Reason: strategic/system-level synthesis does not need hourly mutation. It runs before the operational cycle and must no-op when a healthy PR/integration pipeline is already in flight.

### Development Integrator
- Minute: `:05`
- Cadence: hourly
- Purpose: consume the prior hour's exact-head QA result. Merge only GREEN-DEV work into `design-system-v2-development`; otherwise no-op.

### UI Production Engineer
- Minute: `:15`
- Cadence: hourly
- Purpose: begin/continue the single READY or active UI slice after the integration checkpoint.

### Design QA
- Minute: `:45`
- Cadence: hourly
- Purpose: review the implementation state produced earlier in the hour and hand a GREEN-DEV/BLOCKED disposition to the next `:05` integration checkpoint.

This creates the repeating operational loop:

`HH:05 integrate previous result -> HH:15 implement -> HH:45 review -> (HH+1):05 integrate`

The Design Director runs at `HH:00` every second hour and should avoid changing workstream/shared memory when an exact-head GREEN merge is pending at `:05`; in that case it records no-op unless a material BLOCKING design contradiction exists.

## Cross-project reserved minutes

The currently active Garment Ops team already occupies the following schedule lanes:

- `:10` — one phased specialist each hour (Product / UX / Domain / Frontend, each on 4-hour cadence)
- `:20` — Integration Steward hourly
- `:25` — QA Senior every 2 hours
- `:30` — AppSec Senior hourly
- `:35` — Platform/SRE hourly
- `:40` — PM / Tech Lead hourly
- `:50` — Implementation Loop hourly
- `:55` — Backend Builder hourly

The Design System V2 slots (`:00`, `:05`, `:15`, `:45`) intentionally avoid those lanes.

A currently disabled Garment Ops Frontend Builder historically uses `:05`. If that agent is re-enabled in the future, the global schedule MUST be re-reviewed before activation; do not silently accept the collision.

## Collision rules

1. No agent may change its own schedule.
2. Schedule changes require a global review of all enabled automations, not just this repository.
3. Same-minute starts across active projects are prohibited unless there is an explicit reason and no practical alternative.
4. Within DS2, the UI Engineer must no-op when the exact current implementation PR already has GREEN-DEV awaiting integration; it must not mutate the reviewed HEAD between `:45` QA and next `:05` Integrator.
5. Design QA reviews the exact PR HEAD only. A moved HEAD invalidates prior GREEN-DEV.
6. Integrator merges only the exact reviewed HEAD and updates Team Memory after merge.
7. Product Design Director does not compete with Integrator for a healthy in-flight merge; material design contradictions are the only reason to intervene before the `:05` gate.
8. All roles retain one-slice WIP and state-file ownership from `34_AGENT_TEAM_COMMUNICATION_PROTOCOL.md`.

## Capacity rationale

Hourly cadence is used where fresh state can materially change every cycle:
- implementation
- QA/review
- integration

Two-hour cadence is used for Design Director because its role is system synthesis and roadmap coherence, not repeated code mutation. Running it every hour would add read/write noise without increasing safe throughput while increasing coordination pressure around the same shared governance files.

## Required re-review triggers

Re-run the global scheduling audit before any of the following:

- enabling another scheduled agent
- re-enabling Garment Ops Frontend Builder
- adding a release/security/preview agent to EDARA
- changing an existing agent from multi-hour cadence to hourly
- adding an automation using one of `:00`, `:05`, `:15`, `:45`
- sustained evidence that a role routinely exceeds its handoff window and causes stale reviews or moved HEADs

Scheduling is a throughput control. It must never override exact-head, WIP, branch or quality gates.
