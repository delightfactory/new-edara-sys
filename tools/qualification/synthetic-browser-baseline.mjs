import assert from 'node:assert/strict'
import { createServer } from 'node:http'
import { connect } from 'node:net'
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises'
import { createHash, randomUUID } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { dirname, extname, isAbsolute, relative, resolve, sep } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { build } from 'vite'
import { customerName, fixtureResponse, isOverviewRequest, profile, realtimeReply, syntheticSession } from './synthetic-fixtures.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const options = Object.fromEntries(process.argv.slice(2).map((arg, index, args) =>
  arg.startsWith('--') ? [arg.slice(2), args[index + 1]?.startsWith('--') ? true : args[index + 1] ?? true] : []).filter(entry => entry.length))
let browserServer
let browser
let expect
let server
let runDirectory
const report = {
  requireCairo: options['require-cairo'] === true,
  limitations: ['Synthetic HTTP/Realtime only; no real DB/RLS/Auth authorization or business acceptance', 'Service workers blocked; PWA/offline/update behavior unqualified', 'Synthetic render/request timings are not production latency or p95'],
  scenarios: [], safety: {}, cleanup: {},
}

function portOpen(port) {
  return new Promise(resolveProbe => {
    const socket = connect({ host: '127.0.0.1', port })
    socket.once('connect', () => { socket.destroy(); resolveProbe(true) })
    socket.once('error', () => resolveProbe(false))
  })
}

async function sourceEnvNames(directory) {
  const names = new Set()
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name)
    if (entry.isDirectory()) for (const name of await sourceEnvNames(path)) names.add(name)
    else if (/\.[jt]sx?$/.test(entry.name)) for (const match of (await readFile(path, 'utf8')).matchAll(/VITE_[A-Z0-9_]+/g)) names.add(match[0])
  }
  return names
}

async function buildCandidate(flag, origin) {
  const dist = resolve(runDirectory, `dist-sidebar-${flag}`)
  const inert = {
    VITE_SUPABASE_URL: origin, VITE_SUPABASE_ANON_KEY: 'synthetic-inert-anon-key',
    VITE_SENTRY_DSN: '', VITE_VAPID_PUBLIC_KEY: '', VITE_VISITS_ATOMIC_EXECUTION: 'false',
    VITE_DESIGN_SYSTEM_V2_SIDEBAR: String(flag),
  }
  const consumed = await sourceEnvNames(resolve(root, 'src'))
  assert.deepEqual([...consumed].sort(), Object.keys(inert).sort(), 'Unreviewed VITE variable; stop before building')
  await build({ root, envFile: false, envPrefix: [], cacheDir: resolve(runDirectory, 'vite-cache'),
    define: Object.fromEntries(Object.entries(inert).map(([name, value]) => [`import.meta.env.${name}`, JSON.stringify(value)])),
    build: { outDir: dist, emptyOutDir: false },
  })
  for (const asset of await readdir(resolve(dist, 'assets'))) {
    if (/\.(js|css)$/.test(asset)) assert.ok(!(await readFile(resolve(dist, 'assets', asset), 'utf8')).includes(process.env.VITE_QUALIFICATION_SENTINEL), 'Inherited VITE sentinel leaked')
  }
  return dist
}

async function serveCandidate(port, currentDist) {
  const types = { '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html', '.svg': 'image/svg+xml', '.png': 'image/png', '.woff2': 'font/woff2', '.webmanifest': 'application/manifest+json', '.ico': 'image/x-icon' }
  server = createServer(async (request, response) => {
    const pathname = decodeURIComponent(new URL(request.url, `http://127.0.0.1:${port}`).pathname)
    const path = resolve(currentDist(), `.${pathname}`)
    if ((path !== currentDist() && !path.startsWith(`${currentDist()}${sep}`)) || !['GET', 'HEAD'].includes(request.method)) {
      response.writeHead(403); response.end(); return
    }
    try {
      if (!extname(path) && !['/', '/customers', '/login', '/unauthorized', '/settings/users'].includes(pathname)) {
        response.writeHead(404); response.end(); return
      }
      const assetPath = extname(path) ? path : resolve(currentDist(), 'index.html')
      const bytes = await readFile(assetPath)
      response.writeHead(200, { 'content-type': types[extname(assetPath)] ?? 'application/octet-stream', 'cache-control': 'no-store' })
      response.end(request.method === 'HEAD' ? undefined : bytes)
    } catch {
      response.writeHead(404); response.end()
    }
  })
  await new Promise((resolveListen, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolveListen) })
}

