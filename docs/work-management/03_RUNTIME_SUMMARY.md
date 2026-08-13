# Runtime Summary

Work state changes use server-side atomic RPCs, not direct client updates. Sensitive operations use an `operation_id` plus expected state version for idempotency and concurrency control.

Delegation changes executor only. Ownership transfer changes accountability. Waiting requires a next action and follow-up time. Due-date extensions are audited and may require approval. Completion checks required checklist items, dependencies and approval rules.