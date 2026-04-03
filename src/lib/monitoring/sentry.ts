/**
 * sentry.ts
 * Sentry initialization and helpers.
 *
 * DSN is read from VITE_SENTRY_DSN environment variable.
 * If the variable is absent (local dev without Sentry), all calls are no-ops.
 *
 * Usage:
 *   - Call initSentry() once in main.tsx before ReactDOM.render
 *   - Call captureError(err) from ErrorBoundary and service catch blocks
 *   - Call trackAuthFailure(reason) from auth.ts for sign-in / session failures
 */
import * as Sentry from '@sentry/react'

const DSN = import.meta.env.VITE_SENTRY_DSN as string | undefined
const ENV = import.meta.env.MODE ?? 'development'

export function initSentry() {
  if (!DSN) return // no-op in local dev if DSN not set

  Sentry.init({
    dsn: DSN,
    environment: ENV,
    // Capture 100% of transactions in production; tune down if volume is high
    tracesSampleRate: ENV === 'production' ? 0.2 : 1.0,
    // Ignore noisy browser extension errors
    ignoreErrors: [
      'ResizeObserver loop limit exceeded',
      'ResizeObserver loop completed with undelivered notifications',
    ],
    beforeSend(event) {
      // Strip PII from breadcrumbs URLs (query strings may contain tokens)
      if (Array.isArray(event.breadcrumbs)) {
        event.breadcrumbs = event.breadcrumbs.map((b) => {
          if (b.data?.url) {
            try {
              const u = new URL(b.data.url)
              u.search = ''
              b.data.url = u.toString()
            } catch { /* not a valid URL, leave as-is */ }
          }
          return b
        })
      }
      return event
    },
  })
}

export function captureError(error: unknown, context?: Record<string, unknown>) {
  if (!DSN) {
    console.error('[Sentry no-op]', error, context)
    return
  }
  Sentry.withScope(scope => {
    if (context) scope.setExtras(context)
    Sentry.captureException(error)
  })
}

export function trackAuthFailure(reason: string, extra?: Record<string, unknown>) {
  if (!DSN) {
    console.warn('[Sentry no-op] auth failure:', reason, extra)
    return
  }
  Sentry.withScope(scope => {
    scope.setTag('auth_failure', reason)
    if (extra) scope.setExtras(extra)
    Sentry.captureMessage(`Auth failure: ${reason}`, 'warning')
  })
}

export function setUserContext(userId: string | null) {
  if (!DSN) return
  if (userId) {
    Sentry.setUser({ id: userId })
  } else {
    Sentry.setUser(null)
  }
}
