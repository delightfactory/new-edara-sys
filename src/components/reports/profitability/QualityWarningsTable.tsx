import React from 'react'
import type { AllocationQualityReportResult } from '@/lib/types/profitability'
import { AlertTriangle, AlertCircle, Info } from 'lucide-react'

interface QualityWarningsTableProps {
  data: AllocationQualityReportResult[]
  isLoading?: boolean
}

export default function QualityWarningsTable({ data, isLoading }: QualityWarningsTableProps) {
  if (isLoading) {
    return <div style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)' }}>جارٍ تحميل التقارير...</div>
  }

  if (!data || data.length === 0) {
    return (
      <div style={{ 
        padding: 'var(--space-12)', textAlign: 'center', color: 'var(--color-success)',
        background: 'var(--bg-surface)', borderRadius: 'var(--radius-lg)', border: '1px solid var(--border-primary)' 
      }}>
        لا توجد أي تحذيرات أو أخطاء في جودة التوزيع للفترة المحددة. البيانات سليمة.
      </div>
    )
  }

  const getSeverityColor = (sev: string) => {
    switch(sev) {
      case 'ERROR': return 'var(--color-danger)'
      case 'WARNING': return 'var(--color-warning-dark)'
      default: return 'var(--color-info)'
    }
  }

  const getSeverityBg = (sev: string) => {
    switch(sev) {
      case 'ERROR': return 'var(--color-danger-light)'
      case 'WARNING': return 'var(--color-warning-light)'
      default: return 'var(--bg-secondary)'
    }
  }

  const getIcon = (sev: string) => {
    switch(sev) {
      case 'ERROR': return <AlertCircle size={16} color="var(--color-danger)" />
      case 'WARNING': return <AlertTriangle size={16} color="var(--color-warning-dark)" />
      default: return <Info size={16} color="var(--color-info)" />
    }
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
      {data.map((item, i) => (
        <div key={i} style={{
          display: 'flex', gap: 'var(--space-4)', padding: 'var(--space-4)',
          background: 'var(--bg-surface)', borderRadius: 'var(--radius-md)',
          borderInlineStart: `4px solid ${getSeverityColor(item.severity)}`,
          border: '1px solid var(--border-primary)',
          borderRightWidth: '1px'
        }}>
          <div style={{ 
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            width: '40px', height: '40px', borderRadius: '50%',
            background: getSeverityBg(item.severity), flexShrink: 0
          }}>
            {getIcon(item.severity)}
          </div>
          <div style={{ flex: 1 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <h4 style={{ margin: 0, fontSize: 'var(--text-md)', fontWeight: 600, color: getSeverityColor(item.severity) }}>
                {item.check_type.replace(/_/g, ' ')}
              </h4>
              <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                {item.check_date}
              </span>
            </div>
            
            {/* Display metadata context */}
            {item.detail && Object.keys(item.detail).length > 0 && (
              <div style={{ 
                marginTop: 'var(--space-2)', fontSize: 'var(--text-xs)', color: 'var(--text-secondary)',
                background: 'var(--bg-secondary)', padding: 'var(--space-2)', borderRadius: 'var(--radius-sm)'
              }}>
                <pre style={{ margin: 0, fontFamily: 'inherit' }}>
                  {JSON.stringify(item.detail, null, 2)}
                </pre>
              </div>
            )}
            
            <div style={{ marginTop: 'var(--space-2)', display: 'flex', gap: 'var(--space-3)', fontSize: 'var(--text-xs)' }}>
              <span style={{ color: 'var(--text-muted)' }}>تطبيق الفحص: <strong>{item.applies_to}</strong></span>
              {item.record_count > 0 && <span style={{ color: 'var(--text-muted)' }}>السجلات: <strong>{item.record_count}</strong></span>}
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}
