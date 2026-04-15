import { useState } from 'react'
import {
  DollarSign, Activity, FileText, PieChart, AlertCircle, RefreshCw,
  TrendingDown, TrendingUp, Briefcase, CreditCard, ShoppingBag, ArrowUpDown, ChevronUp, ChevronDown, CheckCircle2,
  XCircle, Filter, Search
} from 'lucide-react'
import { useFinancialSummary, useTrialBalanceDetail } from '@/hooks/useQueryHooks'
import { formatCurrency, formatNumber, formatPercent } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import type { RatioStatus, TrialBalanceEntry, BalanceSheetSection } from '@/lib/types/financialBalanceSheet'

// ── Helpers ──────────────────────────────────────────────────

const statusColor: Record<RatioStatus, string> = {
  excellent: 'var(--color-success)',
  good: 'var(--color-primary)',
  warning: 'var(--color-warning)',
  critical: 'var(--color-danger)',
}

const statusBg: Record<RatioStatus, string> = {
  excellent: 'rgba(16,185,129,0.08)',
  good: 'rgba(37,99,235,0.08)',
  warning: 'rgba(245,158,11,0.08)',
  critical: 'rgba(239,68,68,0.08)',
}

const statusLabel: Record<RatioStatus, string> = {
  excellent: 'ممتاز',
  good: 'جيد',
  warning: 'تحذير',
  critical: 'حرج',
}

// ── Sort helper ─────────────────────────────────────────────
type SortDir = 'asc' | 'desc'
type SortState<K extends string> = { key: K; dir: SortDir }

function SortHeader<K extends string>({ label, sortKey, current, onSort, width }: {
  label: string; sortKey: K; current: SortState<K>; onSort: (key: K) => void; width?: string
}) {
  const active = current.key === sortKey
  return (
    <th 
      style={{ width, cursor: 'pointer', whiteSpace: 'nowrap' }} 
      onClick={() => onSort(sortKey)}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
        <span>{label}</span>
        {active
          ? current.dir === 'asc' ? <ChevronUp size={12} style={{ color: 'var(--color-primary)' }} /> : <ChevronDown size={12} style={{ color: 'var(--color-primary)' }} />
          : <ArrowUpDown size={10} style={{ opacity: 0.3 }} />}
      </div>
    </th>
  )
}

function sortData<T>(data: T[], key: string, dir: SortDir): T[] {
  return [...data].sort((a: any, b: any) => {
    const av = a[key] ?? 0
    const bv = b[key] ?? 0
    if (typeof av === 'string' && typeof bv === 'string') {
      return dir === 'asc' ? av.localeCompare(bv) : bv.localeCompare(av)
    }
    return dir === 'asc' ? Number(av) - Number(bv) : Number(bv) - Number(av)
  })
}

function toggleSort<K extends string>(current: SortState<K>, key: K): SortState<K> {
  if (current.key === key) return { key, dir: current.dir === 'asc' ? 'desc' : 'asc' }
  return { key, dir: 'desc' }
}

// ═════════════════════════════════════════════════════════════
// MAIN COMPONENT
// ═════════════════════════════════════════════════════════════
type TabId = 'health' | 'trial' | 'income' | 'balance'
const TABS: { id: TabId; label: string; icon: typeof Activity }[] = [
  { id: 'health', label: 'الصحة المالية', icon: Activity },
  { id: 'income', label: 'قائمة الدخل', icon: TrendingUp },
  { id: 'balance', label: 'الميزانية العمومية', icon: Briefcase },
  { id: 'trial', label: 'ميزان المراجعة', icon: FileText },
]

function ErrorBanner({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
      padding: '48px 24px', background: 'var(--bg-surface)', borderRadius: '12px',
      border: '1px solid var(--border-color)', gap: '16px', color: 'var(--color-danger)'
    }}>
      <AlertCircle size={36} />
      <div style={{ fontSize: '15px', fontWeight: 500 }}>{message}</div>
      <button className="btn btn-primary btn-sm" onClick={onRetry}>
        <RefreshCw size={14} />
        إعادة المحاولة
      </button>
    </div>
  )
}

