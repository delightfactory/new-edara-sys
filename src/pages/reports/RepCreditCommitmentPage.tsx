/**
 * RepCreditCommitmentPage.tsx — v4
 * تقرير الالتزام الائتماني لمسؤولي المحافظ
 *
 * v4 — إصلاحات Dark Mode + التجاوب:
 *   - كل الألوان الثابتة (hex) أُبدلت بـ CSS variables من tokens.css
 *   - الجدول يتحول إلى cards على الشاشات الصغيرة (≤768px)
 *   - Drawer يظهر من جهة اليمين (RTL صحيح) على desktop
 *     وكـ bottom-sheet على mobile
 *   - KPI grid تحسينات للشاشات الضيقة
 *   - إزالة backdrop-filter لأنه غير موثوق عبر كل المتصفحات
 */

import React, { useState, useCallback } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  getRepCreditCommitmentReport,
  getRepCreditCommitmentDetail,
  type RepCreditCommitmentRow,
  type RepCreditDetailRow,
} from '@/lib/services/rep-credit'

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

function fmt(n: number): string {
  return n.toLocaleString('ar-EG', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

const PAY_LABELS: Record<string, string> = {
  cash:   'نقدي',
  credit: 'آجل',
  mixed:  'مختلط',
}

function payLabel(term: string | null): string {
  if (!term) return '—'
  return PAY_LABELS[term] ?? term
}

// ─────────────────────────────────────────────────────────────
// Static styles — only layout / non-color values here.
// All colors use CSS custom properties so dark-mode is automatic.
// ─────────────────────────────────────────────────────────────

const css = {
  page: {
    padding: 'var(--space-6)',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 'var(--space-6)',
    direction: 'rtl' as const,
    fontFamily: 'var(--font-sans)',
    minHeight: '100%',
    background: 'var(--bg-app)',
  },

  // Header
  pageTitle: {
    fontSize: 'var(--text-2xl)',
    fontWeight: 700,
    color: 'var(--text-primary)',
    margin: 0,
  },
  pageSubtitle: {
    fontSize: 'var(--text-sm)',
    color: 'var(--text-muted)',
    marginTop: 'var(--space-1)',
    margin: 'var(--space-1) 0 0',
  },

  // KPI grid
  kpiGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
    gap: 'var(--space-4)',
  },
  kpiCard: (accent: string) => ({
    background: 'var(--bg-surface)',
    border: '1px solid var(--border-primary)',
    borderTop: `3px solid ${accent}`,
    borderRadius: 'var(--radius-lg)',
    padding: 'var(--space-5)',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 'var(--space-2)',
    boxShadow: 'var(--shadow-sm)',
  }),
  kpiLabel: {
    fontSize: 'var(--text-xs)',
    color: 'var(--text-secondary)',
    fontWeight: 500,
  },
  kpiValue: (accent: string) => ({
    fontSize: 'var(--text-xl)',
    fontWeight: 700,
    color: accent,
  }),
  kpiSub: {
    fontSize: 'var(--text-xs)',
    color: 'var(--text-muted)',
  },

  // Warning banner
  warningBanner: {
    background: 'var(--color-warning-light)',
    border: '1px solid var(--color-warning)',
    borderRadius: 'var(--radius-md)',
    padding: 'var(--space-4) var(--space-5)',
    display: 'flex',
    gap: 'var(--space-3)',
    alignItems: 'flex-start',
  },
  warningText: {
    fontSize: 'var(--text-sm)',
    color: 'var(--color-warning)',
    lineHeight: 1.6,
  },

  // Error banner
  errorBanner: {
    background: 'var(--color-danger-light)',
    border: '1px solid var(--color-danger)',
    borderRadius: 'var(--radius-md)',
    padding: 'var(--space-4)',
    fontSize: 'var(--text-sm)',
    color: 'var(--color-danger)',
  },

  // Table wrapper
  tableWrapper: {
    background: 'var(--bg-surface)',
    border: '1px solid var(--border-primary)',
    borderRadius: 'var(--radius-lg)',
    overflow: 'hidden',
    boxShadow: 'var(--shadow-sm)',
  },
  table: {
    width: '100%',
    borderCollapse: 'collapse' as const,
    fontSize: 'var(--text-sm)',
  },
  th: {
    padding: 'var(--space-3) var(--space-4)',
    textAlign: 'right' as const,
    fontWeight: 600,
    color: 'var(--text-secondary)',
    fontSize: 'var(--text-xs)',
    background: 'var(--bg-surface-2)',
    borderBottom: '2px solid var(--border-primary)',
    whiteSpace: 'nowrap' as const,
  },
  td: {
    padding: 'var(--space-3) var(--space-4)',
    borderBottom: '1px solid var(--divider)',
    color: 'var(--text-primary)',
    verticalAlign: 'middle' as const,
  },

  // Mobile card (replaces table row on small screens)
  mobileCard: (isUnassigned: boolean) => ({
    background: 'var(--bg-surface)',
    border: `1px solid var(--border-primary)`,
    borderRight: isUnassigned ? '4px solid var(--color-warning)' : '4px solid var(--color-primary)',
    borderRadius: 'var(--radius-md)',
    padding: 'var(--space-4)',
    cursor: 'pointer' as const,
    transition: 'box-shadow var(--transition-fast)',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 'var(--space-3)',
  }),
  mobileCardGrid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 'var(--space-2)',
  },
  mobileCardField: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '2px',
  },
  mobileCardLabel: {
    fontSize: '0.65rem',
    color: 'var(--text-muted)',
    fontWeight: 600,
    textTransform: 'uppercase' as const,
    letterSpacing: '0.03em',
  },
  mobileCardValue: {
    fontSize: 'var(--text-sm)',
    fontWeight: 700,
    color: 'var(--text-primary)',
  },

  // Badge
  badge: (bg: string, color: string) => ({
    display: 'inline-flex',
    alignItems: 'center',
    gap: '0.2rem',
    padding: '0.2rem 0.5rem',
    borderRadius: 'var(--radius-full)',
    fontSize: '0.7rem',
    fontWeight: 700,
    background: bg,
    color: color,
    whiteSpace: 'nowrap' as const,
  }),

  // Unassigned badge (always amber, theme-aware via opacity)
  unassignedBadge: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '0.25rem',
    padding: '0.2rem 0.55rem',
    borderRadius: 'var(--radius-full)',
    fontSize: '0.7rem',
    fontWeight: 700,
    background: 'var(--color-warning-light)',
    color: 'var(--color-warning)',
  },

  // Drawer overlay
  overlay: {
    position: 'fixed' as const,
    inset: 0,
    background: 'var(--overlay-bg)',
    zIndex: 'var(--z-overlay)',
  },

  // Drawer panel — from the RIGHT in RTL
  drawer: (isMobile: boolean) => isMobile
    ? {
        position: 'fixed' as const,
        bottom: 0,
        right: 0,
        left: 0,
        maxHeight: '90vh',
        background: 'var(--modal-bg)',
        borderRadius: 'var(--sheet-radius)',
        zIndex: 'var(--z-modal)',
        display: 'flex',
        flexDirection: 'column' as const,
        overflowY: 'auto' as const,
        boxShadow: 'var(--shadow-xl)',
      }
    : {
        position: 'fixed' as const,
        top: 0,
        right: 0,
        height: '100%',
        width: 'min(800px, 92vw)',
        background: 'var(--modal-bg)',
        boxShadow: 'var(--shadow-xl)',
        zIndex: 'var(--z-modal)',
        display: 'flex',
        flexDirection: 'column' as const,
        overflowY: 'auto' as const,
      },

  drawerHeader: {
    padding: 'var(--space-5) var(--space-6)',
    borderBottom: '1px solid var(--border-primary)',
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    position: 'sticky' as const,
    top: 0,
    background: 'var(--modal-bg)',
    zIndex: 1,
  },
  drawerBody: {
    padding: 'var(--space-5) var(--space-6)',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 'var(--space-8)',
  },

  closeBtn: {
    border: 'none',
    background: 'transparent',
    cursor: 'pointer',
    fontSize: '1.35rem',
    lineHeight: 1,
    color: 'var(--text-secondary)',
    padding: 'var(--space-1)',
    borderRadius: 'var(--radius-sm)',
    transition: 'color var(--transition-fast)',
    flexShrink: 0,
  },

  sectionTitle: {
    fontSize: 'var(--text-sm)',
    fontWeight: 700,
    color: 'var(--text-primary)',
    marginBottom: 'var(--space-3)',
    display: 'flex',
    alignItems: 'center',
    gap: 'var(--space-2)',
  },

  // Inner tables (inside drawer)
  innerTableWrapper: {
    border: '1px solid var(--border-primary)',
    borderRadius: 'var(--radius-md)',
    overflow: 'hidden',
  },
  innerTable: {
    width: '100%',
    borderCollapse: 'collapse' as const,
    fontSize: 'var(--text-xs)',
  },
  innerTh: {
    padding: 'var(--space-2) var(--space-3)',
    background: 'var(--bg-surface-2)',
    borderBottom: '1px solid var(--border-primary)',
    fontWeight: 600,
    color: 'var(--text-secondary)',
    textAlign: 'right' as const,
    whiteSpace: 'nowrap' as const,
  },
  innerTd: {
    padding: 'var(--space-2) var(--space-3)',
    borderBottom: '1px solid var(--divider)',
    color: 'var(--text-primary)',
    verticalAlign: 'middle' as const,
  },

  // Notice boxes
  notice: (type: 'warning' | 'info') => ({
    background: type === 'warning' ? 'var(--color-warning-light)' : 'var(--color-info-light)',
    border: `1px solid ${type === 'warning' ? 'var(--color-warning)' : 'var(--color-info)'}`,
    borderRadius: 'var(--radius-md)',
    padding: 'var(--space-4)',
    fontSize: 'var(--text-sm)',
    color: type === 'warning' ? 'var(--color-warning)' : 'var(--color-info)',
    lineHeight: 1.7,
  }),

  emptyRow: {
    padding: 'var(--space-6)',
    textAlign: 'center' as const,
    color: 'var(--text-muted)',
    fontSize: 'var(--text-sm)',
    background: 'var(--bg-surface-2)',
    borderRadius: 'var(--radius-md)',
  },

  skeleton: {
    background: 'var(--bg-surface-2)',
    borderRadius: 'var(--radius-md)',
    height: '2.5rem',
    animation: 'shimmer 1.5s infinite',
    backgroundSize: '200% 100%',
  },
}

