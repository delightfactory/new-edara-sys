# 31 — Development and Manual Preview Workflow

## Integration branch

All Design System V2 / UI Refactor work continues on the long-lived branch:

`design-system-v2-development`

`main` is frozen for this workstream until the UI refactor reaches the agreed completion gate.

## Feature work

1. Create a small feature branch from `design-system-v2-development`.
2. Keep the no-functional-change contract unless a separately approved functional change is explicitly scoped.
3. Review the diff and focused tests.
4. Merge the feature branch into `design-system-v2-development`, not `main`.
5. Do not create a Vercel deployment for normal development commits.

## Manual preview only

When a visual review is requested:

1. Create a temporary preview branch from the current `design-system-v2-development` head.
2. Enable any preview-only feature flags required for visual inspection.
3. Enable Vercel Git deployment only on that temporary preview branch.
4. Push one preview-trigger commit.
5. Use the resulting Preview URL for Desktop / Tablet / Mobile review.
6. Do not continue development on the preview branch.

This ensures normal development commits do not consume Vercel deployment quota.

## Final release

Only after the full UI-refactor acceptance gate passes will `design-system-v2-development` be proposed for merge into `main` as a controlled release PR.
