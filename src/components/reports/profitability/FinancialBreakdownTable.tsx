import React from 'react'

export interface ColumnDef<T> {
  key: Extract<keyof T, string> | string
  header: string
  align?: 'left' | 'right' | 'center'
  render?: (row: T) => React.ReactNode
}

interface FinancialBreakdownTableProps<T> {
  data: T[]
  columns: ColumnDef<T>[]
  rowKey: (row: T) => string
  isLoading?: boolean
  emptyMessage?: string
}

export function formatCurrency(v: number | null | undefined): string {
  if (v === null || v === undefined) return '—'
  return new Intl.NumberFormat('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(v)
}

export default function FinancialBreakdownTable<T>({ 
  data, 
  columns, 
  rowKey,
  isLoading = false,
  emptyMessage = 'لا توجد بيانات للفترة المحددة'
}: FinancialBreakdownTableProps<T>) {

  if (isLoading) {
    return (
      <div style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)' }}>
        جارٍ تحميل البيانات...
      </div>
    )
  }

  if (!data || data.length === 0) {
    return (
      <div style={{ 
        padding: 'var(--space-12)', 
        textAlign: 'center', 
        color: 'var(--text-muted)',
        background: 'var(--bg-surface)',
        borderRadius: 'var(--radius-lg)',
        border: '1px dashed var(--border-primary)'
      }}>
        {emptyMessage}
      </div>
    )
  }

  return (
    <div style={{ overflowX: 'auto', borderRadius: 'var(--radius-lg)', border: '1px solid var(--border-primary)', background: 'var(--bg-surface)' }}>
      <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'right' }}>
        <thead style={{ background: 'var(--bg-secondary)', borderBottom: '1px solid var(--border-primary)' }}>
          <tr>
            {columns.map(col => (
              <th 
                key={col.key} 
                style={{ 
                  padding: 'var(--space-3) var(--space-4)', 
                  fontWeight: 600, 
                  fontSize: 'var(--text-xs)', 
                  color: 'var(--text-secondary)',
                  textAlign: col.align || 'right',
                  whiteSpace: 'nowrap'
                }}
              >
                {col.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {data.map((row, i) => (
            <tr key={rowKey(row)} style={{ borderBottom: i === data.length - 1 ? 'none' : '1px solid var(--border-light)' }}>
              {columns.map(col => (
                <td 
                  key={col.key} 
                  style={{ 
                    padding: 'var(--space-3) var(--space-4)', 
                    fontSize: 'var(--text-sm)', 
                    color: 'var(--text-primary)',
                    textAlign: col.align || 'right'
                  }}
                >
                  {col.render 
                    ? col.render(row) 
                    : typeof (row as any)[col.key] === 'number' 
                      ? formatCurrency((row as any)[col.key])
                      : String((row as any)[col.key] || '—')
                  }
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
