import React, { useState } from 'react'
import { useGrossProfitByRep } from '@/hooks/useProfitability'
import FinancialBreakdownTable, { ColumnDef } from '@/components/reports/profitability/FinancialBreakdownTable'
import ReportFilterBar, { DateRange } from '@/components/reports/ReportFilterBar'
import { Download } from 'lucide-react'
import { downloadAsCSV } from '@/lib/utils/export'
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

export default function RepProfitabilityPage() {
  const { setTitle } = usePageTitle()
  React.useEffect(() => setTitle('ربحية المندوبين (هامش الربح الإجمالي)'), [setTitle])

  const [dateRange, setDateRange] = useState<DateRange>(getInitialDateRange)

  const { data, isLoading } = useGrossProfitByRep({
    date_from: dateRange.from,
    date_to: dateRange.to,
    granularity: 'monthly',
    limit_count: 500
  })

  // Using entity_id_display which maps from rep_id
  const columns: ColumnDef<any>[] = [
    { key: 'entity_id_display', header: 'المندوب', align: 'right' },
    { key: 'net_quantity', header: 'الكمية المباعة' },
    { key: 'net_revenue_after_returns', header: 'صافي الإيراد بعد المرتجعات' },
    { key: 'net_cogs', header: 'تكلفة المبيعات' },
    { key: 'gross_profit', header: 'مجمل الربح' },
  ]

  const exportCSV = () => {
    if (!data) return
    downloadAsCSV(data, `Reps_Profitability_${dateRange.from}_${dateRange.to}`, [
      { key: 'entity_id_display', label: 'المندوب' },
      { key: 'net_quantity', label: 'الكمية المباعة' },
      { key: 'net_revenue_after_returns', label: 'صافي الإيراد بعد المرتجعات' },
      { key: 'net_cogs', label: 'تكلفة البضاعة المباعة' },
      { key: 'gross_profit', label: 'إجمالي الربح' }
    ])
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 'var(--space-4)' }}>
        <div>
          <h2 style={{ fontSize: 'var(--text-xl)', fontWeight: 700, margin: 0 }}>تحليل المندوبين</h2>
        </div>
        <div style={{ display: 'flex', gap: 'var(--space-3)' }}>
          <ReportFilterBar value={dateRange} onChange={setDateRange} />
          <button className="btn btn-secondary" onClick={exportCSV} disabled={!data || data.length === 0} style={{ padding: '0 12px' }}>
            <Download size={16} />
          </button>
        </div>
      </div>

      <FinancialBreakdownTable
        data={data || []}
        columns={columns}
        rowKey={row => row.rep_id ?? 'unknown'}
        isLoading={isLoading}
      />
    </div>
  )
}
