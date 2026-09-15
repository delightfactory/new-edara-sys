# Delight Design System V2

## Purpose
Transform Edara into a coherent, enterprise-grade, Arabic-first product experience while preserving all business behavior.

This program is a UI/design-system refactor, not a functional rewrite.

## Non-negotiable boundary
Design-system PRs must not modify database schema, Supabase RPC behavior, accounting calculations, inventory/credit/HR rules, workflow states, RBAC/RLS, API contracts, or notification semantics. Any functional issue discovered during UI work is logged separately.

## Product usage model
Edara is a multi-device operational system used on desktop, tablet and mobile. Mobile is the primary day-to-day surface for a large share of operational users, while tablet and desktop remain first-class for management, review, reporting and high-density workflows.

Design System V2 therefore follows **mobile-primary operational design**, not desktop-first shrinking. Every important workflow must be intentionally designed for all three device classes.

## Product principles
1. Arabic-first and RTL-native.
2. Operational clarity before decoration.
3. One visual grammar across all modules.
4. High information density without visual noise.
5. Semantic tokens instead of page-specific colors and spacing.
6. Shared components and patterns over one-off implementations.
7. Mobile is the primary operational surface for frequent daily tasks; tablet and desktop are first-class adaptive surfaces, not afterthoughts.
8. Touch, safe-area, camera/upload, GPS and intermittent-network realities are part of mobile UX design where relevant.
9. Every migrated screen must preserve behavior and permissions.
10. No screen is considered migrated until mobile, tablet and desktop behavior is explicitly reviewed.

## Deliverables
- Current UI audit and debt register
- Design foundations and semantic tokens
- Component system specification
- Page-pattern library and information architecture
- Module/page migration matrix
- Device strategy for mobile/tablet/desktop
- Visual/runtime QA plan
- Guardrails and PR contract
- Incremental implementation roadmap

## Current status
Static source audit has started against `main`. The existing system already has useful tokens and shared primitives, so V2 will consolidate and evolve them rather than discard them blindly. Runtime screenshot audit is a separate gate before implementation is considered visually validated.

Automatic Vercel Git deployments are disabled for this project; preview/production deployments are intentional manual actions at review milestones.

Tracking issue: #6
