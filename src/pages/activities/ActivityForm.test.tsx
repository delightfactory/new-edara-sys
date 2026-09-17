import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import ActivityForm from './ActivityForm'

vi.mock('@/hooks/useQueryHooks', () => ({
  useActivityTypes: () => ({
    data: [
      { id: 'type-visit', name: 'زيارة مخططة', category: 'visit', requires_customer: true },
      { id: 'type-call', name: 'اتصال مبيعات', category: 'call', requires_customer: true },
    ],
    isLoading: false,
  }),
  useCreateActivity: () => ({
    mutate: vi.fn((payload, options) => {
      options?.onSuccess?.({ id: 'act-new' })
    }),
    mutateAsync: vi.fn().mockResolvedValue({ id: 'act-new' }),
  }),
  useUpdateActivity: () => ({ mutate: vi.fn() }),
  useActivity: () => ({ data: null, isLoading: false }),
  useSaveCallDetail: () => ({ mutateAsync: vi.fn().mockResolvedValue({}) }),
  useCustomer: () => ({ data: { id: 'cust-123', name: 'عميل 1' }, isLoading: false }),
  useCustomers: () => ({ data: { data: [{ id: 'cust-123', name: 'عميل 1', code: 'C1' }] }, isLoading: false }),
  useActivities: () => ({ data: { data: [] }, isLoading: false }),
  useTargetStatus: () => ({ data: [], isLoading: false }),
}))

const mockNavigate = vi.fn()
let mockSearchParamsStore = new URLSearchParams()

vi.mock('react-router-dom', () => ({
  useParams: () => ({ id: undefined }),
  useSearchParams: () => [mockSearchParamsStore, vi.fn()],
  useNavigate: () => mockNavigate,
}))

vi.mock('@/lib/supabase/client', () => ({
  supabase: {
    from: vi.fn(() => ({
      select: vi.fn(() => ({
        eq: vi.fn(() => ({
          maybeSingle: vi.fn().mockResolvedValue({ data: { plan_id: 'plan-123' } }),
          in: vi.fn(() => ({
            order: vi.fn(() => ({
              limit: vi.fn().mockResolvedValue({ data: [] }),
            })),
          })),
        })),
      })),
    })),
  },
}))

describe('ActivityForm - URL Guards', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockSearchParamsStore = new URLSearchParams()
  })

  it('ActivityForm shows blocker screen when visitPlanItemId is present', async () => {
    mockSearchParamsStore.set('visitPlanItemId', 'item-visit-123')

    render(<ActivityForm />)

    expect(screen.getByText('تنبيه أمني وصحي للبيانات')).toBeDefined()
    expect(screen.getByText(/تنفيذ زيارات الخطة وتسجيل أنشطتها يتم حصرياً/)).toBeDefined()

    const redirectBtn = screen.getByRole('button', { name: 'الذهاب إلى خطط الزيارات' })
    expect(redirectBtn).toBeDefined()

    const backBtn = screen.getByRole('button', { name: 'العودة للصفحة السابقة' })
    fireEvent.click(backBtn)
    expect(mockNavigate).toHaveBeenCalledWith(-1)
  })

  it('ActivityForm renders normal form and allows creation when callPlanItemId is present', async () => {
    mockSearchParamsStore.set('callPlanItemId', 'item-call-123')
    mockSearchParamsStore.set('customerId', 'cust-123')

    render(<ActivityForm />)

    expect(screen.getByText('نوع النشاط')).toBeDefined()
    expect(screen.queryByText('تنبيه أمني وصحي للبيانات')).toBeNull()
  })

  it('uses the shared V2 form composition without changing the normal create-state contract', () => {
    render(<ActivityForm />)

    const typeSelect = screen.getByLabelText(/نوع النشاط/) as HTMLSelectElement
    const outcomeSelect = screen.getByLabelText(/نتيجة النشاط/) as HTMLSelectElement
    const dateInput = screen.getByLabelText(/تاريخ النشاط/) as HTMLInputElement
    const cancel = screen.getByRole('button', { name: 'إلغاء' }) as HTMLButtonElement
    const submit = screen.getByRole('button', { name: 'تسجيل النشاط' }) as HTMLButtonElement

    expect(typeSelect.required).toBe(true)
    expect(outcomeSelect.required).toBe(true)
    expect(outcomeSelect.disabled).toBe(true)
    expect(dateInput.required).toBe(true)
    expect(typeSelect.closest('.ds-form-section')).not.toBeNull()
    expect(dateInput.closest('.ds-form-grid--cols-3')).not.toBeNull()
    expect(submit.closest('.ds-form-actions')).not.toBeNull()
    expect(submit.closest('.ds-form-actions')?.className).not.toContain('sticky')
    expect(cancel.className).toContain('btn-touch')
    expect(submit.className).toContain('btn-touch')

    fireEvent.click(cancel)
    expect(mockNavigate).toHaveBeenCalledWith(-1)
  })
})
