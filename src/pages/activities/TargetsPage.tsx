/**
 * TargetsPage — قائمة الأهداف
 *
 * وضعان:
 *  - Employee motivational view: لمن يملك read_own فقط بدون assign/read_team/read_all
 *  - Manager/Admin view: جدول إداري مع فلاتر متكاملة
 */
import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth-store'
import {
  useTargets, useTargetTypes, useBranches, useHREmployees,
} from '@/hooks/useQueryHooks'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { Target, Plus, Eye, Filter, X, Gift, TrendingUp } from 'lucide-react'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import PermissionGuard from '@/components/shared/PermissionGuard'
import Button from '@/components/ui/Button'
import ActivityStatusBadge from '@/components/shared/ActivityStatusBadge'
import EmployeeTargetCard from '@/components/targets/EmployeeTargetCard'
import { buildTargetListItems } from '@/lib/services/targets'
import type { Target as TargetRow, TargetScope, TargetPeriod, TargetFilters, TargetListItem } from '@/lib/types/activities'

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG-u-nu-latn', { day: 'numeric', month: 'short', year: 'numeric' })
}
function fmtNumber(n: number | null | undefined) {
  if (n == null || isNaN(Number(n))) return '—'
  return Number(n).toLocaleString('en-US', { maximumFractionDigits: 1 })
}

const SCOPE_AR: Record<TargetScope, string> = {
  company: 'الشركة', branch: 'الفرع', department: 'القسم', individual: 'فرد',
}
const PERIOD_AR: Record<TargetPeriod, string> = {
  monthly: 'شهري', quarterly: 'ربع سنوي', yearly: 'سنوي', custom: 'مخصص',
}

function getMonthRange(monthStr: string): { from: string; to: string } | null {
  if (!monthStr) return null
  const [y, m] = monthStr.split('-').map(Number)
  const from   = `${y}-${String(m).padStart(2, '0')}-01`
  const lastDay = new Date(y, m, 0).getDate()
  const to     = `${y}-${String(m).padStart(2, '0')}-${lastDay}`
  return { from, to }
}

