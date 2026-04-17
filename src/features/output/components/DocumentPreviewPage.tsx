import React, { useCallback, useEffect, useRef, useState } from 'react';
import { getDocumentDefinition, isDocumentKind } from '../definitions/document-registry';
import { CanonicalDocument } from '../models/canonical-document';
import { PaperProfile, paperProfiles } from '../paper-profiles/paper-profiles';
import { browserPrintService } from '../services/browser-print-service';
import { DocumentRenderer } from '../renderers/DocumentRenderer';
import { DocumentDefinition } from '../definitions/document-definition';
import { resolveEnvironmentLocale } from '../utils/locale-resolver';
import { PaperProfileId } from '../core/output-types';

interface DocumentPreviewPageProps {
  kind: string;
  entityId: string;
}

interface CommittedState {
  profile: PaperProfile;
  doc: CanonicalDocument;
}

// ── Mobile detection ─────────────────────────────────────────────────────────
// Used ONCE on mount — avoids re-renders from resize events.
function isMobileViewport(): boolean {
  return typeof window !== 'undefined' && window.innerWidth < 768;
}

// ── Document title / PDF filename builder ────────────────────────────────────
// The browser uses <title> as the default filename when saving to PDF.
// Format: «عنوان المستند — رقم التسلسل — التاريخ»
function buildDocTitle(doc: CanonicalDocument): string {
  const parts: string[] = [];
  if (doc.title) parts.push(doc.title);
  if (doc.number) parts.push(doc.number);
  // Short ISO date  YYYY-MM-DD
  const today = new Date().toISOString().split('T')[0];
  parts.push(today);
  return parts.join(' — ');
}

