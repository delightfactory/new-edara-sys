import { useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  AlertTriangle, ArrowLeft, Building2, ChevronLeft, CircleGauge, RefreshCw,
  Target, TrendingUp, Trophy, Users,
} from 'lucide-react'
import { useTargets, useTargetEmployeeContributions } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { formatCurrency, formatNumber, formatPercent } from '@/lib/utils/format'
import { toLocalISODate } from '@/lib/utils/date'
import type { Target as TargetModel, TargetUnit } from '@/lib/types/activities'
import './GoalCommandCenter.css'

const CONTRIBUTION_TYPES = new Set([
  'sales_value', 'collection', 'visits_count', 'calls_count',
  'new_customers', 'product_qty',
])

const SCOPE_LABELS: Record<TargetModel['scope'], string> = {
  company: 'الشركة',
  branch: 'الفرع',
  department: 'القسم',
  individual: 'هدف فردي',
}

function progressOf(target: TargetModel) {
  return target.latest_progress ?? null
}

function formatTargetValue(value: number, unit: TargetUnit | undefined) {
  if (unit === 'currency') return `${formatCurrency(value)} ج.م`
  if (unit === 'percent') return formatPercent(value)
  return formatNumber(value)
}

function targetUnit(target: TargetModel): TargetUnit {
  return target.target_type?.unit ?? 'currency'
}

function expectedPct(target: TargetModel) {
  const stored = Number(progressOf(target)?.calc_details?.expected_pct)
  if (Number.isFinite(stored)) return Math.min(Math.max(stored, 0), 100)

  const dayMs = 24 * 60 * 60 * 1000
  const start = new Date(`${target.period_start}T00:00:00`).getTime()
  const end = new Date(`${target.period_end}T00:00:00`).getTime()
  const today = new Date(`${toLocalISODate(new Date())}T00:00:00`).getTime()
  const boundedToday = Math.min(Math.max(today, start), end)
  const daysElapsed = Math.floor((boundedToday - start) / dayMs) + 1
  const totalDays = Math.floor((end - start) / dayMs) + 1
  return Math.min((daysElapsed / Math.max(totalDays, 1)) * 100, 100)
}

function statusOf(target: TargetModel) {
  const pct = Number(progressOf(target)?.achievement_pct ?? 0)
  const expected = expectedPct(target)
  if (pct >= 100) return { label: 'تم التحقيق', tone: 'success' as const }
  if (pct + 10 < expected) return { label: 'يحتاج تدخلاً', tone: 'danger' as const }
  if (pct < expected) return { label: 'يحتاج متابعة', tone: 'warning' as const }
  return { label: 'على المسار', tone: 'success' as const }
}

function riskGap(target: TargetModel) {
  const pct = Number(progressOf(target)?.achievement_pct ?? 0)
  return pct - expectedPct(target)
}

function commandCenterOrder(a: TargetModel, b: TargetModel) {
  // الهدف العام للمبيعات هو مرساة لوحة القيادة عند وجوده، ثم تأتي
  // الأهداف الأخرى مرتبة حسب حاجتها للتدخل.
  const isGeneralSales = (target: TargetModel) =>
    target.type_code === 'sales_value' && !target.product_id && !target.category_id
  const anchorDifference = Number(isGeneralSales(b)) - Number(isGeneralSales(a))
  if (anchorDifference !== 0) return anchorDifference
  return riskGap(a) - riskGap(b)
}

function GoalSkeleton() {
  return (
    <section className="gcc-shell edara-card" aria-label="جارٍ تحميل متابعة الأهداف">
      <div className="gcc-skeleton-line skeleton" />
      <div className="gcc-skeleton-hero skeleton" />
      <div className="gcc-skeleton-line gcc-skeleton-line--short skeleton" />
    </section>
  )
}

function EmptyGoals({ onOpen }: { onOpen: () => void }) {
  return (
    <section className="gcc-shell edara-card gcc-empty" aria-labelledby="gcc-title">
      <div className="gcc-empty-icon"><Target size={25} /></div>
      <div>
        <h2 id="gcc-title">متابعة الأهداف</h2>
        <p>لا توجد أهداف جارية مخصّصة لك أو لفريقك اليوم.</p>
      </div>
      <button type="button" className="gcc-text-button" onClick={onOpen}>
        سجل الأهداف <ChevronLeft size={16} aria-hidden="true" />
      </button>
    </section>
  )
}

