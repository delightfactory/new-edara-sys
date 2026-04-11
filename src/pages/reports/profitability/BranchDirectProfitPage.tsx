import React, { useState } from 'react'
import { useBranchDirectNetProfit } from '@/hooks/useProfitability'
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

export default function BranchDirectProfitPage() {
  const { setTitle } = usePageTitle()
  React.useEffect(() => setTitle('الربح المباشر للفروع (Phase 2)'), [setTitle])

  const [dateRange, setDateRange] = useState<DateRange>(getInitialDateRange)

  const { data, isLoading } = useBranchDirectNetProfit({
    date_from: dateRange.from,
    date_to: dateRange.to,
  })

  // Using entity_id_display which maps from branch_id
  const columns: ColumnDef<any>[] = [
    { key: 'entity_id_display', header: 'الفرع', align: 'right' },
    { key: 'net_revenue_after_returns', header: 'صافي الإيراد بعد المرتجعات' },
    { key: 'gross_cogs', header: 'تكلفة المبيعات' },
    { key: 'gross_profit', header: 'مجمل الربح المباشر' },
    { key: 'operating_expense', header: 'المصروفات التشغيلية المباشرة' },
    { key: 'payroll_expense', header: 'الرواتب المباشرة' },
    { key: 'net_profit', header: 'صافي الربح المباشر' },
  ]

  const exportCSV = () => {
    if (!data) return
    downloadAsCSV(data, `Branch_Direct_Profitability_${dateRange.from}_${dateRange.to}`, [
      { key: 'entity_id_display', label: 'الفرع' },
      { key: 'net_revenue_after_returns', label: 'صافي الإيراد بعد المرتجعات' },
      { key: 'gross_cogs', label: 'تكلفة البضاعة المباعة' },
      { key: 'gross_profit', label: 'إجمالي الربح المباشر' },
      { key: 'operating_expense', label: 'المصروفات التشغيلية المباشرة' },
      { key: 'payroll_expense', label: 'الرواتب المباشرة' },
      { key: 'net_profit', label: 'صافي الربح المباشر' }
    ])
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 'var(--space-4)' }}>
        <div>
          <h2 style={{ fontSize: 'var(--text-xl)', fontWeight: 700, margin: 0 }}>مباشر الفروع</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)', marginTop: '4px' }}>
            يوضح التكاليف والأرباح المسندة مباشرة للفروع. لا يتم توزيع أحواض التكلفة المشتركة (Shared Pools) في هذا التقرير.
          </p>
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
        rowKey={row => row.branch_id ?? 'unknown'}
        isLoading={isLoading}
      />
    </div>
  )
}
