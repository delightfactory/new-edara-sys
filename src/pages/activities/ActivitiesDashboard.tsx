/**
 * ActivitiesDashboard — لوحة الأنشطة الذكية بثلاثة مستويات
 *
 * مندوب   → خطة اليوم + أهدافه + نشاطاته + callbacks
 * مشرف    → أداء الفريق + خطط اليوم + تنبيهات
 * إدارة   → KPI الشركة + مقارنة الفروع + توقعات
 */
import { useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  MapPin, Phone, Target, Calendar, TrendingUp, Plus,
  ChevronLeft, Users, AlertCircle, CheckCircle2, Clock,
  BarChart3, ArrowUp, ArrowDown, Minus, DollarSign, Wallet,
} from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import {
  useActivities,
  usePlanDailySummary,
  useTargetStatus,
  useRepPerformance,
  useCurrentEmployee,
  useHREmployees,
} from '@/hooks/useQueryHooks'
import { PERMISSIONS } from '@/lib/permissions/constants'
import PageHeader from '@/components/shared/PageHeader'
import ActivityTimeline from '@/components/shared/ActivityTimeline'
import TargetProgressWidget from '@/components/shared/TargetProgressWidget'
import ActivityStatusBadge from '@/components/shared/ActivityStatusBadge'
import Button from '@/components/ui/Button'
import type { Target as TargetRow, TargetProgress, TargetStatusRow } from '@/lib/types/activities'

function todayStr() { return new Date().toISOString().slice(0, 10) }
function thisMonthStart() {
  const d = new Date(); d.setDate(1)
  return d.toISOString().slice(0, 10)
}

function adaptTargetStatus(row: TargetStatusRow): { target: TargetRow; progress: TargetProgress | null } {
  const target: TargetRow = {
    id: row.id, type_id: '', type_code: row.type_code, name: row.name,
    description: null, scope: row.scope, scope_id: row.scope_id,
    period: 'custom', period_start: row.period_start, period_end: row.period_end,
    target_value: row.target_value, min_value: row.min_value, stretch_value: row.stretch_value,
    product_id: null, category_id: null, governorate_id: null, city_id: null,
    area_id: null, dormancy_days: null, filter_criteria: {}, parent_target_id: null,
    auto_split: false, split_basis: null, is_paused: row.is_paused, paused_at: null,
    paused_reason: null, assigned_by: '', is_active: row.is_active, notes: null,
    reward_type: null, reward_base_value: null, reward_pool_basis: null,
    auto_payout: false, payout_month_offset: 0,
    created_at: '', updated_at: '',
  }
  const progress: TargetProgress | null = row.achieved_value != null ? {
    id: '', target_id: row.id, snapshot_date: row.data_as_of ?? todayStr(),
    achieved_value: row.achieved_value, achievement_pct: row.achievement_pct ?? 0,
    trend: row.trend, last_calc_at: row.last_calc_at, calc_details: {},
  } : null
  return { target, progress }
}

// ── Trend Icon
function TrendIcon({ trend }: { trend?: string | null }) {
  if (trend === 'exceeded' || trend === 'achieved') return <ArrowUp size={13} style={{ color: 'var(--color-success)' }} />
  if (trend === 'at_risk') return <Minus size={13} style={{ color: 'var(--color-warning)' }} />
  if (trend === 'behind') return <ArrowDown size={13} style={{ color: 'var(--color-danger)' }} />
  return <Minus size={13} style={{ color: 'var(--text-muted)' }} />
}

// ── Performance Badge
function PerfBadge({ pct }: { pct: number }) {
  let label = 'في خطر'; let bg = 'var(--color-danger-light)'; let color = 'var(--color-danger)'
  if (pct >= 100) { label = '✓ محقق'; bg = 'var(--color-success-light)'; color = 'var(--color-success)' }
  else if (pct >= 80) { label = 'جيد'; bg = 'var(--color-primary-light)'; color = 'var(--color-primary)' }
  else if (pct >= 60) { label = 'يُتابَع'; bg = 'var(--color-warning-light)'; color = 'var(--color-warning)' }
  return (
    <span style={{
      fontSize: 10, fontWeight: 700, padding: '2px 8px',
      borderRadius: 99, background: bg, color, whiteSpace: 'nowrap',
    }}>
      {label}
    </span>
  )
}

