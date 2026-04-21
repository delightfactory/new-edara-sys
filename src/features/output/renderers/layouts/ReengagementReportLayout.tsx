/**
 * ReengagementReportLayout.tsx
 *
 * Layout مخصص لتقرير إعادة الاستهداف.
 * يتعامل مع نوع section 'customer-card' وبقية الأنواع العادية.
 *
 * هيكل التقرير:
 *   1. رأس التقرير (متكرر مع كل صفحة)
 *   2. شريط KPI ملخص (summary section)
 *   3. جدول ملخص سريع لكل العملاء (table section)
 *   4. بطاقات العملاء التفصيلية (customer-card section)
 *   5. ملاحظات + تذييل
 */
import React from 'react';
import type { CanonicalDocument, CustomerCardEntry } from '../../models/canonical-document';
import type { PaperProfile } from '../../paper-profiles/paper-profiles';
import { DocumentNotesBlock, DocumentSectionRenderer } from '../components/DocumentParts';

// ─── Priority Colors ──────────────────────────────────────────────────────────

const SEVERITY_COLORS: Record<string, { bg: string; border: string; text: string }> = {
  critical:    { bg: '#fff5f5', border: '#fc8181', text: '#c53030' },
  warning:     { bg: '#fffbeb', border: '#f6ad55', text: '#b7791f' },
  opportunity: { bg: '#ebf8ff', border: '#63b3ed', text: '#2b6cb0' },
  positive:    { bg: '#f0fff4', border: '#68d391', text: '#276749' },
  info:        { bg: '#f7fafc', border: '#a0aec0', text: '#4a5568' },
};

// ─── Sub-components ───────────────────────────────────────────────────────────

function InfoChip({ label, value, dir = 'rtl', bold = false, color }: {
  label: string; value: string; dir?: string; bold?: boolean; color?: string
}) {
  return (
    <div style={{
      display: 'flex', flexDirection: 'column', gap: '1px',
      padding: '4px 7px',
      background: '#f8f9fa',
      border: '0.5pt solid #e0e0e0',
      borderRadius: '3px',
      direction: dir as any,
      minWidth: '80px',
    }}>
      <span style={{ fontSize: '7pt', color: '#888', lineHeight: 1.2 }}>{label}</span>
      <span style={{ fontSize: '9pt', fontWeight: bold ? 700 : 600, color: color || '#111', lineHeight: 1.3 }}>{value}</span>
    </div>
  );
}

function SectionTitle({ title, accent }: { title: string; accent?: string }) {
  return (
    <div style={{
      fontSize: '8pt',
      fontWeight: 700,
      color: accent || '#2d3748',
      borderBottom: `1pt solid ${accent || '#cbd5e0'}`,
      paddingBottom: '2px',
      marginBottom: '5px',
      marginTop: '8px',
      letterSpacing: '0.02em',
    }}>
      {title}
    </div>
  );
}

