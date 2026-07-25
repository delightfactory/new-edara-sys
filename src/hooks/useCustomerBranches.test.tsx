import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useCustomerBranches } from './useCustomerBranches'
import { getCustomerBranches } from '@/lib/services/customers'

vi.mock('@/lib/services/customers', () => ({
  getCustomerBranches: vi.fn(),
}))

const mockGetCustomerBranches = vi.mocked(getCustomerBranches)

const createWrapper = () => {
  const qc = new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
      },
    },
  })
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
}

describe('useCustomerBranches hook', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('لا يعيد activeBranches وهمية أو حقول غير موجودة في المخطط', async () => {
    mockGetCustomerBranches.mockResolvedValue([
      { id: 'b1', customer_id: 'c1', name: 'فرع 1', latitude: 30, longitude: 31, address: 'a', is_primary: false, created_at: '', updated_at: '', phone: null, contact_name: null }
    ])

    const { result } = renderHook(() => useCustomerBranches({ customerId: 'c1', enabled: true }), { wrapper: createWrapper() })

    await waitFor(() => expect(result.current.isLoading).toBe(false))

    expect(result.current.branches).toHaveLength(1)
    expect(result.current.branches[0].name).toBe('فرع 1')
    expect(result.current).not.toHaveProperty('activeBranches')
  })

  it('عندما يكون enabled=false لا يتم استدعاء getCustomerBranches', async () => {
    const { result } = renderHook(() => useCustomerBranches({ customerId: 'c1', enabled: false }), { wrapper: createWrapper() })

    expect(mockGetCustomerBranches).not.toHaveBeenCalled()
    expect(result.current.branches).toEqual([])
    expect(result.current.isLoading).toBe(false)
    expect(result.current.isError).toBe(false)
  })

  it('عندما يكون enabled=true يتم الاستدعاء مرة واحدة بمعرف العميل الصحيح وتعود الفروع', async () => {
    const mockBranches = [
      { id: 'b1', customer_id: 'c1', name: 'فرع 1', latitude: 30, longitude: 31, address: 'a', is_primary: false, created_at: '', updated_at: '', phone: null, contact_name: null }
    ]
    mockGetCustomerBranches.mockResolvedValueOnce(mockBranches)

    const { result } = renderHook(() => useCustomerBranches({ customerId: 'c1', enabled: true }), { wrapper: createWrapper() })

    await waitFor(() => expect(result.current.isLoading).toBe(false))

    expect(mockGetCustomerBranches).toHaveBeenCalledTimes(1)
    expect(mockGetCustomerBranches).toHaveBeenCalledWith('c1')
    expect(result.current.branches).toEqual(mockBranches)
    expect(result.current.isError).toBe(false)
  })

  it('عند فشل الخدمة تتحول isError إلى true', async () => {
    mockGetCustomerBranches.mockRejectedValueOnce(new Error('Service failure'))

    const { result } = renderHook(() => useCustomerBranches({ customerId: 'c1', enabled: true }), { wrapper: createWrapper() })

    await waitFor(() => expect(result.current.isLoading).toBe(false))

    expect(result.current.isError).toBe(true)
    expect(result.current.branches).toEqual([])
  })

  it('عندما يكون customerId فارغًا لا يتم استدعاء getCustomerBranches', async () => {
    const { result } = renderHook(() => useCustomerBranches({ customerId: '', enabled: true }), { wrapper: createWrapper() })

    expect(mockGetCustomerBranches).not.toHaveBeenCalled()
    expect(result.current.branches).toEqual([])
    expect(result.current.isLoading).toBe(false)
    expect(result.current.isError).toBe(false)
  })
})
