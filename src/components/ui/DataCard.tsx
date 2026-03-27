import { type ReactNode } from 'react'

interface MetadataItem {
  label: string
  value: ReactNode
  /** Highlight value in primary blue color (e.g. for amounts) */
  highlight?: boolean
}

interface DataCardProps {
  /** Primary identifier — order number, customer name, etc. */
  title: ReactNode
  /** Subtitle or secondary info below title */
  subtitle?: ReactNode
  /** Status badge component */
  badge?: ReactNode
  /** Array of key-value metadata rows */
  metadata?: MetadataItem[]
  /** Action buttons, overflow menu, or any ReactNode */
  actions?: ReactNode
  /** Optional icon or avatar to the right of content (RTL = right) */
  leading?: ReactNode
  /** Click handler for the entire card (opens detail page) */
  onClick?: () => void
  className?: string
}

/**
 * DataCard — Mobile-first list item card
 *
 * Designed to replace table rows on mobile screens.
 * Used for: Sales Orders, Customers, Invoices, etc.
 *
 * Usage:
 * ```tsx
 * <DataCard
 *   title="طلب #1045"
 *   subtitle="أحمد محمد"
 *   badge={<span className="badge badge-success">مُسلَّم</span>}
 *   metadata={[
 *     { label: 'التاريخ', value: '27/03/2026' },
 *     { label: 'الإجمالي', value: '2,500 ج.م', highlight: true },
 *   ]}
 *   actions={<button className="btn btn-sm btn-secondary">تفاصيل</button>}
 *   onClick={() => navigate(`/sales/orders/${id}`)}
 * />
 * ```
 */
export default function DataCard({
  title,
  subtitle,
  badge,
  metadata,
  actions,
  leading,
  onClick,
  className = '',
}: DataCardProps) {
  return (
    <article
      className={`data-card ${onClick ? 'data-card--clickable' : ''} ${className}`}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={onClick ? e => e.key === 'Enter' && onClick() : undefined}
    >
      {/* ── Header row ─────────────────────────────────── */}
      <div className="data-card-header">
        {leading && (
          <div className="data-card-leading">
            {leading}
          </div>
        )}

        <div className="data-card-info">
          <div className="data-card-title-row">
            <span className="data-card-title">{title}</span>
            {badge && <span className="data-card-badge">{badge}</span>}
          </div>
          {subtitle && (
            <span className="data-card-subtitle">{subtitle}</span>
          )}
        </div>
      </div>

      {/* ── Metadata grid ───────────────────────────────── */}
      {metadata && metadata.length > 0 && (
        <dl className="data-card-meta">
          {metadata.map((item, i) => (
            <div key={i} className="data-card-meta-item">
              <dt className="data-card-meta-label">{item.label}</dt>
              <dd className={`data-card-meta-value ${item.highlight ? 'data-card-meta-value--highlight' : ''}`}>
                {item.value}
              </dd>
            </div>
          ))}
        </dl>
      )}

      {/* ── Actions ─────────────────────────────────────── */}
      {actions && (
        <div className="data-card-actions" onClick={e => e.stopPropagation()}>
          {actions}
        </div>
      )}

      <style>{`
        .data-card {
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg);
          padding: var(--space-4);
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
          box-shadow: var(--shadow-sm);
          transition: box-shadow var(--transition-base), transform var(--transition-base);
        }

        .data-card--clickable {
          cursor: pointer;
          -webkit-tap-highlight-color: transparent;
        }
        .data-card--clickable:hover {
          box-shadow: var(--shadow-md);
          transform: translateY(-1px);
        }
        .data-card--clickable:active {
          transform: scale(0.99);
        }

        /* ── Header ── */
        .data-card-header {
          display: flex;
          align-items: flex-start;
          gap: var(--space-3);
        }

        .data-card-leading {
          flex-shrink: 0;
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .data-card-info {
          flex: 1;
          min-width: 0;
        }

        .data-card-title-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--space-2);
          flex-wrap: wrap;
        }

        .data-card-title {
          font-size: var(--text-sm);
          font-weight: 700;
          color: var(--text-primary);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .data-card-badge {
          flex-shrink: 0;
        }

        .data-card-subtitle {
          display: block;
          font-size: var(--text-xs);
          color: var(--text-secondary);
          margin-top: 2px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        /* ── Metadata ── */
        .data-card-meta {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(100px, 1fr));
          gap: var(--space-2) var(--space-3);
          padding-top: var(--space-2);
          border-top: 1px solid var(--divider);
          margin: 0;
        }

        .data-card-meta-item {
          display: flex;
          flex-direction: column;
          gap: 2px;
        }

        .data-card-meta-label {
          font-size: 0.65rem;
          font-weight: 600;
          color: var(--text-muted);
          text-transform: uppercase;
          letter-spacing: 0.04em;
        }

        .data-card-meta-value {
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
          font-variant-numeric: tabular-nums;
        }

        .data-card-meta-value--highlight {
          color: var(--color-primary);
        }

        /* ── Actions ── */
        .data-card-actions {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          padding-top: var(--space-2);
          border-top: 1px solid var(--divider);
          flex-wrap: wrap;
        }

        .data-card-actions .btn {
          min-height: var(--touch-target);
          flex: 1;
          justify-content: center;
        }
      `}</style>
    </article>
  )
}
