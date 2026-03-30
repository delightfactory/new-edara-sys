import type { Target, TargetProgress, TargetTrend } from '@/lib/types/activities'
import ActivityStatusBadge from './ActivityStatusBadge'

interface TargetProgressWidgetProps {
  target: Target
  progress?: TargetProgress | null
  onClick?: () => void
  compact?: boolean
}

const TREND_ICON: Record<TargetTrend, string> = {
  on_track:  '→',
  at_risk:   '↘',
  behind:    '↓',
  achieved:  '✓',
  exceeded:  '↑',
}

const TREND_BAR_COLOR: Record<TargetTrend, string> = {
  on_track:  'var(--color-success)',
  at_risk:   'var(--color-warning)',
  behind:    'var(--color-danger)',
  achieved:  'var(--color-success)',
  exceeded:  '#8b5cf6',
}

function fmtNumber(n: number, unit?: string): string {
  if (unit === 'currency') return `${n.toLocaleString('ar-EG')} ج`
  if (unit === 'percent')  return `${n.toFixed(1)}%`
  return n.toLocaleString('ar-EG')
}

export default function TargetProgressWidget({
  target,
  progress,
  onClick,
  compact = false,
}: TargetProgressWidgetProps) {
  const unit      = target.target_type?.unit ?? 'count'
  const achieved  = progress?.achieved_value ?? 0
  const pct       = Math.min(progress?.achievement_pct ?? 0, 120)
  const trend     = progress?.trend ?? 'behind'
  const remaining = Math.max(target.target_value - achieved, 0)
  const barColor  = TREND_BAR_COLOR[trend]

  return (
    <div
      className={`tpw${compact ? ' tpw--compact' : ''}${onClick ? ' tpw--clickable' : ''}`}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={onClick ? e => e.key === 'Enter' && onClick() : undefined}
    >
      <div className="tpw-header">
        <div className="tpw-meta">
          <span className="tpw-name">{target.name}</span>
          {!compact && target.target_type && (
            <span className="tpw-type">{target.target_type.name}</span>
          )}
        </div>
        <div className="tpw-badges">
          <ActivityStatusBadge trend={trend} size="sm" />
          <span className="tpw-trend-icon">{TREND_ICON[trend]}</span>
        </div>
      </div>

      <div className="tpw-bar-wrap">
        <div
          className="tpw-bar-fill"
          style={{ width: `${Math.min(pct, 100)}%`, background: barColor }}
        />
        {pct > 100 && <div className="tpw-bar-overflow" />}
      </div>

      <div className="tpw-numbers">
        <span className="tpw-achieved">
          {fmtNumber(achieved, unit)}{' '}
          <span className="tpw-pct">({pct.toFixed(0)}%)</span>
        </span>
        <span className="tpw-target">من {fmtNumber(target.target_value, unit)}</span>
      </div>

      {!compact && (
        <div className="tpw-footer">
          <span>المتبقي: {fmtNumber(remaining, unit)}</span>
        </div>
      )}

      <style>{`
        .tpw {
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg);
          padding: var(--space-4);
          display: flex;
          flex-direction: column;
          gap: var(--space-2);
          transition: box-shadow var(--transition-fast), transform var(--transition-fast);
        }
        .tpw--clickable { cursor: pointer; }
        .tpw--clickable:hover {
          box-shadow: var(--shadow-md);
          transform: translateY(-1px);
        }
        .tpw--compact { padding: var(--space-3); }
        .tpw-header {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: var(--space-2);
        }
        .tpw-meta { display: flex; flex-direction: column; gap: 2px; }
        .tpw-name {
          font-size: var(--text-sm);
          font-weight: 700;
          color: var(--text-primary);
        }
        .tpw-type {
          font-size: var(--text-xs);
          color: var(--text-muted);
        }
        .tpw-badges {
          display: flex;
          align-items: center;
          gap: var(--space-1);
          flex-shrink: 0;
        }
        .tpw-trend-icon { font-size: 14px; font-weight: 700; }
        .tpw-bar-wrap {
          height: 8px;
          background: var(--bg-surface-2);
          border-radius: 99px;
          overflow: hidden;
          position: relative;
        }
        .tpw-bar-fill {
          height: 100%;
          border-radius: 99px;
          transition: width 0.6s cubic-bezier(0.4,0,0.2,1);
        }
        .tpw-bar-overflow {
          position: absolute;
          top: 0; right: 0;
          width: 4%;
          height: 100%;
          border-radius: 0 99px 99px 0;
          background: #8b5cf6;
          animation: overflow-pulse 1.5s infinite;
        }
        @keyframes overflow-pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.5; }
        }
        .tpw-numbers {
          display: flex;
          align-items: center;
          justify-content: space-between;
        }
        .tpw-achieved {
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
        }
        .tpw-pct { font-size: var(--text-xs); color: var(--text-muted); font-weight: 400; }
        .tpw-target { font-size: var(--text-xs); color: var(--text-muted); }
        .tpw-footer {
          display: flex;
          justify-content: space-between;
          font-size: var(--text-xs);
          color: var(--text-muted);
          padding-top: var(--space-1);
          border-top: 1px dashed var(--border-primary);
        }
      `}</style>
    </div>
  )
}
