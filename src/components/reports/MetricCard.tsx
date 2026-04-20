import type { TrustStatus } from '@/hooks/useSystemTrustState'
import TrustStateBadge from './TrustStateBadge'
import FreshnessIndicator from './FreshnessIndicator'
import type { ReactNode } from 'react'

interface MetricCardProps {
  label: string
  value: string | number | null
  status: string | null  // accepts raw string from RPC; TrustStateBadge handles type narrowing
  lastCompletedAt?: string | null
  isStale?: boolean
  domain?: 'treasury' | 'sales' | 'ar' | 'customers' | 'profit_overview' | 'branch_profitability' | 'allocation_quality' | 'default'
  subtitle?: string
  icon?: ReactNode
  /** secondary value shown below the main one */
  secondary?: { label: string; value: string }
  trend?: 'up' | 'down' | 'neutral'
  trendLabel?: string
}

function formatNum(v: string | number | null): string {
  if (v === null || v === undefined) return '—'
  if (typeof v === 'string') return v
  return new Intl.NumberFormat('en-US', {
    maximumFractionDigits: 0,
  }).format(v)
}

export default function MetricCard({
  label,
  value,
  status,
  lastCompletedAt,
  isStale = false,
  domain = 'default',
  subtitle,
  icon,
  secondary,
  trend,
  trendLabel,
}: MetricCardProps) {
  const isBlocked = status === 'BLOCKED' || status === 'FAILED'
  const hasWarning = status === 'RECONCILED_WITH_WARNING'
  const isRunning = status === 'RUNNING'

  const trendColor =
    trend === 'up'
      ? 'var(--color-success)'
      : trend === 'down'
      ? 'var(--color-danger)'
      : 'var(--text-muted)'

  return (
    <div
      style={{
        background: 'var(--bg-surface)',
        border: `1px solid ${isBlocked ? 'var(--color-danger-light)' : hasWarning ? 'var(--color-warning-light)' : 'var(--border-primary)'}`,
        borderRadius: 'var(--radius-lg)',
        padding: 'var(--space-5)',
        display: 'flex',
        flexDirection: 'column',
        gap: 'var(--space-3)',
        boxShadow: 'var(--shadow-sm)',
        transition: 'box-shadow 0.2s, transform 0.2s',
        position: 'relative',
        overflow: 'hidden',
      }}
      className="edara-card"
    >
      {/* Accent bar for warning */}
      {hasWarning && (
        <div
          style={{
            position: 'absolute',
            top: 0,
            right: 0,
            left: 0,
            height: '3px',
            background: 'var(--color-warning)',
          }}
        />
      )}
      {isBlocked && (
        <div
          style={{
            position: 'absolute',
            top: 0,
            right: 0,
            left: 0,
            height: '3px',
            background: 'var(--color-danger)',
          }}
        />
      )}

      {/* Header row */}
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 'var(--space-2)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
          {icon && (
            <span style={{
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              width: '32px', height: '32px', borderRadius: '8px',
              background: 'var(--bg-secondary)',
              color: 'var(--color-primary)',
              flexShrink: 0,
            }}>
              {icon}
            </span>
          )}
          <div>
            <div style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', fontWeight: 500 }}>{label}</div>
            {subtitle && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{subtitle}</div>}
          </div>
        </div>
        <TrustStateBadge status={status as import('@/hooks/useSystemTrustState').TrustStatus} domain={domain} size="sm" />
      </div>

      {/* Value */}
      {isBlocked ? (
        <div style={{
          background: 'var(--color-danger-light)',
          borderRadius: 'var(--radius-md)',
          padding: 'var(--space-4)',
          textAlign: 'center',
        }}>
          <div style={{ fontSize: 'var(--text-sm)', fontWeight: 600, color: 'var(--color-danger)' }}>
            الرقم محجوب
          </div>
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginTop: '4px' }}>
            يحتاج إلى اكتمال المطابقة المحاسبية قبل العرض
          </div>
        </div>
      ) : isRunning ? (
        <div style={{ fontSize: 'var(--text-xl)', fontWeight: 700, color: 'var(--text-muted)', letterSpacing: '-0.5px' }}>
          جارٍ التحديث…
        </div>
      ) : (
        <div>
          <div style={{
            fontSize: 'var(--text-3xl)',
            fontWeight: 800,
            color: 'var(--text-primary)',
            lineHeight: 1.1,
            letterSpacing: '-1px',
            direction: 'ltr',
            textAlign: 'right',
          }}>
            {formatNum(value)}
          </div>
          {trend && trendLabel && (
            <div style={{ fontSize: 'var(--text-xs)', color: trendColor, marginTop: '4px', fontWeight: 600 }}>
              {trendLabel}
            </div>
          )}
          {secondary && (
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: '4px' }}>
              {secondary.label}: <span style={{ fontWeight: 600, color: 'var(--text-secondary)', direction: 'ltr', display: 'inline-block' }}>{secondary.value}</span>
            </div>
          )}
        </div>
      )}

      {/* Freshness */}
      {lastCompletedAt !== undefined && (
        <FreshnessIndicator lastCompletedAt={lastCompletedAt ?? null} isStale={isStale} />
      )}
    </div>
  )
}
