# 28 — Sidebar V2 Activation Flag

## Purpose
Allow runtime visual QA of Sidebar V2 without replacing the proven production renderer by default.

## Flag
`VITE_DESIGN_SYSTEM_V2_SIDEBAR=true`

## Default behavior
When the environment variable is missing or not exactly `true`, `AppLayout` continues to render the existing `Sidebar` component.

## Enabled behavior
When the flag is `true`, `AppLayout` renders `SidebarV2` while all routes, permissions, BottomNav, FAB, page content and backend behavior remain unchanged.

## Rollout sequence
1. Keep the flag off in production.
2. Enable only in a controlled preview/test environment.
3. Validate desktop light/dark, tablet drawer, mobile drawer, restricted permissions and long labels.
4. Resolve visual/accessibility regressions without changing route or business semantics.
5. Only after acceptance, decide whether to make V2 the default and remove the legacy renderer in a separate PR.

## Guardrails
- This flag is presentation-only.
- It does not grant permissions or bypass route protection.
- The legacy Sidebar remains available for immediate fallback.
