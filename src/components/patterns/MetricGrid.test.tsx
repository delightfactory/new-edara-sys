import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import MetricGrid from './MetricGrid'


describe('MetricGrid', () => {
  it('exposes the requested dense Desktop column contract without owning metric meaning', () => {
    const { container } = render(
      <MetricGrid columns={3} aria-label="ملخص الخزائن">
        <div>الرصيد</div>
        <div>النشطة</div>
        <div>الإجمالي</div>
      </MetricGrid>,
    )

    const grid = container.querySelector('[data-metric-grid]')
    expect(grid).not.toBeNull()
    expect(grid?.classList.contains('ds-metric-grid--cols-3')).toBe(true)
    expect(grid?.getAttribute('data-columns')).toBe('3')
    expect(screen.getByLabelText('ملخص الخزائن')).not.toBeNull()
  })
})
