/**
 * InventoryValuationPage — تقارير وتحليلات المخزون
 * ─────────────────────────────────────────────────
 * Route: /inventory/valuation
 * Permission: finance.view_costs
 *
 * Tab 1: التقييم المالي (قيمة المخزون، توزيع المخازن/التصنيفات)
 * Tab 2: تحليل الحركة (سرعة البيع، أيام التغطية، المخزون الراكد)
 * Tab 3: تصنيف ABC (Pareto classification)
 */

import { useState, useMemo } from 'react'
import {
  PackageOpen, Warehouse, Tag, AlertTriangle, TrendingDown, RefreshCw,
  DollarSign, ShoppingBag, BarChart2, Package, Activity, Layers,
  Clock, AlertOctagon, Archive, Zap, AlertCircle, Search,
  ArrowUpDown, ChevronUp, ChevronDown,
} from 'lucide-react'
import {
  useInventoryValuationSummary, useInventoryByWarehouse, useInventoryByCategory,
  useInventoryMovementAnalysis, useInventoryDeadStockSummary, useInventoryABCAnalysis,
} from '@/hooks/useQueryHooks'
import { formatCurrency, formatNumber, formatPercent } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import type { WarehouseInventory, CategoryInventory, CoverageStatus, ABCClass } from '@/lib/types/inventoryValuation'

// ── Helpers ──────────────────────────────────────────────────
const warehouseTypeLabel: Record<string, string> = { fixed: 'ثابت', vehicle: 'سيارة', retail: 'نقطة بيع' }

const coverageLabel: Record<CoverageStatus, string> = {
  dead: 'راكد', critical: 'حرج', low: 'منخفض', ok: 'مقبول', surplus: 'فائض',
}
const coverageColor: Record<CoverageStatus, string> = {
  dead: 'var(--text-muted)', critical: 'var(--color-danger)', low: 'var(--color-warning)',
  ok: 'var(--color-success)', surplus: '#6366f1',
}
const coverageBg: Record<CoverageStatus, string> = {
  dead: 'rgba(107,114,128,0.08)', critical: 'rgba(239,68,68,0.08)', low: 'rgba(245,158,11,0.08)',
  ok: 'rgba(16,185,129,0.08)', surplus: 'rgba(99,102,241,0.08)',
}

const abcColor: Record<ABCClass, string> = { A: 'var(--color-primary)', B: 'var(--color-warning)', C: 'var(--text-muted)' }
const abcBg: Record<ABCClass, string> = { A: 'rgba(37,99,235,0.08)', B: 'rgba(245,158,11,0.08)', C: 'rgba(107,114,128,0.08)' }

// ── Sort helper ─────────────────────────────────────────────
type SortDir = 'asc' | 'desc'
type SortState<K extends string> = { key: K; dir: SortDir }

function SortHeader<K extends string>({ label, sortKey, current, onSort }: {
  label: string; sortKey: K; current: SortState<K>; onSort: (key: K) => void
}) {
  const active = current.key === sortKey
  return (
    <th className="iv-th-sort" onClick={() => onSort(sortKey)}>
      <span>{label}</span>
      {active
        ? current.dir === 'asc' ? <ChevronUp size={12} /> : <ChevronDown size={12} />
        : <ArrowUpDown size={10} style={{ opacity: 0.3 }} />}
    </th>
  )
}

function sortData<T>(data: T[], key: string, dir: SortDir): T[] {
  return [...data].sort((a: any, b: any) => {
    const av = a[key] ?? 0
    const bv = b[key] ?? 0
    if (typeof av === 'string') return dir === 'asc' ? av.localeCompare(bv) : bv.localeCompare(av)
    return dir === 'asc' ? av - bv : bv - av
  })
}

function toggleSort<K extends string>(current: SortState<K>, key: K): SortState<K> {
  if (current.key === key) return { key, dir: current.dir === 'asc' ? 'desc' : 'asc' }
  return { key, dir: 'desc' }
}

// ═════════════════════════════════════════════════════════════
// MAIN COMPONENT
// ═════════════════════════════════════════════════════════════
type TabId = 'valuation' | 'movement' | 'abc'
const TABS: { id: TabId; label: string; icon: typeof DollarSign }[] = [
  { id: 'valuation', label: 'التقييم المالي', icon: DollarSign },
  { id: 'movement', label: 'تحليل الحركة', icon: Activity },
  { id: 'abc', label: 'تصنيف ABC', icon: Layers },
]

// ── Reusable Error Banner ────────────────────────────────────
function ErrorBanner({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="iv-error">
      <AlertCircle size={36} />
      <div className="iv-error-text">{message}</div>
      <button className="btn btn-primary btn-sm" onClick={onRetry}>
        <RefreshCw size={14} />
        إعادة المحاولة
      </button>
    </div>
  )
}