// ══════════════════════════════════════════════════════
// SECTION A — لوحة المندوب
// ══════════════════════════════════════════════════════
function RepDashboard() {
  const navigate = useNavigate()
  const today    = todayStr()
  const { data: currentEmployee } = useCurrentEmployee()

  const { data: actResult, isLoading: actLoading } = useActivities({
    dateFrom: today, dateTo: today, pageSize: 15,
  })
  const activities = actResult?.data ?? []

  const { data: planSummaries = [], isLoading: plansLoading } = usePlanDailySummary({ date: today })
  const { data: targetRows = [], isLoading: targetsLoading }   = useTargetStatus({ isActive: true })
  const { data: perfResult = [] } = useRepPerformance({ periodFrom: thisMonthStart(), periodTo: today })

  const visitPlan = planSummaries.find(p => p.plan_module === 'visit')
  const callPlan  = planSummaries.find(p => p.plan_module === 'call')
  const topTargets = useMemo(() => targetRows.slice(0, 4), [targetRows])

  // Sales & Collection KPIs from rep performance
  const myPerf = perfResult[0] as any
  const monthSales      = myPerf?.sales_value ?? 0
  const monthCollection = myPerf?.collection_value ?? 0

  // callbacks اليوم: أنشطة بها call_detail.callback_at لتاريخ اليوم
  const todayCallbacks = useMemo(() => {
    return activities.filter(a => {
      const cd = (a as any).call_detail
      if (cd?.callback_at) {
        const cbDate = cd.callback_at.slice(0, 10)
        return cbDate === today
      }
      return a.outcome_type === 'followup_scheduled' || a.outcome_type === 'callback_scheduled'
    })
  }, [activities, today])

  return (
    <div>
      {/* ── Greeting ── */}
      <div className="rep-greeting">
        <span className="rep-greeting-emoji">👋</span>
        <div>
          <div className="rep-greeting-name">
            صباح الخير{currentEmployee?.full_name ? `، ${currentEmployee.full_name.split(' ')[0]}` : ''}
          </div>
          <div className="rep-greeting-date">
            {new Date().toLocaleDateString('ar-EG', { weekday: 'long', day: 'numeric', month: 'long' })}
          </div>
        </div>
      </div>

      {/* ── Quick Stats ── */}
      <div className="act-dash-summary">
        {/* خطة الزيارات */}
        <div className="act-dash-stat act-dash-stat--visit" onClick={() => navigate('/activities/visit-plans')}>
          <div className="act-dash-stat-icon"><MapPin size={22} /></div>
          <div className="act-dash-stat-body">
            <div className="act-dash-stat-value">
              {plansLoading ? '—' : visitPlan ? (
                <>{visitPlan.completed_count} <span>/ {visitPlan.total_items}</span></>
              ) : '—'}
            </div>
            <div className="act-dash-stat-label">زيارات اليوم</div>
            {visitPlan && (
              <div className="act-dash-stat-sub">
                <ActivityStatusBadge planStatus={visitPlan.plan_status} size="sm" />
                {visitPlan.pending_count > 0 && (
                  <span className="act-dash-stat-pending">{visitPlan.pending_count} معلّق</span>
                )}
              </div>
            )}
          </div>
          <ChevronLeft size={14} className="act-dash-stat-arrow" />
        </div>

        {/* خطة المكالمات */}
        <div className="act-dash-stat act-dash-stat--call" onClick={() => navigate('/activities/call-plans')}>
          <div className="act-dash-stat-icon"><Phone size={22} /></div>
          <div className="act-dash-stat-body">
            <div className="act-dash-stat-value">
              {plansLoading ? '—' : callPlan ? (
                <>{callPlan.completed_count} <span>/ {callPlan.total_items}</span></>
              ) : '—'}
            </div>
            <div className="act-dash-stat-label">مكالمات اليوم</div>
          </div>
          <ChevronLeft size={14} className="act-dash-stat-arrow" />
        </div>

        {/* الأنشطة المنجزة */}
        <div className="act-dash-stat act-dash-stat--activity" onClick={() => navigate('/activities/list')}>
          <div className="act-dash-stat-icon"><CheckCircle2 size={22} /></div>
          <div className="act-dash-stat-body">
            <div className="act-dash-stat-value">{actLoading ? '—' : actResult?.count ?? 0}</div>
            <div className="act-dash-stat-label">أنشطة مسجلة</div>
          </div>
          <ChevronLeft size={14} className="act-dash-stat-arrow" />
        </div>

        {/* callbacks */}
        {todayCallbacks.length > 0 && (
          <div className="act-dash-stat act-dash-stat--target">
            <div className="act-dash-stat-icon"><Clock size={22} /></div>
            <div className="act-dash-stat-body">
              <div className="act-dash-stat-value">{todayCallbacks.length}</div>
              <div className="act-dash-stat-label">متابعات مجدولة</div>
            </div>
          </div>
        )}

        {/* مبيعات الشهر */}
        <div className="act-dash-stat cursor-pointer" onClick={() => navigate('/sales/orders')}>
          <div className="act-dash-stat-icon" style={{ background: 'rgba(16,185,129,0.1)', color: '#10b981' }}>
            <DollarSign size={22} />
          </div>
          <div className="act-dash-stat-body">
            <div className="act-dash-stat-value">
              {monthSales > 0 ? monthSales.toLocaleString('ar-EG', { maximumFractionDigits: 0 }) : '—'}
            </div>
            <div className="act-dash-stat-label">مبيعات الشهر</div>
          </div>
          <ChevronLeft size={14} className="act-dash-stat-arrow" />
        </div>

        {/* تحصيلات الشهر */}
        <div className="act-dash-stat cursor-pointer" onClick={() => navigate('/finance/payments')}>
          <div className="act-dash-stat-icon" style={{ background: 'rgba(245,158,11,0.1)', color: '#f59e0b' }}>
            <Wallet size={22} />
          </div>
          <div className="act-dash-stat-body">
            <div className="act-dash-stat-value">
              {monthCollection > 0 ? monthCollection.toLocaleString('ar-EG', { maximumFractionDigits: 0 }) : '—'}
            </div>
            <div className="act-dash-stat-label">تحصيلات الشهر</div>
          </div>
          <ChevronLeft size={14} className="act-dash-stat-arrow" />
        </div>
      </div>

      {/* ── Main Grid ── */}
      <div className="act-dash-grid act-dash-grid--rep">

        {/* Targets Column */}
        {topTargets.length > 0 && (
          <section className="edara-card act-dash-section">
            <div className="act-dash-section-header">
              <div className="act-dash-section-title"><TrendingUp size={16} /><span>أهدافي</span></div>
              <button className="act-dash-view-all" onClick={() => navigate('/activities/targets')}>عرض الكل</button>
            </div>
            <div className="act-dash-targets">
              {targetsLoading
                ? [1, 2].map(i => <div key={i} className="skeleton h-[100px] rounded-md" />)
                : topTargets.map(row => {
                    const { target, progress } = adaptTargetStatus(row)
                    return (
                      <TargetProgressWidget
                        key={row.id} target={target} progress={progress} compact
                        onClick={() => navigate(`/activities/targets/${row.id}`)}
                      />
                    )
                  })
              }
            </div>
          </section>
        )}

        {/* Plan Quick Nav + Timeline */}
        <div className="flex flex-col gap-4">
          {/* Actionable Callbacks Pipeline */}
          {todayCallbacks.length > 0 && (
            <section className="edara-card act-dash-section border-l-4 border-warning">
              <div className="act-dash-section-header">
                <div className="act-dash-section-title"><Clock size={16} className="text-warning" /><span>المتابعات المستحقة اليوم</span></div>
              </div>
              <div className="flex flex-col gap-2 mt-2">
                {todayCallbacks.map(a => {
                  const custName = (a as any).customer?.name ?? 'بدون عميل'
                  const phone = (a as any).call_detail?.phone_number
                  return (
                    <div key={a.id} className="flex justify-between items-center p-2 bg-surface-2 rounded-md">
                      <div>
                        <div className="text-sm font-semibold">{custName}</div>
                        <div className="text-[11px] text-muted">{a.outcome_type === 'callback_scheduled' ? 'مكالمة لاحقة' : 'متابعة'} {phone ? ` • ${phone}` : ''}</div>
                      </div>
                      <button className="btn btn--primary btn--sm text-[11px] px-2 py-1" onClick={() => navigate(`/activities/new?customerId=${a.customer_id}&prefillPlanType=call`)}>
                        تنفيذ المتابعة ↗
                      </button>
                    </div>
                  )
                })}
              </div>
            </section>
          )}

          {/* خطة اليوم */}
          <section className="edara-card act-dash-section">
            <div className="act-dash-section-header">
              <div className="act-dash-section-title"><Calendar size={16} /><span>خطة اليوم</span></div>
            </div>
            <div className="act-dash-plan-btns">
              <button className="act-dash-plan-btn" onClick={() => navigate('/activities/visit-plans')}>
                <MapPin size={20} className="act-dash-plan-icon act-dash-plan-icon--visit" />
                <div>
                  <div className="act-dash-plan-btn-title">خطط الزيارات</div>
                  <div className="act-dash-plan-btn-sub">
                    {visitPlan ? `${visitPlan.completed_count}/${visitPlan.total_items} مكتملة` : 'لا توجد خطة اليوم'}
                  </div>
                </div>
                <ChevronLeft size={16} className="act-dash-stat-arrow" />
              </button>
              <button className="act-dash-plan-btn" onClick={() => navigate('/activities/call-plans')}>
                <Phone size={20} className="act-dash-plan-icon act-dash-plan-icon--call" />
                <div>
                  <div className="act-dash-plan-btn-title">خطط المكالمات</div>
                  <div className="act-dash-plan-btn-sub">
                    {callPlan ? `${callPlan.completed_count}/${callPlan.total_items} مكتملة` : 'لا توجد خطة اليوم'}
                  </div>
                </div>
                <ChevronLeft size={16} className="act-dash-stat-arrow" />
              </button>
            </div>
          </section>

          {/* Timeline */}
          <section className="edara-card act-dash-section">
            <div className="act-dash-section-header">
              <div className="act-dash-section-title"><Calendar size={16} /><span>أنشطة اليوم</span></div>
              <button className="act-dash-view-all" onClick={() => navigate('/activities/list')}>الكل</button>
            </div>
            <ActivityTimeline activities={activities} loading={actLoading} limit={6} />
            {activities.length === 0 && !actLoading && (
              <div style={{ padding: 'var(--space-4)', textAlign: 'center' }}>
                <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/new')} variant="secondary">
                  تسجيل نشاط جديد
                </Button>
              </div>
            )}
          </section>
        </div>
      </div>
    </div>
  )
}

