import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import StatusBadge from './StatusBadge'
import AlertPanel from './AlertPanel'
import StatePanel from './StatePanel'

describe('StatusBadge', () => {
  it('always renders a readable label with a semantic tone', () => {
    render(<StatusBadge tone="warning" label="متأخر" />)

    const badge = screen.getByText('متأخر').closest('.ds-status-badge')
    expect(badge).not.toBeNull()
    expect(badge?.getAttribute('data-tone')).toBe('warning')
    expect(badge?.className).toContain('ds-status-badge--warning')
  })
})

describe('AlertPanel', () => {
  it('keeps static alerts quiet by default', () => {
    render(<AlertPanel tone="warning">رصيد العميل يحتاج مراجعة</AlertPanel>)

    const text = screen.getByText('رصيد العميل يحتاج مراجعة')
    const panel = text.closest('.ds-alert-panel')
    expect(panel?.getAttribute('role')).toBeNull()
    expect(panel?.getAttribute('aria-live')).toBeNull()
  })

  it('supports opt-in live announcements for dynamic danger messages', () => {
    render(<AlertPanel tone="danger" announce>تعذر حفظ العملية</AlertPanel>)

    const panel = screen.getByRole('alert')
    expect(panel.getAttribute('aria-live')).toBe('assertive')
  })
})

describe('StatePanel', () => {
  it('exposes the state kind without owning retry/navigation behavior', () => {
    render(
      <StatePanel
        kind="offline"
        title="لا يوجد اتصال"
        description="سيتم استكمال المزامنة عند عودة الشبكة"
        action={<button type="button">محاولة الآن</button>}
      />,
    )

    const title = screen.getByText('لا يوجد اتصال')
    const panel = title.closest('.ds-state-panel')
    expect(panel?.getAttribute('data-state-kind')).toBe('offline')
    expect(screen.getByRole('button', { name: 'محاولة الآن' })).not.toBeNull()
  })
})
