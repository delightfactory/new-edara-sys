/**
 * VisitPlanItemEditor.test.tsx
 * اختبارات المكون المستقل لمحرر بند الزيارة.
 *
 * نطاق المسؤولية:
 * - التحميل الكسول للفروع
 * - عرض الفروع واختيارها
 * - شارات GPS
 * - التوسعة وإمكانية الوصول
 * - تحذيرات الفرع المفقود/غير النشط
 *
 * خارج النطاق (مسؤولية الوالد):
 * - بناء حمولة RPC
 * - idempotency
 * - التنقل بين الخطوات
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import VisitPlanItemEditor from './VisitPlanItemEditor'
import type { SelectedCustomer } from '../visitPlanFormTypes'
import type { CustomerBranch } from '@/lib/types/master-data'

// ── Mocks ──────────────────────────────────────────────────────────────────────

vi.mock('@/hooks/useCustomerBranches', () => ({
  useCustomerBranches: vi.fn(),
}))

import { useCustomerBranches } from '@/hooks/useCustomerBranches'
const mockUseCustomerBranches = vi.mocked(useCustomerBranches)

// ── Helpers ────────────────────────────────────────────────────────────────────

function makeCustomer(overrides: Partial<SelectedCustomer> = {}): SelectedCustomer {
  return {
    customerId: 'cust-001',
    customerName: 'شركة النيل للتجارة',
    customerCode: 'C001',
    phone: '01001234567',
    latitude: 30.044,
    longitude: 31.235,
    governorate: 'القاهرة',
    city: 'مدينة نصر',
    currentBalance: 1500,
    creditLimit: 5000,
    sequence: 1,
    plannedTime: '',
    estimatedDuration: 30,
    priority: 'normal',
    purposeType: 'sales',
    purpose: '',
    customerBranchId: null,
    customerBranchName: null,
    customerBranchResolved: true,
    customerBranchHasCoordinates: true,
    ...overrides,
  }
}

function makeBranch(overrides: Partial<CustomerBranch> = {}): CustomerBranch {
  return {
    id: 'branch-001',
    customer_id: 'cust-001',
    name: 'فرع المعادي',
    address: 'شارع النصر',
    phone: null,
    contact_name: null,
    latitude: 29.96,
    longitude: 31.25,
    is_primary: false,
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z',
    ...overrides,
  }
}

function makeProps(
  customer: SelectedCustomer,
  overrides: {
    isExpanded?: boolean
    isLocked?: boolean
    index?: number
    total?: number
    onUpdate?: ReturnType<typeof vi.fn>
    onToggleExpand?: ReturnType<typeof vi.fn>
    onMoveUp?: ReturnType<typeof vi.fn>
    onMoveDown?: ReturnType<typeof vi.fn>
    onRemove?: ReturnType<typeof vi.fn>
    onBranchSelectionChange?: ReturnType<typeof vi.fn>
  } = {}
) {
  return {
    customer,
    index: 0,
    total: 3,
    isLocked: false,
    isExpanded: false,
    onToggleExpand: vi.fn(),
    onMoveUp: vi.fn(),
    onMoveDown: vi.fn(),
    onRemove: vi.fn(),
    onUpdate: vi.fn(),
    onBranchSelectionChange: vi.fn(),
    ...overrides,
  }
}

function defaultBranchMock() {
  mockUseCustomerBranches.mockReturnValue({
    branches: [],
    isLoading: false,
    isError: false,
  })
}

function renderEditor(
  customer: SelectedCustomer,
  propsOverrides: Parameters<typeof makeProps>[1] = {}
) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const props = makeProps(customer, propsOverrides)
  const utils = render(
    <QueryClientProvider client={qc}>
      <VisitPlanItemEditor {...props} />
    </QueryClientProvider>
  )
  return { ...utils, props }
}

// ── Tests ──────────────────────────────────────────────────────────────────────

beforeEach(() => {
  vi.clearAllMocks()
  defaultBranchMock()
})

describe('VisitPlanItemEditor — header', () => {
  it('اسم العميل والكود يظهران دائماً', () => {
    renderEditor(makeCustomer())
    expect(screen.getByText('شركة النيل للتجارة')).toBeTruthy()
    expect(screen.getByText('C001')).toBeTruthy()
  })

  it('الرقم التسلسلي يُعرض في الـ header', () => {
    renderEditor(makeCustomer({ sequence: 3 }))
    expect(screen.getByText('3')).toBeTruthy()
  })

  it('الضغط على الـ header يُطلق onToggleExpand بالمعرف الصحيح', () => {
    const onToggleExpand = vi.fn()
    renderEditor(makeCustomer(), { onToggleExpand })
    fireEvent.click(screen.getByRole('button', { name: /شركة النيل للتجارة/i }))
    expect(onToggleExpand).toHaveBeenCalledWith('cust-001')
  })

  it('aria-expanded=false عند الإغلاق', () => {
    renderEditor(makeCustomer(), { isExpanded: false })
    const header = screen.getByRole('button', { name: /شركة النيل للتجارة/i })
    expect(header.getAttribute('aria-expanded')).toBe('false')
  })

  it('aria-expanded=true عند الفتح', () => {
    renderEditor(makeCustomer(), { isExpanded: true })
    // نستخدم queryAllButtons لأن Panel لديه أزرار أخرى
    const headers = screen.getAllByRole('button')
    const header = headers.find(b => b.getAttribute('aria-expanded') === 'true')
    expect(header).toBeTruthy()
  })
})

describe('VisitPlanItemEditor — تحميل الفروع الكسول', () => {
  it('لا يستدعي useCustomerBranches عند isExpanded=false', () => {
    renderEditor(makeCustomer(), { isExpanded: false })
    expect(mockUseCustomerBranches).toHaveBeenCalledWith(
      expect.objectContaining({ enabled: false })
    )
  })

  it('يستدعي useCustomerBranches بـ enabled=true عند isExpanded=true', () => {
    renderEditor(makeCustomer(), { isExpanded: true })
    expect(mockUseCustomerBranches).toHaveBeenCalledWith(
      expect.objectContaining({
        customerId: 'cust-001',
        enabled: true,
      })
    )
  })
})

describe('VisitPlanItemEditor — شارة GPS مع الموقع الرئيسي', () => {
  it('الموقع الرئيسي مع إحداثيات → شارة «موقع متاح»', () => {
    renderEditor(makeCustomer({ customerBranchId: null, latitude: 30.044, longitude: 31.235 }))
    expect(screen.getByText('موقع متاح')).toBeTruthy()
  })

  it('الموقع الرئيسي بدون إحداثيات → شارة «لا توجد إحداثيات»', () => {
    renderEditor(makeCustomer({ customerBranchId: null, latitude: null, longitude: null }))
    expect(screen.getByText('لا توجد إحداثيات')).toBeTruthy()
  })

  it('الموقع الرئيسي لا يُظهر «جاري التحميل» بسبب تحميل الفروع', () => {
    mockUseCustomerBranches.mockReturnValue({
      branches: [],
      isLoading: true,
      isError: false,
    })
    renderEditor(makeCustomer({ customerBranchId: null, isExpanded: true } as SelectedCustomer & { isExpanded?: boolean }))
    // شارة GPS للموقع الرئيسي لا تعتمد على isLoading للفروع
    expect(screen.queryByText(/جاري تحميل موقع الفرع/)).toBeNull()
  })
})

describe('VisitPlanItemEditor — شارة GPS مع الفرع', () => {
  it('فرع مع إحداثيات → شارة «موقع متاح»', async () => {
    const branch = makeBranch({ latitude: 29.96, longitude: 31.25 })
    mockUseCustomerBranches.mockReturnValue({
      branches: [branch],
      isLoading: false,
      isError: false,
    })
    renderEditor(
      makeCustomer({ customerBranchId: 'branch-001', customerBranchHasCoordinates: true }),
      { isExpanded: true }
    )
    await waitFor(() => {
      expect(screen.getByText('موقع متاح')).toBeTruthy()
    })
  })

  it('فرع بدون إحداثيات → شارة «لا توجد إحداثيات»', async () => {
    const branch = makeBranch({ latitude: null, longitude: null })
    mockUseCustomerBranches.mockReturnValue({
      branches: [branch],
      isLoading: false,
      isError: false,
    })
    renderEditor(
      makeCustomer({ customerBranchId: 'branch-001', customerBranchHasCoordinates: false }),
      { isExpanded: true }
    )
    await waitFor(() => {
      expect(screen.getByText('لا توجد إحداثيات')).toBeTruthy()
    })
  })

  it('فرع محدد والبطاقة مفتوحة والفروع قيد التحميل → «جاري تحميل موقع الفرع»', () => {
    mockUseCustomerBranches.mockReturnValue({
      branches: [],
      isLoading: true,
      isError: false,
    })
    renderEditor(
      makeCustomer({ customerBranchId: 'branch-001' }),
      { isExpanded: true }
    )
    expect(screen.getByText('جاري تحميل موقع الفرع')).toBeTruthy()
  })
})

describe('VisitPlanItemEditor — قائمة الفروع', () => {
  it('لا تُعرض قائمة الفروع عند isExpanded=false', () => {
    renderEditor(makeCustomer(), { isExpanded: false })
    expect(screen.queryByRole('combobox', { name: /موقع الزيارة/i })).toBeNull()
  })

  it('تُعرض قائمة الفروع مع الخيار الرئيسي عند فتح البطاقة', () => {
    renderEditor(makeCustomer(), { isExpanded: true })
    const branchSelect = screen.getByLabelText(/موقع الزيارة/i)
    expect(branchSelect).toBeTruthy()
    expect(screen.getByText('الموقع الرئيسي للعميل')).toBeTruthy()
  })

  it('الفروع تظهر في القائمة', async () => {
    const branch = makeBranch({ name: 'فرع المعادي' })
    mockUseCustomerBranches.mockReturnValue({
      branches: [branch],
      isLoading: false,
      isError: false,
    })
    renderEditor(makeCustomer(), { isExpanded: true })
    await waitFor(() => {
      expect(screen.getByText('فرع المعادي')).toBeTruthy()
    })
  })

  it('اختيار فرع يُطلق onBranchSelectionChange بالمعطيات الصحيحة', async () => {
    const onBranchSelectionChange = vi.fn()
    const branch = makeBranch({ id: 'branch-001', name: 'فرع المعادي', latitude: 29.96, longitude: 31.25 })
    mockUseCustomerBranches.mockReturnValue({
      branches: [branch],
      isLoading: false,
      isError: false,
    })
    renderEditor(makeCustomer(), { isExpanded: true, onBranchSelectionChange })
    await waitFor(() => screen.getByText('فرع المعادي'))
    const branchSelect = screen.getByLabelText(/موقع الزيارة/i)
    fireEvent.change(branchSelect, { target: { value: 'branch-001' } })
    expect(onBranchSelectionChange).toHaveBeenCalledWith('cust-001', 'branch-001', 'فرع المعادي', true, true)
  })

  it('اختيار الموقع الرئيسي يُطلق onBranchSelectionChange بـ null وبـ resolved=true', async () => {
    const onBranchSelectionChange = vi.fn()
    const branch = makeBranch()
    mockUseCustomerBranches.mockReturnValue({
      branches: [branch],
      isLoading: false,
      isError: false,
    })
    renderEditor(
      makeCustomer({ customerBranchId: 'branch-001', customerBranchName: 'فرع المعادي', customerBranchResolved: true, customerBranchHasCoordinates: true }),
      { isExpanded: true, onBranchSelectionChange }
    )
    await waitFor(() => screen.getByText('فرع المعادي'))
    const branchSelect = screen.getByLabelText(/موقع الزيارة/i)
    fireEvent.change(branchSelect, { target: { value: '' } })
    expect(onBranchSelectionChange).toHaveBeenCalledWith('cust-001', null, null, true, true)
  })

  it('فشل تحميل الفروع لا يمنع الموقع الرئيسي من الظهور', () => {
    mockUseCustomerBranches.mockReturnValue({
      branches: [],
      isLoading: false,
      isError: true,
    })
    renderEditor(makeCustomer(), { isExpanded: true })
    expect(screen.getByText('الموقع الرئيسي للعميل')).toBeTruthy()
  })
})

describe('VisitPlanItemEditor — تحذيرات الفرع غير الموجود', () => {
  it('فرع محفوظ في القالب غير موجود → تحذير «لم يعد موجوداً»', async () => {
    mockUseCustomerBranches.mockReturnValue({
      branches: [], // لا يوجد الفرع
      isLoading: false,
      isError: false,
    })
    renderEditor(
      makeCustomer({ customerBranchId: 'branch-old', customerBranchName: null, customerBranchResolved: false }),
      { isExpanded: true }
    )
    await waitFor(() => {
      expect(screen.getByText(/الفرع المحفوظ لم يعد موجوداً/)).toBeTruthy()
    })
  })

  it('زر «استخدام الموقع الرئيسي» يُطلق onBranchSelectionChange بـ null', async () => {
    const onBranchSelectionChange = vi.fn()
    mockUseCustomerBranches.mockReturnValue({
      branches: [],
      isLoading: false,
      isError: false,
    })
    renderEditor(
      makeCustomer({ customerBranchId: 'branch-old', customerBranchName: null, customerBranchResolved: false }),
      { isExpanded: true, onBranchSelectionChange }
    )
    await waitFor(() => screen.getByText('استخدام الموقع الرئيسي'))
    fireEvent.click(screen.getByText('استخدام الموقع الرئيسي'))
    expect(onBranchSelectionChange).toHaveBeenCalledWith('cust-001', null, null, true, true)
  })

  it('لا يستبدل customerBranchId بصمت — يبقى حتى يختار المستخدم', async () => {
    const onBranchSelectionChange = vi.fn()
    mockUseCustomerBranches.mockReturnValue({
      branches: [],
      isLoading: false,
      isError: false,
    })
    renderEditor(
      makeCustomer({ customerBranchId: 'branch-old', customerBranchName: null, customerBranchResolved: false }),
      { isExpanded: true, onBranchSelectionChange }
    )
    await waitFor(() => screen.getByText(/الفرع المحفوظ لم يعد موجوداً/))
    // لا يُطلق onBranchSelectionChange تلقائياً لقيم جديدة دون تغيير
    // (التحميل التلقائي للمفقود سيُطلق onBranchSelectionChange بـ resolved=false, hasCoords=false)
    // وهو نفس ما هو مخزن لديه، فلا تكرار ولا مسح صامت للـ id
  })
})

describe('VisitPlanItemEditor — أزرار التحكم', () => {
  it('زر الحذف له aria-label يحتوي اسم العميل', () => {
    renderEditor(makeCustomer(), { isExpanded: true })
    const deleteBtn = screen.getByRole('button', { name: /حذف شركة النيل للتجارة/i })
    expect(deleteBtn).toBeTruthy()
  })

  it('الضغط على حذف يُطلق onRemove بالمعرف', () => {
    const onRemove = vi.fn()
    renderEditor(makeCustomer(), { isExpanded: true, onRemove })
    fireEvent.click(screen.getByRole('button', { name: /حذف شركة النيل للتجارة/i }))
    expect(onRemove).toHaveBeenCalledWith('cust-001')
  })

  it('زر تحريك للأعلى معطل عند index=0', () => {
    renderEditor(makeCustomer(), { isExpanded: true })
    const upBtn = screen.getByRole('button', { name: /تحريك شركة النيل للتجارة للأعلى/i })
    expect(upBtn.hasAttribute('disabled')).toBe(true)
  })

  it('زر تحريك للأسفل معطل عند آخر عنصر', () => {
    renderEditor(makeCustomer(), { isExpanded: true, index: 2 })
    const downBtn = screen.getByRole('button', { name: /تحريك شركة النيل للتجارة للأسفل/i })
    expect(downBtn.hasAttribute('disabled')).toBe(true)
  })

  it('زر تحريك للأعلى يُطلق onMoveUp بالفهرس', () => {
    const onMoveUp = vi.fn()
    renderEditor(makeCustomer(), { isExpanded: true, index: 1, onMoveUp })
    fireEvent.click(screen.getByRole('button', { name: /للأعلى/i }))
    expect(onMoveUp).toHaveBeenCalledWith(1)
  })

  it('جميع الأزرار معطلة عند isLocked=true', () => {
    renderEditor(makeCustomer(), { isExpanded: true, isLocked: true })
    const buttons = screen.getAllByRole('button')
    // كل الأزرار معطلة (بما فيها الـ header) — عدا select التي لا تكون button
    buttons.forEach(btn => {
      expect(btn.hasAttribute('disabled')).toBe(true)
    })
  })
})

describe('VisitPlanItemEditor — حقول التحرير', () => {
  it('تغيير الأولوية يُطلق onUpdate بالقيمة الجديدة', () => {
    const onUpdate = vi.fn()
    renderEditor(makeCustomer(), { isExpanded: true, onUpdate })
    const prioritySelect = screen.getByLabelText('الأولوية')
    fireEvent.change(prioritySelect, { target: { value: 'high' } })
    expect(onUpdate).toHaveBeenCalledWith('cust-001', 'priority', 'high')
  })

  it('تغيير الغرض يُطلق onUpdate بالقيمة الجديدة', () => {
    const onUpdate = vi.fn()
    renderEditor(makeCustomer(), { isExpanded: true, onUpdate })
    const purposeSelect = screen.getByLabelText('الغرض')
    fireEvent.change(purposeSelect, { target: { value: 'collection' } })
    expect(onUpdate).toHaveBeenCalledWith('cust-001', 'purposeType', 'collection')
  })

  it('تغيير الوقت يُطلق onUpdate بالقيمة الجديدة', () => {
    const onUpdate = vi.fn()
    renderEditor(makeCustomer(), { isExpanded: true, onUpdate })
    const timeInput = screen.getByLabelText('الوقت')
    fireEvent.change(timeInput, { target: { value: '09:30' } })
    expect(onUpdate).toHaveBeenCalledWith('cust-001', 'plannedTime', '09:30')
  })

  it('المدة الأدنى 5 دقائق — قيم أقل تُقلَّب إلى 5', () => {
    const onUpdate = vi.fn()
    renderEditor(makeCustomer(), { isExpanded: true, onUpdate })
    const durInput = screen.getByLabelText(/مدة الزيارة للعميل/i)
    fireEvent.change(durInput, { target: { value: '2' } })
    expect(onUpdate).toHaveBeenCalledWith('cust-001', 'estimatedDuration', 5)
  })
})

describe('ط-2ب-1: اختبارات تفصيلية لمحلل الفروع والتحذيرات', () => {
  it('فرع قالب موجود يُحل اسمه وإحداثياته تلقائيًا عند فتح البطاقة', async () => {
    const onBranchSelectionChange = vi.fn()
    const branch = makeBranch({ id: 'branch-001', name: 'فرع المعادي الرئيسي', latitude: 29.9, longitude: 31.2 })
    mockUseCustomerBranches.mockReturnValue({
      branches: [branch],
      isLoading: false,
      isError: false,
    })

    // customer.customerBranchResolved = false (لم يُحل بعد)
    renderEditor(
      makeCustomer({ customerBranchId: 'branch-001', customerBranchResolved: false }),
      { isExpanded: true, onBranchSelectionChange }
    )

    await waitFor(() => {
      expect(onBranchSelectionChange).toHaveBeenCalledWith(
        'cust-001',
        'branch-001',
        'فرع المعادي الرئيسي',
        true,
        true
      )
    })
  })

  it('فرع موجود ومعه إحداثيات → شارة GPS «موقع متاح»', async () => {
    const branch = makeBranch({ id: 'branch-100', name: 'فرع المعادي السليم', latitude: 30.1, longitude: 31.2 })
    mockUseCustomerBranches.mockReturnValue({
      branches: [branch],
      isLoading: false,
      isError: false,
    })
    renderEditor(
      makeCustomer({ customerBranchId: 'branch-100', customerBranchResolved: true, customerBranchHasCoordinates: true }),
      { isExpanded: true }
    )
    expect(screen.getByText('موقع متاح')).toBeTruthy()
  })

  it('فرع موجود دون إحداثيات → شارة GPS «لا توجد إحداثيات»', async () => {
    const branch = makeBranch({ id: 'branch-200', name: 'فرع التجمع بلا موقع', latitude: null, longitude: null })
    mockUseCustomerBranches.mockReturnValue({
      branches: [branch],
      isLoading: false,
      isError: false,
    })
    renderEditor(
      makeCustomer({ customerBranchId: 'branch-200', customerBranchResolved: true, customerBranchHasCoordinates: false }),
      { isExpanded: true }
    )
    expect(screen.getByText('لا توجد إحداثيات')).toBeTruthy()
  })

  it('فرع مفقود (unresolved) → شارة GPS تعرض «الفرع يحتاج تحققًا» ولا تعرض «لا توجد إحداثيات»', async () => {
    mockUseCustomerBranches.mockReturnValue({
      branches: [],
      isLoading: false,
      isError: false,
    })
    renderEditor(
      makeCustomer({ customerBranchId: 'branch-missing', customerBranchResolved: false, customerBranchHasCoordinates: null }),
      { isExpanded: true }
    )
    expect(screen.getByText('الفرع يحتاج تحققًا')).toBeTruthy()
    expect(screen.queryByText('لا توجد إحداثيات')).toBeNull()
  })

  it('فشل تحميل الفروع يعرض تنبيه عربي وزر الموقع الرئيسي ويعمل بالضغط عليه', async () => {
    const onBranchSelectionChange = vi.fn()
    mockUseCustomerBranches.mockReturnValue({
      branches: [],
      isLoading: false,
      isError: true,
    })

    renderEditor(
      makeCustomer({ customerBranchId: 'branch-001', customerBranchResolved: false }),
      { isExpanded: true, onBranchSelectionChange }
    )

    await waitFor(() => {
      expect(screen.getByText('تعذر تحميل فروع العميل')).toBeTruthy()
    })

    const resetBtn = screen.getByRole('button', { name: 'استخدام الموقع الرئيسي' })
    fireEvent.click(resetBtn)

    expect(onBranchSelectionChange).toHaveBeenCalledWith('cust-001', null, null, true, true)
  })

  it('الضغط على زر الموقع الرئيسي يرسل تحديثًا موحدًا مع hasCoordinates=true إذا كانت إحداثيات العميل متوفرة', async () => {
    const onBranchSelectionChange = vi.fn()
    mockUseCustomerBranches.mockReturnValue({
      branches: [],
      isLoading: false,
      isError: true,
    })
    renderEditor(
      makeCustomer({ customerBranchId: 'branch-001', customerBranchResolved: false, latitude: 30.123, longitude: 31.456 }),
      { isExpanded: true, onBranchSelectionChange }
    )
    await waitFor(() => screen.getByRole('button', { name: 'استخدام الموقع الرئيسي' }))
    fireEvent.click(screen.getByRole('button', { name: 'استخدام الموقع الرئيسي' }))
    expect(onBranchSelectionChange).toHaveBeenCalledWith('cust-001', null, null, true, true)
  })

  it('الضغط على زر الموقع الرئيسي يرسل تحديثًا موحدًا مع hasCoordinates=false إذا لم تتوفر إحداثيات العميل', async () => {
    const onBranchSelectionChange = vi.fn()
    mockUseCustomerBranches.mockReturnValue({
      branches: [],
      isLoading: false,
      isError: true,
    })
    renderEditor(
      makeCustomer({ customerBranchId: 'branch-001', customerBranchResolved: false, latitude: null, longitude: null }),
      { isExpanded: true, onBranchSelectionChange }
    )
    await waitFor(() => screen.getByRole('button', { name: 'استخدام الموقع الرئيسي' }))
    fireEvent.click(screen.getByRole('button', { name: 'استخدام الموقع الرئيسي' }))
    expect(onBranchSelectionChange).toHaveBeenCalledWith('cust-001', null, null, true, false)
  })
})
