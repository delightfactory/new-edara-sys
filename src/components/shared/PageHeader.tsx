import type { ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { ChevronLeft } from 'lucide-react'

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
    <div className="page-header">
      <div className="page-header-info">
        {/* Breadcrumbs */}
        {breadcrumbs && breadcrumbs.length > 0 && (
          <nav style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-1)', marginBottom: 'var(--space-1)', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
            {breadcrumbs.map((crumb, idx) => (
              <span key={idx} style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-1)' }}>
                {idx > 0 && <ChevronLeft size={12} />}
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
            style={{ marginBottom: 'var(--space-2)' }}
          >
            {backLabel}
          </button>
        )}

        <h1 className="page-title">{title}</h1>
        {subtitle && <p className="page-subtitle">{subtitle}</p>}
      </div>
      {actions && <div className="page-actions">{actions}</div>}
    </div>
  )
}
