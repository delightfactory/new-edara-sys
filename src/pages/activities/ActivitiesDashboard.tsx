import { useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Activity, MapPin, Phone, Target, Calendar, TrendingUp,
  Plus, ChevronLeft,
} from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import {
  useActivities,
  usePlanDailySummary,
  useTargetStatus,
  useActivityTypes,
} from '@/hooks/useQueryHooks'
import { PERMISSIONS } from '@/lib/permissions/constants'
import PageHeader from '@/components/shared/PageHeader'
import ActivityTimeline from '@/components/shared/ActivityTimeline'
import TargetProgressWidget from '@/components/shared/TargetProgressWidget'
import ActivityStatusBadge from '@/components/shared/ActivityStatusBadge'
import Button from '@/components/ui/Button'
import type { Target as TargetRow, TargetProgress, TargetStatusRow } from '@/lib/types/activities'

// ── الحصول على تاريخ اليوم بصيغة DATE ────────────────────────
function todayStr() {
  return new Date().toISOString().slice(0, 10)
}

// تحويل TargetStatusRow إلى Target + TargetProgress (لـ TargetProgressWidget)
function adaptTargetStatus(row: TargetStatusRow): {
  target: TargetRow
  progress: TargetProgress | null
} {
  const target: TargetRow = {
    id: row.id,
    type_id: '',
    type_code: row.type_code,
    name: row.name,
    description: null,
    scope: row.scope,
    scope_id: row.scope_id,
    period: 'custom',
    period_start: row.period_start,
    period_end: row.period_end,
    target_value: row.target_value,
    min_value: row.min_value,
    stretch_value: row.stretch_value,
    product_id: null,
    category_id: null,
    governorate_id: null,
    city_id: null,
    area_id: null,
    dormancy_days: null,
    filter_criteria: {},
    parent_target_id: null,
    auto_split: false,
    split_basis: null,
    is_paused: row.is_paused,
    paused_at: null,
    paused_reason: null,
    assigned_by: '',
    is_active: row.is_active,
    notes: null,
    created_at: '',
    updated_at: '',
  }
  const progress: TargetProgress | null = row.achieved_value != null ? {
    id: '',
    target_id: row.id,
    snapshot_date: row.data_as_of ?? todayStr(),
    achieved_value: row.achieved_value,
    achievement_pct: row.achievement_pct ?? 0,
    trend: row.trend,
    last_calc_at: row.last_calc_at,
    calc_details: {},
  } : null
  return { target, progress }
}

