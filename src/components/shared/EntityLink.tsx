import type { CSSProperties, MouseEvent, ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { ExternalLink } from 'lucide-react'

type EntityLinkProps = {
  to?: string | null
  children?: ReactNode
  fallback?: ReactNode
  code?: ReactNode
  title?: string
  className?: string
  style?: CSSProperties
  stopPropagation?: boolean
  showIcon?: boolean
  muted?: boolean
  mono?: boolean
  block?: boolean
}

export function EntityLink({
  to,
  children,
  fallback = '—',
  code,
  title,
  className,
  style,
  stopPropagation = true,
  showIcon = false,
  muted = false,
  mono = false,
  block = false,
}: EntityLinkProps) {
  const content = children || fallback
  const baseStyle: CSSProperties = {
    color: muted ? 'var(--text-secondary)' : 'var(--color-primary)',
    fontWeight: 600,
    textDecoration: 'none',
    display: block ? 'inline-flex' : 'inline-flex',
    flexDirection: code ? 'column' : 'row',
    alignItems: code ? 'flex-start' : 'center',
    gap: code ? 2 : 'var(--space-1)',
    minWidth: 0,
    maxWidth: '100%',
    fontFamily: mono ? 'monospace' : undefined,
    direction: mono ? 'ltr' : undefined,
    ...style,
  }

  const inner = (
    <>
      <span style={{
        overflow: 'hidden',
        textOverflow: 'ellipsis',
        whiteSpace: 'nowrap',
        maxWidth: '100%',
      }}>
        {content}
      </span>
      {code && (
        <span dir="ltr" style={{
          color: 'var(--text-muted)',
          fontFamily: 'monospace',
          fontSize: 'var(--text-xs)',
          fontWeight: 500,
          lineHeight: 1.3,
        }}>
          {code}
        </span>
      )}
      {showIcon && <ExternalLink size={11} aria-hidden="true" />}
    </>
  )

  if (!to) {
    return <span className={className} style={{ ...baseStyle, color: muted ? 'var(--text-muted)' : 'var(--text-primary)' }}>{inner}</span>
  }

  const handleClick = (event: MouseEvent<HTMLAnchorElement>) => {
    if (stopPropagation) event.stopPropagation()
  }

  return (
    <Link
      to={to}
      title={title}
      className={className}
      onClick={handleClick}
      style={baseStyle}
    >
      {inner}
    </Link>
  )
}

type NamedEntityProps = Omit<EntityLinkProps, 'to' | 'children' | 'code'> & {
  id?: string | null
  name?: ReactNode
  code?: ReactNode
}

export function CustomerLink({ id, name, code, ...props }: NamedEntityProps) {
  return <EntityLink to={id ? `/customers/${id}` : null} code={code} {...props}>{name}</EntityLink>
}

export function SupplierLink({ id, name, code, ...props }: NamedEntityProps) {
  return <EntityLink to={id ? `/suppliers/${id}` : null} code={code} {...props}>{name}</EntityLink>
}

export function ProductLink({ id, name, code, ...props }: NamedEntityProps) {
  return <EntityLink to={id ? `/products/${id}` : null} code={code} {...props}>{name}</EntityLink>
}

export function SalesOrderLink({ id, name, code, ...props }: NamedEntityProps) {
  return <EntityLink to={id ? `/sales/orders/${id}` : null} code={code} mono={!code} {...props}>{name}</EntityLink>
}

export function PaymentReceiptLink({ id, name, code, ...props }: NamedEntityProps) {
  return <EntityLink to={id ? `/finance/payments/${id}` : null} code={code} mono={!code} {...props}>{name}</EntityLink>
}

export function EmployeeLink({ id, name, code, ...props }: NamedEntityProps) {
  return <EntityLink to={id ? `/hr/employees/${id}` : null} code={code} {...props}>{name}</EntityLink>
}

type WarehouseLinkProps = Omit<EntityLinkProps, 'to' | 'children' | 'code'> & {
  name?: ReactNode
}

export function WarehouseLink({ name, title = 'عرض المخازن', ...props }: WarehouseLinkProps) {
  return <EntityLink to={name ? '/inventory/warehouses' : null} title={title} muted {...props}>{name}</EntityLink>
}
