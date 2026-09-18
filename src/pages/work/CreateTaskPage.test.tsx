import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen } from '@testing-library/react'
import CreateTaskPage from './CreateTaskPage'

const mocks = vi.hoisted(() => ({
  navigate: vi.fn(),
  mutateAsync: vi.fn(),
  toastSuccess: vi.fn(),
  toastError: vi.fn(),
  candidates: [
    { user_id: 'me', full_name: 'المستخدم الحالي', is_self: true },
    { user_id: 'u2', full_name: 'موظف آخر', is_self: false },
  ],
  candidatesLoading: false,
  isPending: false,
}))

vi.mock('react-router-dom', () => ({
  useNavigate: () => mocks.navigate,
}))

vi.mock('sonner', () => ({
  toast: {
    success: mocks.toastSuccess,
    error: mocks.toastError,
  },
}))

vi.mock('@/features/work/runtime-hooks', () => ({
  useAssignmentCandidates: () => ({
    data: mocks.candidates,
    isLoading: mocks.candidatesLoading,
  }),
  useCreateTask: () => ({
    mutateAsync: mocks.mutateAsync,
    isPending: mocks.isPending,
  }),
}))

describe('CreateTaskPage V2 composition', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.candidates = [
      { user_id: 'me', full_name: 'المستخدم الحالي', is_self: true },
      { user_id: 'u2', full_name: 'موظف آخر', is_self: false },
    ]
    mocks.candidatesLoading = false
    mocks.isPending = false
    mocks.mutateAsync.mockResolvedValue({ work_item_id: 'task-1' })
  })

  it('uses shared sections, fields, two-column grids and non-sticky touch-safe actions', () => {
    const { container } = render(<CreateTaskPage />)

    expect(container.querySelectorAll('.ds-form-section')).toHaveLength(4)
    expect(container.querySelectorAll('.ds-form-grid--cols-2')).toHaveLength(3)

    expect(screen.getByText('ما المطلوب بالضبط؟')).not.toBeNull()
    expect(screen.getByText('من المسؤول ومن يمسك الكرة الآن؟')).not.toBeNull()
    expect(screen.getByText('ما الخطوة التالية ومتى؟')).not.toBeNull()
    expect(screen.getByText('أولوية وخصوصية الإجراء')).not.toBeNull()

    const title = screen.getByLabelText(/عنوان المهمة/) as HTMLInputElement
    const outcome = screen.getByLabelText(/النتيجة المتوقعة/) as HTMLTextAreaElement
    const owner = screen.getByLabelText(/المسؤول النهائي/) as HTMLSelectElement
    const assignee = screen.getByLabelText(/المكلف الحالي/) as HTMLSelectElement
    const nextActionAt = screen.getByLabelText(/موعد الإجراء التالي/) as HTMLInputElement
    const dueAt = screen.getByLabelText(/الموعد النهائي/) as HTMLInputElement

    expect(title.required).toBe(false)
    expect(title.getAttribute('aria-required')).toBe('true')
    expect(outcome.getAttribute('aria-required')).toBe('true')
    expect(owner.getAttribute('aria-required')).toBe('true')
    expect(assignee.getAttribute('aria-required')).toBe('true')
    expect(nextActionAt.type).toBe('datetime-local')
    expect(dueAt.type).toBe('datetime-local')

    const outcomeHint = screen.getByText('هذه ليست خطوة تنفيذ؛ هي تعريف واضح للنتيجة النهائية المقبولة.')
    expect(outcome.getAttribute('aria-describedby')).toBe(outcomeHint.id)

    const cancel = screen.getByRole('button', { name: 'إلغاء' })
    const submit = screen.getByRole('button', { name: 'إنشاء وتفعيل المهمة' })
    const actions = submit.closest('.ds-form-actions')

    expect(actions).not.toBeNull()
    expect(actions?.className).not.toContain('sticky')
    expect(cancel.className).toContain('btn-touch')
    expect(submit.className).toContain('btn-touch')

    fireEvent.click(cancel)
    expect(mocks.navigate).toHaveBeenCalledWith('/work')
  })

  it('connects manual validation errors to the shared Field controls without invoking create', () => {
    mocks.candidates = []
    render(<CreateTaskPage />)

    const title = screen.getByLabelText(/عنوان المهمة/) as HTMLInputElement
    const outcome = screen.getByLabelText(/النتيجة المتوقعة/) as HTMLTextAreaElement
    const nextAction = screen.getByLabelText(/الإجراء التالي/) as HTMLInputElement
    const owner = screen.getByLabelText(/المسؤول النهائي/) as HTMLSelectElement
    const assignee = screen.getByLabelText(/المكلف الحالي/) as HTMLSelectElement

    fireEvent.click(screen.getByRole('button', { name: 'إنشاء وتفعيل المهمة' }))

    const titleError = screen.getByText('عنوان المهمة مطلوب')
    const outcomeError = screen.getByText('حدد النتيجة التي تعتبر المهمة مكتملة عند تحقيقها')
    const nextActionError = screen.getByText('حدد أول إجراء عملي بعد إنشاء المهمة')
    const ownerError = screen.getByText('حدد المسؤول النهائي عن النتيجة')
    const assigneeError = screen.getByText('حدد الشخص الذي تقع عنده الكرة الآن')

    expect(title.getAttribute('aria-invalid')).toBe('true')
    expect(title.getAttribute('aria-describedby')).toBe(titleError.id)
    expect(outcome.getAttribute('aria-describedby')).toBe(outcomeError.id)
    expect(nextAction.getAttribute('aria-describedby')).toBe(nextActionError.id)
    expect(owner.getAttribute('aria-describedby')).toBe(ownerError.id)
    expect(assignee.getAttribute('aria-describedby')).toBe(assigneeError.id)
    expect(mocks.mutateAsync).not.toHaveBeenCalled()
  })

  it('preserves the create loading/disabled state on the shared primary action', () => {
    mocks.isPending = true
    render(<CreateTaskPage />)

    const submit = screen.getByRole('button', { name: 'إنشاء وتفعيل المهمة' }) as HTMLButtonElement
    expect(submit.disabled).toBe(true)
    expect(submit.getAttribute('aria-busy')).toBe('true')
  })
})
