import React from 'react';
import { CanonicalDocument, DocumentSection, DocumentColumn, DocumentRow } from '../../models/canonical-document';

/* ═══════════════════════════════════════════════════════════════════
   DocumentStatusBadge — compact inline status pill
   ═══════════════════════════════════════════════════════════════════ */
export function DocumentStatusBadge({ status }: { status?: string | null }) {
  if (!status) return null;
  return (
    <span style={{
      display: 'inline-block',
      padding: '2px 7px',
      border: '0.75pt solid currentColor',
      borderRadius: '3px',
      fontSize: '8.5pt',
      fontWeight: 700,
      letterSpacing: '0.02em',
      verticalAlign: 'middle',
    }}>
      {status}
    </span>
  );
}

/* ═══════════════════════════════════════════════════════════════════
   DocumentMetaBlock — header facts grid (compact cards)
   ═══════════════════════════════════════════════════════════════════ */
export function DocumentMetaBlock({ meta, dir }: { meta?: CanonicalDocument['meta'], dir: 'rtl' | 'ltr' }) {
  if (!meta || meta.length === 0) return null;
  return (
    <div style={{
      display: 'grid',
      gridTemplateColumns: 'repeat(auto-fill, minmax(110px, 1fr))',
      gap: '5px',
      marginTop: '8px',
    }}>
      {meta.map((item, idx) => (
        <div
          key={idx}
          style={{
            padding: '5px 7px',
            border: '0.5pt solid #e0e0e0',
            borderRadius: '3px',
            background: '#f8f8f8',
            direction: item.dir || dir,
          }}
        >
          <div style={{ fontSize: '7.5pt', color: '#666', marginBottom: '2px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {item.label}
          </div>
          <div style={{ fontWeight: 700, fontSize: '9pt', wordBreak: 'break-word' }}>
            {item.value}
          </div>
        </div>
      ))}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════════
   DocumentTotalsBlock — aligned totals at bottom-end
   ═══════════════════════════════════════════════════════════════════ */
export function DocumentTotalsBlock({ totals, dir }: { totals?: CanonicalDocument['totals'], dir: 'rtl' | 'ltr' }) {
  if (!totals) return null;

  const rows: { label: string; value: string; bold?: boolean; color?: string }[] = [];

  if (totals.subtotal) rows.push({ label: 'الإجمالي الفرعي', value: totals.subtotal });
  if (totals.discount) rows.push({ label: 'الخصم', value: totals.discount, color: '#b91c1c' });
  if (totals.tax)      rows.push({ label: 'الضريبة', value: totals.tax });
  if (totals.total)    rows.push({ label: 'الإجمالي الكلي', value: totals.total, bold: true });
  if (totals.paid)     rows.push({ label: 'المدفوع', value: totals.paid, color: '#15803d' });
  if (totals.remaining) rows.push({ label: 'المتبقي', value: totals.remaining, color: '#b45309' });

  if (rows.length === 0) return null;

  return (
    <div style={{ marginTop: '10px', display: 'flex', justifyContent: 'flex-end', direction: dir }}>
      <div style={{ minWidth: '220px', borderTop: '1.5pt solid #333', paddingTop: '6px' }}>
        {rows.map((row, i) => (
          <div
            key={i}
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              padding: row.bold ? '4px 0 2px' : '2.5px 0',
              fontSize: row.bold ? '10.5pt' : '9pt',
              fontWeight: row.bold ? 800 : 500,
              color: row.color || '#111',
              borderTop: row.bold && rows.findIndex(r => r.bold) === i ? '0.5pt solid #ccc' : 'none',
              marginTop: row.bold ? '2px' : 0,
            }}
          >
            <span>{row.label}:</span>
            <span style={{ marginInlineStart: '20px' }}>{row.value}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════════
   DocumentNotesBlock — compact notes strip
   ═══════════════════════════════════════════════════════════════════ */
export function DocumentNotesBlock({ notes, dir }: { notes?: string[] | null, dir: 'rtl' | 'ltr' }) {
  if (!notes || notes.length === 0) return null;
  return (
    <div style={{
      marginTop: '8px',
      padding: '5px 8px',
      background: '#fffbeb',
      borderInlineStart: '3pt solid #d97706',
      direction: dir,
      borderRadius: '0 3px 3px 0',
    }}>
      <strong style={{ fontSize: '8.5pt', display: 'block', marginBottom: '2px' }}>ملاحظات:</strong>
      {notes.map((note, i) => (
        <div key={i} style={{ fontSize: '9pt' }}>• {note}</div>
      ))}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════════
   DocumentApprovalsBlock — compact signature row (no wasted space)
   ═══════════════════════════════════════════════════════════════════ */
export function DocumentApprovalsBlock({ approvals, dir }: { approvals?: CanonicalDocument['approvals'], dir: 'rtl' | 'ltr' }) {
  if (!approvals || approvals.length === 0) return null;
  return (
    <div style={{
      marginTop: '16px',
      display: 'flex',
      justifyContent: 'space-around',
      gap: '12px',
      direction: dir,
      borderTop: '0.5pt dashed #bbb',
      paddingTop: '8px',
    }}>
      {approvals.map((app, idx) => (
        <div key={idx} style={{ textAlign: 'center', flex: 1 }}>
          <div style={{ fontSize: '8pt', color: '#555', marginBottom: '18px' }}>{app.label}</div>
          <div style={{
            borderTop: '0.75pt solid #555',
            paddingTop: '3px',
            fontSize: '8.5pt',
            fontWeight: app.value ? 600 : 400,
            color: app.value ? '#111' : 'transparent',
          }}>
            {app.value || '·'}
          </div>
        </div>
      ))}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════════
   DocumentSectionRenderer — handles: table | kv | summary | plain-text
   ═══════════════════════════════════════════════════════════════════ */
export function DocumentSectionRenderer({ sec, defaultDir }: { sec: DocumentSection, defaultDir: 'rtl' | 'ltr' }) {
  return (
    <div style={{ marginBottom: '10px' }}>
      {sec.title && (
        <div style={{
          fontSize: '9.5pt',
          fontWeight: 700,
          color: '#222',
          borderBottom: '1.5pt solid #555',
          paddingBottom: '3px',
          marginBottom: '6px',
          letterSpacing: '0.01em',
        }}>
          {sec.title}
        </div>
      )}

      {/* ── plain-text ─────────────────────────────────────────────── */}
      {sec.type === 'plain-text' && (
        <p style={{ whiteSpace: 'pre-wrap', margin: 0, fontSize: '9.5pt', direction: sec.dir || defaultDir }}>
          {sec.content}
        </p>
      )}

      {/* ── kv ─────────────────────────────────────────────────────── */}
      {sec.type === 'kv' && (
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))',
          gap: '3px 16px',
        }}>
          {sec.rows.map((row: { label: string; value: string; dir?: 'rtl' | 'ltr' }, i: number) => (
            <div key={i} style={{
              display: 'flex',
              gap: '5px',
              alignItems: 'baseline',
              direction: row.dir || defaultDir,
              padding: '1.5px 0',
              borderBottom: '0.25pt solid #ebebeb',
            }}>
              <span style={{ fontSize: '8.5pt', color: '#555', flexShrink: 0 }}>{row.label}:</span>
              <span style={{ fontSize: '9pt', fontWeight: 600 }}>{row.value}</span>
            </div>
          ))}
        </div>
      )}

      {/* ── table ──────────────────────────────────────────────────── */}
      {sec.type === 'table' && (
        <table style={{ background: '#fff', fontSize: '9pt' }}>
          <thead>
            <tr>
              {sec.columns.map((col: DocumentColumn) => (
                <th
                  key={col.key}
                  style={{
                    textAlign: col.align === 'center' ? 'center' : col.align === 'end' ? 'end' : 'start',
                    width: col.width,
                    direction: col.dir || defaultDir,
                  }}
                >
                  {col.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {sec.rows.map((row: DocumentRow, i: number) => (
              <tr key={i}>
                {sec.columns.map((col: DocumentColumn) => (
                  <td
                    key={col.key}
                    style={{
                      textAlign: col.align === 'center' ? 'center' : col.align === 'end' ? 'end' : 'start',
                      direction: col.dir || defaultDir,
                    }}
                  >
                    {row[col.key]}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {/* ── summary ────────────────────────────────────────────────── */}
      {sec.type === 'summary' && (
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))',
          gap: '4px 12px',
          padding: '6px 8px',
          background: '#f5f8ff',
          border: '0.5pt solid #c8daff',
          borderRadius: '3px',
          direction: defaultDir,
        }}>
          {sec.items.map((item: { label: string; value: string }, i: number) => (
            <div key={i} style={{ display: 'flex', gap: '5px', alignItems: 'baseline' }}>
              <span style={{ fontSize: '8pt', color: '#555' }}>{item.label}:</span>
              <span style={{ fontSize: '9.5pt', fontWeight: 700 }}>{item.value}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
