import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import SidebarV2 from './SidebarV2'

const authState = vi.hoisted(() => ({
  profile: {
    full_name: 'Ahmed Salama',
    roles: [{ name_ar: 'مدير' }],
  },
  can: (_permission: string) => true,
  canAny: (_permissions: string[]) => true,
}))

const uiState = vi.hoisted(() => ({
  theme: 'light' as 'light' | 'dark',
  sidebarOpen: true,
  setSidebarOpen: vi.fn(),
  toggleTheme: vi.fn(),
}))

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: (selector: (state: typeof authState) => unknown) => selector(authState),
}))

vi.mock('@/stores/notification-store', () => ({
  useNotificationStore: (selector: (state: { unreadCount: number }) => unknown) => selector({ unreadCount: 7 }),
}))

vi.mock('@/stores/ui-store', () => ({
  useUiStore: (selector?: (state: typeof uiState) => unknown) =>
    selector ? selector(uiState) : uiState,
}))

vi.mock('@/lib/services/auth', () => ({
  signOut: vi.fn(),
}))

describe('SidebarV2', () => {
  it('auto-expands the group that owns the current route and keeps unread context', async () => {
    render(
      <MemoryRouter initialEntries={['/sales/orders']}>
        <SidebarV2 />
      </MemoryRouter>,
    )

    const salesTrigger = screen.getByRole('button', { name: 'المبيعات' })
    await waitFor(() => expect(salesTrigger.getAttribute('aria-expanded')).toBe('true'))
    expect(screen.getByRole('link', { name: 'طلبات البيع' })).toBeTruthy()
    expect(screen.getByLabelText('7 إشعار غير مقروء')).toBeTruthy()
  })

  it('closes the drawer after navigation on tablet/mobile widths', () => {
    Object.defineProperty(window, 'innerWidth', {
      configurable: true,
      writable: true,
      value: 900,
    })
    uiState.setSidebarOpen.mockClear()

    render(
      <MemoryRouter initialEntries={['/']}>
        <SidebarV2 />
      </MemoryRouter>,
    )

    fireEvent.click(screen.getByRole('link', { name: 'الموردون' }))
    expect(uiState.setSidebarOpen).toHaveBeenCalledWith(false)
  })
})
