# Data Model Summary

Core tables:
- work_items
- work_events
- work_participants
- work_comments
- work_checklist_items
- work_attachments
- work_links
- work_dependencies

Domain tables cover queues/requests, approvals, policies/escalation, recurrence and versioned workflows.

Actor references use `profiles.id`. Work history is append-only. Waiting requires a reason, next action and follow-up timestamp. Required checklist items and hard dependencies can block completion. Entity links never grant permission to the linked entity. Published policy/workflow definitions are versioned and immutable.