export default function InventoryValuationPage() {
  const [activeTab, setActiveTab] = useState<TabId>('valuation')

  // ── Tab 1 data (always loaded) ────────────────────────────
  const { data: summary, isLoading: summaryLoading, error: summaryErr, refetch: refetchSummary } = useInventoryValuationSummary()
  const { data: warehouses, isLoading: whLoading, error: whErr, refetch: refetchWh } = useInventoryByWarehouse()
  const { data: categories, isLoading: catLoading, error: catErr, refetch: refetchCat } = useInventoryByCategory()

  // ── Tab 2 data (lazy: only when movement tab is active) ───
  const isMovementTab = activeTab === 'movement'
  const { data: movements, isLoading: movLoading, error: movErr, refetch: refetchMov } = useInventoryMovementAnalysis({ enabled: isMovementTab })
  const { data: deadSummary, isLoading: deadLoading, error: deadErr, refetch: refetchDead } = useInventoryDeadStockSummary({ enabled: isMovementTab })

  // ── Tab 3 data (lazy: only when abc tab is active) ────────
  const isAbcTab = activeTab === 'abc'
  const { data: abcData, isLoading: abcLoading, error: abcErr, refetch: refetchAbc } = useInventoryABCAnalysis({ enabled: isAbcTab })

  const isLoading = activeTab === 'valuation'
    ? summaryLoading || whLoading || catLoading
    : activeTab === 'movement'
    ? movLoading || deadLoading
    : abcLoading

  // Only refresh the active tab
  const handleRefresh = () => {
    if (activeTab === 'valuation') { refetchSummary(); refetchWh(); refetchCat() }
    else if (activeTab === 'movement') { refetchMov(); refetchDead() }
    else { refetchAbc() }
  }

  const profitMargin = summary ? summary.total_retail_value - summary.total_value : 0

  // Aggregate error per tab
  const valuationError = summaryErr || whErr || catErr
  const movementError = movErr || deadErr
  const abcError = abcErr

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="تحليلات المخزون"
        subtitle="تقارير مالية وتحليل حركة المخزون"
        actions={
          <button className="btn btn-ghost btn-sm" onClick={handleRefresh} disabled={isLoading} title="تحديث">
            <RefreshCw size={14} className={isLoading ? 'iv-spin' : ''} />
            تحديث
          </button>
        }
      />

      {/* ── Tab Bar ─────────────────────────────────────────── */}
      <div className="iv-tab-bar">
        {TABS.map(t => (
          <button key={t.id} className={`iv-tab ${activeTab === t.id ? 'iv-tab--active' : ''}`} onClick={() => setActiveTab(t.id)}>
            <t.icon size={15} />
            <span>{t.label}</span>
          </button>
        ))}
      </div>

      {/* ── Tab Content ────────────────────────────────────── */}
      {activeTab === 'valuation' && (
        valuationError
          ? <ErrorBanner message="فشل تحميل بيانات التقييم المالي" onRetry={() => { refetchSummary(); refetchWh(); refetchCat() }} />
          : <ValuationTab summary={summary} summaryLoading={summaryLoading} warehouses={warehouses} whLoading={whLoading} categories={categories} catLoading={catLoading} profitMargin={profitMargin} />
      )}
      {activeTab === 'movement' && (
        movementError
          ? <ErrorBanner message="فشل تحميل بيانات تحليل الحركة" onRetry={() => { refetchMov(); refetchDead() }} />
          : <MovementTab movements={movements} movLoading={movLoading} deadSummary={deadSummary} deadLoading={deadLoading} />
      )}
      {activeTab === 'abc' && (
        abcError
          ? <ErrorBanner message="فشل تحميل بيانات تصنيف ABC" onRetry={refetchAbc} />
          : <ABCTab abcData={abcData} abcLoading={abcLoading} />
      )}

      <style>{STYLES}</style>
    </div>
  )
}

