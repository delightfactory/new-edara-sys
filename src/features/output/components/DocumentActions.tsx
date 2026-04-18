/**
 * DocumentActions — Output Hub Component
 *
 * Capability-driven: shows only outputs that are both declared by the
 * document definition AND allowed for the current platform (via
 * resolveAllCapabilities in useDocumentOutput).
 *
 * ── Semantic honesty ────────────────────────────────────────────────
 * Every button's label MUST match its actual behaviour:
 *
 *   "معاينة / طباعة"  → opens preview tab (user prints manually)
 *   "حفظ كـ PDF"      → opens preview tab with __autoprint=1
 *                        (browser print dialog fires automatically —
 *                         user selects "Save as PDF")
 *
 * On iOS, the gating layer removes pdf-download and pdf-browser from
 * capabilities, so only "print" (triggerPreview) is visible.
 * The button label reads "معاينة / طباعة" — not "حفظ PDF" —
 * because the actual behaviour IS preview → manual print.
 *
 * ── Print vs Preview on iOS ─────────────────────────────────────────
 * On iOS the 'print' capability is mapped to triggerPreview (popup).
 * This is correct: there is no same-window print path from the caller
 * context (DocumentActions lives inside the main app shell, not in
 * the isolated preview page). The preview tab opened is where the
 * user actually triggers print.
 *
 * If you need a same-window print (inside DocumentPreviewPage itself),
 * use browserPrintService.print() directly.
 */
import React, { useState, useRef, useEffect } from 'react';
import { DocumentKind, PaperProfileId } from '../core/output-types';
import { useDocumentOutput } from '../hooks/useDocumentOutput';

interface DocumentActionsProps {
  kind: DocumentKind;
  entityId: string;
  className?: string;
  paperProfileId?: PaperProfileId;
  params?: Record<string, string>;
  /** Compact mode: one icon button + dropdown for additional actions */
  compact?: boolean;
}

// ── Icons ────────────────────────────────────────────────────────────
const IconPrint = () => (
  <svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24"
    fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <polyline points="6 9 6 2 18 2 18 9" />
    <path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2" />
    <rect x="6" y="14" width="12" height="8" />
  </svg>
);

const IconDownload = () => (
  <svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24"
    fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
    <polyline points="7 10 12 15 17 10" />
    <line x1="12" y1="15" x2="12" y2="3" />
  </svg>
);

const IconChevron = () => (
  <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24"
    fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
    <polyline points="6 9 12 15 18 9" />
  </svg>
);

const IconSpinner = () => (
  <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24"
    fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
    style={{ animation: 'spin 0.8s linear infinite' }}>
    <path d="M21 12a9 9 0 1 1-6.219-8.56" />
  </svg>
);

