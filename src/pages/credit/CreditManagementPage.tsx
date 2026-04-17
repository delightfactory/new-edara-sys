/**
 * CreditManagementPage — صفحة إدارة الائتمان (Responsive v2)
 *
 * Mobile-first: الجدول يتحول لبطاقات على الشاشات < 768px
 *
 * غرفة قيادة ائتمانية تشمل:
 *   - شريط KPIs للمحفظة (6 مؤشرات)
 *   - جدول العملاء على الديسكتوب + بطاقات على الموبايل
 *   - بحث وفلتر طريقة الدفع (server-side)
 *   - مؤشر تأخر: طلب واحد لـ 25 عميل في الصفحة فقط
 *   - لوحة جانبية (Drawer) مع إغلاق بـ Escape والخلفية
 *
 * الصلاحيات:
 *   customers.read أو customers.read_all  → رؤية الصفحة
 *   customers.credit.update               → تبويب التعديل
 *
 * الأداء:
 *   - getCreditCustomers() يضمن COUNT صحيح على عملاء الائتمان لا الكل
 *   - getOverdueBatch() يعمل على 25 ID فقط (مطابق لصفحة الجدول)
 *   - لا N+1 في أي تفاعل
 */

import { useState, useEffect, useCallback } from 'react'
import { useQuery, useQueryClient }          from '@tanstack/react-query'

import {
  getCreditCustomers,
  getOverdueBatch,
  type CreditCustomerRow,
  type OverdueInfo,
}                               from '@/lib/services/credit'
import { computeCreditState }   from '@/components/shared/CustomerCreditChip'
import CreditKPIBar             from '@/components/credit/CreditKPIBar'
import CustomerCreditPanel      from '@/components/credit/CustomerCreditPanel'
import { formatNumber }         from '@/lib/utils/format'
import type { Customer }        from '@/lib/types/master-data'

