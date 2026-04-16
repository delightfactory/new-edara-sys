/**
 * CreditManagementPage — صفحة إدارة الائتمان
 *
 * غرفة قيادة ائتمانية تشمل:
 *   - شريط KPIs للمحفظة (6 مؤشرات)
 *   - جدول العملاء الائتمانيين — pagination حقيقي 25 عميل server-side
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
  // SQL تحكم على التأخر داخلياً (credit_days JOIN) — لا مقارنة JS
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
    <div
      id="credit-management-page"
      className="animate-enter"
      style={{ padding: 'var(--space-5)', minHeight: '100vh', background: 'var(--bg-app)' }}
    >
      {/* ── Page Header ─────────────────────────────────────── */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        marginBottom: 'var(--space-4)',
      }}>
        <div>
          <h1 style={{
            fontSize: 'var(--text-2xl)', fontWeight: 800,
            color: 'var(--text-primary)', margin: 0,
          }}>
            🏦 إدارة الائتمان
          </h1>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)', margin: '4px 0 0' }}>
            المحفظة الائتمانية للعملاء الآجلين والمختلطين
          </p>
        </div>

        <button
          id="credit-refresh-btn"
          onClick={() => {
            qc.invalidateQueries({ queryKey: ['credit-customers'] })
            qc.invalidateQueries({ queryKey: ['credit-portfolio-kpis'] })
          }}
          style={{
            border: '1px solid var(--border-primary)', background: 'var(--bg-surface)',
            borderRadius: 8, padding: '7px 14px', cursor: 'pointer',
            color: 'var(--text-secondary)', fontFamily: 'var(--font-sans)',
            fontSize: 'var(--text-sm)', fontWeight: 600,
            display: 'flex', alignItems: 'center', gap: 6,
          }}
        >
          ↺ تحديث
        </button>
      </div>

      {/* ── KPI Bar ──────────────────────────────────────────── */}
      <CreditKPIBar />

      {/* ── Filters & Search ─────────────────────────────────── */}
      <div style={{
        display: 'flex', gap: 'var(--space-3)',
        marginBottom: 'var(--space-3)',
        flexWrap: 'wrap', alignItems: 'center',
      }}>
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
          className="form-input"
          style={{ width: 'auto', minWidth: 150 }}
        >
          <option value="">الآجل والمختلط</option>
          <option value="credit">آجل فقط</option>
          <option value="mixed">مختلط فقط</option>
        </select>
      </div>

      {/* ── Info Bar ─────────────────────────────────────────── */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        marginBottom: 'var(--space-2)',
        fontSize: 'var(--text-xs)', color: 'var(--text-muted)',
      }}>
        <span>
          {isLoading
            ? 'جاري التحميل...'
            : `${customers.length} في الصفحة — إجمالي ${totalCount} عميل ائتماني`
          }
        </span>
        <span>صفحة {page} من {totalPages}</span>
      </div>

      {/* ── Table ────────────────────────────────────────────── */}
      <div style={{
        background: 'var(--bg-surface)', borderRadius: 12,
        border: '1px solid var(--border-primary)', boxShadow: 'var(--shadow-sm)',
        overflow: 'hidden',
      }}>
        {isLoading ? (
          <TableSkeleton />
        ) : !customers.length ? (
          <EmptyState />
        ) : (
          <>
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

            {/* Pagination */}
            <div style={{
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              padding: '12px 16px', borderTop: '1px solid var(--border-primary)',
            }}>
              <button
                id="credit-prev-page"
                onClick={() => setPage(p => Math.max(1, p - 1))}
                disabled={page <= 1}
                style={pagerBtnStyle(page <= 1)}
              >← السابق</button>

              <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                {page} / {totalPages} ({totalCount} عميل)
              </span>

              <button
                id="credit-next-page"
                onClick={() => setPage(p => Math.min(totalPages, p + 1))}
                disabled={page >= totalPages}
                style={pagerBtnStyle(page >= totalPages)}
              >التالي →</button>
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
          {/* CreditCustomerRow → Customer cast للوحة الجانبية */}
          <CustomerCreditPanel
            customer={selectedCustomer as unknown as Customer}
            onClose={closePanel}
            onUpdated={handleUpdated}
          />
        </>
      )}

      <style>{`
        .credit-table-row:hover {
          background: var(--bg-surface-2) !important;
        }
      `}</style>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// CreditRow
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

function pagerBtnStyle(disabled: boolean): React.CSSProperties {
  return {
    padding: '6px 14px', border: '1px solid var(--border-primary)',
    borderRadius: 8, background: 'var(--bg-surface)',
    color: disabled ? 'var(--text-muted)' : 'var(--text-primary)',
    fontFamily: 'var(--font-sans)', fontSize: 'var(--text-xs)',
    fontWeight: 600,
    cursor: disabled ? 'not-allowed' : 'pointer',
    opacity: disabled ? 0.5 : 1,
  }
}