export default function FinancialBalanceSheetPage() {
  const [activeTab, setActiveTab] = useState<TabId>('health')
  const [asOfDate, setAsOfDate] = useState(() => new Date().toISOString().split('T')[0])
  const [periodStart, setPeriodStart] = useState(() => {
    const d = new Date()
    d.setDate(1) // first day of current month
    return d.toISOString().split('T')[0]
  })

  // Tab 2 (Trial Balance) specific state
  const [showParents, setShowParents] = useState(false)
  const isTrialActive = activeTab === 'trial'

  // Data fetching
  const summaryQuery = useFinancialSummary(asOfDate, periodStart)
  const trialQuery = useTrialBalanceDetail(asOfDate, showParents, isTrialActive)

  const handleRefresh = () => {
    summaryQuery.refetch()
    if (isTrialActive) trialQuery.refetch()
  }

  return (
    <div className="page-container">
      <PageHeader 
        title="الميزان المالي (General Ledger)" 
        subtitle="تقرير شامل للأرصدة المالية والميزانية المجمعة"
        actions={
          <div style={{ display: 'flex', gap: '8px', alignItems: 'flex-end' }}>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label className="form-label" style={{ fontSize: '12px' }}>فترة الدخل من (Tab 3)</label>
              <input 
                type="date" 
                className="form-control form-control-sm"
                value={periodStart}
                onChange={e => setPeriodStart(e.target.value)}
              />
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label className="form-label" style={{ fontSize: '12px' }}>محسوب حتى تاريخ (الكل)</label>
              <input 
                type="date" 
                className="form-control form-control-sm"
                value={asOfDate}
                onChange={e => setAsOfDate(e.target.value)}
              />
            </div>
            <button 
              className="btn btn-secondary btn-sm" 
              onClick={handleRefresh}
              disabled={summaryQuery.isFetching || trialQuery.isFetching}
            >
              <RefreshCw size={14} className={summaryQuery.isFetching ? 'spin' : ''} />
              تحديث
            </button>
          </div>
        }
      />

      {/* Tabs */}
      <div className="iv-tabs" style={{ 
        display: 'flex', gap: '8px', borderBottom: '1px solid var(--border-color)', marginBottom: '24px' 
      }}>
        {TABS.map(tab => (
          <button
            key={tab.id}
            className={`iv-tab-btn ${activeTab === tab.id ? 'active' : ''}`}
            onClick={() => setActiveTab(tab.id)}
            style={{
              display: 'flex', alignItems: 'center', gap: '8px', padding: '12px 16px',
              borderBottom: activeTab === tab.id ? '2px solid var(--color-primary)' : '2px solid transparent',
              color: activeTab === tab.id ? 'var(--color-primary)' : 'var(--text-secondary)',
              fontWeight: activeTab === tab.id ? 600 : 500,
              background: 'none', borderTop: 'none', borderLeft: 'none', borderRight: 'none',
              cursor: 'pointer'
            }}
          >
            <tab.icon size={16} />
            {tab.label}
          </button>
        ))}
      </div>

      {/* Loading / Error / Content */}
      {summaryQuery.isError && <ErrorBanner message={(summaryQuery.error as Error).message || 'حدث خطأ أثناء تحميل الملخص المالي'} onRetry={handleRefresh} />}
      {isTrialActive && trialQuery.isError && <ErrorBanner message={(trialQuery.error as Error).message || 'حدث خطأ أثناء تحميل ميزان المراجعة'} onRetry={handleRefresh} />}
      
      {summaryQuery.isLoading ? (
        <div className="p-8 text-center"><RefreshCw size={24} className="spin mx-auto text-muted" /></div>
      ) : summaryQuery.data && (
        <div className="tab-content transition-all">
          {activeTab === 'health' && <HealthTab data={summaryQuery.data.health_indicators} bs={summaryQuery.data.balance_sheet} />}
          {activeTab === 'income' && <IncomeTab data={summaryQuery.data.income_statement} />}
          {activeTab === 'balance' && <BalanceTab data={summaryQuery.data.balance_sheet} isData_date={summaryQuery.data.as_of_date} />}
        </div>
      )}

      {isTrialActive && (
        trialQuery.isLoading ? (
          <div className="p-8 text-center"><RefreshCw size={24} className="spin mx-auto text-muted" /></div>
        ) : trialQuery.data && (
          <TrialBalanceTab 
            data={trialQuery.data} 
            showParents={showParents} 
            setShowParents={setShowParents} 
          />
        )
      )}
      
    </div>
  )
}

