import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import VisitReportsPage from './VisitReportsPage'
import {
  getVisitReportRows,
  getVisitReportSummary,
  getVisitSurveyReportAnswers,
} from '@/lib/services/visitReports'

vi.mock('@/lib/services/visitReports', () => ({
  getVisitReportSummary: vi.fn(),
  getVisitReportRows: vi.fn(),
  getVisitSurveyReportAnswers: vi.fn(),
  getVisitReportExportRows: vi.fn(),
}))

vi.mock('@/hooks/useQueryHooks', () => ({
  useBranches: () => ({ data: [{ id: 'branch-1', name: 'الفرع الرئيسي' }] }),
  useHREmployees: () => ({ data: { data: [{ id: 'employee-1', full_name: 'أحمد' }] } }),
}))

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: (selector: (state: { can: () => boolean }) => unknown) => selector({ can: () => true }),
}))

const summary = {
  metrics: {
    planned: 58,
    completed: 57,
    field_recorded: 53,
    administrative: 4,
    effective_contacts: 28,
    survey_completed: 52,
    gps_passed: 46,
    gps_pending_review: 8,
    quality_exceptions: 12,
    open_visits: 0,
    average_duration_minutes: 5.4,
    opportunity_value: 479,
    sales_created: 2,
    sales_expected: 9,
    sales_lost: 4,
    activation_followup: 10,
    at_risk_visits: 16,
    very_short_visits: 29,
    unlinked_order_claims: 2,
    actionable_visits: 31,
  },
  contact_results: [{ label: 'تمت مقابلة المسؤول', count: 23 }],
  customer_states: [{ label: 'مستقر', count: 13 }],
  sales_outcomes: [{ label: 'طلب متوقع لاحقاً', count: 9 }],
  activation_outcomes: [{ label: 'مهتم ويحتاج متابعة', count: 10 }],
  daily_results: [],
  purpose_results: [],
  employee_results: [{
    employee_id: 'employee-1',
    employee_name: 'أحمد',
    planned: 58,
    completed: 57,
    field_recorded: 53,
    effective_contacts: 28,
    quality_exceptions: 12,
  }],
}

const longEmployeeName = 'أحمد مندوب مبيعات باسم عربي طويل لاختبار الالتفاف داخل البطاقة'
const longCustomerName = 'عميل اختبار باسم تجاري عربي طويل جداً لاختبار الالتفاف بدون تجاوز أفقي'
const longContactResult = 'تمت مقابلة المسؤول والاتفاق على متابعة تفصيلية طويلة خلال الزيارة القادمة'

const visitRow = {
  visit_item_id: 'item-1',
  plan_id: 'plan-1',
  plan_date: '2026-07-28',
  plan_status: 'completed',
  branch_id: 'branch-1',
  branch_name: 'الفرع الرئيسي',
  employee_id: 'employee-1',
  employee_name: longEmployeeName,
  sequence: 1,
  customer_id: 'customer-1',
  customer_code: 'CUS-001',
  customer_name: longCustomerName,
  purpose_type: 'sales',
  purpose: null,
  priority: 'normal',
  visit_status: 'completed',
  activity_id: 'activity-1',
  started_at: '2026-07-28T08:00:00Z',
  completed_at: '2026-07-28T08:10:00Z',
  duration_minutes: 10,
  gps_validation_status: 'passed',
  gps_review_status: 'not_required',
  is_administrative_completion: false,
  recording_quality: 'recorded',
  response_count: 4,
  contact_result: longContactResult,
  contact_person_name: 'محمد',
  customer_state: 'مستقر',
  visit_summary: 'تم الاتفاق على متابعة',
  sales_order_outcome: 'طلب متوقع لاحقاً',
  sales_no_order_reason: null,
  sales_opportunity_value: 100,
  activation_response: null,
  followup_status: null,
  has_core_survey: true,
  business_outcome: 'طلب متوقع لاحقاً',
  is_effective_contact: true,
  needs_gps_review: false,
  has_quality_exception: false,
}

