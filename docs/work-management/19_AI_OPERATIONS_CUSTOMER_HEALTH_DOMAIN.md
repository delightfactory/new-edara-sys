# AI Operations — Customer Health / Re-engagement Domain

**Status:** branch implementation artifacts only — no production AI Operations migration applied  
**Branch:** `feature/work-management`  
**Domain:** `customer_health`  
**Acceptance sequence:** governed by `18_AI_OPERATIONS_BUILD_ALL_DOMAINS_ACCEPTANCE_STRATEGY.md`.

## 1. Production reality used by this domain

This increment was designed after a read-only inspection of the production database rather than from a synthetic CRM model.

The production system already contains useful Customer Health evidence across:

- `public.customers` and assigned representatives;
- `public.sales_orders` / items / returns;
- active `targets`, `target_customers` and target filter criteria;
- structured activities, visit plans and call plans;
- current credit/balance fields;
- generic Work links;
- Customer 360 and historical re-engagement analytics.

The deployed commercial date authority is `analytics.effective_sale_date(delivered_at, order_date)`. Customer Health therefore accepts both historical `completed` and current `delivered` orders instead of treating `delivered_at`-only data as complete history.

Production observations used to validate the design, but **not hard-coded as permanent thresholds**, included:

- the current active reactivation target selects 104 customers;
- its current governed dormancy threshold is 30 days;
- its configured minimum reactivation value is EGP 1,000;
- the active category-spread target selects 133 customers and requires four new categories;
- a material set of high-value dormant repeat customers currently sits outside the selected reactivation target.

These are runtime business records. The engine reads current governed values each run instead of embedding August 2026 campaign values in code.

## 2. Existing assets reused instead of duplicated

The domain intentionally reuses established semantics:

- `analytics.effective_sale_date` for Cairo commercial dates;
- `targets` / `target_customers` for explicit reactivation policy and customer selection;
- the target engine's reactivation success semantics: scoped net sales must reach the configured minimum value;
- category-spread baselines and new-category logic as supporting commercial context;
- Customer 360 concepts such as recency, repeat buying and customer value;
- signed customer balance semantics, where a negative balance remains customer credit rather than being clamped to zero;
- activities/visits/calls as supporting interaction evidence only;
- existing Work Engine customer/target link allowlists and reviewed Work execution path.

Historical fixed re-engagement labels such as 45/90-day status buckets remain useful analytical evidence but are **not** current operational authority when an active governed target defines another threshold.

## 3. Deterministic Case families

### A. `reactivation_gap`

An `exception` Case is raised when a customer is explicitly selected by a currently active reactivation target, its dormancy baseline is valid, and scoped net sales in the target period have not reached the target's current `min_reactivation_value`.

This distinguishes:

- no reactivation sale yet;
- partial sale below the required success threshold;
- successful reactivation.

A small invoice therefore cannot silently close a reactivation objective that requires a higher minimum value.

### B. `high_value_reactivation_opportunity`

An `opportunity` Case may be raised for a repeat customer that:

- is outside the active reactivation target selection;
- is in the top decile of historical net value among repeat customers;
- is dormant by the currently governed reactivation dormancy threshold.

This Case does **not** override the official target. It exposes a material commercial opportunity for AI/human review, which may correctly end in `IGNORE`, `MONITOR`, `INVESTIGATE`, `INFORM` or reviewed Work.

## 4. Evidence frozen per Case

The bounded worker evidence includes, where available:

- customer identity/name/code/type and geography IDs;
- assigned representative and organisational placement;
- historical order count, lifetime net value and value percentile;
- last commercial sale, recency and recent-vs-prior 90-day value;
- current governed reactivation target facts;
- current category-spread context;
- signed balance, credit limit/days and a coarse feasibility state;
- latest structured customer activity;
- open visit/call commitments;
- existing active customer-linked Work;
- assigned-rep/direct-manager/target-scope accountability evidence;
- bounded governed operational context.

Direct contact PII such as phone/mobile/email/tax number is deliberately excluded from the AI worker facts.

Field activity and credit evidence do not prove why a customer stopped buying. They inform feasibility and investigation only.

## 5. Shared snapshot and global domain budget

The previous operational snapshot allocator was explicitly two-domain. This increment introduces a deterministic round-robin water-fill allocator so additional domains can share one hard global Case budget without comparing domain-specific severity scales.

The canonical snapshot now supports immutable capture markers for:

1. Receivables;
2. Sales;
3. Customer Health.

Unused reserved capacity may spill to another domain. If Customer Health demand exists but no global capacity remains, the snapshot records a `partial` zero-row capture marker rather than pretending the domain had no Cases.

A previously captured Receivables/Sales snapshot may receive Customer Health only before a worker context hash is bound. Once reasoning has a context identity, the evidence set is immutable.

The existing generic worker already consumes every `snapshot_case` and every `domain_capture`; no parallel Customer Health AI worker is introduced.

## 6. Current-state validation

Before consequential Customer Health execution, the canonical guard rechecks the deterministic Case against current data.

It fails closed when material state changed, including:

- customer became missing/inactive;
- Case is no longer a current deterministic candidate;
- assigned representative changed;
- governing target identity/dormancy/minimum-value rules changed;
- target scope accountability changed;
- sales/reactivation progress changed;
- credit feasibility class changed;
- a newer customer interaction occurred;
- a new visit/call commitment appeared;
- active customer-linked Work now collides;
- escalation no longer points to active customer-linked Work;
- proposed owner/assignee is unavailable;
- Customer Health capture is incomplete for action;
- newer governed customer/employee/target context appeared.

The audited Receivables/Sales guard is preserved as a private primitive and Customer Health is added through the same canonical dispatcher.

## 7. Human-reviewed Work execution

Customer Health never autonomously creates Work.

Reviewed `CREATE_WORK` uses the existing safety contract:

- planner enabled;
- Shadow Mode off;
- human review approved;
- exact reviewed decision fingerprint/revision still current;
- decision already validated;
- canonical current-state guard rerun in the same transaction immediately before Work mutation;
- explicit active owner and assignee;
- explicit future due date;
- deterministic `source_key` and idempotent retries.

Created Work is system-origin, employee-safe and linked:

- primarily to the exact customer;
- optionally to the governing reactivation target.

The bridge mutates Work and AI provenance only. It does not mutate customers, targets, target progress, sales, activities, visits, calls or credit records.

## 8. Continuous acceptance for this increment

Before proceeding to Inventory, the current branch should pass:

- static architecture/security review;
- Customer Health deterministic Case contract tests;
- immutable snapshot/global budget contract tests;
- current-state drift contract tests;
- human-reviewed Work bridge contract tests;
- repository test/type-check/build/clean-install CI on the current HEAD.

The expensive local database runtime acceptance remains intentionally deferred to the final integrated all-domain sweep. No production migration or release is authorized by this document.