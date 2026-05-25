import { useState, useMemo, useEffect } from 'react'
import { PackageSearch, AlertTriangle, Package, BarChart2, ClipboardList, X, RotateCcw, Warehouse } from 'lucide-react'
import { useStock, useWarehouses } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { Stock } from '@/lib/types/master-data'
import { formatNumber, formatCurrency } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import { ProductLink, WarehouseLink } from '@/components/shared/EntityLink'
import Badge from '@/components/ui/Badge'

// ── Status helpers ────────────────────────────────────────────
function stockStatus(s: Stock): { variant: 'danger' | 'warning' | 'success'; label: string; color: string } {
  if (s.available_quantity <= 0)    return { variant: 'danger',  label: 'نفد',    color: 'var(--color-danger)'  }
  if (s.product && s.quantity <= (s.product as any).min_stock_level)
                                    return { variant: 'warning', label: 'منخفض', color: 'var(--color-warning)' }
  return                                   { variant: 'success', label: 'كافي',  color: 'var(--color-success)' }
}

type StockStatusFilter = 'all' | 'with_stock' | 'out_of_stock' | 'reserved'

// ── Diff color helper ─────────────────────────────────────────
function diffColor(diff: number): string {
  if (diff > 0) return 'var(--color-primary)'
  if (diff < 0) return 'var(--color-danger)'
  return 'var(--text-muted)'
}

