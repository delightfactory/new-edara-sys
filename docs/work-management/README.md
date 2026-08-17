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

## AI Operations Planner — design + branch implementation artifacts, not deployed

- `07_AI_OPERATIONS_PLANNER_SPEC.md` — engineering specification for compact analytics consumption, causal responsibility reasoning, decision gates, human factors, guarded Work creation, reliability/recovery, security, observability and rollout.
- `08_AI_OPERATIONS_PLANNER_ACCEPTANCE_SCENARIOS.md` — real-business, human-factor, failure/recovery, security and tool-efficiency acceptance scenarios.
- `09_AI_OPERATIONS_PLANNER_SCHEMA_STUDY_MIGRATION_PLAN.md` — read-only live-schema findings, isolation decisions, resource/lock budget, staged migration plan, rollout gates and prerequisite reliability/security findings.
- `10_AI_OPERATIONS_PLANNER_REALITY_INTEGRATION_GATE.md` — reality review separating the durable EDARA planner core from replaceable AI worker adapters, defining what is production-real today, what remains Shadow/Human-review only, and the first closed-loop vertical slice.
- `11_AI_OPERATIONS_EXISTING_ENTITY_MAP.md` — catalog-driven map of existing Work/entities that must be reused rather than duplicated.
- `12_AI_OPERATIONS_CREDIT_SOURCE_MAP.md` — verified deployed Credit/Receivables source semantics, responsibility evidence and Work-collision sources.
- `13_AI_OPERATIONS_PREVIEW_REVIEW_GUIDE.md` — database-free local Preview review flow for the control-center UI.
- `14_AI_OPERATIONS_CREDIT_SLICE_IMPLEMENTATION_DELTA.md` — implementation-time corrections: immutable snapshot-case evidence, atomic snapshot building, context byte budgeting, conservative trust and UI/worker boundary.
- `15_AI_OPERATIONS_DECISION_PIPELINE_IMPLEMENTATION_DELTA.md` — staged-decision, validation, human-review and explicit Work-commit runtime contract.
- `16_AI_OPERATIONS_SALES_TARGETS_SOURCE_MAP.md` — production-reality map and implementation boundary for Sales & Targets.
- `17_AI_OPERATIONS_MULTI_DOMAIN_SALES_INTEGRATION.md` — shared multi-domain worker/snapshot integration for Sales & Targets.
- `18_AI_OPERATIONS_BUILD_ALL_DOMAINS_ACCEPTANCE_STRATEGY.md` — approved build-all strategy and deferred integrated local runtime acceptance.
- `19_AI_OPERATIONS_CUSTOMER_HEALTH_DOMAIN.md` — Customer Health / Re-engagement deterministic Case, validation and reviewed Work contract.
- `20_AI_OPERATIONS_INVENTORY_DOMAIN.md` — Inventory deterministic Case, snapshot, actionability and reviewed Work contract.
- `21_AI_OPERATIONS_FIELD_EXECUTION_DOMAIN.md` — Visits / Field Execution domain implementation contract.
- `22_AI_OPERATIONS_WORK_HEALTH_DOMAIN.md` — native Work Health continuity domain and recovery Work contract.
- `23_AI_OPERATIONS_HR_AVAILABILITY_DOMAIN.md` — HR / Availability planning-constraint domain using official schedules, approved leave and explicit attendance state without employee scoring.

The AI Operations Planner has **reviewable branch artifacts** (design-time SQL files, service contracts, Preview/RPC UI and tests), but the presence of these files does **not** mean the AI layer has been migrated, enabled, scheduled or deployed to production.

Production remains unchanged by these AI Operations branch artifacts. No production migration or deployment is authorised by the presence of the documents or SQL files.
