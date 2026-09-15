# 33 — Test and Validation Policy During GitHub Actions Quota Freeze

## Status

GitHub Actions / hosted CI is intentionally unavailable to the Design System V2 agent workstream until the owner explicitly lifts this restriction.

This is a cost/quota governance decision, not permission to lower the quality bar.

## Absolute rule

Design System agents MUST NOT:

- trigger GitHub Actions intentionally
- rerun a failed or canceled GitHub Actions workflow
- use workflow dispatch
- change workflow triggers to make development PRs run CI
- create temporary CI workflows
- use GitHub Actions as a substitute for local/static review
- merge a PR because a previous unrelated workflow happened to be green

The development branch workflow configuration additionally restricts Work Management PR CI to base `main`, so PRs targeting `design-system-v2-development` do not consume Actions quota.

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

This is sufficient for controlled merge into `design-system-v2-development` when all other development gates pass.

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

### `MANUAL_PREVIEW_BUILD_PASS`

May only be claimed after the owner explicitly asks for a preview and the dedicated preview branch completes a Vercel build successfully for the frozen development baseline.

The preview build can reveal integration/type/build failures and is a milestone gate, not a per-commit test mechanism.

### `RUNTIME_VISUAL_PASS`

Requires actual visual/runtime inspection on representative devices/viewports and relevant flows. A source review or successful build is not sufficient.

## Development merge gate

A UI PR may merge into `design-system-v2-development` without hosted CI only when all of the following are true:

1. exact-head `SOURCE_REVIEW_PASS`
2. scope and functional-isolation gates pass
3. tests are authored for material risks, or reviewer records why no new test is necessary
4. no known build/type failure is outstanding
5. no unresolved material review blocker exists
6. the PR does not target `main`

The reviewer marker for this state is:

`AGENT-REVIEW: GREEN-DEV`

This means safe enough to integrate into the isolated development workstream. It does not mean release-ready.

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
