import { describe, it, expect, beforeEach } from 'vitest'
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom'
import { act, render, screen } from '@testing-library/react'
import { ProtectedRoute } from '@/components/layout/ProtectedRoute'
import { useAuthStore } from '@/stores/auth-store'
import type { MyProfile } from '@/lib/types/auth'

const activeProfile: MyProfile = {
  id: 'synthetic-user',
  full_name: 'مستخدم الاختبار',
  email: null,
  phone: null,
  avatar_url: null,
  status: 'active',
  last_login_at: null,
  created_at: '2026-10-10T00:00:00Z',
  updated_at: '2026-10-10T00:00:00Z',
  roles: [],
  permissions: ['sales.orders.read'],
}

function CurrentPath() {
  return <output aria-label="current-path">{useLocation().pathname}</output>
}

function renderProtectedRoute(permission?: string | string[]) {
  render(
    <MemoryRouter initialEntries={['/secure']}>
      <CurrentPath />
      <Routes>
        <Route path="/secure" element={<ProtectedRoute permission={permission}><div>secure-page</div></ProtectedRoute>} />
        <Route path="/login" element={<div>login-page</div>} />
        <Route path="/unauthorized" element={<div>unauthorized-page</div>} />
      </Routes>
    </MemoryRouter>,
  )
}

function setRecoverableProfileFailure() {
  useAuthStore.setState({
    isInitialized: true,
    isLoading: false,
    hasSession: true,
    profile: null,
    profileLoadError: 'rpc_error',
  })
}

describe('ProtectedRoute', () => {
  beforeEach(() => {
    useAuthStore.getState().reset()
  })

  it('shows a recoverable retry state when a live session exists but profile loading failed', () => {
    setRecoverableProfileFailure()
    renderProtectedRoute()

    expect(screen.getByText('تعذر تحميل بيانات المستخدم مؤقتاً')).toBeTruthy()
    expect(screen.getByRole('button', { name: 'إعادة المحاولة' })).toBeTruthy()
    expect(screen.queryByText('secure-page')).toBeNull()
    expect(screen.queryByText('login-page')).toBeNull()
  })

  // Browser incident 2026-10-10: clearing the profile error at retry start
  // redirected a valid session to login before the successful response arrived.
  // Exercise that public store lifecycle with real routes; the real button/SDK
  // request flow is qualified separately in the synthetic browser harness.
  it.each(['success', 'failure'] as const)(
    'a profile retry stays on the protected URL until %s completes',
    outcome => {
      setRecoverableProfileFailure()
      renderProtectedRoute('sales.orders.read')

      act(() => {
        const store = useAuthStore.getState()
        store.setLoading(true)
        store.setProfileLoadError(null)
      })

      expect(screen.getByLabelText('current-path').textContent).toBe('/secure')
      expect(screen.queryByText('login-page')).toBeNull()
      expect(screen.queryByText('secure-page')).toBeNull()
      expect(screen.queryByRole('button', { name: 'إعادة المحاولة' })).toBeNull()

      act(() => {
        const store = useAuthStore.getState()
        if (outcome === 'success') {
          store.setProfile(activeProfile)
          store.setPermissions(activeProfile.permissions)
        } else {
          store.setProfileLoadError('rpc_error')
        }
        store.setLoading(false)
      })

      expect(screen.getByLabelText('current-path').textContent).toBe('/secure')
      expect(screen.queryByText('login-page')).toBeNull()
      if (outcome === 'success') {
        expect(screen.getByText('secure-page')).toBeTruthy()
        expect(screen.queryByRole('button', { name: 'إعادة المحاولة' })).toBeNull()
      } else {
        expect(screen.getByRole('button', { name: 'إعادة المحاولة' })).toBeTruthy()
        expect(screen.queryByText('secure-page')).toBeNull()
      }
    },
  )

  it('waits on the protected URL during cold initialization without a profile', () => {
    useAuthStore.getState().setLoading(true)
    renderProtectedRoute()

    expect(screen.getByLabelText('current-path').textContent).toBe('/secure')
    expect(screen.queryByText('login-page')).toBeNull()
    expect(screen.queryByText('secure-page')).toBeNull()
  })

  it.each([false, true])('a confirmed sign-out redirects even when loading is %s', isLoading => {
    useAuthStore.setState({ isInitialized: true, isLoading, hasSession: false })
    renderProtectedRoute()

    expect(screen.getByLabelText('current-path').textContent).toBe('/login')
    expect(screen.getByText('login-page')).toBeTruthy()
    expect(screen.queryByText('secure-page')).toBeNull()
  })

  it('keeps cached authorized content visible during background profile loading', () => {
    useAuthStore.setState({
      profile: activeProfile,
      permissions: activeProfile.permissions,
      hasSession: true,
      isInitialized: true,
      isLoading: true,
    })
    renderProtectedRoute('sales.orders.read')

    expect(screen.getByLabelText('current-path').textContent).toBe('/secure')
    expect(screen.getByText('secure-page')).toBeTruthy()
  })

  it.each<{
    scenario: string
    permissions: string[]
    required: string | string[]
    allowed: boolean
  }>([
    { scenario: 'exact grant', permissions: ['sales.orders.read'], required: 'sales.orders.read', allowed: true },
    { scenario: 'denied exact grant', permissions: ['sales.orders.read', '!sales.orders.read'], required: 'sales.orders.read', allowed: false },
    { scenario: 'denied wildcard grant', permissions: ['*', '!sales.orders.read'], required: 'sales.orders.read', allowed: false },
    { scenario: 'OR with one exact grant', permissions: ['customers.read'], required: ['sales.orders.read', 'customers.read'], allowed: true },
    { scenario: 'OR with one unblocked wildcard grant', permissions: ['*', '!sales.orders.read'], required: ['sales.orders.read', 'customers.read'], allowed: true },
    { scenario: 'OR with all wildcard grants denied', permissions: ['*', '!sales.orders.read', '!customers.read'], required: ['sales.orders.read', 'customers.read'], allowed: false },
  ])('preserves route access for $scenario', ({ permissions, required, allowed }) => {
    useAuthStore.setState({
      profile: { ...activeProfile, permissions },
      permissions,
      hasSession: true,
      isInitialized: true,
      isLoading: false,
    })
    renderProtectedRoute(required)

    expect(screen.getByLabelText('current-path').textContent).toBe(allowed ? '/secure' : '/unauthorized')
    expect(screen.getByText(allowed ? 'secure-page' : 'unauthorized-page')).toBeTruthy()
    expect(screen.queryByText('login-page')).toBeNull()
  })
})