export default function TargetsPage() {
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  // ── Permission-based mode decision
  const canAssign   = can(PERMISSIONS.TARGETS_ASSIGN)
  const canReadTeam = can(PERMISSIONS.TARGETS_READ_TEAM)
  const canReadAll  = can(PERMISSIONS.TARGETS_READ_ALL)
  const isManagerView = canAssign || canReadTeam || canReadAll

  // ── Filters (manager only)
  const [scope,       setScope]       = useState<TargetScope | ''>('')
  const [type_code,   setTypeCode]    = useState('')
  const [is_active,   setIsActive]    = useState<'true' | 'false' | ''>('true')
  const [branch_id,   setBranchId]    = useState('')
  const [employee_id, setEmployeeId]  = useState('')
  const [period_month, setPeriodMonth] = useState('')
  const [has_reward,  setHasReward]   = useState<'true' | 'false' | ''>('')
  const [auto_payout, setAutoPayout]  = useState<'true' | 'false' | ''>('')
  const [payout_status, setPayoutStatus] = useState<'' | 'pending' | 'committed' | 'cancelled'>('')
  const [showFilters, setShowFilters] = useState(false)
  const [page,        setPage]        = useState(1)

  const { data: targetTypes = [] } = useTargetTypes()
  const { data: branches = [] }    = useBranches()
  const { data: empRes }           = useHREmployees({ pageSize: 200 })
  const employees = useMemo(() => empRes?.data ?? [], [empRes])

  const monthRange = getMonthRange(period_month)

  const filters = useMemo<TargetFilters>(() => ({
    scope:       (scope as TargetScope) || undefined,
    type_code:   type_code || undefined,
    is_active:   is_active === '' ? undefined : is_active === 'true',
    branch_id:   branch_id   || undefined,
    employee_id: employee_id || undefined,
    date_from:   monthRange?.from || undefined,
    date_to:     monthRange?.to   || undefined,
    has_reward:    has_reward === '' ? undefined : has_reward === 'true',
    auto_payout:   auto_payout === '' ? undefined : auto_payout === 'true',
    payout_status: payout_status || undefined,
  }), [scope, type_code, is_active, branch_id, employee_id, monthRange?.from, monthRange?.to, has_reward, auto_payout, payout_status])

  // فلاتر وضع الموظف — include_tiers لحساب estimated_reward فعلياً
  const employeeFilters = useMemo<TargetFilters>(() => ({
    is_active: true,
    include_tiers: true,   // ينشّط حساب estimated_reward في الخدمة
  }), [])

  const pagination     = useMemo(() => ({ page, pageSize: isManagerView ? 25 : 50 }), [page, isManagerView])
  const activeFilters  = isManagerView ? filters : employeeFilters
  const { data: result, isLoading: loading } = useTargets(activeFilters, pagination)
  const targets    = result?.data     ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count    ?? 0

  // ── Employee view-model: تحويل Target[] → TargetListItem[] بحقول محسوبة
  // buildTargetListItems يحسب achieved_value / achievement_pct / current_tier_info / estimated_reward
  const employeeListItems = useMemo<TargetListItem[]>(
    () => isManagerView ? [] : buildTargetListItems(targets),
    [targets, isManagerView]
  )

  const activeFiltersCount = [scope, type_code, branch_id, employee_id, period_month, has_reward, auto_payout, payout_status]
    .filter(Boolean).length + (is_active !== 'true' ? 1 : 0)

  const clearFilters = () => {
    setScope(''); setTypeCode(''); setIsActive('true')
    setBranchId(''); setEmployeeId(''); setPeriodMonth('')
    setHasReward(''); setAutoPayout(''); setPayoutStatus(''); setPage(1)
  }

  // ── Employee Motivational View ────────────────────────────
  if (!isManagerView) {
    return (
      <div className="page-container animate-enter">
        <PageHeader
          title="أهدافي"
          subtitle={loading ? '...' : `${totalCount} هدف نشط`}
          breadcrumbs={[{ label: 'أهدافي' }]}
        />

        {loading ? (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: '16px' }}>
            {[1, 2, 3].map(i => (
              <div key={i} className="edara-card" style={{ padding: '20px' }}>
                {[80, 60, 40].map((w, j) => (
                  <div key={j} className="skeleton" style={{ height: 16, width: `${w}%`, marginBottom: '12px' }} />
                ))}
              </div>
            ))}
          </div>
        ) : targets.length === 0 ? (
          <div className="empty-state" style={{ padding: '64px 0' }}>
            <Target size={48} style={{ opacity: 0.3, marginBottom: '16px' }} />
            <p className="empty-state-title">لا توجد أهداف مُسندة إليك</p>
            <p className="empty-state-text">عندما يمنحك مديرك هدفاً، سيظهر هنا مع تقدمك وحوافزك.</p>
          </div>
        ) : (
          <div className="tg-emp-grid">
            {employeeListItems.map(t => (
              <EmployeeTargetCard
                key={t.id}
                target={t}
                onClick={() => navigate(`/activities/targets/${t.id}`)}
              />
            ))}
          </div>
        )}

        {/* Pagination للموظف إذا لديه أهداف كثيرة */}
        {totalPages > 1 && (
          <div style={{ display: 'flex', justifyContent: 'center', gap: '8px', marginTop: '24px' }}>
            <Button variant="secondary" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>السابق</Button>
            <span style={{ lineHeight: '36px', fontSize: '13px', color: 'var(--text-muted)' }}>{page} / {totalPages}</span>
            <Button variant="secondary" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>التالي</Button>
          </div>
        )}

        <style>{`
          .tg-emp-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: var(--space-4);
          }
          @media (max-width: 480px) {
            .tg-emp-grid { grid-template-columns: 1fr; }
          }
        `}</style>
      </div>
    )
  }

  // ── Manager / Admin View ────────────────────────────────
  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="الأهداف"
        subtitle={loading ? '...' : `${totalCount} هدف`}
        actions={
          <div className="flex gap-2">
            <Button
              variant="secondary"
              icon={<Filter size={14} />}
              onClick={() => setShowFilters(!showFilters)}
              className="tg-filter-toggle"
            >
              فلاتر
              {activeFiltersCount > 0 && (
                <span className="tg-filter-badge">{activeFiltersCount}</span>
              )}
            </Button>
            <PermissionGuard permission={PERMISSIONS.TARGETS_ASSIGN}>
              <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/targets/new')} className="desktop-only-btn">
                هدف جديد
              </Button>
            </PermissionGuard>
          </div>
        }
      />

      {/* ── Filters Panel ── */}
      <div className={`tg-filters${showFilters ? ' tg-filters--open' : ''}`}>
        <div className="tg-filters-inner">
          {/* Row 1: نوع + نطاق + حالة */}
          <div className="tg-filters-row">
            <select className="form-select tg-filter-select" value={type_code}
              onChange={e => { setTypeCode(e.target.value); setPage(1) }}>
              <option value="">كل الأنواع</option>
              {targetTypes.map(t => (
                <option key={t.id} value={t.code}>{t.name}</option>
              ))}
            </select>
            <select className="form-select tg-filter-select" value={scope}
              onChange={e => { setScope(e.target.value as TargetScope | ''); setPage(1) }}>
              <option value="">كل النطاقات</option>
              <option value="company">الشركة</option>
              <option value="branch">الفرع</option>
              <option value="department">القسم</option>
              <option value="individual">فرد</option>
            </select>
            <select className="form-select tg-filter-select" value={is_active}
              onChange={e => { setIsActive(e.target.value as 'true' | 'false' | ''); setPage(1) }}>
              <option value="true">نشط</option>
              <option value="false">غير نشط</option>
              <option value="">الكل</option>
            </select>
          </div>
          {/* Row 2: فرع + موظف + فترة */}
          <div className="tg-filters-row">
            <select className="form-select tg-filter-select" value={branch_id}
              onChange={e => { setBranchId(e.target.value); setPage(1) }}>
              <option value="">كل الفروع</option>
              {(branches as any[]).map((b: any) => (
                <option key={b.id} value={b.id}>{b.name}</option>
              ))}
            </select>
            <select className="form-select tg-filter-select" value={employee_id}
              onChange={e => { setEmployeeId(e.target.value); setPage(1) }}>
              <option value="">كل الموظفين</option>
              {employees.map((e: any) => (
                <option key={e.id} value={e.id}>{e.full_name}</option>
              ))}
            </select>
            <input type="month" className="form-input tg-filter-select" value={period_month}
              onChange={e => { setPeriodMonth(e.target.value); setPage(1) }}
              placeholder="الفترة" />
          </div>
          {/* Row 3: Phase 22 filters */}
          <div className="tg-filters-row">
            <select className="form-select tg-filter-select" value={has_reward}
              onChange={e => { setHasReward(e.target.value as any); setPage(1) }}>
              <option value="">كل الأهداف (بمكافأة وبدونها)</option>
              <option value="true">🎁 لديها مكافأة فقط</option>
              <option value="false">بدون مكافأة</option>
            </select>
            <select className="form-select tg-filter-select" value={auto_payout}
              onChange={e => { setAutoPayout(e.target.value as any); setPage(1) }}>
              <option value="">كل الصرف</option>
              <option value="true">صرف تلقائي مفعّل</option>
              <option value="false">صرف يدوي</option>
            </select>
            <select className="form-select tg-filter-select" value={payout_status}
              onChange={e => { setPayoutStatus(e.target.value as any); setPage(1) }}>
              <option value="">كل حالات الاستحقاق</option>
              <option value="committed">💰 مصروفة</option>
              <option value="pending">⏳ قيد الصرف</option>
              <option value="cancelled">✕ ملغية</option>
            </select>
          </div>
          {activeFiltersCount > 0 && (
            <button className="tg-clear-btn" onClick={clearFilters}>
              <X size={12} /> مسح كل الفلاتر
            </button>
          )}
        </div>
      </div>

      {/* ── Table ── */}
      <div className="tg-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<TargetRow>
          columns={[
            {
              key: 'name', label: 'الهدف',
              render: t => (
                <>
                  <div className="font-bold text-sm">{t.name}</div>
                  <div className="text-xs text-muted flex gap-2 mt-1">
                    <span>{t.target_type?.name ?? t.type_code}</span>
                    <span>•</span>
                    <span>{SCOPE_AR[t.scope]}</span>
                    {t.reward_type && <span style={{ color: 'var(--color-primary)' }}>• 🎁</span>}
                  </div>
                </>
              ),
            },
            {
              key: 'period', label: 'الفترة', hideOnMobile: true,
              render: t => (
                <>
                  <div className="text-sm">{PERIOD_AR[t.period]}</div>
                  <div className="text-xs text-muted">
                    {fmtDate(t.period_start)} — {fmtDate(t.period_end)}
                  </div>
                </>
              ),
            },
            {
              key: 'target_value', label: 'المستهدف',
              render: t => (
                <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>
                  {fmtNumber(t.target_value)}
                  <span style={{ fontSize: 11, color: 'var(--text-muted)', marginRight: 2 }}>
                    {t.target_type?.unit === 'currency' ? ' ج' : ''}
                  </span>
                </span>
              ),
            },
            {
              key: 'progress', label: 'الإنجاز',
              render: t => {
                // normalizeLatestProgress في الخدمة يضمن هذا، لكن نُضيف حماية إضافية هنا
                const rawProg = t.latest_progress
                const prog: typeof rawProg extends any[] ? never : typeof rawProg =
                  Array.isArray(rawProg) ? (rawProg.length > 0 ? rawProg[0] : null) : rawProg
                if (!prog) return <span className="text-muted text-xs">لم يُحسب</span>
                return (
                  <div>
                    <ActivityStatusBadge trend={prog.trend ?? undefined} size="sm" />
                    <div className="text-xs text-muted mt-1">
                      {fmtNumber(prog.achieved_value)} ({fmtNumber(prog.achievement_pct)}%)
                    </div>
                  </div>
                )
              },
            },
            {
              key: 'reward', label: 'المكافأة', hideOnMobile: true,
              render: t => {
                if (!t.reward_type) return <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>—</span>
                return (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
                    <span style={{ fontSize: '11px', fontWeight: 700, color: 'var(--color-primary)', display: 'flex', alignItems: 'center', gap: '4px' }}>
                      <Gift size={11} />
                      {t.reward_type === 'fixed' ? 'مقطوعة' : 'نسبية'}
                    </span>
                    {t.auto_payout && (
                      <span style={{ fontSize: '10px', color: 'var(--color-success)' }}>⚡ صرف تلقائي</span>
                    )}
                  </div>
                )
              },
            },
            {
              key: 'status', label: 'الحالة',
              render: t => (
                <span className={`text-xs font-bold ${t.is_paused ? 'text-warning' : t.is_active ? 'text-success' : 'text-muted'}`}>
                  {t.is_paused ? '⏸ موقوف' : t.is_active ? '● نشط' : '○ ملغى'}
                </span>
              ),
            },
            {
              key: 'actions', label: '', width: 60,
              render: t => (
                <div className="flex gap-1" onClick={e => e.stopPropagation()}>
                  <Button variant="ghost" size="sm" onClick={() => navigate(`/activities/targets/${t.id}`)}>
                    <Eye size={14} />
                  </Button>
                </div>
              ),
            },
          ]}
          data={targets}
          loading={loading}
          onRowClick={t => navigate(`/activities/targets/${t.id}`)}
          emptyIcon={<Target size={48} />}
          emptyTitle="لا توجد أهداف"
          emptyAction={
            <PermissionGuard permission={PERMISSIONS.TARGETS_ASSIGN}>
              <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/targets/new')}>هدف جديد</Button>
            </PermissionGuard>
          }
          page={page} totalPages={totalPages} totalCount={totalCount} onPageChange={setPage}
          dataCardMapping={t => {
            const prog = t.latest_progress
            return {
              title: t.name,
              subtitle: `${t.target_type?.name ?? t.type_code} • ${SCOPE_AR[t.scope]}`,
              badge: prog?.trend ? <ActivityStatusBadge trend={prog.trend} size="sm" /> : undefined,
              metadata: [
                { label: 'المستهدف', value: fmtNumber(t.target_value), highlight: true },
                { label: 'الفترة', value: PERIOD_AR[t.period] },
                ...(prog ? [{ label: 'الإنجاز', value: `${prog.achievement_pct.toFixed(0)}%` }] : []),
                { label: 'الحالة', value: t.is_paused ? '⏸ موقوف' : t.is_active ? '● نشط' : '○ ملغى' },
                ...(t.reward_type ? [{ label: 'مكافأة', value: t.reward_type === 'fixed' ? '🎁 مقطوعة' : '🎁 نسبية' }] : []),
              ],
              actions: (
                <Button variant="secondary" size="sm" onClick={() => navigate(`/activities/targets/${t.id}`)}
                  style={{ flex: 1, justifyContent: 'center' }}>
                  <Eye size={14} /> تفاصيل
                </Button>
              ),
              onClick: () => navigate(`/activities/targets/${t.id}`),
            }
          }}
        />
      </div>

      {/* ── Mobile FAB ── */}
      <PermissionGuard permission={PERMISSIONS.TARGETS_ASSIGN}>
        <button className="fab-button" onClick={() => navigate('/activities/targets/new')} aria-label="هدف جديد">
          <Plus size={24} />
        </button>
      </PermissionGuard>

      <style>{`
        .tg-filter-toggle { position: relative; }
        .tg-filter-badge {
          position: absolute; top: -6px; left: -6px;
          background: var(--color-danger); color: #fff;
          font-size: 10px; font-weight: 700; width: 18px; height: 18px;
          border-radius: 50%; display: flex; align-items: center; justify-content: center;
        }
        .tg-filters {
          max-height: 0; overflow: hidden;
          transition: max-height 0.3s ease, margin 0.3s ease;
        }
        .tg-filters--open { max-height: 400px; margin-bottom: var(--space-4); }
        .tg-filters-inner {
          background: var(--bg-surface); border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg); padding: var(--space-4);
          display: flex; flex-direction: column; gap: var(--space-3);
        }
        .tg-filters-row { display: flex; gap: var(--space-3); flex-wrap: wrap; }
        .tg-filter-select { min-width: 120px; flex: 1; }
        .tg-clear-btn {
          display: flex; align-items: center; gap: 4px;
          background: none; border: none; color: var(--color-danger);
          font-size: var(--text-xs); font-weight: 600; cursor: pointer;
          font-family: inherit; padding: 0;
        }
        .tg-clear-btn:hover { text-decoration: underline; }
        .tg-table-view { display: block; }
        .fab-button { display: none; }
        @media (max-width: 768px) {
          .desktop-only-btn { display: none; }
          .fab-button {
            display: flex; align-items: center; justify-content: center;
            position: fixed; bottom: calc(var(--bottom-nav-height, 64px) + var(--space-4)); inset-inline-end: var(--space-4);
            width: 56px; height: 56px; border-radius: 28px;
            background: var(--color-primary); color: white;
            box-shadow: var(--shadow-lg); z-index: 160; border: none;
            transition: transform 0.2s;
          }
          .fab-button:active { transform: scale(0.95); }
        }
      `}</style>
    </div>
  )
}
