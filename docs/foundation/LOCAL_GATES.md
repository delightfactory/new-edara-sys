# B0 local verification gates

Install the locked dependencies with `npm ci`. ESLint is a local, exact development dependency; no global installation is required.

The ESLint 10.12.0 engine supports Node `^20.19.0 || ^22.13.0 || >=24`. B0 was executed with Node 24.16.0 and npm 11.13.0. The TypeScript parser/plugin are pinned at 8.71.1 and the React Hooks plugin at 7.1.1; application runtime dependencies are unchanged.

Run the gates from the repository root:

```sh
npm test -- --maxWorkers=2 --minWorkers=1
npm run lint
npm run build
git diff --check
```

Vitest supplies inert `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` values in its test configuration before application imports. These values allow client construction in isolated tests; they do not authenticate a real backend. Tests that exercise services must retain their existing mocks. Production configuration is unaffected.

Source/CSS contract tests use the Node `URL` constructor alias so Vite does not rewrite file references into browser asset URLs. Vitest processes only CSS imports ending in `?raw` for source assertions; ordinary CSS remains on its default test path. One literal multiline CSS contract normalizes CRLF to LF, preserving selector and property assertions on Windows checkouts.

`npm run lint` checks application source under `src` and the root Vite, Vitest, PWA and ESLint configuration files. It enforces explicit core JavaScript correctness rules and React hook call order, with zero warnings allowed. This B0 policy does not claim complete style enforcement, type-aware linting, exhaustive effect dependency checking, or coverage of backend/operational scripts. Type checking remains part of `npm run build`. Existing directives for optional rules are retained; no new inline suppressions are introduced for enabled correctness rules.

The ReportsLayout regression navigates between reengagement, visits and analytics on the same mounted router tree. It checks operational gate bypass, analytics gating and the absence of hook-order errors. It fails with the original conditional hook call and passes with both route matches called unconditionally.

These gates run locally. They do not trigger hosted CI, previews, database changes or deployment, and their success does not establish production or multi-device acceptance.
