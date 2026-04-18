/**
 * CreditManagementPage — صفحة إدارة الائتمان v3
 *
 * الجديد في v3:
 *   - filter model احترافي كامل مع advanced filters قابل للطي
 *   - server-side: search, paymentTerms, repId, balanceState,
 *     currentBalanceMin/Max, creditLimitMin/Max, sortBy
 *   - DocumentActions مدمج في الـ Header للطباعة/PDF
 *   - كل تغيير فلتر يعيد page إلى 1
 *   - الطباعة تعتمد على كل النتائج المطابقة للفلاتر (لا page الحالية)
 */

import { useState, useEffect, useCallback, useRef } from 'react'
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
import { DocumentActions }      from '@/features/output/components/DocumentActions'
import type { Customer }        from '@/lib/types/master-data'
import { supabase }             from '@/lib/supabase/client'

// ─────────────────────────────────────────────────────────────
// Filter Model
// ─────────────────────────────────────────────────────────────

type BalanceState = 'all' | 'with-balance-only' | 'near-limit' | 'exceeded' | 'no-limit'
type SortBy       = 'name' | 'current_balance_desc' | 'available_asc' | 'utilization_desc' | 'overdue_count_desc'

interface CreditFilters {
  search:            string
  paymentTerms:      '' | 'credit' | 'mixed'
  repId:             string
  balanceState:      BalanceState
  currentBalanceMin: string
  currentBalanceMax: string
  creditLimitMin:    string
  creditLimitMax:    string
  sortBy:            SortBy
}

const DEFAULT_FILTERS: CreditFilters = {
  search:            '',
  paymentTerms:      '',
  repId:             '',
  balanceState:      'all',
  currentBalanceMin: '',
  currentBalanceMax: '',
  creditLimitMin:    '',
  creditLimitMax:    '',
  sortBy:            'name',
}

function hasAdvancedFilters(f: CreditFilters): boolean {
  return (
    f.balanceState      !== 'all' ||
    f.currentBalanceMin !== ''    ||
    f.currentBalanceMax !== ''    ||
    f.creditLimitMin    !== ''    ||
    f.creditLimitMax    !== ''    ||
    f.sortBy            !== 'name'
  )
}

// ─────────────────────────────────────────────────────────────
// تحويل الفلاتر إلى params لـ DocumentActions
// (سلاسل نصية فقط لأن params في الـ hook من نوع Record<string, string>)
// ─────────────────────────────────────────────────────────────

function filtersToParams(f: CreditFilters): Record<string, string> {
  const p: Record<string, string> = {}
  if (f.search)            p['search']            = f.search
  if (f.paymentTerms)      p['paymentTerms']       = f.paymentTerms
  if (f.repId)             p['repId']              = f.repId
  if (f.balanceState !== 'all') p['balanceState']  = f.balanceState
  if (f.currentBalanceMin) p['currentBalanceMin']  = f.currentBalanceMin
  if (f.currentBalanceMax) p['currentBalanceMax']  = f.currentBalanceMax
  if (f.creditLimitMin)    p['creditLimitMin']     = f.creditLimitMin
  if (f.creditLimitMax)    p['creditLimitMax']     = f.creditLimitMax
  if (f.sortBy !== 'name') p['sortBy']             = f.sortBy
  return p
}

