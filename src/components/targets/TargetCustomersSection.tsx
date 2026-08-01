import React from 'react'
import type { TargetCustomer, TargetCustomerProgressRow } from '@/lib/types/activities'

interface TargetCustomersSectionProps {
  customers: TargetCustomer[]
  progress?: TargetCustomerProgressRow[]
  typeCode?: string
  loading?: boolean
  error?: boolean
}

const formatDate = (d: string | null) => {
  if (!d) return ''
  return new Date(d).toLocaleDateString('ar-EG-u-nu-latn', { month: 'short', year: 'numeric' })
}

const STATUS_AR: Record<string, string> = {
  achieved: 'متحقق', baseline_missing: 'خط الأساس غير متاح', no_sales_yet: 'لا مبيعات بعد',
  in_progress: 'جارٍ التقدم', dormancy_not_verified: 'الخمول غير متحقق',
  not_reactivated_yet: 'لم يعد للشراء', below_minimum_value: 'أقل من حد العودة',
  required_count_missing: 'العدد المطلوب غير محدد', no_categories_yet: 'لا تصنيفات بعد',
}

export default function TargetCustomersSection({ customers, progress = [], typeCode, loading = false, error = false }: TargetCustomersSectionProps) {
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

  const achievedCustomers = progress.filter(row => row.is_achieved).length
  const progressByCustomer = new Map(progress.map(row => [row.customer_id, row]))

  const baselineLabel = (c: TargetCustomer) => typeCode === 'reactivation'
    ? (c.baseline_period_end || '—')
    : typeCode === 'category_spread'
      ? `${(c.baseline_category_count ?? 0).toLocaleString('en-US')} تصنيف`
      : c.baseline_value != null ? `${c.baseline_value.toLocaleString('en-US', { maximumFractionDigits: 1 })} ج.م` : '—'

  const progressLabel = (row?: TargetCustomerProgressRow) => row
    ? `${row.achieved_value.toLocaleString('en-US', { maximumFractionDigits: 1 })} / ${row.required_value.toLocaleString('en-US', { maximumFractionDigits: 1 })}`
    : '—'

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
        {loading ? (
          <span className="tc-summary" role="status">جاري تحديث التقدم...</span>
        ) : error ? (
          <span className="tc-summary tc-summary--error">تعذر تحميل التقدم</span>
        ) : progress.length > 0 && (
          <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--color-success)' }}>
            تحقق {achievedCustomers} من {customers.length}
          </span>
        )}
      </div>

      <div className="tc-table-wrap">
        <table className="tc-table">
          <thead>
            <tr style={{ background: 'var(--bg-body)', borderBottom: '1px solid var(--border-color)' }}>
              <th style={{ padding: '12px 20px', fontSize: '12px', color: 'var(--text-secondary)', fontWeight: 600 }}>العميل</th>
              <th style={{ padding: '12px 20px', fontSize: '12px', color: 'var(--text-secondary)', fontWeight: 600 }}>
                {typeCode === 'category_spread' ? 'التصنيفات الحالية / المطلوبة' : typeCode === 'reactivation' ? 'صافي العودة / الحد' : 'الصافي الحالي / المطلوب'}
              </th>
              <th style={{ padding: '12px 20px', fontSize: '12px', color: 'var(--text-secondary)', fontWeight: 600 }}>
                {typeCode === 'reactivation' ? 'آخر شراء قبل الهدف' : 'خط الأساس'}
              </th>
              <th style={{ padding: '12px 20px', fontSize: '12px', color: 'var(--text-secondary)', fontWeight: 600 }}>الحالة</th>
            </tr>
          </thead>
          <tbody>
            {customers.map((c, i) => {
               const row = progressByCustomer.get(c.customer_id)
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
                    {progressLabel(row)}
                  </td>
                  <td style={{ padding: '12px 20px', fontSize: '14px', color: 'var(--text-primary)' }}>
                    {baselineLabel(c)}
                  </td>
                  <td style={{ padding: '12px 20px', fontSize: '13px', color: 'var(--text-secondary)' }}>
                    {row ? (
                      <span style={{ color: row.is_achieved ? 'var(--color-success)' : 'var(--text-secondary)', fontWeight: 600 }}>
                        {row.is_achieved ? '✓ ' : ''}{STATUS_AR[row.status_reason] ?? row.status_reason}
                      </span>
                    ) : periodStr}
                  </td>
                </tr>
               )
            })}
          </tbody>
        </table>
      </div>

      <div className="tc-mobile-list">
        {customers.map(c => {
          const row = progressByCustomer.get(c.customer_id)
          return (
            <article key={c.id} className={`tc-mobile-card${row?.is_achieved ? ' tc-mobile-card--achieved' : ''}`}>
              <div className="tc-mobile-head">
                <div className="tc-mobile-name">
                  <strong>{c.customer?.name || 'عميل غير معروف'}</strong>
                  {c.customer?.code && <span dir="ltr">{c.customer.code}</span>}
                </div>
                <span className={`tc-status${row?.is_achieved ? ' tc-status--success' : ''}`}>
                  {loading ? 'جاري التحديث' : row ? `${row.is_achieved ? '✓ ' : ''}${STATUS_AR[row.status_reason] ?? row.status_reason}` : '—'}
                </span>
              </div>
              <div className="tc-mobile-metrics">
                <div><span>الحالي / المطلوب</span><strong dir="ltr">{progressLabel(row)}</strong></div>
                <div><span>{typeCode === 'reactivation' ? 'آخر شراء' : 'خط الأساس'}</span><strong>{baselineLabel(c)}</strong></div>
              </div>
            </article>
          )
        })}
      </div>

      <style>{`
        .tc-summary { font-size: 12px; font-weight: 600; color: var(--text-muted); }
        .tc-summary--error { color: var(--color-danger); }
        .tc-table-wrap { overflow-x: auto; -webkit-overflow-scrolling: touch; }
        .tc-table { min-width: 100%; border-collapse: collapse; text-align: start; }
        .tc-mobile-list { display: none; }
        @media (max-width: 640px) {
          .tc-table-wrap { display: none; }
          .tc-mobile-list { display: flex; flex-direction: column; gap: var(--space-3); padding: var(--space-3); }
          .tc-mobile-card { border: 1px solid var(--border-primary); border-radius: var(--radius-md); padding: var(--space-3); background: var(--bg-surface); }
          .tc-mobile-card--achieved { border-color: var(--color-success); background: var(--color-success-light); }
          .tc-mobile-head { display: flex; align-items: flex-start; justify-content: space-between; gap: var(--space-2); }
          .tc-mobile-name { min-width: 0; display: flex; flex-direction: column; gap: 2px; color: var(--text-primary); font-size: 14px; }
          .tc-mobile-name span { color: var(--text-muted); font-size: 12px; text-align: end; }
          .tc-status { flex-shrink: 0; max-width: 48%; border-radius: 999px; padding: 4px 8px; background: var(--bg-surface-2); color: var(--text-secondary); font-size: 12px; font-weight: 600; text-align: center; }
          .tc-status--success { background: var(--color-success-light); color: var(--color-success); }
          .tc-mobile-metrics { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-2); margin-top: var(--space-3); }
          .tc-mobile-metrics > div { display: flex; flex-direction: column; gap: 3px; padding: var(--space-2); border-radius: var(--radius-sm); background: var(--bg-surface-2); min-width: 0; }
          .tc-mobile-metrics span { color: var(--text-muted); font-size: 12px; }
          .tc-mobile-metrics strong { color: var(--text-primary); font-size: 13px; overflow-wrap: anywhere; }
        }
        @media (max-width: 380px) {
          .tc-mobile-head { flex-direction: column; }
          .tc-status { max-width: 100%; }
          .tc-mobile-metrics { grid-template-columns: 1fr; }
        }
      `}</style>
    </div>
  )
}
