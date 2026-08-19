# AI Operations — Credit Slice Implementation Delta

**Status:** branch implementation artifacts only — no database migration applied  
**Branch:** `feature/work-management`  
**Purpose:** record implementation-time corrections that supersede narrower assumptions in the earlier design documents.

## 1. Current implementation boundary

The first closed-loop slice is deliberately limited to **Receivables / overdue credit invoices**.

Implemented on the branch as reviewable artifacts:

- isolated `ai_ops` foundation migration design;
- immutable snapshot-case evidence design;
- overdue-credit candidate/case engine design;
- atomic snapshot builder design;
- management-only read gateway design;
- TypeScript service/data contracts;
- database-free Preview adapter and fixtures;
- AI Operations management UI preview;
- contract tests for isolation/security/idempotency/evidence semantics.

Not implemented or enabled in production:

- no `ai_ops` schema in production;
- no migration applied;
- no planner schedule/cron;
- no ChatGPT worker gateway;
- no staged-decision writer;
- no Work auto-creation bridge;
- no autonomous write permission;
- no production AI Operations UI data connection.

## 2. Catalog-driven correction: Work links already exist

Early exploratory reasoning used the provisional name `work_entity_links`. Full catalog discovery confirmed the deployed capability already exists as:

```text
public.work_links
```

with existing link RPC/UI support and an entity lookup index.

Therefore the AI slice **reuses `work_links`** for exact invoice collision detection and creates no competing link table.

This is a permanent implementation rule: object gaps are established from the catalog/repo, not from expected object names.

## 3. New invariant: Current Case is not historical evidence

A material implementation-time gap was discovered in the original snapshot model.

`ai_ops.cases` is intentionally mutable current state:

- `last_snapshot_id` advances;
- current facts/evidence are refreshed;
- status can evolve;
- a stable `case_key` survives across runs.

Therefore `ai_ops.cases` alone cannot prove what evidence a historical AI run actually saw.

### Corrected model

```text
ai_ops.cases
  = current materialized attention state

ai_ops.snapshot_cases
  = immutable, ranked evidence frozen for a specific snapshot/run
```

`ai_ops.snapshot_cases` stores:

- snapshot/case identity;
- snapshot rank;
- domain/case/entity identity;
- severity/status at capture;
- source timestamp;
- exact bounded facts;
- exact responsibility evidence;
- trust envelope;
- serialized evidence byte size.

Rows are immutable using the same update/delete rejection guard as snapshots.

### Consequence

Management review and future AI context must read historical evidence from `snapshot_cases`, not from the mutable `cases.facts` columns.

This is required for replay, audit, debugging, human override review and evidence-quality measurement.

## 4. Credit source semantics are anchored to deployed logic

The deployed `public.get_overdue_sales_invoices(...)` definition was inspected directly.

The AI candidate kernel preserves its factual semantics:

- delivered / partially delivered orders only;
- credit / mixed payment terms;
- delivered date exists;
- due date exists and is before business date;
- positive `max(0, total - paid - returned)` balance;
- 7 / 30 / 60-day overdue buckets.

The intentional difference is date handling:

```text
existing report: CURRENT_DATE
AI slice: durable planner run.business_date (Africa/Cairo business date)
```

This makes replay deterministic and removes the UTC-midnight ambiguity.

## 5. Causal responsibility evidence is richer than assignment

The first kernel returns evidence separately rather than deciding an owner in SQL:

```text
current customer rep
order rep
order creator
credit override actor
latest customer credit-limit change actor + before/after + reason
latest invoice due-date change actor + reason
exact active Work linked to the sales order
```

The UI explicitly grades evidence as:

- direct;
- supporting;
- contextual.

For example, a current sales rep is a strong relationship signal but does not override direct evidence that management explicitly approved credit or changed the due date.

SQL generates **evidence**, not blame and not a rigid routing rule.

## 6. Human text is bounded untrusted data

Governed `reason` fields can be valuable business context but are still user-entered content.

For the Credit slice:

- only specific governed reason fields are included;
- each reason is truncated to 500 characters;
- the evidence marks it `untrusted_human_text`;
- arbitrary customer notes/comments are excluded from normal context;
- future AI instructions must treat the text as evidence, never as executable instructions.

This is part of the prompt-injection boundary.

## 7. Snapshot building is atomic and retry-safe

`ai_ops.build_credit_snapshot(run_id, limit)` is designed to:

1. serialize concurrent builders for the same run with a transaction advisory lock;
2. return an already-existing snapshot before reading operational sources again;
3. allow new build only for valid run states;
4. use the durable Cairo `business_date`;
5. calculate compact aggregate pulse/coverage;
6. apply a case-explosion circuit breaker;
7. insert the immutable snapshot;
8. capture/update current cases and freeze `snapshot_cases` in the same transaction path.

If evidence capture fails, the snapshot insert rolls back with the function transaction.

`refresh_credit_cases()` itself is single-shot per snapshot. Retry is performed through the idempotent builder, not by recapturing evidence into an existing immutable snapshot.

## 8. Context/resource budget is measured, not guessed

The implementation separates serialized size into:

```text
snapshots.payload_bytes
  = compact snapshot/header envelope

snapshot_cases.payload_bytes
  = each frozen case evidence envelope

estimated_context_bytes
  = header bytes + sum(case evidence bytes)
```

This allows a future worker gateway to reject or reduce an oversized context **before** handing it to an LLM.

The normal case count remains bounded by `max_cases_per_snapshot`; aggregate coverage records omitted cases rather than shipping them all.

## 9. Trust semantics remain conservative

The overdue balance is a current operational calculation. It is not automatically promoted to accounting truth.

The builder reads the internal Analytics AR trust signal as supporting health evidence, but the first Receivables domain remains classified as `partial` from the AI decision perspective because:

- the overdue figure is operational current-state;
- Analytics AR freshness helps detect trust degradation;
- neither should be presented to the AI as a final accounting close without separate reconciliation semantics.

Missing/stale Analytics trust fails conservatively and must not produce a misleading healthy note.

## 10. Management UI and worker security are separate contracts

The management UI read gateway is intentionally distinct from any future AI worker gateway.

Management read RPCs:

```text
public.ai_ops_get_console_snapshot()
public.ai_ops_get_case_detail(case_id)
```

They follow the existing Work-management security pattern:

- authenticated user;
- active Work actor;
- `work.policies.manage` permission;
- `SECURITY DEFINER` with fixed `search_path`;
- no anon execution;
- read-only;
- no direct table grants on `ai_ops`.

The future worker must not reuse this browser/admin surface as its autonomous execution security boundary.

## 11. UI Preview remains database-free

The AI Operations management tab is hidden by default.

Preview requires:

```text
VITE_AI_OPERATIONS_PREVIEW=true
VITE_AI_OPERATIONS_DATA_MODE=preview
```

In Preview mode:

- fixtures are deterministic synthetic data;
- no AI Operations Supabase RPC is called;
- case details are loaded lazily from local fixtures;
- the UI clearly labels the data as review-only;
- no migration needs to exist.

The future RPC adapter already uses the same typed UI contract but runtime-validates all responses with Zod and fails closed on malformed payloads.

## 12. Gate before any database application

Before any of these SQL files can be considered executable migration candidates:

1. re-run live catalog/schema discovery at that future date;
2. check schema drift against every referenced object/function/enum/index;
3. compile/apply the full migration chain in an isolated Supabase/Postgres environment;
4. run pgTAP/contract/security tests;
5. run `EXPLAIN (ANALYZE, BUFFERS)` on the real candidate/builder queries against representative data;
6. verify lock/statement-timeout behavior and rollback;
7. manually review grants/RLS/function ownership/search paths;
8. smoke-test the UI using the real RPC adapter in the isolated environment;
9. obtain explicit approval before touching production.

Until those gates pass, every SQL file in this slice is a **design-time implementation artifact, not an authorised production migration**.
