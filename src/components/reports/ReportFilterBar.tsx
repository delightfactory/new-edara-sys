import { Calendar } from 'lucide-react'
import SegmentedControl from '@/components/patterns/SegmentedControl'
import DateField from '@/components/ui/DateField'
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
  const presets = PRESETS.map(preset => ({
    ...preset,
    range: applyPreset(preset.days, preset.mode),
  }))
  const activePreset = presets.find(preset => (
    preset.range.from === value.from && preset.range.to === value.to
  ))?.label ?? ''

  return (
    <div className="report-filter-bar" style={{
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-3)',
      flexWrap: 'wrap',
      minWidth: 0,
      maxWidth: '100%',
    }}>
      <SegmentedControl
        ariaLabel="اختصارات الفترة"
        value={activePreset}
        items={presets.map(preset => ({ value: preset.label, label: preset.label }))}
        onValueChange={label => {
          const preset = presets.find(item => item.label === label)
          if (preset) onChange(preset.range)
        }}
      />

      <div
        className="report-filter-dates"
        role="group"
        aria-label="الفترة المخصصة"
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 'var(--space-2)',
          flexWrap: 'wrap',
          minWidth: 0,
          maxWidth: '100%',
        }}
      >
        <Calendar size={14} color="var(--text-muted)" aria-hidden="true" />
        <DateField
          aria-label="من تاريخ"
          value={value.from}
          onChange={e => onChange(normalizeDateRange(e.target.value, value.to))}
        />
        <span aria-hidden="true" style={{ color: 'var(--text-muted)', fontSize: 'var(--text-xs)' }}>—</span>
        <DateField
          aria-label="إلى تاريخ"
          value={value.to}
          onChange={e => onChange(normalizeDateRange(value.from, e.target.value))}
        />
      </div>
    </div>
  )
}
