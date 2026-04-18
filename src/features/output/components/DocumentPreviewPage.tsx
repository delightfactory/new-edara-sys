import React, { useCallback, useEffect, useRef, useState } from 'react';
import { getDocumentDefinition, isDocumentKind } from '../definitions/document-registry';
import { CanonicalDocument } from '../models/canonical-document';
import { PaperProfile, paperProfiles } from '../paper-profiles/paper-profiles';
import { browserPrintService } from '../services/browser-print-service';
import { DocumentRenderer } from '../renderers/DocumentRenderer';
import { DocumentDefinition } from '../definitions/document-definition';
import { resolveEnvironmentLocale } from '../utils/locale-resolver';
import { PaperProfileId } from '../core/output-types';
import { openPreviewPopup, collectCurrentUrlParams } from '../services/open-preview-popup';
import {
  CURRENT_PLATFORM,
  isThermalProfile,
  resolveOutputCapability,
} from '../core/platform-capabilities';

/* ═══════════════════════════════════════════════════════════════════
   DocumentPreviewPage
   ───────────────────────────────────────────────────────────────────
   Screen preview vs Print surface:
   - Screen: full-width, mobile-first, no desktop paper-stage on mobile
   - Print:  @page + CSS rules in print-thermal.css enforce physical size

   Platform-aware:
   - data-platform attribute drives CSS/JS decisions
   - Capability gating hides unavailable actions (iOS: print-only)

   Auto-print readiness:
   - Triggered only after document is committed + not loading/rebuilding
   - browserPrintService uses fonts.ready + double-rAF (no blind timer)
   ═══════════════════════════════════════════════════════════════════ */

interface DocumentPreviewPageProps {
  kind: string;
  entityId: string;
}

interface CommittedState {
  profile: PaperProfile;
  doc: CanonicalDocument;
}

// ── Document title / PDF filename ────────────────────────────────────
// Uses the document's own date (issuedAt) as the primary date component.
// Falls back to today only if the document has no date — making the
// saved PDF filename meaningful and professionally consistent.
function buildDocTitle(doc: CanonicalDocument): string {
  const parts: string[] = [];
  if (doc.title)  parts.push(doc.title);
  if (doc.number) parts.push(doc.number);
  // Prefer document date; fall back to wall-clock today.
  const dateStr = doc.issuedAt ?? new Date().toISOString().split('T')[0];
  parts.push(dateStr);
  return parts.join(' — ');
}

// SVG icon components (no emoji as primary UI element)
const PrintIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <polyline points="6 9 6 2 18 2 18 9"/>
    <path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/>
    <rect x="6" y="14" width="12" height="8"/>
  </svg>
);

const PdfIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
    <polyline points="14 2 14 8 20 8"/>
    <line x1="16" y1="13" x2="8" y2="13"/>
    <line x1="16" y1="17" x2="8" y2="17"/>
    <polyline points="10 9 9 9 8 9"/>
  </svg>
);

