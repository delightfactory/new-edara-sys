import { ReactNode } from 'react'
import { ArrowLeft } from 'lucide-react'

export interface StatCardProps {
  /** Optional ID for testing/automation */
  id?: string
  /** The main title of the stat */
  label: string
  /** The primary numeric or string value */
  value: string | number
  /** Additional secondary information */
  sub?: ReactNode
  /** Icon component (e.g. from lucide-react) */
  icon: ReactNode
  /** CSS color variable or hex (e.g. 'var(--color-primary)') */
  color: string
  /** Action handler when the card is clicked */
  onClick?: () => void
  /** Loading state skeleton */
  loading?: boolean
}

export default function StatCard({
  id,
  label,
  value,
  sub,
  icon,
  color,
  onClick,
  loading,
}: StatCardProps) {
  const isClickable = typeof onClick === 'function'

  // Extract base color if it's a CSS variable for safe fallback in complex browsers
  // For most modern browsers `color-mix` handles var() perfectly.
  const gradientStr = `linear-gradient(to bottom, ${color}, color-mix(in srgb, ${color} 40%, transparent))`

  return (
    <button
      id={id}
      type="button"
      onClick={onClick}
      disabled={!isClickable}
      className={`edara-card ${isClickable ? 'hoverable-stat-card' : ''}`}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 'var(--space-4)',
        padding: 'var(--space-5)',
        background: 'var(--bg-card)',
        border: `1px solid color-mix(in srgb, ${color} 18%, var(--border-color, var(--border-primary)))`,
        borderRadius: 'var(--radius-xl)',
        cursor: isClickable ? 'pointer' : 'default',
        textAlign: 'start', // RTL Support
        width: '100%',
        transition: 'transform var(--transition-fast), box-shadow var(--transition-fast)',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      {/* Accent stripe on the end (right side in LTR, left side in RTL natively with inset-inline-end) */}
      <div
        style={{
          position: 'absolute',
          top: 0,
          insetInlineEnd: 0, // RTL Logical Property
          width: 4,
          height: '100%',
          background: gradientStr,
        }}
        className="stat-card-stripe"
      />

      {/* Icon Area */}
      <div
        style={{
          width: 48,
          height: 48,
          borderRadius: 'var(--radius-lg)',
          flexShrink: 0,
          background: `color-mix(in srgb, ${color} 12%, transparent)`,
          color,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        {icon}
      </div>

      {/* Content Area */}
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 2 }}>
          {label}
        </div>
        {loading ? (
          <div
            className="skeleton"
            style={{
              height: 24,
              width: 60,
              borderRadius: 6,
              background: 'var(--bg-surface-2)',
              animation: 'pulse 1.5s ease infinite',
            }}
          />
        ) : (
          <div
            style={{
              fontWeight: 800,
              fontSize: 'var(--text-xl)',
              color,
              lineHeight: 1.1,
              fontVariantNumeric: 'tabular-nums',
            }}
          >
            {value}
          </div>
        )}
        {sub && (
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 2 }}>
            {sub}
          </div>
        )}
      </div>

      {/* Action Indicator */}
      {isClickable && (
        <ArrowLeft
          size={14}
          style={{ color: 'var(--text-muted)', flexShrink: 0 }}
          className="stat-card-arrow"
        />
      )}

      {/* Dynamic Hover Styles */}
      <style>{`
        .hoverable-stat-card:hover:not(:disabled) {
          transform: translateY(-2px);
          box-shadow: 0 8px 24px -4px color-mix(in srgb, ${color} 15%, transparent);
        }
        .hoverable-stat-card:active:not(:disabled) {
          transform: translateY(0);
        }
        /* RTL awareness for arrow */
        .stat-card-arrow {
          transition: transform 0.2s;
        }
        html[dir="rtl"] .hoverable-stat-card:hover .stat-card-arrow {
          transform: translateX(-3px);
        }
        html[dir="ltr"] .hoverable-stat-card:hover .stat-card-arrow {
          transform: translateX(3px) scaleX(-1);
        }
      `}</style>
    </button>
  )
}