function GoalsError({ onRetry }: { onRetry: () => void }) {
  return (
    <section className="gcc-shell edara-card gcc-error" role="alert" aria-labelledby="gcc-error-title">
      <div className="gcc-error-icon"><AlertTriangle size={23} /></div>
      <div>
        <h2 id="gcc-error-title">تعذّر تحميل الأهداف</h2>
        <p>لم نستطع تحديث لوحة المتابعة الآن. بيانات أهدافك لم تختفِ.</p>
      </div>
      <button type="button" className="gcc-retry-button" onClick={onRetry}>
        <RefreshCw size={16} aria-hidden="true" /> إعادة المحاولة
      </button>
    </section>
  )
}

export default function GoalCommandCenter() {
  const navigate = useNavigate()
  const can = useAuthStore(state => state.can)
  const today = toLocalISODate(new Date())
  const { data, isLoading, isError, refetch } = useTargets({
    is_active: true,
    is_paused: false,
    active_on: today,
    include_tiers: true,
  }, { page: 1, pageSize: 30 })

  const targets = useMemo(
    () => [...(data?.data ?? [])].sort(commandCenterOrder),
    [data?.data]
  )
  const primary = targets[0]
  const canReadCompanyDetails = can('targets.read_all')
  const canLoadContributions = !!primary
    && primary.scope !== 'individual'
    && CONTRIBUTION_TYPES.has(primary.type_code)
    && (primary.scope !== 'company' || canReadCompanyDetails)
  const {
    data: contributions = [],
    isLoading: loadingContributions,
    isError: contributionsError,
    refetch: refetchContributions,
  } =
    useTargetEmployeeContributions(primary?.id, canLoadContributions, today)

  if (isLoading) return <GoalSkeleton />
  if (isError && !primary) return <GoalsError onRetry={() => void refetch()} />
  if (!primary) return <EmptyGoals onOpen={() => navigate('/activities/targets')} />

  const progress = progressOf(primary)
  const pct = Number(progress?.achievement_pct ?? 0)
  const ringPct = Math.min(Math.max(pct, 0), 100)
  const expected = expectedPct(primary)
  const achieved = Number(progress?.achieved_value ?? 0)
  const remaining = Math.max(Number(primary.target_value) - achieved, 0)
  const status = statusOf(primary)
  const unit = targetUnit(primary)
  const topContributors = contributions.slice(0, 5)

  return (
    <section className="gcc-shell edara-card" aria-labelledby="gcc-title">
      <header className="gcc-head">
        <div className="gcc-heading-copy">
          <span className="gcc-heading-icon"><CircleGauge size={18} /></span>
          <div>
            <h2 id="gcc-title">مركز متابعة الأهداف</h2>
            <p>صورتك المباشرة للتقدم اليوم</p>
          </div>
        </div>
        <button type="button" className="gcc-view-all" onClick={() => navigate('/activities/targets')}>
          كل الأهداف <ArrowLeft size={16} aria-hidden="true" />
        </button>
      </header>

      {isError && (
        <div className="gcc-notice" role="status">
          تعذّر تحديث بعض بيانات الأهداف الآن، أعد فتح الصفحة للمحاولة مرة أخرى.
        </div>
      )}

      <article className="gcc-hero">
        <button
          type="button"
          className="gcc-hero-action"
          onClick={() => navigate(`/activities/targets/${primary.id}`)}
          aria-label={`فتح تفاصيل هدف ${primary.name}`}
        />
        <div className="gcc-hero-top">
          <div className="gcc-goal-copy">
            <div className="gcc-badges">
              <span className="gcc-scope-badge">
                {primary.scope === 'department' ? <Users size={13} /> : <Building2 size={13} />}
                {SCOPE_LABELS[primary.scope]}
              </span>
              <span className={`gcc-status gcc-status--${status.tone}`}>{status.label}</span>
            </div>
            <h3>{primary.name}</h3>
            <p>{primary.target_type?.name ?? 'هدف أداء'} · حتى {new Date(`${primary.period_end}T00:00:00`).toLocaleDateString('ar-EG-u-nu-latn', { day: 'numeric', month: 'short' })}</p>
          </div>
          <div
            className="gcc-ring"
            style={{ '--gcc-progress': `${ringPct * 3.6}deg` } as React.CSSProperties}
            aria-label={`نسبة الإنجاز ${formatPercent(pct)}`}
          >
            <span>{formatPercent(pct)}</span>
            <small>منجز</small>
          </div>
        </div>

        <div className="gcc-metrics">
          <div><span>المحقق</span><strong>{formatTargetValue(achieved, unit)}</strong></div>
          <div><span>المستهدف</span><strong>{formatTargetValue(Number(primary.target_value), unit)}</strong></div>
          <div><span>المتبقي</span><strong>{formatTargetValue(remaining, unit)}</strong></div>
        </div>

        <div className="gcc-pace">
          <div className="gcc-pace-labels">
            <span>التقدم الفعلي {formatPercent(pct)}</span>
            <span>المفترض اليوم {formatPercent(expected)}</span>
          </div>
          <div className="gcc-track" aria-hidden="true">
            <span className="gcc-track-fill" style={{ inlineSize: `${ringPct}%` }} />
            <i style={{ insetInlineStart: `${Math.min(expected, 100)}%` }} />
          </div>
        </div>
      </article>

      {targets.length > 1 && (
        <div className="gcc-goal-strip" aria-label="الأهداف الجارية الأخرى">
          {targets.slice(1, 5).map(target => {
            const targetPct = Number(progressOf(target)?.achievement_pct ?? 0)
            const targetStatus = statusOf(target)
            return (
              <button
                type="button"
                className="gcc-mini-goal"
                key={target.id}
                onClick={() => navigate(`/activities/targets/${target.id}`)}
              >
                <span className={`gcc-mini-dot gcc-mini-dot--${targetStatus.tone}`} />
                <span className="gcc-mini-copy">
                  <strong>{target.name}</strong>
                  <small>{SCOPE_LABELS[target.scope]}</small>
                </span>
                <b>{formatPercent(targetPct)}</b>
              </button>
            )
          })}
        </div>
      )}

      {canLoadContributions && (
        <div className="gcc-team" aria-labelledby="gcc-team-title">
          <div className="gcc-team-head">
            <div>
              <h3 id="gcc-team-title"><Trophy size={17} /> مساهمة الفريق</h3>
              <p>مساهمة كل عضو في الإنجاز الحالي للهدف</p>
            </div>
            <TrendingUp size={20} aria-hidden="true" />
          </div>
          {loadingContributions ? (
            <div className="gcc-contribution-skeleton skeleton" />
          ) : contributionsError ? (
            <div className="gcc-team-error" role="status">
              <span>تعذّر تحميل مساهمات الفريق.</span>
              <button type="button" onClick={() => void refetchContributions()}>
                <RefreshCw size={15} aria-hidden="true" /> إعادة المحاولة
              </button>
            </div>
          ) : topContributors.length > 0 ? (
            <div className="gcc-contributors">
              {topContributors.map(row => (
                <div className="gcc-contributor" key={row.employee_id}>
                  <span className="gcc-rank">{row.contribution_rank}</span>
                  <span className="gcc-avatar" aria-hidden="true">{row.employee_name.trim().charAt(0)}</span>
                  <div className="gcc-person">
                    <div><strong>{row.employee_name}</strong><span>{formatTargetValue(row.achieved_value, unit)}</span></div>
                    <div className="gcc-person-track"><span style={{ inlineSize: `${Math.min(Math.max(row.contribution_share_pct, 0), 100)}%` }} /></div>
                  </div>
                  <b>{formatPercent(row.contribution_share_pct)}</b>
                </div>
              ))}
            </div>
          ) : (
            <p className="gcc-team-empty">لم تُسجّل مساهمات على هذا الهدف حتى الآن.</p>
          )}
        </div>
      )}
    </section>
  )
}