const surveyAnswer = {
  plan_date: '2026-07-28',
  branch_id: 'branch-1',
  branch_name: 'الفرع الرئيسي',
  employee_id: 'employee-1',
  employee_name: 'أحمد',
  visit_item_id: 'item-1',
  plan_id: 'plan-1',
  customer_id: 'customer-1',
  customer_code: 'CUS-001',
  customer_name: 'عميل الاختبار',
  purpose_type: 'sales',
  activity_id: 'activity-1',
  response_id: 'response-1',
  template_code: 'visit.core',
  template_name: 'نتيجة الزيارة الأساسية',
  template_version: 1,
  question_code: 'contact.result',
  question_text: 'ما نتيجة التواصل أثناء الزيارة؟',
  question_type: 'single_choice',
  answer_value: 'تمت مقابلة المسؤول',
  answer_json: null,
  created_at: '2026-07-28T08:10:00Z',
}

function setViewport(width: number) {
  Object.defineProperty(window, 'innerWidth', {
    configurable: true,
    writable: true,
    value: width,
  })
  act(() => window.dispatchEvent(new Event('resize')))
}

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <VisitReportsPage />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

function getVisitSection(title = 'سجل الزيارات') {
  return screen.getByRole('heading', { name: title }).closest('section') as HTMLElement
}

async function openVisitTab(name: RegExp = /سجل الزيارات/) {
  const user = userEvent.setup()
  await user.click(screen.getByRole('tab', { name }))
  return user
}