export function DocumentPreviewPage({ kind, entityId }: DocumentPreviewPageProps) {
  const [committed, setCommitted] = useState<CommittedState | null>(null);
  const [definition, setDefinition] = useState<DocumentDefinition | null>(null);
  const [loading, setLoading] = useState(true);
  const [rebuilding, setRebuilding] = useState(false);
  const [rebuildError, setRebuildError] = useState<string | null>(null);
  const [fatalError, setFatalError] = useState<string | null>(null);
  const [autoPrintFired, setAutoPrintFired] = useState(false);

  // Detect __autoprint=1 flag passed by pdf-download-service
  const isAutoprint = new URLSearchParams(window.location.search).get('__autoprint') === '1';

  // ── Race-condition guard ──────────────────────────────────────────
  const buildTokenRef = useRef<number>(0);

  // ── Core build function ──────────────────────────────────────────
  const buildDoc = useCallback(async (
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
  }, [entityId]);

  // ── Parse URL filters — strips internal params ───────────────────
  const getFilters = useCallback((): Record<string, any> => {
    const searchParams = new URLSearchParams(window.location.search);
    const filters: Record<string, any> = {};
    searchParams.forEach((val, key) => {
      if (key !== '__paper' && key !== '__autoprint') filters[key] = val;
    });
    return filters;
  }, []);

  // ── Read __paper query param ─────────────────────────────────────
  const getRequestedPaperId = useCallback((): PaperProfileId | undefined => {
    const raw = new URLSearchParams(window.location.search).get('__paper');
    if (!raw) return undefined;
    return raw as PaperProfileId;
  }, []);

  // ── Initial load ─────────────────────────────────────────────────
  useEffect(() => {
    async function initialFetch() {
      try {
        setLoading(true);
        setFatalError(null);
        if (!isDocumentKind(kind)) throw new Error(`Invalid document kind: ${kind}`);

        const def = getDocumentDefinition(kind);
        if (!def) throw new Error(`Document definition not registered: ${kind}`);

        setDefinition(def);

        // Priority order for initial paper:
        // 1. __paper URL param (set by triggerPreview / pdf-download)
        // 2. thermal-80mm if on mobile AND definition supports it
        // 3. definition.defaultPaper
        const requestedPaper = getRequestedPaperId();
        let initPaperId: PaperProfileId;
        if (requestedPaper && def.supportedPapers.includes(requestedPaper)) {
          initPaperId = requestedPaper;
        } else if (isMobileViewport() && def.supportedPapers.includes('thermal-80mm')) {
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

  // ── Dynamic document.title = PDF filename ────────────────────────
  // The browser uses <title> as the default filename in Save-as-PDF dialog.
  useEffect(() => {
    if (!committed) return;
    const title = buildDocTitle(committed.doc);
    document.title = title;
    // Restore generic title on unmount
    return () => { document.title = 'EDARA'; };
  }, [committed]);

  // ── Rebuild on paper selection change ────────────────────────────
  const handleProfileChange = useCallback(async (newProfileId: PaperProfileId) => {
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
  }, [definition, buildDoc, getFilters]);

  // ── Preview route class ──────────────────────────────────────────
  useEffect(() => {
    document.body.classList.add('is-preview-route');
    return () => { document.body.classList.remove('is-preview-route'); };
  }, []);

  // ── Auto-print ───────────────────────────────────────────────────
  useEffect(() => {
    if (!isAutoprint) return;
    if (autoPrintFired) return;
    if (!committed || loading || rebuilding) return;

    setAutoPrintFired(true);
    const timer = setTimeout(() => { browserPrintService.print(); }, 400);
    return () => clearTimeout(timer);
  }, [isAutoprint, autoPrintFired, committed, loading, rebuilding]);

  // ── Fatal states ─────────────────────────────────────────────────
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
  const containerDir = doc.direction;
  const displayProfileId = profile.id;
  const printBusy = rebuilding || (isAutoprint && !autoPrintFired);

  return (
    <div style={{ background: '#d8d8d8', minHeight: '100vh', padding: '20px 0', direction: containerDir }}>

      {/* ── Action Bar ─────────────────────────────────────────────── */}
      <div className="preview-action-bar" dir="rtl">

        {/* Left cluster: paper selector + status */}
        <div className="pab-left">
          <select
            value={displayProfileId}
            disabled={rebuilding}
            onChange={(e) => handleProfileChange(e.target.value as PaperProfileId)}
            className="pab-select"
          >
            {definition?.supportedPapers.map(pid => (
              <option key={pid} value={pid}>{paperProfiles[pid].name}</option>
            ))}
          </select>

          {rebuilding && (
            <span className="pab-status">
              <span className="pab-spinner" />
              <span className="pab-status-text">جاري إعادة البناء...</span>
            </span>
          )}

          {isAutoprint && !autoPrintFired && !rebuilding && (
            <span className="pab-status pab-status--blue">
              <span className="pab-spinner pab-spinner--blue" />
              <span className="pab-status-text">جاري تحضير الطباعة...</span>
            </span>
          )}

          {rebuildError && !rebuilding && (
            <span className="pab-error" onClick={() => setRebuildError(null)} title="انقر لإغلاق">
              ⚠ {rebuildError}
            </span>
          )}
        </div>

        {/* Right cluster: print button */}
        <div className="pab-right">
          <button
            onClick={() => browserPrintService.print()}
            disabled={printBusy}
            className={`pab-print-btn${printBusy ? ' pab-print-btn--busy' : ''}`}
          >
            <span className="pab-print-icon">🖨</span>
            <span className="pab-print-label">طباعة / حفظ PDF</span>
          </button>
        </div>
      </div>

      {/* ── Styles ─────────────────────────────────────────────────── */}
      <style>
        {`
          @keyframes preview-spin { to { transform: rotate(360deg); } }

          /* ─── Action Bar ──────────────────────────────────────────── */
          .preview-action-bar {
            position: fixed; top: 0; left: 0; right: 0;
            background: rgba(255,255,255,0.96);
            backdrop-filter: blur(10px);
            -webkit-backdrop-filter: blur(10px);
            box-shadow: 0 1px 0 rgba(0,0,0,0.08), 0 2px 8px rgba(0,0,0,0.05);
            z-index: 1000;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 8px;
            padding: 8px 16px;
            min-height: 50px;
            box-sizing: border-box;
          }

          .pab-left  { display: flex; align-items: center; gap: 8px; flex-shrink: 1; min-width: 0; overflow: hidden; }
          .pab-right { display: flex; align-items: center; gap: 8px; flex-shrink: 0; }

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
            max-width: 160px;
          }
          .pab-select:disabled { opacity: 0.5; cursor: not-allowed; }

          /* Status */
          .pab-status {
            display: flex; align-items: center; gap: 5px;
            font-size: 12px; color: #666;
            white-space: nowrap;
          }
          .pab-status--blue { color: #0055cc; }

          .pab-status-text { display: inline; }

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
            max-width: 180px;
          }

          /* Print button */
          .pab-print-btn {
            display: flex; align-items: center; gap: 6px;
            padding: 8px 20px;
            background: #0055cc;
            color: white; border: none; border-radius: 6px;
            cursor: pointer; font-weight: bold; font-size: 13px;
            font-family: inherit;
            transition: background 0.15s, opacity 0.15s;
            white-space: nowrap;
          }
          .pab-print-btn--busy { background: #9ab4d8; cursor: not-allowed; }
          .pab-print-btn:not(:disabled):hover { background: #0044aa; }
          .pab-print-icon { font-size: 15px; line-height: 1; }

          /* ─── Mobile (≤ 480px) ────────────────────────────────────── */
          @media (max-width: 480px) {
            .preview-action-bar { padding: 6px 10px; min-height: 46px; gap: 6px; }

            .pab-select { font-size: 12px; padding: 5px 7px; max-width: 120px; }

            /* Hide status text on very small screens — keep spinner only */
            .pab-status-text { display: none; }

            /* Compact print button: icon only */
            .pab-print-label { display: none; }
            .pab-print-btn {
              padding: 8px 12px;
              border-radius: 8px;
              font-size: 16px;
            }
          }

          /* ─── Print suppression ───────────────────────────────────── */
          @media print {
            .preview-action-bar { display: none !important; }
            .stt-btn            { display: none !important; }
            [class*="fab"]      { display: none !important; }
            [class*="toast"]    { display: none !important; }
            [class*="Toaster"]  { display: none !important; }
            nav, aside          { display: none !important; }
            body, html          { background: white !important; }
            .output-print-root  { margin-top: 0 !important; opacity: 1 !important; }

            @page {
              size: ${profile.size === 'auto' ? 'auto' : `${profile.size.width} ${profile.size.height}`};
              margin: ${profile.margins.top} ${profile.margins.right} ${profile.margins.bottom} ${profile.margins.left};
            }
          }

          /* ─── Output root CSS vars ────────────────────────────────── */
          .output-print-root {
            --profile-width:  ${profile.size === 'auto' ? '100%' : profile.size.width};
            --profile-height: ${profile.size === 'auto' ? 'auto' : profile.size.height};
            --profile-pad-t:  ${profile.margins.top};
            --profile-pad-r:  ${profile.margins.right};
            --profile-pad-b:  ${profile.margins.bottom};
            --profile-pad-l:  ${profile.margins.left};
          }

          /* ─── Printable container top offset ─────────────────────── */
          .output-root-offset {
            margin-top: 54px;
          }
          @media (max-width: 480px) {
            .output-root-offset { margin-top: 50px; }
          }
        `}
      </style>

      {/* ── Printable Surface ──────────────────────────────────────── */}
      <div
        className="output-print-root output-root-offset"
        data-output-ready={committed && !loading && !rebuilding ? 'true' : undefined}
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