export default function StockPage() {
  const can = useAuthStore(s => s.can)
  const canViewCosts = can('finance.view_costs')

  // ── قراءة warehouseId من URL عند التحميل ─────────────────
  const initialWarehouseId = useMemo(() => {
    if (typeof window === 'undefined') return ''
    return new URLSearchParams(window.location.search).get('warehouseId') || ''
  }, [])

  const [search, setSearch]               = useState('')
  const [whFilter, setWhFilter]           = useState(initialWarehouseId)
  const [lowStockOnly, setLowStockOnly]   = useState(false)
  const [stockStatus2, setStockStatus2]   = useState<StockStatusFilter>('all')
  const [page, setPage]                   = useState(1)

  // ── وضع مراجعة الجرد (محلي فقط — لا حفظ، لا تسويات) ─────
  const [reviewMode, setReviewMode]       = useState(false)
  const [actualCounts, setActualCounts]   = useState<Record<string, string>>({})

  const { data: warehouses = [] } = useWarehouses()

  // لا يمكن الجمع بين lowStockOnly و stockStatus — lowStockOnly له أولوية
  const effectiveStockStatus = lowStockOnly ? 'all' : stockStatus2

  const queryParams = useMemo(() => ({
    search: lowStockOnly ? undefined : search, // البحث معطل في وضع lowStockOnly لتجنب نتائج مضللة
    warehouseId: whFilter,
    lowStockOnly,
    stockStatus: effectiveStockStatus,
    page,
    pageSize: 25,
  }), [search, whFilter, lowStockOnly, effectiveStockStatus, page])

  const { data: result, isLoading: loading } = useStock(queryParams)
  const stock        = result?.data ?? []
  const totalPages   = result?.totalPages ?? 1
  const totalCount   = result?.count ?? 0
  const searchBlocked = result?.searchDisabledInLowStockMode ?? false

  // ── ملخص النتائج المعروضة (الصفحة الحالية فقط) ───────────
  const pageSummary = useMemo(() => ({
    items:     stock.length,
    totalQty:  stock.reduce((s, r) => s + r.quantity, 0),
    available: stock.reduce((s, r) => s + r.available_quantity, 0),
    reserved:  stock.reduce((s, r) => s + r.reserved_quantity, 0),
  }), [stock])

  const selectedWarehouse = warehouses.find(w => w.id === whFilter)

  // إعادة ضبط الصفحة عند تغيير الفلاتر
  useEffect(() => { setPage(1) }, [search, whFilter, lowStockOnly, stockStatus2])

  const outOfStock = stock.filter(s => s.available_quantity <= 0).length
  const lowStock   = stock.filter(s => s.available_quantity > 0 && s.product && s.quantity <= (s.product as any).min_stock_level).length

  // ── وضع المراجعة: حساب الفرق محلياً ─────────────────────
  function getActual(id: string): number | null {
    const v = actualCounts[id]
    if (v === undefined || v === '') return null
    const n = parseFloat(v)
    return isNaN(n) ? null : n
  }
  function getDiff(s: Stock): number | null {
    const a = getActual(s.id)
    if (a === null) return null
    return a - s.available_quantity
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title={reviewMode ? 'أرصدة المخزون — وضع مراجعة الجرد' : 'أرصدة المخزون'}
        subtitle={loading ? '...' : `${totalCount} سجل`}
        actions={
          <button
            className={`btn btn-sm ${reviewMode ? 'btn-warning' : 'btn-ghost'}`}
            onClick={() => { setReviewMode(v => !v); setActualCounts({}) }}
          >
            <ClipboardList size={14} />
            {reviewMode ? 'إلغاء وضع المراجعة' : 'وضع مراجعة الجرد'}
          </button>
        }
      />

      {/* ── تنبيه وضع المراجعة ──────────────────────────────── */}
      {reviewMode && (
        <div className="review-banner">
          <ClipboardList size={15} />
          <span>هذه مراجعة محلية لا تنشئ تسوية ولا تحفظ العد الفعلي. المقارنة تتم مع <strong>المتاح</strong>.</span>
          <button className="btn btn-ghost btn-xs" onClick={() => setActualCounts({})}>
            <RotateCcw size={12} /> تصفير الأعداد
          </button>
        </div>
      )}

      {/* ── تنبيه تعطيل البحث مع lowStockOnly ──────────────── */}
      {searchBlocked && search.trim() && (
        <div className="review-banner review-banner--warning">
          <AlertTriangle size={14} />
          <span>البحث النصي غير متاح عند تفعيل فلتر «أقل من الحد الأدنى» لأن الفلترة تتم على مستوى قاعدة البيانات بالكامل. أوقف الفلتر لاستخدام البحث.</span>
        </div>
      )}

      {/* ── Health summary ──────────────────────────────────── */}
      <div className="stock-health-grid" style={{ marginBottom: 'var(--space-4)' }}>
        <div className="edara-card stock-health-card">
          <div className="shc-icon shc-icon-total"><Package size={18} /></div>
          <div className="shc-value">{totalCount}</div>
          <div className="shc-label">إجمالي الأصناف</div>
        </div>
        <div className={`edara-card stock-health-card ${outOfStock > 0 ? 'shc-alert-danger' : ''}`}>
          <div className="shc-icon shc-icon-danger"><AlertTriangle size={18} /></div>
          <div className="shc-value" style={{ color: outOfStock > 0 ? 'var(--color-danger)' : undefined }}>{outOfStock}</div>
          <div className="shc-label">نفد المخزون</div>
        </div>
        <div className={`edara-card stock-health-card ${lowStock > 0 ? 'shc-alert-warning' : ''}`}>
          <div className="shc-icon shc-icon-warning"><BarChart2 size={18} /></div>
          <div className="shc-value" style={{ color: lowStock > 0 ? 'var(--color-warning)' : undefined }}>{lowStock}</div>
          <div className="shc-label">مخزون منخفض</div>
        </div>
      </div>

      {/* ── ملخص المخزن المحدد ──────────────────────────────── */}
      {selectedWarehouse && (
        <div className="warehouse-context-card edara-card" style={{ marginBottom: 'var(--space-4)' }}>
          <div className="wcc-header">
            <Warehouse size={16} />
            <span>مراجعة أرصدة: <strong>{selectedWarehouse.name}</strong></span>
            <button className="btn btn-ghost btn-xs" onClick={() => setWhFilter('')}>
              <X size={12} /> إلغاء الفلتر
            </button>
          </div>
          <div className="wcc-stats">
            <div className="wcc-stat">
              <div className="wcc-stat-value">{pageSummary.items}</div>
              <div className="wcc-stat-label">صنف معروض</div>
            </div>
            <div className="wcc-stat">
              <div className="wcc-stat-value">{formatNumber(pageSummary.totalQty)}</div>
              <div className="wcc-stat-label">إجمالي الكمية</div>
            </div>
            <div className="wcc-stat">
              <div className="wcc-stat-value" style={{ color: 'var(--color-success)' }}>{formatNumber(pageSummary.available)}</div>
              <div className="wcc-stat-label">المتاح</div>
            </div>
            {pageSummary.reserved > 0 && (
              <div className="wcc-stat">
                <div className="wcc-stat-value" style={{ color: 'var(--color-warning)' }}>{formatNumber(pageSummary.reserved)}</div>
                <div className="wcc-stat-label">المحجوز</div>
              </div>
            )}
          </div>
          <div className="wcc-disclaimer">
            ⚠️ الأرقام التالية محسوبة من النتائج المعروضة حالياً فقط {totalPages > 1 ? `(صفحة ${page} من ${totalPages})` : ''}
          </div>
        </div>
      )}

      {/* ── Filters ──────────────────────────────────────────── */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div style={{ display: 'flex', gap: 'var(--space-3)', flexWrap: 'wrap', alignItems: 'center' }}>
          <div style={{ flex: 2, minWidth: 180 }}>
            <SearchInput
              value={search}
              onChange={val => setSearch(val)}
              placeholder="بحث بالمنتج أو الكود SKU..."
            />
          </div>
          <select className="form-select" style={{ flex: 1, minWidth: 120 }} value={whFilter}
            onChange={e => setWhFilter(e.target.value)}>
            <option value="">كل المخازن</option>
            {warehouses.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
          </select>

          {/* فلتر حالة الرصيد — معطل مع lowStockOnly */}
          {!lowStockOnly && (
            <select className="form-select" style={{ flex: 1, minWidth: 140 }}
              value={stockStatus2}
              onChange={e => setStockStatus2(e.target.value as StockStatusFilter)}>
              <option value="all">كل الأرصدة</option>
              <option value="with_stock">بأرصدة فقط</option>
              <option value="out_of_stock">نفد المخزون</option>
              <option value="reserved">به كمية محجوزة</option>
            </select>
          )}

          <label style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', fontSize: 'var(--text-sm)', cursor: 'pointer', whiteSpace: 'nowrap' }}>
            <input type="checkbox" checked={lowStockOnly} onChange={e => setLowStockOnly(e.target.checked)} />
            <AlertTriangle size={14} style={{ color: 'var(--color-warning)' }} />
            أقل من الحد الأدنى
          </label>
        </div>
      </div>

      {/* ── DESKTOP: DataTable ─────────────────────────────────── */}
      <div className="stock-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<Stock>
          columns={[
            {
              key: 'product', label: 'المنتج',
              render: s => (
                <ProductLink id={s.product?.id} name={s.product?.name} code={s.product?.sku} />
              ),
            },
            { key: 'warehouse', label: 'المخزن', render: s => <WarehouseLink name={s.warehouse?.name} /> },
            { key: 'quantity', label: 'الكمية', render: s => <span style={{ fontWeight: 600 }}>{formatNumber(s.quantity)}</span> },
            { key: 'reserved', label: 'المحجوز', hideOnMobile: true, render: s => formatNumber(s.reserved_quantity) },
            {
              key: 'available', label: 'المتاح',
              render: s => {
                const st = stockStatus(s)
                return <span style={{ fontWeight: 700, color: st.color }}>{formatNumber(s.available_quantity)}</span>
              },
            },
            ...(canViewCosts ? [
              { key: 'wac' as const, label: 'التكلفة المرجحة', hideOnMobile: true, render: (s: Stock) => formatCurrency(s.wac) },
              { key: 'value' as const, label: 'القيمة', hideOnMobile: true, render: (s: Stock) => <span style={{ fontWeight: 600 }}>{formatCurrency(s.total_cost_value)}</span> },
            ] : []),
            // أعمدة وضع المراجعة
            ...(reviewMode ? [
              {
                key: 'actual' as const,
                label: 'العدد الفعلي',
                render: (s: Stock) => (
                  <input
                    type="number"
                    min={0}
                    step="any"
                    className="review-input"
                    value={actualCounts[s.id] ?? ''}
                    placeholder="—"
                    onChange={e => setActualCounts(prev => ({ ...prev, [s.id]: e.target.value }))}
                  />
                ),
              },
              {
                key: 'diff' as const,
                label: 'الفرق',
                render: (s: Stock) => {
                  const diff = getDiff(s)
                  if (diff === null) return <span style={{ color: 'var(--text-muted)' }}>—</span>
                  const sign = diff > 0 ? '+' : ''
                  return <span style={{ fontWeight: 700, color: diffColor(diff) }}>{sign}{formatNumber(diff)}</span>
                },
              },
            ] : []),
            {
              key: 'status', label: 'الحالة',
              render: s => {
                const st = stockStatus(s)
                return (
                  <Badge variant={st.variant}>
                    {st.variant !== 'success' && <AlertTriangle size={10} />}
                    {st.label}
                  </Badge>
                )
              },
            },
          ]}
          data={stock}
          loading={loading}
          emptyIcon={<PackageSearch size={48} />}
          emptyTitle="لا يوجد أرصدة"
          emptyText="لم يتم العثور على أرصدة مطابقة"
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>

      {/* ── MOBILE: Cards ─────────────────────────────────────── */}
      <div className="stock-card-view">
        {loading ? (
          <div className="mobile-card-list">
            {[1, 2, 3].map(i => <div key={i} className="edara-card" style={{ height: 110 }}><div className="skeleton" style={{ height: '100%' }} /></div>)}
          </div>
        ) : stock.length === 0 ? (
          <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)' }}>
            <PackageSearch size={40} style={{ margin: '0 auto 12px', display: 'block', opacity: 0.3 }} />
            <p>لا يوجد أرصدة</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {stock.map((s: Stock) => {
              const st = stockStatus(s)
              const diff = getDiff(s)
              return (
                <div key={s.id} className={`edara-card stock-health-row ${st.variant === 'danger' ? 'shc-row-danger' : st.variant === 'warning' ? 'shc-row-warning' : ''}`}>
                  <div className={`stock-row-stripe ${st.variant}`} />
                  <div style={{ flex: 1, minWidth: 0, padding: 'var(--space-4)' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 6 }}>
                      <div>
                        <ProductLink id={s.product?.id} name={s.product?.name} code={s.product?.sku} style={{ fontSize: 'var(--text-sm)' }} />
                      </div>
                      <Badge variant={st.variant}>{st.variant !== 'success' && <AlertTriangle size={9} />} {st.label}</Badge>
                    </div>
                    <div style={{ display: 'flex', gap: 'var(--space-4)', flexWrap: 'wrap' }}>
                      <div>
                        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>المتاح</div>
                        <div style={{ fontWeight: 800, fontSize: '1.1rem', color: st.color, fontVariantNumeric: 'tabular-nums' }}>{formatNumber(s.available_quantity)}</div>
                      </div>
                      <div>
                        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>الإجمالي</div>
                        <div style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{formatNumber(s.quantity)}</div>
                      </div>
                      {s.reserved_quantity > 0 && <div>
                        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>محجوز</div>
                        <div style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums', color: 'var(--color-warning)' }}>{formatNumber(s.reserved_quantity)}</div>
                      </div>}
                      <div>
                        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>المخزن</div>
                        <div style={{ fontSize: 'var(--text-sm)', fontWeight: 500 }}>
                          <WarehouseLink name={s.warehouse?.name} />
                        </div>
                      </div>
                      {/* التكلفة تظهر للمخولين فقط */}
                      {canViewCosts && s.wac > 0 && <div>
                        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>التكلفة المرجحة</div>
                        <div style={{ fontSize: 'var(--text-sm)', fontVariantNumeric: 'tabular-nums' }}>{formatCurrency(s.wac)}</div>
                      </div>}
                    </div>
                    {/* وضع المراجعة: العدد الفعلي والفرق داخل الكارد */}
                    {reviewMode && (
                      <div style={{ marginTop: 8, display: 'flex', gap: 'var(--space-3)', alignItems: 'center', paddingTop: 8, borderTop: '1px dashed var(--border-primary)' }}>
                        <div>
                          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 2 }}>العدد الفعلي</div>
                          <input
                            type="number"
                            min={0}
                            step="any"
                            className="review-input"
                            value={actualCounts[s.id] ?? ''}
                            placeholder="أدخل العدد"
                            onChange={e => setActualCounts(prev => ({ ...prev, [s.id]: e.target.value }))}
                          />
                        </div>
                        {diff !== null && (
                          <div>
                            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 2 }}>الفرق</div>
                            <div style={{ fontWeight: 800, fontSize: '1rem', color: diffColor(diff), fontVariantNumeric: 'tabular-nums' }}>
                              {diff > 0 ? '+' : ''}{formatNumber(diff)}
                            </div>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        )}

        {totalPages > 1 && (
          <div className="mobile-pagination">
            <button disabled={page <= 1} onClick={() => setPage(p => p - 1)} className="btn btn-ghost btn-sm">السابق</button>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>{page} / {totalPages}</span>
            <button disabled={page >= totalPages} onClick={() => setPage(p => p + 1)} className="btn btn-ghost btn-sm">التالي</button>
          </div>
        )}
      </div>

      <style>{`
        /* Health summary grid */
        .stock-health-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: var(--space-3); }
        .stock-health-card { padding: var(--space-4); display: flex; flex-direction: column; align-items: center; text-align: center; gap: var(--space-1); }
        .shc-icon { width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin-bottom: 4px; }
        .shc-icon-total   { background: rgba(37,99,235,0.1);  color: var(--color-primary); }
        .shc-icon-danger  { background: rgba(239,68,68,0.1);  color: var(--color-danger); }
        .shc-icon-warning { background: rgba(245,158,11,0.1); color: var(--color-warning); }
        .shc-value { font-weight: 800; font-size: 1.5rem; font-variant-numeric: tabular-nums; }
        .shc-label { font-size: var(--text-xs); color: var(--text-muted); }
        .shc-alert-danger  { border: 1.5px solid rgba(239,68,68,0.3); }
        .shc-alert-warning { border: 1.5px solid rgba(245,158,11,0.3); }

        /* Review mode banner */
        .review-banner {
          display: flex; align-items: center; gap: var(--space-2);
          padding: var(--space-3) var(--space-4); margin-bottom: var(--space-4);
          background: rgba(37,99,235,0.07); border: 1px solid rgba(37,99,235,0.2);
          border-radius: 10px; font-size: var(--text-sm); color: var(--color-primary);
        }
        .review-banner--warning {
          background: rgba(245,158,11,0.07); border-color: rgba(245,158,11,0.2);
          color: var(--color-warning);
        }
        .review-banner span { flex: 1; }

        /* Review input */
        .review-input {
          width: 90px; padding: 4px 8px; border: 1.5px solid var(--border-primary);
          border-radius: 6px; font-size: var(--text-sm); text-align: center;
          background: var(--bg-primary); color: var(--text-primary);
          font-variant-numeric: tabular-nums;
        }
        .review-input:focus { outline: none; border-color: var(--color-primary); }

        /* Warehouse context card */
        .warehouse-context-card { padding: var(--space-4); }
        .wcc-header { display: flex; align-items: center; gap: var(--space-2); font-weight: 600; margin-bottom: var(--space-3); }
        .wcc-header span { flex: 1; }
        .wcc-stats { display: flex; gap: var(--space-6); flex-wrap: wrap; margin-bottom: var(--space-2); }
        .wcc-stat-value { font-weight: 800; font-size: 1.2rem; font-variant-numeric: tabular-nums; }
        .wcc-stat-label { font-size: var(--text-xs); color: var(--text-muted); }
        .wcc-disclaimer { font-size: var(--text-xs); color: var(--text-muted); padding: var(--space-2) var(--space-3); background: var(--bg-secondary); border-radius: 6px; }

        /* Table/Card toggle */
        .stock-table-view { display: block; }
        .stock-card-view  { display: none; }

        /* Mobile row */
        .stock-health-row { display: flex; align-items: stretch; gap: 0; padding: 0; overflow: hidden; }
        .stock-row-stripe { width: 4px; flex-shrink: 0; }
        .stock-row-stripe.danger  { background: var(--color-danger); }
        .stock-row-stripe.warning { background: var(--color-warning); }
        .stock-row-stripe.success { background: var(--color-success); }
        .shc-row-danger  { border-right: none; }
        .shc-row-warning { border-right: none; }
        .mobile-card-list { display: flex; flex-direction: column; gap: var(--space-3); }
        .mobile-pagination { display: flex; align-items: center; justify-content: center; gap: var(--space-4); padding: var(--space-4) 0; }

        @media (max-width: 768px) {
          .stock-health-grid { grid-template-columns: repeat(3, 1fr); gap: var(--space-2); }
          .stock-health-card { padding: var(--space-3); }
          .shc-value { font-size: 1.2rem; }
          .stock-table-view { display: none; }
          .stock-card-view  { display: block; }
          .wcc-stats { gap: var(--space-4); }
          .review-input { width: 80px; }
        }
      `}</style>
    </div>
  )
}
