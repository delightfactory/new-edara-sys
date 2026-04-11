import React from 'react'
import { Info } from 'lucide-react'

interface EstimatedAllocationBadgeProps {
  isEstimated: boolean
}

export default function EstimatedAllocationBadge({ isEstimated }: EstimatedAllocationBadgeProps) {
  if (!isEstimated) return null

  return (
    <span 
      className="edara-badge"
      title="هذا التوزيع مبني على أساس تقديري (مثل: نسب عدد الموظفين) وليس بناءً على قيد مالي مباشر للحصة. القيم تقريبية."
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: '4px',
        backgroundColor: 'var(--color-warning-light)',
        color: 'var(--color-warning-dark)',
        padding: '2px 8px',
        borderRadius: '12px',
        fontSize: '11px',
        fontWeight: 600,
        cursor: 'help'
      }}
    >
      <Info size={12} />
      تقديري
    </span>
  )
}