export function DocumentActions({
  kind,
  entityId,
  className,
  paperProfileId,
  params,
  compact = false,
}: DocumentActionsProps) {
  const {
    capabilities,
    busy,
    error,
    triggerPreview,
    triggerPdfDownload,
    clearError,
  } = useDocumentOutput({ kind, entityId, paperProfileId, params });

  const [dropdownOpen, setDropdownOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close dropdown on outside click
  useEffect(() => {
    if (!dropdownOpen) return;
    const handler = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setDropdownOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [dropdownOpen]);

  // ── Derive visible capabilities ────────────────────────────────────
  // 'print' and 'pdf-browser' both map to triggerPreview (open preview tab).
  // They are semantically identical from the caller's perspective.
  const hasPrint       = capabilities.some(c => c.kind === 'pdf-browser' || c.kind === 'print');
  const hasPdfDownload = capabilities.some(c => c.kind === 'pdf-download');
  const hasMultiple    = hasPrint && hasPdfDownload;

  // ── Determine the correct label for the primary button ─────────────
  // If pdf-download is also available, the primary button is "معاينة / طباعة"
  // (to distinguish it from the "حفظ كـ PDF" option).
  // If pdf-download is NOT available (e.g. iOS), the label stays "معاينة / طباعة"
  // — which is an honest description of what the action does.
  // NOTE: We do NOT label it "حفظ PDF" on platforms where the popup will
  // just produce a print dialog.
  const primaryLabel = 'معاينة / طباعة';

  // ── No capabilities at all (shouldn't happen in practice) ──────────
  if (!hasPrint && !hasPdfDownload) return null;

  // ── Compact or multi-action: split button + dropdown ───────────────
  if (compact || hasMultiple) {
    return (
      <div
        ref={dropdownRef}
        className={`document-actions ${className || ''}`}
        style={{ position: 'relative', display: 'inline-block' }}
      >
        <div style={{ display: 'flex', alignItems: 'stretch' }}>
          {/* Primary: preview/print — opens preview tab */}
          {hasPrint && (
            <button
              onClick={triggerPreview}
              disabled={busy}
              className="btn btn-secondary"
              title="يفتح صفحة المعاينة — اطبع أو احفظ كـ PDF من هناك"
              style={{
                display: 'flex', alignItems: 'center', gap: '6px',
                padding: '6px 12px',
                borderRadius: hasMultiple ? '4px 0 0 4px' : '4px',
                borderInlineEnd: hasMultiple ? 'none' : undefined,
                fontSize: '13px',
              }}
            >
              {busy ? <IconSpinner /> : <IconPrint />}
              <span>{primaryLabel}</span>
            </button>
          )}

          {/* Dropdown toggle — only when pdf-download is also available */}
          {hasMultiple && (
            <button
              onClick={() => setDropdownOpen(v => !v)}
              disabled={busy}
              className="btn btn-secondary"
              title="إجراءات إضافية"
              aria-haspopup="true"
              aria-expanded={dropdownOpen}
              style={{
                display: 'flex', alignItems: 'center',
                padding: '6px 8px',
                borderRadius: '0 4px 4px 0',
                borderInlineStart: '1px solid rgba(0,0,0,0.08)',
              }}
            >
              <IconChevron />
            </button>
          )}
        </div>

        {/* Dropdown: pdf-download option */}
        {dropdownOpen && hasMultiple && (
          <div style={{
            position: 'absolute',
            top: 'calc(100% + 4px)',
            insetInlineStart: 0,
            minWidth: '200px',
            background: 'white',
            border: '1px solid #e0e0e0',
            borderRadius: '6px',
            boxShadow: '0 4px 12px rgba(0,0,0,0.12)',
            zIndex: 999,
            overflow: 'hidden',
            direction: 'rtl',
          }}>
            {hasPdfDownload && (
              <button
                onClick={() => {
                  // SYNC: triggerPdfDownload calls openPreviewPopup internally
                  // before any async. Dropdown close happens after — this is safe
                  // because setDropdownOpen is a local state update, not an await.
                  setDropdownOpen(false);
                  triggerPdfDownload();
                }}
                disabled={busy}
                title="يفتح نافذة الطباعة تلقائياً — اختر 'حفظ كـ PDF' من حوار الطباعة"
                style={{
                  width: '100%', textAlign: 'start',
                  display: 'flex', alignItems: 'center', gap: '8px',
                  padding: '9px 14px',
                  background: 'transparent', border: 'none',
                  cursor: busy ? 'not-allowed' : 'pointer',
                  fontSize: '13px', color: '#222',
                }}
                onMouseEnter={e => (e.currentTarget.style.background = '#f5f5f5')}
                onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
              >
                <IconDownload />
                {/* Honest label: this opens a print dialog where user saves as PDF */}
                <span>حفظ كـ PDF</span>
              </button>
            )}
          </div>
        )}

        {/* Inline error feedback */}
        {error && (
          <div
            onClick={clearError}
            title="انقر لإغلاق"
            style={{
              position: 'absolute',
              top: 'calc(100% + 6px)',
              insetInlineStart: 0,
              background: '#fef2f2',
              border: '1px solid #fca5a5',
              color: '#c00',
              borderRadius: '4px',
              padding: '5px 10px',
              fontSize: '11px',
              cursor: 'pointer',
              whiteSpace: 'nowrap',
              zIndex: 1000,
              direction: 'rtl',
            }}
          >
            ⚠ {error}
          </div>
        )}

        <style>{`@keyframes spin{to{transform:rotate(360deg)}}`}</style>
      </div>
    );
  }

  // ── Single action (print only — e.g. iOS, or document with 1 capability) ──
  // The label is always "معاينة / طباعة" regardless of platform.
  // We do NOT show "حفظ PDF" here even on desktop — that only appears in the
  // dropdown above (hasMultiple path). This prevents the label being printed
  // in the UI but the action being "open a print dialog". The dropdown tooltip
  // makes the mechanism clear.
  return (
    <div className={`document-actions ${className || ''}`} style={{ display: 'inline-block' }}>
      <button
        onClick={triggerPreview}
        disabled={busy}
        className="btn btn-secondary"
        title="يفتح صفحة المعاينة — اطبع أو احفظ كـ PDF من هناك"
        style={{
          display: 'flex', alignItems: 'center', gap: '6px',
          padding: '6px 14px', fontSize: '13px',
        }}
      >
        {busy ? <IconSpinner /> : <IconPrint />}
        <span>{primaryLabel}</span>
      </button>
      {error && (
        <div onClick={clearError} style={{ fontSize: '11px', color: '#c00', marginTop: '4px', cursor: 'pointer' }}>
          ⚠ {error}
        </div>
      )}
      <style>{`@keyframes spin{to{transform:rotate(360deg)}}`}</style>
    </div>
  );
}
