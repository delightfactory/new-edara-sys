import type { ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { ChevronLeft, ArrowRight } from 'lucide-react'

interface Breadcrumb {
  label: string
  path?: string
}

interface PageHeaderProps {
  title: string
  subtitle?: string
  actions?: ReactNode
  breadcrumbs?: Breadcrumb[]
  backPath?: string
  backLabel?: string
}

/**
 * PageHeader — ترويسة صفحة موحدة مع breadcrumbs واختيارياً زر العودة
 * Mobile-first: padding مضغوط، العنوان يقطع بـ ellipsis، الأزرار تبقى accessible
 */
export default function PageHeader({
  title,
  subtitle,
  actions,
  breadcrumbs,
  backPath,
  backLabel = 'رجوع',
}: PageHeaderProps) {
  const navigate = useNavigate()

  return (
    <div className="page-header" style={{ gap: 'var(--space-3)', paddingBottom: 'var(--space-3)' }}>
      <div className="page-header-info" style={{ minWidth: 0, flex: 1 }}>
        {/* Breadcrumbs */}
        {breadcrumbs && breadcrumbs.length > 0 && (
          <nav style={{
            display: 'flex', alignItems: 'center', gap: 'var(--space-1)',
            marginBottom: 'var(--space-1)',
            fontSize: 'var(--text-xs)', color: 'var(--text-muted)',
            flexWrap: 'wrap',
          }}>
            {breadcrumbs.map((crumb, idx) => (
              <span key={idx} style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-1)' }}>
                {idx > 0 && <ChevronLeft size={11} />}
                {crumb.path ? (
                  <button
                    className="btn btn-ghost"
                    style={{ padding: 0, fontSize: 'var(--text-xs)', fontWeight: 400 }}
                    onClick={() => navigate(crumb.path!)}
                  >
                    {crumb.label}
                  </button>
                ) : (
                  <span style={{ color: 'var(--text-secondary)', fontWeight: 500 }}>{crumb.label}</span>
                )}
              </span>
            ))}
          </nav>
        )}

        {/* Back button (if no breadcrumbs) */}
        {!breadcrumbs && backPath && (
          <button
            className="btn btn-ghost btn-sm"
            onClick={() => navigate(backPath)}
            style={{ marginBottom: 'var(--space-2)', gap: 4, display: 'inline-flex', alignItems: 'center' }}
          >
            <ArrowRight size={13} /> {backLabel}
          </button>
        )}

        {/* Title — truncates with ellipsis on very narrow viewports */}
        <h1 className="page-title" style={{
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          maxWidth: '100%',
        }}>{title}</h1>

        {subtitle && (
          <p className="page-subtitle" style={{
            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
            maxWidth: '100%',
          }}>{subtitle}</p>
        )}
      </div>

      {/* Actions — wrap gracefully on narrow screens */}
      {actions && (
        <div className="page-actions" style={{ flexShrink: 0, display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap', alignItems: 'center' }}>
          {actions}
        </div>
      )}
    </div>
  )
}
