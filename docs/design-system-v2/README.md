# Delight Design System V2

## Purpose
Transform Edara into a coherent, enterprise-grade, Arabic-first product experience while preserving all business behavior.

This program is a UI/design-system refactor, not a functional rewrite.

## Non-negotiable boundary
Design-system PRs must not modify database schema, Supabase RPC behavior, accounting calculations, inventory/credit/HR rules, workflow states, RBAC/RLS, API contracts, or notification semantics. Any functional issue discovered during UI work is logged separately.

## Product principles
1. Arabic-first and RTL-native.
2. Operational clarity before decoration.
3. One visual grammar across all modules.
4. High information density without visual noise.
5. Semantic tokens instead of page-specific colors and spacing.
6. Shared components and patterns over one-off implementations.
7. Desktop management workflows and mobile field workflows are both first-class.
8. Every migrated screen must preserve behavior and permissions.

## Deliverables
- Current UI audit and debt register
- Design foundations and semantic tokens
- Component system specification
- Page-pattern library and information architecture
- Module/page migration matrix
- Visual/runtime QA plan
- Guardrails and PR contract
- Incremental implementation roadmap

## Current status
Static source audit has started against `main`. The existing system already has useful tokens and shared primitives, so V2 will consolidate and evolve them rather than discard them blindly. Runtime screenshot audit is a separate gate before implementation is considered visually validated.

Tracking issue: #6