// ═════════════════════════════════════════════════════════════
// TAB 1: VALUATION
// ═════════════════════════════════════════════════════════════
function ValuationTab({ summary, summaryLoading, warehouses, whLoading, categories, catLoading, profitMargin }: any) {
  return (
    <>
      {/* KPI Cards */}
      <div className="iv-kpi-grid">
        <div className="edara-card iv-kpi">{summaryLoading ? <div className="skeleton" style={{ height: 80 }} /> : (<>
          <div className="iv-kpi-icon iv-kpi-icon--primary"><DollarSign size={20} /></div>
          <div className="iv-kpi-value">{formatCurrency(summary?.total_value)}</div>
          <div className="iv-kpi-label">إجمالي قيمة التكلفة</div>
        </>)}</div>
        <div className="edara-card iv-kpi">{summaryLoading ? <div className="skeleton" style={{ height: 80 }} /> : (<>
          <div className="iv-kpi-icon iv-kpi-icon--success"><ShoppingBag size={20} /></div>
          <div className="iv-kpi-value">{formatCurrency(summary?.total_retail_value)}</div>
          <div className="iv-kpi-label">إجمالي قيمة البيع</div>
        </>)}</div>
        <div className="edara-card iv-kpi">{summaryLoading ? <div className="skeleton" style={{ height: 80 }} /> : (<>
          <div className={`iv-kpi-icon ${profitMargin >= 0 ? 'iv-kpi-icon--success' : 'iv-kpi-icon--danger'}`}><BarChart2 size={20} /></div>
          <div className="iv-kpi-value" style={{ color: profitMargin >= 0 ? 'var(--color-success)' : 'var(--color-danger)' }}>{formatCurrency(profitMargin)}</div>
          <div className="iv-kpi-label">هامش الربح المتوقع</div>
        </>)}</div>
        <div className="edara-card iv-kpi">{summaryLoading ? <div className="skeleton" style={{ height: 80 }} /> : (<>
          <div className="iv-kpi-icon iv-kpi-icon--warning"><AlertTriangle size={20} /></div>
          <div className="iv-kpi-sub-grid">
            <div>
              <div className="iv-kpi-mini-value" style={{ color: (summary?.out_of_stock_count ?? 0) > 0 ? 'var(--color-danger)' : undefined }}>{formatNumber(summary?.out_of_stock_count)}</div>
              <div className="iv-kpi-mini-label">نفد المخزون</div>
            </div>
            <div>
              <div className="iv-kpi-mini-value" style={{ color: (summary?.low_stock_count ?? 0) > 0 ? 'var(--color-warning)' : undefined }}>{formatNumber(summary?.low_stock_count)}</div>
              <div className="iv-kpi-mini-label">مخزون منخفض</div>
            </div>
          </div>
        </>)}</div>
      </div>

      {/* Stats row */}
      <div className="iv-stat-row">
        <div className="edara-card iv-stat">{summaryLoading ? <div className="skeleton" style={{ height: 46 }} /> : (<><Package size={16} style={{ color: 'var(--color-primary)', flexShrink: 0 }} /><div><div className="iv-stat-value">{formatNumber(summary?.unique_products)}</div><div className="iv-stat-label">منتج فريد</div></div></>)}</div>
        <div className="edara-card iv-stat">{summaryLoading ? <div className="skeleton" style={{ height: 46 }} /> : (<><Warehouse size={16} style={{ color: 'var(--color-primary)', flexShrink: 0 }} /><div><div className="iv-stat-value">{formatNumber(summary?.total_warehouses)}</div><div className="iv-stat-label">مخزن نشط</div></div></>)}</div>
        <div className="edara-card iv-stat">{summaryLoading ? <div className="skeleton" style={{ height: 46 }} /> : (<><TrendingDown size={16} style={{ color: 'var(--text-muted)', flexShrink: 0 }} /><div><div className="iv-stat-value">{formatNumber(summary?.total_quantity)}</div><div className="iv-stat-label">إجمالي الكمية</div></div></>)}</div>
      </div>

      {/* Warehouse Table */}
      <div className="edara-card" style={{ overflow: 'auto', marginBottom: 'var(--space-4)' }}>
        <div className="iv-section-header"><Warehouse size={16} /><span>توزيع القيمة حسب المخازن</span></div>
        {whLoading ? <div style={{ padding: 'var(--space-4)' }}>{[1,2,3].map(i => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 8 }} />)}</div>
        : !warehouses?.length ? <div className="iv-empty"><PackageOpen size={36} style={{ opacity: 0.3 }} /><span>لا توجد بيانات</span></div>
        : <table className="iv-table"><thead><tr><th>المخزن</th><th>النوع</th><th>عدد المنتجات</th><th>الكمية</th><th>القيمة</th><th>النسبة</th></tr></thead><tbody>
          {warehouses.map((wh: WarehouseInventory) => (
            <tr key={wh.warehouse_id}>
              <td style={{ fontWeight: 600 }}>{wh.warehouse_name}</td>
              <td><span className={`iv-badge iv-badge--${wh.warehouse_type}`}>{warehouseTypeLabel[wh.warehouse_type] || wh.warehouse_type}</span></td>
              <td>{formatNumber(wh.product_count)}</td><td>{formatNumber(wh.total_quantity)}</td>
              <td style={{ fontWeight: 600 }}>{formatCurrency(wh.total_value)}</td>
              <td><div className="iv-pct-bar-wrap"><div className="iv-pct-bar" style={{ width: `${Math.min(wh.value_percentage, 100)}%` }} /><span className="iv-pct-text">{formatPercent(wh.value_percentage)}</span></div></td>
            </tr>
          ))}
        </tbody></table>}
      </div>

      {/* Category Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        <div className="iv-section-header"><Tag size={16} /><span>توزيع القيمة حسب التصنيفات</span></div>
        {catLoading ? <div style={{ padding: 'var(--space-4)' }}>{[1,2,3].map(i => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 8 }} />)}</div>
        : !categories?.length ? <div className="iv-empty"><PackageOpen size={36} style={{ opacity: 0.3 }} /><span>لا توجد بيانات</span></div>
        : <table className="iv-table"><thead><tr><th>التصنيف</th><th>عدد المنتجات</th><th>الكمية</th><th>القيمة</th><th>النسبة</th></tr></thead><tbody>
          {categories.map((cat: CategoryInventory, idx: number) => (
            <tr key={cat.category_id || `unc-${idx}`}>
              <td style={{ fontWeight: 600 }}>{cat.category_name}</td>
              <td>{formatNumber(cat.product_count)}</td><td>{formatNumber(cat.total_quantity)}</td>
              <td style={{ fontWeight: 600 }}>{formatCurrency(cat.total_value)}</td>
              <td><div className="iv-pct-bar-wrap"><div className="iv-pct-bar" style={{ width: `${Math.min(cat.value_percentage, 100)}%` }} /><span className="iv-pct-text">{formatPercent(cat.value_percentage)}</span></div></td>
            </tr>
          ))}
        </tbody></table>}
      </div>
    </>
  )
}

// ═════════════════════════════════════════════════════════════
// TAB 2: MOVEMENT ANALYSIS
// ═════════════════════════════════════════════════════════════
function MovementTab({ movements, movLoading, deadSummary, deadLoading }: any) {
  const [statusFilter, setStatusFilter] = useState<CoverageStatus | 'all'>('all')
  const [catFilter, setCatFilter] = useState<string>('all')
  const [search, setSearch] = useState('')
  const [sort, setSort] = useState<SortState<string>>({ key: 'days_of_cover', dir: 'asc' })

  // Extract unique categories
  const categories = useMemo(() => {
    if (!movements) return []
    const set = new Set<string>(movements.map((m: any) => m.category_name))
    return Array.from(set).sort()
  }, [movements])

  // Filter + sort pipeline
  const filtered = useMemo(() => {
    let data = movements ?? []
    if (statusFilter !== 'all') data = data.filter((m: any) => m.coverage_status === statusFilter)
    if (catFilter !== 'all') data = data.filter((m: any) => m.category_name === catFilter)
    if (search.trim()) {
      const q = search.trim().toLowerCase()
      data = data.filter((m: any) => m.product_name?.toLowerCase().includes(q) || m.product_sku?.toLowerCase().includes(q))
    }
    return sortData(data, sort.key, sort.dir)
  }, [movements, statusFilter, catFilter, search, sort])

  return (
    <>
      {/* Dead Stock KPIs */}
      <div className="iv-kpi-grid">
        <div className="edara-card iv-kpi">{deadLoading ? <div className="skeleton" style={{ height: 80 }} /> : (<>
          <div className="iv-kpi-icon" style={{ background: 'rgba(107,114,128,0.1)', color: 'var(--text-muted)' }}><Archive size={20} /></div>
          <div className="iv-kpi-value">{formatCurrency(deadSummary?.total_dead_value)}</div>
          <div className="iv-kpi-label">قيمة المخزون الراكد</div>
          {deadSummary?.total_dead_pct > 0 && <div className="iv-kpi-sub-label">{formatPercent(deadSummary.total_dead_pct)} من الإجمالي</div>}
        </>)}</div>
        <div className="edara-card iv-kpi">{deadLoading ? <div className="skeleton" style={{ height: 80 }} /> : (<>
          <div className="iv-kpi-icon iv-kpi-icon--danger"><AlertOctagon size={20} /></div>
          <div className="iv-kpi-value" style={{ color: (deadSummary?.critical_count ?? 0) > 0 ? 'var(--color-danger)' : undefined }}>{formatNumber(deadSummary?.critical_count)}</div>
          <div className="iv-kpi-label">أصناف بتغطية حرجة</div>
          <div className="iv-kpi-sub-label">أقل من 7 أيام</div>
        </>)}</div>
        <div className="edara-card iv-kpi">{deadLoading ? <div className="skeleton" style={{ height: 80 }} /> : (<>
          <div className="iv-kpi-icon iv-kpi-icon--warning"><Clock size={20} /></div>
          <div className="iv-kpi-value" style={{ color: (deadSummary?.low_count ?? 0) > 0 ? 'var(--color-warning)' : undefined }}>{formatNumber(deadSummary?.low_count)}</div>
          <div className="iv-kpi-label">أصناف بتغطية منخفضة</div>
          <div className="iv-kpi-sub-label">7 - 30 يوم</div>
        </>)}</div>
        <div className="edara-card iv-kpi">{deadLoading ? <div className="skeleton" style={{ height: 80 }} /> : (<>
          <div className="iv-kpi-icon" style={{ background: 'rgba(99,102,241,0.1)', color: '#6366f1' }}><Zap size={20} /></div>
          <div className="iv-kpi-sub-grid">
            <div>
              <div className="iv-kpi-mini-value">{formatNumber(deadSummary?.surplus_count)}</div>
              <div className="iv-kpi-mini-label">فائض</div>
            </div>
            <div>
              <div className="iv-kpi-mini-value">{formatCurrency(deadSummary?.surplus_value)}</div>
              <div className="iv-kpi-mini-label">قيمته</div>
            </div>
          </div>
        </>)}</div>
      </div>

      {/* Dead stock aging row */}
      <div className="iv-stat-row">
        <div className="edara-card iv-stat">{deadLoading ? <div className="skeleton" style={{ height: 46 }} /> : (<>
          <Archive size={16} style={{ color: 'var(--text-muted)', flexShrink: 0 }} />
          <div><div className="iv-stat-value">{formatNumber(deadSummary?.dead_30?.count)}</div><div className="iv-stat-label">راكد +30 يوم</div></div>
        </>)}</div>
        <div className="edara-card iv-stat">{deadLoading ? <div className="skeleton" style={{ height: 46 }} /> : (<>
          <Archive size={16} style={{ color: 'var(--color-warning)', flexShrink: 0 }} />
          <div><div className="iv-stat-value">{formatNumber(deadSummary?.dead_60?.count)}</div><div className="iv-stat-label">راكد +60 يوم</div></div>
        </>)}</div>
        <div className="edara-card iv-stat">{deadLoading ? <div className="skeleton" style={{ height: 46 }} /> : (<>
          <Archive size={16} style={{ color: 'var(--color-danger)', flexShrink: 0 }} />
          <div><div className="iv-stat-value">{formatNumber(deadSummary?.dead_90?.count)}</div><div className="iv-stat-label">راكد +90 يوم</div></div>
        </>)}</div>
      </div>

      {/* Filter toolbar + Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        <div className="iv-section-header" style={{ justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}><Activity size={16} /><span>تفاصيل حركة المنتجات</span></div>
          {!movLoading && <span className="iv-result-count">{filtered.length} منتج</span>}
        </div>
        <div className="iv-filter-bar">
          <div className="iv-search-wrap">
            <Search size={14} className="iv-search-icon" />
            <input className="iv-search-input" placeholder="بحث بالاسم أو الكود..." value={search} onChange={e => setSearch(e.target.value)} />
          </div>
          <select className="form-select iv-filter-select" value={catFilter} onChange={e => setCatFilter(e.target.value)}>
            <option value="all">كل التصنيفات</option>
            {categories.map((c: string) => <option key={c} value={c}>{c}</option>)}
          </select>
          <select className="form-select iv-filter-select" value={statusFilter} onChange={e => setStatusFilter(e.target.value as any)}>
            <option value="all">كل الحالات</option>
            <option value="dead">راكد</option>
            <option value="critical">حرج</option>
            <option value="low">منخفض</option>
            <option value="ok">مقبول</option>
            <option value="surplus">فائض</option>
          </select>
        </div>
        {movLoading ? <div style={{ padding: 'var(--space-4)' }}>{[1,2,3,4].map(i => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 8 }} />)}</div>
        : !filtered.length ? <div className="iv-empty"><PackageOpen size={36} style={{ opacity: 0.3 }} /><span>لا توجد بيانات مطابقة</span></div>
        : <table className="iv-table"><thead><tr>
          <SortHeader label="المنتج" sortKey="product_name" current={sort} onSort={k => setSort(toggleSort(sort, k))} />
          <th>التصنيف</th>
          <SortHeader label="المتاح" sortKey="available_qty" current={sort} onSort={k => setSort(toggleSort(sort, k))} />
          <SortHeader label="القيمة" sortKey="total_value" current={sort} onSort={k => setSort(toggleSort(sort, k))} />
          <SortHeader label="السرعة/يوم" sortKey="daily_velocity" current={sort} onSort={k => setSort(toggleSort(sort, k))} />
          <SortHeader label="أيام التغطية" sortKey="days_of_cover" current={sort} onSort={k => setSort(toggleSort(sort, k))} />
          <SortHeader label="آخر خروج" sortKey="days_since_last_out" current={sort} onSort={k => setSort(toggleSort(sort, k))} />
          <th>الحالة</th>
        </tr></thead><tbody>
          {filtered.map((m: any) => (
            <tr key={m.product_id}>
              <td><div style={{ fontWeight: 600 }}>{m.product_name}</div><div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }} dir="ltr">{m.product_sku}</div></td>
              <td style={{ fontSize: 'var(--text-xs)' }}>{m.category_name}</td>
              <td>{formatNumber(m.available_qty)}</td>
              <td style={{ fontWeight: 600 }}>{formatCurrency(m.total_value)}</td>
              <td style={{ fontVariantNumeric: 'tabular-nums' }}>{m.daily_velocity > 0 ? m.daily_velocity.toFixed(1) : '—'}</td>
              <td style={{ fontWeight: 600 }}>{m.days_of_cover >= 999 ? '∞' : formatNumber(Math.round(m.days_of_cover))}</td>
              <td style={{ fontSize: 'var(--text-xs)' }}>{m.days_since_last_out != null ? `${m.days_since_last_out} يوم` : 'لا حركة'}</td>
              <td><span className="iv-status-badge" style={{ background: coverageBg[m.coverage_status as CoverageStatus], color: coverageColor[m.coverage_status as CoverageStatus] }}>{coverageLabel[m.coverage_status as CoverageStatus]}</span></td>
            </tr>
          ))}
        </tbody></table>}
      </div>
    </>
  )
}

// ═════════════════════════════════════════════════════════════
// TAB 3: ABC ANALYSIS
// ═════════════════════════════════════════════════════════════
function ABCTab({ abcData, abcLoading }: any) {
  const [classFilter, setClassFilter] = useState<ABCClass | 'all'>('all')
  const [catFilter, setCatFilter] = useState<string>('all')
  const [search, setSearch] = useState('')
  const [sort, setSort] = useState<SortState<string>>({ key: 'total_value', dir: 'desc' })

  // Extract unique categories
  const categories = useMemo(() => {
    if (!abcData) return []
    const set = new Set<string>(abcData.map((p: any) => p.category_name))
    return Array.from(set).sort()
  }, [abcData])

  // Filter + sort pipeline
  const filtered = useMemo(() => {
    let data = abcData ?? []
    if (classFilter !== 'all') data = data.filter((p: any) => p.abc_class === classFilter)
    if (catFilter !== 'all') data = data.filter((p: any) => p.category_name === catFilter)
    if (search.trim()) {
      const q = search.trim().toLowerCase()
      data = data.filter((p: any) => p.product_name?.toLowerCase().includes(q) || p.product_sku?.toLowerCase().includes(q))
    }
    return sortData(data, sort.key, sort.dir)
  }, [abcData, classFilter, catFilter, search, sort])

  // Summary cards (from unfiltered data)
  const aItems = abcData?.filter((p: any) => p.abc_class === 'A') ?? []
  const bItems = abcData?.filter((p: any) => p.abc_class === 'B') ?? []
  const cItems = abcData?.filter((p: any) => p.abc_class === 'C') ?? []
  const sumVal = (items: any[]) => items.reduce((s: number, p: any) => s + (p.total_value || 0), 0)
  const sumPct = (items: any[]) => items.reduce((s: number, p: any) => s + (p.value_pct || 0), 0)

  return (
    <>
      {/* ABC Summary Cards */}
      <div className="iv-abc-grid">
        {([
          { cls: 'A' as ABCClass, label: 'فئة A — حرجة', desc: 'أعلى قيمة (80% من المخزون)', items: aItems },
          { cls: 'B' as ABCClass, label: 'فئة B — متوسطة', desc: 'قيمة متوسطة (80-95%)', items: bItems },
          { cls: 'C' as ABCClass, label: 'فئة C — منخفضة', desc: 'أقل قيمة (95-100%)', items: cItems },
        ]).map(g => (
          <div key={g.cls} className="edara-card iv-abc-card" style={{ borderTop: `3px solid ${abcColor[g.cls]}` }}>
            {abcLoading ? <div className="skeleton" style={{ height: 90 }} /> : (<>
              <div className="iv-abc-header">
                <span className="iv-abc-class" style={{ background: abcBg[g.cls], color: abcColor[g.cls] }}>{g.cls}</span>
                <div><div style={{ fontWeight: 700 }}>{g.label}</div><div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{g.desc}</div></div>
              </div>
              <div className="iv-abc-stats">
                <div><div className="iv-abc-stat-value">{g.items.length}</div><div className="iv-abc-stat-label">منتج</div></div>
                <div><div className="iv-abc-stat-value">{formatCurrency(sumVal(g.items))}</div><div className="iv-abc-stat-label">القيمة</div></div>
                <div><div className="iv-abc-stat-value">{formatPercent(sumPct(g.items))}</div><div className="iv-abc-stat-label">النسبة</div></div>
              </div>
            </>)}
          </div>
        ))}
      </div>

      {/* Filter toolbar + Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        <div className="iv-section-header" style={{ justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}><Layers size={16} /><span>تفاصيل تصنيف ABC</span></div>
          {!abcLoading && <span className="iv-result-count">{filtered.length} منتج</span>}
        </div>
        <div className="iv-filter-bar">
          <div className="iv-search-wrap">
            <Search size={14} className="iv-search-icon" />
            <input className="iv-search-input" placeholder="بحث بالاسم أو الكود..." value={search} onChange={e => setSearch(e.target.value)} />
          </div>
          <select className="form-select iv-filter-select" value={catFilter} onChange={e => setCatFilter(e.target.value)}>
            <option value="all">كل التصنيفات</option>
            {categories.map((c: string) => <option key={c} value={c}>{c}</option>)}
          </select>
          <select className="form-select iv-filter-select" value={classFilter} onChange={e => setClassFilter(e.target.value as any)}>
            <option value="all">كل الفئات</option>
            <option value="A">فئة A</option>
            <option value="B">فئة B</option>
            <option value="C">فئة C</option>
          </select>
        </div>
        {abcLoading ? <div style={{ padding: 'var(--space-4)' }}>{[1,2,3,4].map(i => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 8 }} />)}</div>
        : !filtered.length ? <div className="iv-empty"><PackageOpen size={36} style={{ opacity: 0.3 }} /><span>لا توجد بيانات</span></div>
        : <table className="iv-table"><thead><tr>
          <SortHeader label="المنتج" sortKey="product_name" current={sort} onSort={k => setSort(toggleSort(sort, k))} />
          <th>التصنيف</th>
          <SortHeader label="الكمية" sortKey="total_quantity" current={sort} onSort={k => setSort(toggleSort(sort, k))} />
          <SortHeader label="القيمة" sortKey="total_value" current={sort} onSort={k => setSort(toggleSort(sort, k))} />
          <SortHeader label="النسبة" sortKey="value_pct" current={sort} onSort={k => setSort(toggleSort(sort, k))} />
          <SortHeader label="التراكمي" sortKey="cumulative_pct" current={sort} onSort={k => setSort(toggleSort(sort, k))} />
          <th>الفئة</th>
        </tr></thead><tbody>
          {filtered.map((p: any) => (
            <tr key={p.product_id}>
              <td><div style={{ fontWeight: 600 }}>{p.product_name}</div><div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }} dir="ltr">{p.product_sku}</div></td>
              <td style={{ fontSize: 'var(--text-xs)' }}>{p.category_name}</td>
              <td>{formatNumber(p.total_quantity)}</td>
              <td style={{ fontWeight: 600 }}>{formatCurrency(p.total_value)}</td>
              <td>{formatPercent(p.value_pct)}</td>
              <td><div className="iv-pct-bar-wrap"><div className="iv-pct-bar" style={{ width: `${Math.min(p.cumulative_pct, 100)}%`, background: abcColor[p.abc_class as ABCClass] }} /><span className="iv-pct-text">{formatPercent(p.cumulative_pct)}</span></div></td>
              <td><span className="iv-status-badge" style={{ background: abcBg[p.abc_class as ABCClass], color: abcColor[p.abc_class as ABCClass], fontWeight: 800 }}>{p.abc_class}</span></td>
            </tr>
          ))}
        </tbody></table>}
      </div>
    </>
  )
}

// ═════════════════════════════════════════════════════════════
// STYLES
// ═════════════════════════════════════════════════════════════
const STYLES = `
/* Tab Bar */
.iv-tab-bar {
  display: flex; gap: var(--space-1); margin-bottom: var(--space-4);
  background: var(--bg-secondary); border-radius: 10px; padding: 4px;
  overflow-x: auto;
}
.iv-tab {
  display: flex; align-items: center; gap: var(--space-2);
  padding: 8px 16px; border-radius: 8px; border: none; cursor: pointer;
  font-size: var(--text-sm); font-weight: 600; white-space: nowrap;
  background: transparent; color: var(--text-muted);
  transition: all 0.2s;
}
.iv-tab:hover { color: var(--text-primary); background: var(--bg-hover); }
.iv-tab--active {
  background: var(--bg-primary); color: var(--color-primary);
  box-shadow: 0 1px 3px rgba(0,0,0,0.08);
}

/* KPI Grid */
.iv-kpi-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: var(--space-3); margin-bottom: var(--space-4); }
.iv-kpi { padding: var(--space-4); display: flex; flex-direction: column; align-items: center; text-align: center; gap: var(--space-2); }
.iv-kpi-icon { width: 42px; height: 42px; border-radius: 12px; display: flex; align-items: center; justify-content: center; margin-bottom: 2px; }
.iv-kpi-icon--primary { background: rgba(37,99,235,0.1); color: var(--color-primary); }
.iv-kpi-icon--success { background: rgba(16,185,129,0.1); color: var(--color-success); }
.iv-kpi-icon--danger  { background: rgba(239,68,68,0.1);  color: var(--color-danger); }
.iv-kpi-icon--warning { background: rgba(245,158,11,0.1); color: var(--color-warning); }
.iv-kpi-value { font-weight: 800; font-size: 1.35rem; font-variant-numeric: tabular-nums; line-height: 1.2; }
.iv-kpi-label { font-size: var(--text-xs); color: var(--text-muted); font-weight: 500; }
.iv-kpi-sub-label { font-size: 10px; color: var(--text-muted); margin-top: -2px; }
.iv-kpi-sub-grid { display: flex; gap: var(--space-6); }
.iv-kpi-mini-value { font-weight: 800; font-size: 1.2rem; font-variant-numeric: tabular-nums; line-height: 1.2; }
.iv-kpi-mini-label { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }

