import React from 'react'

interface RewardEstimateChipProps {
  hasReward?: boolean
  estimatedReward?: number | null
  rewardType?: 'fixed' | 'percentage' | null
  size?: 'sm' | 'md'
}

export default function RewardEstimateChip({
  hasReward,
  estimatedReward,
  rewardType,
  size = 'md'
}: RewardEstimateChipProps) {
  if (!hasReward) return null

  const pad = size === 'sm' ? '2px 8px' : '4px 12px'
  const fs = size === 'sm' ? '11px' : '13px'

  // If there's a reward, but it's not calculated or not available yet
  if (estimatedReward === null || estimatedReward === undefined) {
    if (rewardType === 'fixed') {
      return (
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: '6px',
          background: 'var(--bg-surface)', border: '1px solid var(--border-color)',
          color: 'var(--text-secondary)', padding: pad, borderRadius: '99px',
          fontSize: fs, fontWeight: 500
        }}>
          🎁 مكافأة مقطوعة
        </span>
      )
    }
    if (rewardType === 'percentage') {
      return (
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: '6px',
          background: 'var(--bg-surface)', border: '1px solid var(--border-color)',
          color: 'var(--text-secondary)', padding: pad, borderRadius: '99px',
          fontSize: fs, fontWeight: 500
        }}>
          🎁 مكافأة بنسبة
        </span>
      )
    }
    return null
  }

  // We have a computed estimated reward
  const isZero = estimatedReward === 0
  const bgColor = isZero ? 'var(--bg-surface)' : 'rgba(16, 185, 129, 0.1)'
  const txColor = isZero ? 'var(--text-muted)' : 'var(--color-success)'
  const bColor = isZero ? 'var(--border-color)' : 'rgba(16, 185, 129, 0.2)'

  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: '6px',
      background: bgColor, border: `1px solid ${bColor}`,
      color: txColor, padding: pad, borderRadius: '99px',
      fontSize: fs, fontWeight: 600, whiteSpace: 'nowrap'
    }} title="المكافأة التقديرية بناءً على الإنجاز الحالي للهدف">
      💰 المتوقع: {estimatedReward ? estimatedReward.toLocaleString('ar-EG', { maximumFractionDigits: 1 }) : '0'} 
    </span>
  )
}
