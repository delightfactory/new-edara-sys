# Design Director State

## Reviewed baseline

Initialized on the current `design-system-v2-development` communication-system setup. Future updates must record exact reviewed development HEAD / PR HEAD.

## Current professional position

EDARA Design System V2 is a system-level product-design program, not a collection of cosmetic page refactors.

The active work must continuously converge toward:
- one Arabic-first visual and interaction language;
- mobile-primary operational clarity;
- deliberate tablet composition;
- dense but calm desktop productivity;
- consistent semantic actions/statuses/states;
- reusable primitives/patterns that reduce page-local invention;
- progressive retirement of legacy visual systems after parity.

Current READY slice: `DS2-UI-001 — Customer Form: basic-info composition`.

## Preserve

- zero backend/business behavior drift;
- existing customer create/update/GPS/credit/default-branch/default-contact semantics;
- Design System shared-layer ownership;
- current long-lived development branch / preview / CI policies;
- one implementation slice at a time.

## Current design-system watchpoints

- Do not convert form migration into a broad Customer module redesign.
- If Customer Form proves a recurring form pattern gap, strengthen the shared pattern instead of inventing a customer-only primitive.
- Maintain clear primary action and section hierarchy on mobile without sacrificing desktop productivity.
- Avoid over-cardification and decorative surfaces that add no operational meaning.

## Cross-role handoff

- **To:** UI Production Engineer, Design QA, Development Integrator
- **What changed:** team communication is now repository-native; all roles must read/write their owned state files and use cross-role handoffs.
- **Preserve:** North Star, functional isolation, device strategy, shared-component ownership.
- **Need from you:** initialize your role state only when you have material current evidence; read all peer states first.
- **Blocker level:** NONE
- **Baseline:** current `design-system-v2-development` HEAD at time of role run.
