import React from 'react'
import { Target, TrendingUp, TrendingDown, Minus } from 'lucide-react'
import type { TargetListItem } from '@/lib/types/activities'
import RewardEstimateChip from './RewardEstimateChip'

interface EmployeeTargetCardProps {
  target: TargetListItem
  onClick?: (id: string) => void
}

export default function EmployeeTargetCard({ target, onClick }: EmployeeTargetCardProps) {
  const isPaused = target.is_paused
  const isActive = target.is_active

  return (
    <div 
      onClick={() => onClick?.(target.id)}
      style={{
        background: 'var(--bg-surface)',
        border: '1px solid var(--border-color)',
        borderRadius: '12px',
        padding: '16px',
        display: 'flex',
        flexDirection: 'column',
        gap: '16px',
        cursor: onClick ? 'pointer' : 'default',
        transition: 'all 0.2s',
        opacity: isPaused || !isActive ? 0.7 : 1,
        boxShadow: '0 1px 3px rgba(0,0,0,0.02)'
      }}
      onMouseEnter={e => {
        if (onClick) {
          e.currentTarget.style.transform = 'translateY(-2px)'
          e.currentTarget.style.boxShadow = '0 4px 12px rgba(0,0,0,0.05)'
        }
      }}
      onMouseLeave={e => {
        if (onClick) {
          e.currentTarget.style.transform = 'none'
          e.currentTarget.style.boxShadow = '0 1px 3px rgba(0,0,0,0.02)'
        }
      }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '4px' }}>
            <h3 style={{ margin: 0, fontSize: '15px', fontWeight: 600, color: 'var(--text-primary)' }}>
              {target.name}
            </h3>
            {isPaused && (
              <span style={{ fontSize: '11px', background: 'var(--bg-body)', padding: '2px 8px', borderRadius: '4px', color: 'var(--text-muted)' }}>
                متوقف
              </span>
            )}
            {!isActive && (
              <span style={{ fontSize: '11px', background: 'var(--bg-body)', padding: '2px 8px', borderRadius: '4px', color: 'var(--text-muted)' }}>
                ملغي
              </span>
            )}
          </div>
          <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
            {target.type_name} • {target.period_end ? new Date(target.period_end).toLocaleDateString('ar-EG', { month: 'short', day: 'numeric' }) : target.period}
          </div>
        </div>
        
        <div style={{ background: 'var(--bg-body)', padding: '8px', borderRadius: '50%', color: 'var(--color-primary)' }}>
          <Target size={20} />
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <span style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>
            إنجاز: <strong style={{ color: 'var(--text-primary)', fontSize: '15px' }}>{target.achieved_value?.toLocaleString('ar-EG', { maximumFractionDigits: 1 })}</strong> {target.unit}
          </span>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
            من {target.target_value?.toLocaleString('ar-EG', { maximumFractionDigits: 1 })}
          </span>
        </div>

        <div style={{ height: '6px', background: 'var(--bg-body)', borderRadius: '99px', overflow: 'hidden' }}>
          <div style={{ 
            height: '100%', 
            background: target.achievement_pct >= 100 ? 'var(--color-success)' : 'var(--color-primary)', 
            width: `${Math.min(100, target.achievement_pct || 0)}%`,
            borderRadius: '99px',
            transition: 'width 0.5s ease'
          }} />
        </div>
        
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '4px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '12px' }}>
            {target.trend === 'on_track' || target.trend === 'achieved' || target.trend === 'exceeded' ? (
              <TrendingUp size={14} color="var(--color-success)" />
            ) : target.trend === 'behind' || target.trend === 'at_risk' ? (
              <TrendingDown size={14} color="var(--color-warning)" />
            ) : (
              <Minus size={14} color="var(--text-muted)" />
            )}
            <span style={{ 
              color: target.trend === 'on_track' || target.trend === 'achieved' || target.trend === 'exceeded' ? 'var(--color-success)' :
                     target.trend === 'behind' || target.trend === 'at_risk' ? 'var(--color-warning)' : 'var(--text-muted)',
              fontWeight: 500
            }}>
              {target.achievement_pct?.toLocaleString('ar-EG', { maximumFractionDigits: 1 }) || 0}%
            </span>
          </div>

          <RewardEstimateChip 
            hasReward={target.has_reward} 
            estimatedReward={target.estimated_reward} 
            rewardType={target.reward_type}
            size="sm" 
          />
        </div>
      </div>
    </div>
  )
}
