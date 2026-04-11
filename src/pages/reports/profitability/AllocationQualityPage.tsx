import React, { useState } from 'react'
import { useAllocationQualityReport } from '@/hooks/useProfitability'
import QualityWarningsTable from '@/components/reports/profitability/QualityWarningsTable'
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

export default function AllocationQualityPage() {
  const { setTitle } = usePageTitle()
  React.useEffect(() => setTitle('جودة توزيع الربحية (Quality)'), [setTitle])

  const [dateRange, setDateRange] = useState<DateRange>(getInitialDateRange)

  const { data, isLoading } = useAllocationQualityReport({
    date_from: dateRange.from,
    date_to: dateRange.to,
  })

  const exportCSV = () => {
    if (!data) return
    downloadAsCSV(data, `Allocation_Quality_${dateRange.from}_${dateRange.to}`, [
      { key: 'check_date', label: 'التاريخ' },
      { key: 'check_month', label: 'الشهر' },
      { key: 'applies_to', label: 'يطبق على' },
      { key: 'check_type', label: 'نوع الفحص' },
      { key: 'severity', label: 'الخطورة' },
      { key: 'record_count', label: 'السجلات المتأثرة' },
    ])
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 'var(--space-4)' }}>
        <div>
          <h2 style={{ fontSize: 'var(--text-xl)', fontWeight: 700, margin: 0 }}>مراقبة جودة التوزيع</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)', marginTop: '4px' }}>
            يعرض التحذيرات والأخطاء الخاصة بعمليات تخصيص التكاليف والأوزان المفتقدة، لتوجيه المحاسبين لإصلاح الإعدادات.
          </p>
        </div>
        <div style={{ display: 'flex', gap: 'var(--space-3)' }}>
          <ReportFilterBar value={dateRange} onChange={setDateRange} />
          <button className="btn btn-secondary" onClick={exportCSV} disabled={!data || data.length === 0} style={{ padding: '0 12px' }}>
            <Download size={16} />
          </button>
        </div>
      </div>

      <QualityWarningsTable data={data || []} isLoading={isLoading} />
    </div>
  )
}
