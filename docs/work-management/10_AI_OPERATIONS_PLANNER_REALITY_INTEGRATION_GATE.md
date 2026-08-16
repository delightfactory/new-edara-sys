# Delight AI Operations Planner — Reality & Integration Gate

**Status:** Architecture reality review — no AI migration implemented  
**Branch:** `feature/work-management`  
**Purpose:** distinguish what is technically real today from what still requires a hardened integration path before autonomous production use.

---

## 1. Executive verdict

The core idea is **real and implementable**: EDARA can build compact operational snapshots, material cases, responsibility evidence, governed context, AI decisions, human feedback, reliability state and guarded Work creation without modifying the core transaction paths.

The critical correction is architectural:

> **The AI Operations Planner core must belong to EDARA. ChatGPT is one replaceable reasoning worker adapter, not the scheduler, source of truth, recovery engine or security boundary.**

This separation is required for continuity, auditability and future portability.

The system is therefore split into:

```text
EDARA Planner Core
  deterministic schedules / expected runs
  snapshot + case engine
  operational context
  run ledger / leases / checkpoints
  decisions / feedback
  safety gates
  Work bridge
  UI / audit / health

AI Worker Adapter
  claim a due run
  consume bounded context
  request bounded drill-down
  reason / prioritise
  stage concise decisions
  never become source of truth
```

---

## 2. What is implementable now with high confidence

The following can be implemented entirely inside the existing EDARA/Supabase architecture and does not depend on ChatGPT product reliability:

1. isolated `ai_ops` schema and planner state;
2. deterministic run schedules and expected-run creation;
3. immutable snapshots and case fingerprints;
4. compact current-state/read models over existing reporting semantics;
5. receivables/credit causal responsibility evidence;
6. operational context with expiry/review;
7. decision staging and feedback records;
8. duplicate/collision validation against current Work;
9. system-origin Work bridge using existing `source_kind='system'`, `actor_kind='system'`, source-key idempotency and Work notifications;
10. dead-man health detection inside EDARA;
11. an AI Operations Control Center UI;
12. Shadow Mode and human approval workflows.

These parts form a useful product even before autonomous AI execution is enabled.

---

## 3. What is NOT safe to assume

### 3.1 A ChatGPT Scheduled Task is not a guaranteed orchestrator

Scheduled Tasks are suitable for recurring checks, but the planner architecture must assume a scheduled worker may:

- miss a run;
- be paused or require user action;
- lose access to an app/action;
- encounter product/tool errors;
- execute late;
- execute twice around a retry/recovery edge.

Therefore a scheduled task must not be the authoritative record that a business planning cycle exists or completed.

EDARA creates/knows the expected run first. An AI worker only claims it.

### 3.2 Database dead-man monitoring cannot magically wake a failed ChatGPT task

A database watchdog can detect a missed run and notify management. It cannot, by itself, guarantee that a personal ChatGPT Scheduled Task will restart.

Recovery therefore has two levels:

1. **same-worker recovery:** the next successful worker check can claim old pending/expired runs;
2. **human/platform recovery:** EDARA raises an explicit alert when the AI worker channel itself has stopped.

This is still materially better than silent failure, but it is not the same as a fully API-triggered durable worker.

### 3.3 The current Supabase ChatGPT connection is not a least-privilege autonomous write channel

The current Supabase app connection has broad administrative capabilities. Prompt instructions such as “only call these RPCs” are policy, not a technical permission boundary.

Therefore:

- interactive development/read analysis can continue through the current connection;
- Shadow Mode may use it under explicit testing controls;
- **unattended autonomous mutation is not production-approved through this broad connector**;
- automatic Work creation remains disabled until a bounded action surface is technically enforced.

### 3.4 Custom narrow write integrations are plan/platform dependent

OpenAI currently exposes fuller custom MCP/action control for managed Business/Enterprise/Edu environments. A personal Plus setup must not be designed as if those managed-workspace controls already exist.

The core must therefore support multiple worker adapters so upgrading/changing the AI integration later does not require redesigning `ai_ops` or Work Management.

---

## 4. The real closed loop

The genuine business loop is:

```text
1. EDARA decides a planning cycle is due.
2. EDARA builds a trusted bounded snapshot/case set.
3. AI worker claims that persisted run.
4. AI reasons only over that bounded context.
5. Optional drill-down retrieves evidence for selected cases only.
6. AI stages dispositions and concise rationale.
7. EDARA validates current facts, ownership, context, duplicates and policy again.
8. In Shadow/Human mode: management accepts/rejects/edits.
9. In a future approved low-risk auto tier: system Work bridge commits validated actions.
10. Work events and business outcomes feed back into the next planner context.
11. Human overrides remain authoritative and become structured feedback/context where useful.
```

The loop is **not**:

```text
ChatGPT reads database -> invents tasks -> inserts them -> hopes tomorrow's task runs.
```

---

## 5. Reality of “learning” and adaptation

The system can improve over time, but not by allowing the model to rewrite its own rules.

