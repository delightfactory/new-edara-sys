import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import WorkHubPage from './WorkHubPage'

const mocks = vi.hoisted(() => ({
  navigate: vi.fn(),
  setSearchParams: vi.fn(),
}))

vi.mock('react-router-dom', () => ({
  useNavigate: () => mocks.navigate,
  useSearchParams: () => [new URLSearchParams(), mocks.setSearchParams],
}))

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: (
    selector: (state: { profile: { id: string }; can: (permission: string) => boolean }) => unknown,
  ) => selector({ profile: { id: 'me' }, can: () => false }),
}))

vi.mock('@/features/work/hooks', () => ({
  useVisibleWorkItems: () => ({ data: [], isLoading: false }),
}))

vi.mock('@/features/work/runtime-hooks', () => ({
  useMyActionInbox: () => ({ data: [], isLoading: false }),
  useOperationalFlags: () => ({ data: [] }),
}))

vi.mock('@/features/work/components/WorkItemCard', () => ({
  default: () => null,
}))

vi.mock('./SubmitRequestPanel', () => ({
  default: () => null,
}))

describe('WorkHubPage V2 view-mode selector', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('renders the shared selector with the exact Arabic option order and actions selected by default', () => {
    render(<WorkHubPage />)

    const group = screen.getByRole('group', { name: 'نوع العرض' })
    const buttons = within(group).getAllByRole('button')

    expect(buttons.map(button => button.textContent)).toEqual([
      'مطلوب مني الآن',
      'كل الأعمال',
      'يحتاج انتباه',
    ])
    expect(buttons.map(button => button.getAttribute('aria-pressed'))).toEqual([
      'true',
      'false',
      'false',
    ])
    expect(buttons.every(button => button.getAttribute('type') === 'button')).toBe(true)
    expect(group.className).toContain('ds-segmented-control')
  })

  it('switches all three presentation modes while preserving aria-pressed state ownership', () => {
    render(<WorkHubPage />)

    const group = screen.getByRole('group', { name: 'نوع العرض' })
    const actions = within(group).getByRole('button', { name: 'مطلوب مني الآن' })
    const work = within(group).getByRole('button', { name: 'كل الأعمال' })
    const attention = within(group).getByRole('button', { name: 'يحتاج انتباه' })

    fireEvent.click(work)
    expect(actions.getAttribute('aria-pressed')).toBe('false')
    expect(work.getAttribute('aria-pressed')).toBe('true')
    expect(attention.getAttribute('aria-pressed')).toBe('false')
    expect(screen.getByText('كل الأعمال المتاحة لك')).not.toBeNull()

    fireEvent.click(attention)
    expect(actions.getAttribute('aria-pressed')).toBe('false')
    expect(work.getAttribute('aria-pressed')).toBe('false')
    expect(attention.getAttribute('aria-pressed')).toBe('true')
    expect(screen.getByText('أعمال تحتاج انتباه')).not.toBeNull()

    fireEvent.click(actions)
    expect(actions.getAttribute('aria-pressed')).toBe('true')
    expect(screen.getByText('مرتبة حسب أقرب إجراء يحتاج قرارك أو تنفيذك.')).not.toBeNull()
  })
})
