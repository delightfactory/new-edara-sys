import { render, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import ChartTooltip from './ChartTooltip'

describe('ChartTooltip', () => {
  it('renders the shared RTL informational anatomy while preserving caller row order, color and value direction', () => {
    const { container } = render(
      <ChartTooltip
        label="2026-09-18"
        items={[
          { key: 'receipts', label: 'إيصالات', value: '120 ج.م', color: '#2563eb', valueDirection: 'ltr' },
          { key: 'refunds', label: 'مردودات', value: '20 ج.م', color: '#dc2626', valueDirection: 'ltr' },
          { key: 'net', label: 'صافي', value: '100 ج.م', color: '#16a34a', valueDirection: 'ltr' },
        ]}
      />,
    )

    const tooltip = container.querySelector('.ds-chart-tooltip') as HTMLElement
    expect(tooltip).not.toBeNull()
    expect(tooltip.getAttribute('dir')).toBe('rtl')
    expect(within(tooltip).getByText('2026-09-18').classList.contains('ds-chart-tooltip__label')).toBe(true)

    const rows = Array.from(tooltip.querySelectorAll('.ds-chart-tooltip__row')) as HTMLElement[]
    expect(rows).toHaveLength(3)
    expect(rows.map(row => within(row).getByText(/إيصالات|مردودات|صافي/).textContent)).toEqual(['إيصالات', 'مردودات', 'صافي'])
    expect(rows.map(row => row.style.color)).toEqual(['rgb(37, 99, 235)', 'rgb(220, 38, 38)', 'rgb(22, 163, 74)'])
    expect(rows.map(row => row.querySelector('.ds-chart-tooltip__value')?.getAttribute('dir'))).toEqual(['ltr', 'ltr', 'ltr'])
  })

  it('preserves long Arabic content without introducing interaction or live-region semantics', () => {
    const longLabel = 'اسم سلسلة تحليلي طويل باللغة العربية يجب أن يظل كاملاً وقابلاً للالتفاف داخل مساحة التلميح'
    const longHeading = 'فترة تحليل طويلة جداً مع وصف عربي إضافي'

    const { container } = render(
      <ChartTooltip
        label={longHeading}
        items={[{ key: 'long', label: longLabel, value: '1,234,567 ج.م', valueDirection: 'ltr' }]}
      />,
    )

    const tooltip = container.querySelector('.ds-chart-tooltip') as HTMLElement
    expect(within(tooltip).getByText(longHeading).textContent).toBe(longHeading)
    expect(within(tooltip).getByText(longLabel).textContent).toBe(longLabel)
    expect(tooltip.querySelector('.ds-chart-tooltip__item-label')).not.toBeNull()
    expect(tooltip.querySelector('.ds-chart-tooltip__value')?.getAttribute('dir')).toBe('ltr')
    expect(tooltip.getAttribute('aria-live')).toBeNull()
    expect(tooltip.getAttribute('role')).toBeNull()
    expect(tooltip.querySelector('button, a, input, select, textarea, [tabindex]:not([tabindex="-1"])')).toBeNull()
  })
})
