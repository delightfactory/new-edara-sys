# Current restore and published compatibility preflight — 2026-10-11

The selected metadata compatibility and current same-cluster restore gates passed. Overall baseline, production release and full security acceptance remain open. Source parent:9576fc0d9629abbc72ef5510ee9c78147d1d9fb8.

## Published identity

Public edara.delight-world.com HTML and its main JS returned200. The live bundle targets Supabase ozthzccqudrudicnneuu. Authenticated Vercel metadata associates the domain with deployment dpl_Aa1KTwZFaBj9fj766JtTHMgLr6Ld, project new-edara-sys, main SHA d0d5f35429463219e575d4e306464ea24ebed776. These are separate verified observations. The unique deployment URL redirected to Vercel login; its200 response was a login page. Matching the live served asset to that exact Git SHA remains unverified. No independent reproducible-build claim.

## Selected compatibility

All25 selected existing function signatures, argument names and result contracts match the owned candidate database. Bodies of22 unchanged functions match exactly. The original bodies of the3 intentionally replaced functions match existing repository sources: check_permission in03g, get_low_stock in02f and create_ui_manual_journal_entry in60. This confirms original-source compatibility, while the new behavior is supported by its separate slice tests.

Eleven selected RLS policies across products/profiles/stock/units/warehouses/warehouse_managers match exactly. Production metadata still shows client execution grants and table-wide cost SELECT grants which the candidate migrations narrow. This is privilege metadata, not a production row-visibility or exploit test. No production business rows or financial workflow RPCs were read/invoked and no production mutation occurred. Unselected functions, policies and schema are outside this preflight.

## Current backup and restore

A fresh custom archive of the current synthetic database was restored into a checked absent template0 database in the same owned PG17 cluster. All48 public table row hashes, Auth users/identities, public function bodies/owners/ACL, table/column ACL/defaults/types, RLS policies, triggers, constraints and indexes matched. The source database stayed unchanged; the temporary database was retired. Archive SHA256:0e06c5aa2f34a4a49c7a827356d9972563a87fd0de03f7a7538ea3d083fcc939. The private archive stays outside Git.

This closes the current same-cluster schema/data restore gap after the workflow qualification runs. It does not prove independent-server/global-role provisioning, Auth runtime after restore or durable financial transaction replay; previous flow fixtures were reverted before archiving.

## Review and next gate

Direct Claude read-only review passed with the asset-to-SHA limitation and selected-only coverage explicit. Actual full App/forms, unified cold/warm performance and offline/update behavior, Realtime, final exact-SHA review and release approval remain open. No main/DS2 merge, hosted CI, production migration or deployment.