Real feedback mechanisms are:

- accepted/rejected/superseded decision outcomes;
- wrong-owner and wrong-timing feedback;
- completion outcome vs expected outcome;
- newly documented operational context;
- repeated human override patterns;
- policy revisions approved by management.

The planner may propose a new rule/context after repeated evidence. A human or governed deterministic process approves it.

No self-modifying thresholds, permissions, SQL or routing policy.

---

## 6. Realistic rollout boundary

### Phase A — Core without AI dependency

Build:
- `ai_ops` foundation;
- current-state snapshot contracts;
- receivables/credit cases;
- responsibility evidence;
- UI for runs/cases/context/settings;
- deterministic validation;
- no ChatGPT scheduled worker yet.

Pass criteria: EDARA itself consistently produces the right factual cases and ownership evidence.

### Phase B — Interactive Shadow Reasoning

Use ChatGPT interactively against the bounded planner context.

Goal:
- prove decision quality;
- tune case ranking;
- discover missing context fields;
- validate responsibility reasoning;
- create no autonomous Work.

### Phase C — Scheduled Shadow Worker

Use one small number of scheduled ChatGPT worker checks to claim due runs and return analysis.

Important design preference: **one general worker that claims any due/pending run is more robust than separate independent automations for every department/run type.**

A missed execution can then be recovered by the next successful check.

No autonomous business mutation through a broad connector.

### Phase D — Human-approved Work commit

Management reviews staged recommendations in EDARA and explicitly commits selected actions through the system Work bridge.

This proves the whole loop including Work outcomes without granting AI autonomous write authority.

### Phase E — Low-risk autonomous actions only after hardened worker channel

Requirements:
- technically bounded action surface;
- proven idempotency/recovery;
- action allowlist;
- decision confidence/evidence gates;
- maximum actions/run;
- circuit breaker;
- audit and rollback/compensation model;
- successful shadow/human-approval history.

Sensitive financial, HR, legal, access-control and irreversible actions remain human-controlled.

---

## 7. Integration truth by subsystem

| Link | Reality | Decision |
|---|---|---|
| Operational modules -> Analytics | Existing and real | Reuse |
| Analytics/current reports -> AI snapshot | Real, but needs bounded internal kernels/current-state semantics | Build |
| Snapshot -> Cases | Deterministic and real | Build in DB |
| Cases -> AI reasoning | Real through worker adapter | Keep replaceable |
| AI -> Responsibility | AI interprets evidence; DB validates identities/availability | Hybrid |
| AI -> Work | Must go through validated system bridge | Build, disabled for auto initially |
| Work -> notifications | Existing and real | Reuse |
| Work -> outcome feedback | Work events real; business-outcome mapping needs explicit success signals | Build incrementally |
| DB -> personal Scheduled Task trigger | Not a guaranteed durable trigger | Do not depend on it |
| Scheduled Task -> recovery | Best-effort; next run can recover persisted work | Support, do not overclaim |
| Current broad Supabase app -> unattended auto write | Technically too broad for desired least privilege | Block production auto-write |

---

## 8. Scope discipline — what we deliberately postpone

Do not build in the first implementation:

- general-purpose AI access to arbitrary SQL;
- cross-company autonomous manager logic;
- hidden employee scoring;
- full time-sheet/capacity optimization;
- automatic policy learning;
- AI financial/HR/legal mutations;
- dozens of domain case types;
- custom routing DSL before real cases prove it is needed;
- automatic pricing/credit changes;
- multiple scheduled ChatGPT tasks per employee.

The first real vertical slice is **Receivables/Credit -> causal responsibility -> decision -> human review -> optional Work commit -> outcome**.

---

## 9. First vertical slice acceptance test

A production-realistic pilot is successful only when all of the following are demonstrated with real-like fixtures/local database:

1. overdue exposure is detected from trusted current data;
2. the same condition retains a stable case key across runs;
3. responsibility evidence differentiates assigned rep, order rep, creator, credit override actor and due-date decision actor;
4. explicit human context can suppress/defer the case;
5. existing equivalent Work prevents duplication;
6. AI may choose no action/monitor/investigate;
7. staged recommendation explains why this owner and why now;
8. human can accept/reject/edit without losing audit trail;
9. accepted recommendation creates exactly one system-origin Work item through the bridge;
10. retry after partial failure creates no duplicate;
11. completion alone is not treated as success unless the expected business outcome is observed/recorded;
12. missed AI worker execution remains visible as a missed/pending run rather than disappearing.

If this slice is not reliable, expansion to Sales/Inventory/Visits is blocked.

---

## 10. Implementation go/no-go

**GO now:** build the EDARA-side foundation, first current-state/case slice, control UI and Shadow/Human-review loop.

**NO-GO now:** autonomous production writes from a personal scheduled ChatGPT worker through the current broad Supabase connector.

This is not a limitation of the business idea. It is a deliberate separation between a sound planner core and the current worker-channel security/reliability characteristics.
