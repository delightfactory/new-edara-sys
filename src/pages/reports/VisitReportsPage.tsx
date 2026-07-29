import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { toast } from 'sonner'
import {
  AlertTriangle,
  BarChart3,
  CalendarClock,
  CheckCircle2,
  CircleDollarSign,
  ClipboardCheck,
  Download,
  FileWarning,
  MapPinCheck,
  Route,
  ShieldCheck,
  TrendingUp,
  Users,
} from 'lucide-react'
import ReportFilterBar, { type DateRange } from '@/components/reports/ReportFilterBar'
import Button from '@/components/ui/Button'
import { useBranches, useHREmployees } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { toLocalISODate } from '@/lib/utils/date'
import {
  getVisitReportExportRows,
  getVisitReportRows,
  getVisitReportSummary,
  getVisitSurveyReportAnswers,
  type VisitReportBreakdown,
  type VisitReportFilters,
  type VisitReportMetrics,
  type VisitReportRow,
  type VisitSurveyReportAnswer,
} from '@/lib/services/visitReports'
import './VisitReportsPage.css'

type ReportTab = 'overview' | 'visits' | 'surveys' | 'quality'

const PURPOSE_LABELS: Record<string, string> = {
  sales: 'بيع وإعادة طلب',
  collection: 'تحصيل',
  activation: 'تنشيط',
  promotion: 'ترويج',
  followup: 'متابعة',
  service: 'خدمة أو شكوى',
  unspecified: 'غير محدد',
}

const STATUS_LABELS: Record<string, string> = {
  pending: 'مخططة',
  in_progress: 'جارية',
  completed: 'مكتملة',
  skipped: 'متخطاة',
  missed: 'فائتة',
  rescheduled: 'مجدولة لاحقًا',
}

const QUALITY_LABELS: Record<string, string> = {
  recorded: 'مسجلة ميدانيًا',
  administrative: 'إغلاق إداري',
  missing_activity: 'بدون نشاط ميداني',
  open: 'مفتوحة',
  skipped: 'متخطاة',
  missed: 'فائتة',
  rescheduled: 'مجدولة لاحقًا',
}

const GPS_LABELS: Record<string, string> = {
  passed: 'GPS مطابق',
  failed_distance: 'خارج النطاق',
  no_coordinates: 'بدون إحداثيات',
  not_checked: 'غير مفحوص',
}

const numberFormatter = new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 })

function initialDateRange(): DateRange {
  const to = new Date()
  const from = new Date(to)
  from.setDate(to.getDate() - 29)
  return { from: toLocalISODate(from), to: toLocalISODate(to) }
}

function formatNumber(value: number | null | undefined) {
  return value == null ? '—' : numberFormatter.format(value)
}

function formatDate(value: string) {
  return new Date(`${value}T12:00:00`).toLocaleDateString('en-GB')
}

