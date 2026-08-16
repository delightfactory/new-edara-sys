# Work Management

This directory contains the design baseline, implementation closure notes, release validation material, and planned extensions for the Operational Work Management module.

## Core Work Management

- `01_PRINCIPLES.md` — domain principles and responsibility model.
- `02_DATA_MODEL_SUMMARY.md` — core Work data model.
- `03_RUNTIME_SUMMARY.md` — runtime/state-transition and continuity model.
- `04_SECURITY_SUMMARY.md` — Work security summary.
- `05_AUTOMATION_SUMMARY.md` — deterministic scanners, recurrence and notification automation.
- `06_UX_SUMMARY.md` — Work UX summary.
- `IMPLEMENTATION_CHECKLIST.md` — implementation-vs-release closure checklist.
- `LOCAL_PREMERGE_VALIDATION.md` — isolated-runtime acceptance plan before merge/release.

## AI Operations Planner — design extension, not implemented

- `07_AI_OPERATIONS_PLANNER_SPEC.md` — engineering specification for compact analytics consumption, causal responsibility reasoning, decision gates, human factors, guarded Work creation, reliability/recovery, security, observability and rollout.
- `08_AI_OPERATIONS_PLANNER_ACCEPTANCE_SCENARIOS.md` — real-business, human-factor, failure/recovery, security and tool-efficiency acceptance scenarios.
- `09_AI_OPERATIONS_PLANNER_SCHEMA_STUDY_MIGRATION_PLAN.md` — read-only live-schema findings, isolation decisions, resource/lock budget, staged migration plan, rollout gates and prerequisite reliability/security findings.

The AI Operations Planner documents are **design specifications only**. They do not mean the AI layer has been implemented, enabled, scheduled, migrated or deployed.

No production migration or deployment is authorised by the presence of these documents.
