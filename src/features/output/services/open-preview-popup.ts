/**
 * open-preview-popup.ts
 *
 * Single source of truth for building the preview/autoprint URL and
 * opening the popup window synchronously.
 *
 * ALL callers (useDocumentOutput, DocumentPreviewPage, DocumentActions)
 * must use this function — no duplicated window.open() logic elsewhere.
 *
 * ── Sync contract ──────────────────────────────────────────────────
 * This function MUST be called synchronously within a user gesture
 * handler (onClick). Do NOT call it after any `await`.
 *
 * ── URL building rules ─────────────────────────────────────────────
 * 1. Start from `baseParams` (caller-supplied existing query params,
 *    e.g. from current URL filters for account-statement).
 * 2. Always override __paper and __autoprint regardless of baseParams.
 * 3. This ensures account-statement filters (dateFrom, dateTo, etc.)
 *    are preserved across preview and PDF-download trips.
 */

export interface PreviewPopupOptions {
  kind: string;
  entityId: string;
  paperProfileId: string;
  /** Existing query params to carry forward (e.g. URL filters). */
  baseParams?: Record<string, string>;
  /** If true, adds __autoprint=1 (auto-triggers print on load). */
  autoprint?: boolean;
}

/**
 * Builds the preview URL and opens a popup synchronously.
 * Returns the Window reference, or null if blocked.
 */
export function openPreviewPopup(options: PreviewPopupOptions): Window | null {
  const { kind, entityId, paperProfileId, baseParams, autoprint = false } = options;

  // Build from existing params first, then stamp our control params.
  const urlParams = new URLSearchParams(baseParams ?? {});
  urlParams.set('__paper', paperProfileId);
  if (autoprint) {
    urlParams.set('__autoprint', '1');
  } else {
    urlParams.delete('__autoprint'); // ensure clean preview URL
  }

  const url = `/documents/${kind}/${entityId}/preview?${urlParams.toString()}`;

  return window.open(url, '_blank', 'noopener,noreferrer');
}

/**
 * Collects the *current* window's query params, stripping internal ones.
 * Useful inside DocumentPreviewPage where we want to forward existing
 * filters to a new PDF popup.
 */
export function collectCurrentUrlParams(): Record<string, string> {
  const result: Record<string, string> = {};
  const searchParams = new URLSearchParams(window.location.search);
  searchParams.forEach((val, key) => {
    if (key !== '__paper' && key !== '__autoprint') {
      result[key] = val;
    }
  });
  return result;
}