function formatDateTime(value: string | null) {
  if (!value) return '—'
  return new Date(value).toLocaleString('ar-EG-u-nu-latn', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function percentage(value: number, total: number) {
  if (!total) return '0%'
  return `${formatNumber((value / total) * 100)}%`
}

function Metric({
  label,
  value,
  note,
  icon,
}: {
  label: string
  value: string | number
  note: string
  icon: React.ReactNode
}) {
  return (
    <article className="edara-card visit-report-metric">
      <span className="visit-report-metric-icon">{icon}</span>
      <div className="visit-report-metric-label">{label}</div>
      <div className="visit-report-metric-value">{value}</div>
      <div className="visit-report-metric-note">{note}</div>
    </article>
  )
}

function DecisionCard({
  label,
  value,
  note,
  tone,
  icon,
}: {
  label: string
  value: string
  note: string
  tone: 'success' | 'warning' | 'danger' | 'info'
  icon: React.ReactNode
}) {
  return (
    <article className={`visit-decision-card visit-decision-card--${tone}`}>
      <span className="visit-decision-card-icon">{icon}</span>
      <div>
        <p>{label}</p>
        <strong dir="ltr">{value}</strong>
        <span>{note}</span>
      </div>
    </article>
  )
}

function VisitFunnel({ metrics }: { metrics: VisitReportMetrics }) {
  const stages = [
    { label: 'مخططة', value: metrics.planned },
    { label: 'مكتملة', value: metrics.completed },
    { label: 'مسجلة ميدانيًا', value: metrics.field_recorded },
    { label: 'تواصل فعلي', value: metrics.effective_contacts },
  ]
  const base = Math.max(metrics.planned, 1)
  return (
    <div className="visit-decision-funnel">
      {stages.map((stage, index) => (
        <div className="visit-decision-funnel-stage" key={stage.label}>
          <div className="visit-decision-funnel-copy">
            <span>{stage.label}</span>
            <strong dir="ltr">{formatNumber(stage.value)}</strong>
          </div>
          <div className="visit-decision-funnel-track">
            <span style={{ inlineSize: `${Math.max((stage.value / base) * 100, stage.value ? 8 : 0)}%` }} />
          </div>
          {index > 0 ? <small>{percentage(stage.value, stages[index - 1].value)} من المرحلة السابقة</small> : null}
        </div>
      ))}
    </div>
  )
}

function DistributionBars({ rows, emptyText }: { rows: VisitReportBreakdown[]; emptyText: string }) {
  const max = Math.max(...rows.map(row => row.count), 0)
  if (!rows.length) return <div className="visit-report-empty">{emptyText}</div>

  return (
    <div className="visit-report-bars">
      {rows.map(row => (
        <div key={row.label}>
          <div className="visit-report-bar-label">
            <span>{row.label}</span>
            <strong dir="ltr">{formatNumber(row.count)}</strong>
          </div>
          <div className="visit-report-bar-track" aria-hidden="true">
            <div className="visit-report-bar-fill" style={{ width: `${max ? (row.count / max) * 100 : 0}%` }} />
          </div>
        </div>
      ))}
    </div>
  )
}

function badgeClass(kind: 'success' | 'warning' | 'danger' | 'info' | 'muted') {
  return `visit-report-badge visit-report-badge--${kind}`
}

function qualityKind(row: VisitReportRow): 'success' | 'warning' | 'danger' | 'info' | 'muted' {
  if (row.recording_quality === 'recorded' && !row.has_quality_exception) return 'success'
  if (row.recording_quality === 'administrative' || row.needs_gps_review) return 'warning'
  if (row.recording_quality === 'missing_activity') return 'danger'
  return 'muted'
}

function qualityReasons(row: VisitReportRow) {
  const reasons: string[] = []
  if (row.is_administrative_completion) reasons.push('إغلاق إداري')
  if (row.visit_status === 'completed' && !row.activity_id) reasons.push('لا يوجد نشاط ميداني')
  if (row.visit_status === 'completed' && !row.has_core_survey) reasons.push('الاستبيان الأساسي غير مكتمل')
  if (row.needs_gps_review) reasons.push('GPS ينتظر المراجعة')
  return reasons
}

function answerText(row: VisitSurveyReportAnswer) {
  if (row.answer_value) return row.answer_value
  if (row.answer_json == null) return '—'
  if (Array.isArray(row.answer_json)) return row.answer_json.join('، ')
  return JSON.stringify(row.answer_json)
}

function csvCell(value: unknown) {
  const text = value == null ? '' : String(value)
  return `"${text.replace(/"/g, '""')}"`
}

function downloadVisitCsv(rows: VisitReportRow[]) {
  const headers = [
    'التاريخ', 'المندوب', 'الفرع', 'كود العميل', 'العميل', 'الغرض', 'الحالة',
    'جودة التسجيل', 'نتيجة التواصل', 'حالة العميل', 'النتيجة التجارية', 'المدة بالدقائق',
    'حالة GPS', 'مراجعة GPS', 'ملخص الزيارة',
  ]
  const body = rows.map(row => [
    row.plan_date,
    row.employee_name,
    row.branch_name,
    row.customer_code,
    row.customer_name,
    PURPOSE_LABELS[row.purpose_type ?? 'unspecified'] ?? row.purpose_type,
    STATUS_LABELS[row.visit_status] ?? row.visit_status,
    QUALITY_LABELS[row.recording_quality] ?? row.recording_quality,
    row.contact_result,
    row.customer_state,
    row.business_outcome,
    row.duration_minutes,
    GPS_LABELS[row.gps_validation_status ?? ''] ?? row.gps_validation_status,
    row.gps_review_status,
    row.visit_summary,
  ])
  const csv = `\uFEFF${[headers, ...body].map(line => line.map(csvCell).join(',')).join('\r\n')}`
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }))
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = `visit-report-${new Date().toISOString().slice(0, 10)}.csv`
  anchor.click()
  URL.revokeObjectURL(url)
}

