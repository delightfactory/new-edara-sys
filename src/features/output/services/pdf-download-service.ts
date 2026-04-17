/**
 * pdf-download-service.ts
 *
 * Strategy: Open the existing preview page in a new popup window with
 * `__autoprint=true` in the URL. DocumentPreviewPage detects this flag and
 * calls window.print() automatically once data-output-ready is set.
 *
 * Why the previous hidden-iframe approach failed:
 * ───────────────────────────────────────────────
 * An iframe is a fresh browser context. It must:
 *   1. Re-download the full React + Vite bundle
 *   2. Re-establish the Supabase auth session
 *   3. Fetch all document data from the API
 *   4. Render the full component tree
 * All of this inside a hidden, resource-throttled iframe — which browsers
 * deprioritize. The 15 s hard timeout was hit consistently.
 *
 * The new approach reuses the full browser window lifecycle: the user sees
 * the document building in a real tab, and print fires automatically after
 * the readiness marker appears. It is identical to clicking "طباعة" manually
 * — just with auto-trigger instead of manual click.
 *
 * This module is LAZY-LOADED — never in the main bundle.
 */

export interface PdfDownloadOptions {
  kind: string;
  entityId: string;
  paperProfileId: string;
  params?: Record<string, string>;
  // pageSize / pageMargins no longer needed here — DocumentPreviewPage owns @page
}

export async function generateAndDownloadPdf(options: PdfDownloadOptions): Promise<void> {
  const { kind, entityId, paperProfileId, params } = options;

  const urlParams = new URLSearchParams(params ?? {});
  urlParams.set('__paper', paperProfileId);
  urlParams.set('__autoprint', '1');   // signals DocumentPreviewPage to auto-print

  const url = `/documents/${kind}/${entityId}/preview?${urlParams.toString()}`;

  // Open a real popup window — full browser context, full auth, full rendering
  const popup = window.open(url, '_blank', 'noopener,noreferrer');

  if (!popup) {
    throw new Error(
      'لم يتمكن المتصفح من فتح نافذة الطباعة. تأكد من السماح بالنوافذ المنبثقة لهذا الموقع.'
    );
  }

  // The hook resolves immediately — the popup handles its own lifecycle.
  // The user sees the document being built, then print fires automatically.
}
