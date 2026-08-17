# AI Operations — Build-All-Domains Acceptance Strategy

**Status:** authoritative execution strategy for the current development cycle  
**Branch:** `feature/work-management`  
**Production:** untouched  
**Supersedes:** any earlier instruction that isolated/local DB runtime acceptance for Sales must block development of the next AI Operations domain.

## 1. Decision

AI Operations will now be developed as one integrated Operational Intelligence Engine before the final local database acceptance sweep.

The domain sequence remains:

1. Receivables / Credit — existing first slice
2. Sales & Targets
3. Customer Health / Re-engagement
4. Inventory
5. Visits / Field Execution
6. Work Health
7. HR / Availability

The engine is not considered production-ready merely because all domain code exists. The expensive database/runtime acceptance is intentionally deferred until the domain set and cross-domain orchestration are complete.

## 2. What is deferred

Deferred until the complete domain build is ready:

- applying the full AI Operations migration chain to the local isolated database;
- end-to-end snapshot/runtime execution against realistic local data;
- mixed-domain worker runs with real database state transitions;
- human review + reviewed Work commit runtime scenarios;
- mutation-between-review-and-commit runtime scenarios;
- final full-engine operational acceptance.

This is a testing-sequence decision only. It is not permission to weaken runtime safety contracts or omit required layers.

## 3. What is NOT deferred

Every domain increment must still pass cheap, repeatable gates before the next domain starts:

### A. Static architecture review

Verify:

- correct source of truth;
- no prohibited operational mutation in detection/snapshot/reasoning paths;
- immutable snapshot/evidence behavior;
- bounded context and deterministic ordering;
- no duplicate parallel AI subsystem;
- domain adapter fits the shared Case -> Decision -> Validation -> Review -> Work lifecycle;
- current-state drift is checked before consequential execution;
- explicit Work owner/assignee/deadline requirements remain intact;
- normal API/browser roles do not gain internal AI execution access.

### B. Contract tests

Add/maintain tests for:

- SQL migration contracts;
- read-only boundaries;
- grants/revokes;
- cardinality and global case/action budgets;
- stale/fresh evidence semantics;
- responsibility/routing evidence;
- Work collision/idempotency behavior;
- TypeScript worker/UI contracts where applicable.

### C. Repository CI

The current branch must continue to pass:

- clean dependency install;
- full test suite;
- TypeScript type-check;
- production build;
- Windows clean install job.

A previous successful run never substitutes for a run on the current HEAD.

### D. Review findings are fixed immediately

A credible logic/security/contract defect discovered during static review is fixed in the responsible domain or shared orchestration layer before moving on. It is not parked merely because local runtime testing is deferred.

## 4. Integration principle

All domains must converge on the same lifecycle:

```text
Evidence
  -> deterministic detection
  -> immutable Case snapshot
  -> bounded multi-domain reasoning context
  -> one disposition per frozen Case
  -> current-state validation
  -> human review
  -> reviewed operational execution
  -> Work / source entity linkage
  -> outcome capture
```

No domain should create a private copy of the worker, review or Work execution architecture when the shared engine can be extended safely.

## 5. Cross-domain feasibility requirement

Before final acceptance, the shared engine must evaluate recommendations against operational feasibility, not only domain severity.

The final reasoning/validation model must consider at least:

- employee availability and workload;
- existing Work assignments/deadlines;
- visits and route commitments;
- inventory/product availability where relevant;
- customer receivables/credit restrictions;
- target gaps and commercial impact;
- dependencies and approvals;
- duplicate/conflicting recommendations;
- evidence freshness and trust;
- permissions and accountable ownership.

A recommendation that cannot realistically be executed must not become operational Work merely because its underlying domain Case is severe.

## 6. Final local acceptance sweep

After all domains and shared orchestration layers are implemented, perform one integrated local acceptance cycle:

1. apply the complete migration chain to the isolated local database;
2. seed/use realistic cross-domain operational data;
3. verify deterministic domain candidates independently;
4. capture one multi-domain immutable snapshot;
5. verify global case budget, ranks, bytes and domain coverage;
6. generate/parse one worker context containing all supported domains;
7. stage exactly one decision per frozen case;
8. validate fresh vs stale evidence behavior;
9. verify responsibility and feasibility conflicts across domains;
10. exercise human Approve / Reject / Snooze / Dismiss paths;
11. create reviewed Work only where permitted;
12. verify exact source links, employee-safe text and no management-rationale leakage;
13. retry commits and prove idempotency/no duplicate Work;
14. change source state between snapshot/review/commit and prove fail-closed behavior;
15. execute Work/outcome scenarios and rerun the engine;
16. prove Cases close, persist, reprioritize or reappear according to actual outcomes;
17. rerun full repository CI and final architecture/security review.

## 7. Release gate

No merge to production and no production database migration is authorized by this strategy.

Release remains blocked until:

- all intended domains are implemented;
- shared cross-domain orchestration is complete;
- final local runtime acceptance passes;
- repository CI passes on the final HEAD;
- final technical/security review has no unresolved blocking findings.
