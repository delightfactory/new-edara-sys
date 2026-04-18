/**
 * useDocumentOutput — central hook for all document output actions.
 *
 * All popup/URL logic is delegated to openPreviewPopup() — no
 * duplicated window.open() or URLSearchParams here.
 *
 * ── Sync contract ───────────────────────────────────────────────────
 * triggerPreview and triggerPdfDownload call openPreviewPopup()
 * synchronously inside the useCallback — preserving the user gesture
 * chain required by browsers (especially iOS Safari).
 *
 * ── Platform gating ─────────────────────────────────────────────────
 * Capabilities are resolved by resolveAllCapabilities() which applies
 * platform × paperProfile × outputKind rules. Components must only
 * render buttons whose capability is visible=true.
 */
import { useState, useCallback, useMemo } from 'react';
import { getDocumentDefinition } from '../definitions/document-registry';
import { paperProfiles } from '../paper-profiles/paper-profiles';
import { DocumentKind, OutputKind, PaperProfileId } from '../core/output-types';
import { CURRENT_PLATFORM, resolveAllCapabilities } from '../core/platform-capabilities';
import { openPreviewPopup } from '../services/open-preview-popup';

export interface DocumentCapability {
  kind: OutputKind;
  allowed: boolean;
  visible: boolean;
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
  triggerPdfDownload: () => void;  // sync — must be called directly in onClick
  triggerPrint: () => void;          // same-window print (always safe, incl. iOS)
  clearError: () => void;
}

export function useDocumentOutput({
  kind,
  entityId,
  paperProfileId,
  params,
}: UseDocumentOutputOptions): UseDocumentOutputReturn {
  const [busy, setBusy]   = useState(false);
  const [error, setError] = useState<string | null>(null);

  const def = getDocumentDefinition(kind);

  // ── Resolve paper profile ─────────────────────────────────────────
  const resolvedPaperId: PaperProfileId =
    paperProfileId ?? (def?.defaultPaper ?? 'a4-portrait');

  // Validate profile exists at hook init time (caught early, not at click time)
  void paperProfiles[resolvedPaperId];

  // ── Platform-aware capabilities ───────────────────────────────────
  const capabilities = useMemo<DocumentCapability[]>(() => {
    const supported = def?.supportedOutputs ?? [];
    return resolveAllCapabilities(
      supported as OutputKind[],
      CURRENT_PLATFORM,
      resolvedPaperId,
    ) as DocumentCapability[];
  }, [def, resolvedPaperId]);

  // ── Preview (opens preview tab — no autoprint) ────────────────────
  // SYNC: openPreviewPopup called immediately in gesture frame.
  const triggerPreview = useCallback(() => {
    const popup = openPreviewPopup({
      kind,
      entityId,
      paperProfileId: resolvedPaperId,
      baseParams: params ?? {},
      autoprint: false,
    });
    if (!popup) {
      setError('تعذّر فتح نافذة المعاينة. تأكد من السماح بالنوافذ المنبثقة.');
    }
  }, [kind, entityId, resolvedPaperId, params]);

  // ── PDF Download (preview + autoprint) ───────────────────────────
  // SYNC: openPreviewPopup called first — before any setState or async.
  // The "busy" state is UI-only feedback; it does NOT gate the popup.
  const triggerPdfDownload = useCallback(() => {
    if (!def) {
      setError('تعريف المستند غير موجود');
      return;
    }

    // Step 1 — SYNC: open popup immediately (user gesture frame preserved)
    const popup = openPreviewPopup({
      kind,
      entityId,
      paperProfileId: resolvedPaperId,
      baseParams: params ?? {},
      autoprint: true,
    });

    if (!popup) {
      setError(
        'لم يتمكن المتصفح من فتح نافذة الطباعة. تأكد من السماح بالنوافذ المنبثقة.'
      );
      return;
    }

    // Step 2 — UI-only busy indicator.
    // The popup manages its own lifecycle; this timer is purely cosmetic
    // so the button feels responsive. It is NOT a readiness gate.
    setBusy(true);
    setTimeout(() => setBusy(false), 2000);   // UI-only, not a readiness gate
  }, [def, kind, entityId, resolvedPaperId, params]);

  // ── Same-window print — works on all platforms including iOS ──────
  const triggerPrint = useCallback(() => {
    import('../services/browser-print-service').then(({ browserPrintService }) => {
      browserPrintService.print().catch(() => setError('فشل تشغيل الطباعة'));
    });
  }, []);

  const clearError = useCallback(() => setError(null), []);

  return { capabilities, busy, error, triggerPreview, triggerPdfDownload, triggerPrint, clearError };
}