// ─────────────────────────────────────────────────────────────
// useIsMobile — simple hook
// ─────────────────────────────────────────────────────────────

function useIsMobile(): boolean {
  const [mobile, setMobile] = React.useState(() =>
    typeof window !== 'undefined' ? window.innerWidth <= 768 : false
  )
  React.useEffect(() => {
    const handler = () => setMobile(window.innerWidth <= 768)
    window.addEventListener('resize', handler)
    return () => window.removeEventListener('resize', handler)
  }, [])
  return mobile
}

// ─────────────────────────────────────────────────────────────
// Skeleton
// ─────────────────────────────────────────────────────────────

function Skeleton({ rows = 5 }: { rows?: number }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', padding: 'var(--space-4)' }}>
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} style={css.skeleton} />
      ))}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// Inner tables
// ─────────────────────────────────────────────────────────────

function CustomerTable({ customers }: { customers: RepCreditDetailRow[] }) {
  if (customers.length === 0) return <div style={css.emptyRow}>لا يوجد عملاء</div>
  return (
    <div style={{ overflowX: 'auto' }}>
      <table style={css.innerTable}>
        <thead>
          <tr>
            <th style={css.innerTh}>الاسم</th>
            <th style={css.innerTh}>الكود</th>
            <th style={css.innerTh}>الرصيد الحالي</th>
            <th style={css.innerTh}>حد الائتمان</th>
            <th style={css.innerTh}>نوع الدفع</th>
            <th style={css.innerTh}>أيام الائتمان</th>
          </tr>
        </thead>
        <tbody>
          {customers.map(c => (
            <tr key={c.entity_id}>
              <td style={{ ...css.innerTd, fontWeight: 600 }}>{c.entity_name}</td>
              <td style={{ ...css.innerTd, fontFamily: 'monospace', color: 'var(--text-secondary)' }}>
                {c.entity_ref ?? '—'}
              </td>
              <td style={{
                ...css.innerTd,
                fontWeight: 700,
                color: c.amount_1 > 0 ? 'var(--color-danger)' : 'var(--color-success)',
              }}>
                {fmt(c.amount_1)}
              </td>
              <td style={css.innerTd}>{c.amount_2 != null ? fmt(c.amount_2) : '—'}</td>
              <td style={css.innerTd}>{payLabel(c.status_text)}</td>
              <td style={css.innerTd}>
                {c.amount_3 != null ? `${Math.round(c.amount_3)} يوم` : '—'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function OrderTable({ orders }: { orders: RepCreditDetailRow[] }) {
  if (orders.length === 0) return <div style={css.emptyRow}>لا توجد فواتير مفتوحة</div>
  return (
    <div style={{ overflowX: 'auto' }}>
      <table style={css.innerTable}>
        <thead>
          <tr>
            <th style={css.innerTh}>رقم الطلب</th>
            <th style={css.innerTh}>العميل</th>
            <th style={css.innerTh}>الصافي المتبقي</th>
            <th style={css.innerTh}>الإجمالي</th>
            <th style={css.innerTh}>المحصَّل</th>
            <th style={css.innerTh}>تاريخ التسليم</th>
            <th style={css.innerTh}>الأيام</th>
          </tr>
        </thead>
        <tbody>
          {orders.map(o => {
            const days = o.extra_int ?? 0
            return (
              <tr key={o.entity_id} style={{ background: days > 0 ? 'var(--color-danger-light)' : 'transparent' }}>
                <td style={{ ...css.innerTd, fontFamily: 'monospace', color: 'var(--color-info)' }}>
                  {o.entity_ref ?? '—'}
                </td>
                <td style={css.innerTd}>{o.entity_name}</td>
                <td style={{ ...css.innerTd, fontWeight: 700, color: 'var(--color-danger)' }}>
                  {fmt(o.amount_1)}
                </td>
                <td style={css.innerTd}>{o.amount_2 != null ? fmt(o.amount_2) : '—'}</td>
                <td style={css.innerTd}>{o.amount_3 != null ? fmt(o.amount_3) : '—'}</td>
                <td style={css.innerTd}>{o.date_1 ?? '—'}</td>
                <td style={{
                  ...css.innerTd,
                  color: days > 0 ? 'var(--color-danger)' : 'var(--color-success)',
                  fontWeight: 700,
                }}>
                  {o.extra_int != null ? o.extra_int : '—'}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

function ReceiptTable({ receipts }: { receipts: RepCreditDetailRow[] }) {
  if (receipts.length === 0) return <div style={css.emptyRow}>لا توجد تحصيلات مؤكدة</div>
  return (
    <div style={{ overflowX: 'auto' }}>
      <table style={css.innerTable}>
        <thead>
          <tr>
            <th style={css.innerTh}>رقم الإيصالة</th>
            <th style={css.innerTh}>العميل</th>
            <th style={css.innerTh}>المبلغ</th>
            <th style={css.innerTh}>تاريخ المراجعة</th>
          </tr>
        </thead>
        <tbody>
          {receipts.map(r => (
            <tr key={r.entity_id}>
              <td style={{ ...css.innerTd, fontFamily: 'monospace', color: 'var(--color-success)' }}>
                {r.entity_ref ?? '—'}
              </td>
              <td style={css.innerTd}>{r.entity_name}</td>
              <td style={{ ...css.innerTd, fontWeight: 700, color: 'var(--color-success)' }}>
                {fmt(r.amount_1)}
              </td>
              <td style={css.innerTd}>{r.date_1 ?? '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// Drawer
// ─────────────────────────────────────────────────────────────

interface DrawerProps {
  repId:        string | null
  repName:      string
  isUnassigned: boolean
  onClose:      () => void
}

function RepDetailDrawer({ repId, repName, isUnassigned, onClose }: DrawerProps) {
  const isMobile = useIsMobile()

  const { data, isLoading, error } = useQuery({
    queryKey:  ['rep-credit-detail', repId],
    queryFn:   () => getRepCreditCommitmentDetail(repId),
    staleTime: 60_000,
  })

  // Close on Escape
  React.useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', handler)
    return () => document.removeEventListener('keydown', handler)
  }, [onClose])

  return (
    <>
      <div
        style={{ ...css.overlay, zIndex: 190 }}
        onClick={onClose}
        aria-hidden="true"
      />

      <div
        style={{ ...css.drawer(isMobile), zIndex: 200 }}
        role="dialog"
        aria-modal="true"
        aria-label={isUnassigned ? 'تفاصيل: العملاء غير المسندين' : `تفاصيل: ${repName}`}
      >
        {/* Header */}
        <div style={css.drawerHeader}>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-3)', flexWrap: 'wrap' as const }}>
              {isUnassigned && (
                <span style={css.unassignedBadge}>⚠ غير مسند</span>
              )}
              <h2 style={{ margin: 0, fontSize: 'var(--text-lg)', fontWeight: 700, color: 'var(--text-primary)' }}>
                {isUnassigned ? 'العملاء غير المسندين' : repName}
              </h2>
            </div>
            <p style={{ margin: 'var(--space-1) 0 0', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
              {isUnassigned
                ? 'عملاء نشطون عليهم رصيد ولم يُحدَّد لهم مسؤول متابعة'
                : `مسؤول المحفظة — ${repName}`}
            </p>
          </div>
          <button onClick={onClose} style={css.closeBtn} aria-label="إغلاق">✕</button>
        </div>

        {/* Body */}
        <div style={css.drawerBody}>

          {/* تنبيه الصف الصناعي */}
          {isUnassigned && (
            <div style={css.notice('warning')}>
              <strong>⚠ تنبيه:</strong> هؤلاء العملاء عليهم أرصدة مستحقة ولم يتم تعيين مسؤول
              متابعة لهم حتى الآن. يُرجى الانتقال إلى صفحة إدارة العملاء وإسناد كل عميل
              إلى المسؤول المناسب.
              <br />
              <strong>ملاحظة:</strong> لا تُنسب المديونية المنشأة أو التحصيلات إلى هذا الصف —
              هذه البيانات منسوبة إلى أفراد بعينهم عبر سجلات الفواتير والإيصالات.
            </div>
          )}

          {isLoading && <Skeleton rows={8} />}

          {error && (
            <div style={css.notice('warning')}>
              حدث خطأ عند تحميل البيانات. يرجى المحاولة لاحقاً.
            </div>
          )}

          {data && (
            <>
              {/* القسم 1: العملاء */}
              <div>
                <div style={css.sectionTitle}>
                  <span>👥</span>
                  <span>
                    {isUnassigned
                      ? `العملاء غير المسندين — رصيد قائم (${data.customers.length})`
                      : `العملاء المسندون حالياً (${data.customers.length})`}
                  </span>
                </div>
                <div style={css.innerTableWrapper}>
                  <CustomerTable customers={data.customers} />
                </div>
              </div>

              {/* القسم 2 & 3: للمسؤولين الحقيقيين فقط */}
              {!isUnassigned && (
                <>
                  <div>
                    <div style={css.sectionTitle}>
                      <span>📄</span>
                      <span>الفواتير المنشأة بواسطته — صافي متبقٍ ({data.orders.length})</span>
                    </div>
                    <div style={css.innerTableWrapper}>
                      <OrderTable orders={data.orders} />
                    </div>
                  </div>

                  <div>
                    <div style={css.sectionTitle}>
                      <span>💳</span>
                      <span>التحصيلات المؤكدة بواسطته ({data.receipts.length})</span>
                    </div>
                    <div style={css.innerTableWrapper}>
                      <ReceiptTable receipts={data.receipts} />
                    </div>
                  </div>
                </>
              )}
            </>
          )}
        </div>
      </div>
    </>
  )
}

// ─────────────────────────────────────────────────────────────
// MobileRepCard — table row → card on small screens
// ─────────────────────────────────────────────────────────────

function MobileRepCard({
  row,
  onClick,
}: {
  row: RepCreditCommitmentRow
  onClick: () => void
}) {
  const isUnass = row.is_unassigned
  return (
    <div
      style={css.mobileCard(isUnass)}
      onClick={onClick}
      role="button"
      tabIndex={0}
      onKeyDown={e => { if (e.key === 'Enter') onClick() }}
    >
      {/* Header row */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        {isUnass ? (
          <span style={css.unassignedBadge}>⚠ غير مسند</span>
        ) : (
          <span style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>
            {row.rep_name}
          </span>
        )}
        {row.overdue_customers_count > 0 && (
          <span style={css.badge('var(--color-danger-light)', 'var(--color-danger)')}>
            {row.overdue_customers_count} متأخر
          </span>
        )}
      </div>

      {/* Stats grid */}
      <div style={css.mobileCardGrid}>
        <div style={css.mobileCardField}>
          <span style={css.mobileCardLabel}>محفظة المتابعة</span>
          <span style={{ ...css.mobileCardValue, color: 'var(--color-info)' }}>
            {fmt(row.portfolio_balance)}
          </span>
        </div>
        <div style={css.mobileCardField}>
          <span style={css.mobileCardLabel}>العملاء</span>
          <span style={css.mobileCardValue}>
            {row.customers_count} (<span style={{ color: 'var(--color-info)' }}>{row.customers_with_balance}</span> بأرصدة)
          </span>
        </div>
        {!isUnass && (
          <>
            <div style={css.mobileCardField}>
              <span style={css.mobileCardLabel}>المديونية المنشأة</span>
              <span style={{ ...css.mobileCardValue, color: 'var(--color-danger)' }}>
                {fmt(row.created_debt)}
              </span>
            </div>
            <div style={css.mobileCardField}>
              <span style={css.mobileCardLabel}>التحصيلات</span>
              <span style={{ ...css.mobileCardValue, color: 'var(--color-success)' }}>
                {fmt(row.confirmed_collections)}
              </span>
            </div>
          </>
        )}
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// Main Page
// ─────────────────────────────────────────────────────────────

export default function RepCreditCommitmentPage() {
  const isMobile = useIsMobile()
  const [selectedRow, setSelectedRow] = useState<RepCreditCommitmentRow | null>(null)
  const [hoveredId, setHoveredId] = useState<string | null>(null)

  const { data, isLoading, error } = useQuery({
    queryKey:  ['rep-credit-commitment'],
    queryFn:   getRepCreditCommitmentReport,
    staleTime: 5 * 60_000,
  })

  const handleRowClick = useCallback((row: RepCreditCommitmentRow) => {
    setSelectedRow(row)
  }, [])

  const handleClose = useCallback(() => setSelectedRow(null), [])

  const rows    = data?.rows    ?? []
  const summary = data?.summary

  const rowKey = (r: RepCreditCommitmentRow) => r.rep_id ?? '__unassigned__'

  return (
    <>
      {/* Shimmer keyframe injected once */}
      <style>{`
        @keyframes shimmer {
          0%   { background-position: 200% 0; }
          100% { background-position: -200% 0; }
        }
      `}</style>

      <div style={css.page} dir="rtl">

        {/* Page Header */}
        <div>
          <h1 style={css.pageTitle}>التزام مسؤولي المحافظ الائتمانية</h1>
          <p style={css.pageSubtitle}>
            تحليل محافظ المتابعة، المديونية المنشأة، والتحصيلات لكل مسؤول محفظة
          </p>
        </div>

        {/* KPI Cards skeleton */}
        {isLoading && (
          <div style={css.kpiGrid}>
            {[1, 2, 3, 4].map(i => (
              <div key={i} style={{
                ...css.kpiCard('#e2e8f0'),
                height: '6rem',
                background: 'var(--bg-surface-2)',
                animation: 'shimmer 1.5s infinite',
              }} />
            ))}
          </div>
        )}

        {/* KPI Cards */}
        {summary && (
          <>
            <div style={css.kpiGrid}>
              <div style={css.kpiCard('var(--color-primary)')}>
                <span style={css.kpiLabel}>مسؤولو المحافظ</span>
                <span style={css.kpiValue('var(--color-primary)')}>{summary.totalReps}</span>
                <span style={css.kpiSub}>لديهم عملاء بأرصدة فعلية</span>
              </div>

              <div style={css.kpiCard('var(--color-info)')}>
                <span style={css.kpiLabel}>إجمالي محافظ المتابعة</span>
                <span style={css.kpiValue('var(--color-info)')}>{fmt(summary.totalPortfolio)}</span>
                <span style={css.kpiSub}>يشمل الأرصدة الافتتاحية</span>
              </div>

              <div style={css.kpiCard('var(--color-danger)')}>
                <span style={css.kpiLabel}>إجمالي المديونية المنشأة</span>
                <span style={css.kpiValue('var(--color-danger)')}>{fmt(summary.totalCreatedDebt)}</span>
                <span style={css.kpiSub}>فواتير مسلَّمة صافيها {'>'} 0</span>
              </div>

              <div style={css.kpiCard('var(--color-success)')}>
                <span style={css.kpiLabel}>إجمالي التحصيلات المؤكدة</span>
                <span style={css.kpiValue('var(--color-success)')}>{fmt(summary.totalConfirmedCollections)}</span>
                <span style={css.kpiSub}>إيصالات confirmed فقط</span>
              </div>
            </div>

            {/* Unassigned warning banner */}
            {summary.hasUnassigned && (
              <div style={css.warningBanner}>
                <span style={{ fontSize: '1.4rem', flexShrink: 0 }}>⚠</span>
                <div style={css.warningText}>
                  <strong>أرصدة بدون مسؤول متابعة:</strong>{' '}
                  يوجد رصيد قدره <strong>{fmt(summary.unassignedBalance)}</strong> لدى
                  عملاء غير مسندين لأي مسؤول.
                  انقر على صف "غير مسند" في الجدول أدناه لعرض قائمة هؤلاء العملاء.
                </div>
              </div>
            )}
          </>
        )}

        {/* Error */}
        {error && (
          <div style={css.errorBanner}>
            حدث خطأ عند تحميل التقرير. يرجى إعادة المحاولة.
          </div>
        )}

        {/* ── Mobile Cards ─────────────────────────────────── */}
        {isMobile && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
            {isLoading && <Skeleton rows={5} />}
            {!isLoading && rows.length === 0 && (
              <div style={css.emptyRow}>لا توجد بيانات</div>
            )}
            {rows.map(row => (
              <MobileRepCard
                key={rowKey(row)}
                row={row}
                onClick={() => handleRowClick(row)}
              />
            ))}
          </div>
        )}

        {/* ── Desktop Table ─────────────────────────────────── */}
        {!isMobile && (
          <div style={css.tableWrapper}>
            <table style={css.table}>
              <thead>
                <tr>
                  <th style={css.th}>المسؤول</th>
                  <th style={{ ...css.th, textAlign: 'center' }}>العملاء</th>
                  <th style={{ ...css.th, textAlign: 'center' }}>بأرصدة</th>
                  <th style={{ ...css.th, textAlign: 'center' }}>متأخرون</th>
                  <th style={css.th}>محفظة المتابعة</th>
                  <th style={css.th}>المديونية المنشأة</th>
                  <th style={css.th}>التحصيلات</th>
                </tr>
              </thead>
              <tbody>
                {isLoading && (
                  <tr>
                    <td colSpan={7}><Skeleton rows={5} /></td>
                  </tr>
                )}
                {!isLoading && rows.length === 0 && (
                  <tr>
                    <td colSpan={7} style={{ ...css.td, textAlign: 'center', color: 'var(--text-muted)' }}>
                      لا توجد بيانات
                    </td>
                  </tr>
                )}

                {rows.map(row => {
                  const key     = rowKey(row)
                  const isHover = hoveredId === key
                  const isUnass = row.is_unassigned

                  return (
                    <tr
                      key={key}
                      style={{
                        cursor: 'pointer',
                        transition: 'background var(--transition-fast)',
                        background: isUnass
                          ? isHover ? 'var(--color-warning-light)'  : 'transparent'
                          : isHover ? 'var(--bg-hover)'             : 'transparent',
                        borderRight: isUnass ? '3px solid var(--color-warning)' : '3px solid transparent',
                      }}
                      onClick={() => handleRowClick(row)}
                      onMouseEnter={() => setHoveredId(key)}
                      onMouseLeave={() => setHoveredId(null)}
                    >
                      {/* المسؤول */}
                      <td style={css.td}>
                        {isUnass ? (
                          <span style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
                            <span style={css.unassignedBadge}>⚠ غير مسند</span>
                            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                              عملاء بلا مسؤول
                            </span>
                          </span>
                        ) : (
                          <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>
                            {row.rep_name}
                          </span>
                        )}
                      </td>

                      {/* العملاء */}
                      <td style={{ ...css.td, textAlign: 'center', fontWeight: 600, color: 'var(--text-primary)' }}>
                        {row.customers_count}
                      </td>

                      {/* بأرصدة */}
                      <td style={{ ...css.td, textAlign: 'center', fontWeight: 600, color: 'var(--color-info)' }}>
                        {row.customers_with_balance}
                      </td>

                      {/* متأخرون */}
                      <td style={{ ...css.td, textAlign: 'center' }}>
                        {row.overdue_customers_count > 0 ? (
                          <span style={css.badge('var(--color-danger-light)', 'var(--color-danger)')}>
                            {row.overdue_customers_count}
                          </span>
                        ) : (
                          <span style={{ color: 'var(--color-success)', fontWeight: 600 }}>—</span>
                        )}
                      </td>

                      {/* محفظة المتابعة */}
                      <td style={{ ...css.td, fontWeight: 700, color: 'var(--color-info)' }}>
                        {fmt(row.portfolio_balance)}
                      </td>

                      {/* المديونية المنشأة */}
                      <td style={css.td}>
                        {isUnass ? (
                          <span style={{ color: 'var(--text-muted)', fontSize: 'var(--text-xs)' }}>لا ينطبق</span>
                        ) : (
                          <span style={{ fontWeight: 600, color: row.created_debt > 0 ? 'var(--color-danger)' : 'var(--text-secondary)' }}>
                            {fmt(row.created_debt)}
                          </span>
                        )}
                      </td>

                      {/* التحصيلات */}
                      <td style={css.td}>
                        {isUnass ? (
                          <span style={{ color: 'var(--text-muted)', fontSize: 'var(--text-xs)' }}>لا ينطبق</span>
                        ) : (
                          <span style={{ fontWeight: 600, color: 'var(--color-success)' }}>
                            {fmt(row.confirmed_collections)}
                          </span>
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}

        {/* Detail Drawer */}
        {selectedRow && (
          <RepDetailDrawer
            repId={selectedRow.rep_id}
            repName={selectedRow.rep_name}
            isUnassigned={selectedRow.is_unassigned}
            onClose={handleClose}
          />
        )}
      </div>
    </>
  )
}
