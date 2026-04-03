import { describe, it, expect, beforeEach, vi } from 'vitest'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { render, screen } from '@testing-library/react'
import { ProtectedRoute } from '@/components/layout/ProtectedRoute'
import { useAuthStore } from '@/stores/auth-store'

const { mockLoadSession } = vi.hoisted(() => ({
  mockLoadSession: vi.fn(),
}))

vi.mock('@/lib/services/auth', () => ({
  loadSession: mockLoadSession,
}))

describe('ProtectedRoute', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    useAuthStore.getState().reset()
  })

  it('shows a recoverable retry state when a live session exists but profile loading failed', () => {
    useAuthStore.setState({
      isInitialized: true,
      isLoading: false,
      hasSession: true,
      profile: null,
      profileLoadError: 'rpc_error',
    })

    render(
      <MemoryRouter initialEntries={['/secure']}>
        <Routes>
          <Route
            path="/secure"
            element={
              <ProtectedRoute>
                <div>secure-page</div>
              </ProtectedRoute>
            }
          />
          <Route path="/login" element={<div>login-page</div>} />
        </Routes>
      </MemoryRouter>,
    )

    expect(screen.getByText('تعذر تحميل بيانات المستخدم مؤقتاً')).toBeTruthy()
    expect(screen.queryByText('secure-page')).toBeNull()
    expect(screen.queryByText('login-page')).toBeNull()
  })
})