// ── Tab 1: Health Indicators ──────────────────────────────────────────

function HealthTab({ data, bs }: { data: any; bs: any }) {
  const kpis = [
    { label: 'نسبة التداول (Current Ratio)', value: data.current_ratio, target: 'مثالي > 1.5', status: data.current_ratio_status, prefix: 'x' },
    { label: 'السيولة السريعة (Quick Ratio)', value: data.quick_ratio, target: 'مثالي > 1.0', status: data.quick_ratio_status, prefix: 'x' },
    { label: 'الرافعة المالية (Debt to Equity)', value: data.debt_to_equity, target: 'مثالي < 1.0', status: data.debt_to_equity_status, prefix: 'x' },
  ]

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
      
      {/* 3 Main Highlights */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: '16px' }}>
        <div className="metric-card" style={{ background: 'var(--bg-surface)', padding: '24px', borderRadius: '12px', border: '1px solid var(--border-color)', display: 'flex', gap: '16px', alignItems: 'center' }}>
          <div style={{ width: '48px', height: '48px', borderRadius: '12px', background: 'rgba(16,185,129,0.1)', color: '#10b981', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Briefcase size={24} />
          </div>
          <div>
            <div style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>إجمالي الأصول (Assets)</div>
            <div style={{ fontSize: '24px', fontWeight: 600, marginTop: '4px' }}>{formatCurrency(bs.total_assets)}</div>
          </div>
        </div>
        <div className="metric-card" style={{ background: 'var(--bg-surface)', padding: '24px', borderRadius: '12px', border: '1px solid var(--border-color)', display: 'flex', gap: '16px', alignItems: 'center' }}>
          <div style={{ width: '48px', height: '48px', borderRadius: '12px', background: 'rgba(239,68,68,0.1)', color: '#ef4444', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <CreditCard size={24} />
          </div>
          <div>
            <div style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>إجمالي الالتزامات (Liabilities)</div>
            <div style={{ fontSize: '24px', fontWeight: 600, marginTop: '4px' }}>{formatCurrency(bs.total_liabilities)}</div>
          </div>
        </div>
        <div className="metric-card" style={{ background: 'var(--bg-surface)', padding: '24px', borderRadius: '12px', border: '1px solid var(--border-color)', display: 'flex', gap: '16px', alignItems: 'center' }}>
          <div style={{ width: '48px', height: '48px', borderRadius: '12px', background: 'rgba(56,189,248,0.1)', color: '#38bdf8', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <PieChart size={24} />
          </div>
          <div>
            <div style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>صافي الأصول</div>
            <div style={{ fontSize: '24px', fontWeight: 600, marginTop: '4px' }}>{formatCurrency(bs.total_assets - bs.total_liabilities)}</div>
          </div>
        </div>
      </div>

      {/* KPIs Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '16px' }}>
        {kpis.map((kpi, i) => (
          <div key={i} style={{ background: 'var(--bg-surface)', padding: '20px', borderRadius: '12px', border: `1px solid ${statusColor[kpi.status as RatioStatus] || 'var(--border-color)'}`, borderTop: `4px solid ${statusColor[kpi.status as RatioStatus] || 'var(--border-color)'}` }}>
            <div style={{ fontSize: '14px', fontWeight: 500 }}>{kpi.label}</div>
            <div style={{ fontSize: '32px', fontWeight: 700, margin: '8px 0', color: statusColor[kpi.status as RatioStatus] }}>
              {kpi.value === null ? <span style={{ fontSize: '20px' }}>غير منطبق</span> : kpi.value.toFixed(2)}
              {kpi.value !== null && <span style={{ fontSize: '16px', marginLeft: '4px' }}>{kpi.prefix}</span>}
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '12px', color: 'var(--text-secondary)' }}>
              <span>{kpi.target}</span>
              <span style={{ background: statusBg[kpi.status as RatioStatus] || '#eee', color: statusColor[kpi.status as RatioStatus] || '#666', padding: '2px 8px', borderRadius: '12px', fontWeight: 600 }}>
                {statusLabel[kpi.status as RatioStatus] || 'غير معروف'}
              </span>
            </div>
          </div>
        ))}
        
        <div style={{ background: 'var(--bg-surface)', padding: '20px', borderRadius: '12px', border: '1px solid var(--border-color)', borderTop: '4px solid #8b5cf6' }}>
          <div style={{ fontSize: '14px', fontWeight: 500 }}>رأس المال العامل (Working Capital)</div>
          <div style={{ fontSize: '28px', fontWeight: 700, margin: '8px 0', color: '#8b5cf6' }}>
            {formatCurrency(data.working_capital)}
          </div>
          <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>الأصول المتداولة - الخصوم المتداولة</div>
        </div>
      </div>
      
    </div>
  )
}

// ── Tab 2: Trial Balance ──────────────────────────────────────────────

function TrialBalanceTab({ data, showParents, setShowParents }: { data: TrialBalanceEntry[], showParents: boolean, setShowParents: (v: boolean) => void }) {
  const [search, setSearch] = useState('')
  const [typeFilter, setTypeFilter] = useState('all')
  const [sort, setSort] = useState<SortState<keyof TrialBalanceEntry>>({ key: 'account_code', dir: 'asc' })

  // Filtering
  const filtered = data.filter(d => {
    if (typeFilter !== 'all' && d.account_type !== typeFilter) return false
    if (search) {
      const q = search.toLowerCase()
      if (!d.account_code.includes(q) && !(d.account_name?.toLowerCase() || '').includes(q)) return false
    }
    return true
  })

  // Sorting
  const displayData = sortData(filtered, sort.key, sort.dir)

  const handleSort = (key: keyof TrialBalanceEntry) => setSort(toggleSort(sort, key))

  // Footer sums:
  // - If showParents is true, only sum the top-level accounts (depth === 0) to avoid double counting.
  // - If showParents is false, all rows represent direct movement, so sum all of them.
  const accountsToSum = showParents ? filtered.filter(d => d.depth === 0) : filtered;
  const totalDebits = accountsToSum.reduce((acc, r) => acc + Number(r.total_debit), 0)
  const totalCredits = accountsToSum.reduce((acc, r) => acc + Number(r.total_credit), 0)
  const diff = Math.abs(totalDebits - totalCredits)

  return (
    <div className="card">
      <div className="p-4" style={{ display: 'flex', gap: '16px', alignItems: 'center', flexWrap: 'wrap', borderBottom: '1px solid var(--border-color)' }}>
        <div className="input-group" style={{ maxWidth: '300px', flex: 1 }}>
          <span className="input-group-text"><Search size={16} /></span>
          <input 
            type="text" 
            className="form-control" 
            placeholder="بحث بالرقم الدليلي أو الاسم..." 
            value={search}
            onChange={e => setSearch(e.target.value)}
          />
        </div>
        
        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
          <Filter size={16} style={{ color: 'var(--text-muted)' }} />
          <select className="form-select form-select-sm" value={typeFilter} onChange={e => setTypeFilter(e.target.value)} style={{ width: '150px' }}>
            <option value="all">كل الأنواع</option>
            <option value="asset">أصول</option>
            <option value="liability">التزامات</option>
            <option value="equity">حقوق ملكية</option>
            <option value="revenue">إيرادات</option>
            <option value="expense">مصروفات</option>
          </select>
        </div>
        
        <div style={{ flexGrow: 1 }} />
        
        <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer', userSelect: 'none', fontSize: '14px', fontWeight: 500 }}>
          <input 
            type="checkbox" 
            checked={showParents} 
            onChange={e => setShowParents(e.target.checked)} 
            style={{ width: '16px', height: '16px' }}
          />
          عرض المجموعات (Rollup)
        </label>
      </div>

      <div className="table-responsive">
        <table className="table">
          <thead>
            <tr>
              <SortHeader label="الكود" sortKey="account_code" current={sort} onSort={handleSort} width="120px" />
              <SortHeader label="الاسم" sortKey="account_name" current={sort} onSort={handleSort} />
              <SortHeader label="النوع" sortKey="account_type" current={sort} onSort={handleSort} width="100px" />
              <SortHeader label="مدين" sortKey="total_debit" current={sort} onSort={handleSort} width="150px" />
              <SortHeader label="دائن" sortKey="total_credit" current={sort} onSort={handleSort} width="150px" />
              <SortHeader label="الصافي" sortKey="net_balance" current={sort} onSort={handleSort} width="150px" />
            </tr>
          </thead>
          <tbody>
            {displayData.map((row) => {
              const isGroup = !row.is_leaf
              const typeTrans: Record<string,string> = { asset:'أصل', liability:'التزام', equity:'حقوق ملكية', revenue:'إيراد', expense:'مصروف' }
              return (
                <tr key={row.account_id} style={{ 
                  fontWeight: isGroup ? 700 : 400, 
                  background: isGroup ? 'rgba(0,0,0,0.02)' : 'transparent',
                }}>
                  <td style={{ paddingRight: `${isGroup ? 16 : 32}px` }}>{row.account_code}</td>
                  <td>{row.account_name} {isGroup && <span style={{ fontSize: '10px', background: 'var(--border-color)', padding: '2px 6px', borderRadius: '4px', marginRight: '8px' }}>مجموعة</span>}</td>
                  <td className="text-muted text-sm">{typeTrans[row.account_type] || row.account_type}</td>
                  <td style={{ color: Number(row.total_debit) > 0 ? 'inherit' : 'var(--text-muted)' }}>{formatCurrency(row.total_debit)}</td>
                  <td style={{ color: Number(row.total_credit) > 0 ? 'inherit' : 'var(--text-muted)' }}>{formatCurrency(row.total_credit)}</td>
                  <td style={{ 
                    fontWeight: 600, 
                    color: Number(row.net_balance) < 0 ? 'var(--color-danger)' : 'var(--color-success)' 
                  }}>
                    {Number(row.net_balance) === 0 ? '-' : formatCurrency(row.net_balance)}
                  </td>
                </tr>
              )
            })}
            {displayData.length === 0 && (
              <tr><td colSpan={6} className="text-center p-8 text-muted">لا توجد حسابات مطابقة</td></tr>
            )}
          </tbody>
          <tfoot style={{ background: 'var(--bg-surface-alt)', fontWeight: 700 }}>
            <tr>
              <td colSpan={3} className="text-left" style={{ padding: '16px' }}>إجمالي الحركة (للحسابات الفرعية المعروضة):</td>
              <td style={{ padding: '16px', color: 'var(--color-success)' }}>{formatCurrency(totalDebits)}</td>
              <td style={{ padding: '16px', color: 'var(--color-success)' }}>{formatCurrency(totalCredits)}</td>
              <td style={{ padding: '16px' }}>
                {diff <= 0.01 
                  ? <span style={{ color: 'var(--color-success)', display: 'flex', alignItems: 'center', gap: '4px' }}><CheckCircle2 size={16} /> متزن</span>
                  : <span style={{ color: 'var(--color-danger)', display: 'flex', alignItems: 'center', gap: '4px' }}><XCircle size={16} /> فرق: {formatCurrency(diff)}</span>
                }
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  )
}

// ── Tab 3: Income Statement ───────────────────────────────────────────

function IncomeTab({ data }: { data: any }) {
  return (
    <div style={{ maxWidth: '800px', margin: '0 auto', display: 'flex', flexDirection: 'column', gap: '16px' }}>
      <StatementRow label={`إجمالي الإيرادات (4100)`} amount={data.gross_revenue} />
      <StatementRow label={`(-) مرتجعات المبيعات (4200)`} amount={-data.sales_returns} indent />
      <StatementRow label={`(-) خصومات المبيعات (4300)`} amount={-data.sales_discounts} indent />
      <StatementTotal label="صافي الإيرادات" amount={data.net_revenue} />
      
      <div style={{ height: '8px' }} />
      <StatementRow label={`(-) تكلفة البضاعة المباعة (5100)`} amount={-data.cogs} />
      <StatementTotal label="مجمل الربح (Gross Profit)" amount={data.gross_profit} subtext={`هامش: ${data.gross_margin_pct}%`} bold underline />
      
      <div style={{ height: '8px' }} />
      <StatementRow label={`(-) مصروفات تشغيلية (52xx)`} amount={-data.operating_expenses} />
      <StatementRow label={`(-) مصروفات رواتب (531x-533x)`} amount={-data.payroll_expenses} />
      <StatementRow label={`(-) تسويات مخزونية (5300)`} amount={-data.inventory_adjustments} subtext="عجز/زيادة وفروق تكلفة WAC" />
      <StatementRow label={`(-) فروق تقريب (5900)`} amount={-data.rounding_diffs} />
      <StatementTotal label="إجمالي المصروفات" amount={-data.total_expenses} />
      
      <div style={{ height: '16px' }} />
      <div style={{ display: 'flex', justifyContent: 'space-between', padding: '20px', background: 'var(--bg-surface-alt)', borderRadius: '12px', border: '1px solid var(--border-color)', fontWeight: 800, fontSize: '18px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <TrendingUp size={24} style={{ color: data.net_profit >= 0 ? 'var(--color-success)' : 'var(--color-danger)' }} />
          صافي الربح للفترة (Net Profit)
        </div>
        <div style={{ textAlign: 'right' }}>
          <div style={{ color: data.net_profit >= 0 ? 'var(--color-success)' : 'var(--color-danger)' }}>
            {formatCurrency(data.net_profit)}
          </div>
          <div style={{ fontSize: '12px', color: 'var(--text-secondary)', fontWeight: 500, marginTop: '4px' }}>
            هامش الربح الصافي: {data.net_margin_pct}%
          </div>
        </div>
      </div>
    </div>
  )
}

// ── Tab 4: Balance Sheet ──────────────────────────────────────────────

function BalanceTab({ data, isData_date }: { data: any; isData_date: string }) {
  const diff = Math.abs(data.balance_diff)
  const isBalanced = data.balance_check

  return (
    <div>
      {/* Overview equation */}
      <div style={{ display: 'flex', alignItems: 'stretch', gap: '16px', background: 'var(--bg-surface-alt)', padding: '20px', borderRadius: '12px', marginBottom: '24px', flexWrap: 'wrap' }}>
        <div style={{ flex: 1, minWidth: '200px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
          <div style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>إجمالي الأصول</div>
          <div style={{ fontSize: '24px', fontWeight: 800, color: 'var(--color-primary)' }}>{formatCurrency(data.total_assets)}</div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', fontSize: '24px', fontWeight: 800, color: 'var(--text-muted)' }}>=</div>
        <div style={{ flex: 1, minWidth: '200px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
          <div style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>الالتزامات</div>
          <div style={{ fontSize: '24px', fontWeight: 800 }}>{formatCurrency(data.total_liabilities)}</div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', fontSize: '24px', fontWeight: 800, color: 'var(--text-muted)' }}>+</div>
        <div style={{ flex: 1, minWidth: '200px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
          <div style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>حقوق الملكية (GL)</div>
          <div style={{ fontSize: '24px', fontWeight: 800 }}>{formatCurrency(data.total_equity_gl)}</div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', fontSize: '24px', fontWeight: 800, color: 'var(--text-muted)' }}>+</div>
        <div style={{ flex: 1, minWidth: '200px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
          <div style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>أرباح غير مقفلة (تراكمي)</div>
          <div style={{ fontSize: '24px', fontWeight: 800 }}>{formatCurrency(data.unclosed_pnl_to_date)}</div>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'minmax(300px, 1fr) minmax(300px, 1fr)', gap: '32px' }}>
        {/* Left Column: Assets */}
        <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-color)', borderRadius: '12px', overflow: 'hidden' }}>
          <div style={{ padding: '16px', background: 'rgba(37,99,235,0.05)', borderBottom: '2px solid var(--color-primary)', fontWeight: 700, fontSize: '16px', color: 'var(--color-primary)' }}>
            الأصول (Assets)
          </div>
          <div style={{ padding: '16px', display: 'flex', flexDirection: 'column', gap: '12px' }}>
            <SectionRow section={data.sections.cash} />
            <SectionRow section={data.sections.receivables} />
            <SectionRow section={data.sections.inventory} />
            <SectionRow section={data.sections.custody} />
            <SectionRow section={data.sections.other_assets} />
          </div>
          <div style={{ padding: '16px', background: 'var(--bg-surface-alt)', borderTop: '1px solid var(--border-color)', display: 'flex', justifyContent: 'space-between', fontWeight: 800, fontSize: '18px' }}>
            <span>إجمالي الأصول</span>
            <span>{formatCurrency(data.total_assets)}</span>
          </div>
        </div>

        {/* Right Column: Liabilities & Equity */}
        <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-color)', borderRadius: '12px', overflow: 'hidden' }}>
          <div style={{ padding: '16px', background: 'rgba(239,68,68,0.05)', borderBottom: '2px solid var(--color-danger)', fontWeight: 700, fontSize: '16px', color: 'var(--color-danger)' }}>
            الالتزامات (Liabilities)
          </div>
          <div style={{ padding: '16px', display: 'flex', flexDirection: 'column', gap: '12px' }}>
            <SectionRow section={data.sections.payables} />
            <SectionRow section={data.sections.tax_payable} />
            <SectionRow section={data.sections.employee_liabilities} />
          </div>
          <div style={{ padding: '16px', background: 'var(--bg-surface-alt)', borderTop: '1px solid var(--border-color)', display: 'flex', justifyContent: 'space-between', fontWeight: 800 }}>
            <span>إجمالي الالتزامات</span>
            <span>{formatCurrency(data.total_liabilities)}</span>
          </div>

          <div style={{ padding: '16px', background: 'rgba(139,92,246,0.05)', borderBottom: '2px solid #8b5cf6', borderTop: '1px solid var(--border-color)', fontWeight: 700, fontSize: '16px', color: '#8b5cf6' }}>
            حقوق الملكية (Equity)
          </div>
          <div style={{ padding: '16px', display: 'flex', flexDirection: 'column', gap: '12px' }}>
            <SectionRow section={data.sections.capital} />
            <SectionRow section={data.sections.retained_earnings} />
            <div style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0', borderBottom: '1px dashed var(--border-color)', color: 'var(--text-secondary)' }}>
              <span>أرباح/خسائر غير مقفلة (تراكمي) P&L</span>
              <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{formatCurrency(data.unclosed_pnl_to_date)}</span>
            </div>
          </div>
          <div style={{ padding: '16px', background: 'var(--bg-surface-alt)', borderTop: '1px solid var(--border-color)', display: 'flex', justifyContent: 'space-between', fontWeight: 800 }}>
            <span>إجمالي حقوق الملكية (مع الأرباح)</span>
            <span>{formatCurrency(data.total_equity_gl + data.unclosed_pnl_to_date)}</span>
          </div>
          
          <div style={{ padding: '20px', background: 'var(--bg-surface)', borderTop: '2px solid var(--border-color)', display: 'flex', justifyContent: 'space-between', fontWeight: 800, fontSize: '18px' }}>
            <span>إجمالي الالتزامات وحقوق الملكية</span>
            <span>{formatCurrency(data.total_liabilities + data.total_equity_gl + data.unclosed_pnl_to_date)}</span>
          </div>
        </div>
      </div>

      <div style={{ marginTop: '24px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px', background: isBalanced ? 'rgba(16,185,129,0.05)' : 'rgba(239,68,68,0.05)', border: `1px solid ${isBalanced ? '#10b981' : '#ef4444'}`, borderRadius: '12px' }}>
        <div style={{ display: 'flex', gap: '12px', alignItems: 'center', color: isBalanced ? '#10b981' : '#ef4444', fontWeight: 600 }}>
          {isBalanced ? <CheckCircle2 size={24} /> : <XCircle size={24} />}
          <div>
            <div>{isBalanced ? 'الميزانية متزنة (معادلة الميزانية صحيحة)' : 'الميزانية غير متزنة'}</div>
            {!isBalanced && <div style={{ fontSize: '13px', marginTop: '4px' }}>يوجد فرق بقيمة {formatCurrency(diff)} لم يتم تخصيصه بشكل صحيح. قد يكون هناك خلل في القيود الافتتاحية.</div>}
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', fontSize: '13px', color: 'var(--text-secondary)' }}>
          <div style={{ background: '#e0e7ff', color: '#4338ca', padding: '4px 8px', borderRadius: '4px', fontWeight: 600, display: 'inline-block', marginBottom: '8px' }}>
            صافي ربح الفترة المعروضة: {formatCurrency(data.net_profit_current_period)}
          </div>
          (للعرض فقط - الأرباح التراكمية مستخدمة في المعادلة)
        </div>
      </div>
    </div>
  )
}

function SectionRow({ section }: { section: BalanceSheetSection }) {
  if (!section) return null
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0', borderBottom: '1px dashed var(--border-color)' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
        <span style={{ fontWeight: 500 }}>{section.label}</span>
      </div>
      <span style={{ fontWeight: 600 }}>{formatCurrency(section.total)}</span>
    </div>
  )
}

function StatementRow({ label, amount, indent = false, subtext }: { label: string; amount: number; indent?: boolean; subtext?: string }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 16px', background: 'var(--bg-surface)', borderRadius: '8px', border: '1px solid var(--border-color)', marginLeft: indent ? '24px' : '0' }}>
      <div>
        <div style={{ fontWeight: 500 }}>{label}</div>
        {subtext && <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '2px' }}>{subtext}</div>}
      </div>
      <div style={{ fontWeight: 600, color: amount < 0 ? 'var(--color-danger)' : 'inherit' }}>
        {formatCurrency(amount)}
      </div>
    </div>
  )
}

function StatementTotal({ label, amount, bold = false, underline = false, subtext }: { label: string; amount: number; bold?: boolean; underline?: boolean; subtext?: string }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '16px', background: 'var(--bg-surface-alt)', borderRadius: '8px', borderTop: underline ? '2px solid var(--border-color)' : 'none' }}>
      <div style={{ fontWeight: bold ? 700 : 600, fontSize: bold ? '16px' : '15px' }}>{label}</div>
      <div style={{ textAlign: 'right' }}>
        <div style={{ fontWeight: bold ? 700 : 600, fontSize: bold ? '16px' : '15px' }}>{formatCurrency(amount)}</div>
        {subtext && <div style={{ fontSize: '12px', color: 'var(--text-secondary)', marginTop: '2px' }}>{subtext}</div>}
      </div>
    </div>
  )
}
