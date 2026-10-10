# B2-F — synthetic browser qualification

This tooling runs the actual Vite build, application, Supabase SDK, stores and UI in an installed Chromium browser. Only HTTP and Realtime boundaries have synthetic fixtures. It never connects to a database, uses the existing local Supabase/demo, loads `.env` files, or supplies real credentials.

Run from the isolated worktree with Node and installed project dependencies:

Set the two paths below to an existing Playwright package and an external artifact directory. Neither value is a service credential.

```powershell
$playwrightPackage = 'C:\absolute\existing\playwright-package'
$artifactRoot = 'C:\absolute\external\qualification-artifacts'
node --check tools/qualification/synthetic-browser-baseline.mjs
node --test tools/qualification/synthetic-fixtures.test.mjs
node tools/qualification/synthetic-browser-baseline.mjs --preflight --playwright "$playwrightPackage"
node tools/qualification/synthetic-browser-baseline.mjs --playwright "$playwrightPackage" --out "$artifactRoot" --port 5197
# Optional, for a separately prepared local-Cairo candidate:
node tools/qualification/synthetic-browser-baseline.mjs --playwright "$playwrightPackage" --out "$artifactRoot" --port 5197 --require-cairo
```

The CLI does not install packages or browsers. An occupied port fails without stopping its owner. Builds and screenshots go into a fresh external run directory. `report.json` records the exact Git SHA, dirty file hashes, browser version, synthetic profile identifier, sidebar flags, request methods/paths/status/timing, views, failures and cleanup evidence. Auth headers, JWTs and profile responses are not logged. Synthetic SDK session storage is initialized in a fresh browser context; application auth/profile state is established by the real lifecycle.

Static serving uses the real built files and only the matrix's known SPA routes. Unknown static paths return404. Synthetic profile identifiers refer to fixtures, never real users; the signed-out scenario has no synthetic session/profile identifier.

Both sidebar builds use `envFile:false`, `envPrefix:[]` and explicitly defined inert values for every source-consumed `VITE_*` variable. New consumed variables stop the build pending review. A sentinel injected into the inherited environment must be absent from generated assets. Browser HTTP and WebSocket boundaries reject external traffic, unknown API methods/endpoints and unknown Realtime topics/events. Separate safety probes demonstrate the rejection of external HTTP/WebSocket and an unknown fixture. Fixtures cover only the listed journeys; they do not model ERP business transactions.

The bounded matrix covers dashboard loading/completion and the authorized Customers list at 390, 900, 1440 and 360 pixels, plus desktop legacy-sidebar parity; actual UI links verify SPA navigation without a document reload. It also covers explicit permission denial taking precedence over wildcard access, profile-unavailable/retry through the visible button, inactive/signed-out redirection, a desktop dark/long-Arabic case and a separate warm reload. Deferred responses prove low-stock starts before six count requests complete and that loading remains until low-stock completes. Screenshots disable animations for stable capture; document overflow and uncaught browser errors are checked. Browser and owned HTTP listener retirement are checked in `finally`, including failed runs.

`--require-cairo` is off by default. When enabled, every normal capture first loads actual Cairo FontFaces for400/500/600/700 with Arabic and Latin text, awaits `document.fonts.ready`, and requires nonempty returned faces whose normalized family is Cairo and whose status is loaded. Each view records weights, face counts, families and loading status. A fallback font or `document.fonts.check` result alone cannot satisfy this gate. The option does not change fixtures, fonts or application code; it requires a separately prepared candidate and independent execution.

## Original baseline findings (historical)

The first real run completed the visible journeys without horizontal overflow or uncaught page errors, but strict network qualification **FAILS** because `src/styles/tokens.css` imports Cairo from `https://fonts.googleapis.com/css2`. The harness blocks these external requests and records the failures. It does not return pretend font CSS, exempt the requests or change the application. Screenshots therefore show the local fallback font; external-font appearance is unqualified. `journeyStatus:PASS` describes completion only; it does not turn the failed strict boundary gate into PASS.

The stronger second run exercised the actual profile-retry button. Two synthetic profile503 responses produced the intended temporary-error UI. Clicking retry then received profile200 and denial200, but the page redirected to `/login` and never requested dashboard data. `retry-900-profile-retry.png`, `retry-900-failure.png` and the report request trace preserve this product finding. Source inspection identifies a potential transition window: `loadSession` clears `profileLoadError` before restoring `profile`, while `ProtectedRoute` ignores the loading state once initialized and redirects when profile is absent. This slice records the observed failure; it does not change auth behavior or claim real-backend acceptance.

The second writer run completed seven other visible journeys, including real SPA navigation and dark/warm reload; its legacy-sidebar journey hit a harness selector mismatch (`قائمة العملاء` rather than `العملاء`). After correcting the selector, the parent's independent run confirmed **8/9 visible journeys**, including legacy-sidebar SPA navigation; the retry journey remained FAIL and every strict network gate remained FAIL on the font dependency. It recorded zero uncaught page errors and successful browser/listener retirement. These baseline runs do not qualify a local-font candidate or the optional Cairo check, which must be executed on its exact candidate independently.

## Qualified frontend successor

The original failures above are retained as counterfactual evidence. They describe the earlier candidate, not the current successor. The local Cairo slice `953eed5`, profile-retry guard slice `43477cf`, actor-scoped cold dashboard dedup slice `9fc6893`, and lazy-login slice `70b234f` were each qualified separately before local preservation. The tooling commit is included on the local `codex/performance-frontend-qualified` branch; this branch is not a production release or full foundation acceptance.

On the lazy-login successor, the existing strict nine-case browser matrix passed with `--require-cairo`, both sidebar builds and successful owned browser/listener retirement. The full suite, lint and forced TypeScript check also passed locally. Re-run the commands above against any new candidate; source review or an earlier green report cannot qualify later changes.

`DashboardPage` now shares the identical pending-sales count only during cold loading. Its outer caches remain fresh for60seconds and populated refetches request independent fresh counts. These two query groups are keyed by profile identity and canonical permissions; this does not repair other components' cache lifecycle or the SDK session-generation race. The login route uses the existing lazy/Suspense pattern, with the login component itself unchanged.

The SW still precaches all generated build assets. A lazy import can reduce the critical static entry closure while the first SW installation still downloads those assets in the background. The blocked-SW browser matrix cannot measure that background traffic or certify offline/update behavior.

## Evidence limits

- This is synthetic frontend request/render evidence, not production latency or p95.
- Real Supabase SQL, RLS, transactions, Auth backend acceptance and full seeded golden workflows remain required.
- Service workers are blocked. PWA, offline, update, push and device acceptance remain open.
- A completed journey, source review or successful build does not approve a production release.
- No product source, dependency, workflow, migration, deployment or production configuration is changed by this slice.
