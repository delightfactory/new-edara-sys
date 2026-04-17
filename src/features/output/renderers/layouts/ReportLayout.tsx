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

export function ReportLayout({ document, profile }: { document: CanonicalDocument, profile: PaperProfile }) {
  const dir = document.direction;
  const isRtl = dir === 'rtl';

  return (
    <div
      className="output-document layout-report"
      style={{
        '--doc-dir': dir,
        '--font-scale': profile.fontScale ?? 1,
        '--header-height': '72px',
        fontSize: '9.5pt',
      } as React.CSSProperties}
      dir={dir}
    >
      <table style={{ width: '100%', border: 'none' }}>
        <thead className="print-header-spacer">
          <tr>
            <th style={{ border: 'none', padding: 0 }}>
              {/* ── Repeating Report Header ──────────────────────── */}
              <div className="layout-standard-header" style={{ paddingBottom: '4px' }}>
                <div style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  gap: '12px',
                }}>
                  {/* Left: company + title */}
                  <div>
                    <div style={{ fontWeight: 800, fontSize: '11pt', color: '#111', lineHeight: 1.2 }}>
                      {document.company.name}
                    </div>
                    <div style={{ display: 'flex', gap: '8px', alignItems: 'center', marginTop: '2px' }}>
                      <span style={{ fontSize: '9.5pt', color: '#333', fontWeight: 700 }}>
                        {document.title}
                      </span>
                      {document.status && <DocumentStatusBadge status={document.status} />}
                    </div>
                    {document.number && (
                      <div style={{ fontSize: '8pt', color: '#555', direction: 'ltr', display: 'inline-block', marginTop: '1px' }}>
                        {document.number}
                      </div>
                    )}
                  </div>

                  {/* Right: date + parties */}
                  <div style={{ textAlign: isRtl ? 'left' : 'right', flexShrink: 0 }}>
                    {document.issuedAt && (
                      <div style={{ fontSize: '8.5pt', color: '#444', marginBottom: '2px' }}>
                        <span style={{ color: '#777' }}>تاريخ التقرير: </span>
                        <strong>{document.issuedAt}</strong>
                      </div>
                    )}
                    {document.parties && document.parties.map((p, idx) => (
                      <div key={idx} style={{ fontSize: '8.5pt', color: '#444' }}>
                        <span style={{ color: '#777' }}>{p.role}: </span>
                        <strong>{p.name}</strong>
                        {p.code && (
                          <span style={{ fontSize: '8pt', color: '#888', marginInlineStart: '4px', direction: 'ltr', display: 'inline-block' }}>
                            ({p.code})
                          </span>
                        )}
                      </div>
                    ))}
                  </div>

                  {/* Logo */}
                  {document.company.logoUrl && (
                    <img
                      src={document.company.logoUrl}
                      alt=""
                      style={{ maxHeight: '44px', maxWidth: '80px', objectFit: 'contain', flexShrink: 0 }}
                    />
                  )}
                </div>
                <hr className="thick" style={{ marginTop: '5px', marginBottom: 0 }} />
              </div>
            </th>
          </tr>
        </thead>

        <tbody>
          <tr>
            <td style={{ border: 'none', padding: 0 }}>
              <main style={{ padding: '8px 0' }}>
                {/* ── Meta facts ─────────────────────────────────── */}
                <DocumentMetaBlock meta={document.meta} dir={isRtl ? 'rtl' : 'ltr'} />

                {/* ── Sections ───────────────────────────────────── */}
                <div style={{ marginTop: '10px' }}>
                  {document.sections.map((sec, idx) => (
                    <DocumentSectionRenderer key={idx} sec={sec} defaultDir={isRtl ? 'rtl' : 'ltr'} />
                  ))}
                </div>

                <DocumentTotalsBlock totals={document.totals} dir={isRtl ? 'rtl' : 'ltr'} />
                <DocumentNotesBlock notes={document.notes} dir={isRtl ? 'rtl' : 'ltr'} />
                <DocumentApprovalsBlock approvals={document.approvals} dir={isRtl ? 'rtl' : 'ltr'} />
              </main>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  );
}
