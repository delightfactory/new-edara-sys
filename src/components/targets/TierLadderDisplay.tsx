import React from 'react'
import type { TargetRewardTier } from '@/lib/types/activities'

interface TierLadderDisplayProps {
  tiers: TargetRewardTier[]
  currentAchievementPct: number
  estimatedReward?: number | null
  rewardType: 'fixed' | 'percentage' | null
  rewardBaseValue?: number | null
}

export default function TierLadderDisplay({
  tiers,
  currentAchievementPct,
  estimatedReward,
  rewardType,
  rewardBaseValue
}: TierLadderDisplayProps) {
  if (!tiers || tiers.length === 0) return null

  // Sort tiers ascending by sequence
  const sortedTiers = [...tiers].sort((a, b) => a.sequence - b.sequence)

  // Find current tier based on achievement percentage
  let currentTierIndex = -1
  for (let i = sortedTiers.length - 1; i >= 0; i--) {
    if (currentAchievementPct >= sortedTiers[i].threshold_pct) {
      currentTierIndex = i
      break
    }
  }

  return (
    <div style={{
      background: 'var(--bg-surface)',
      border: '1px solid var(--border-color)',
      borderRadius: '12px',
      padding: '16px',
      display: 'flex',
      flexDirection: 'column',
      gap: '16px'
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h4 style={{ margin: 0, fontSize: '15px', fontWeight: 600, color: 'var(--text-primary)' }}>
          سلم المكافآت
        </h4>
        {estimatedReward != null && (
          <span style={{
            color: 'var(--color-success)',
            fontWeight: 700,
            fontSize: '14px',
            background: 'rgba(16,185,129,0.1)',
            padding: '4px 12px',
            borderRadius: '99px'
          }}>
            المتوقع: {estimatedReward.toLocaleString('en-US', { maximumFractionDigits: 1 })}
          </span>
        )}
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
        {sortedTiers.map((tier, idx) => {
          const isCurrent = idx === currentTierIndex
          const isNext = idx === currentTierIndex + 1
          const isPassed = idx < currentTierIndex

          let statusColor = 'var(--text-muted)'
          let bg = 'transparent'
          let border = '1px solid var(--border-color)'

          if (isCurrent) {
            statusColor = 'var(--color-primary)'
            bg = 'var(--bg-primary-light)'
            border = '1px solid var(--color-primary)'
          } else if (isPassed) {
            statusColor = 'var(--color-success)'
            bg = 'rgba(16,185,129,0.05)'
            border = '1px solid rgba(16,185,129,0.2)'
          }

          // Compute displayed reward
          let tierValueStr = ''
          if (rewardType === 'fixed') {
            const val = ((rewardBaseValue || 0) * tier.reward_pct) / 100
            tierValueStr = val.toLocaleString('en-US', { maximumFractionDigits: 1 })
          } else if (rewardType === 'percentage') {
            tierValueStr = `${tier.reward_pct.toLocaleString('en-US', { maximumFractionDigits: 1 })}%`
          }

          return (
            <div key={tier.id} style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '10px 14px',
              borderRadius: '8px',
              background: bg,
              border
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                <div style={{
                  width: '24px', height: '24px', borderRadius: '50%',
                  background: isPassed ? 'var(--color-success)' : isCurrent ? 'var(--color-primary)' : 'var(--bg-body)',
                  color: isPassed || isCurrent ? '#fff' : 'var(--text-muted)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: '12px', fontWeight: 'bold'
                }}>
                  {idx + 1}
                </div>
                <div>
                  <div style={{ fontWeight: isCurrent ? 700 : 500, color: isCurrent || isPassed ? 'var(--text-primary)' : 'var(--text-secondary)' }}>
                    {tier.label || `شريحة ${idx + 1}`}
                  </div>
                  <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '4px' }}>
                    إنجاز: <strong style={{ color: 'var(--text-secondary)' }}>{tier.threshold_pct.toLocaleString('en-US', { maximumFractionDigits: 1 })}%</strong>
                  </div>
                </div>
              </div>

              <div style={{ textAlign: 'left' }}>
                <div style={{ fontWeight: 700, color: statusColor, fontSize: '14px' }}>
                  {tierValueStr}
                </div>
                {isNext && (
                  <div style={{ fontSize: '11px', color: 'var(--color-warning)', marginTop: '4px' }}>
                    باقي {(tier.threshold_pct - currentAchievementPct).toLocaleString('en-US', { maximumFractionDigits: 1 })}% للوصول
                  </div>
                )}
              </div>
            </div>
          )
        })}
      </div>

      {currentTierIndex < sortedTiers.length - 1 && (
        <div style={{
          textAlign: 'center', marginTop: '4px', fontSize: '13px',
          color: 'var(--text-secondary)', background: 'var(--bg-body)',
          padding: '8px', borderRadius: '8px'
        }}>
          🚀 استمر! اقتربت من <strong>{sortedTiers[currentTierIndex + 1]?.label || `شريحة ${currentTierIndex + 2}`}</strong>
        </div>
      )}
    </div>
  )
}
