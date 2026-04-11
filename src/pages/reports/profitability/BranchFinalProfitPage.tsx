import React, { useState } from 'react'
import { useBranchFinalNetProfitMonthly } from '@/hooks/useProfitability'
import FinancialBreakdownTable, { ColumnDef, formatCurrency } from '@/components/reports/profitability/FinancialBreakdownTable'
import ReportFilterBar, { DateRange } from '@/components/reports/ReportFilterBar'
import EstimatedAllocationBadge from '@/components/reports/profitability/EstimatedAllocationBadge'
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

export default function BranchFinalProfitPage() {
  const { setTitle } = usePageTitle()
  React.useEffect(() => setTitle('الربح النهائي للفروع (Phase 3)'), [setTitle])

  const [dateRange, setDateRange] = useState<DateRange>(getInitialDateRange)

  const { data, isLoading } = useBranchFinalNetProfitMonthly({
    date_from: dateRange.from,
    date_to: dateRange.to,
  })

  const columns: ColumnDef<any>[] = [
    { 
      key: 'branch_name_display', 
      header: 'الفرع / الوعاء', 
      align: 'right',
      render: (row) => (
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <span style={{ 
            fontWeight: row.branch_id === null ? 700 : 500,
            color: row.branch_id === null ? 'var(--color-primary-dark)' : 'inherit'
          }}>
            {row.branch_name_display}
          </span>
          <EstimatedAllocationBadge isEstimated={row.is_estimated} />
        </div>
      )
    },
    { key: 'net_revenue_after_returns', header: 'صافي الإيراد بعد المرتجعات' },
    { key: 'direct_gross_profit', header: 'مجمل الربح المباشر' },
    { 
      key: 'operating_total', 
      header: 'التشغيلي (مباشر + موزع)',
      render: (row) => (
        <span>{formatCurrency(row.direct_operating_exp + row.allocated_shared_op + row.unallocated_shared_op)}</span>
      )
    },
    { 
      key: 'payroll_total', 
      header: 'الرواتب (مباشر + موزع)',
      render: (row) => (
        <span>{formatCurrency(row.direct_payroll_exp + row.allocated_shared_pay + row.unallocated_shared_pay)}</span>
      )
    },
    { key: 'final_net_profit', header: 'صافي الربح النهائي' },
    {
      key: 'allocation_status',
      header: 'حالة التوزيع',
      render: (row) => (
        <span style={{
          display: 'inline-block',
          padding: '2px 8px',
          borderRadius: '12px',
          fontSize: '11px',
          fontWeight: 600,
          background: row.allocation_status === 'ALLOCATED' ? 'var(--color-success-light)' : row.allocation_status === 'PARTIAL' ? 'var(--color-warning-light)' : 'var(--bg-secondary)',
          color: row.allocation_status === 'ALLOCATED' ? 'var(--color-success)' : row.allocation_status === 'PARTIAL' ? 'var(--color-warning-dark)' : 'var(--text-muted)',
        }}>
          {row.allocation_status === 'ALLOCATED' ? 'مكتمل' : row.allocation_status === 'PARTIAL' ? 'جزئي' : row.allocation_status ?? '—'}
        </span>
      )
    },
  ]

  const exportCSV = () => {
    if (!data) return
    downloadAsCSV(data, `Branch_Final_Profitability_${dateRange.from}_${dateRange.to}`, [
      { key: 'branch_name_display', label: 'الفرع' },
      { key: 'net_revenue_after_returns', label: 'صافي الإيراد بعد المرتجعات' },
      { key: 'direct_gross_profit', label: 'إجمالي الربح المباشر' },
      { key: 'direct_operating_exp', label: 'ت. تشغيلية مباشرة' },
      { key: 'allocated_shared_op', label: 'ت. تشغيلية موزعة' },
      { key: 'unallocated_shared_op', label: 'ت. تشغيلية غير موزعة' },
      { key: 'direct_payroll_exp', label: 'رواتب مباشرة' },
      { key: 'allocated_shared_pay', label: 'رواتب موزعة' },
      { key: 'unallocated_shared_pay', label: 'رواتب غير موزعة' },
      { key: 'final_net_profit', label: 'صافي الربح النهائي' },
      { key: 'is_estimated', label: 'مبني على تقدير؟' },
      { key: 'allocation_status', label: 'حالة التوزيع' }
    ])
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 'var(--space-4)' }}>
        <div>
          <h2 style={{ fontSize: 'var(--text-xl)', fontWeight: 700, margin: 0 }}>نهائي الفروع (بعد التوزيع)</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)', marginTop: '4px' }}>
            يتضمن التكاليف المشتركة الموزعة حسب القواعد المعتمدة. المبالغ المتبقية بلا توزيع تُسجل في "وعاء مشترك غير موزع".
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
        rowKey={row => row.branch_id ?? 'unallocated_pool'}
        isLoading={isLoading}
      />
    </div>
  )
}
