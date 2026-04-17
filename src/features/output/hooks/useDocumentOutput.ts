/**
 * useDocumentOutput — central hook for all document output actions.
 *
 * Architecture (corrected):
 * - preview/print: opens DocumentPreviewPage in new tab (always correct)
 * - pdf-download: lazy-loads pdf-download-service and passes the FULL preview URL
 *   parameters (kind, entityId, params, paperProfileId) — no CanonicalDocument
 *   is built here to avoid data duplication; DocumentPreviewPage handles building.
 *
 * Capability gating: only outputs that are both declared in the definition
 * AND currently implemented end-to-end are exposed.
 */
import { useState, useCallback } from 'react';
import { getDocumentDefinition } from '../definitions/document-registry';
import { paperProfiles } from '../paper-profiles/paper-profiles';
import { DocumentKind, OutputKind, PaperProfileId } from '../core/output-types';

/** Actions that are currently implemented end-to-end */
const IMPLEMENTED_OUTPUTS: Set<OutputKind> = new Set(['print', 'pdf-browser', 'pdf-download']);

export interface DocumentCapability {
  kind: OutputKind;
  available: boolean;
  label: string;
}

export interface UseDocumentOutputOptions {
  kind: DocumentKind;
  entityId: string;
  paperProfileId?: PaperProfileId;
  params?: Record<string, string>;
}

export interface UseDocumentOutputReturn {
  capabilities: DocumentCapability[];
  busy: boolean;
  error: string | null;
  triggerPreview: () => void;
  triggerPdfDownload: () => Promise<void>;
  clearError: () => void;
}

export function useDocumentOutput({
  kind,
  entityId,
  paperProfileId,
  params,
}: UseDocumentOutputOptions): UseDocumentOutputReturn {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const def = getDocumentDefinition(kind);

  // ── Capabilities ─────────────────────────────────────────────────
  const capabilities: DocumentCapability[] = (def?.supportedOutputs ?? [])
    .filter((o): o is OutputKind => IMPLEMENTED_OUTPUTS.has(o))
    .map(o => ({ kind: o, available: true, label: outputLabel(o) }));

  // ── Resolve paper profile ─────────────────────────────────────────
  const resolvedPaperId: PaperProfileId = paperProfileId ?? (def?.defaultPaper ?? 'a4-portrait');
  const resolvedProfile = paperProfiles[resolvedPaperId];

  // ── Preview / Print ──────────────────────────────────────────────
  // Passes params (+ paperProfileId via __paper) so DocumentPreviewPage
  // can rebuild the correct variant when the tab opens.
  const triggerPreview = useCallback(() => {
    const urlParams = new URLSearchParams(params ?? {});
    if (paperProfileId) urlParams.set('__paper', paperProfileId);
    const query = urlParams.toString();
    const url = `/documents/${kind}/${entityId}/preview${query ? '?' + query : ''}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  }, [kind, entityId, params, paperProfileId]);

  // ── PDF Download (lazy, popup-based, auto-print) ──────────────────
  const triggerPdfDownload = useCallback(async () => {
    if (!def) {
      setError('تعريف المستند غير موجود');
      return;
    }

    setBusy(true);
    setError(null);

    try {
      // Lazy-load keeps this out of the main bundle
      const { generateAndDownloadPdf } = await import('../services/pdf-download-service');
      await generateAndDownloadPdf({
        kind,
        entityId,
        paperProfileId: resolvedPaperId,
        params: params ?? {},
      });
    } catch (err: any) {
      setError(err.message || 'فشل فتح نافذة الحفظ');
    } finally {
      setBusy(false);
    }
  }, [def, kind, entityId, resolvedPaperId, params]);

  const clearError = useCallback(() => setError(null), []);

  return { capabilities, busy, error, triggerPreview, triggerPdfDownload, clearError };
}

function outputLabel(kind: OutputKind): string {
  switch (kind) {
    case 'print':        return 'طباعة';
    case 'pdf-browser':  return 'معاينة / طباعة';
    case 'pdf-download': return 'حفظ كـ PDF';
    default: return kind;
  }
}
