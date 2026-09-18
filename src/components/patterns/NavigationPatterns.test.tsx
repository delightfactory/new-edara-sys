import { fireEvent, render, screen } from '@testing-library/react'
import { useState } from 'react'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it } from 'vitest'
import navigationStyles from '../../styles/design-system-v2-navigation.css?raw'
import SegmentedControl from './SegmentedControl'
import SubNav from './SubNav'
import Tabs from './Tabs'

function TabsHarness({ direction = 'ltr' }: { direction?: 'rtl' | 'ltr' }) {
  const [value, setValue] = useState('summary')

  return (
    <Tabs
      direction={direction}
      value={value}
      onValueChange={setValue}
      ariaLabel="تفاصيل العميل"
      items={[
        { value: 'summary', label: 'الملخص', panel: <div>محتوى الملخص</div> },
        { value: 'credit', label: 'الائتمان', panel: <div>محتوى الائتمان</div> },
        { value: 'disabled', label: 'غير متاح', disabled: true, panel: <div>مخفي</div> },
      ]}
    />
  )
}

describe('Tabs', () => {
  it('uses tab/tabpanel semantics and updates the active panel', () => {
    render(<TabsHarness />)

    const summary = screen.getByRole('tab', { name: 'الملخص' })
    const credit = screen.getByRole('tab', { name: 'الائتمان' })

    expect(summary.getAttribute('aria-selected')).toBe('true')
    expect(screen.getByRole('tabpanel').textContent).toBe('محتوى الملخص')

    fireEvent.click(credit)
    expect(credit.getAttribute('aria-selected')).toBe('true')
    expect(screen.getByRole('tabpanel').textContent).toBe('محتوى الائتمان')
  })

  it('moves horizontal arrow navigation according to RTL direction', () => {
    render(<TabsHarness direction="rtl" />)

    const summary = screen.getByRole('tab', { name: 'الملخص' })
    fireEvent.click(screen.getByRole('tab', { name: 'الائتمان' }))
    const credit = screen.getByRole('tab', { name: 'الائتمان' })
    credit.focus()

    fireEvent.keyDown(credit, { key: 'ArrowRight' })

    expect(summary.getAttribute('aria-selected')).toBe('true')
    expect(document.activeElement).toBe(summary)
  })
})

describe('SubNav', () => {
  it('keeps route navigation as real link semantics', () => {
    render(
      <MemoryRouter initialEntries={['/reports/sales']}>
        <SubNav
          ariaLabel="تقارير المبيعات"
          items={[
            { to: '/reports/overview', label: 'نظرة عامة' },
            { to: '/reports/sales', label: 'المبيعات' },
            { to: '/reports/locked', label: 'مقفل', disabled: true },
          ]}
        />
      </MemoryRouter>,
    )

    const sales = screen.getByRole('link', { name: 'المبيعات' })
    expect(sales.className).toContain('ds-subnav__item--active')
    expect(screen.getByText('مقفل').closest('[aria-disabled="true"]')).not.toBeNull()
    expect(screen.queryByRole('link', { name: 'مقفل' })).toBeNull()
  })
})

describe('SegmentedControl', () => {
  it('represents selection with aria-pressed instead of tab semantics', () => {
    function Harness() {
      const [value, setValue] = useState('cards')
      return (
        <SegmentedControl
          value={value}
          onValueChange={setValue}
          ariaLabel="طريقة العرض"
          items={[
            { value: 'cards', label: 'بطاقات' },
            { value: 'table', label: 'جدول' },
          ]}
        />
      )
    }

    render(<Harness />)
    const table = screen.getByRole('button', { name: 'جدول' })
    expect(table.getAttribute('aria-pressed')).toBe('false')

    fireEvent.click(table)
    expect(table.getAttribute('aria-pressed')).toBe('true')
    expect(screen.queryByRole('tab')).toBeNull()
  })

  it('keeps default items intrinsic while block mode retains equal-width stretching', () => {
    const defaultItemRule = navigationStyles.match(/\.ds-segmented-control__item\s*\{([^}]*)\}/)?.[1]
    const blockItemRule = navigationStyles.match(/\.ds-segmented-control--block\s+\.ds-segmented-control__item\s*\{([^}]*)\}/)?.[1]
    const mobileRule = navigationStyles.match(/@media \(max-width: 768px\)\s*\{([\s\S]*?)\n\}/)?.[1]

    expect(defaultItemRule).toContain('flex: 0 0 auto;')
    expect(blockItemRule).toContain('flex: 1 1 0;')
    expect(mobileRule).toMatch(/\.ds-segmented-control\s*\{[^}]*overflow-x:\s*auto;/)
  })
})
