import React from 'react';
import { CanonicalDocument } from '../../models/canonical-document';
import { PaperProfile } from '../../paper-profiles/paper-profiles';

/* ═══════════════════════════════════════════════════════════════════
   ThermalLayout — Professional 80mm Receipt
   Does NOT reuse A4 DocumentParts subcomponents.
   All rendering is inline and thermal-optimised.
   ═══════════════════════════════════════════════════════════════════ */

export function ThermalLayout({ document, profile }: { document: CanonicalDocument, profile: PaperProfile }) {
  const dir = document.direction;
  const isRtl = dir === 'rtl';
  const monochrome = profile.thermalConstraints?.monochrome ?? true;
  const hideImages = profile.thermalConstraints?.hideImages ?? true;

  const monoClass = monochrome ? 'monochrome' : '';
  const hideImgClass = hideImages ? 'hide-images' : '';

  return (
    <div
      className={`output-document layout-thermal ${monoClass} ${hideImgClass}`}
      style={{ '--doc-dir': dir } as React.CSSProperties}
      dir={dir}
    >
      {/* ── Company Header ───────────────────────────────────────── */}
      <div className="th-center" style={{ marginBottom: '4px' }}>
        {document.company.logoUrl && !hideImages && (
          <img
            src={document.company.logoUrl}
            alt=""
            style={{ maxHeight: '32px', display: 'block', margin: '0 auto 3px' }}
          />
        )}
        <div style={{ fontWeight: 800, fontSize: '10.5pt', lineHeight: 1.2 }}>
          {document.company.name}
        </div>
        {document.company.taxNumber && (
          <div style={{ fontSize: '7.5pt', color: '#444' }}>
            الرقم الضريبي: {document.company.taxNumber}
          </div>
        )}
        {document.company.phone && (
          <div style={{ fontSize: '7.5pt', direction: 'ltr' }}>{document.company.phone}</div>
        )}
      </div>

      <hr className="th-divider-solid" />

      {/* ── Document Title + Number + Status ────────────────────── */}
      <div className="th-center" style={{ marginBottom: '3px' }}>
        <div style={{ fontWeight: 800, fontSize: '10pt' }}>{document.title}</div>
        {document.number && (
          <div style={{ fontSize: '8pt', direction: 'ltr', marginTop: '1px' }}>
            #{document.number}
          </div>
        )}
        {document.status && (
          <div style={{ fontSize: '7.5pt', fontWeight: 700, marginTop: '1px' }}>
            [{document.status}]
          </div>
        )}
        {document.issuedAt && (
          <div style={{ fontSize: '7.5pt', color: '#555', marginTop: '1px' }}>
            {document.issuedAt}
          </div>
        )}
      </div>

      {/* ── Parties ──────────────────────────────────────────────── */}
      {document.parties && document.parties.length > 0 && (
        <>
          <hr className="th-divider" />
          {document.parties.map((p, i) => (
            <div key={i} className="th-kv-row">
              <span className="th-kv-label">{p.role}:</span>
              <span className="th-kv-value">
                {p.name}
                {p.code ? ` (${p.code})` : ''}
              </span>
            </div>
          ))}
        </>
      )}

      {/* ── Meta (essential fields only) ────────────────────────── */}
      {document.meta && document.meta.length > 0 && (
        <>
          <hr className="th-divider" />
          {document.meta.map((item, i) => (
            <div key={i} className="th-kv-row" dir={item.dir || dir}>
              <span className="th-kv-label">{item.label}:</span>
              <span className="th-kv-value">{item.value}</span>
            </div>
          ))}
        </>
      )}

      {/* ── Sections ─────────────────────────────────────────────── */}
      {document.sections.map((sec, idx) => {
        if (sec.type === 'plain-text') {
          return (
            <div key={idx}>
              <hr className="th-divider" />
              {sec.title && (
                <div style={{ fontWeight: 700, fontSize: '8.5pt', marginBottom: '2px' }}>{sec.title}</div>
              )}
              <div style={{ fontSize: '9pt', fontWeight: 700, textAlign: 'center', padding: '3px 0' }}>
                {sec.content}
              </div>
            </div>
          );
        }

        if (sec.type === 'kv') {
          return (
            <div key={idx}>
              <hr className="th-divider" />
              {sec.title && (
                <div style={{ fontWeight: 700, fontSize: '8pt', marginBottom: '2px' }}>{sec.title}</div>
              )}
              {sec.rows.map((row: { label: string; value: string; dir?: 'rtl' | 'ltr' }, i: number) => (
                <div key={i} className="th-kv-row" dir={row.dir || dir}>
                  <span className="th-kv-label">{row.label}:</span>
                  <span className="th-kv-value">{row.value}</span>
                </div>
              ))}
            </div>
          );
        }

        if (sec.type === 'table') {
          return (
            <div key={idx}>
              <hr className="th-divider" />
              {sec.title && (
                <div style={{ fontWeight: 700, fontSize: '8pt', marginBottom: '2px' }}>{sec.title}</div>
              )}
              <table>
                <thead>
                  <tr>
                    {sec.columns.map((col: any) => (
                      <th
                        key={col.key}
                        style={{
                          textAlign: col.align === 'center' ? 'center' : col.align === 'end' ? 'end' : 'start',
                          direction: col.dir || dir,
                        }}
                      >
                        {col.label}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {sec.rows.map((row: any, i: number) => (
                    <tr key={i}>
                      {sec.columns.map((col: any) => (
                        <td
                          key={col.key}
                          style={{
                            textAlign: col.align === 'center' ? 'center' : col.align === 'end' ? 'end' : 'start',
                            direction: col.dir || dir,
                          }}
                        >
                          {row[col.key]}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          );
        }

        if (sec.type === 'summary') {
          return (
            <div key={idx}>
              <hr className="th-divider" />
              {sec.items.map((item: { label: string; value: string }, i: number) => (
                <div key={i} className="th-kv-row">
                  <span className="th-kv-label">{item.label}:</span>
                  <span className="th-kv-value">{item.value}</span>
                </div>
              ))}
            </div>
          );
        }

        if (sec.type === 'compact-items') {
          return (
            <div key={idx}>
              <hr className="th-divider" />
              {sec.title && (
                <div style={{ fontWeight: 700, fontSize: '8.5pt', marginBottom: '3px' }}>{sec.title}</div>
              )}
              {sec.items && sec.items.length > 0 ? (
                sec.items.map((item: any, i: number) => (
                  <div
                    key={i}
                    style={{
                      paddingBottom: '4px',
                      marginBottom: '4px',
                      borderBottom: '0.25pt dotted #ccc',
                    }}
                  >
                    <div style={{
                      fontWeight: 700,
                      fontSize: '9pt',
                      lineHeight: 1.3,
                      display: '-webkit-box',
                      WebkitLineClamp: 2,
                      WebkitBoxOrient: 'vertical' as any,
                      overflow: 'hidden',
                      wordBreak: 'break-word',
                    }}>
                      {item.name}
                    </div>
                    <div style={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center',
                      fontSize: '8.5pt',
                      marginTop: '2px',
                    }}>
                      <span style={{ color: '#444' }}>{item.qtyPrice}</span>
                      <span style={{ fontWeight: 800 }}>{item.lineTotal}</span>
                    </div>
                    {item.details && (
                      <div style={{ fontSize: '7.5pt', color: '#666', marginTop: '1px' }}>
                        {item.details}
                      </div>
                    )}
                  </div>
                ))
              ) : (
                <div style={{ fontSize: '8pt', color: '#888', textAlign: 'center', padding: '6px 0' }}>
                  لا توجد بنود
                </div>
              )}
            </div>
          );
        }

        return null;
      })}

      {/* ── Totals ───────────────────────────────────────────────── */}
      {document.totals && (() => {
        const t = document.totals;
        const lines: { label: string; value: string; bold?: boolean }[] = [];
        if (t.subtotal) lines.push({ label: 'الإجمالي الفرعي', value: t.subtotal });
        if (t.discount) lines.push({ label: 'الخصم', value: t.discount });
        if (t.tax)      lines.push({ label: 'الضريبة', value: t.tax });
        if (t.total)    lines.push({ label: 'الإجمالي', value: t.total, bold: true });
        if (t.paid)     lines.push({ label: 'المدفوع', value: t.paid });
        if (t.remaining) lines.push({ label: 'المتبقي', value: t.remaining });
        if (lines.length === 0) return null;
        return (
          <>
            <hr className="th-divider" />
            {lines.map((line, i) =>
              line.bold ? (
                <div key={i} className="th-total-row">
                  <span>{line.label}</span>
                  <span>{line.value}</span>
                </div>
              ) : (
                <div key={i} className="th-kv-row">
                  <span className="th-kv-label">{line.label}:</span>
                  <span className="th-kv-value">{line.value}</span>
                </div>
              )
            )}
          </>
        );
      })()}

      {/* ── Notes ────────────────────────────────────────────────── */}
      {document.notes && document.notes.length > 0 && (
        <>
          <hr className="th-divider" />
          {document.notes.map((note, i) => (
            <div key={i} style={{ fontSize: '7.5pt', color: '#444', textAlign: 'center' }}>
              {note}
            </div>
          ))}
        </>
      )}

      {/* ── Approvals (printed name only, no empty lines) ────────── */}
      {document.approvals && document.approvals.some(a => a.value) && (
        <>
          <hr className="th-divider" />
          {document.approvals.filter(a => a.value).map((app, i) => (
            <div key={i} className="th-kv-row">
              <span className="th-kv-label">{app.label}:</span>
              <span className="th-kv-value">{app.value}</span>
            </div>
          ))}
        </>
      )}

      {/* ── Footer ───────────────────────────────────────────────── */}
      <div className="layout-thermal-footer" style={{ marginTop: '6px' }}>
        <hr className="th-divider-solid" />
        {document.company.footerNote && (
          <div className="th-footer-text">{document.company.footerNote}</div>
        )}
        {document.company.website && (
          <div className="th-footer-text" style={{ direction: 'ltr' }}>{document.company.website}</div>
        )}
        {/* EDARA watermark — optional */}
        <div className="th-footer-text" style={{ marginTop: '3px', color: '#999' }}>
          EDARA
        </div>
      </div>
    </div>
  );
}
