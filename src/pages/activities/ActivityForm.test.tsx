import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import ActivityForm from './ActivityForm'
import { supabase } from '@/lib/supabase/client'
import { useSearchParams } from 'react-router-dom'

// Mock react-query hooks
vi.mock('@/hooks/useQueryHooks', () => ({
  useActivityTypes: () => ({
    data: [
      { id: 'type-visit', name: 'زيارة مخططة', category: 'visit', requires_customer: true },
      { id: 'type-call', name: 'اتصال مبيعات', category: 'call', requires_customer: true }
    ],
    isLoading: false
  }),
  useCreateActivity: () => ({
    mutate: vi.fn((payload, options) => {
      options?.onSuccess?.({ id: 'act-new' })
    }),
    mutateAsync: vi.fn().mockResolvedValue({ id: 'act-new' })
  }),
  useUpdateActivity: () => ({ mutate: vi.fn() }),
  useActivity: () => ({ data: null, isLoading: false }),
  useSaveCallDetail: () => ({ mutateAsync: vi.fn().mockResolvedValue({}) }),
  useCustomer: () => ({ data: { id: 'cust-123', name: 'عميل 1' }, isLoading: false }),
  useCustomers: () => ({ data: { data: [{ id: 'cust-123', name: 'عميل 1', code: 'C1' }] }, isLoading: false }),
  useActivities: () => ({ data: { data: [] }, isLoading: false }),
  useTargetStatus: () => ({ data: [], isLoading: false })
}))

// Mock navigate and useParams
const mockNavigate = vi.fn()
let mockSearchParamsStore = new URLSearchParams()

vi.mock('react-router-dom', () => ({
  useParams: () => ({ id: undefined }),
  useSearchParams: () => [mockSearchParamsStore, vi.fn()],
  useNavigate: () => mockNavigate
}))

// Mock supabase client
vi.mock('@/lib/supabase/client', () => ({
  supabase: {
    from: vi.fn(() => ({
      select: vi.fn(() => ({
        eq: vi.fn(() => ({
          maybeSingle: vi.fn().mockResolvedValue({ data: { plan_id: 'plan-123' } }),
          in: vi.fn(() => ({
            order: vi.fn(() => ({
              limit: vi.fn().mockResolvedValue({ data: [] })
            }))
          }))
        }))
      }))
    }))
  }
}))

describe('ActivityForm - URL Guards', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockSearchParamsStore = new URLSearchParams()
  })

  it('ActivityForm shows blocker screen when visitPlanItemId is present', async () => {
    mockSearchParamsStore.set('visitPlanItemId', 'item-visit-123')
    
    render(<ActivityForm />)

    // Check that warning message exists
    expect(screen.getByText('تنبيه أمني وصحي للبيانات')).toBeDefined()
    expect(screen.getByText(/تنفيذ زيارات الخطة وتسجيل أنشطتها يتم حصرياً/)).toBeDefined()
    
    // Check that transition button is present
    const redirectBtn = screen.getByRole('button', { name: 'الذهاب إلى خطط الزيارات' })
    expect(redirectBtn).toBeDefined()
    
    // Click go back
    const backBtn = screen.getByRole('button', { name: 'العودة للصفحة السابقة' })
    fireEvent.click(backBtn)
    expect(mockNavigate).toHaveBeenCalledWith(-1)
  })

  it('ActivityForm renders normal form and allows creation when callPlanItemId is present', async () => {
    mockSearchParamsStore.set('callPlanItemId', 'item-call-123')
    mockSearchParamsStore.set('customerId', 'cust-123')

    render(<ActivityForm />)

    // Form title should be loaded, form select elements should be visible
    expect(screen.getByText('نوع النشاط')).toBeDefined()
    expect(screen.queryByText('تنبيه أمني وصحي للبيانات')).toBeNull()
  })

  it('ActivityForm renders normal form and allows creation for normal independent activities', async () => {
    // No search parameters
    render(<ActivityForm />)

    expect(screen.getByText('نوع النشاط')).toBeDefined()
    expect(screen.queryByText('تنبيه أمني وصحي للبيانات')).toBeNull()
  })
})
