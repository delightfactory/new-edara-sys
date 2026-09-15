# Design System V2 — Decision Log

Use this file only for durable decisions future agents must preserve unless explicitly superseded.

## DS2-DEC-001 — Mobile-primary multi-device strategy
- **Date:** 2026-09-15
- **Decision:** Mobile is the primary daily operational surface; Tablet is a deliberate hybrid mode; Desktop is optimized for dense management/review workflows.
- **Reason:** Actual EDARA usage is multi-device with most daily operational work performed on mobile.
- **Affected area:** layout, navigation, controls, lists, forms, task screens.
- **Owner:** Product Design Director / project owner direction.
- **Status:** ACTIVE

## DS2-DEC-002 — Canonical device boundaries
- **Date:** 2026-09-15
- **Decision:** Mobile `<=768px`, Tablet `769–1024px`, Desktop `>=1025px` for the Design System V2 device-mode contract.
- **Reason:** Existing binary mobile/desktop behavior made Tablet a compressed desktop. V2 requires an explicit intermediate composition.
- **Affected area:** App Shell and responsive patterns.
- **Owner:** Product Design Director.
- **Status:** ACTIVE

## DS2-DEC-003 — Development branch isolation
- **Date:** 2026-09-15
- **Decision:** All Design System implementation integrates into `design-system-v2-development`; `main` remains frozen until explicit owner approval of final rollout.
- **Reason:** Permit continuous autonomous UI development without destabilizing the production/default branch.
- **Affected area:** branching, PRs, merges.
- **Owner:** Project owner.
- **Status:** ACTIVE

## DS2-DEC-004 — Manual preview only
- **Date:** 2026-09-15
- **Decision:** Vercel preview is created only when the user explicitly asks to inspect the current version. Normal development must not auto-deploy.
- **Reason:** Preserve deployment quota and make runtime visual validation a deliberate evidence gate.
- **Affected area:** Vercel / preview branches.
- **Owner:** Project owner.
- **Status:** ACTIVE

## DS2-DEC-005 — Hosted CI quota protection
- **Date:** 2026-09-15
- **Decision:** Design System development agents must not trigger/rerun GitHub Actions or rely on hosted CI. Development PR workflow execution is prevented by branch targeting policy; tests are still authored and evidence is labeled honestly.
- **Reason:** GitHub Actions quota has been exceeded/exhausted; uncontrolled CI would halt useful work without adding proportional value.
- **Affected area:** testing, review, workflow configuration.
- **Owner:** Project owner / Design System governance.
- **Status:** ACTIVE

## DS2-DEC-006 — UI-only functional isolation
- **Date:** 2026-09-15
- **Decision:** Design System V2 PRs must not change DB/RPC/service contracts, RBAC/RLS, permissions, business calculations, workflow semantics, query/cache semantics, or validation meaning.
- **Reason:** The project is a UI/UX refactor of a functioning product; functional defects are separate workstreams.
- **Affected area:** all V2 implementation slices.
- **Owner:** Design System governance.
- **Status:** ACTIVE

## DS2-DEC-007 — Shared system before page-local invention
- **Date:** 2026-09-15
- **Decision:** When a recurring UI need is proven by a migrated screen, strengthen or add the shared V2 primitive/pattern before creating a page-local mini design system.
- **Reason:** Final goal is one deep product language across all EDARA modules.
- **Affected area:** components, patterns, page migration.
- **Owner:** Product Design Director.
- **Status:** ACTIVE

## DS2-DEC-008 — Repository-native agent team memory
- **Date:** 2026-09-15
- **Decision:** All scheduled Design System agents read the shared Team Memory and every role state at the start of each run. Each role owns its own current-state file and communicates cross-role handoffs there. Issue #27 remains the concise chronological event stream.
- **Reason:** Enable autonomous agents to behave as one informed team rather than isolated scheduled jobs, following the proven Garment Ops operating pattern.
- **Affected area:** autonomous workstream communication and handoffs.
- **Owner:** Project owner / Product Design Director.
- **Status:** ACTIVE
