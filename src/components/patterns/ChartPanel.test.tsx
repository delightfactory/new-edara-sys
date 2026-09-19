import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import ChartPanel from './ChartPanel'

describe('ChartPanel', () => {
  it('composes the approved Card and SectionHeader contracts without owning chart behavior', () => {
    render(
      <ChartPanel
        title="تطور الإيراد اليومي"
        description="صافي إيراد + قيمة مرتجعات"
        action={<button type="button">تفاصيل الثقة</button>}
      >
        <div data-testid="chart-body">chart-owned content</div>
      </ChartPanel>,
    )

    const heading = screen.getByRole('heading', { level: 3, name: 'تطور الإيراد اليومي' })
    const card = heading.closest('.ds-card')

    expect(card?.className).toContain('ds-chart-panel')
    expect(card?.className).toContain('ds-card--default')
    expect(card?.className).toContain('ds-card--padding-lg')
    expect(screen.getByText('صافي إيراد + قيمة مرتجعات')).not.toBeNull()
    expect(screen.getByRole('button', { name: 'تفاصيل الثقة' })).not.toBeNull()
    expect(screen.getByTestId('chart-body').parentElement?.className).toContain('ds-chart-panel__body')
  })
})