function VisitRowsTable({ rows, qualityMode = false }: { rows: VisitReportRow[]; qualityMode?: boolean }) {
  if (!rows.length) {
    return <div className="visit-report-empty">لا توجد زيارات مطابقة للفلاتر المحددة.</div>
  }

  return (
    <div className="visit-report-table-wrap">
      <table className="visit-report-table">
        <thead>
          <tr>
            <th>التاريخ</th>
            <th>المندوب</th>
            <th>العميل</th>
            <th>الغرض</th>
            <th>الحالة</th>
            <th>نتيجة التواصل</th>
            <th>{qualityMode ? 'الاستثناءات' : 'المدة'}</th>
            <th>GPS</th>
            <th>التسجيل</th>
            <th>التفاصيل</th>
          </tr>
        </thead>
        <tbody>
          {rows.map(row => {
            const reasons = qualityReasons(row)
            return (
              <tr key={row.visit_item_id}>
                <td dir="ltr">{formatDate(row.plan_date)}</td>
                <td>
                  <strong>{row.employee_name}</strong>
                  <div className="text-muted">{row.branch_name ?? '—'}</div>
                </td>
                <td>
                  <strong>{row.customer_name}</strong>
                  <div className="text-muted" dir="ltr">{row.customer_code}</div>
                </td>
                <td>{PURPOSE_LABELS[row.purpose_type ?? 'unspecified'] ?? row.purpose_type}</td>
                <td><span className={badgeClass(row.visit_status === 'completed' ? 'success' : 'muted')}>{STATUS_LABELS[row.visit_status] ?? row.visit_status}</span></td>
                <td>{row.contact_result ?? '—'}</td>
                <td>
                  {qualityMode ? (
                    reasons.length ? reasons.map(reason => <div key={reason}>{reason}</div>) : '—'
                  ) : (
                    <>
                      <strong dir="ltr">{row.duration_minutes == null ? '—' : `${formatNumber(row.duration_minutes)} د`}</strong>
                      <div className="text-muted">{formatDateTime(row.started_at)}</div>
                    </>
                  )}
                </td>
                <td>
                  <span className={badgeClass(row.gps_validation_status === 'passed' ? 'success' : row.needs_gps_review ? 'warning' : 'muted')}>
                    {GPS_LABELS[row.gps_validation_status ?? ''] ?? row.gps_validation_status ?? 'غير مسجل'}
                  </span>
                </td>
                <td>
                  <span className={badgeClass(qualityKind(row))}>{QUALITY_LABELS[row.recording_quality] ?? row.recording_quality}</span>
                </td>
                <td>
                  <Link className="visit-report-link" to={`/activities/visit-plans/${row.plan_id}`}>الخطة</Link>
                  {row.activity_id ? (
                    <> · <Link className="visit-report-link" to={`/activities/${row.activity_id}`}>النشاط</Link></>
                  ) : null}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

export default function VisitReportsPage() {
  const can = useAuthStore(state => state.can)
  const canExport = can(PERMISSIONS.REPORTS_EXPORT)
  const [tab, setTab] = useState<ReportTab>('overview')
  const [range, setRange] = useState<DateRange>(initialDateRange)
  const [employeeId, setEmployeeId] = useState('')
  const [branchId, setBranchId] = useState('')
  const [purposeType, setPurposeType] = useState('')
  const [visitStatus, setVisitStatus] = useState('')
  const [recordingQuality, setRecordingQuality] = useState('')
  const [contactResult, setContactResult] = useState('')
  const [page, setPage] = useState(1)
  const [surveyTemplate, setSurveyTemplate] = useState('visit.core')
  const [surveyQuestion, setSurveyQuestion] = useState('contact.result')
  const [exporting, setExporting] = useState(false)

  const filters = useMemo<VisitReportFilters>(() => ({
    dateFrom: range.from,
    dateTo: range.to,
    employeeId: employeeId || undefined,
    branchId: branchId || undefined,
    purposeType: purposeType || undefined,
    visitStatus: visitStatus || undefined,
    recordingQuality: recordingQuality || undefined,
    contactResult: contactResult || undefined,
  }), [range, employeeId, branchId, purposeType, visitStatus, recordingQuality, contactResult])

  const { data: employeesResult } = useHREmployees({ status: 'active', pageSize: 300 })
  const { data: branches = [] } = useBranches()
  const employees = employeesResult?.data ?? []

  const summaryQuery = useQuery({
    queryKey: ['visit-report-summary', filters.dateFrom, filters.dateTo, employeeId, branchId, purposeType],
    queryFn: () => getVisitReportSummary(filters),
  })

  const rowsQuery = useQuery({
    queryKey: ['visit-report-rows', filters, page, tab],
    queryFn: () => getVisitReportRows(filters, { page, pageSize: 25, exceptionsOnly: tab === 'quality' }),
    enabled: tab === 'visits' || tab === 'quality',
  })

  const surveyQuery = useQuery({
    queryKey: ['visit-report-surveys', filters.dateFrom, filters.dateTo, employeeId, branchId, purposeType],
    queryFn: () => getVisitSurveyReportAnswers(filters),
    enabled: tab === 'surveys',
  })

  const summary = summaryQuery.data
  const metrics: VisitReportMetrics = summary?.metrics ?? {
    planned: 0,
    completed: 0,
    field_recorded: 0,
    administrative: 0,
    effective_contacts: 0,
    survey_completed: 0,
    gps_passed: 0,
    gps_pending_review: 0,
    quality_exceptions: 0,
    open_visits: 0,
    average_duration_minutes: null,
    opportunity_value: 0,
    sales_created: 0,
    sales_expected: 0,
    sales_lost: 0,
    activation_followup: 0,
    at_risk_visits: 0,
    very_short_visits: 0,
    unlinked_order_claims: 0,
    actionable_visits: 0,
  }

  const surveyModel = useMemo(() => {
    const answers = surveyQuery.data ?? []
    const templates = Array.from(new Map(answers.map(row => [row.template_code, {
      code: row.template_code,
      name: row.template_name,
    }])).values())
    const effectiveTemplate = templates.some(template => template.code === surveyTemplate)
      ? surveyTemplate
      : templates[0]?.code ?? ''
    const questions = Array.from(new Map(
      answers
        .filter(row => row.template_code === effectiveTemplate)
        .map(row => [row.question_code, { code: row.question_code, text: row.question_text, type: row.question_type }]),
    ).values())
    const effectiveQuestion = questions.some(question => question.code === surveyQuestion)
      ? surveyQuestion
      : questions[0]?.code ?? ''
    const selectedRows = answers.filter(row => row.template_code === effectiveTemplate && row.question_code === effectiveQuestion)
    const counts = new Map<string, number>()
    selectedRows.forEach(row => {
      const answer = answerText(row)
      counts.set(answer, (counts.get(answer) ?? 0) + 1)
    })
    const distribution = Array.from(counts, ([label, count]) => ({ label, count }))
      .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label, 'ar'))

    return { templates, effectiveTemplate, questions, effectiveQuestion, selectedRows, distribution }
  }, [surveyQuery.data, surveyTemplate, surveyQuestion])

  function resetPage() {
    setPage(1)
  }

  function changeTab(nextTab: ReportTab) {
    setTab(nextTab)
    setPage(1)

    if (nextTab !== 'visits') {
      setRecordingQuality('')
      setContactResult('')
    }
    if (nextTab !== 'visits' && nextTab !== 'quality') {
      setVisitStatus('')
    }
  }

  async function handleExport() {
    setExporting(true)
    try {
      const rows = await getVisitReportExportRows(filters)
      downloadVisitCsv(rows)
      toast.success(`تم تصدير ${rows.length} زيارة`)
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر تصدير التقرير')
    } finally {
      setExporting(false)
    }
  }

  const tabs: Array<{ key: ReportTab; label: string; icon: React.ReactNode }> = [
    { key: 'overview', label: 'الملخص', icon: <BarChart3 size={17} /> },
    { key: 'visits', label: 'سجل الزيارات', icon: <Route size={17} /> },
    { key: 'surveys', label: 'الاستبيانات', icon: <ClipboardCheck size={17} /> },
    { key: 'quality', label: 'الاستثناءات', icon: <FileWarning size={17} /> },
  ]

  return (
    <div className="visit-report-page">
      <header className="visit-report-header">
        <div>
          <h1>تقارير الزيارات</h1>
          <p>التنفيذ الفعلي، نتائج التواصل، الاستبيانات وجودة التسجيل في مكان واحد.</p>
        </div>
        {canExport ? (
          <Button variant="secondary" icon={<Download size={17} />} onClick={handleExport} disabled={exporting}>
            {exporting ? 'جاري التصدير…' : 'تصدير CSV'}
          </Button>
        ) : null}
      </header>

      <div className="visit-report-tabs" role="tablist" aria-label="أقسام تقارير الزيارات">
        {tabs.map(item => (
          <button
            key={item.key}
            type="button"
            role="tab"
            aria-selected={tab === item.key}
            className="visit-report-tab"
            onClick={() => changeTab(item.key)}
          >
            {item.icon}
            {item.label}
          </button>
        ))}
      </div>

      <section className="edara-card visit-report-filters" aria-label="فلاتر التقرير">
        <ReportFilterBar value={range} onChange={value => { setRange(value); resetPage() }} />
        <div className="visit-report-filter-grid">
          <label>
            الفرع
            <select className="form-input" value={branchId} onChange={event => { setBranchId(event.target.value); resetPage() }}>
              <option value="">كل الفروع</option>
              {branches.map(branch => <option key={branch.id} value={branch.id}>{branch.name}</option>)}
            </select>
          </label>
          <label>
            المندوب
            <select className="form-input" value={employeeId} onChange={event => { setEmployeeId(event.target.value); resetPage() }}>
              <option value="">كل المندوبين</option>
              {employees.map(employee => <option key={employee.id} value={employee.id}>{employee.full_name}</option>)}
            </select>
          </label>
          <label>
            غرض الزيارة
            <select className="form-input" value={purposeType} onChange={event => { setPurposeType(event.target.value); resetPage() }}>
              <option value="">كل الأغراض</option>
              {Object.entries(PURPOSE_LABELS).filter(([key]) => key !== 'unspecified').map(([key, label]) => (
                <option key={key} value={key}>{label}</option>
              ))}
            </select>
          </label>
          {(tab === 'visits' || tab === 'quality') ? (
            <label>
              حالة الزيارة
              <select className="form-input" value={visitStatus} onChange={event => { setVisitStatus(event.target.value); resetPage() }}>
                <option value="">كل الحالات</option>
                {Object.entries(STATUS_LABELS).map(([key, label]) => <option key={key} value={key}>{label}</option>)}
              </select>
            </label>
          ) : null}
          {tab === 'visits' ? (
            <>
              <label>
                جودة التسجيل
                <select className="form-input" value={recordingQuality} onChange={event => { setRecordingQuality(event.target.value); resetPage() }}>
                  <option value="">كل أنواع التسجيل</option>
                  {Object.entries(QUALITY_LABELS).map(([key, label]) => <option key={key} value={key}>{label}</option>)}
                </select>
              </label>
              <label>
                نتيجة التواصل
                <select className="form-input" value={contactResult} onChange={event => { setContactResult(event.target.value); resetPage() }}>
                  <option value="">كل النتائج</option>
                  {(summary?.contact_results ?? []).map(result => <option key={result.label} value={result.label}>{result.label}</option>)}
                </select>
              </label>
            </>
          ) : null}
        </div>
      </section>

      {summaryQuery.isError ? (
        <div className="edara-card visit-report-error">تعذر تحميل ملخص الزيارات. يرجى المحاولة مرة أخرى.</div>
      ) : null}

      {tab === 'overview' ? (
        <>
          <section className="visit-decision-hero" aria-labelledby="visit-decision-title">
            <div className="visit-decision-hero-copy">
              <span className="visit-decision-eyebrow">لوحة القرار</span>
              <h2 id="visit-decision-title">ماذا تحقق، وما الذي يحتاج تدخلًا؟</h2>
              <p>النتائج التالية تجمع التنفيذ والفرص والمخاطر، دون اعتبار الحقول الاختيارية نقصًا يعطل المندوب.</p>
            </div>
            <div className="visit-decision-cards">
              <DecisionCard
                label="فرص طلب تحتاج متابعة"
                value={formatNumber(metrics.sales_expected)}
                note={`قيمة مقدرة ${formatNumber(metrics.opportunity_value)} ج.م`}
                tone="info"
                icon={<TrendingUp size={20} />}
              />
              <DecisionCard
                label="عملاء في دائرة الخطر"
                value={formatNumber(metrics.at_risk_visits)}
                note="تراجع أو معرض للفقد أو متوقف"
                tone="danger"
                icon={<AlertTriangle size={20} />}
              />
              <DecisionCard
                label="إجراءات تحتاج انتباهًا"
                value={formatNumber(metrics.actionable_visits)}
                note="فرص ومخاطر واستثناءات قابلة للمراجعة"
                tone="warning"
                icon={<CalendarClock size={20} />}
              />
              <DecisionCard
                label="طلبات تم الإبلاغ عنها"
                value={formatNumber(metrics.sales_created)}
                note={`${formatNumber(metrics.unlinked_order_claims)} غير مرتبطة بطلب فعلي`}
                tone="success"
                icon={<CircleDollarSign size={20} />}
              />
            </div>
          </section>

          <section className="visit-decision-grid">
            <article className="edara-card visit-report-panel visit-decision-panel">
              <div className="visit-report-section-head">
                <div><h2>مسار تنفيذ الزيارات</h2><p>يوضح أين يتوقف التحول من الخطة إلى التواصل الفعلي.</p></div>
              </div>
              <VisitFunnel metrics={metrics} />
            </article>
            <article className="edara-card visit-report-panel visit-attention-panel">
              <div className="visit-report-section-head">
                <div><h2>ثقة البيانات</h2><p>تنبيهات للمراجعة وليست أسبابًا لمنع المندوب من الإغلاق.</p></div>
                <ShieldCheck size={22} />
              </div>
              <div className="visit-attention-list">
                <div><span>زيارات قصيرة جدًا</span><strong dir="ltr">{formatNumber(metrics.very_short_visits)}</strong></div>
                <div><span>طلبات مذكورة بلا ربط</span><strong dir="ltr">{formatNumber(metrics.unlinked_order_claims)}</strong></div>
                <div><span>استثناءات تسجيل أو GPS</span><strong dir="ltr">{formatNumber(metrics.quality_exceptions)}</strong></div>
                <div><span>زيارات مفتوحة</span><strong dir="ltr">{formatNumber(metrics.open_visits)}</strong></div>
              </div>
            </article>
          </section>

          <section className="visit-report-metrics" aria-label="المؤشرات الرئيسية">
            <Metric label="الزيارات المخططة" value={formatNumber(metrics.planned)} note="إجمالي بنود الخطط" icon={<Route size={18} />} />
            <Metric label="المكتملة تشغيليًا" value={formatNumber(metrics.completed)} note={percentage(metrics.completed, metrics.planned)} icon={<CheckCircle2 size={18} />} />
            <Metric label="المسجلة ميدانيًا" value={formatNumber(metrics.field_recorded)} note={`${percentage(metrics.field_recorded, metrics.completed)} من المكتمل`} icon={<MapPinCheck size={18} />} />
            <Metric label="التواصل الفعلي" value={formatNumber(metrics.effective_contacts)} note={`${percentage(metrics.effective_contacts, metrics.survey_completed)} من الاستبيانات`} icon={<Users size={18} />} />
            <Metric label="استبيان أساسي مكتمل" value={formatNumber(metrics.survey_completed)} note={percentage(metrics.survey_completed, metrics.field_recorded)} icon={<ClipboardCheck size={18} />} />
            <Metric label="GPS مطابق" value={formatNumber(metrics.gps_passed)} note={`${metrics.gps_pending_review} تنتظر المراجعة`} icon={<MapPinCheck size={18} />} />
            <Metric label="استثناءات جودة" value={formatNumber(metrics.quality_exceptions)} note={`${metrics.administrative} إغلاق إداري`} icon={<AlertTriangle size={18} />} />
            <Metric label="متوسط مدة الزيارة" value={`${formatNumber(metrics.average_duration_minutes)} د`} note={`قيمة الفرص: ${formatNumber(metrics.opportunity_value)}`} icon={<BarChart3 size={18} />} />
          </section>

          <section className="visit-report-overview-grid">
            <article className="edara-card visit-report-panel">
              <h2>نتائج التواصل</h2>
              <DistributionBars rows={summary?.contact_results ?? []} emptyText="لا توجد نتائج تواصل في الفترة." />
            </article>
            <article className="edara-card visit-report-panel">
              <h2>حالة العملاء</h2>
              <DistributionBars rows={summary?.customer_states ?? []} emptyText="لا توجد تقييمات عملاء في الفترة." />
            </article>
          </section>

          <section className="visit-report-overview-grid">
            <article className="edara-card visit-report-panel">
              <h2>نتائج فرص المبيعات</h2>
              <DistributionBars rows={summary?.sales_outcomes ?? []} emptyText="لا توجد زيارات مبيعات في الفترة." />
            </article>
            <article className="edara-card visit-report-panel">
              <h2>استجابة العملاء للتنشيط</h2>
              <DistributionBars rows={summary?.activation_outcomes ?? []} emptyText="لا توجد زيارات تنشيط في الفترة." />
            </article>
          </section>

          <section className="edara-card visit-report-table-card">
            <div className="visit-report-table-head"><h2>الأداء حسب المندوب</h2></div>
            <div className="visit-report-table-wrap">
              <table className="visit-report-table">
                <thead><tr><th>المندوب</th><th>المخطط</th><th>المكتمل</th><th>المسجل</th><th>تواصل فعلي</th><th>استثناءات</th></tr></thead>
                <tbody>
                  {(summary?.employee_results ?? []).map(row => (
                    <tr key={row.employee_id}>
                      <td><strong>{row.employee_name}</strong></td>
                      <td dir="ltr">{row.planned}</td>
                      <td dir="ltr">{row.completed}</td>
                      <td dir="ltr">{row.field_recorded}</td>
                      <td dir="ltr">{row.effective_contacts}</td>
                      <td dir="ltr">{row.quality_exceptions}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </>
      ) : null}

      {(tab === 'visits' || tab === 'quality') ? (
        <section className="edara-card visit-report-table-card">
          <div className="visit-report-table-head">
            <div>
              <h2>{tab === 'quality' ? 'الزيارات التي تحتاج مراجعة' : 'سجل الزيارات'}</h2>
              <p>{formatNumber(rowsQuery.data?.count ?? 0)} زيارة مطابقة</p>
            </div>
          </div>
          {rowsQuery.isLoading ? <div className="visit-report-loading">جاري تحميل الزيارات…</div> : null}
          {rowsQuery.isError ? <div className="visit-report-error">تعذر تحميل سجل الزيارات.</div> : null}
          {rowsQuery.data ? <VisitRowsTable rows={rowsQuery.data.data} qualityMode={tab === 'quality'} /> : null}
          {(rowsQuery.data?.totalPages ?? 1) > 1 ? (
            <div className="visit-report-pagination">
              <Button variant="secondary" size="sm" disabled={page <= 1} onClick={() => setPage(value => value - 1)}>السابق</Button>
              <span>صفحة <strong dir="ltr">{page}</strong> من <strong dir="ltr">{rowsQuery.data?.totalPages}</strong></span>
              <Button variant="secondary" size="sm" disabled={page >= (rowsQuery.data?.totalPages ?? 1)} onClick={() => setPage(value => value + 1)}>التالي</Button>
            </div>
          ) : null}
        </section>
      ) : null}

      {tab === 'surveys' ? (
        <>
          <section className="edara-card visit-report-panel">
            <div className="visit-report-section-head">
              <div>
                <h2>تحليل إجابات الاستبيانات</h2>
                <p>اختر الاستبيان والسؤال لعرض توزيع الإجابات والتفاصيل.</p>
              </div>
            </div>
            <div className="visit-report-survey-controls">
              <label>
                الاستبيان
                <select className="form-input" value={surveyModel.effectiveTemplate} onChange={event => { setSurveyTemplate(event.target.value); setSurveyQuestion('') }}>
                  {surveyModel.templates.map(template => <option key={template.code} value={template.code}>{template.name}</option>)}
                </select>
              </label>
              <label>
                السؤال
                <select className="form-input" value={surveyModel.effectiveQuestion} onChange={event => setSurveyQuestion(event.target.value)}>
                  {surveyModel.questions.map(question => <option key={question.code} value={question.code}>{question.text}</option>)}
                </select>
              </label>
            </div>
            {surveyQuery.isLoading ? <div className="visit-report-loading">جاري تحميل الإجابات…</div> : null}
            {surveyQuery.isError ? <div className="visit-report-error">تعذر تحميل إجابات الاستبيانات.</div> : null}
            {!surveyQuery.isLoading && !surveyQuery.isError ? (
              <DistributionBars rows={surveyModel.distribution} emptyText="لا توجد إجابات لهذا السؤال في الفترة." />
            ) : null}
          </section>

          <section className="edara-card visit-report-table-card">
            <div className="visit-report-table-head">
              <h2>الإجابات التفصيلية</h2>
              <span>{formatNumber(surveyModel.selectedRows.length)} إجابة</span>
            </div>
            <div className="visit-report-table-wrap">
              <table className="visit-report-table">
                <thead><tr><th>التاريخ</th><th>المندوب</th><th>العميل</th><th>الإجابة</th><th>الزيارة</th></tr></thead>
                <tbody>
                  {surveyModel.selectedRows.slice(0, 250).map(row => (
                    <tr key={row.response_id}>
                      <td dir="ltr">{formatDate(row.plan_date)}</td>
                      <td>{row.employee_name}</td>
                      <td><strong>{row.customer_name}</strong><div className="text-muted" dir="ltr">{row.customer_code}</div></td>
                      <td className="visit-report-answer">{answerText(row)}</td>
                      <td><Link className="visit-report-link" to={`/activities/visit-plans/${row.plan_id}`}>فتح الخطة</Link></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </>
      ) : null}
    </div>
  )
}