async function installBoundary(context, origin, scenario, evidence) {
  const state = { profileAttempts: 0, allowProfileRecovery: false, allowDashboardRecovery: false }
  const deferred = []
  const requestEvents = new WeakMap()
  context.on('response', response => {
    const event = requestEvents.get(response.request())
    if (event) event.status = response.status()
  })
  context.on('requestfinished', request => {
    const event = requestEvents.get(request)
    if (event) event.completedMs = performance.now()
  })
  await context.routeWebSocket('**/*', socket => {
    const url = new URL(socket.url())
    if (url.origin !== origin.replace('http:', 'ws:') || url.pathname !== '/realtime/v1/websocket') {
      evidence.boundaryFailures.push(`WebSocket ${url.pathname}`)
      socket.close(); return
    }
    socket.onMessage(message => {
      try { const reply = realtimeReply(message); if (reply) socket.send(reply) }
      catch (error) { evidence.boundaryFailures.push(error.message); socket.close() }
    })
  })
  await context.route('**/*', async route => {
    const request = route.request()
    const url = new URL(request.url())
    if (url.origin !== origin) {
      evidence.boundaryFailures.push(`HTTP ${request.method()} ${url.pathname}`)
      await route.abort('blockedbyclient'); return
    }
    const started = performance.now()
    const event = { method: request.method(), path: url.pathname, startedMs: started }
    evidence.requests.push(event)
    requestEvents.set(request, event)
    if (!url.pathname.startsWith('/rest/') && !url.pathname.startsWith('/auth/')) {
      await route.continue(); return
    }
    try {
      const fixture = fixtureResponse(request, scenario, state)
      if (isOverviewRequest(request) && scenario.kind === 'admin') {
        await new Promise(resolveDeferred => deferred.push({ event, release: resolveDeferred }))
      }
      await route.fulfill(fixture)
      event.status = fixture.status
      event.completedMs = performance.now()
    } catch (error) {
      evidence.boundaryFailures.push(error.message)
      await route.abort('blockedbyclient')
    }
  })
  return { state, deferred }
}

