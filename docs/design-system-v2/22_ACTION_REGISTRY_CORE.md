# 22 — Action Registry Core

## Purpose
Create one deterministic, device-aware source of truth for action priority before any page is migrated.

## Contract
A domain page declares actions by meaning:
- id / label / handler
- importance: primary / secondary / tertiary
- visual tone
- disabled/loading state
- optional device availability
- optional stable order

The page does **not** decide whether an action becomes a header button, sticky mobile action, FAB, or overflow item.

## Resolution policy
- Mobile: one visible action, remaining eligible actions go to overflow.
- Tablet: two visible actions, remaining eligible actions go to overflow.
- Desktop: up to four visible actions, remaining eligible actions go to overflow.
- Primary importance is resolved before secondary and tertiary.
- Hidden and device-ineligible actions are removed before placement.

## Guardrails
- No current page or shell consumes the registry in this slice.
- No route, permission, workflow, database, RPC, accounting or inventory behavior changes.
- Presentation integration happens only after runtime visual evidence and explicit shell/action-surface work.
