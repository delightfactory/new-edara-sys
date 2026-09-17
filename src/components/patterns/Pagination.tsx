import { cn } from '@/lib/utils/helpers'
import '@/styles/design-system-v2-pagination.css'

export interface PaginationProps {
  page: number
  totalPages: number
  totalCount?: number
  onPageChange: (page: number) => void
  ariaLabel?: string
  className?: string
}

/**
 * Pagination — shared presentation for paged collections.
 *
 * The caller owns page/query truth. This component preserves the established
 * five-page window and only emits page-change requests within known bounds.
 */
export default function Pagination({
  page,
  totalPages,
  totalCount,
  onPageChange,
  ariaLabel = 'ترقيم صفحات البيانات',
  className,
}: PaginationProps) {
  if (totalPages <= 1) return null

  const pageNumbers = Array.from({ length: Math.min(totalPages, 5) }, (_, index) => {
    const number = page <= 3 ? index + 1 : page + index - 2
    return number >= 1 && number <= totalPages ? number : null
  }).filter((number): number is number => number != null)

  const requestPage = (nextPage: number) => {
    if (nextPage < 1 || nextPage > totalPages) return
    onPageChange(nextPage)
  }

  return (
    <nav
      className={cn('pagination', 'ds-pagination', className)}
      aria-label={ariaLabel}
    >
      <span className="pagination-info">
        صفحة {page} من {totalPages}
        {totalCount != null && ` (${totalCount})`}
      </span>

      <div className="pagination-buttons">
        <button
          type="button"
          className="pagination-btn pagination-btn-nav"
          aria-label="الصفحة السابقة"
          disabled={page <= 1}
          onClick={() => requestPage(page - 1)}
        >
          السابق
        </button>

        {pageNumbers.map(number => (
          <button
            type="button"
            key={number}
            className={cn('pagination-btn', number === page && 'active')}
            aria-label={`الصفحة ${number}`}
            aria-current={number === page ? 'page' : undefined}
            onClick={() => requestPage(number)}
          >
            {number}
          </button>
        ))}

        <button
          type="button"
          className="pagination-btn pagination-btn-nav"
          aria-label="الصفحة التالية"
          disabled={page >= totalPages}
          onClick={() => requestPage(page + 1)}
        >
          التالي
        </button>
      </div>
    </nav>
  )
}