async function screenshot(page, name, evidence) {
  const fontChecks = report.requireCairo ? await page.evaluate(async () => {
    const checks = []
    for (const weight of [400, 500, 600, 700]) {
      const faces = await document.fonts.load(`${weight} 16px Cairo`, 'العربية EDARA')
      checks.push({ weight, faceCount: faces.length, faces: faces.map(face => ({ family: face.family, status: face.status, weight: face.weight })) })
    }
    await document.fonts.ready
    return checks
  }) : undefined
  const dimensions = await page.evaluate(() => ({
    viewport: window.innerWidth, document: document.documentElement.scrollWidth,
    direction: document.documentElement.dir, theme: document.documentElement.dataset.theme ?? 'light',
  }))
  evidence.views.push({ name, ...dimensions, fontChecks })
  for (const check of fontChecks ?? []) {
    assert.ok(check.faceCount > 0, `Cairo ${check.weight} did not resolve any FontFace at ${name}`)
    assert.ok(check.faces.every(face => face.family.replace(/["']/g, '').trim() === 'Cairo' && face.status === 'loaded'), `Cairo ${check.weight} is not loaded at ${name}`)
  }
  assert.equal(dimensions.direction, 'rtl')
  assert.ok(dimensions.document <= dimensions.viewport + 1, `Document overflow at ${name}: ${dimensions.document}/${dimensions.viewport}`)
  await page.screenshot({ path: resolve(runDirectory, `${evidence.name}-${name}.png`), fullPage: true, animations: 'disabled' })
}

async function navigateToCustomers(page, scenario, evidence) {
  const timeOrigin = await page.evaluate(() => performance.timeOrigin)
  if (scenario.width <= 768) {
    await page.getByRole('navigation', { name: 'التنقل الرئيسي' }).getByRole('link', { name: 'العملاء', exact: true }).click()
  } else {
    if (scenario.width <= 1024) await page.getByRole('button', { name: 'فتح القائمة الرئيسية', exact: true }).click()
    const sidebar = page.getByRole('complementary', { name: 'القائمة الرئيسية' })
    await sidebar.getByRole('button', { name: 'العملاء', exact: true }).click()
    await sidebar.getByRole('link', { name: scenario.sidebar ? 'العملاء' : 'قائمة العملاء', exact: true }).click()
  }
  await expect(page).toHaveURL(/\/customers$/)
  assert.equal(await page.evaluate(() => performance.timeOrigin), timeOrigin, 'Navigation unexpectedly reloaded the app')
  evidence.navigation = 'actual-ui-SPA-link; document timeOrigin unchanged'
}

async function runScenario(origin, scenario) {
  const evidence = { ...scenario, profileId: scenario.kind === 'signedout' ? null : profile.id, requests: [], boundaryFailures: [], consoleErrors: [], pageErrors: [], views: [] }
  report.scenarios.push(evidence)
  const context = await browser.newContext({ viewport: { width: scenario.width, height: 900 }, serviceWorkers: 'block', permissions: ['geolocation'], geolocation: { latitude: 30, longitude: 31 } })
  const boundary = await installBoundary(context, origin, scenario, evidence)
  await context.addInitScript(({ session }) => {
    if (session) localStorage.setItem('sb-127-auth-token', JSON.stringify(session))
  }, { session: scenario.kind === 'signedout' ? null : syntheticSession() })
  const page = await context.newPage()
  page.on('pageerror', error => evidence.pageErrors.push({ name: error.name, message: error.message.slice(0, 300) }))
  page.on('console', message => { if (message.type() === 'error') evidence.consoleErrors.push(message.text().split('\n')[0].slice(0, 180)) })
  try {
    await page.goto(origin, { waitUntil: 'domcontentloaded' })
    if (['inactive', 'signedout'].includes(scenario.kind)) {
      await expect(page.getByRole('button', { name: 'تسجيل الدخول', exact: true })).toBeVisible()
      await expect(page).toHaveURL(`${origin}/login`)
      assert.equal(await page.evaluate(() => sessionStorage.getItem('edara_auth_v1')), null)
      await screenshot(page, 'login', evidence)
    } else {
      if (scenario.kind === 'retry') {
        await expect(page.getByText('تعذر تحميل بيانات المستخدم مؤقتاً', { exact: true })).toBeVisible()
        await screenshot(page, 'profile-retry', evidence)
        boundary.state.allowProfileRecovery = true
        await page.getByRole('button', { name: 'إعادة المحاولة', exact: true }).click()
        evidence.retryAction = 'actual retry button clicked after profile-unavailable UI'
      }
      if (scenario.kind === 'admin') {
        await expect.poll(() => new Set(boundary.deferred.filter(entry => entry.event.method === 'HEAD').map(entry => entry.event.path)).size).toBe(6)
        assert.ok(boundary.deferred.some(entry => entry.event.path === '/rest/v1/rpc/get_low_stock'), 'Low-stock did not start with unresolved counts')
        await expect(page.getByLabel('جاري تحميل القيمة').first()).toBeVisible()
        await screenshot(page, 'loading', evidence)
        for (const entry of boundary.deferred.filter(entry => entry.event.method === 'HEAD')) entry.release()
        await expect(page.getByLabel('جاري تحميل القيمة').first()).toBeVisible()
        boundary.deferred.find(entry => entry.event.path === '/rest/v1/rpc/get_low_stock').release()
      }
      if (scenario.kind === 'dashboard-error') {
        const overviewFailed = scenario.errorGroup === 'overview'
        const title = overviewFailed ? 'تعذّر تحميل مؤشرات النظام' : 'تعذّر تحميل مؤشرات المبيعات'
        await expect(page.getByText(title, { exact: true })).toBeVisible()
        const healthyLabel = overviewFailed ? 'إيرادات اليوم' : 'العملاء النشطون'
        const hiddenLabel = overviewFailed ? 'العملاء النشطون' : 'إيرادات اليوم'
        await expect(page.getByText(healthyLabel, { exact: true })).toBeVisible()
        await expect(page.getByText(hiddenLabel, { exact: true })).toHaveCount(0)
        assert.equal(evidence.requests.filter(request => request.status === 503).length, overviewFailed ? 1 : 2, 'Unexpected automatic dashboard retries')
        await screenshot(page, 'dashboard-error', evidence)
        boundary.state.allowDashboardRecovery = true
        await page.getByRole('button', { name: overviewFailed ? 'إعادة تحميل المؤشرات' : 'إعادة تحميل المبيعات', exact: true }).click()
        await expect(page.getByText(title, { exact: true })).toHaveCount(0)
        await expect(page.getByText(hiddenLabel, { exact: true })).toBeVisible()
        evidence.dashboardRetry = 'actual group retry button; failed metrics absent; independent group visible; recovered'
      }
      if (scenario.kind === 'limited') {
        await expect(page.getByText('مرحباً بك', { exact: true })).toBeVisible()
        await expect(page.getByText('تنبيهات المخزون', { exact: true })).toHaveCount(0)
      } else await expect(page.getByText('3 صنف على وشك النفاد', { exact: true })).toBeVisible({ timeout: 15_000 })
      if (scenario.kind === 'retry') assert.ok(boundary.state.profileAttempts >= 3, 'Initial automatic retry and visible retry must execute')
      await screenshot(page, 'dashboard', evidence)
      await navigateToCustomers(page, scenario, evidence)
      await expect(page.getByText(customerName, { exact: true }).first()).toBeVisible()
      await screenshot(page, 'customers', evidence)
      if (scenario.kind === 'limited') {
        await page.goto(`${origin}/settings/users`, { waitUntil: 'domcontentloaded' })
        await expect(page.getByRole('heading', { name: 'غير مصرح بالوصول' })).toBeVisible()
        await expect(page).toHaveURL(`${origin}/unauthorized`)
        assert.ok(!evidence.requests.some(request => request.path === '/rest/v1/rpc/get_users'), 'Denied page requested protected data')
        await screenshot(page, 'denied', evidence)
      }
      if (scenario.dark) {
        await page.getByRole('button', { name: 'الوضع الداكن', exact: true }).click()
        await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')
        await screenshot(page, 'customers-dark-long-arabic', evidence)
        await page.reload({ waitUntil: 'domcontentloaded' })
        await expect(page.getByText(customerName, { exact: true }).first()).toBeVisible()
        await screenshot(page, 'warm-reload', evidence)
        evidence.warmReload = 'actual page reload with real session/cache storage'
      }
    }
    evidence.journeyStatus = 'PASS'
    assert.deepEqual(evidence.boundaryFailures, [], 'Unexpected HTTP/WebSocket boundary')
    assert.deepEqual(evidence.pageErrors, [], 'Uncaught browser errors')
    const allowedErrors = scenario.kind === 'retry' ? /503|\[Sentry no-op\]/ : scenario.kind === 'dashboard-error' ? /503/ : scenario.kind === 'signedout' ? /406/ : /^$/
    assert.ok(evidence.consoleErrors.every(message => allowedErrors.test(message)), `Unexpected console errors: ${evidence.consoleErrors.join('; ')}`)
    evidence.status = 'PASS'
  } catch (error) {
    evidence.status = 'FAIL'
    evidence.journeyStatus ??= 'FAIL'
    evidence.findingKind = evidence.boundaryFailures.some(failure => failure.startsWith('Unqualified'))
      ? 'FIXTURE_GAP' : evidence.journeyStatus === 'PASS' ? 'NETWORK_OR_RUNTIME_GATE_FAILURE' : 'VISIBLE_JOURNEY_FAILURE'
    evidence.failure = error.message.slice(0, 1500)
    await page.screenshot({ path: resolve(runDirectory, `${evidence.name}-failure.png`), fullPage: true, animations: 'disabled' })
  } finally { evidence.profileAttempts = boundary.state.profileAttempts; await context.close() }
}

async function runBaseline() {
  assert.ok(options['require-cairo'] === undefined || options['require-cairo'] === true, '--require-cairo is a flag without a value')
  assert.equal(typeof options.playwright, 'string', '--playwright must point to an existing Playwright package directory')
  const { chromium } = await import(pathToFileURL(resolve(options.playwright, 'index.mjs')).href)
  ;({ expect } = await import(pathToFileURL(resolve(options.playwright, 'test.mjs')).href))
  report.gitSha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim()
  browserServer = await chromium.launchServer({ headless: true, host: '127.0.0.1' })
  browser = await chromium.connect(browserServer.wsEndpoint())
  report.browser = browser.version()
  report.browserPid = browserServer.process().pid
  if (options.preflight) { report.status = 'PASS'; return }
  assert.ok(typeof options.out === 'string' && isAbsolute(options.out), '--out must be an absolute external artifact directory')
  const outputRoot = resolve(options.out)
  const relativeOutput = relative(root, outputRoot)
  assert.ok(relativeOutput === '..' || relativeOutput.startsWith(`..${sep}`) || isAbsolute(relativeOutput), 'Artifacts must be outside the worktree')
  const port = Number(options.port ?? 5197)
  assert.ok(Number.isInteger(port) && port >= 1024 && port <= 65535, 'Invalid loopback port')
  assert.equal(await portOpen(port), false, 'Port occupied: stop without touching its owner')
  runDirectory = resolve(outputRoot, `synthetic-${Date.now()}-${randomUUID()}`)
  await mkdir(runDirectory, { recursive: true })
  const origin = `http://127.0.0.1:${port}`
  report.origin = origin
  const sentinelBefore = process.env.VITE_QUALIFICATION_SENTINEL
  process.env.VITE_QUALIFICATION_SENTINEL = `INHERITED-DO-NOT-BUNDLE-${randomUUID()}`
  let distOn, distOff
  try { distOn = await buildCandidate(true, origin); distOff = await buildCandidate(false, origin) }
  finally { if (sentinelBefore === undefined) delete process.env.VITE_QUALIFICATION_SENTINEL; else process.env.VITE_QUALIFICATION_SENTINEL = sentinelBefore }
  report.safety.inheritedViteSentinelAbsent = true
  let currentDist = distOn
  await serveCandidate(port, () => currentDist)
  const safetyContext = await browser.newContext({ serviceWorkers: 'block' })
  const safetyEvidence = { boundaryFailures: [], requests: [] }
  await installBoundary(safetyContext, origin, { kind: 'signedout' }, safetyEvidence)
  const safetyPage = await safetyContext.newPage()
  assert.equal((await safetyPage.goto(`${origin}/unqualified-static`)).status(), 404)
  report.safety.unknownStaticPathReturns404 = true
  await safetyPage.goto('https://qualification.invalid/blocked').catch(() => {})
  await safetyPage.goto(`${origin}/rest/v1/unqualified`).catch(() => {})
  await safetyPage.evaluate(() => new Promise(resolveClosed => {
    const socket = new WebSocket('wss://qualification.invalid/blocked-socket')
    socket.onclose = () => resolveClosed()
    socket.onerror = () => resolveClosed()
  }))
  assert.deepEqual(safetyEvidence.boundaryFailures, ['HTTP GET /blocked', 'Unqualified fixture: GET /rest/v1/unqualified', 'WebSocket /blocked-socket'])
  report.safety.externalHttpWebSocketAndUnknownFixtureAborted = true
  await safetyContext.close()
  const scenarios = [
    ...[390, 900, 1440, 360].map(width => ({ name: `admin-${width}-sidebar-on`, kind: 'admin', width, sidebar: true, dark: width === 1440 })),
    { name: 'limited-390', kind: 'limited', width: 390, sidebar: true },
    { name: 'retry-900', kind: 'retry', width: 900, sidebar: true },
    { name: 'inactive-360', kind: 'inactive', width: 360, sidebar: true },
    { name: 'signedout-360', kind: 'signedout', width: 360, sidebar: true },
    { name: 'admin-1440-sidebar-off', kind: 'admin', width: 1440, sidebar: false },
    ...[390, 900, 1440].map(width => ({ name: `dashboard-error-${width}`, kind: 'dashboard-error', errorGroup: width === 900 ? 'sales' : 'overview', width, sidebar: true })),
  ]
  for (const scenario of scenarios) {
    currentDist = scenario.sidebar ? distOn : distOff
    await runScenario(origin, scenario)
    console.log(`${scenario.name}: ${report.scenarios.at(-1).status}`)
  }
  const changed = execFileSync('git', ['ls-files', '--modified', '--others', '--exclude-standard'], { cwd: root, encoding: 'utf8' }).trim().split(/\r?\n/).filter(Boolean)
  report.dirtyFileHashes = Object.fromEntries(await Promise.all(changed.map(async path => [path, createHash('sha256').update(await readFile(resolve(root, path))).digest('hex')])))
  report.status = report.scenarios.every(scenario => scenario.status === 'PASS') ? 'PASS' : 'FAIL'
}

try { await runBaseline() }
catch (error) {
  report.status = 'HARNESS_FAILURE'
  report.failure = error.message
} finally {
  report.cleanup.errors = []
  try { await browser?.close() } catch { report.cleanup.errors.push('browser.close failed') }
  try { await browserServer?.close() } catch { report.cleanup.errors.push('browserServer.close failed') }
  report.cleanup.browserExited = browserServer ? browserServer.process().exitCode !== null : 'not_started'
  if (server?.listening) {
    try {
      await new Promise((resolveClose, reject) => server.close(error => error ? reject(error) : resolveClose()))
      report.cleanup.httpListenerRetired = !(await portOpen(Number(options.port ?? 5197)))
    } catch { report.cleanup.errors.push('HTTP server retirement failed') }
  } else report.cleanup.httpListenerRetired = 'not_started'
  if (runDirectory) await writeFile(resolve(runDirectory, 'report.json'), JSON.stringify(report, null, 2))
  console.log(JSON.stringify({ status: report.status, browser: report.browser, runDirectory, cleanup: report.cleanup }))
  process.exitCode = report.status === 'PASS' && report.cleanup.browserExited && report.cleanup.httpListenerRetired && report.cleanup.errors.length === 0 ? 0 : 1
}