// ─────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────
export default function CreditManagementPage() {
  const qc = useQueryClient()

  // ── Filter / Search State ──────────────────────────────────
  const [search,       setSearch]       = useState('')
  const [inputValue,   setInputValue]   = useState('')
  const [paymentTerms, setPaymentTerms] = useState<'' | 'credit' | 'mixed'>('')
  const [page,         setPage]         = useState(1)

  // Debounced search — 350ms
  useEffect(() => {
    const t = setTimeout(() => { setSearch(inputValue); setPage(1) }, 350)
    return () => clearTimeout(t)
  }, [inputValue])

  // ── Customers Query — pagination حقيقي server-side ─────────
  const { data: result, isLoading } = useQuery({
    queryKey: ['credit-customers', { search, paymentTerms, page }],
    queryFn:  () => getCreditCustomers({
      search:       search  || undefined,
      paymentTerms: paymentTerms || undefined,
      page,
    }),
    staleTime:       2 * 60_000,
    placeholderData: (prev: any) => prev,
  })

  const customers    = result?.data       ?? []
  const totalPages   = result?.totalPages ?? 1
  const totalCount   = result?.count      ?? 0

  // ── Overdue Batch — بالضبط 25 ID من الصفحة الحالية ─────────
  const customerIds = customers.map(c => c.id)

  const { data: overdueMap } = useQuery<Record<string, OverdueInfo>>({
    queryKey: ['overdue-batch', customerIds],
    queryFn:  () => getOverdueBatch(customerIds),
    staleTime: 2 * 60_000,
    enabled:   customerIds.length > 0,
  })

  // ── Selected Customer (Drawer) ──────────────────────────────
  const [selectedCustomer, setSelectedCustomer] = useState<CreditCustomerRow | null>(null)

  const handleRowClick = useCallback((c: CreditCustomerRow) => {
    setSelectedCustomer(prev => prev?.id === c.id ? null : c)
  }, [])

  const closePanel = useCallback(() => setSelectedCustomer(null), [])

  const handleUpdated = useCallback(() => {
    qc.invalidateQueries({ queryKey: ['credit-customers'] })
    qc.invalidateQueries({ queryKey: ['credit-portfolio-kpis'] })
    qc.invalidateQueries({ queryKey: ['overdue-batch'] })
  }, [qc])

  // ── Escape key — إغلاق الـ Drawer ──────────────────────────
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && selectedCustomer) closePanel()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [selectedCustomer, closePanel])

  // ─────────────────────────────────────────────────────────────
  return (
    <div id="credit-management-page" className="cm-page animate-enter">

      {/* ── Page Header ─────────────────────────────────────── */}
      <div className="cm-header">
        <div>
          <h1 className="cm-title">🏦 إدارة الائتمان</h1>
          <p className="cm-subtitle">المحفظة الائتمانية للعملاء الآجلين والمختلطين</p>
        </div>

        <button
          id="credit-refresh-btn"
          onClick={() => {
            qc.invalidateQueries({ queryKey: ['credit-customers'] })
            qc.invalidateQueries({ queryKey: ['credit-portfolio-kpis'] })
          }}
          className="cm-refresh-btn"
        >
          ↺ تحديث
        </button>
      </div>

      {/* ── KPI Bar ──────────────────────────────────────────── */}
      <CreditKPIBar />

      {/* ── Filters & Search ─────────────────────────────────── */}
      <div className="cm-filters">
        {/* بحث */}
        <div style={{ position: 'relative', flex: '1 1 220px' }}>
          <span style={{
            position: 'absolute', insetInlineStart: 10,
            top: '50%', transform: 'translateY(-50%)',
            color: 'var(--text-muted)', pointerEvents: 'none',
          }}>🔍</span>
          <input
            id="credit-search"
            type="text"
            placeholder="ابحث باسم العميل أو الكود..."
            value={inputValue}
            onChange={e => setInputValue(e.target.value)}
            className="form-input"
            style={{ paddingInlineStart: 32, width: '100%' }}
          />
        </div>

        {/* فلتر طريقة الدفع — server-side */}
        <select
          id="credit-filter-terms"
          value={paymentTerms}
          onChange={e => { setPaymentTerms(e.target.value as any); setPage(1) }}
          className="form-input cm-filter-select"
        >
          <option value="">الآجل والمختلط</option>
          <option value="credit">آجل فقط</option>
          <option value="mixed">مختلط فقط</option>
        </select>
      </div>

      {/* ── Info Bar ─────────────────────────────────────────── */}
      <div className="cm-info-bar">
        <span>
          {isLoading
            ? 'جاري التحميل...'
            : `${customers.length} في الصفحة — إجمالي ${totalCount} عميل ائتماني`
          }
        </span>
        <span>صفحة {page} من {totalPages}</span>
      </div>

      {/* ── Table / Cards Container ───────────────────────────── */}
      <div className="cm-table-wrapper">
        {isLoading ? (
          <TableSkeleton />
        ) : !customers.length ? (
          <EmptyState />
        ) : (
          <>
            {/* ── Desktop Table ──────────────────────────────── */}
            <div className="cm-desktop-table">
              <div style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                  <thead>
                    <tr style={{ background: 'var(--bg-surface-2)' }}>
                      {['العميل', 'الكود', 'المندوب', 'الدفع', 'الحد', 'الرصيد', 'المتاح', '%', 'المدة', 'الحالة', 'تأخر'].map(col => (
                        <th key={col} style={{
                          padding: '10px 12px', textAlign: 'start',
                          fontSize: 'var(--text-xs)', fontWeight: 700,
                          color: 'var(--text-secondary)',
                          borderBottom: '1px solid var(--border-primary)',
                          whiteSpace: 'nowrap',
                        }}>
                          {col}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {customers.map(customer => (
                      <CreditRow
                        key={customer.id}
                        customer={customer}
                        overdueInfo={overdueMap?.[customer.id]}
                        isSelected={selectedCustomer?.id === customer.id}
                        onClick={() => handleRowClick(customer)}
                      />
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            {/* ── Mobile Card List ───────────────────────────── */}
            <div className="cm-mobile-list">
              {customers.map(customer => (
                <CreditMobileCard
                  key={customer.id}
                  customer={customer}
                  overdueInfo={overdueMap?.[customer.id]}
                  isSelected={selectedCustomer?.id === customer.id}
                  onClick={() => handleRowClick(customer)}
                />
              ))}
            </div>

            {/* ── Pagination ─────────────────────────────────── */}
            <div className="cm-pagination">
              {/* RTL: السابق = صفحة أصغر = يسار في رقمي = يمين في القراءة → السهم ‹ */}
              <button
                id="credit-prev-page"
                onClick={() => setPage(p => Math.max(1, p - 1))}
                disabled={page <= 1}
                className={`cm-pager-btn${page <= 1 ? ' cm-pager-disabled' : ''}`}
              >
                السابق ›
              </button>

              <span className="cm-page-info">
                {page} / {totalPages}
                <span className="cm-page-info-full"> ({totalCount} عميل)</span>
              </span>

              <button
                id="credit-next-page"
                onClick={() => setPage(p => Math.min(totalPages, p + 1))}
                disabled={page >= totalPages}
                className={`cm-pager-btn${page >= totalPages ? ' cm-pager-disabled' : ''}`}
              >
                ‹ التالي
              </button>
            </div>
          </>
        )}
      </div>

      {/* ── Drawer Overlay ───────────────────────────────────── */}
      {selectedCustomer && (
        <>
          <div
            onClick={closePanel}
            style={{
              position: 'fixed', inset: 0,
              background: 'rgba(0,0,0,0.25)', zIndex: 299,
            }}
          />
          <CustomerCreditPanel
            customer={selectedCustomer as unknown as Customer}
            onClose={closePanel}
            onUpdated={handleUpdated}
          />
        </>
      )}

      {/* ── Styles ───────────────────────────────────────────── */}
      <style>{`
        /* ── Page Layout ─────────────────── */
        .cm-page {
          padding: var(--space-5);
          min-height: 100vh;
          background: var(--bg-app);
        }
        @media (max-width: 768px) {
          .cm-page { padding: var(--space-3); }
        }

        /* ── Page Header ─────────────────── */
        .cm-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: var(--space-4);
          gap: var(--space-3);
          flex-wrap: wrap;
        }
        .cm-title {
          font-size: var(--text-2xl);
          font-weight: 800;
          color: var(--text-primary);
          margin: 0;
        }
        .cm-subtitle {
          font-size: var(--text-sm);
          color: var(--text-muted);
          margin: 4px 0 0;
        }
        @media (max-width: 480px) {
          .cm-title   { font-size: var(--text-xl); }
          .cm-subtitle { font-size: var(--text-xs); }
        }

        /* ── Refresh Button ──────────────── */
        .cm-refresh-btn {
          border: 1px solid var(--border-primary);
          background: var(--bg-surface);
          border-radius: 8px;
          padding: 7px 14px;
          cursor: pointer;
          color: var(--text-secondary);
          font-family: var(--font-sans);
          font-size: var(--text-sm);
          font-weight: 600;
          display: flex;
          align-items: center;
          gap: 6px;
          white-space: nowrap;
          flex-shrink: 0;
          transition: background 0.15s;
        }
        .cm-refresh-btn:hover { background: var(--bg-surface-2); }

        /* ── Filters ─────────────────────── */
        .cm-filters {
          display: flex;
          gap: var(--space-3);
          margin-bottom: var(--space-3);
          flex-wrap: wrap;
          align-items: center;
        }
        .cm-filter-select {
          width: auto;
          min-width: 150px;
        }
        @media (max-width: 480px) {
          .cm-filters           { flex-direction: column; }
          .cm-filters > div     { flex: unset !important; width: 100%; }
          .cm-filter-select     { width: 100% !important; min-width: unset; }
        }

        /* ── Info Bar ────────────────────── */
        .cm-info-bar {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: var(--space-2);
          font-size: var(--text-xs);
          color: var(--text-muted);
          flex-wrap: wrap;
          gap: 4px;
        }

        /* ── Table Wrapper ───────────────── */
        .cm-table-wrapper {
          background: var(--bg-surface);
          border-radius: 12px;
          border: 1px solid var(--border-primary);
          box-shadow: var(--shadow-sm);
          overflow: hidden;
        }

        /* ── Desktop / Mobile Toggle ─────── */
        .cm-desktop-table { display: block; }
        .cm-mobile-list   { display: none;  }

        @media (max-width: 768px) {
          .cm-desktop-table { display: none; }
          .cm-mobile-list {
            display: flex;
            flex-direction: column;
            gap: 8px;
            padding: var(--space-3);
          }
        }

        /* ── Mobile Card ─────────────────── */
        .cm-mobile-card {
          background: var(--bg-surface-2);
          border: 1px solid var(--border-primary);
          border-radius: 10px;
          padding: 12px 14px;
          cursor: pointer;
          transition: background 0.15s, box-shadow 0.15s, border-color 0.15s;
          display: flex;
          flex-direction: column;
          gap: 8px;
          -webkit-tap-highlight-color: transparent;
        }
        .cm-mobile-card:active {
          transform: scale(0.99);
          background: var(--bg-hover);
        }
        .cm-mobile-card.cm-selected {
          background: var(--color-primary-light);
          border-color: var(--color-primary);
        }

        /* ── Pagination ──────────────────── */
        .cm-pagination {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 12px 16px;
          border-top: 1px solid var(--border-primary);
          gap: 8px;
        }
        .cm-pager-btn {
          padding: 7px 16px;
          border: 1px solid var(--border-primary);
          border-radius: 8px;
          background: var(--bg-surface);
          color: var(--text-primary);
          font-family: var(--font-sans);
          font-size: var(--text-xs);
          font-weight: 600;
          cursor: pointer;
          min-height: 36px;
          min-width: 80px;
          transition: background 0.15s;
        }
        .cm-pager-btn:hover:not(.cm-pager-disabled) {
          background: var(--bg-surface-2);
        }
        .cm-pager-btn.cm-pager-disabled {
          color: var(--text-muted);
          cursor: not-allowed;
          opacity: 0.5;
        }
        .cm-page-info {
          font-size: var(--text-xs);
          color: var(--text-muted);
          text-align: center;
          white-space: nowrap;
        }
        .cm-page-info-full { }
        @media (max-width: 400px) {
          .cm-pager-btn        { padding: 6px 10px; min-width: 64px; font-size: 0.7rem; }
          .cm-page-info-full   { display: none; }
        }

        /* ── Table Row Hover ─────────────── */
        .credit-table-row:hover {
          background: var(--bg-surface-2) !important;
        }
      `}</style>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// CreditRow — Desktop Table
// ─────────────────────────────────────────────────────────────
function CreditRow({
  customer, overdueInfo, isSelected, onClick,
}: {
  customer:    CreditCustomerRow
  overdueInfo: OverdueInfo | undefined
  isSelected:  boolean
  onClick:     () => void
}) {
  const state = computeCreditState({
    payment_terms:   customer.payment_terms,
    credit_limit:    customer.credit_limit,
    current_balance: customer.current_balance,
  })

  const pct       = state.type === 'credit' ? Math.round(state.usedPct * 100) : 0
  const available = state.type === 'credit' ? state.available : null
  const accent    = state.type === 'credit'  ? state.accent   :
                    state.type === 'cash'     ? '#2563eb'      : '#64748b'
  const stateLabel = state.type === 'credit'   ? state.label       :
                     state.type === 'cash'      ? 'نقدي'            :
                     state.type === 'no_limit'  ? 'غير محدود'       : '—'

  const termsLabel: Record<string, string> = {
    cash: 'نقدي', credit: 'آجل', mixed: 'مختلط',
  }

  const tdBase: React.CSSProperties = {
    padding: '10px 12px', whiteSpace: 'nowrap',
  }

  return (
    <tr
      onClick={onClick}
      className="credit-table-row"
      style={{
        cursor:       'pointer',
        background:   isSelected ? 'var(--color-primary-light)' : 'transparent',
        borderBottom: '1px solid var(--border-primary)',
        transition:   'background 0.12s',
      }}
    >
      {/* اسم */}
      <td style={{ ...tdBase, fontWeight: 700, color: 'var(--text-primary)', maxWidth: 200 }}>
        <div style={{ maxWidth: 190, overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {customer.name}
        </div>
      </td>

      {/* كود */}
      <td style={{ ...tdBase, fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
        {customer.code || '—'}
      </td>

      {/* مندوب */}
      <td style={{ ...tdBase, fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>
        {(customer.assigned_rep as any)?.full_name || '—'}
      </td>

      {/* طريقة الدفع */}
      <td style={tdBase}>
        <span style={{
          background: accent + '18', color: accent,
          borderRadius: 99, padding: '2px 8px', fontWeight: 600,
          fontSize: 'var(--text-xs)',
        }}>
          {termsLabel[customer.payment_terms] || customer.payment_terms}
        </span>
      </td>

      {/* الحد */}
      <td style={{ ...tdBase, fontSize: 'var(--text-sm)', fontWeight: 600, color: 'var(--text-primary)' }}>
        {state.type === 'credit'   ? `${formatNumber(state.limit)} ج.م` :
         state.type === 'no_limit' ? '∞'                                : '—'}
      </td>

      {/* الرصيد */}
      <td style={{ ...tdBase, fontSize: 'var(--text-sm)', fontWeight: 600, color: accent }}>
        {formatNumber(customer.current_balance || 0)} ج.م
      </td>

      {/* المتاح */}
      <td style={tdBase}>
        {available != null ? (
          <span style={{
            fontWeight: 700, fontSize: 'var(--text-sm)',
            color: available > 0 ? '#16a34a' : '#dc2626',
          }}>
            {formatNumber(available)} ج.م
          </span>
        ) : '—'}
      </td>

      {/* نسبة الاستخدام */}
      <td style={{ ...tdBase, minWidth: 80 }}>
        {state.type === 'credit' ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <div style={{ flex: 1, height: 5, borderRadius: 99, background: 'var(--bg-surface-2)', overflow: 'hidden' }}>
              <div style={{
                height: '100%', width: `${pct}%`,
                borderRadius: 99, background: accent,
                transition: 'width 0.3s ease',
              }} />
            </div>
            <span style={{ fontSize: '0.65rem', color: accent, fontWeight: 700, flexShrink: 0 }}>
              {pct}%
            </span>
          </div>
        ) : '—'}
      </td>

      {/* مدة السداد */}
      <td style={{ ...tdBase, fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>
        {customer.credit_days ? `${customer.credit_days} يوم` : '—'}
      </td>

      {/* الحالة */}
      <td style={tdBase}>
        <span style={{
          fontSize: 'var(--text-xs)', fontWeight: 700,
          color: accent, background: accent + '18',
          borderRadius: 99, padding: '2px 8px',
        }}>
          {stateLabel}
        </span>
      </td>

      {/* التأخر */}
      <td style={tdBase}>
        {overdueInfo?.hasOverdue ? (
          <span style={{
            fontSize: 'var(--text-xs)', fontWeight: 700,
            color: '#dc2626', background: 'rgba(220,38,38,0.1)',
            borderRadius: 99, padding: '2px 8px',
            display: 'inline-flex', alignItems: 'center', gap: 4,
          }}>
            ⚠️ {overdueInfo.overdueCount}
          </span>
        ) : (
          <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>—</span>
        )}
      </td>
    </tr>
  )
}

// ─────────────────────────────────────────────────────────────
// CreditMobileCard — Mobile Card (≤ 768px)
// ─────────────────────────────────────────────────────────────
function CreditMobileCard({
  customer, overdueInfo, isSelected, onClick,
}: {
  customer:    CreditCustomerRow
  overdueInfo: OverdueInfo | undefined
  isSelected:  boolean
  onClick:     () => void
}) {
  const state = computeCreditState({
    payment_terms:   customer.payment_terms,
    credit_limit:    customer.credit_limit,
    current_balance: customer.current_balance,
  })

  const pct        = state.type === 'credit' ? Math.round(state.usedPct * 100) : 0
  const available  = state.type === 'credit' ? state.available : null
  const accent     = state.type === 'credit'  ? state.accent   :
                     state.type === 'cash'     ? '#2563eb'      : '#64748b'
  const stateLabel = state.type === 'credit'   ? state.label    :
                     state.type === 'cash'      ? 'نقدي'         :
                     state.type === 'no_limit'  ? 'غير محدود'    : '—'

  const termsLabel: Record<string, string> = {
    cash: 'نقدي', credit: 'آجل', mixed: 'مختلط',
  }

  return (
    <div
      onClick={onClick}
      className={`cm-mobile-card${isSelected ? ' cm-selected' : ''}`}
    >
      {/* ── Row 1: Name + State Badge ─── */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
        <span style={{
          fontWeight: 700, fontSize: 'var(--text-base)',
          color: 'var(--text-primary)',
          flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
        }}>
          {customer.name}
        </span>
        <span style={{
          fontSize: 'var(--text-xs)', fontWeight: 700,
          color: accent, background: accent + '18',
          borderRadius: 99, padding: '2px 8px', flexShrink: 0,
        }}>
          {stateLabel}
        </span>
      </div>

      {/* ── Row 2: Meta — Code, Rep, Terms, Days ─── */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
        {customer.code && (
          <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFeatureSettings: '"tnum"' }}>
            {customer.code}
          </span>
        )}
        {(customer.assigned_rep as any)?.full_name && (
          <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>
            • {(customer.assigned_rep as any).full_name}
          </span>
        )}
        <span style={{
          fontSize: 'var(--text-xs)', fontWeight: 600,
          color: accent, background: accent + '18',
          borderRadius: 99, padding: '1px 7px',
        }}>
          {termsLabel[customer.payment_terms] || customer.payment_terms}
        </span>
        {customer.credit_days ? (
          <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
            {customer.credit_days} يوم
          </span>
        ) : null}
      </div>

      {/* ── Row 3: Financial Figures 2-column ─── */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
        <div style={{ background: 'var(--bg-surface)', borderRadius: 8, padding: '7px 10px' }}>
          <div style={{ fontSize: '0.65rem', color: 'var(--text-muted)', marginBottom: 2 }}>الرصيد</div>
          <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: accent }}>
            {formatNumber(customer.current_balance || 0)}{' '}
            <span style={{ fontSize: '0.65rem', fontWeight: 400, color: 'var(--text-muted)' }}>ج.م</span>
          </div>
        </div>

        {available != null ? (
          <div style={{ background: 'var(--bg-surface)', borderRadius: 8, padding: '7px 10px' }}>
            <div style={{ fontSize: '0.65rem', color: 'var(--text-muted)', marginBottom: 2 }}>المتاح</div>
            <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: available > 0 ? '#16a34a' : '#dc2626' }}>
              {formatNumber(available)}{' '}
              <span style={{ fontSize: '0.65rem', fontWeight: 400, color: 'var(--text-muted)' }}>ج.م</span>
            </div>
          </div>
        ) : (
          <div style={{ background: 'var(--bg-surface)', borderRadius: 8, padding: '7px 10px' }}>
            <div style={{ fontSize: '0.65rem', color: 'var(--text-muted)', marginBottom: 2 }}>الحد</div>
            <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>—</div>
          </div>
        )}
      </div>

      {/* ── Row 4: Progress bar + Overdue ─── */}
      {state.type === 'credit' ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{ flex: 1, height: 5, borderRadius: 99, background: 'var(--bg-surface)', overflow: 'hidden' }}>
            <div style={{
              height: '100%', width: `${pct}%`,
              borderRadius: 99, background: accent,
              transition: 'width 0.35s ease',
            }} />
          </div>
          <span style={{ fontSize: '0.65rem', color: accent, fontWeight: 700, flexShrink: 0 }}>{pct}%</span>
          {overdueInfo?.hasOverdue && (
            <span style={{
              fontSize: 'var(--text-xs)', fontWeight: 700,
              color: '#dc2626', background: 'rgba(220,38,38,0.1)',
              borderRadius: 99, padding: '2px 8px',
              display: 'inline-flex', alignItems: 'center', gap: 4, flexShrink: 0,
            }}>
              ⚠️ {overdueInfo.overdueCount} متأخرة
            </span>
          )}
        </div>
      ) : overdueInfo?.hasOverdue ? (
        <span style={{
          fontSize: 'var(--text-xs)', fontWeight: 700,
          color: '#dc2626', background: 'rgba(220,38,38,0.1)',
          borderRadius: 99, padding: '2px 8px',
          display: 'inline-flex', alignItems: 'center', gap: 4, alignSelf: 'flex-start',
        }}>
          ⚠️ {overdueInfo.overdueCount} متأخرة
        </span>
      ) : null}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

function TableSkeleton() {
  return (
    <div style={{ padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 8 }}>
      {Array.from({ length: 8 }).map((_, i) => (
        <div key={i} className="skeleton" style={{ height: 44, borderRadius: 8 }} />
      ))}
    </div>
  )
}

function EmptyState() {
  return (
    <div style={{ padding: '60px 40px', textAlign: 'center', color: 'var(--text-muted)' }}>
      <div style={{ fontSize: '3rem', marginBottom: 12 }}>🏦</div>
      <div style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 6 }}>
        لا يوجد عملاء ائتمانيون
      </div>
      <div style={{ fontSize: 'var(--text-sm)' }}>
        لا يوجد عملاء آجلون أو مختلطون مطابقون للبحث أو الفلتر الحالي
      </div>
    </div>
  )
}