export function DocumentPreviewPage({ kind, entityId }: DocumentPreviewPageProps) {
  const [committed, setCommitted]     = useState<CommittedState | null>(null);
  const [definition, setDefinition]   = useState<DocumentDefinition | null>(null);
  const [loading, setLoading]         = useState(true);
  const [rebuilding, setRebuilding]   = useState(false);
  const [rebuildError, setRebuildError] = useState<string | null>(null);
  const [fatalError, setFatalError]   = useState<string | null>(null);
  const [autoPrintFired, setAutoPrintFired] = useState(false);

  // __autoprint=1 → DocumentPreviewPage auto-prints after readiness
  const isAutoprint =
    new URLSearchParams(window.location.search).get('__autoprint') === '1';

  const buildTokenRef = useRef<number>(0);

  // ── Core build ──────────────────────────────────────────────────
  const buildDoc = useCallback(
    async (
      def: DocumentDefinition,
      paperProfileId: PaperProfileId,
      filters: Record<string, any>,
      token: number
    ): Promise<{ doc: CanonicalDocument; profile: PaperProfile } | null> => {
      const { locale: fallbackLocale, direction: fallbackDir } = resolveEnvironmentLocale();
      const builtDoc = await def.fetchAndBuild({
        entityId,
        locale: fallbackLocale,
        direction: fallbackDir,
        filters,
        paperProfileId,
      });

      if (token !== buildTokenRef.current) return null;
      return { doc: builtDoc, profile: paperProfiles[paperProfileId] };
    },
    [entityId]
  );

  // ── URL param helpers ───────────────────────────────────────────
  const getFilters = useCallback((): Record<string, any> => {
    const searchParams = new URLSearchParams(window.location.search);
    const filters: Record<string, any> = {};
    searchParams.forEach((val, key) => {
      if (key !== '__paper' && key !== '__autoprint') filters[key] = val;
    });
    return filters;
  }, []);

  const getRequestedPaperId = useCallback((): PaperProfileId | undefined => {
    const raw = new URLSearchParams(window.location.search).get('__paper');
    if (!raw) return undefined;
    return raw as PaperProfileId;
  }, []);

  // ── Initial load ────────────────────────────────────────────────
  useEffect(() => {
    async function initialFetch() {
      try {
        setLoading(true);
        setFatalError(null);
        if (!isDocumentKind(kind)) throw new Error(`Invalid document kind: ${kind}`);

        const def = getDocumentDefinition(kind);
        if (!def) throw new Error(`Document definition not registered: ${kind}`);
        setDefinition(def);

        // Paper priority:
        // 1. __paper URL param (explicit from caller)
        // 2. thermal-80mm if mobile + definition supports it
        // 3. definition.defaultPaper
        const requestedPaper = getRequestedPaperId();
        let initPaperId: PaperProfileId;
        const isMobile = window.innerWidth < 768;
        if (requestedPaper && def.supportedPapers.includes(requestedPaper)) {
          initPaperId = requestedPaper;
        } else if (isMobile && def.supportedPapers.includes('thermal-80mm')) {
          initPaperId = 'thermal-80mm';
        } else {
          initPaperId = def.defaultPaper;
        }

        const token = ++buildTokenRef.current;
        const result = await buildDoc(def, initPaperId, getFilters(), token);
        if (!result) return;
        setCommitted(result);
      } catch (err: any) {
        setFatalError(err.message);
      } finally {
        setLoading(false);
      }
    }
    initialFetch();
  }, [kind, entityId, buildDoc, getFilters, getRequestedPaperId]);

  // ── Document title (= PDF save-as filename) ─────────────────────
  useEffect(() => {
    if (!committed) return;
    document.title = buildDocTitle(committed.doc);
    return () => { document.title = 'EDARA'; };
  }, [committed]);

  // ── Add thermal-print class to body when profile is thermal ─────
  //    Used by print-thermal.css to enforce narrow @page margins
  useEffect(() => {
    if (!committed) return;
    const isThermal = isThermalProfile(committed.profile.id);
    if (isThermal) {
      document.body.classList.add('thermal-print');
    }
    return () => {
      document.body.classList.remove('thermal-print');
    };
  }, [committed]);

  // ── Rebuild on paper change ─────────────────────────────────────
  const handleProfileChange = useCallback(
    async (newProfileId: PaperProfileId) => {
      if (!definition) return;
      if (!paperProfiles[newProfileId]) return;

      const token = ++buildTokenRef.current;
      setRebuilding(true);
      setRebuildError(null);

      try {
        const result = await buildDoc(definition, newProfileId, getFilters(), token);
        if (!result) return;
        setCommitted(result);
      } catch (err: any) {
        setRebuildError(`فشل تغيير المقاس: ${err.message}`);
      } finally {
        if (token === buildTokenRef.current) setRebuilding(false);
      }
    },
    [definition, buildDoc, getFilters]
  );

  // ── Preview route class ─────────────────────────────────────────
  useEffect(() => {
    document.body.classList.add('is-preview-route');
    return () => { document.body.classList.remove('is-preview-route'); };
  }, []);

  // ── Auto-print — waits for committed state, no blind timer ──────
  useEffect(() => {
    if (!isAutoprint) return;
    if (autoPrintFired) return;
    if (!committed || loading || rebuilding) return;

    setAutoPrintFired(true);
    // browserPrintService.print() internally waits: fonts.ready → rAF → rAF → print()
    browserPrintService.print();
  }, [isAutoprint, autoPrintFired, committed, loading, rebuilding]);

  // ── Fatal states ────────────────────────────────────────────────
  if (loading) return (
    <div style={{ padding: '2rem', textAlign: 'center', direction: 'rtl', fontFamily: 'system-ui, sans-serif' }}>
      <div style={{
        display: 'inline-block', width: '32px', height: '32px', borderRadius: '50%',
        border: '3px solid #e0e0e0', borderTopColor: '#0055cc',
        animation: 'preview-spin 0.7s linear infinite', marginBottom: '12px',
      }} />
      <p style={{ color: '#555', margin: 0 }}>جاري تحضير المستند...</p>
      <style>{`@keyframes preview-spin { to { transform: rotate(360deg); } }`}</style>
    </div>
  );

  if (fatalError) return (
    <div style={{ color: '#c00', padding: '2rem', direction: 'rtl', fontWeight: 600, fontFamily: 'system-ui, sans-serif' }}>
      ⚠ {fatalError}
    </div>
  );

  if (!committed) return null;

  const { profile, doc } = committed;
  const containerDir    = doc.direction;
  const displayProfileId = profile.id;
  const isThermal       = isThermalProfile(profile.id);
  const printBusy       = rebuilding || (isAutoprint && !autoPrintFired);
  const platform        = CURRENT_PLATFORM;

  // ── Capability check for pdf-download button ────────────────────
  const pdfDownloadCap = resolveOutputCapability('pdf-download', platform, profile.id);
  const showPdfBtn     = pdfDownloadCap.visible;

  // ── Background: desktop gets paper-stage gray; mobile/thermal gets white ──
  const pageBackground = isThermal || window.innerWidth < 768 ? '#f5f5f5' : '#d8d8d8';

  return (
    <div
      style={{ background: pageBackground, minHeight: '100vh', padding: '0', direction: containerDir }}
      data-platform={platform}
      data-paper={profile.id}
      data-preview-mode={isThermal ? 'thermal' : 'standard'}
    >
      {/* ── Action Bar ─────────────────────────────────────────────── */}
      <div className="preview-action-bar" dir="rtl" role="toolbar" aria-label="أدوات المستند">

        {/* Left: paper selector + status */}
        <div className="pab-left">
          <label htmlFor="paper-profile-select" className="pab-select-label">الحجم:</label>
          <select
            id="paper-profile-select"
            value={displayProfileId}
            disabled={rebuilding}
            onChange={(e) => handleProfileChange(e.target.value as PaperProfileId)}
            className="pab-select"
            aria-label="حجم الورق"
          >
            {definition?.supportedPapers.map(pid => (
              <option key={pid} value={pid}>{paperProfiles[pid].name}</option>
            ))}
          </select>

          {rebuilding && (
            <span className="pab-status" role="status" aria-live="polite">
              <span className="pab-spinner" aria-hidden="true" />
              <span className="pab-status-text">إعادة بناء...</span>
            </span>
          )}

          {isAutoprint && !autoPrintFired && !rebuilding && (
            <span className="pab-status pab-status--blue" role="status" aria-live="polite">
              <span className="pab-spinner pab-spinner--blue" aria-hidden="true" />
              <span className="pab-status-text">جاري التحضير...</span>
            </span>
          )}

          {rebuildError && !rebuilding && (
            <span
              className="pab-error"
              onClick={() => setRebuildError(null)}
              role="alert"
              title="انقر لإغلاق"
            >
              ⚠ {rebuildError}
            </span>
          )}
        </div>

        {/* Right: action buttons */}
        <div className="pab-right">
          {/* Print button — always shown (works on all platforms) */}
          <button
            id="btn-print"
            onClick={() => browserPrintService.print()}
            disabled={printBusy}
            className={`pab-btn pab-btn--primary${printBusy ? ' pab-btn--busy' : ''}`}
            aria-label="طباعة"
          >
            <PrintIcon />
            <span className="pab-btn-label">طباعة</span>
          </button>

          {/* PDF Download — only shown when platform supports it */}
          {showPdfBtn && (
            <button
              id="btn-pdf-download"
              onClick={() => {
                // SYNC — openPreviewPopup must be the first call here
                // (no await, no setState before this line).
                // collectCurrentUrlParams() carries forward all active filters
                // (e.g. dateFrom/dateTo for account-statement) into the PDF popup.
                const popup = openPreviewPopup({
                  kind,
                  entityId,
                  paperProfileId: profile.id,
                  baseParams: collectCurrentUrlParams(),
                  autoprint: true,
                });
                if (!popup) {
                  alert('تعذّر فتح نافذة PDF. السماح بالنوافذ المنبثقة مطلوب.');
                }
              }}
              disabled={printBusy}
              className={`pab-btn pab-btn--secondary${printBusy ? ' pab-btn--busy' : ''}`}
              aria-label="حفظ كـ PDF"
            >
              <PdfIcon />
              <span className="pab-btn-label">حفظ PDF</span>
            </button>
          )}
        </div>
      </div>

      {/* ── Inline styles ────────────────────────────────────────────── */}
      <style>
        {`
          @keyframes preview-spin { to { transform: rotate(360deg); } }

          /* ─── Action Bar base ──────────────────────────────────────── */
          .preview-action-bar {
            position: fixed; top: 0; left: 0; right: 0;
            background: rgba(255,255,255,0.97);
            backdrop-filter: blur(10px);
            -webkit-backdrop-filter: blur(10px);
            box-shadow: 0 1px 0 rgba(0,0,0,0.08), 0 2px 8px rgba(0,0,0,0.05);
            z-index: 1000;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 8px;
            padding: 8px 16px;
            min-height: 52px;
            box-sizing: border-box;
            /* iOS safe-area support */
            padding-top: max(8px, env(safe-area-inset-top));
            padding-right: max(16px, env(safe-area-inset-right));
            padding-left: max(16px, env(safe-area-inset-left));
          }

          .pab-left  { display: flex; align-items: center; gap: 8px; flex: 1 1 auto; min-width: 0; overflow: hidden; }
          .pab-right { display: flex; align-items: center; gap: 6px; flex-shrink: 0; }

          /* Select label — hidden on narrow screens */
          .pab-select-label {
            font-size: 12px; color: #666; white-space: nowrap; flex-shrink: 0;
          }

          /* Paper selector */
          .pab-select {
            padding: 6px 10px;
            border: 1px solid #d0d0d0;
            border-radius: 6px;
            font-family: inherit;
            font-size: 13px;
            background: white;
            color: #333;
            cursor: pointer;
            /* Never truncate to the point of losing meaning */
            max-width: 180px;
            min-width: 100px;
          }
          .pab-select:disabled { opacity: 0.5; cursor: not-allowed; }

          /* Status */
          .pab-status {
            display: flex; align-items: center; gap: 5px;
            font-size: 12px; color: #666;
            white-space: nowrap; flex-shrink: 1; min-width: 0; overflow: hidden;
          }
          .pab-status--blue { color: #0055cc; }
          .pab-status-text  { overflow: hidden; text-overflow: ellipsis; }

          /* Spinner */
          .pab-spinner {
            display: inline-block; width: 10px; height: 10px;
            border-radius: 50%;
            border: 2px solid #ccc; border-top-color: #666;
            animation: preview-spin 0.7s linear infinite;
            flex-shrink: 0;
          }
          .pab-spinner--blue { border-color: #93b8f5; border-top-color: #0055cc; }

          /* Error */
          .pab-error {
            font-size: 11px; color: #c00; cursor: pointer;
            padding: 3px 7px; background: #fff5f5;
            border-radius: 4px; border: 1px solid #fca5a5;
            white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
            max-width: 160px; flex-shrink: 1;
          }

          /* ─── Action Buttons ───────────────────────────────────────── */
          .pab-btn {
            display: flex; align-items: center; gap: 6px;
            padding: 8px 14px;
            border: none; border-radius: 7px;
            cursor: pointer; font-weight: 600; font-size: 13px;
            font-family: inherit;
            transition: background 0.15s, opacity 0.15s;
            white-space: nowrap;
            /* Minimum touch target 44×44px */
            min-height: 40px;
            min-width: 40px;
          }
          .pab-btn--primary {
            background: #0055cc;
            color: white;
          }
          .pab-btn--primary:not(:disabled):hover { background: #0044aa; }
          .pab-btn--secondary {
            background: #f0f0f0;
            color: #333;
            border: 1px solid #d0d0d0;
          }
          .pab-btn--secondary:not(:disabled):hover { background: #e4e4e4; }
          .pab-btn--busy { opacity: 0.5; cursor: not-allowed; }

          /* ─── Tablet / large mobile (480–767px) ────────────────────── */
          @media (max-width: 767px) and (min-width: 481px) {
            .preview-action-bar { padding: 7px 12px; min-height: 50px; }
            .pab-select { max-width: 140px; font-size: 12px; }
            .pab-select-label { display: none; }
            .pab-btn { padding: 8px 12px; font-size: 12px; }
          }

          /* ─── Narrow mobile (≤ 480px) ─────────────────────────────── */
          @media (max-width: 480px) {
            .preview-action-bar {
              padding: 6px 10px;
              min-height: 48px;
              /* Stack: left goes below if overflow, right stays put */
              flex-wrap: nowrap;
            }
            .pab-select-label { display: none; }
            .pab-select {
              font-size: 11px; padding: 5px 6px;
              max-width: 110px; min-width: 80px;
            }
            /* Status text hidden on very narrow — keep spinner */
            .pab-status-text { display: none; }
            /* Buttons: icon only, but minimum viable touch target */
            .pab-btn {
              padding: 8px 10px;
              font-size: 14px;
              min-height: 40px;
              min-width: 40px;
              border-radius: 8px;
            }
            .pab-btn-label { display: none; }
          }

          /* ─── Print suppression ─────────────────────────────────────── */
          @media print {
            .preview-action-bar { display: none !important; }
            .stt-btn            { display: none !important; }
            [class*="fab"]      { display: none !important; }
            [class*="toast"]    { display: none !important; }
            [class*="Toaster"]  { display: none !important; }
            nav, aside          { display: none !important; }
            body, html          { background: white !important; }
            .output-print-root  { margin-top: 0 !important; opacity: 1 !important; }

            /* Physical page size from profile */
            @page {
              size: ${profile.size === 'auto' ? 'auto' : `${(profile.size as {width:string;height:string}).width} ${(profile.size as {width:string;height:string}).height}`};
              margin: ${profile.margins.top} ${profile.margins.right} ${profile.margins.bottom} ${profile.margins.left};
            }
          }

          /* ─── Output root CSS vars (profile geometry) ───────────────── */
          .output-print-root {
            --profile-width:  ${profile.size === 'auto' ? '80mm' : (profile.size as {width:string;height:string}).width};
            --profile-height: ${profile.size === 'auto' ? 'auto' : (profile.size as {width:string;height:string}).height};
            --profile-pad-t:  ${profile.margins.top};
            --profile-pad-r:  ${profile.margins.right};
            --profile-pad-b:  ${profile.margins.bottom};
            --profile-pad-l:  ${profile.margins.left};
          }

          /* ─── Top offset for action bar ─────────────────────────────── */
          .output-root-offset { margin-top: 56px; }
          @media (max-width: 480px) { .output-root-offset { margin-top: 52px; } }

          /* ─── Mobile preview surface ────────────────────────────────── */
          /* On mobile, the receipt fills the screen comfortably */
          @media (max-width: 767px) {
            /* Thermal: the receipt card is centered with breathing room */
            [data-preview-mode="thermal"] .output-print-root {
              padding: 12px 16px;
            }
            /* Standard: just top offset, document fills width naturally */
            [data-preview-mode="standard"] .output-print-root {
              padding: 0;
            }
          }

          /* Desktop: classic paper-stage centering */
          @media (min-width: 768px) {
            [data-preview-mode="standard"] .output-print-root {
              max-width: 900px;
              margin-left: auto;
              margin-right: auto;
              padding: 20px;
            }
            [data-preview-mode="thermal"] .output-print-root {
              padding: 20px;
            }
          }
        `}
      </style>

      {/* ── Printable Surface ──────────────────────────────────────────── */}
      <div
        className="output-print-root output-root-offset"
        data-output-ready={committed && !loading && !rebuilding ? 'true' : undefined}
        data-paper={profile.id}
        style={{
          opacity: rebuilding ? 0.4 : 1,
          transition: 'opacity 0.15s',
        }}
      >
        <DocumentRenderer document={doc} profile={profile} />
      </div>
    </div>
  );
}
