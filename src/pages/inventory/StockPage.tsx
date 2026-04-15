import { useState, useMemo } from 'react'
import { PackageSearch, AlertTriangle, Package, BarChart2 } from 'lucide-react'
import { useStock, useWarehouses } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { Stock } from '@/lib/types/master-data'
import { formatNumber, formatCurrency } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'

// ── Status helpers ────────────────────────────────────────────────
function stockStatus(s: Stock): { variant: 'danger' | 'warning' | 'success'; label: string; color: string } {
  if (s.available_quantity <= 0)    return { variant: 'danger',  label: 'نفد',          color: 'var(--color-danger)'  }
  if (s.product && s.quantity <= (s.product as any).min_stock_level)
                                    return { variant: 'warning', label: 'منخفض',        color: 'var(--color-warning)' }
  return                                   { variant: 'success', label: 'كافي',         color: 'var(--color-success)' }
}

export default function StockPage() {
  const can = useAuthStore(s => s.can)
  const canViewCosts = can('finance.view_costs')
  const [search, setSearch] = useState('')
  const [whFilter, setWhFilter] = useState('')
  const [lowStockOnly, setLowStockOnly] = useState(false)
  const [page, setPage] = useState(1)

  const { data: warehouses = [] } = useWarehouses()

  const queryParams = useMemo(() => ({
    search, warehouseId: whFilter, lowStockOnly, page, pageSize: 25,
  }), [search, whFilter, lowStockOnly, page])

  const { data: result, isLoading: loading } = useStock(queryParams)
  const stock = result?.data ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count ?? 0

  const outOfStock  = stock.filter(s => s.available_quantity <= 0).length
  const lowStock    = stock.filter(s => s.available_quantity > 0 && s.product && s.quantity <= (s.product as any).min_stock_level).length

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="أرصدة المخزون"
        subtitle={loading ? '...' : `${totalCount} سجل`}
      />

      {/* ── Health monitor summary row ─────────────────────────── */}
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

      {/* ── Filters ──────────────────────────────────────────────── */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div style={{ display: 'flex', gap: 'var(--space-3)', flexWrap: 'wrap', alignItems: 'center' }}>
          <div style={{ flex: 2, minWidth: 180 }}>
            <SearchInput value={search} onChange={val => { setSearch(val); setPage(1) }} placeholder="بحث بالمنتج..." />
          </div>
          <select className="form-select" style={{ flex: 1, minWidth: 120 }} value={whFilter}
            onChange={e => { setWhFilter(e.target.value); setPage(1) }}>
            <option value="">كل المخازن</option>
            {warehouses.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
          </select>
          <label style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', fontSize: 'var(--text-sm)', cursor: 'pointer', whiteSpace: 'nowrap' }}>
            <input type="checkbox" checked={lowStockOnly} onChange={e => { setLowStockOnly(e.target.checked); setPage(1) }} />
            <AlertTriangle size={14} style={{ color: 'var(--color-warning)' }} />
            أقل من الحد الأدنى
          </label>
        </div>
      </div>

      {/* ── DESKTOP: DataTable ────────────────────────────────────── */}
      <div className="stock-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<Stock>
          columns={[
            {
              key: 'product', label: 'المنتج',
              render: s => (
                <>
                  <div style={{ fontWeight: 600 }}>{s.product?.name || '—'}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }} dir="ltr">{s.product?.sku}</div>
                </>
              ),
            },
            { key: 'warehouse', label: 'المخزن', render: s => s.warehouse?.name || '—' },
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

      {/* ── MOBILE: Health Monitor Cards ─────────────────────────── */}
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
              return (
                <div key={s.id} className={`edara-card stock-health-row ${st.variant === 'danger' ? 'shc-row-danger' : st.variant === 'warning' ? 'shc-row-warning' : ''}`}>
                  {/* Status stripe */}
                  <div className={`stock-row-stripe ${st.variant}`} />

                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 6 }}>
                      <div>
                        <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)' }}>{s.product?.name || '—'}</div>
                        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }} dir="ltr">{s.product?.sku}</div>
                      </div>
                      <Badge variant={st.variant}>{st.variant !== 'success' && <AlertTriangle size={9} />} {st.label}</Badge>
                    </div>
                    <div style={{ display: 'flex', gap: 'var(--space-4)', flexWrap: 'wrap' }}>
                      <div>
                        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>المتاح</div>
                        <div style={{ fontWeight: 800, fontSize: '1.1rem', color: st.color, fontVariantNumeric: 'tabular-nums' }}>
                          {formatNumber(s.available_quantity)}
                        </div>
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
                        <div style={{ fontSize: 'var(--text-sm)', fontWeight: 500 }}>{s.warehouse?.name || '—'}</div>
                      </div>
                      {canViewCosts && s.wac > 0 && <div>
                        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>التكلفة المرجحة</div>
                        <div style={{ fontSize: 'var(--text-sm)', fontVariantNumeric: 'tabular-nums' }}>{formatCurrency(s.wac)}</div>
                      </div>}
                    </div>
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

        /* Table/Card toggle */
        .stock-table-view { display: block; }
        .stock-card-view  { display: none; }

        /* Mobile row */
        .stock-health-row {
          display: flex; align-items: stretch; gap: 0;
          padding: 0; overflow: hidden; position: relative;
        }
        .stock-row-stripe {
          width: 4px; flex-shrink: 0; border-radius: 0;
        }
        .stock-row-stripe.danger  { background: var(--color-danger); }
        .stock-row-stripe.warning { background: var(--color-warning); }
        .stock-row-stripe.success { background: var(--color-success); }
        .stock-health-row > div:last-child { padding: var(--space-4); }
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
        }
      `}</style>
    </div>
  )
}