describe('VisitReportsPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    setViewport(1440)
    vi.mocked(getVisitReportSummary).mockResolvedValue(summary)
    vi.mocked(getVisitReportRows).mockResolvedValue({ data: [visitRow], count: 1, totalPages: 1 })
    vi.mocked(getVisitSurveyReportAnswers).mockResolvedValue([surveyAnswer])
  })

  it('shows operational and business metrics separately', async () => {
    renderPage()

    expect(await screen.findByText('الزيارات المخططة')).toBeTruthy()
    expect(screen.getByText('لوحة القرار')).toBeTruthy()
    expect(screen.getByText('فرص طلب تحتاج متابعة')).toBeTruthy()
    expect(screen.getByText('ثقة البيانات')).toBeTruthy()
    expect(screen.getByText('المسجلة ميدانيًا')).toBeTruthy()
    expect(screen.getByText('التواصل الفعلي')).toBeTruthy()
    expect(await screen.findByText('تمت مقابلة المسؤول')).toBeTruthy()
  })

  it('preserves the dense Desktop visit table, exact ten-fact order, semantic headers, row anatomy and drill-down destinations', async () => {
    renderPage()
    await openVisitTab()

    const section = getVisitSection()
    const table = await within(section).findByRole('table')
    const headers = within(table).getAllByRole('columnheader')
    expect(headers.map(header => header.textContent)).toEqual([
      'التاريخ',
      'المندوب',
      'العميل',
      'الغرض',
      'الحالة',
      'نتيجة التواصل',
      'المدة',
      'GPS',
      'التسجيل',
      'التفاصيل',
    ])
    headers.forEach(header => expect(header.getAttribute('scope')).toBe('col'))
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()

    const dataRow = within(table).getAllByRole('row')[1]
    const cells = within(dataRow).getAllByRole('cell')
    expect(cells).toHaveLength(10)
    expect(cells[0].getAttribute('dir')).toBe('ltr')
    expect(within(cells[1]).getByText(longEmployeeName)).toBeTruthy()
    expect(within(cells[1]).getByText('الفرع الرئيسي')).toBeTruthy()
    expect(within(cells[2]).getByText(longCustomerName)).toBeTruthy()
    expect(within(cells[2]).getByText('CUS-001').getAttribute('dir')).toBe('ltr')
    expect(cells[3].textContent).toBe('بيع وإعادة طلب')
    expect(within(cells[4]).getByText('مكتملة').className).toContain('visit-report-badge--success')
    expect(cells[5].textContent).toBe(longContactResult)
    expect(within(cells[6]).getByText('10 د').getAttribute('dir')).toBe('ltr')
    expect(within(cells[7]).getByText('GPS مطابق').className).toContain('visit-report-badge--success')
    expect(within(cells[8]).getByText('مسجلة ميدانيًا').className).toContain('visit-report-badge--success')
    expect(within(cells[9]).getByRole('link', { name: 'الخطة' }).getAttribute('href')).toBe('/activities/visit-plans/plan-1')
    expect(within(cells[9]).getByRole('link', { name: 'النشاط' }).getAttribute('href')).toBe('/activities/activity-1')
  })

  it('mounts only one-column Mobile passive cards with all ten facts, safe wrapping, LTR values and touch-sized native links', async () => {
    setViewport(390)
    renderPage()
    await openVisitTab()

    const section = getVisitSection()
    await screen.findByText(longCustomerName)
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-1')).not.toBeNull()

    const card = within(section).getByText(longCustomerName).closest('.ds-card') as HTMLElement
    const labels = Array.from(card.querySelectorAll('dt')).map(label => label.textContent)
    expect(labels).toEqual([
      'التاريخ',
      'المندوب',
      'العميل',
      'الغرض',
      'الحالة',
      'نتيجة التواصل',
      'المدة',
      'GPS',
      'التسجيل',
      'التفاصيل',
    ])
    expect(within(card).getByText(longEmployeeName).parentElement?.style.overflowWrap).toBe('anywhere')
    expect(within(card).getByText(longCustomerName).parentElement?.style.overflowWrap).toBe('anywhere')
    expect(within(card).getByText(longContactResult).style.overflowWrap).toBe('anywhere')
    expect(within(card).getByText('28/07/2026').getAttribute('dir')).toBe('ltr')
    expect(within(card).getByText('CUS-001').getAttribute('dir')).toBe('ltr')
    expect(within(card).getByText('10 د').getAttribute('dir')).toBe('ltr')
    expect(within(card).getByText('مكتملة').className).toContain('visit-report-badge--success')
    expect(within(card).getByText('GPS مطابق').className).toContain('visit-report-badge--success')
    expect(within(card).getByText('مسجلة ميدانيًا').className).toContain('visit-report-badge--success')
    const planLink = within(card).getByRole('link', { name: 'الخطة' })
    const activityLink = within(card).getByRole('link', { name: 'النشاط' })
    expect(planLink.getAttribute('href')).toBe('/activities/visit-plans/plan-1')
    expect(activityLink.getAttribute('href')).toBe('/activities/activity-1')
    expect(planLink.style.minHeight).toBe('44px')
    expect(activityLink.style.minHeight).toBe('44px')
    expect(within(card).queryByRole('button')).toBeNull()
  })

  it('uses deliberate two-column Tablet cards and mounts neither Desktop nor Mobile renderer', async () => {
    setViewport(900)
    renderPage()
    await openVisitTab()

    const section = getVisitSection()
    await screen.findByText(longCustomerName)
    expect(within(section).queryByRole('table')).toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--tablet')).not.toBeNull()
    expect(section.querySelector('.ds-responsive-card-grid--mobile')).toBeNull()
    expect(section.querySelector('.ds-key-value-list--cols-2')).not.toBeNull()
    expect(within(section).getByRole('link', { name: 'الخطة' }).getAttribute('href')).toBe('/activities/visit-plans/plan-1')
    expect(within(section).getByRole('link', { name: 'النشاط' }).getAttribute('href')).toBe('/activities/activity-1')
  })

  it('preserves quality-mode seventh fact, exact exception reasons/fallback, warning semantics and conditional activity link', async () => {
    setViewport(390)
    const qualityRow = {
      ...visitRow,
      visit_item_id: 'item-quality-1',
      customer_id: 'customer-quality-1',
      customer_code: 'CUS-Q01',
      customer_name: 'عميل يحتاج مراجعة',
      activity_id: null,
      gps_validation_status: 'failed_distance',
      is_administrative_completion: true,
      recording_quality: 'administrative',
      has_core_survey: false,
      needs_gps_review: true,
      has_quality_exception: true,
    }
    const fallbackRow = {
      ...visitRow,
      visit_item_id: 'item-quality-2',
      plan_id: 'plan-2',
      activity_id: 'activity-2',
      customer_id: 'customer-quality-2',
      customer_code: 'CUS-Q02',
      customer_name: 'عميل بلا أسباب إضافية',
      has_quality_exception: true,
    }
    vi.mocked(getVisitReportRows).mockResolvedValue({ data: [qualityRow, fallbackRow], count: 2, totalPages: 1 })

    renderPage()
    await openVisitTab(/الاستثناءات/)

    const section = getVisitSection('الزيارات التي تحتاج مراجعة')
    const reasonCard = (await within(section).findByText('عميل يحتاج مراجعة')).closest('.ds-card') as HTMLElement
    expect(Array.from(reasonCard.querySelectorAll('dt')).map(label => label.textContent)[6]).toBe('الاستثناءات')
    expect(within(reasonCard).queryByText('المدة')).toBeNull()
    expect(within(reasonCard).getAllByText('إغلاق إداري')).toHaveLength(2)
    expect(within(reasonCard).getByText('لا يوجد نشاط ميداني')).toBeTruthy()
    expect(within(reasonCard).getByText('الاستبيان الأساسي غير مكتمل')).toBeTruthy()
    expect(within(reasonCard).getByText('GPS ينتظر المراجعة')).toBeTruthy()
    expect(within(reasonCard).getByText('خارج النطاق').className).toContain('visit-report-badge--warning')
    expect(within(reasonCard).getByText('إغلاق إداري', { selector: '.visit-report-badge' }).className).toContain('visit-report-badge--warning')
    expect(within(reasonCard).getByRole('link', { name: 'الخطة' }).getAttribute('href')).toBe('/activities/visit-plans/plan-1')
    expect(within(reasonCard).queryByRole('link', { name: 'النشاط' })).toBeNull()

    const fallbackCard = within(section).getByText('عميل بلا أسباب إضافية').closest('.ds-card') as HTMLElement
    const fallbackItems = fallbackCard.querySelectorAll('.ds-key-value-list__item')
    expect(fallbackItems[6].querySelector('dt')?.textContent).toBe('الاستثناءات')
    expect(fallbackItems[6].querySelector('dd')?.textContent).toBe('—')
    expect(within(fallbackCard).getByRole('link', { name: 'النشاط' }).getAttribute('href')).toBe('/activities/activity-2')
  })

  it('preserves caller-owned loading and error copy without mounting a ready renderer', async () => {
    vi.mocked(getVisitReportRows).mockImplementationOnce(() => new Promise<never>(() => {}))
    const first = renderPage()
    await openVisitTab()
    expect(await screen.findByText('جاري تحميل الزيارات…')).toBeTruthy()
    let section = getVisitSection()
    expect(section.querySelector('.ds-responsive-collection')).toBeNull()
    first.unmount()

    vi.mocked(getVisitReportRows).mockRejectedValueOnce(new Error('boom'))
    renderPage()
    await openVisitTab()
    expect(await screen.findByText('تعذر تحميل سجل الزيارات.')).toBeTruthy()
    section = getVisitSection()
    expect(section.querySelector('.ds-responsive-card-grid')).toBeNull()
  })

  it('preserves exact empty copy and current pagination controls', async () => {
    vi.mocked(getVisitReportRows).mockResolvedValueOnce({ data: [], count: 0, totalPages: 1 })
    const emptyRender = renderPage()
    await openVisitTab()
    const emptySection = getVisitSection()
    expect(await within(emptySection).findByText('لا توجد زيارات مطابقة للفلاتر المحددة.')).toBeTruthy()
    expect(emptySection.querySelector('[data-collection-state="empty"]')).not.toBeNull()
    expect(within(emptySection).queryByRole('table')).toBeNull()
    emptyRender.unmount()

    vi.mocked(getVisitReportRows).mockResolvedValueOnce({ data: [visitRow], count: 26, totalPages: 2 })
    renderPage()
    await openVisitTab()
    const section = getVisitSection()
    await within(section).findByText(longCustomerName)
    expect(within(section).getByText(/صفحة/).textContent).toContain('1 من 2')
    expect((within(section).getByRole('button', { name: 'السابق' }) as HTMLButtonElement).disabled).toBe(true)
    expect((within(section).getByRole('button', { name: 'التالي' }) as HTMLButtonElement).disabled).toBe(false)
  })

  it('loads survey answers only when the survey tab is selected', async () => {
    const user = userEvent.setup()
    renderPage()

    expect(getVisitSurveyReportAnswers).not.toHaveBeenCalled()
    await user.click(screen.getByRole('tab', { name: /الاستبيانات/ }))

    await waitFor(() => expect(getVisitSurveyReportAnswers).toHaveBeenCalledTimes(1))
    expect(await screen.findByText('الإجابات التفصيلية')).toBeTruthy()
    expect(screen.getByText('عميل الاختبار')).toBeTruthy()
  })
})
