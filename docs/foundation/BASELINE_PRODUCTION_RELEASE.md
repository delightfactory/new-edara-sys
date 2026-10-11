# Delight baseline production release — 2026-10-12

Status: **PRODUCTION_DEPLOYED_VERIFIED**.

- Live domain: https://edara.delight-world.com
- Application source: `d7fdc527f3dc087f5f0c30b464df31ee481c8483`.
- Deployment: `dpl_99LWy3BshNvwX6Tb9X4smnmp72GC`.
- Project/team: `prj_lxOEu9ZLCgeKdlJbIj2Rt4YMWBEF` /
  `team_AYQTvxuQJ1EepKxDVhzjX1ew`.
- Supabase: `ozthzccqudrudicnneuu` / `NEW-EDARA-SYS`.
- Previous production deployment retained for rollback:
  `dpl_Aa1KTwZFaBj9fj766JtTHMgLr6Ld`, source `d0d5f35429463219e575d4e306464ea24ebed776`.

## Approved recovery mechanism

The owner explicitly approved function/view/ACL rollback capture instead of a full
business-data backup for this metadata-only release. The ten named migration files
replace/create functions, create a safe stock read view and adjust grants. They do
not migrate/delete business records, change table columns or replace RLS policies.
This release does not claim full-database disaster recovery.

Fresh production definitions/owners/effective grants for 25 existing functions,
stock/products table/column grants, and absence of the two additive surfaces were
captured. The generated rollback is stored privately on C and in
`D:\local-database\new-edara-sys\release-backups\2026-10-12`.
SHA256: `64a62fab9a7cc32b7ceadce8ca6e94326a78894fc21d72fa3846ac738a37ff4e`.
No private catalog, credentials, production actor IDs or business records were uploaded
to the public GitHub repository.

On the owned qualification database, the rehearsal restored original production
contracts, applied all ten hash-verified files, compared candidate definitions/grants,
reversed to original contracts, and restored the qualification candidate. All 158
public-table counts/content digests remained unchanged. This demonstrates object
rollback, not full database restoration. The original signatures remained replaceable.
Catalog comparison uses a consistent `public` search path for PostgreSQL deparsing.

Claude Pro directly reviewed the narrower mechanism: PASS, no blocking issue. This
was a supplied-evidence review with tools disabled, not independent runtime execution.
Before a future rollback drops additive objects, check current dependencies/callers;
the script uses RESTRICT, never CASCADE. Roll back frontend first where compatible,
and review any reverted security grants before restoring older access behavior.

## Publication and executed checks

1. Built the immutable archived source with production variables, atomic visits and
   DS2 sidebar enabled. `.env*` was explicitly excluded from source upload. Git auto
   deployment remains disabled; no main/DS2/AI branch merge was performed.
2. Created the production-configured deployment with `--skip-domain`. Build READY and
   protected hosted HTML/JS/SW checks passed before changing the custom live domain.
3. Rechecked original production object contracts; then applied exactly ten manifest
   files through Supabase MCP. Actual provider-generated migration versions are recorded
   separately from source filename timestamps in the release evidence.
4. Verified all 26 resulting function bodies and client grants, stock/products column
   ACLs and safe stock view. Existing object owners remain unchanged. The two new
   objects are owned by `postgres` in production, versus the isolated migration executor
   `supabase_admin`; the privileged backend service role also receives its normal default
   view grants in production. These explicit environment differences were reviewed;
   anonymous/authenticated grants and view definitions match the qualified contract.
5. Executed read-only transactions under authenticated claims of existing active admin
   and representative actors: profile lookup, stock view, low-stock RPC and unread-count
   RPC succeeded; cost access matched each actor's permission, with no costs shown to the
   representative. These are SQL/RLS checks, not real production password-login UAT.
   No business posting or test user was created in production. Stock publication remains.
6. Promoted the exact deployment. Domain resolution now identifies that deployment.
   Four live SPA routes return 200 and the new bundle; JS names the correct production
   API, assets remain immutable, and `sw.js` has no-store/no-cache headers.

Live entry script: `/assets/index-Dxb7-ugj.js`.
Live JS SHA256: `aa7e60675ff9113719bf6128458356e9d4bfbe8e21b2ffff1d55311e4128d2ca`.
Live SW SHA256: `d9cc136e3573a743af80bc96db27cea2fa732013091092fd3aaec75821e2a2cf`.

The browser initially had a cached earlier login bundle. A temporary tab-scoped
service-worker bypass verified rendering of the new live bundle; the bypass was reset
and the owned tab closed. No user's cache, drafts or offline queues were deleted.
Existing sessions can retain a prior build until the update is accepted. Production
password login, field-device/GPS use and actual-client PWA transition remain user UAT;
the earlier isolated update/reconnect tests remain scoped to their tested environment.

The user's preview at 5180 remains available, its database/fixtures unchanged. This
release establishes the deployed Delight baseline; it does not declare the whole DS2,
deferred AI integration or resale product finished.
