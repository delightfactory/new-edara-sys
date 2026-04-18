import React from 'react';
import { CanonicalDocument } from '../../models/canonical-document';
import { PaperProfile } from '../../paper-profiles/paper-profiles';

/* ═══════════════════════════════════════════════════════════════════
   ThermalLayout — Professional Thermal Receipt (80mm / 58mm)
   Thermal-native: NOT a scaled-down A4 document.

   Key design decisions:
   - NO truncation (no -webkit-line-clamp, no text-overflow).
   - Product names wrap fully — thermal paper is continuous, not paged.
   - Totals are visually prominent (largest font, bold border).
   - monochrome affects images via CSS filter (not just color).
   - hideImages defaults true in production thermal profiles.
   - Physical width is set solely by profile.size.width; inner content width organically results from internal padding, removing the need for a separate max-width var.
   ═══════════════════════════════════════════════════════════════════ */

export function ThermalLayout({ document, profile }: { document: CanonicalDocument; profile: PaperProfile }) {
  const dir = document.direction;
  const monochrome = profile.thermalConstraints?.monochrome ?? true;
  const hideImages = profile.thermalConstraints?.hideImages ?? true;

  const monoClass = monochrome ? 'monochrome' : '';
  const hideImgClass = hideImages ? 'hide-images' : '';

  return (
    <div
      className={`output-document layout-thermal ${monoClass} ${hideImgClass}`}
      style={{
        '--doc-dir': dir,
      } as React.CSSProperties}
      dir={dir}
      data-paper={profile.id}
    >
      {/* ── Company Header ───────────────────────────────────────── */}
      <div className="th-center" style={{ marginBottom: '5px' }}>
        {document.company.logoUrl && !hideImages && (
          <img
            src={document.company.logoUrl}
            alt=""
            style={{
              maxHeight: '28px',
              display: 'block',
              margin: '0 auto 3px',
              // monochrome via filter when class is active
            }}
          />
        )}
        <div style={{ fontWeight: 800, fontSize: '11pt', lineHeight: 1.2 }}>
          {document.company.name}
        </div>
        {document.company.taxNumber && (
          <div style={{ fontSize: '7.5pt', color: '#444', marginTop: '1px' }}>
            الرقم الضريبي: {document.company.taxNumber}
          </div>
        )}
        {document.company.phone && (
          <div style={{ fontSize: '7.5pt', direction: 'ltr', marginTop: '1px' }}>
            {document.company.phone}
          </div>
        )}
        {document.company.address && (
          <div style={{ fontSize: '7pt', color: '#555', marginTop: '1px' }}>
            {document.company.address}
          </div>
        )}
      </div>

      <hr className="th-divider-solid" />

      {/* ── Document Title + Number + Status ────────────────────── */}
      <div className="th-center" style={{ marginBottom: '4px' }}>
        <div style={{ fontWeight: 800, fontSize: '10.5pt', letterSpacing: '0.02em' }}>
          {document.title}
        </div>
        {document.number && (
          <div style={{ fontSize: '8.5pt', direction: 'ltr', marginTop: '2px', letterSpacing: '0.05em' }}>
            #{document.number}
          </div>
        )}
        {document.status && (
          <div style={{ fontSize: '8pt', fontWeight: 700, marginTop: '2px' }}>
            [{document.status}]
          </div>
        )}
        {document.issuedAt && (
          <div style={{ fontSize: '7.5pt', color: '#555', marginTop: '2px' }}>
            {document.issuedAt}
          </div>
        )}
      </div>

      {/* ── Parties (if any — thermal may use KV rows instead) ───── */}
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

      {/* ── Meta (compact — for essential reference values) ──────── */}
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
                <div style={{ fontWeight: 700, fontSize: '8.5pt', marginBottom: '2px' }}>
                  {sec.title}
                </div>
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
                <div style={{ fontWeight: 700, fontSize: '8pt', marginBottom: '2px' }}>
                  {sec.title}
                </div>
              )}
              {sec.rows.map((row: { label: string; value: string; dir?: 'rtl' | 'ltr' }, i: number) => (
                <div key={i} className="th-kv-row" dir={row.dir || dir}>
                  <span className="th-kv-label">{row.label}:</span>
                  {/* No truncation — value wraps naturally */}
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
                <div style={{ fontWeight: 700, fontSize: '8pt', marginBottom: '2px' }}>
                  {sec.title}
                </div>
              )}
              <table>
                <thead>
                  <tr>
                    {sec.columns.map((col: any) => (
                      <th
                        key={col.key}
                        style={{
                          textAlign:
                            col.align === 'center'
                              ? 'center'
                              : col.align === 'end'
                              ? 'end'
                              : 'start',
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
                            textAlign:
                              col.align === 'center'
                                ? 'center'
                                : col.align === 'end'
                                ? 'end'
                                : 'start',
                            direction: col.dir || dir,
                          }}
                        >
                          {/* No truncation — cell wraps */}
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
              {sec.title && (
                <div style={{ fontWeight: 700, fontSize: '8pt', marginBottom: '2px' }}>
                  {sec.title}
                </div>
              )}
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
                <div style={{ fontWeight: 700, fontSize: '8.5pt', marginBottom: '3px' }}>
                  {sec.title}
                </div>
              )}
              {sec.items && sec.items.length > 0 ? (
                sec.items.map((item: any, i: number) => (
                  <div
                    key={i}
                    style={{
                      paddingBottom: '5px',
                      marginBottom: '5px',
                      borderBottom: '0.25pt dotted #bbb',
                    }}
                  >
                    {/*
                     * CRITICAL: NO -webkit-line-clamp here.
                     * Product names MUST fully wrap on thermal paper.
                     * Thermal rolls are continuous — truncation is unacceptable
                     * as it removes commercially significant data.
                     */}
                    <div
                      style={{
                        fontWeight: 700,
                        fontSize: '9pt',
                        lineHeight: 1.35,
                        whiteSpace: 'normal',
                        wordBreak: 'break-word',
                        overflowWrap: 'anywhere',
                      }}
                    >
                      {item.name}
                    </div>
                    <div
                      style={{
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        fontSize: '8.5pt',
                        marginTop: '2px',
                        gap: '4px',
                      }}
                    >
                      <span style={{ color: '#444', flexShrink: 1, minWidth: 0, wordBreak: 'break-word' }}>
                        {item.qtyPrice}
                      </span>
                      <span style={{ fontWeight: 800, flexShrink: 0 }}>{item.lineTotal}</span>
                    </div>
                    {item.details && (
                      <div
                        style={{
                          fontSize: '7.5pt',
                          color: '#555',
                          marginTop: '2px',
                          wordBreak: 'break-word',
                        }}
                      >
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
      {document.totals &&
        (() => {
          const t = document.totals;
          const lines: { label: string; value: string; bold?: boolean; prominent?: boolean }[] = [];
          if (t.subtotal)  lines.push({ label: 'الإجمالي الفرعي', value: t.subtotal });
          if (t.discount)  lines.push({ label: 'الخصم', value: t.discount });
          if (t.tax)       lines.push({ label: 'الضريبة', value: t.tax });
          if (t.total)     lines.push({ label: 'الإجمالي', value: t.total, bold: true, prominent: true });
          if (t.paid)      lines.push({ label: 'المدفوع', value: t.paid, bold: true });
          if (t.remaining) lines.push({ label: 'المتبقي', value: t.remaining, bold: true });
          if (lines.length === 0) return null;
          return (
            <>
              <hr className="th-divider" />
              {lines.map((line, i) =>
                line.prominent ? (
                  /* Grand total — maximum prominence */
                  <div key={i} className="th-total-row" style={{ fontSize: '11pt' }}>
                    <span>{line.label}</span>
                    <span>{line.value}</span>
                  </div>
                ) : line.bold ? (
                  /* Secondary totals (paid / remaining) */
                  <div key={i} className="th-kv-row" style={{ fontWeight: 700, fontSize: '9.5pt' }}>
                    <span className="th-kv-label">{line.label}:</span>
                    <span className="th-kv-value">{line.value}</span>
                  </div>
                ) : (
                  /* Sub-lines */
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
            <div
              key={i}
              style={{
                fontSize: '7.5pt',
                color: '#444',
                textAlign: 'center',
                wordBreak: 'break-word',
              }}
            >
              {note}
            </div>
          ))}
        </>
      )}

      {/* ── Approvals (print name only; no empty signature lines) ── */}
      {document.approvals && document.approvals.some(a => a.value) && (
        <>
          <hr className="th-divider" />
          {document.approvals
            .filter(a => a.value)
            .map((app, i) => (
              <div key={i} className="th-kv-row">
                <span className="th-kv-label">{app.label}:</span>
                <span className="th-kv-value">{app.value}</span>
              </div>
            ))}
        </>
      )}

      {/* ── Footer ───────────────────────────────────────────────── */}
      <div className="layout-thermal-footer" style={{ marginTop: '8px' }}>
        <hr className="th-divider-solid" />
        {document.company.footerNote && (
          <div className="th-footer-text">{document.company.footerNote}</div>
        )}
        {document.company.website && (
          <div className="th-footer-text" style={{ direction: 'ltr' }}>
            {document.company.website}
          </div>
        )}
        <div className="th-footer-text" style={{ marginTop: '4px', color: '#aaa', letterSpacing: '0.05em' }}>
          EDARA
        </div>
      </div>
    </div>
  );
}