// ══════════════════════════════════════════════════════
// SECTION B — لوحة المشرف
// ══════════════════════════════════════════════════════
function SupervisorDashboard() {
  const navigate = useNavigate()
  const today    = todayStr()
  const monthStart = thisMonthStart()

  const { data: actResult, isLoading: actLoading } = useActivities({
    dateFrom: today, dateTo: today, pageSize: 15,
  })
  const activities = actResult?.data ?? []

  const { data: planSummaries = [], isLoading: plansLoading } = usePlanDailySummary({ date: today })
  const { data: targetRows = [] }   = useTargetStatus({ isActive: true })
  const { data: perfResult = [], isLoading: perfLoading }  = useRepPerformance({
    periodFrom: monthStart, periodTo: today,
  })
  const { data: employeesResult } = useHREmployees({ status: 'active' })
  const teamEmployees = useMemo(() => employeesResult?.data ?? [], [employeesResult])

  // أعضاء الفريق الذين لم يسجلوا نشاطاً اليوم
  const activeToday = new Set(activities.map(a => (a as any).employee_id))
  const inactiveReps = teamEmployees.filter(e => !activeToday.has(e.id))

  const noPlansToday = planSummaries.filter(p => p.plan_status === 'missed' || p.completed_count === 0)

  // إجمالي الأهداف في خطر
  const atRiskTargets = targetRows.filter(t => t.trend === 'at_risk' || t.trend === 'behind')

  return (
    <div>
      {/* ── Supervisor Alerts ── */}
      {(inactiveReps.length > 0 || atRiskTargets.length > 0 || noPlansToday.length > 0) && (
        <div className="sup-alerts">
          {inactiveReps.length > 0 && (
            <div className="sup-alert sup-alert--warning">
              <AlertCircle size={16} />
              <span>{inactiveReps.length} مندوب بدون نشاط اليوم</span>
            </div>
          )}
          {atRiskTargets.length > 0 && (
            <div className="sup-alert sup-alert--danger">
              <TrendingUp size={16} />
              <span>{atRiskTargets.length} هدف في خطر أو متأخر</span>
              <button className="sup-alert-link" onClick={() => navigate('/activities/targets')}>عرض</button>
            </div>
          )}
          {noPlansToday.length > 0 && (
            <div className="sup-alert sup-alert--info">
              <Calendar size={16} />
              <span>{noPlansToday.length} خطة لم تُنجَز حتى الآن</span>
            </div>
          )}
        </div>
      )}

      {/* ── Quick Stats ── */}
      <div className="act-dash-summary">
        <div className="act-dash-stat act-dash-stat--visit" onClick={() => navigate('/activities/visit-plans')}>
          <div className="act-dash-stat-icon"><MapPin size={22} /></div>
          <div className="act-dash-stat-body">
            <div className="act-dash-stat-value">
              {plansLoading ? '—' : planSummaries
                .filter(p => p.plan_module === 'visit')
                .reduce((s, p) => s + p.completed_count, 0)}
              <span> / {plansLoading ? '—' : planSummaries
                .filter(p => p.plan_module === 'visit')
                .reduce((s, p) => s + p.total_items, 0)}</span>
            </div>
            <div className="act-dash-stat-label">زيارات الفريق اليوم</div>
          </div>
          <ChevronLeft size={14} className="act-dash-stat-arrow" />
        </div>
        <div className="act-dash-stat act-dash-stat--call" onClick={() => navigate('/activities/call-plans')}>
          <div className="act-dash-stat-icon"><Phone size={22} /></div>
          <div className="act-dash-stat-body">
            <div className="act-dash-stat-value">{actLoading ? '—' : actResult?.count ?? 0}</div>
            <div className="act-dash-stat-label">أنشطة اليوم</div>
          </div>
          <ChevronLeft size={14} className="act-dash-stat-arrow" />
        </div>
        <div className="act-dash-stat cursor-default">
          <div className="act-dash-stat-icon bg-success-light text-success">
            <Users size={22} />
          </div>
          <div className="act-dash-stat-body">
            <div className="act-dash-stat-value">
              {teamEmployees.length - inactiveReps.length}
              <span> / {teamEmployees.length}</span>
            </div>
            <div className="act-dash-stat-label">مندوبون نشطون اليوم</div>
          </div>
        </div>
        <div className="act-dash-stat act-dash-stat--target" onClick={() => navigate('/activities/targets')}>
          <div className="act-dash-stat-icon"><Target size={22} /></div>
          <div className="act-dash-stat-body">
            <div className="act-dash-stat-value">{targetRows.length}</div>
            <div className="act-dash-stat-label">هدف نشط</div>
          </div>
          <ChevronLeft size={14} className="act-dash-stat-arrow" />
        </div>
      </div>

      {/* ── Main Grid ── */}
      <div className="act-dash-grid">

        {/* Team Performance Table */}
        <section className="edara-card act-dash-section col-span-full">
          <div className="act-dash-section-header">
            <div className="act-dash-section-title"><BarChart3 size={16} /><span>أداء الفريق — الشهر الحالي</span></div>
            <button className="act-dash-view-all" onClick={() => navigate('/activities/list')}>تفاصيل</button>
          </div>
          {perfLoading ? (
            <div className="flex flex-col gap-2">
              {[1,2,3].map(i => <div key={i} className="skeleton h-12 rounded-md" />)}
            </div>
          ) : perfResult.length === 0 ? (
            <p className="text-muted text-sm text-center p-4">
              لا توجد بيانات أداء لهذا الشهر
            </p>
          ) : (
            <div className="sup-perf-table">
              <div className="sup-perf-header">
                <span>المندوب</span>
                <span>الزيارات</span>
                <span>المكالمات</span>
                <span>المبيعات</span>
                <span>الحالة</span>
              </div>
              {perfResult.slice(0, 8).map((rep: any) => {
                const visitTarget = targetRows.find(t => t.scope_id === rep.employee_id && t.type_code === 'visits_count')
                const pct = visitTarget?.achievement_pct ?? null
                return (
                  <div key={rep.employee_id} className="sup-perf-row">
                    <div className="sup-perf-name">{rep.employee_name}</div>
                    <div className="sup-perf-cell">
                      {rep.visits_count}
                      {visitTarget && (
                        <div className="sup-perf-mini-bar">
                          <div style={{
                            width: `${Math.min(pct ?? 0, 100)}%`,
                            background: (pct ?? 0) >= 80 ? 'var(--color-success)' : (pct ?? 0) >= 60 ? 'var(--color-warning)' : 'var(--color-danger)',
                          }} />
                        </div>
                      )}
                    </div>
                    <div className="sup-perf-cell">{rep.calls_count}</div>
                    <div className="sup-perf-cell">
                      {rep.sales_value > 0
                        ? rep.sales_value.toLocaleString('ar-EG', { maximumFractionDigits: 0 })
                        : '—'}
                    </div>
                    <div className="sup-perf-cell">
                      {pct !== null
                        ? <PerfBadge pct={pct} />
                        : <span className="text-[11px] text-muted">بلا هدف</span>
                      }
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </section>

        {/* Targets */}
        {targetRows.length > 0 && (
          <section className="edara-card act-dash-section">
            <div className="act-dash-section-header">
              <div className="act-dash-section-title"><TrendingUp size={16} /><span>أهداف الفريق</span></div>
              <button className="act-dash-view-all" onClick={() => navigate('/activities/targets')}>الكل</button>
            </div>
            <div className="act-dash-targets">
              {targetRows.slice(0, 3).map(row => {
                const { target, progress } = adaptTargetStatus(row)
                return (
                  <TargetProgressWidget
                    key={row.id} target={target} progress={progress} compact
                    onClick={() => navigate(`/activities/targets/${row.id}`)}
                  />
                )
              })}
            </div>
          </section>
        )}

        {/* Today's Timeline */}
        <section className="edara-card act-dash-section">
          <div className="act-dash-section-header">
            <div className="act-dash-section-title"><Calendar size={16} /><span>آخر أنشطة اليوم</span></div>
            <button className="act-dash-view-all" onClick={() => navigate('/activities/list')}>الكل</button>
          </div>
          <ActivityTimeline activities={activities} loading={actLoading} limit={6} />
        </section>
      </div>
    </div>
  )
}

// ══════════════════════════════════════════════════════
// SECTION C — لوحة الإدارة
// ══════════════════════════════════════════════════════
function ManagerDashboard() {
  const navigate   = useNavigate()
  const today      = todayStr()
  const monthStart = thisMonthStart()

  const { data: actResult }       = useActivities({ dateFrom: today, dateTo: today, pageSize: 5 })
  const { data: targetRows = [] } = useTargetStatus({ isActive: true })
  const { data: perfResult = [], isLoading: perfLoading } = useRepPerformance({
    periodFrom: monthStart, periodTo: today,
  })

  const activities = actResult?.data ?? []

  // KPIs from performance data (aggregate)
  const totalVisits   = perfResult.reduce((s: number, r: any) => s + (r.visits_count ?? 0), 0)
  const totalCalls    = perfResult.reduce((s: number, r: any) => s + (r.calls_count ?? 0), 0)
  const totalSales    = perfResult.reduce((s: number, r: any) => s + (r.sales_value ?? 0), 0)
  const totalCollect  = perfResult.reduce((s: number, r: any) => s + (r.collection_value ?? 0), 0)

  // أفضل وأضعف مندوب
  const sorted = [...perfResult].sort((a: any, b: any) => b.sales_value - a.sales_value)
  const topRep = sorted[0]
  const lowRep = sorted[sorted.length - 1]

  // أهداف الشركة
  const companyTargets = targetRows.filter(t => t.scope === 'company')
  const atRisk         = targetRows.filter(t => t.trend === 'behind' || t.trend === 'at_risk')

  return (
    <div>
      {/* ── KPI Cards ── */}
      <div className="mgr-kpi-grid">
        {[
          { icon: <MapPin size={20} />, value: totalVisits.toLocaleString('ar-EG'), label: 'زيارات الشهر', color: 'primary' },
          { icon: <Phone size={20} />, value: totalCalls.toLocaleString('ar-EG'), label: 'مكالمات الشهر', color: 'success' },
          { icon: <BarChart3 size={20} />, value: totalSales > 0 ? `${(totalSales/1000).toFixed(1)}ك` : '—', label: 'مبيعات الشهر', color: 'warning' },
          { icon: <Target size={20} />, value: totalCollect > 0 ? `${(totalCollect/1000).toFixed(1)}ك` : '—', label: 'تحصيلات الشهر', color: 'target' },
        ].map((kpi, i) => (
          <div key={i} className={`mgr-kpi-card mgr-kpi-card--${kpi.color}`}>
            <div className="mgr-kpi-icon">{kpi.icon}</div>
            <div className="mgr-kpi-value">{kpi.value}</div>
            <div className="mgr-kpi-label">{kpi.label}</div>
          </div>
        ))}
      </div>

      {/* ── At-Risk Alert ── */}
      {atRisk.length > 0 && (
        <div className="sup-alert sup-alert--danger mb-4">
          <AlertCircle size={16} />
          <span>{atRisk.length} هدف في خطر أو متأخر</span>
          <button className="sup-alert-link" onClick={() => navigate('/activities/targets')}>مراجعة</button>
        </div>
      )}

      {/* ── Main Grid ── */}
      <div className="act-dash-grid">

        {/* Company Targets */}
        <section className="edara-card act-dash-section">
          <div className="act-dash-section-header">
            <div className="act-dash-section-title"><TrendingUp size={16} /><span>أهداف الشركة</span></div>
            <button className="act-dash-view-all" onClick={() => navigate('/activities/targets')}>الكل</button>
          </div>
          {companyTargets.length === 0 ? (
            <p className="text-sm text-muted text-center p-4">
              لا توجد أهداف على مستوى الشركة
            </p>
          ) : (
            <div className="act-dash-targets">
              {companyTargets.slice(0, 3).map(row => {
                const { target, progress } = adaptTargetStatus(row)
                return (
                  <TargetProgressWidget
                    key={row.id} target={target} progress={progress} compact
                    onClick={() => navigate(`/activities/targets/${row.id}`)}
                  />
                )
              })}
            </div>
          )}
        </section>

        {/* Top/Low reps + Recent Activity */}
        <div className="flex flex-col gap-4">
          {/* Top performers */}
          {perfResult.length > 0 && (
            <section className="edara-card act-dash-section">
              <div className="act-dash-section-header">
                <div className="act-dash-section-title"><Users size={16} /><span>الأداء الشهري</span></div>
              </div>
              {perfLoading ? (
                <div className="skeleton h-20 rounded-md" />
              ) : (
                <div className="flex flex-col gap-2">
                  {topRep && (
                    <div className="mgr-rep-highlight mgr-rep-highlight--top">
                      <span>🏆</span>
                      <div>
                        <div className="font-bold text-sm">{topRep.employee_name}</div>
                        <div className="text-xs text-muted">
                          مبيعات: {topRep.sales_value?.toLocaleString('ar-EG', { maximumFractionDigits: 0 }) ?? '—'}
                        </div>
                      </div>
                    </div>
                  )}
                  {lowRep && lowRep.employee_id !== topRep?.employee_id && sorted.length > 1 && (
                    <div className="mgr-rep-highlight mgr-rep-highlight--low">
                      <span>⚠</span>
                      <div>
                        <div className="font-semibold text-sm">{lowRep.employee_name}</div>
                        <div className="text-xs text-muted">
                          يحتاج متابعة
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              )}
            </section>
          )}

          {/* Recent Activities */}
          <section className="edara-card act-dash-section">
            <div className="act-dash-section-header">
              <div className="act-dash-section-title"><Calendar size={16} /><span>آخر الأنشطة</span></div>
              <button className="act-dash-view-all" onClick={() => navigate('/activities/list')}>الكل</button>
            </div>
            <ActivityTimeline activities={activities} loading={false} limit={5} />
          </section>
        </div>
      </div>
    </div>
  )
}

// ══════════════════════════════════════════════════════
// MAIN — يحدد اللوحة حسب الدور
// ══════════════════════════════════════════════════════
export default function ActivitiesDashboard() {
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  // تحديد المستوى
  const isManager    = can(PERMISSIONS.TARGETS_READ_ALL) || can(PERMISSIONS.ACTIVITIES_READ_ALL)
  const isSupervisor = !isManager && (can(PERMISSIONS.VISIT_PLANS_READ_TEAM) || can(PERMISSIONS.ACTIVITIES_READ_TEAM))
  const canCreate    = can(PERMISSIONS.ACTIVITIES_CREATE)

  const dashboardTitle = isManager ? 'لوحة الإدارة' : isSupervisor ? 'لوحة المشرف' : 'لوحتي'
  const dashboardSub   = new Date().toLocaleDateString('ar-EG', { weekday: 'long', day: 'numeric', month: 'long' })

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title={dashboardTitle}
        subtitle={dashboardSub}
        actions={canCreate && !isManager ? (
          <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/new')} className="desktop-only-btn">
            نشاط جديد
          </Button>
        ) : undefined}
      />

      {isManager   ? <ManagerDashboard />    :
       isSupervisor ? <SupervisorDashboard /> :
       <RepDashboard />}

      <style>{`
        /* ── Greeting (Rep) ── */
        .rep-greeting {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          margin-bottom: var(--space-4);
          padding: var(--space-4);
          background: linear-gradient(135deg, var(--color-primary-light), var(--bg-surface));
          border-radius: var(--radius-lg);
          border: 1px solid var(--color-primary);
        }
        .rep-greeting-emoji { font-size: 28px; }
        .rep-greeting-name { font-weight: 700; font-size: var(--text-base); color: var(--text-primary); }
        .rep-greeting-date { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }

        /* ── Summary Cards ── */
        .act-dash-summary {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
          gap: var(--space-3);
          margin-bottom: var(--space-5);
        }
        .act-dash-stat {
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg);
          padding: var(--space-4);
          display: flex; align-items: flex-start; gap: var(--space-3);
          cursor: pointer; transition: box-shadow var(--transition-fast), transform var(--transition-fast);
          position: relative;
        }
        .act-dash-stat:hover { box-shadow: var(--shadow-md); transform: translateY(-1px); }
        .act-dash-stat-icon {
          width: 44px; height: 44px; border-radius: var(--radius-md);
          display: flex; align-items: center; justify-content: center; flex-shrink: 0;
        }
        .act-dash-stat--visit .act-dash-stat-icon   { background: var(--color-primary-light); color: var(--color-primary); }
        .act-dash-stat--call .act-dash-stat-icon    { background: var(--color-success-light); color: var(--color-success); }
        .act-dash-stat--activity .act-dash-stat-icon{ background: var(--color-warning-light); color: var(--color-warning); }
        .act-dash-stat--target .act-dash-stat-icon  { background: rgba(139,92,246,0.1); color: #7c3aed; }
        .act-dash-stat-body { flex: 1; }
        .act-dash-stat-value { font-size: var(--text-xl); font-weight: 700; color: var(--text-primary); line-height: 1.2; }
        .act-dash-stat-value span { font-size: var(--text-base); color: var(--text-muted); font-weight: 400; }
        .act-dash-stat-label { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }
        .act-dash-stat-sub { display: flex; align-items: center; gap: var(--space-2); margin-top: var(--space-1); flex-wrap: wrap; }
        .act-dash-stat-pending { font-size: 10px; color: var(--color-warning); font-weight: 600; }
        .act-dash-stat-arrow { position: absolute; left: var(--space-3); top: 50%; transform: translateY(-50%); color: var(--text-muted); opacity: 0.6; }

        /* ── Grid ── */
        .act-dash-grid { display: grid; grid-template-columns: 1fr 1.4fr; gap: var(--space-4); }
        .act-dash-grid--rep { grid-template-columns: 1fr 1.4fr; }
        @media (max-width: 900px) {
          .act-dash-grid { grid-template-columns: 1fr; }
          .act-dash-grid--rep { grid-template-columns: 1fr; }
        }

        /* ── Section ── */
        .act-dash-section { padding: var(--space-4); }
        .act-dash-section-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: var(--space-3); }
        .act-dash-section-title { display: flex; align-items: center; gap: var(--space-2); font-size: var(--text-sm); font-weight: 700; color: var(--text-primary); }
        .act-dash-view-all { border: none; background: none; cursor: pointer; font-size: var(--text-xs); color: var(--color-primary); font-weight: 600; padding: var(--space-1) var(--space-2); border-radius: var(--radius-sm); transition: background var(--transition-fast); }
        .act-dash-view-all:hover { background: var(--color-primary-light); }
        .act-dash-targets { display: flex; flex-direction: column; gap: var(--space-3); }

        /* ── Plan buttons ── */
        .act-dash-plan-btns { display: flex; flex-direction: column; gap: var(--space-2); }
        .act-dash-plan-btn {
          display: flex; align-items: center; gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          background: var(--bg-surface-2); border: 1px solid var(--border-primary);
          border-radius: var(--radius-md); cursor: pointer; text-align: right;
          transition: background var(--transition-fast), box-shadow var(--transition-fast);
          width: 100%; position: relative;
        }
        .act-dash-plan-btn:hover { background: var(--bg-hover); box-shadow: var(--shadow-sm); }
        .act-dash-plan-icon { flex-shrink: 0; }
        .act-dash-plan-icon--visit { color: var(--color-primary); }
        .act-dash-plan-icon--call  { color: var(--color-success); }
        .act-dash-plan-btn-title { font-size: var(--text-sm); font-weight: 600; color: var(--text-primary); }
        .act-dash-plan-btn-sub { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }

        /* ── Supervisor Alerts ── */
        .sup-alerts { display: flex; flex-direction: column; gap: var(--space-2); margin-bottom: var(--space-4); }
        .sup-alert {
          display: flex; align-items: center; gap: var(--space-2);
          padding: var(--space-3) var(--space-4);
          border-radius: var(--radius-md); border: 1px solid;
          font-size: var(--text-sm); font-weight: 600;
        }
        .sup-alert--warning { background: var(--color-warning-light); border-color: var(--color-warning); color: var(--color-warning); }
        .sup-alert--danger  { background: var(--color-danger-light); border-color: var(--color-danger); color: var(--color-danger); }
        .sup-alert--info    { background: var(--color-primary-light); border-color: var(--color-primary); color: var(--color-primary); }
        .sup-alert-link { margin-inline-start: auto; background: none; border: none; cursor: pointer; font-weight: 700; font-size: var(--text-xs); text-decoration: underline; color: inherit; }

        /* ── Supervisor Performance Table ── */
        .sup-perf-table { display: flex; flex-direction: column; gap: 0; font-size: var(--text-sm); }
        .sup-perf-header {
          display: grid; grid-template-columns: 2fr 1fr 1fr 1.5fr 1fr;
          gap: var(--space-2); padding: var(--space-2) var(--space-3);
          font-size: var(--text-xs); font-weight: 700; color: var(--text-muted);
          text-transform: uppercase; letter-spacing: 0.04em;
          border-bottom: 2px solid var(--border-primary);
        }
        .sup-perf-row {
          display: grid; grid-template-columns: 2fr 1fr 1fr 1.5fr 1fr;
          gap: var(--space-2); padding: var(--space-3);
          border-bottom: 1px solid var(--border-primary);
          align-items: center;
          transition: background var(--transition-fast);
        }
        .sup-perf-row:hover { background: var(--bg-hover); }
        .sup-perf-name { font-weight: 600; color: var(--text-primary); }
        .sup-perf-cell { color: var(--text-secondary); display: flex; flex-direction: column; gap: 3px; }
        .sup-perf-mini-bar {
          height: 4px; background: var(--bg-surface-2); border-radius: 99;
          overflow: hidden; margin-top: 2px;
        }
        .sup-perf-mini-bar > div { height: 100%; border-radius: 99; transition: width 0.4s ease; }
        @media (max-width: 600px) {
          .sup-perf-header, .sup-perf-row { grid-template-columns: 2fr 1fr 1fr; }
          .sup-perf-header span:nth-child(4), .sup-perf-row > *:nth-child(4),
          .sup-perf-header span:nth-child(5), .sup-perf-row > *:nth-child(5) { display: none; }
        }

        /* ── Manager KPI Grid ── */
        .mgr-kpi-grid {
          display: grid; grid-template-columns: repeat(4, 1fr);
          gap: var(--space-3); margin-bottom: var(--space-5);
        }
        .mgr-kpi-card {
          padding: var(--space-4); border-radius: var(--radius-lg);
          border: 1px solid; text-align: center;
          transition: box-shadow var(--transition-fast);
        }
        .mgr-kpi-card:hover { box-shadow: var(--shadow-md); }
        .mgr-kpi-card--primary { background: var(--color-primary-light); border-color: var(--color-primary); color: var(--color-primary); }
        .mgr-kpi-card--success { background: var(--color-success-light); border-color: var(--color-success); color: var(--color-success); }
        .mgr-kpi-card--warning { background: var(--color-warning-light); border-color: var(--color-warning); color: var(--color-warning); }
        .mgr-kpi-card--target  { background: rgba(139,92,246,0.1); border-color: rgba(139,92,246,0.3); color: #7c3aed; }
        .mgr-kpi-icon { display: flex; justify-content: center; margin-bottom: var(--space-2); }
        .mgr-kpi-value { font-size: var(--text-2xl); font-weight: 800; line-height: 1.1; }
        .mgr-kpi-label { font-size: var(--text-xs); margin-top: var(--space-1); opacity: 0.8; }
        @media (max-width: 600px) { .mgr-kpi-grid { grid-template-columns: 1fr 1fr; } }

        /* ── Rep highlights (Manager) ── */
        .mgr-rep-highlight {
          display: flex; align-items: center; gap: var(--space-3);
          padding: var(--space-3); border-radius: var(--radius-md); border: 1px solid;
        }
        .mgr-rep-highlight--top { background: var(--color-success-light); border-color: var(--color-success); }
        .mgr-rep-highlight--low { background: var(--color-warning-light); border-color: var(--color-warning); }
        .mgr-rep-highlight > span { font-size: 20px; }
      `}</style>
    </div>
  )
}
