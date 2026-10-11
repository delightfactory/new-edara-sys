# Frozen baseline release qualification — 2026-10-12

Disposition: **ISOLATED_LOCAL_RELEASE_CANDIDATE**. User UAT and final independent
release review remain open. Production adoption is not approved or executed.
Application source: `d7fdc527f3dc087f5f0c30b464df31ee481c8483`.

| Gate | Executed result |
|---|---|
| Full exact-source suite | 142 files / 1093 tests PASS; `npm test -- --minWorkers=2 --maxWorkers=2` |
| Lint / types | `npm run lint` and `npx tsc -b` PASS |
| Immutable production-style build | PASS, archived Git source; local qualification API only; atomic visits enabled |
| Ten release SQL files | Source SHA256 verified and separately packaged; production unapplied |
| Fresh production contracts | Read-only capture of 25 existing functions plus affected table/view/column ACLs and migration catalog |
| Contract comparison | Function owners preserved; grant-only bodies unchanged; changed bodies limited to named migrations |
| Actual scoped Realtime SDK | Two authenticated users; permitted update, foreign warehouse suppression with positive control, permission revoke/regrant, no raw cost keys PASS |
| Built application's stock refresh | Synthetic quantity 3→4 visible without reload; after owned Realtime restart, 4→5 visible without reload PASS |
| PWA old→candidate | Old script `index-C1Hu6q19.js`, new `index-Bl5rt-Iw.js`; actual waiting update prompt/manual activation PASS |
| PWA draft protection | Customer-name draft survives “لاحقاً”; activation from second tab preserves original tab/draft PASS; no customer saved |
| Offline shell | New build login shell loads after tab-scoped network disable; networking restored PASS |
| Cleanup / restore rehearsal | Pre-test custom dump restored successfully; all 158 public-table counts/content fingerprints match; synthetic Auth users removed; candidate contracts rechecked PASS |
| User local environment | 5180 and its separate Auth API healthy; its database untouched |
| Claude final package review | NOT EXECUTED: CLI authenticated through api-key helper to Agent Router; provider returned 402 budget quota exhausted |

The first test command supplied only `--maxWorkers=2`; Vitest rejected conflicting
default minimum workers before executing any tests. Setting both min/max workers
corrected the invocation; no test assertions/timeouts or source files were changed.

Browser qualification exposed duplicate upstream/proxy CORS headers and missing
PostgREST profile headers in the local qualification gateway. The owned gateway
now strips upstream CORS duplicates and allows `content-profile`/`accept-profile`.
This is external harness configuration, not an application or production change.
The static server applies `vercel.json` headers with an explicit local-API CSP
addition. TLS, Vercel transport and actual hosted Supabase remain outside this proof.

Production lacks the additive `update_purchase_return_draft` RPC; deploying the UI
without its required database release would be incomplete. Existing function snapshots
are rollback inputs, not a full production backup. The current isolated build contains
loopback configuration and must not be promoted to production.

This closes bounded local Realtime/PWA checks on the latest visits/directions source.
It does not prove the root cause of the historical intermittent Realtime incident,
exhaustive device/offline field behavior, or completion of the full DS2/resale roadmap.
Independent final release review, owner UAT, fresh recoverable production backup,
target-specific deployment smoke and explicit production approval remain separate gates.

See [release and rollback plan](BASELINE_RELEASE_PLAN.md),
[exact SQL manifest](BASELINE_RELEASE_MIGRATIONS.json), and
[sanitized evidence](BASELINE_RELEASE_EVIDENCE.json).
