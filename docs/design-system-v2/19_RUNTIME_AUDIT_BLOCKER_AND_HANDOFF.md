# 19 — Runtime Visual Audit Blocker & Handoff

## Why this remains open

The source audit can prove component structure, route coverage, responsive CSS rules, accessibility risks visible in code, and repeated local UI implementations. It cannot prove the final rendered experience.

A valid runtime visual audit requires an interactive browser session against the real application with authenticated representative roles and screenshots captured at target device widths.

The current Blueprint therefore **does not claim** that visual hierarchy, contrast, density, clipping, touch feel, browser safe areas or real tablet behavior have been visually validated.

## Required runtime inputs

Use a safe non-production or read-safe environment with representative data. Do not expose sensitive Delight customer/credit/employee data in externally shared screenshots.

Representative roles should cover at minimum:
- management/admin
- sales/rep
- finance/collection where materially different
- HR/self-service where materially different

## Required capture set

Capture the flows listed in `08_RUNTIME_VISUAL_AUDIT.md`, at the widths listed in `11_GOLDEN_FLOW_ACCEPTANCE.md`.

Priority order:
1. shell/navigation
2. dashboard
3. customers
4. sales
5. inventory transfer
6. finance payment
7. purchase invoice
8. attendance
9. visit execution
10. work hub/detail
11. reports
12. representative admin/permission page

## What runtime evidence may change

Runtime evidence may adjust:
- exact token values
- spacing/density
- typography sizes/weights
- breakpoints
- tablet shell composition
- navigation group labels/order
- component composition
- action placement
- card/table information priority
- dialog/sheet sizing

It must not alter business rules or authorization semantics inside the same UI PR.

## Runtime finding format

Each finding should record:
- flow/screen
- device/viewport
- screenshot reference
- severity P1/P2/P3
- observed problem
- user impact
- V2 pattern/token implicated
- proposed UI correction
- whether a separate functional issue is required

## Handoff rule

Broad visual implementation of App Shell and Golden Flow page composition begins only after this runtime pass, or proceeds with an explicit note that visual values remain provisional and must be validated before merge.

Low-risk source-grounded infrastructure such as semantic token aliases, control accessibility fixes and component API hardening may start before the runtime audit if they do not visually redesign broad product surfaces.
