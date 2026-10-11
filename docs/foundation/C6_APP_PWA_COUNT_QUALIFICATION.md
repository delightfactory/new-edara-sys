# C6 — Actual App PWA, count isolation and local timing samples

The current App, Auth/login, protected product form and installed Service Worker passed on the owned loopback Auth/PostgREST platform. No production mutation or deployment occurred. Overall baseline acceptance remains open, especially Realtime and final exact-candidate review.

## Scope and evidence

Ten exact statements from original source42 completed only the count dependency. Source bytes/hashes are in C6_APP_PWA_COUNT_EVIDENCE.json and baseline_notification_count_dependency.sql. Absent objects and dry-run ROLLBACK were verified before application; all existing48 table rows, functions, ACLs and policies were preserved. The platform now has50 public tables; the historical48-table restore is not a50-table restore proof.

Actual SDK tests proved own manager2/restricted1 counts with read/archived/expired rows excluded. Anonymous arbitrary-user count2 exposed a concrete source42 gap locally. Read-only production catalog confirms the same original function predicates and PUBLIC/anon EXECUTE grants; no production notification rows or RPC were read/called. This is metadata compatibility, not production exploitation testing.

Standalone migration20261011100000_notification_count_access_hardening.sql adds caller identity to the original count predicates and removes PUBLIC/anon EXECUTE. Trusted service_role arbitrary-user counts remain. Authenticated cross-user calls return0. Signature/default/result/STABLE/SECURITY DEFINER/search_path, table ACL/RLS/policies, other functions and business filters are preserved. Body/owner/ACL rollback and one idempotence apply PASS. Real API13 requests PASS: own/default/explicit count, both cross-user0, anonymous42501, service-role2/1. All seeded notifications removed. No broader notification mutation/push/security acceptance is claimed.

Claude fixture review2e78bf5a-b259-4916-8a81-e0e5d6c6af65 GO after one final-answer resume. Security discussion first reached turn limit; a no-tools response initially requested source without verdict. A complete in-brief contract yielded GO in sessionda2c7d4a-21a4-4caa-9867-f412695acd41 with service-role verification required; actual server-key counts passed. These are contract reviews, not executed reviewer tests or final artifact approval.

## Actual PWA

Using the already-built identical frontend sources with real Auth/API and SW enabled: real login, controlling SW,3 warm form reloads, offline authenticated form shell reload, reconnect, frontend-only cache284 entries, and explicit update all PASS. No private Auth/REST responses were in SW caches. A byte-distinct SW with only an appended qualification comment waited for the UI update action, then exactly1 navigation preserved the product route. This tests the actual same-assets update lifecycle; new-build asset compatibility, offline business data/write availability and Realtime are not certified.19 observed HTTP requests, no pageerror or unexpected external dependencies.50-table row cleanup parity PASS; Auth session metadata is not byte-restored.

## Finite timings

Three fresh-context cold boots copied only the same synthetic authenticated browser state, then compared SW-controlled warm reloads of the same form build/role/data/viewport. A first diagnostic run did not observe the extra contexts' requests; retained outside Git as first-report evidence, not used as final HTTP coverage. One corrected final run observes all contexts and reruns after the count migration:29 HTTP requests, zero API HTTP errors/pageerrors/external requests, and50-table cleanup parity. Exact samples are in JSON. First/repeat customer route timings end at visible heading and use document navigation, not SPA-click or completed table-data timing.

No production performance percentage, prior-version before/after comparison or universal latency target is inferred. Older synthetic C4 before/after evidence remains separately scoped. No application TypeScript changed in this slice; last full suite141 files/1074, type/lint/build evidence remains historical at its recorded source identities. Final integration checks are still required before candidate approval.

Next bounded gates: distinguish live Realtime server delivery from SDK dispatch using new instrumentation, then updated50-table restore, exact-source final gates/review and candidate handoff. No repeat of the earlier unchanged Realtime experiment.

Final artifact review: Claude Code fc37472c-bcba-45c3-a6fc-5e18ca639206 PASS for this slice, exit0/readOnlyViolation=false; three named artifacts reviewed, no reviewer-executed tests. HTTP anonymous denial was401 in the actual API evidence with PostgreSQL42501; no reliance on the discussion's predicted403 status.