// ─────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────
export default function CreditManagementPage() {
  const qc = useQueryClient()

  // ── Filter State ──────────────────────────────────────────
  const [filters,        setFilters]        = useState<CreditFilters>(DEFAULT_FILTERS)
  const [inputValue,     setInputValue]     = useState('')
  const [page,           setPage]           = useState(1)
  const [paper,          setPaper]          = useState<'a4-landscape' | 'a4-portrait'>('a4-landscape')
  const [showAdvanced,   setShowAdvanced]   = useState(false)

  // جلب قائمة المندوبين للفلتر
  const { data: repsData } = useQuery({
    queryKey: ['profiles-for-credit-filter'],
    queryFn:  async () => {
      const { data } = await supabase
        .from('profiles')
        .select('id, full_name')
        .eq('status', 'active')
        .order('full_name')
      return data || []
    },
    staleTime: 10 * 60_000,
  })

  // Debounced search — 350ms
  const searchTimer = useRef<ReturnType<typeof setTimeout>>()
  useEffect(() => {
    clearTimeout(searchTimer.current)
    searchTimer.current = setTimeout(() => {
      setFilters(prev => ({ ...prev, search: inputValue }))
      setPage(1)
    }, 350)
    return () => clearTimeout(searchTimer.current)
  }, [inputValue])

  // أي تغيير فلتر يعيد page إلى 1
  const updateFilter = useCallback(<K extends keyof CreditFilters>(
    key: K,
    value: CreditFilters[K]
  ) => {
    setFilters(prev => ({ ...prev, [key]: value }))
    setPage(1)
  }, [])

  // ── Customers Query ───────────────────────────────────────
  const { data: result, isLoading } = useQuery({
    queryKey: ['credit-customers', { ...filters, page }],
    queryFn:  () => getCreditCustomers({
      search:            filters.search            || undefined,
      paymentTerms:      filters.paymentTerms      || undefined,
      repId:             filters.repId             || undefined,
      balanceState:      filters.balanceState !== 'all' ? filters.balanceState : undefined,
      currentBalanceMin: filters.currentBalanceMin ? parseFloat(filters.currentBalanceMin) : undefined,
      currentBalanceMax: filters.currentBalanceMax ? parseFloat(filters.currentBalanceMax) : undefined,
      creditLimitMin:    filters.creditLimitMin    ? parseFloat(filters.creditLimitMin)    : undefined,
      creditLimitMax:    filters.creditLimitMax    ? parseFloat(filters.creditLimitMax)    : undefined,
      sortBy:            filters.sortBy !== 'name' ? filters.sortBy : undefined,
      page,
    }),
    staleTime:       2 * 60_000,
    placeholderData: (prev: any) => prev,
  })

  const customers  = result?.data       ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count      ?? 0

  // ── Overdue Batch ─────────────────────────────────────────
  const customerIds = customers.map(c => c.id)

  const { data: overdueMap } = useQuery<Record<string, OverdueInfo>>({
    queryKey: ['overdue-batch', customerIds],
    queryFn:  () => getOverdueBatch(customerIds),
    staleTime: 2 * 60_000,
    enabled:   customerIds.length > 0,
  })

  // ── Selected Customer (Drawer) ────────────────────────────
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

  // ── Escape key ────────────────────────────────────────────
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && selectedCustomer) closePanel()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [selectedCustomer, closePanel])

  const activeFilterCount =
    (filters.paymentTerms      ? 1 : 0) +
    (filters.repId             ? 1 : 0) +
    (filters.balanceState !== 'all' ? 1 : 0) +
    (filters.currentBalanceMin ? 1 : 0) +
    (filters.currentBalanceMax ? 1 : 0) +
    (filters.creditLimitMin    ? 1 : 0) +
    (filters.creditLimitMax    ? 1 : 0) +
    (filters.sortBy !== 'name' ? 1 : 0)

  const printParams = filtersToParams(filters)

  // ─────────────────────────────────────────────────────────
  return (
    <div id="credit-management-page" className="cm-page animate-enter">

      {/* ── Page Header ────────────────────────────────────── */}
      <div className="cm-header">
        <div>
          <h1 className="cm-title">🏦 إدارة الائتمان</h1>
          <p className="cm-subtitle">المحفظة الائتمانية للعملاء الآجلين والمختلطين</p>
        </div>

        <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
          {/* ── Paper Selector ────────────────────────────── */}
          <select 
            value={paper} 
            onChange={e => setPaper(e.target.value as any)}
            className="filter-select"
            title="اختر مقاس الورقة للطباعة"
            style={{ 
              padding: '6px 12px', 
              fontSize: '13px', 
              borderRadius: '4px', 
              border: '1px solid #ddd',
              backgroundColor: '#fff',
              outline: 'none',
              cursor: 'pointer'
            }}
          >
            <option value="a4-landscape">📄 A4 بالعرض</option>
            <option value="a4-portrait">📄 A4 بالطول</option>
          </select>

          {/* ── Print / PDF Actions ─────────────────────── */}
          <DocumentActions
            kind="credit-portfolio-report"
            entityId="all"
            paperProfileId={paper}
            params={printParams}
            compact={true}
          />

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
      </div>

      {/* ── KPI Bar ────────────────────────────────────────── */}
      <CreditKPIBar filters={{
        search:            filters.search            || undefined,
        paymentTerms:      filters.paymentTerms      || undefined,
        repId:             filters.repId             || undefined,
        balanceState:      filters.balanceState !== 'all' ? filters.balanceState : undefined,
        currentBalanceMin: filters.currentBalanceMin ? parseFloat(filters.currentBalanceMin) : undefined,
        currentBalanceMax: filters.currentBalanceMax ? parseFloat(filters.currentBalanceMax) : undefined,
        creditLimitMin:    filters.creditLimitMin    ? parseFloat(filters.creditLimitMin)    : undefined,
        creditLimitMax:    filters.creditLimitMax    ? parseFloat(filters.creditLimitMax)    : undefined,
      }} />

      {/* ── Filters ─────────────────────────────────────────── */}
      <div className="cm-filters-container">

        {/* ── الصف الأول: بحث + طريقة الدفع + المندوب ─── */}
        <div className="cm-filters-row1">

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

          {/* طريقة الدفع */}
          <select
            id="credit-filter-terms"
            value={filters.paymentTerms}
            onChange={e => updateFilter('paymentTerms', e.target.value as '' | 'credit' | 'mixed')}
            className="form-input cm-filter-select"
          >
            <option value="">الآجل والمختلط</option>
            <option value="credit">آجل فقط</option>
            <option value="mixed">مختلط فقط</option>
          </select>

          {/* المندوب */}
          <select
            id="credit-filter-rep"
            value={filters.repId}
            onChange={e => updateFilter('repId', e.target.value)}
            className="form-input cm-filter-select"
          >
            <option value="">كل المندوبين</option>
            {(repsData ?? []).map((r: any) => (
              <option key={r.id} value={r.id}>{r.full_name}</option>
            ))}
          </select>

          {/* زر الفلاتر المتقدمة */}
          <button
            id="credit-advanced-toggle"
            onClick={() => setShowAdvanced(v => !v)}
            className={`cm-pager-btn${hasAdvancedFilters(filters) ? ' cm-advanced-active' : ''}`}
            style={{ flexShrink: 0, display: 'flex', alignItems: 'center', gap: 6 }}
          >
            <span>⚙</span>
            <span>متقدم</span>
            {activeFilterCount > 0 && (
              <span style={{
                background: 'var(--color-primary)',
                color: '#fff',
                borderRadius: 99,
                padding: '1px 6px',
                fontSize: '0.65rem',
                fontWeight: 800,
              }}>{activeFilterCount}</span>
            )}
          </button>

          {/* إعادة تعيين — فقط إذا هناك فلاتر فعالة */}
          {activeFilterCount > 0 && (
            <button
              id="credit-reset-filters"
              onClick={() => {
                setFilters(DEFAULT_FILTERS)
                setInputValue('')
                setPage(1)
              }}
              className="cm-pager-btn"
              style={{ flexShrink: 0, color: 'var(--color-danger)', borderColor: 'var(--color-danger)' }}
            >
              ✕ إعادة تعيين
            </button>
          )}
        </div>

        {/* ── الصف الثاني: الفلاتر المتقدمة ─────────────── */}
        {showAdvanced && (
          <div className="cm-filters-advanced">
            {/* حالة الرصيد */}
            <div className="cm-filter-group">
              <label className="cm-filter-label">حالة الائتمان</label>
              <select
                id="credit-filter-balance-state"
                value={filters.balanceState}
                onChange={e => updateFilter('balanceState', e.target.value as BalanceState)}
                className="form-input cm-filter-select"
                style={{ width: '100%' }}
              >
                <option value="all">الكل</option>
                <option value="with-balance-only">لديهم رصيد {'>'} 0</option>
                <option value="near-limit">قريبون من الحد (≥80%)</option>
                <option value="exceeded">تجاوزوا الحد</option>
                <option value="no-limit">بلا حد ائتماني</option>
              </select>
            </div>

            {/* ترتيب النتائج */}
            <div className="cm-filter-group">
              <label className="cm-filter-label">ترتيب النتائج</label>
              <select
                id="credit-filter-sort"
                value={filters.sortBy}
                onChange={e => updateFilter('sortBy', e.target.value as SortBy)}
                className="form-input cm-filter-select"
                style={{ width: '100%' }}
              >
                <option value="name">الاسم (أبجدي)</option>
                <option value="current_balance_desc">الرصيد (تنازلياً)</option>
                <option value="available_asc">المتاح (تصاعدياً)</option>
                <option value="utilization_desc">الاستخدام % (تنازلياً)</option>
              </select>
            </div>

            {/* نطاق الرصيد الحالي */}
            <div className="cm-filter-group">
              <label className="cm-filter-label">الرصيد الحالي (ج.م)</label>
              <div style={{ display: 'flex', gap: 6 }}>
                <input
                  id="credit-filter-bal-min"
                  type="number"
                  min="0"
                  placeholder="من"
                  dir="ltr"
                  value={filters.currentBalanceMin}
                  onChange={e => updateFilter('currentBalanceMin', e.target.value)}
                  className="form-input"
                  style={{ width: '50%' }}
                />
                <input
                  id="credit-filter-bal-max"
                  type="number"
                  min="0"
                  placeholder="إلى"
                  dir="ltr"
                  value={filters.currentBalanceMax}
                  onChange={e => updateFilter('currentBalanceMax', e.target.value)}
                  className="form-input"
                  style={{ width: '50%' }}
                />
              </div>
            </div>

            {/* نطاق الحد الائتماني */}
            <div className="cm-filter-group">
              <label className="cm-filter-label">الحد الائتماني (ج.م)</label>
              <div style={{ display: 'flex', gap: 6 }}>
                <input
                  id="credit-filter-limit-min"
                  type="number"
                  min="0"
                  placeholder="من"
                  dir="ltr"
                  value={filters.creditLimitMin}
                  onChange={e => updateFilter('creditLimitMin', e.target.value)}
                  className="form-input"
                  style={{ width: '50%' }}
                />
                <input
                  id="credit-filter-limit-max"
                  type="number"
                  min="0"
                  placeholder="إلى"
                  dir="ltr"
                  value={filters.creditLimitMax}
                  onChange={e => updateFilter('creditLimitMax', e.target.value)}
                  className="form-input"
                  style={{ width: '50%' }}
                />
              </div>
            </div>
          </div>
        )}
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

        /* ── Filters Container ────────────── */
        .cm-filters-container {
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: 12px;
          padding: var(--space-4);
          margin-bottom: var(--space-3);
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
        }
        .cm-filters-row1 {
          display: flex;
          gap: var(--space-3);
          flex-wrap: wrap;
          align-items: center;
        }
        .cm-filter-select {
          width: auto;
          min-width: 140px;
          flex-shrink: 0;
        }
        @media (max-width: 640px) {
          .cm-filters-row1 { flex-direction: column; align-items: stretch; }
          .cm-filter-select { min-width: unset; width: 100% !important; }
        }

        /* ── Advanced Filters Panel ──────── */
        .cm-filters-advanced {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
          gap: var(--space-3);
          border-top: 1px solid var(--border-primary);
          padding-top: var(--space-3);
          animation: fade-in 0.15s ease;
        }
        @keyframes fade-in {
          from { opacity: 0; transform: translateY(-4px); }
          to   { opacity: 1; transform: translateY(0); }
        }
        .cm-filter-group {
          display: flex;
          flex-direction: column;
          gap: 6px;
        }
        .cm-filter-label {
          font-size: var(--text-xs);
          font-weight: 600;
          color: var(--text-secondary);
        }
        .cm-advanced-active {
          background: var(--color-primary-light) !important;
          border-color: var(--color-primary) !important;
          color: var(--color-primary) !important;
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

      {/* ── Row 2: Meta ─── */}
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

      {/* ── Row 3: Financial ─── */}
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

      {/* ── Row 4: Progress + Overdue ─── */}
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