/* Stats Row */
.iv-stat-row { display: grid; grid-template-columns: repeat(3, 1fr); gap: var(--space-3); margin-bottom: var(--space-4); }
.iv-stat { padding: var(--space-3) var(--space-4); display: flex; align-items: center; gap: var(--space-3); }
.iv-stat-value { font-weight: 700; font-size: var(--text-lg); font-variant-numeric: tabular-nums; }
.iv-stat-label { font-size: var(--text-xs); color: var(--text-muted); }

/* Section Header */
.iv-section-header { display: flex; align-items: center; gap: var(--space-2); padding: var(--space-3) var(--space-4); font-weight: 700; font-size: var(--text-base); border-bottom: 1px solid var(--border-primary); color: var(--text-primary); }

/* Table */
.iv-table { width: 100%; border-collapse: collapse; font-size: var(--text-sm); }
.iv-table th { padding: var(--space-3) var(--space-4); text-align: right; font-weight: 600; font-size: var(--text-xs); color: var(--text-muted); border-bottom: 1px solid var(--border-primary); white-space: nowrap; }
.iv-th-sort {
  padding: var(--space-3) var(--space-4); text-align: right; font-weight: 600;
  font-size: var(--text-xs); color: var(--text-muted); border-bottom: 1px solid var(--border-primary);
  white-space: nowrap; cursor: pointer; user-select: none;
  display: table-cell;
}
.iv-th-sort:hover { color: var(--text-primary); background: var(--bg-hover); }
.iv-th-sort span { vertical-align: middle; }
.iv-th-sort svg { vertical-align: middle; margin-inline-start: 4px; }
.iv-table td { padding: var(--space-3) var(--space-4); border-bottom: 1px solid var(--border-primary); white-space: nowrap; font-variant-numeric: tabular-nums; }
.iv-table tbody tr:hover { background: var(--bg-hover); }
.iv-table tbody tr:last-child td { border-bottom: none; }

