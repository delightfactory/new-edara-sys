import React from 'react'
import { Target, TrendingUp, TrendingDown, Minus, Gift, ChevronRight } from 'lucide-react'
import type { TargetListItem } from '@/lib/types/activities'
import RewardEstimateChip from './RewardEstimateChip'

interface EmployeeTargetCardProps {
  target: TargetListItem
  onClick?: (id: string) => void
}

function fmtN(n: number) {
  return n.toLocaleString('en-US', { maximumFractionDigits: 1 })
}

export default function EmployeeTargetCard({ target, onClick }: EmployeeTargetCardProps) {
  const isPaused = target.is_paused
  const isActive = target.is_active
  const pct      = target.achievement_pct || 0

  // ── Tier info — حقل رسمي في TargetListItem (مُحسَّب عند include_tiers)
  const tierInfo = target.current_tier_info

  const hasReward     = target.has_reward
  const reachedTier   = tierInfo?.reached_tier
  const nextTier      = tierInfo?.next_tier
  const nextThreshold = tierInfo?.next_threshold_pct
  const gapToNext     = nextThreshold != null ? Math.max(0, nextThreshold - pct) : null

  // Progress bar color
  const barColor = pct >= 100
    ? 'var(--color-success)'
    : pct >= 80
    ? 'var(--color-primary)'
    : pct >= 50
    ? '#f59e0b'
    : 'var(--color-danger)'

  return (
    <div
      onClick={() => onClick?.(target.id)}
      style={{
        background: 'var(--bg-surface)',
        border: `1px solid ${isPaused || !isActive ? 'var(--border-color)' : 'var(--border-primary)'}`,
        borderRadius: '14px',
        padding: '18px',
        display: 'flex',
        flexDirection: 'column',
        gap: '14px',
        cursor: onClick ? 'pointer' : 'default',
        transition: 'all 0.2s',
        opacity: isPaused || !isActive ? 0.65 : 1,
        boxShadow: '0 1px 4px rgba(0,0,0,0.04)',
        position: 'relative',
        overflow: 'hidden',
      }}
      onMouseEnter={e => {
        if (onClick) {
          e.currentTarget.style.transform = 'translateY(-3px)'
          e.currentTarget.style.boxShadow = '0 8px 20px rgba(0,0,0,0.08)'
          e.currentTarget.style.borderColor = 'var(--color-primary)'
        }
      }}
      onMouseLeave={e => {
        if (onClick) {
          e.currentTarget.style.transform = 'none'
          e.currentTarget.style.boxShadow = '0 1px 4px rgba(0,0,0,0.04)'
          e.currentTarget.style.borderColor = 'var(--border-primary)'
        }
      }}
    >
      {/* ── Header ─────────────────── */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '8px' }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '4px', flexWrap: 'wrap' }}>
            <h3 style={{ margin: 0, fontSize: '14px', fontWeight: 700, color: 'var(--text-primary)', lineHeight: 1.3 }}>
              {target.name}
            </h3>
            {isPaused && (
              <span style={{ fontSize: '10px', background: 'var(--color-warning-light)', color: 'var(--color-warning)', padding: '2px 7px', borderRadius: '4px', fontWeight: 600 }}>
                موقوف
              </span>
            )}
            {!isActive && (
              <span style={{ fontSize: '10px', background: 'var(--bg-body)', color: 'var(--text-muted)', padding: '2px 7px', borderRadius: '4px' }}>
                منتهٍ
              </span>
            )}
          </div>
          <div style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
            <span>{target.type_name}</span>
            {target.period_end && (
              <>
                <span style={{ color: 'var(--border-color)' }}>•</span>
                <span>ينتهي {new Date(target.period_end).toLocaleDateString('ar-EG-u-nu-latn', { month: 'short', day: 'numeric' })}</span>
              </>
            )}
          </div>
        </div>

        <div style={{
          width: 44, height: 44, borderRadius: '50%',
          background: `${barColor}18`,
          display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
        }}>
          <Target size={20} style={{ color: barColor }} />
        </div>
      </div>

      {/* ── Progress ─────────────────── */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
        {/* values row */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <span style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>
            <strong style={{ color: 'var(--text-primary)', fontSize: '16px' }}>
              {fmtN(target.achieved_value ?? 0)}
            </strong>{' '}
            <span style={{ fontSize: '11px' }}>{target.unit}</span>
          </span>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
            من {fmtN(target.target_value ?? 0)} {target.unit}
          </span>
        </div>

        {/* progress bar */}
        <div style={{ position: 'relative', height: '8px', background: 'var(--bg-body)', borderRadius: '99px', overflow: 'hidden' }}>
          <div style={{
            position: 'absolute', top: 0, right: 0, bottom: 0,
            background: barColor,
            width: `${Math.min(100, pct)}%`,
            borderRadius: '99px',
            transition: 'width 0.6s cubic-bezier(0.4, 0, 0.2, 1)',
          }} />
        </div>

        {/* percentage row */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
            {target.trend === 'on_track' || target.trend === 'achieved' || target.trend === 'exceeded' ? (
              <TrendingUp size={14} color="var(--color-success)" />
            ) : target.trend === 'behind' || target.trend === 'at_risk' ? (
              <TrendingDown size={14} color="var(--color-warning)" />
            ) : (
              <Minus size={14} color="var(--text-muted)" />
            )}
            <span style={{
              fontSize: '13px', fontWeight: 700,
              color: pct >= 100 ? 'var(--color-success)' : pct >= 80 ? 'var(--color-primary)' : pct >= 50 ? '#f59e0b' : 'var(--color-danger)',
            }}>
              {fmtN(pct)}%
            </span>
          </div>
          <RewardEstimateChip
            hasReward={target.has_reward}
            estimatedReward={tierInfo?.estimated_reward ?? target.estimated_reward}
            rewardType={target.reward_type}
            size="sm"
          />
        </div>
      </div>

      {/* ── Tier Layer (motivational) ─────────────────── */}
      {hasReward && tierInfo !== undefined && (
        <div style={{
          padding: '10px 14px',
          background: 'var(--bg-body)',
          borderRadius: '10px',
          display: 'flex',
          flexDirection: 'column',
          gap: '6px',
        }}>
          {reachedTier != null ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <Gift size={13} style={{ color: 'var(--color-success)', flexShrink: 0 }} />
              <span style={{ fontSize: '12px', color: 'var(--color-success)', fontWeight: 700 }}>
                أنت في الشريحة {reachedTier} {tierInfo?.reached_label ? `(${tierInfo.reached_label})` : ''}
              </span>
            </div>
          ) : (
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <Gift size={13} style={{ color: 'var(--text-muted)', flexShrink: 0 }} />
              <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                لم تصل لأي شريحة بعد
              </span>
            </div>
          )}

          {nextTier != null && gapToNext != null && gapToNext > 0 ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <ChevronRight size={13} style={{ color: 'var(--color-primary)', flexShrink: 0 }} />
              <span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                تبقى{' '}
                <strong style={{ color: 'var(--color-primary)' }}>{fmtN(gapToNext)}%</strong>
                {' '}للشريحة {nextTier}
              </span>
              {/* mini gap bar */}
              <div style={{ flex: 1, height: '4px', background: 'var(--border-color)', borderRadius: '99px', overflow: 'hidden', maxWidth: 60 }}>
                <div style={{
                  height: '100%',
                  width: `${Math.min(100, (pct / nextThreshold!) * 100)}%`,
                  background: 'var(--color-primary)',
                  borderRadius: '99px',
                }} />
              </div>
            </div>
          ) : nextTier != null && gapToNext === 0 ? (
            <div style={{ fontSize: '12px', color: 'var(--color-success)', fontWeight: 600 }}>
              🎉 وصلت للشريحة التالية!
            </div>
          ) : null}
        </div>
      )}
    </div>
  )
}
