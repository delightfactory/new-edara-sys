import { cn } from '@/lib/utils/helpers'

export interface PaginationProps {
  page: number
  totalPages: number
  onPageChange: (page: number) => void
  disabled?: boolean
  compact?: boolean
  ariaLabel?: string
  className?: string
}

type PageToken = number | 'ellipsis-start' | 'ellipsis-end'

function pageTokens(page: number, totalPages: number): PageToken[] {
  if (totalPages <= 7) {
    return Array.from({ length: totalPages }, (_, index) => index + 1)
  }

  const tokens: PageToken[] = [1]
  const start = Math.max(2, page - 1)
  const end = Math.min(totalPages - 1, page + 1)

  if (start > 2) tokens.push('ellipsis-start')
  for (let current = start; current <= end; current += 1) tokens.push(current)
  if (end < totalPages - 1) tokens.push('ellipsis-end')

  tokens.push(totalPages)
  return tokens
}

/**
 * Pagination — controlled presentation only. The caller owns page state and
 * data fetching so adopting V2 cannot change pagination/query semantics.
 */
export default function Pagination({
  page,
  totalPages,
  onPageChange,
  disabled = false,
  compact = false,
  ariaLabel = 'التنقل بين الصفحات',
  className,
}: PaginationProps) {
  const safeTotal = Math.max(1, totalPages)
  const safePage = Math.min(Math.max(1, page), safeTotal)

  return (
    <nav
      className={cn('ds-pagination', compact && 'ds-pagination--compact', className)}
      aria-label={ariaLabel}
    >
      <button
        type="button"
        className="ds-pagination__button ds-pagination__previous"
        disabled={disabled || safePage <= 1}
        onClick={() => onPageChange(safePage - 1)}
        aria-label="الصفحة السابقة"
      >
        السابق
      </button>

      {!compact && (
        <div className="ds-pagination__pages">
          {pageTokens(safePage, safeTotal).map(token => {
            if (typeof token !== 'number') {
              return (
                <span
                  key={token}
                  className="ds-pagination__ellipsis"
                  aria-hidden="true"
                >
                  …
                </span>
              )
            }

            const current = token === safePage
            return (
              <button
                key={token}
                type="button"
                className={cn(
                  'ds-pagination__button',
                  'ds-pagination__page',
                  current && 'ds-pagination__page--active',
                )}
                disabled={disabled}
                aria-current={current ? 'page' : undefined}
                aria-label={current ? `الصفحة ${token}، الحالية` : `الصفحة ${token}`}
                onClick={() => onPageChange(token)}
              >
                {token}
              </button>
            )
          })}
        </div>
      )}

      {compact && (
        <span className="ds-pagination__summary" aria-live="polite">
          {safePage} / {safeTotal}
        </span>
      )}

      <button
        type="button"
        className="ds-pagination__button ds-pagination__next"
        disabled={disabled || safePage >= safeTotal}
        onClick={() => onPageChange(safePage + 1)}
        aria-label="الصفحة التالية"
      >
        التالي
      </button>
    </nav>
  )
}
