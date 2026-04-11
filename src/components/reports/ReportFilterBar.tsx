import { Calendar, ChevronDown } from 'lucide-react'
import { useState } from 'react'
import { normalizeDateRange, toLocalISODate } from '@/lib/utils/date'

export interface DateRange {
  from: string
  to: string
}

interface Props {
  value: DateRange
  onChange: (v: DateRange) => void
}

const PRESETS = [
  { label: 'آخر 7 أيام', days: 7 },
  { label: 'آخر 30 يوماً', days: 30 },
  { label: 'آخر 90 يوماً', days: 90 },
  { label: 'هذا الشهر', days: 0, mode: 'current-month' as const },
]

function applyPreset(days: number, mode?: 'current-month') {
  const now = new Date()
  if (mode === 'current-month') {
    const from = new Date(now.getFullYear(), now.getMonth(), 1)
    const to = new Date(now.getFullYear(), now.getMonth() + 1, 0) // last day of month
    return normalizeDateRange(toLocalISODate(from), toLocalISODate(to))
  }
  const from = new Date(now)
  from.setDate(now.getDate() - days + 1)
  return normalizeDateRange(toLocalISODate(from), toLocalISODate(now))
}

export default function ReportFilterBar({ value, onChange }: Props) {
  const [open, setOpen] = useState(false)

  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-3)',
      flexWrap: 'wrap',
    }}>
      {/* Preset buttons */}
      <div style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        {PRESETS.map(p => {
          const range = applyPreset(p.days, p.mode)
          const isActive = range.from === value.from && range.to === value.to
          return (
            <button
              key={p.label}
              onClick={() => { onChange(range); setOpen(false) }}
              style={{
                padding: '5px 12px',
                borderRadius: 'var(--radius-full)',
                fontSize: 'var(--text-xs)',
                fontWeight: isActive ? 700 : 500,
                border: `1px solid ${isActive ? 'var(--color-primary)' : 'var(--border-primary)'}`,
                background: isActive ? 'var(--color-primary-light)' : 'var(--bg-surface)',
                color: isActive ? 'var(--color-primary)' : 'var(--text-secondary)',
                cursor: 'pointer',
                transition: 'all 0.15s',
                fontFamily: 'var(--font-sans)',
              }}
            >
              {p.label}
            </button>
          )
        })}
      </div>

      {/* Custom date inputs */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
        <Calendar size={14} color="var(--text-muted)" />
        <input
          type="date"
          value={value.from}
          onChange={e => onChange(normalizeDateRange(e.target.value, value.to))}
          style={{
            padding: '4px 8px',
            borderRadius: 'var(--radius-sm)',
            border: '1px solid var(--border-primary)',
            background: 'var(--bg-input)',
            color: 'var(--text-primary)',
            fontSize: 'var(--text-xs)',
            fontFamily: 'var(--font-sans)',
            outline: 'none',
          }}
        />
        <span style={{ color: 'var(--text-muted)', fontSize: 'var(--text-xs)' }}>—</span>
        <input
          type="date"
          value={value.to}
          onChange={e => onChange(normalizeDateRange(value.from, e.target.value))}
          style={{
            padding: '4px 8px',
            borderRadius: 'var(--radius-sm)',
            border: '1px solid var(--border-primary)',
            background: 'var(--bg-input)',
            color: 'var(--text-primary)',
            fontSize: 'var(--text-xs)',
            fontFamily: 'var(--font-sans)',
            outline: 'none',
          }}
        />
      </div>
    </div>
  )
}
