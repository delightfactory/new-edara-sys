import { fireEvent, render, screen } from '@testing-library/react'
import { useState } from 'react'
import { describe, expect, it } from 'vitest'
import CustomerDetailTabs, { type CustomerDetailTab } from './CustomerDetailTabs'

function Harness({ canViewCredit = true }: { canViewCredit?: boolean }) {
  const [value, setValue] = useState<CustomerDetailTab>('info')

  return (
    <CustomerDetailTabs
      value={value}
      onValueChange={setValue}
      counts={{ branches: 2, contacts: 3, credit: 1 }}
      canViewCredit={canViewCredit}
      infoPanel={<div>لوحة البيانات الأساسية</div>}
      branchesPanel={<div>لوحة الفروع</div>}
      contactsPanel={<div>لوحة جهات الاتصال</div>}
      creditPanel={<div>لوحة سجل الائتمان</div>}
    />
  )
}

describe('CustomerDetailTabs', () => {
  it('composes the Customer sections on top of the complete shared Tabs contract', () => {
    render(<Harness />)

    const info = screen.getByRole('tab', { name: 'البيانات الأساسية' })
    const branches = screen.getByRole('tab', { name: /الفروع/ })

    expect(info.getAttribute('aria-selected')).toBe('true')
    expect(screen.getByRole('tabpanel').textContent).toBe('لوحة البيانات الأساسية')
    expect(screen.getByLabelText('عدد الفروع: 2')).not.toBeNull()

    fireEvent.click(branches)

    expect(branches.getAttribute('aria-selected')).toBe('true')
    expect(screen.getByRole('tabpanel').textContent).toBe('لوحة الفروع')
  })

  it('preserves the credit section permission boundary', () => {
    render(<Harness canViewCredit={false} />)

    expect(screen.queryByRole('tab', { name: /سجل الائتمان/ })).toBeNull()
    expect(screen.queryByText('لوحة سجل الائتمان')).toBeNull()
  })

  it('inherits RTL-aware keyboard navigation from shared Tabs', () => {
    document.documentElement.dir = 'rtl'
    render(<Harness />)

    const info = screen.getByRole('tab', { name: 'البيانات الأساسية' })
    const branches = screen.getByRole('tab', { name: /الفروع/ })

    fireEvent.click(branches)
    branches.focus()
    fireEvent.keyDown(branches, { key: 'ArrowRight' })

    expect(info.getAttribute('aria-selected')).toBe('true')
    expect(document.activeElement).toBe(info)

    document.documentElement.dir = ''
  })
})
