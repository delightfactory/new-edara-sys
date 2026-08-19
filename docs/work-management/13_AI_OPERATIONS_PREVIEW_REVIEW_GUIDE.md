# AI Operations — Database-Free Preview Review Guide

**Rule:** no `ai_ops` migration is applied to any database during design review.

## What exists on the branch

- design-time SQL files under `supabase/migrations/`;
- verified entity/source maps under `docs/work-management/`;
- TypeScript service adapter under `src/features/ai-operations/`;
- management UI preview under Work Management;
- contract tests that guarantee preview mode performs no AI Operations RPC.

## What does NOT exist in production yet

- no `ai_ops` schema;
- no AI planner tables;
- no AI planner RPCs;
- no AI scheduler/cron;
- no ChatGPT worker integration;
- no automatic Work creation;
- no source-table triggers/indexes added by AI Operations.

## Local UI review without database changes

In local `.env.local`:

```env
VITE_AI_OPERATIONS_PREVIEW=true
VITE_AI_OPERATIONS_DATA_MODE=preview
```

Then open:

```text
Work Management → إدارة العمل → AI Operations
```

The tab is shown only when:

1. `VITE_AI_OPERATIONS_PREVIEW=true`;
2. the signed-in user already has `work.policies.manage`.

The preview adapter returns only `src/features/ai-operations/preview-data.ts` and never invokes Supabase AI Operations RPCs.

The screen itself displays a persistent warning that all numbers/names are review fixtures rather than company data.

## Do not use RPC mode yet

Keep:

```env
VITE_AI_OPERATIONS_DATA_MODE=preview
```

`rpc` mode is intentionally an unready contract until the database layer has completed:

- code review;
- migration review;
- SQL compile/testing in a safe environment;
- security review;
- explicit approval to apply the migrations.

If someone sets `rpc` before the backend is installed, the service converts a missing RPC into an explicit `AI_OPERATIONS_NOT_READY` error instead of silently degrading to guessed data.

## Review checklist

### UX

- mobile layout remains usable at 360–430 px;
- preview warning cannot be mistaken for live company data;
- Pulse is compact rather than a second reporting dashboard;
- Cases clearly communicate `Case ≠ Task`;
- existing Work collision is visible before any recommended action;
- responsibility is presented as evidence, not accusation;
- trust/confidence is visible near the decision surface;
- planner reliability/run health is visible to management;
- operational context has visible lifetime/review semantics.

### Service boundary

- preview performs zero Supabase AI RPC calls;
- RPC names exist only as future adapter contracts;
- no direct table calls to `ai_ops` from the browser;
- no direct Work mutation from the AI console;
- no browser use of service-role credentials.

### Database design

- no migration applied during this phase;
- no source-module trigger introduced;
- no existing report permission weakened;
- no duplicate Work entity-link table introduced;
- no unsupported entity assumed without catalog verification;
- every vertical slice has a live-schema source map before SQL is written.

## Approval gate before any database application

A migration may be considered for application only when all of the following are true:

1. branch CI is green;
2. SQL has been compiled/tested against a safe database clone/local Supabase environment;
3. migrations are reviewed for locks, grants, RLS and rollback/forward-fix behavior;
4. existing production schema is re-discovered immediately before application to detect drift;
5. user explicitly authorizes applying the reviewed migrations.
