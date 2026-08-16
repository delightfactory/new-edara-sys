# Automation Summary

Reuse the existing notification engine, push, Realtime, `notification_alert_state` and pg_cron.

Scheduled processing is set-based: operational scan, recurrence generation and workflow-step activation. Overdue, follow-up due, stale and escalation use deterministic alert keys and cooldowns.

Recurring work defaults to `strict`: every cycle creates an independent Work Item even when an older cycle is overdue. Optional `single_open` records an overlap without moving the original due date or hiding the missed cycle.