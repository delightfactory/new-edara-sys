import React from 'react'
import type { TargetCustomer } from '@/lib/types/activities'

interface TargetCustomersSectionProps {
  customers: TargetCustomer[]
}

const formatDate = (d: string | null) => {
  if (!d) return ''
  return new Date(d).toLocaleDateString('ar-EG', { month: 'short', year: 'numeric' })
}

export default function TargetCustomersSection({ customers }: TargetCustomersSectionProps) {
  if (!customers || customers.length === 0) {
    return (
      <div style={{
        background: 'var(--bg-surface)', border: '1px solid var(--border-color)',
        borderRadius: '12px', padding: '24px', textAlign: 'center', color: 'var(--text-muted)'
      }}>
        لا يوجد عملاء مستهدفين. (الهدف ينطبق على النطاق العام).
      </div>
    )
  }

  return (
    <div style={{
      background: 'var(--bg-surface)',
      border: '1px solid var(--border-color)',
      borderRadius: '12px',
      overflow: 'hidden'
    }}>
      <div style={{
        padding: '16px 20px',
        borderBottom: '1px solid var(--border-color)',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        background: 'var(--bg-body)'
      }}>
        <h3 style={{ margin: 0, fontSize: '15px', fontWeight: 600, color: 'var(--text-primary)' }}>
          العملاء المستهدفين ({customers.length})
        </h3>
      </div>

      <div style={{ overflowX: 'auto' }}>
        <table style={{ minWidth: '100%', borderCollapse: 'collapse', textAlign: 'right' }}>
          <thead>
            <tr style={{ background: 'var(--bg-body)', borderBottom: '1px solid var(--border-color)' }}>
              <th style={{ padding: '12px 20px', fontSize: '12px', color: 'var(--text-secondary)', fontWeight: 600 }}>العميل</th>
              <th style={{ padding: '12px 20px', fontSize: '12px', color: 'var(--text-secondary)', fontWeight: 600 }}>متوسط السحب المرجعي</th>
              <th style={{ padding: '12px 20px', fontSize: '12px', color: 'var(--text-secondary)', fontWeight: 600 }}>عدد الأصناف المرجعي</th>
              <th style={{ padding: '12px 20px', fontSize: '12px', color: 'var(--text-secondary)', fontWeight: 600 }}>فترة الأساس (Baseline)</th>
            </tr>
          </thead>
          <tbody>
            {customers.map((c, i) => {
               const periodStart = formatDate(c.baseline_period_start)
               const periodEnd = formatDate(c.baseline_period_end)
               const periodStr = periodStart && periodEnd ? `${periodStart} - ${periodEnd}` : '—'
               const customerName = c.customer?.name || 'عميل غير معروف'

               return (
                <tr key={c.id || i} style={{ borderBottom: '1px solid var(--border-color)', background: 'var(--bg-surface)' }}>
                  <td style={{ padding: '12px 20px', fontSize: '14px', fontWeight: 500, color: 'var(--text-primary)' }}>
                    {customerName}
                    {c.customer?.code && <span style={{ fontSize: '12px', color: 'var(--text-muted)', display: 'block', marginTop: '2px' }}>{c.customer.code}</span>}
                  </td>
                  <td style={{ padding: '12px 20px', fontSize: '14px', color: 'var(--text-primary)' }}>
                    {c.baseline_value != null ? c.baseline_value.toLocaleString('ar-EG', { maximumFractionDigits: 1 }) : '—'}
                  </td>
                  <td style={{ padding: '12px 20px', fontSize: '14px', color: 'var(--text-primary)' }}>
                    {c.baseline_category_count != null ? c.baseline_category_count.toLocaleString('ar-EG') : '—'}
                  </td>
                  <td style={{ padding: '12px 20px', fontSize: '13px', color: 'var(--text-secondary)' }}>
                    {periodStr}
                  </td>
                </tr>
               )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}
