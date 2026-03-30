import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth-store'
import { useTargets, useTargetTypes, useAdjustTarget } from '@/hooks/useQueryHooks'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { toast } from 'sonner'
import { Target, Plus, Eye, TrendingUp } from 'lucide-react'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import DataCard from '@/components/ui/DataCard'
import Button from '@/components/ui/Button'
import ActivityStatusBadge from '@/components/shared/ActivityStatusBadge'
import type { Target as TargetRow, TargetScope, TargetPeriod } from '@/lib/types/activities'

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG', { day: 'numeric', month: 'short', year: 'numeric' })
}

function fmtNumber(n: number) {
  return n.toLocaleString('ar-EG', { maximumFractionDigits: 1 })
}

const SCOPE_AR: Record<TargetScope, string> = {
  company:    'الشركة',
  branch:     'الفرع',
  department: 'القسم',
  individual: 'فرد',
}

const PERIOD_AR: Record<TargetPeriod, string> = {
  monthly:   'شهري',
  quarterly: 'ربع سنوي',
  yearly:    'سنوي',
  custom:    'مخصص',
}

export default function TargetsPage() {
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  const [scopeFilter,    setScopeFilter]    = useState<TargetScope | ''>('')
  const [typeCodeFilter, setTypeCodeFilter] = useState('')
  const [activeFilter,   setActiveFilter]   = useState<'true' | 'false' | ''>('true')
  const [page,           setPage]           = useState(1)

  const { data: targetTypes = [] } = useTargetTypes()

  const queryParams = useMemo(() => ({
    scope:    scopeFilter    || undefined,
    typeCode: typeCodeFilter || undefined,
    isActive: activeFilter === '' ? undefined : activeFilter === 'true',
    page,
    pageSize: 25,
  }), [scopeFilter, typeCodeFilter, activeFilter, page])

  const { data: result, isLoading: loading } = useTargets(queryParams)
  const targets    = result?.data     ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count    ?? 0

  const canCreate  = can(PERMISSIONS.TARGETS_ASSIGN)

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="الأهداف"
        subtitle={loading ? '...' : `${totalCount} هدف`}
        actions={canCreate ? (
          <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/targets/new')} className="desktop-only-btn">
            هدف جديد
          </Button>
        ) : undefined}
      />

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="act-filter-row">
          <select className="form-select filter-select" value={scopeFilter}
            onChange={e => { setScopeFilter(e.target.value as TargetScope | ''); setPage(1) }}>
            <option value="">كل النطاقات</option>
            <option value="company">الشركة</option>
            <option value="branch">الفرع</option>
            <option value="individual">فرد</option>
          </select>
          <select className="form-select filter-select" value={typeCodeFilter}
            onChange={e => { setTypeCodeFilter(e.target.value); setPage(1) }}>
            <option value="">كل الأنواع</option>
            {targetTypes.map(t => (
              <option key={t.id} value={t.code}>{t.name}</option>
            ))}
          </select>
          <select className="form-select filter-select" value={activeFilter}
            onChange={e => { setActiveFilter(e.target.value as 'true' | 'false' | ''); setPage(1) }}>
            <option value="true">نشط</option>
            <option value="false">غير نشط</option>
            <option value="">الكل</option>
          </select>
        </div>
      </div>

      {/* Desktop */}
      <div className="act-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<TargetRow>
          columns={[
            {
              key: 'name', label: 'الهدف',
              render: t => (
                <>
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{t.name}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', display: 'flex', gap: 'var(--space-2)', marginTop: 2 }}>
                    <span>{t.target_type?.name ?? t.type_code}</span>
                    <span>•</span>
                    <span>{SCOPE_AR[t.scope]}</span>
                  </div>
                </>
              ),
            },
            {
              key: 'period', label: 'الفترة', hideOnMobile: true,
              render: t => (
                <>
                  <div style={{ fontSize: 'var(--text-sm)' }}>{PERIOD_AR[t.period]}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    {fmtDate(t.period_start)} — {fmtDate(t.period_end)}
                  </div>
                </>
              ),
            },
            {
              key: 'target_value', label: 'القيمة المستهدفة',
              render: t => (
                <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>
                  {fmtNumber(t.target_value)}
                </span>
              ),
            },
            {
              key: 'progress', label: 'الإنجاز',
              render: t => {
                const prog = t.latest_progress
                if (!prog) return <span style={{ color: 'var(--text-muted)' }}>لم يُحسب بعد</span>
                return (
                  <div>
                    <ActivityStatusBadge trend={prog.trend ?? undefined} size="sm" />
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 2 }}>
                      {fmtNumber(prog.achieved_value)} ({prog.achievement_pct.toFixed(0)}%)
                    </div>
                  </div>
                )
              },
            },
            {
              key: 'status', label: 'الحالة',
              render: t => (
                <span style={{
                  fontSize: 'var(--text-xs)', fontWeight: 600,
                  color: t.is_active && !t.is_paused ? 'var(--color-success)' : 'var(--text-muted)',
                }}>
                  {t.is_paused ? 'موقوف' : t.is_active ? 'نشط' : 'غير نشط'}
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
          emptyAction={canCreate ? (
            <Button icon={<Plus size={16} />} onClick={() => navigate('/activities/targets/new')}>هدف جديد</Button>
          ) : undefined}
          page={page} totalPages={totalPages} totalCount={totalCount} onPageChange={setPage}
        />
      </div>

      {/* Mobile */}
      <div className="act-card-view">
        {loading ? (
          <div className="mobile-card-list">
            {[1, 2, 3].map(i => (
              <div key={i} className="edara-card" style={{ padding: 'var(--space-4)' }}>
                <div className="skeleton" style={{ height: 16, width: '60%', marginBottom: 8 }} />
                <div className="skeleton" style={{ height: 8, width: '100%', marginBottom: 4 }} />
                <div className="skeleton" style={{ height: 12, width: '40%' }} />
              </div>
            ))}
          </div>
        ) : (
          <div className="mobile-card-list">
            {targets.map(t => {
              const prog = t.latest_progress
              return (
                <DataCard
                  key={t.id}
                  title={t.name}
                  subtitle={`${t.target_type?.name ?? t.type_code} • ${SCOPE_AR[t.scope]}`}
                  badge={prog?.trend ? <ActivityStatusBadge trend={prog.trend} size="sm" /> : undefined}
                  metadata={[
                    { label: 'المستهدف', value: fmtNumber(t.target_value), highlight: true },
                    { label: 'الفترة', value: PERIOD_AR[t.period] },
                    ...(prog ? [{ label: 'الإنجاز', value: `${prog.achievement_pct.toFixed(0)}%` }] : []),
                  ]}
                  actions={
                    <Button variant="secondary" size="sm" onClick={() => navigate(`/activities/targets/${t.id}`)}
                      style={{ flex: 1, justifyContent: 'center' }}>
                      <Eye size={14} /> تفاصيل
                    </Button>
                  }
                  onClick={() => navigate(`/activities/targets/${t.id}`)}
                />
              )
            })}
          </div>
        )}
        {totalPages > 1 && (
          <div className="mobile-pagination">
            <Button variant="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>السابق</Button>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>{page} / {totalPages}</span>
            <Button variant="ghost" size="sm" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>التالي</Button>
          </div>
        )}
      </div>

      <style>{`
        .act-filter-row { display: flex; gap: var(--space-3); flex-wrap: wrap; align-items: flex-end; }
        .filter-select { min-width: 120px; flex: 1; }
        .act-table-view { display: block; }
        .act-card-view  { display: none; }
        @media (max-width: 768px) {
          .act-table-view { display: none; }
          .act-card-view  { display: block; }
          .desktop-only-btn { display: none; }
        }
        .mobile-card-list { display: flex; flex-direction: column; gap: var(--space-3); padding: 0 0 var(--space-2); }
        .mobile-pagination { display: flex; align-items: center; justify-content: center; gap: var(--space-4); padding: var(--space-4) 0; }
      `}</style>
    </div>
  )
}