export default function ActivitiesDashboard() {
  const navigate  = useNavigate()
  const can       = useAuthStore(s => s.can)
  const today     = todayStr()

  const { data: actResult, isLoading: actLoading } = useActivities({
    dateFrom: today,
    dateTo:   today,
    pageSize: 10,
  })
  const activities = actResult?.data ?? []

  const { data: planSummaries = [], isLoading: plansLoading } = usePlanDailySummary({
    date: today,
  })

  const { data: targetRows = [], isLoading: targetsLoading } = useTargetStatus({
    isActive: true,
  })
  const { data: activityTypes = [] } = useActivityTypes()

  // ملخص خطط اليوم
  const visitPlan = planSummaries.find(p => p.plan_module === 'visit')
  const callPlan  = planSummaries.find(p => p.plan_module === 'call')

  // أهداف اليوم - أول 4 فقط في الـ Dashboard
  const topTargets = useMemo(() => targetRows.slice(0, 4), [targetRows])

  const canCreateActivity = can(PERMISSIONS.ACTIVITIES_CREATE)
  const canReadPlans      = can(PERMISSIONS.VISIT_PLANS_READ_TEAM) || can(PERMISSIONS.VISIT_PLANS_READ_ALL)
  const canReadTargets    = can(PERMISSIONS.TARGETS_READ_TEAM) || can(PERMISSIONS.TARGETS_READ_ALL)

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="لوحة الأنشطة الميدانية"
        subtitle={`اليوم • ${new Date().toLocaleDateString('ar-EG', { weekday: 'long', day: 'numeric', month: 'long' })}`}
        actions={canCreateActivity ? (
          <Button
            icon={<Plus size={16} />}
            onClick={() => navigate('/activities/new')}
            className="desktop-only-btn"
          >
            نشاط جديد
          </Button>
        ) : undefined}
      />

      {/* ── Summary Cards ──────────────────────────────────────── */}
      <div className="act-dash-summary">
        {/* زيارات اليوم */}
        <div className="act-dash-stat act-dash-stat--visit" onClick={() => canReadPlans && navigate('/activities/visit-plans')}>
          <div className="act-dash-stat-icon">
            <MapPin size={22} />
          </div>
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
          {canReadPlans && <ChevronLeft size={14} className="act-dash-stat-arrow" />}
        </div>

        {/* مكالمات اليوم */}
        <div className="act-dash-stat act-dash-stat--call" onClick={() => canReadPlans && navigate('/activities/call-plans')}>
          <div className="act-dash-stat-icon">
            <Phone size={22} />
          </div>
          <div className="act-dash-stat-body">
            <div className="act-dash-stat-value">
              {plansLoading ? '—' : callPlan ? (
                <>{callPlan.completed_count} <span>/ {callPlan.total_items}</span></>
              ) : '—'}
            </div>
            <div className="act-dash-stat-label">مكالمات اليوم</div>
            {callPlan && (
              <div className="act-dash-stat-sub">
                <ActivityStatusBadge planStatus={callPlan.plan_status} size="sm" />
              </div>
            )}
          </div>
          {canReadPlans && <ChevronLeft size={14} className="act-dash-stat-arrow" />}
        </div>

        {/* الأنشطة المنجزة */}
        <div className="act-dash-stat act-dash-stat--activity" onClick={() => navigate('/activities/list')}>
          <div className="act-dash-stat-icon">
            <Activity size={22} />
          </div>
          <div className="act-dash-stat-body">
            <div className="act-dash-stat-value">
              {actLoading ? '—' : actResult?.count ?? 0}
            </div>
            <div className="act-dash-stat-label">أنشطة اليوم</div>
          </div>
          <ChevronLeft size={14} className="act-dash-stat-arrow" />
        </div>

        {/* الأهداف */}
        {canReadTargets && (
          <div className="act-dash-stat act-dash-stat--target" onClick={() => navigate('/activities/targets')}>
            <div className="act-dash-stat-icon">
              <Target size={22} />
            </div>
            <div className="act-dash-stat-body">
              <div className="act-dash-stat-value">
                {targetsLoading ? '—' : targetRows.length}
              </div>
              <div className="act-dash-stat-label">هدف نشط</div>
            </div>
            <ChevronLeft size={14} className="act-dash-stat-arrow" />
          </div>
        )}
      </div>

      {/* ── Main Grid ───────────────────────────────────────────── */}
      <div className="act-dash-grid">

        {/* ── Targets Column ──────────────────────────────────── */}
        {canReadTargets && topTargets.length > 0 && (
          <section className="edara-card act-dash-section">
            <div className="act-dash-section-header">
              <div className="act-dash-section-title">
                <TrendingUp size={16} />
                <span>الأهداف</span>
              </div>
              <button
                className="act-dash-view-all"
                onClick={() => navigate('/activities/targets')}
              >
                عرض الكل
              </button>
            </div>
            <div className="act-dash-targets">
              {targetsLoading ? (
                [1, 2].map(i => (
                  <div key={i} className="skeleton" style={{ height: 100, borderRadius: 'var(--radius-md)' }} />
                ))
              ) : (
                topTargets.map(row => {
                  const { target, progress } = adaptTargetStatus(row)
                  return (
                    <TargetProgressWidget
                      key={row.id}
                      target={target}
                      progress={progress}
                      compact
                      onClick={() => navigate(`/activities/targets/${row.id}`)}
                    />
                  )
                })
              )}
            </div>
          </section>
        )}

        {/* ── Timeline Column ──────────────────────────────────── */}
        <section className="edara-card act-dash-section">
          <div className="act-dash-section-header">
            <div className="act-dash-section-title">
              <Calendar size={16} />
              <span>أنشطة اليوم</span>
            </div>
            <button
              className="act-dash-view-all"
              onClick={() => navigate('/activities/list')}
            >
              الكل
            </button>
          </div>
          <ActivityTimeline
            activities={activities}
            loading={actLoading}
            limit={8}
          />
          {canCreateActivity && activities.length === 0 && !actLoading && (
            <div style={{ padding: 'var(--space-4)', textAlign: 'center' }}>
              <Button
                icon={<Plus size={16} />}
                onClick={() => navigate('/activities/new')}
                variant="secondary"
              >
                تسجيل نشاط جديد
              </Button>
            </div>
          )}
        </section>

        {/* ── Plans Quick Nav ──────────────────────────────────── */}
        {canReadPlans && (
          <section className="edara-card act-dash-section act-dash-section--plans">
            <div className="act-dash-section-header">
              <div className="act-dash-section-title">
                <Calendar size={16} />
                <span>خطط اليوم</span>
              </div>
            </div>
            <div className="act-dash-plan-btns">
              <button
                className="act-dash-plan-btn"
                onClick={() => navigate('/activities/visit-plans')}
              >
                <MapPin size={20} className="act-dash-plan-icon act-dash-plan-icon--visit" />
                <div>
                  <div className="act-dash-plan-btn-title">خطط الزيارات</div>
                  {visitPlan ? (
                    <div className="act-dash-plan-btn-sub">
                      {visitPlan.completed_count}/{visitPlan.total_items} مكتملة
                    </div>
                  ) : (
                    <div className="act-dash-plan-btn-sub">لا توجد خطة اليوم</div>
                  )}
                </div>
                <ChevronLeft size={16} className="act-dash-stat-arrow" />
              </button>
              <button
                className="act-dash-plan-btn"
                onClick={() => navigate('/activities/call-plans')}
              >
                <Phone size={20} className="act-dash-plan-icon act-dash-plan-icon--call" />
                <div>
                  <div className="act-dash-plan-btn-title">خطط المكالمات</div>
                  {callPlan ? (
                    <div className="act-dash-plan-btn-sub">
                      {callPlan.completed_count}/{callPlan.total_items} مكتملة
                    </div>
                  ) : (
                    <div className="act-dash-plan-btn-sub">لا توجد خطة اليوم</div>
                  )}
                </div>
                <ChevronLeft size={16} className="act-dash-stat-arrow" />
              </button>
            </div>
          </section>
        )}
      </div>

      <style>{`
        /* ── Summary Cards ─────────────────────────────────── */
        .act-dash-summary {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
          gap: var(--space-3);
          margin-bottom: var(--space-5);
        }
        .act-dash-stat {
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg);
          padding: var(--space-4);
          display: flex;
          align-items: flex-start;
          gap: var(--space-3);
          cursor: pointer;
          transition: box-shadow var(--transition-fast), transform var(--transition-fast);
          position: relative;
        }
        .act-dash-stat:hover {
          box-shadow: var(--shadow-md);
          transform: translateY(-1px);
        }
        .act-dash-stat-icon {
          width: 44px; height: 44px;
          border-radius: var(--radius-md);
          display: flex; align-items: center; justify-content: center;
          flex-shrink: 0;
        }
        .act-dash-stat--visit .act-dash-stat-icon  { background: var(--color-primary-light); color: var(--color-primary); }
        .act-dash-stat--call .act-dash-stat-icon   { background: var(--color-success-light); color: var(--color-success); }
        .act-dash-stat--activity .act-dash-stat-icon { background: var(--color-warning-light); color: var(--color-warning); }
        .act-dash-stat--target .act-dash-stat-icon { background: rgba(139,92,246,0.1); color: #7c3aed; }
        .act-dash-stat-body { flex: 1; }
        .act-dash-stat-value {
          font-size: var(--text-xl);
          font-weight: 700;
          color: var(--text-primary);
          line-height: 1.2;
        }
        .act-dash-stat-value span {
          font-size: var(--text-base);
          color: var(--text-muted);
          font-weight: 400;
        }
        .act-dash-stat-label {
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-top: 2px;
        }
        .act-dash-stat-sub {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          margin-top: var(--space-1);
          flex-wrap: wrap;
        }
        .act-dash-stat-pending {
          font-size: 10px;
          color: var(--color-warning);
          font-weight: 600;
        }
        .act-dash-stat-arrow {
          position: absolute;
          left: var(--space-3);
          top: 50%;
          transform: translateY(-50%);
          color: var(--text-muted);
          opacity: 0.6;
        }

        /* ── Grid ─────────────────────────────────────────── */
        .act-dash-grid {
          display: grid;
          grid-template-columns: 1fr 1.4fr;
          gap: var(--space-4);
        }
        @media (max-width: 900px) {
          .act-dash-grid { grid-template-columns: 1fr; }
          .act-dash-section--plans { order: -1; }
        }

        /* ── Section ─────────────────────────────────────── */
        .act-dash-section { padding: var(--space-4); }
        .act-dash-section-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: var(--space-3);
        }
        .act-dash-section-title {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          font-size: var(--text-sm);
          font-weight: 700;
          color: var(--text-primary);
        }
        .act-dash-view-all {
          border: none; background: none; cursor: pointer;
          font-size: var(--text-xs);
          color: var(--color-primary);
          font-weight: 600;
          padding: var(--space-1) var(--space-2);
          border-radius: var(--radius-sm);
          transition: background var(--transition-fast);
        }
        .act-dash-view-all:hover { background: var(--color-primary-light); }

        /* ── Targets ─────────────────────────────────────── */
        .act-dash-targets { display: flex; flex-direction: column; gap: var(--space-3); }

        /* ── Plan Buttons ─────────────────────────────────── */
        .act-dash-plan-btns { display: flex; flex-direction: column; gap: var(--space-2); }
        .act-dash-plan-btn {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          background: var(--bg-surface-2);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-md);
          cursor: pointer;
          text-align: right;
          transition: background var(--transition-fast), box-shadow var(--transition-fast);
          width: 100%;
          position: relative;
        }
        .act-dash-plan-btn:hover {
          background: var(--bg-hover);
          box-shadow: var(--shadow-sm);
        }
        .act-dash-plan-icon { flex-shrink: 0; }
        .act-dash-plan-icon--visit { color: var(--color-primary); }
        .act-dash-plan-icon--call  { color: var(--color-success); }
        .act-dash-plan-btn-title {
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
        }
        .act-dash-plan-btn-sub {
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-top: 2px;
        }
      `}</style>
    </div>
  )
}
