import React, { useState } from 'react'
import { useProfitSummary } from '@/hooks/useProfitability'
import { useSystemTrustState, useTrustForComponent } from '@/hooks/useSystemTrustState'
import MetricCard from '@/components/reports/MetricCard'
import ReportFilterBar, { DateRange } from '@/components/reports/ReportFilterBar'
import { Wallet, TrendingUp, Building } from 'lucide-react'
import { usePageTitle } from '@/components/layout/PageTitleContext'
import { toLocalISODate } from '@/lib/utils/date'

function getInitialDateRange(): DateRange {
  const d = new Date()
  const from = new Date(d.getFullYear(), d.getMonth(), 1)
  return {
    from: toLocalISODate(from),
    to: toLocalISODate(d)
  }
}

export default function ProfitDashboard() {
  const { setTitle } = usePageTitle()
  React.useEffect(() => setTitle('لوحة معلومات الربحية'), [setTitle])

  const [dateRange, setDateRange] = useState<DateRange>(getInitialDateRange)
  const [branchId] = useState<string | null>(null)

  const { data: summary, isLoading } = useProfitSummary({
    date_from: dateRange.from,
    date_to: dateRange.to,
    branch_id: branchId
  })

  // We are pulling a single domain 'profit_overview' for the trust state
  const { data: trustRows } = useSystemTrustState('profit_overview') 
  const overviewTrust = useTrustForComponent(trustRows, 'fact_profit_daily')

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 'var(--space-4)' }}>
        <h2 style={{ fontSize: 'var(--text-xl)', fontWeight: 700, margin: 0 }}>نظرة عامة على الربحية</h2>
        <ReportFilterBar value={dateRange} onChange={setDateRange} />
      </div>

      <div className="report-grid">
        <MetricCard
          label="صافي الإيراد بعد المرتجعات"
          value={isLoading ? '...' : summary?.net_revenue ?? 0}
          status={overviewTrust?.status ?? null}
          lastCompletedAt={overviewTrust?.last_completed_at}
          isStale={overviewTrust?.is_stale}
          domain="profit_overview"
          icon={<TrendingUp />}
        />
        <MetricCard
          label="المبيعات (تكلفة البضاعة)"
          value={isLoading ? '...' : summary?.cogs ?? 0}
          status={overviewTrust?.status ?? null}
          lastCompletedAt={overviewTrust?.last_completed_at}
          isStale={overviewTrust?.is_stale}
          domain="profit_overview"
          icon={<PackageIcon />}
        />
        <MetricCard
          label="إجمالي الربح (التشغيلي)"
          value={isLoading ? '...' : summary?.gross_profit ?? 0}
          status={overviewTrust?.status ?? null}
          lastCompletedAt={overviewTrust?.last_completed_at}
          isStale={overviewTrust?.is_stale}
          domain="profit_overview"
          icon={<Wallet />}
          secondary={summary ? { label: 'هامش الربح', value: summary.net_revenue && summary.net_revenue > 0 ? ((summary.gross_profit / summary.net_revenue) * 100).toFixed(1) + '%' : '0%' } : undefined}
        />
        <MetricCard
          label="المصروفات التشغيلية والرواتب"
          value={isLoading ? '...' : (summary?.operating_expenses ?? 0) + (summary?.payroll_expenses ?? 0)}
          status={overviewTrust?.status ?? null}
          lastCompletedAt={overviewTrust?.last_completed_at}
          isStale={overviewTrust?.is_stale}
          domain="profit_overview"
          icon={<Building />}
        />
      </div>

      <div className="report-grid-2">
        <div style={{ background: 'var(--bg-surface)', padding: 'var(--space-6)', borderRadius: 'var(--radius-lg)', border: '1px solid var(--primary-light)'}}>
           <h3 style={{ fontSize: 'var(--text-lg)', marginBottom: 'var(--space-4)' }}>صافي الربح النهائي</h3>
           <div style={{ fontSize: '2.5rem', fontWeight: 800, color: 'var(--color-primary-dark)' }}>
             {isLoading ? '...' : new Intl.NumberFormat('ar-EG').format(summary?.net_profit ?? 0)}
             <span style={{ fontSize: '1rem', color: 'var(--text-muted)', marginInlineStart: 'var(--space-2)', fontWeight: 500 }}>ج.م</span>
           </div>
           {summary && summary.net_revenue > 0 && (
             <div style={{ marginTop: 'var(--space-2)', color: 'var(--text-secondary)' }}>
               هامش صافي الربح: <strong>{((summary.net_profit / summary.net_revenue) * 100).toFixed(1)}%</strong>
             </div>
           )}
        </div>
      </div>
    </div>
  )
}

function PackageIcon() {
  return <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="16.5" y1="9.4" x2="7.5" y2="4.21"></line><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"></path><polyline points="3.27 6.96 12 12.01 20.73 6.96"></polyline><line x1="12" y1="22.08" x2="12" y2="12"></line></svg>
}
