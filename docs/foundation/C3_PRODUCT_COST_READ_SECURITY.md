# Product cost read checkpoint

Status: saved work, not a release-qualified baseline. Parent: 6c36e320cf7b88908424a48e02d7635c0b4f7041.

The migration removes table-wide product SELECT and protects cost_price and last_purchase_price. Existing financial metrics remain behind finance.view_costs; write grants, RLS and function bodies are preserved. Product create/update now return the same 15 nonfinancial fields as existing reads. The verification-only SQL copies five exact statements from source migration 84 for the owned synthetic environment; it is not a production migration replay.

Actual Auth/PostgREST and product service checks passed with 29 HTTP responses, including restricted reads/writes, explicit deny, expired grants and authorized costs. All 48 public table fixtures were restored. ACL rollback, idempotence and source hashes passed. Direct Claude production and test-delta reviews passed.

Type checking, lint and production build passed. The isolated Visit suite passed 35 tests. Both full-suite attempts passed 1073/1074 tests. The first failed a fixed 50ms restoration wait; that wait now observes the same assertions with waitFor. The corrected full run failed a different existing temporary-session assertion at useVisitExecutionSession.test.ts:451. This remains open; no further retry or test weakening was performed.

## Restart checkpoint

The user requested a safe stop for a device restart. Preserve this branch on GitHub and pause. A private local database archive is retained outside Git; it contains synthetic Auth data and is deliberately not committed. Stop only the four owned edara-c3-compose-20261011 services, preserving their Docker volumes.

After resuming: inspect this checkpoint and exact SHA; diagnose the remaining Visit test before release qualification. Then continue the finite baseline plan: actual App/forms, unified performance/offline/update checks, Realtime and restore gates, and final review. Verify published backend compatibility before applying any migration. No main/DS2 merge or production deployment is authorized by this checkpoint.

## Resumed qualification — 2026-10-11

The remaining temporary pending-start scenario also used a fixed 50ms sleep while the real IndexedDB restoration awaited multiple operations. Only that wait now uses default waitFor around its unchanged not-null assertion. No production hook, fixture, mock, timeout or scheduler changes were made. Direct Claude read-only review passed with readOnlyViolation=false. Focused tests:35 PASS; corrected full suite:141 files/1074 tests PASS; type and lint PASS. The previous production build remains applicable because the subsequent source delta is test-only. Earlier failures remain documented as historical evidence.

Status is now PASS for this bounded product cost HTTP/API slice. It does not accept the full baseline. Owned Docker services were restarted after validating their project labels. Continue published-backend compatibility preflight and the written unified App/performance/offline/Realtime/restore gates; no deployment or production mutation.
