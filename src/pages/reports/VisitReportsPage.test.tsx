import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen, waitFor } from '@testing-library/react'
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

const visitRow = {
  visit_item_id: 'item-1',
  plan_id: 'plan-1',
  plan_date: '2026-07-28',
  plan_status: 'completed',
  branch_id: 'branch-1',
  branch_name: 'الفرع الرئيسي',
  employee_id: 'employee-1',
  employee_name: 'أحمد',
  sequence: 1,
  customer_id: 'customer-1',
  customer_code: 'CUS-001',
  customer_name: 'عميل الاختبار',
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
  contact_result: 'تمت مقابلة المسؤول',
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

describe('VisitReportsPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(getVisitReportSummary).mockResolvedValue(summary)
    vi.mocked(getVisitReportRows).mockResolvedValue({ data: [visitRow], count: 1, totalPages: 1 })
    vi.mocked(getVisitSurveyReportAnswers).mockResolvedValue([{
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
    }])
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

  it('opens the visit register with drill-down links', async () => {
    const user = userEvent.setup()
    renderPage()

    await user.click(screen.getByRole('tab', { name: /سجل الزيارات/ }))
    expect(await screen.findByText('عميل الاختبار')).toBeTruthy()
    expect(screen.getByRole('link', { name: 'الخطة' }).getAttribute('href')).toBe('/activities/visit-plans/plan-1')
    expect(screen.getByRole('link', { name: 'النشاط' }).getAttribute('href')).toBe('/activities/activity-1')
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