function CustomerCard({ entry, index }: { entry: CustomerCardEntry; index: number }) {
  const has360 = entry.kpis360 !== undefined
    || entry.products360 !== undefined
    || entry.paymentBehavior360 !== undefined
    || entry.recommendations360 !== undefined
    || entry.arAging360 !== undefined;

  const FMT = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });
  const fmtNum = (n: number | null | undefined) => n != null ? FMT.format(n) : '—';
  const fmtCur = (n: number | null | undefined) => n != null ? `${FMT.format(n)} ج.م` : '—';

  // Balance color
  const balColor = entry.outstandingBalance > 0 ? '#c53030'
    : entry.outstandingBalance < 0 ? '#276749' : '#718096';

  return (
    <div style={{
      breakInside: 'avoid',
      pageBreakInside: 'avoid',
      marginBottom: '10pt',
      border: '0.75pt solid #e2e8f0',
      borderRadius: '4pt',
      overflow: 'hidden',
      boxShadow: '0 1pt 3pt rgba(0,0,0,0.06)',
    }}>
      {/* ── Card Header ─────────────────────────────────────────────────────── */}
      <div style={{
        background: `linear-gradient(135deg, ${entry.priorityAccent}18 0%, ${entry.priorityAccent}08 100%)`,
        borderBottom: `2pt solid ${entry.priorityAccent}`,
        padding: '6pt 9pt',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'flex-start',
        gap: '8pt',
      }}>
        {/* Left: rank + name + meta */}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '6pt', flexWrap: 'wrap' }}>
            {/* Rank badge */}
            <div style={{
              width: '18pt', height: '18pt',
              borderRadius: '50%',
              background: entry.priorityAccent,
              color: '#fff',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: '8pt', fontWeight: 700,
              flexShrink: 0,
            }}>
              {index + 1}
            </div>
            <div>
              <div style={{ fontSize: '11pt', fontWeight: 700, color: '#1a202c', lineHeight: 1.2 }}>
                {entry.customerName}
              </div>
              <div style={{ fontSize: '8pt', color: '#718096', marginTop: '1pt', lineHeight: 1.3 }}>
                {entry.customerCode && <span style={{ fontFamily: 'monospace', background: '#edf2f7', padding: '0 3pt', borderRadius: '2pt', marginInlineEnd: '5pt' }}>{entry.customerCode}</span>}
                <span>{entry.customerType}</span>
                <span style={{ margin: '0 4pt', color: '#cbd5e0' }}>·</span>
                <span>{entry.repName}</span>
                <span style={{ margin: '0 4pt', color: '#cbd5e0' }}>·</span>
                <span>{entry.governorate}{entry.city && entry.city !== '—' ? ` / ${entry.city}` : ''}</span>
              </div>
            </div>
          </div>
        </div>

        {/* Right: Priority badge */}
        <div style={{ flexShrink: 0, textAlign: 'end' }}>
          <div style={{
            display: 'inline-block',
            padding: '3pt 8pt',
            background: `${entry.priorityAccent}20`,
            border: `1pt solid ${entry.priorityAccent}50`,
            borderRadius: '20pt',
            fontSize: '8pt', fontWeight: 700, color: entry.priorityAccent,
            whiteSpace: 'nowrap',
          }}>
            {entry.priorityDisplay}
          </div>
        </div>
      </div>

      {/* ── Card Body ────────────────────────────────────────────────────────── */}
      <div style={{ padding: '7pt 9pt' }}>

        {/* Basic Metrics Row */}
        <div style={{ display: 'flex', gap: '5pt', flexWrap: 'wrap', marginBottom: '6pt' }}>
          <InfoChip label="القيمة التاريخية" value={fmtCur(entry.historicalRevenue)} bold />
          <InfoChip label="آخر 90 يوم" value={fmtCur(entry.revenueL90d)} />
          <InfoChip
            label="آخر شراء"
            value={entry.recencyDays != null ? `${entry.recencyDays} يوم` : 'لا طلبات'}
            color={
              entry.recencyDays == null ? '#718096'
              : entry.recencyDays > 90  ? '#c53030'
              : entry.recencyDays > 45  ? '#b7791f'
              : '#276749'
            }
          />
          {entry.lastOrderDate && (
            <InfoChip label="تاريخ آخر طلب" value={new Date(entry.lastOrderDate).toLocaleDateString('en-GB')} dir="ltr" />
          )}
          <InfoChip
            label="الرصيد"
            value={entry.outstandingBalance === 0 ? '—' : fmtCur(Math.abs(entry.outstandingBalance))}
            color={balColor}
            bold={entry.outstandingBalance !== 0}
          />
          <InfoChip label="عدد الطلبات" value={`${entry.orderCount} طلب`} />
          {entry.valueTier && (
            <InfoChip
              label="شريحة القيمة"
              value={entry.valueTier === 'HIGH' ? '⭐ عالي' : entry.valueTier === 'MED' ? '🔵 متوسط' : '⚪ منخفض'}
            />
          )}
        </div>

        {/* ── 360° Sections ────────────────────────────────────────────────── */}
        {has360 && (
          <div style={{
            borderTop: '0.5pt dashed #e2e8f0',
            paddingTop: '6pt',
            marginTop: '2pt',
          }}>
            <div style={{ fontSize: '7.5pt', fontWeight: 700, color: '#718096', marginBottom: '5pt', letterSpacing: '0.03em' }}>
              ── بيانات 360° ──────────────────────────────
            </div>

            {/* Recommendations */}
            {entry.recommendations360 && entry.recommendations360 !== 'error' && entry.recommendations360.length > 0 && (
              <div style={{ marginBottom: '6pt' }}>
                <SectionTitle title="💡 التوصيات والتنبيهات" accent="#4a5568" />
                <div style={{ display: 'flex', flexDirection: 'column', gap: '3pt' }}>
                  {entry.recommendations360.map((rec, i) => {
                    const cfg = SEVERITY_COLORS[rec.severity] || SEVERITY_COLORS.info;
                    return (
                      <div key={i} style={{
                        display: 'flex', gap: '6pt', alignItems: 'flex-start',
                        padding: '4pt 6pt',
                        background: cfg.bg,
                        border: `0.5pt solid ${cfg.border}`,
                        borderRadius: '3pt',
                        breakInside: 'avoid',
                      }}>
                        <span style={{ fontSize: '8.5pt', flexShrink: 0 }}>
                          {rec.severity === 'critical' ? '🔴' : rec.severity === 'warning' ? '🟡' : rec.severity === 'opportunity' ? '🔵' : rec.severity === 'positive' ? '🟢' : 'ℹ️'}
                        </span>
                        <div>
                          <div style={{ fontSize: '8.5pt', fontWeight: 700, color: cfg.text }}>{rec.title}</div>
                          {rec.reason && <div style={{ fontSize: '8pt', color: '#4a5568', marginTop: '1pt' }}>{rec.reason}</div>}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}
            {entry.recommendations360 === 'error' && (
              <div style={{ fontSize: '8pt', color: '#b7791f', padding: '3pt 6pt', background: '#fffbeb', borderRadius: '3pt', marginBottom: '4pt' }}>
                ⚠ تعذر تحميل التوصيات لهذا العميل
              </div>
            )}

            {/* KPIs 360 */}
            {entry.kpis360 && entry.kpis360 !== 'error' && (
              <div style={{ marginBottom: '6pt' }}>
                <SectionTitle title="📊 الملخص التنفيذي" accent="#2b6cb0" />
                <div style={{ display: 'flex', gap: '4pt', flexWrap: 'wrap' }}>
                  {entry.kpis360.netRevenue != null && (
                    <InfoChip label="صافي الإيراد" value={fmtCur(entry.kpis360.netRevenue)} bold />
                  )}
                  {entry.kpis360.totalCollected != null && (
                    <InfoChip label="إجمالي المحصل" value={fmtCur(entry.kpis360.totalCollected)} />
                  )}
                  {entry.kpis360.returnRatePct != null && (
                    <InfoChip
                      label="نسبة المرتجعات"
                      value={`${entry.kpis360.returnRatePct.toFixed(1)}%`}
                      color={entry.kpis360.returnRatePct > 15 ? '#c53030' : '#2d3748'}
                    />
                  )}
                  {entry.kpis360.creditUtilizationPct != null && (
                    <InfoChip
                      label="استخدام الائتمان"
                      value={`${entry.kpis360.creditUtilizationPct.toFixed(1)}%`}
                      color={entry.kpis360.creditUtilizationPct > 85 ? '#c53030' : '#2d3748'}
                    />
                  )}
                  {entry.kpis360.customerSinceDays != null && (
                    <InfoChip label="مدة العميل" value={`${entry.kpis360.customerSinceDays} يوم`} />
                  )}
                </div>
              </div>
            )}
            {entry.kpis360 === 'error' && (
              <div style={{ fontSize: '8pt', color: '#b7791f', padding: '3pt 6pt', background: '#fffbeb', borderRadius: '3pt', marginBottom: '4pt' }}>
                ⚠ تعذر تحميل الملخص التنفيذي لهذا العميل
              </div>
            )}

            {/* AR Aging */}
            {entry.arAging360 && entry.arAging360 !== 'error' && entry.arAging360.some(b => b.amount > 0) && (
              <div style={{ marginBottom: '6pt' }}>
                <SectionTitle title="📅 أعمار الديون (AR Aging)" accent="#c53030" />
                <div style={{ display: 'flex', gap: '4pt', flexWrap: 'wrap' }}>
                  {entry.arAging360.filter(b => b.amount > 0).map((b, i) => (
                    <InfoChip
                      key={i}
                      label={`${b.bucket} يوم`}
                      value={fmtCur(b.amount)}
                      color={b.bucket === '90+' ? '#c53030' : b.bucket === '61-90' ? '#b7791f' : '#4a5568'}
                      bold={b.bucket === '90+'}
                    />
                  ))}
                </div>
              </div>
            )}

            {/* Payment Behavior */}
            {entry.paymentBehavior360 && entry.paymentBehavior360 !== 'error' && (
              <div style={{ marginBottom: '6pt' }}>
                <SectionTitle title="💳 سلوك السداد" accent="#276749" />
                <div style={{ display: 'flex', gap: '4pt', flexWrap: 'wrap' }}>
                  {entry.paymentBehavior360.avgDelayDays != null && (
                    <InfoChip
                      label="متوسط التأخير"
                      value={`${entry.paymentBehavior360.avgDelayDays} يوم`}
                      color={entry.paymentBehavior360.avgDelayDays > 45 ? '#c53030' : '#2d3748'}
                    />
                  )}
                  {entry.paymentBehavior360.cashPct > 0 && (
                    <InfoChip label="نقدي" value={`${entry.paymentBehavior360.cashPct}%`} color="#276749" />
                  )}
                  {entry.paymentBehavior360.chequePct > 0 && (
                    <InfoChip label="شيكات" value={`${entry.paymentBehavior360.chequePct}%`} />
                  )}
                  {entry.paymentBehavior360.transferPct > 0 && (
                    <InfoChip label="تحويل بنكي" value={`${entry.paymentBehavior360.transferPct}%`} />
                  )}
                </div>
              </div>
            )}
            {entry.paymentBehavior360 === 'error' && (
              <div style={{ fontSize: '8pt', color: '#b7791f', padding: '3pt 6pt', background: '#fffbeb', borderRadius: '3pt', marginBottom: '4pt' }}>
                ⚠ تعذر تحميل سلوك السداد لهذا العميل
              </div>
            )}

            {/* Top Products */}
            {entry.products360 && entry.products360 !== 'error' && entry.products360.length > 0 && (
              <div style={{ marginBottom: '4pt' }}>
                <SectionTitle title="📦 أبرز المنتجات" accent="#553c9a" />
                <div style={{
                  display: 'grid',
                  gridTemplateColumns: 'repeat(auto-fill, minmax(160pt, 1fr))',
                  gap: '3pt',
                }}>
                  {entry.products360.slice(0, 6).map((p, i) => (
                    <div key={i} style={{
                      padding: '4pt 6pt',
                      background: '#fafafa',
                      border: '0.5pt solid #e8e8e8',
                      borderInlineStart: `2pt solid ${p.status === 'خامد' ? '#fc8181' : p.status === 'جديد' ? '#63b3ed' : '#68d391'}`,
                      borderRadius: '0 3pt 3pt 0',
                      breakInside: 'avoid',
                    }}>
                      <div style={{ fontSize: '8.5pt', fontWeight: 700, color: '#1a202c', lineHeight: 1.2, marginBottom: '2pt' }}>
                        {p.name}
                      </div>
                      <div style={{ display: 'flex', gap: '6pt', fontSize: '7.5pt', color: '#718096', flexWrap: 'wrap' }}>
                        <span>{p.totalValue}</span>
                        <span>·</span>
                        <span>{p.orderCount} طلب</span>
                        {p.lastPurchase && <><span>·</span><span dir="ltr">{p.lastPurchase}</span></>}
                        <span style={{
                          color: p.status === 'خامد' ? '#c53030' : p.status === 'جديد' ? '#2b6cb0' : '#276749',
                          fontWeight: 600,
                        }}>
                          {p.status}
                        </span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
            {entry.products360 === 'error' && (
              <div style={{ fontSize: '8pt', color: '#b7791f', padding: '3pt 6pt', background: '#fffbeb', borderRadius: '3pt' }}>
                ⚠ تعذر تحميل بيانات المنتجات لهذا العميل
              </div>
            )}

          </div>
        )}
      </div>
    </div>
  );
}

// ─── Main Layout ──────────────────────────────────────────────────────────────

export function ReengagementReportLayout({
  document,
  profile,
}: {
  document: CanonicalDocument;
  profile: PaperProfile;
}) {
  const dir = document.direction;

  return (
    <div
      className="output-document layout-report"
      style={{
        '--doc-dir': dir,
        '--font-scale': profile.fontScale ?? 1,
        '--header-height': '70px',
        fontSize: '9.5pt',
      } as React.CSSProperties}
      dir={dir}
    >
      <style>{`
        .rr-page-break { break-before: page; page-break-before: always; }
        @media print {
          .rr-cards-section { break-before: page; }
        }
      `}</style>

      <table style={{ width: '100%', border: 'none', borderCollapse: 'collapse' }}>
        {/* ── Repeating Header ──────────────────────────────────────────── */}
        <thead className="print-header-spacer">
          <tr>
            <th style={{ border: 'none', padding: 0 }}>
              <div className="layout-report-header" style={{ paddingBottom: '4px' }}>
                <div style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  gap: '12px',
                }}>
                  {/* Logo */}
                  {document.company.logoUrl && (
                    <img
                      src={document.company.logoUrl}
                      alt=""
                      style={{ maxHeight: '40px', maxWidth: '70px', objectFit: 'contain', flexShrink: 0 }}
                    />
                  )}

                  {/* Title block */}
                  <div style={{ flex: 1 }}>
                    <div style={{ fontWeight: 700, fontSize: '10.5pt', color: '#111', lineHeight: 1.2 }}>
                      {document.company.name}
                    </div>
                    <div style={{ fontSize: '9pt', color: '#444', fontWeight: 700, marginTop: '2px' }}>
                      {document.title}
                    </div>
                  </div>

                  {/* Date + filter summary */}
                  <div style={{ textAlign: 'start', flexShrink: 0 }}>
                    {document.issuedAt && (
                      <div style={{ fontSize: '8pt', color: '#555', marginBottom: '2px' }}>
                        <span style={{ color: '#888' }}>تاريخ التقرير: </span>
                        <strong>{document.issuedAt}</strong>
                      </div>
                    )}
                    {document.meta.find(m => m.label === 'الفلاتر النشطة') && (
                      <div style={{ fontSize: '7.5pt', color: '#888' }}>
                        {document.meta.find(m => m.label === 'الفلاتر النشطة')?.value}
                      </div>
                    )}
                  </div>
                </div>
                <hr className="thick" style={{ margin: '5px 0 0', borderColor: '#2563eb' }} />
              </div>
            </th>
          </tr>
        </thead>

        <tbody>
          <tr>
            <td style={{ border: 'none', padding: 0 }}>
              <main style={{ padding: '6px 0' }}>
                {/* ── Render standard sections (summary + table) ──────── */}
                {document.sections.filter(s => s.type !== 'customer-card').map((sec, idx) => (
                  <DocumentSectionRenderer key={idx} sec={sec} defaultDir={dir} />
                ))}

                {/* ── Customer Cards Section ───────────────────────────── */}
                {(() => {
                  const cardSection = document.sections.find(s => s.type === 'customer-card');
                  if (!cardSection || cardSection.type !== 'customer-card') return null;
                  const customers = cardSection.customers;
                  if (!customers || customers.length === 0) return null;

                  return (
                    <div className="rr-cards-section">
                      <div style={{
                        fontSize: '10pt',
                        fontWeight: 700,
                        color: '#1a202c',
                        borderBottom: '2pt solid #2563eb',
                        paddingBottom: '4pt',
                        marginBottom: '10pt',
                        marginTop: '4pt',
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                      }}>
                        <span>تفاصيل العملاء المستهدفين</span>
                        <span style={{ fontSize: '8pt', color: '#718096', fontWeight: 500 }}>
                          {customers.length} عميل
                        </span>
                      </div>

                      {customers.map((entry: CustomerCardEntry, idx: number) => (
                        <CustomerCard key={entry.customerId} entry={entry} index={idx} />
                      ))}
                    </div>
                  );
                })()}

                {/* ── Notes ───────────────────────────────────────────── */}
                <DocumentNotesBlock notes={document.notes} dir={dir} />

                {/* ── Footer ──────────────────────────────────────────── */}
                <div style={{
                  marginTop: '16pt',
                  paddingTop: '6pt',
                  borderTop: '0.5pt solid #e2e8f0',
                  display: 'flex',
                  justifyContent: 'space-between',
                  fontSize: '7.5pt',
                  color: '#a0aec0',
                }}>
                  <span>سري — للاستخدام الداخلي فقط</span>
                  <span>{document.company.name} · {document.issuedAt}</span>
                </div>
              </main>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  );
}
