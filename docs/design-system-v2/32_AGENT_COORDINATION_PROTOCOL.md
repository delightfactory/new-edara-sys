# 32 — Agent Coordination Protocol (Claude ↔ Codex)

Two AI agents work on the V2 program for the same owner. They cannot message each other directly and do not run at the same time, so **the repository and GitHub are the only shared channel**. Anything not written here, in a PR, or in tracking issue #6 does not exist for the other agent.

## Roles (default — the owner can reassign any slice)
| Area | Owner | Other agent |
|---|---|---|
| Visual direction, token values, board updates (`31`, `visual-concept/`) | Claude | Reviews for feasibility against the code |
| Program docs `01–30`, epics, PR slicing (`18`) | Codex | Reviews against the visual direction |
| Implementation PRs | Codex by default | Claude reviews; implements only slices the owner assigns to Claude |
| Runtime visual audit (`08`, `19`) | Whoever the owner gives a running environment to | — |
| Decisions D1–D5 in `31` and any scope question | **Owner** | Agents propose; never decide alone |

## Rules
1. **One owner per slice at a time.** Before starting a slice, claim it in the Slice board below in the same commit/PR. Do not edit files another open slice claims.
2. **The no-functional-change contract in `06` binds both agents.** A visual PR never touches DB/RPC, calculations, workflow states, RBAC/RLS or data contracts.
3. **Existing architecture wins over the concept where they conflict**, unless the owner approves a change in the Decision log. The concept supplies values and composition, not new architecture.
4. **Disagreements are written down, not acted on.** Add an entry under Open questions with both positions; the owner resolves it.
5. **Do not rewrite the other agent's documents.** Add a dated note or open a question instead. Fixing an obvious factual error is fine if noted in the commit message.
6. **Every claim about the system cites a file path.** Every visual value cites a token.
7. Branches: Claude works on `ccr-*` branches, Codex on its own branches; each opens its own PRs. Neither pushes to the other's branch.

## How to hand work across
- **Async notes:** append to *Handoff log* below (newest first) with date, author, what changed, what the other agent should do next.
- **PR review:** the author lists "Review requested: Claude" or "Review requested: Codex" in the PR description. The owner tells the reviewer the PR number (Claude can then watch the PR and answer review threads directly).
- **Questions:** add to *Open questions* with an ID (`Q-###`). Answers go inline under the question with author and date.

## Slice board
| Slice | Owner | Status | Branch / PR |
|---|---|---|---|
| Visual concept boards + `31` | Claude | Done — awaiting owner review | `ccr-6dd02f22-t7y7ay` |
| Epic 0 — runtime baseline | Unassigned | Blocked (needs running env + roles) | — |
| Epic 1A — apply proposed values to physical tokens behind a flag | Unassigned | Waiting on D1, D2, D5 | — |

## Decision log
| ID | Decision | Decided by | Date |
|---|---|---|---|
| — | (none yet) | | |

## Open questions
- **Q-001 (Claude → Codex):** `04` sketches a 7-group IA; `registry.ts` implements 8 `NavigationGroupId`s and the concept's module rail uses those 8. Is the 7-group IA still the target, or is the registry grouping now authoritative?
- **Q-002 (Claude → Codex):** For tenant branding, do you prefer boot-time CSS variables from `company_settings` (concept proposal) or a build-time theme? Either way the key additions are a separate functional PR.
- **Q-003 (Claude → owner/Codex):** Are there label maps for transfer/adjustment/expense/visit-plan/HR statuses that the concept missed? The `SystemMap` labels for those were authored, not copied.

## Handoff log
- **2026-10-24 — Claude:** Added `31_VISUAL_DIRECTION_CONCEPT.md`, `visual-concept/` board sources, and this protocol. The concept maps proposed values onto the existing `--ds-*` aliases and keeps the registry/sidebar model. Next for Codex: read `31`, answer Q-001–Q-003, and flag anything in the boards that contradicts the code or the epics in `18`. Next for owner: decide D1–D5 in `31`.
