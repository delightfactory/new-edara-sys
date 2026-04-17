/**
 * DocumentActions — Output Hub Component
 *
 * Capability-driven component: shows only the outputs that are both declared
 * by the document definition AND implemented end-to-end in this platform.
 *
 * Currently implemented outputs:
 *   - pdf-browser / print → opens DocumentPreviewPage in new tab
 *   - pdf-download        → client-side PDF (lazy-loaded service)
 *
 * NOT shown yet (pending Batch 2):
 *   - csv, xlsx, pdf-archive
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
  /** Compact mode: just one icon button that opens a dropdown */
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
  const { capabilities, busy, error, triggerPreview, triggerPdfDownload, clearError } =
    useDocumentOutput({ kind, entityId, paperProfileId, params });

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

  const hasPrint = capabilities.some(c => c.kind === 'pdf-browser' || c.kind === 'print');
  const hasPdfDownload = capabilities.some(c => c.kind === 'pdf-download');
  const hasMultiple = hasPrint && hasPdfDownload;

  // ── Compact: single icon button + dropdown ────────────────────────
  if (compact || hasMultiple) {
    return (
      <div
        ref={dropdownRef}
        className={`document-actions ${className || ''}`}
        style={{ position: 'relative', display: 'inline-block' }}
      >
        {/* Primary action: Preview/Print */}
        <div style={{ display: 'flex', alignItems: 'stretch' }}>
          {hasPrint && (
            <button
              onClick={triggerPreview}
              disabled={busy}
              className="btn btn-secondary"
              title="معاينة / طباعة"
              style={{
                display: 'flex', alignItems: 'center', gap: '6px',
                padding: '6px 12px',
                borderRadius: hasMultiple ? '4px 0 0 4px' : '4px',
                borderInlineEnd: hasMultiple ? 'none' : undefined,
                fontSize: '13px',
              }}
            >
              {busy ? <IconSpinner /> : <IconPrint />}
              <span>طباعة</span>
            </button>
          )}

          {/* Dropdown toggle */}
          {hasMultiple && (
            <button
              onClick={() => setDropdownOpen(v => !v)}
              disabled={busy}
              className="btn btn-secondary"
              title="إجراءات أخرى"
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

        {/* Dropdown menu */}
        {dropdownOpen && hasMultiple && (
          <div style={{
            position: 'absolute',
            top: 'calc(100% + 4px)',
            insetInlineStart: 0,
            minWidth: '160px',
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
                onClick={async () => {
                  setDropdownOpen(false);
                  await triggerPdfDownload();
                }}
                disabled={busy}
                title="يفتح نافذة الطباعة مع خيار حفظ كـ PDF — قد يختلف السلوك حسب المتصفح"
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
                <span>حفظ كـ PDF</span>
              </button>
            )}
          </div>
        )}

        {/* Inline error toast */}
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

        {/* Spinner keyframe */}
        <style>{`@keyframes spin{to{transform:rotate(360deg)}}`}</style>
      </div>
    );
  }

  // ── Single-action fallback: just Preview/Print ────────────────────
  return (
    <div className={`document-actions ${className || ''}`} style={{ display: 'inline-block' }}>
      <button
        onClick={triggerPreview}
        disabled={busy}
        className="btn btn-secondary"
        title="معاينة / طباعة المستند"
        style={{
          display: 'flex', alignItems: 'center', gap: '6px',
          padding: '6px 14px', fontSize: '13px',
        }}
      >
        <IconPrint />
        <span>معاينة / طباعة</span>
      </button>
    </div>
  );
}
