import type { ReactNode } from 'react'
import { cn } from '@/lib/utils/helpers'
import DataCard from '@/components/ui/DataCard'

interface Column<T> {
  key: string
  label: string
  render?: (item: T) => ReactNode
  hideOnMobile?: boolean
  width?: number | string
  align?: 'start' | 'center' | 'end'
}

interface DataTableProps<T> {
  columns: Column<T>[]
  data: T[]
  loading?: boolean
  keyField?: string
  onRowClick?: (item: T) => void
  emptyIcon?: ReactNode
  emptyTitle?: string
  emptyText?: string
  emptyAction?: ReactNode
  /** Pagination */
  page?: number
  totalPages?: number
  totalCount?: number
  onPageChange?: (page: number) => void
  /** Row styling */
  rowClassName?: (item: T) => string | undefined
  rowStyle?: (item: T) => React.CSSProperties | undefined
  /** Mobile DataCard rendering */
  dataCardMapping?: (item: T) => any
}

/**
 * DataTable — جدول بيانات موحد مع skeleton + empty + pagination
 * يُقلل تكرار كود الجداول في كل صفحة
 */
export default function DataTable<T extends Record<string, any>>({
  columns,
  data,
  loading,
  keyField = 'id',
  onRowClick,
  emptyIcon,
  emptyTitle = 'لا توجد بيانات',
  emptyText,
  emptyAction,
  page,
  totalPages,
  totalCount,
  onPageChange,
  rowClassName,
  rowStyle,
  dataCardMapping,
}: DataTableProps<T>) {
  // Skeleton loading
  if (loading) {
    return (
      <div style={{ padding: 'var(--space-6)' }}>
        {[1, 2, 3, 4, 5].map(i => <div key={i} className="skeleton skeleton-row" />)}
      </div>
    )
  }

  // Empty state
  if (data.length === 0) {
    return (
      <div className="empty-state">
        {emptyIcon && <div className="empty-state-icon">{emptyIcon}</div>}
        <p className="empty-state-title">{emptyTitle}</p>
        {emptyText && <p className="empty-state-text">{emptyText}</p>}
        {emptyAction}
      </div>
    )
  }

  const renderTable = () => (
    <table className="data-table">
      <thead>
        <tr>
          {columns.map(col => (
            <th
              key={col.key}
              className={cn(col.hideOnMobile && 'hide-mobile')}
              style={{ width: col.width, textAlign: col.align || 'start' }}
            >
              {col.label}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {data.map(item => (
          <tr
            key={item[keyField]}
            onClick={onRowClick ? () => onRowClick(item) : undefined}
            style={{ cursor: onRowClick ? 'pointer' : undefined, ...rowStyle?.(item) }}
            className={rowClassName?.(item)}
          >
            {columns.map(col => (
              <td
                key={col.key}
                className={cn(col.hideOnMobile && 'hide-mobile')}
                style={{ textAlign: col.align || 'start' }}
              >
                {col.render ? col.render(item) : item[col.key]}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  )

  return (
    <>
      {dataCardMapping ? (
        <>
          <div className="system-desktop-table">{renderTable()}</div>
          <div className="system-mobile-cards" style={{ display: 'none', flexDirection: 'column', gap: 'var(--space-3)', padding: 'var(--space-4)' }}>
            {data.map(item => (
              <DataCard key={item[keyField]} {...dataCardMapping(item)} />
            ))}
          </div>
        </>
      ) : (
        renderTable()
      )}

      {/* Pagination */}
      {page && totalPages && totalPages > 1 && onPageChange && (
        <div className="pagination" style={{ padding: 'var(--space-4)' }}>
          <span className="pagination-info">
            صفحة {page} من {totalPages}
            {totalCount != null && ` (${totalCount})`}
          </span>
          <div className="pagination-buttons">
            <button
              className="pagination-btn"
              disabled={page <= 1}
              onClick={() => onPageChange(page - 1)}
            >
              ‹
            </button>
            {Array.from({ length: Math.min(totalPages, 5) }, (_, i) => {
              const num = page <= 3 ? i + 1 : page + i - 2
              if (num < 1 || num > totalPages) return null
              return (
                <button
                  key={num}
                  className={cn('pagination-btn', num === page && 'active')}
                  onClick={() => onPageChange(num)}
                >
                  {num}
                </button>
              )
            })}
            <button
              className="pagination-btn"
              disabled={page >= totalPages}
              onClick={() => onPageChange(page + 1)}
            >
              ›
            </button>
          </div>
        </div>
      )}

      <style>{`
        .system-desktop-table { display: block; }
        .system-mobile-cards  { display: none !important; }
        @media (max-width: 768px) {
          .system-desktop-table { display: none; }
          .system-mobile-cards  { display: flex !important; }
        }
      `}</style>
    </>
  )
}
