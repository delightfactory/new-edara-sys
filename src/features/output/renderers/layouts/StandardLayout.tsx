import React from 'react';
import { CanonicalDocument } from '../../models/canonical-document';
import { PaperProfile } from '../../paper-profiles/paper-profiles';
import {
  DocumentStatusBadge,
  DocumentMetaBlock,
  DocumentTotalsBlock,
  DocumentNotesBlock,
  DocumentApprovalsBlock,
  DocumentSectionRenderer,
} from '../components/DocumentParts';

export function StandardLayout({ document, profile }: { document: CanonicalDocument, profile: PaperProfile }) {
  const dir = document.direction;
  const isRtl = dir === 'rtl';

  return (
    <div
      className="output-document layout-standard"
      style={{
        '--doc-dir': dir,
        '--font-scale': profile.fontScale ?? 1,
        '--header-height': '88px',
        '--footer-height': '52px',
        fontSize: '10.5pt',
      } as React.CSSProperties}
      dir={dir}
    >
      {/* ── Fixed Header ─────────────────────────────────────────── */}
      <div className="layout-standard-header">
        <div style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          gap: '12px',
        }}>
          {/* Company info block */}
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{
              fontSize: '13pt',
              fontWeight: 800,
              color: '#111',
              lineHeight: 1.2,
              marginBottom: '2px',
            }}>
              {document.company.name}
            </div>
            {document.company.taxNumber && (
              <div style={{ fontSize: '8pt', color: '#555' }}>
                الرقم الضريبي: <span style={{ direction: 'ltr', display: 'inline-block' }}>{document.company.taxNumber}</span>
              </div>
            )}
            {document.company.phone && (
              <div style={{ fontSize: '8pt', color: '#555', direction: 'ltr', display: 'inline-block' }}>
                {document.company.phone}
              </div>
            )}
          </div>

          {/* Document title + number + status */}
          <div style={{ textAlign: 'center', flexShrink: 0 }}>
            <div style={{ fontSize: '12pt', fontWeight: 800, color: '#111', letterSpacing: '0.01em' }}>
              {document.title}
            </div>
            {document.number && (
              <div style={{ fontSize: '8.5pt', color: '#444', direction: 'ltr', marginTop: '1px' }}>
                {document.number}
              </div>
            )}
            {document.status && (
              <div style={{ marginTop: '2px' }}>
                <DocumentStatusBadge status={document.status} />
              </div>
            )}
          </div>

          {/* Logo */}
          {document.company.logoUrl && (
            <div style={{ flexShrink: 0 }}>
              <img
                src={document.company.logoUrl}
                alt="شعار الشركة"
                style={{ maxHeight: '60px', maxWidth: '100px', objectFit: 'contain' }}
              />
            </div>
          )}
        </div>
        <hr className="thick" style={{ marginTop: '6px', marginBottom: 0 }} />
      </div>

      {/* ── Spacer table trick for fixed header/footer ───────────── */}
      <table style={{ width: '100%', border: 'none' }}>
        <thead className="print-header-spacer">
          <tr><th style={{ border: 'none', padding: 0 }} /></tr>
        </thead>
        <tbody>
          <tr>
            <td style={{ border: 'none', padding: 0 }}>
              <main style={{ padding: '10px 0' }}>

                {/* ── Parties + Date row ──────────────────────────── */}
                <div style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'flex-start',
                  gap: '12px',
                  marginBottom: '8px',
                }}>
                  {/* Parties */}
                  <div style={{ flex: 1 }}>
                    {document.parties && document.parties.map((p, i) => (
                      <div key={i} style={{ fontSize: '9.5pt', marginBottom: '2px' }}>
                        <span style={{ color: '#666' }}>{p.role}: </span>
                        <strong>{p.name}</strong>
                        {p.code && (
                          <span style={{ color: '#888', fontSize: '8.5pt', marginInlineStart: '6px', direction: 'ltr', display: 'inline-block' }}>
                            ({p.code})
                          </span>
                        )}
                      </div>
                    ))}
                  </div>

                  {/* Date */}
                  {document.issuedAt && (
                    <div style={{ textAlign: isRtl ? 'left' : 'right', flexShrink: 0 }}>
                      <span style={{ fontSize: '8pt', color: '#666' }}>التاريخ: </span>
                      <span style={{ fontSize: '9.5pt', fontWeight: 600 }}>{document.issuedAt}</span>
                    </div>
                  )}
                </div>

                {/* ── Meta facts ───────────────────────────────────── */}
                <DocumentMetaBlock meta={document.meta} dir={isRtl ? 'rtl' : 'ltr'} />

                {/* ── Sections ─────────────────────────────────────── */}
                <div style={{ marginTop: '12px' }}>
                  {document.sections.map((sec, idx) => (
                    <DocumentSectionRenderer key={idx} sec={sec} defaultDir={isRtl ? 'rtl' : 'ltr'} />
                  ))}
                </div>

                {/* ── Totals / Notes / Approvals ───────────────────── */}
                <DocumentTotalsBlock totals={document.totals} dir={isRtl ? 'rtl' : 'ltr'} />
                <DocumentNotesBlock notes={document.notes} dir={isRtl ? 'rtl' : 'ltr'} />
                <DocumentApprovalsBlock approvals={document.approvals} dir={isRtl ? 'rtl' : 'ltr'} />
              </main>
            </td>
          </tr>
        </tbody>
        <tfoot className="print-footer-spacer">
          <tr><td style={{ border: 'none', padding: 0 }} /></tr>
        </tfoot>
      </table>

      {/* ── Fixed Footer ─────────────────────────────────────────── */}
      <div className="layout-standard-footer">
        <hr style={{ marginTop: 0, marginBottom: '4px' }} />
        <div style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          fontSize: '7.5pt',
          color: '#777',
        }}>
          <div>{document.company.footerNote}</div>
          <div style={{ direction: 'ltr' }}>
            {document.company.website || document.company.phone || ''}
          </div>
        </div>
      </div>
    </div>
  );
}
