import { ReactNode } from 'react'

export interface DetailRowProps {
  /** The descriptive label e.g., 'Date', 'Amount' */
  label: ReactNode
  /** The value content, can be string, number, or a component */
  value: ReactNode
  /** If true, the value is highlighted using primary color and thicker weight */
  highlight?: boolean
  /** Optional icon to display before the label */
  icon?: ReactNode
}

/**
 * A standardized row for displaying label-value pairs in modals and detail cards.
 * Completely respects RTL logical properties.
 */
export default function DetailRow({ label, value, highlight, icon }: DetailRowProps) {
  return (
    <div
      style={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        padding: 'var(--space-2) 0',
        borderBottom: '1px solid var(--border-primary)',
      }}
    >
      <span
        style={{
          fontSize: 'var(--text-sm)',
          color: 'var(--text-muted)',
          display: 'flex',
          alignItems: 'center',
          gap: 'var(--space-2)',
        }}
      >
        {icon && (
          <span style={{ color: 'var(--text-muted)', display: 'flex', alignItems: 'center' }}>
            {icon}
          </span>
        )}
        {label}
      </span>
      <span
        style={{
          fontSize: 'var(--text-sm)',
          fontWeight: highlight ? 700 : 500,
          color: highlight ? 'var(--color-primary)' : 'var(--text-primary)',
          textAlign: 'end', // RTL Logic safely aligns text to the end
        }}
      >
        {value}
      </span>
    </div>
  )
}