/* Filter toolbar */
.iv-filter-bar {
  display: flex; gap: var(--space-2); padding: var(--space-3) var(--space-4);
  border-bottom: 1px solid var(--border-primary); flex-wrap: wrap; align-items: center;
}
.iv-search-wrap {
  position: relative; flex: 2; min-width: 160px;
}
.iv-search-icon {
  position: absolute; right: 10px; top: 50%; transform: translateY(-50%);
  color: var(--text-muted); pointer-events: none;
}
.iv-search-input {
  width: 100%; padding: 6px 32px 6px 10px; border: 1px solid var(--border-primary);
  border-radius: 8px; font-size: var(--text-xs); background: var(--bg-primary);
  color: var(--text-primary); outline: none; transition: border-color 0.2s;
}
.iv-search-input:focus { border-color: var(--color-primary); }
.iv-search-input::placeholder { color: var(--text-muted); }
.iv-filter-select {
  width: auto !important; font-size: var(--text-xs) !important;
  padding: 5px 8px !important; min-width: 110px;
}
.iv-result-count {
  font-size: var(--text-xs); color: var(--text-muted); font-weight: 600;
  background: var(--bg-secondary); padding: 2px 10px; border-radius: 6px;
}

/* Badges */
.iv-badge { display: inline-flex; padding: 2px 8px; border-radius: 6px; font-size: var(--text-xs); font-weight: 600; }
.iv-badge--fixed   { background: rgba(37,99,235,0.08); color: #2563eb; }
.iv-badge--vehicle { background: rgba(245,158,11,0.08); color: #d97706; }
.iv-badge--retail  { background: rgba(16,185,129,0.08); color: #059669; }

.iv-status-badge { display: inline-flex; padding: 2px 10px; border-radius: 6px; font-size: var(--text-xs); font-weight: 700; }

/* Percentage bar */
.iv-pct-bar-wrap { display: flex; align-items: center; gap: var(--space-2); min-width: 120px; }
.iv-pct-bar { height: 6px; background: var(--color-primary); border-radius: 3px; min-width: 2px; opacity: 0.7; transition: width 0.3s ease; }
.iv-pct-text { font-size: var(--text-xs); color: var(--text-muted); font-weight: 600; white-space: nowrap; }

/* Empty state */
.iv-empty { display: flex; flex-direction: column; align-items: center; gap: var(--space-3); padding: var(--space-8); color: var(--text-muted); font-size: var(--text-sm); }

/* Error state */
.iv-error {
  display: flex; flex-direction: column; align-items: center; gap: var(--space-3);
  padding: var(--space-8); color: var(--color-danger);
  text-align: center;
}
.iv-error-text { font-size: var(--text-sm); font-weight: 600; color: var(--text-secondary); }

/* ABC Cards */
.iv-abc-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: var(--space-3); margin-bottom: var(--space-4); }
.iv-abc-card { padding: var(--space-4); }
.iv-abc-header { display: flex; align-items: center; gap: var(--space-3); margin-bottom: var(--space-3); }
.iv-abc-class { width: 36px; height: 36px; border-radius: 10px; display: flex; align-items: center; justify-content: center; font-weight: 900; font-size: 1.1rem; flex-shrink: 0; }
.iv-abc-stats { display: flex; gap: var(--space-4); flex-wrap: wrap; }
.iv-abc-stat-value { font-weight: 800; font-size: var(--text-base); font-variant-numeric: tabular-nums; }
.iv-abc-stat-label { font-size: var(--text-xs); color: var(--text-muted); }

/* Refresh spin */
@keyframes iv-rotate { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
.iv-spin { animation: iv-rotate 1s linear infinite; }

/* Responsive */
@media (max-width: 1024px) {
  .iv-kpi-grid { grid-template-columns: repeat(2, 1fr); }
  .iv-abc-grid { grid-template-columns: 1fr; }
}
@media (max-width: 768px) {
  .iv-kpi-grid { grid-template-columns: 1fr 1fr; }
  .iv-stat-row { grid-template-columns: 1fr; }
  .iv-kpi-value { font-size: 1.1rem; }
  .iv-pct-bar-wrap { min-width: 80px; }
  .iv-tab { padding: 6px 12px; font-size: var(--text-xs); }
}
@media (max-width: 480px) {
  .iv-kpi-grid { grid-template-columns: 1fr; }
}
`
