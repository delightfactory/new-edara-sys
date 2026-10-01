# 33 — Test and Validation Policy During GitHub Actions Quota Freeze

## Status

Normal Design System V2 development remains under the hosted-CI quota freeze.
On 2026-10-01 the owner authorized one narrow exception: explicit final-candidate
validation via `pull_request: ready_for_review` targeting Development. Follow
`.github/FINAL_CANDIDATE_CI.md`; scheduled agents must keep PRs draft and may not
request this transition without owner final-candidate authorization. This
exception supersedes the blanket prohibitions below only for the frozen final
candidate. It does not authorize dispatch, normal push/synchronize execution,
deployment, or any change/merge to `main`.

Before final-candidate integration, require successful hosted evidence on the
exact unchanged head and base in addition to the source-review gates. A newer
head/base invalidates acceptance and needs a fresh authorized ready transition.

This is a cost/quota governance decision, not permission to lower the quality bar.

## Normal development and retry restrictions

Design System agents MUST NOT:

- trigger GitHub Actions during normal development; only an explicitly owner-authorized final-candidate ready transition is permitted
- rerun a failed or canceled GitHub Actions workflow without separate explicit owner authorization
- use workflow dispatch
- change workflow triggers to make opened, push or synchronize events run CI
- create temporary CI workflows
- use GitHub Actions as a substitute for local/static review
- merge a PR because a previous unrelated workflow happened to be green

The development workflow now runs only for the explicit ready transition on
`design-system-v2-development`; opened/push/synchronize events do not run it.
The unchanged default-branch workflow still has automatic main-targeted PR and
`feature/work-management` push behavior outside this authorized branch scope.

## Test authoring is still mandatory

CI execution and test authoring are different concerns.

Agents must continue to add focused test artifacts when a UI migration puts behavior or composition at risk.

Examples:

- device-specific renderer selection
- permission visibility
- preserved primary actions
- form submit wiring
- status mapping
- state/empty/loading composition
- navigation/action registry invariants

Never delete, weaken or bypass a test merely because it cannot currently be executed in GitHub Actions.

## Evidence labels

Every reviewed slice must distinguish evidence accurately.

### `SOURCE_REVIEW_PASS`

Means the reviewer inspected the exact HEAD and found no material source-level blocker in scope, contracts, TypeScript reasoning, permissions, state coverage, responsive composition or test intent.

This passes the source-review gate for a draft candidate. It is not sufficient
for merge: integration also requires the owner-authorized final-candidate run
and successful evidence for the unchanged current head and base.

It is NOT equivalent to an executed build or test suite.

### `TESTS_AUTHORED_NOT_EXECUTED`

Use when focused tests exist but no approved execution environment ran them.

This is expected during normal autonomous development under the quota freeze.

### `LOCAL_EXECUTION_PASS`

May only be claimed when an agent actually has an approved local/sandbox runtime and records the exact command, exact HEAD and result.

Typical project commands are:

- `npm test`
- `npm run build`
- `npm run lint`

Do not claim this evidence from source inspection alone.

### `FINAL_CANDIDATE_CI_PASS`

Requires an actual successful `pull_request: ready_for_review` run of all existing
jobs on the exact frozen candidate. Record the run URL/ID, candidate head, base
and tested merge snapshot from the guard summaries. It does not imply visual,
preview or release acceptance. Missing, skipped, failed or stale checks do not
qualify; a head/base change requires a fresh authorized candidate transition.

### `MANUAL_PREVIEW_BUILD_PASS`

May only be claimed after the owner explicitly asks for a preview and the dedicated preview branch completes a Vercel build successfully for the frozen development baseline.

The preview build can reveal integration/type/build failures and is a milestone gate, not a per-commit test mechanism.

### `RUNTIME_VISUAL_PASS`

Requires actual visual/runtime inspection on representative devices/viewports and relevant flows. A source review or successful build is not sufficient.

## Development merge gate

A UI PR may integrate into `design-system-v2-development` only when all of the following are true:

1. exact-head `SOURCE_REVIEW_PASS`
2. scope and functional-isolation gates pass
3. tests are authored for material risks, or reviewer records why no new test is necessary
4. no known build/type failure is outstanding
5. no unresolved material review blocker exists
6. the PR does not target `main`
7. the owner explicitly authorizes the frozen final-candidate ready transition
8. all existing jobs succeed on the unchanged candidate with `FINAL_CANDIDATE_CI_PASS`
9. immediately before merge, the reviewed head and tested base remain current; use expected-head merge protection and serialize the base recheck/integration

The reviewer marker for this state is:

`AGENT-REVIEW: GREEN-DEV`

This means the exact head passes source review. It does not authorize integration
by itself, establish an executed PASS, or mean release-ready. The final-candidate
CI and owner authorization gates above remain mandatory. A current owner
instruction forbidding merge always takes precedence.

## Build failure behavior

If any approved manual preview/local build exposes a failure:

- it becomes a blocker for the development baseline
- fix it on `design-system-v2-development` or an appropriate feature PR
- do not hide the failure by removing checks or loosening TypeScript
- do not continue claiming the affected baseline is build-clean

## Manual preview gate

Preview is created only when the owner requests to see the current version.

At that point:

1. freeze exact development HEAD
2. create/update isolated preview branch
3. apply preview-only feature flags there
4. permit the minimum deployment trigger necessary
5. run one preview build
6. inspect build result
7. fix material build blockers on development, not only on preview
8. retry only when needed
9. share URL only after READY/200 validation
10. never merge preview-only switches/deployment config back into development

## Main/release gate

No Design System V2 work is merged from development to `main` merely because the autonomous loop has completed pages.

Before final rollout to `main`, require a deliberate release review that includes at minimum:

- build/type-check PASS on the candidate baseline using an approved non-quota-wasting execution route
- relevant automated tests executed successfully where feasible
- representative runtime visual review
- Mobile/Tablet/Desktop golden flows
- RTL and long Arabic-content review
- loading/empty/error/permission states
- no functional-isolation violations
- no open P0/P1 Design System blocker

The user controls this final rollout decision.

## Why this model is safe

Normal autonomous development emphasizes:

- small slices
- focused test authoring
- independent source review
- isolated development branch
- no production/main impact

Execution-heavy gates are concentrated at intentional milestones rather than paid hosted CI on every agent commit.
