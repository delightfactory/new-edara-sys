import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Link, MemoryRouter, Route, Routes } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useAuthStore } from '@/stores/auth-store'

const mockGetRoles = vi.fn()
const mockGetUser = vi.fn()
const mockGetUserPermissionContext = vi.fn()
const mockUpdateUserWithAccessAtomic = vi.fn()
const mockUpdateProfile = vi.fn()
const mockToastWarning = vi.fn()

vi.mock('@/lib/services/auth', () => ({ createUser: vi.fn() }))
vi.mock('@/lib/services/users', () => ({
  getRoles: mockGetRoles,
  getUser: mockGetUser,
  getUserPermissionContext: mockGetUserPermissionContext,
  updateUserWithAccessAtomic: mockUpdateUserWithAccessAtomic,
  updateProfile: mockUpdateProfile,
}))
vi.mock('sonner', () => ({
  toast: {
    warning: mockToastWarning,
    success: vi.fn(),
    error: vi.fn(),
  },
}))

const { default: UserFormPage } = await import('./UserFormPage')

describe('UserFormPage permission compatibility', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    useAuthStore.setState({
      profile: { id: 'admin-user' } as never,
      permissions: ['*'],
    })
    mockGetRoles.mockResolvedValue([{
      id: 'role-1',
      name: 'sales_rep',
      name_ar: 'مندوب مبيعات',
      color: '#2563eb',
      is_system: true,
    }])
    mockGetUser.mockResolvedValue({
      id: 'target-user',
      full_name: 'مستخدم حالي',
      email: 'user@example.com',
      phone: '01000000000',
      user_roles: [{ role_id: 'role-1' }],
    })
    mockUpdateUserWithAccessAtomic.mockResolvedValue({ saved_count: 0, changed: false })
  })

  it('keeps basic profile and role editing available when permission context loading fails', async () => {
    mockGetUserPermissionContext.mockRejectedValue(new Error('permission context unavailable'))
    const user = userEvent.setup()

    render(
      <MemoryRouter initialEntries={['/settings/users/target-user/edit']}>
        <Routes>
          <Route path="/settings/users/:id/edit" element={<UserFormPage />} />
          <Route path="/settings/users" element={<div>users list</div>} />
        </Routes>
      </MemoryRouter>,
    )

    expect(await screen.findByDisplayValue('مستخدم حالي')).toBeTruthy()
    expect(mockToastWarning).toHaveBeenCalledOnce()
    expect(screen.queryByText('الصلاحيات الفردية')).toBeNull()

    await user.click(screen.getByRole('button', { name: 'حفظ التعديلات' }))

    await waitFor(() => {
      expect(mockUpdateUserWithAccessAtomic).toHaveBeenCalledWith(
        'target-user',
        { full_name: 'مستخدم حالي', phone: '01000000000' },
        ['role-1'],
        null,
      )
    })
    expect(mockUpdateProfile).not.toHaveBeenCalled()
  })

  it('does not block the established form while permission context is still loading', async () => {
    let resolveContext!: (value: {
      inherited_permissions: string[]
      has_wildcard: boolean
      role_permissions_by_role: Record<string, string[]>
      overrides: never[]
    }) => void
    mockGetUserPermissionContext.mockReturnValue(new Promise(resolve => {
      resolveContext = resolve
    }))

    render(
      <MemoryRouter initialEntries={['/settings/users/target-user/edit']}>
        <Routes>
          <Route path="/settings/users/:id/edit" element={<UserFormPage />} />
        </Routes>
      </MemoryRouter>,
    )

    expect(await screen.findByDisplayValue('مستخدم حالي')).toBeTruthy()
    expect(screen.queryByText('الصلاحيات الفردية')).toBeNull()

    await act(async () => {
      resolveContext({
        inherited_permissions: [],
        has_wildcard: false,
        role_permissions_by_role: { 'role-1': [] },
        overrides: [],
      })
    })

    expect(await screen.findByText('الصلاحيات الفردية')).toBeTruthy()
  })

  it('clears permission state before loading a different user route', async () => {
    let resolveSecondContext!: (value: {
      inherited_permissions: string[]
      has_wildcard: boolean
      role_permissions_by_role: Record<string, string[]>
      overrides: never[]
    }) => void
    mockGetUser.mockImplementation(async (userId: string) => ({
      id: userId,
      full_name: userId === 'target-user' ? 'المستخدم الأول' : 'المستخدم الثاني',
      email: `${userId}@example.com`,
      phone: null,
      user_roles: [{ role_id: 'role-1' }],
    }))
    mockGetUserPermissionContext
      .mockResolvedValueOnce({
        inherited_permissions: [],
        has_wildcard: false,
        role_permissions_by_role: { 'role-1': [] },
        overrides: [],
      })
      .mockReturnValueOnce(new Promise(resolve => {
        resolveSecondContext = resolve
      }))
    const user = userEvent.setup()

    render(
      <MemoryRouter initialEntries={['/settings/users/target-user/edit']}>
        <Link to="/settings/users/second-user/edit">المستخدم التالي</Link>
        <Routes>
          <Route path="/settings/users/:id/edit" element={<UserFormPage />} />
        </Routes>
      </MemoryRouter>,
    )

    expect(await screen.findByText('الصلاحيات الفردية')).toBeTruthy()
    await user.click(screen.getByRole('link', { name: 'المستخدم التالي' }))

    expect(await screen.findByDisplayValue('المستخدم الثاني')).toBeTruthy()
    expect(screen.queryByText('الصلاحيات الفردية')).toBeNull()

    await act(async () => {
      resolveSecondContext({
        inherited_permissions: [],
        has_wildcard: false,
        role_permissions_by_role: { 'role-1': [] },
        overrides: [],
      })
    })
  })

  it('preserves unsaved profile edits when refreshed session permissions enable permission management', async () => {
    useAuthStore.setState({ permissions: [] })
    mockGetUserPermissionContext.mockResolvedValue({
      inherited_permissions: [],
      has_wildcard: false,
      role_permissions_by_role: { 'role-1': [] },
      overrides: [],
    })
    const user = userEvent.setup()

    render(
      <MemoryRouter initialEntries={['/settings/users/target-user/edit']}>
        <Routes>
          <Route path="/settings/users/:id/edit" element={<UserFormPage />} />
        </Routes>
      </MemoryRouter>,
    )

    const nameInput = await screen.findByDisplayValue('مستخدم حالي')
    await user.clear(nameInput)
    await user.type(nameInput, 'اسم غير محفوظ')

    act(() => {
      useAuthStore.setState({ permissions: ['*'] })
    })

    expect(await screen.findByText('الصلاحيات الفردية')).toBeTruthy()
    expect(screen.getByDisplayValue('اسم غير محفوظ')).toBeTruthy()
    expect(mockGetUser).toHaveBeenCalledOnce()
    expect(mockGetRoles).toHaveBeenCalledOnce()
  })
})
