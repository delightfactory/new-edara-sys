/**
 * TargetPayoutsPage — HR Payroll: حساب وتثبيت مكافآت الأهداف
 * Run & Review History model
 * - يقرأ target_id من query string إذا جاء من TargetDetail
 * - يعرض عمود الموظف + مرجع الرواتب (adjustment_id)
 */
import { useState, useMemo } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import {
  useTargetPayouts, usePrepareTargetPayouts, useHRPayrollPeriods, useHREmployees,
} from '@/hooks/useQueryHooks'
import { toast } from 'sonner'
import { Play, ChevronRight, Gift, AlertCircle, Filter, TrendingUp, CheckCircle, Users } from 'lucide-react'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'

function fmtN(n: number, currency = false) {
  return currency
    ? `${n.toLocaleString('ar-EG', { maximumFractionDigits: 0 })} ج.م`
    : n.toLocaleString('ar-EG', { maximumFractionDigits: 2 })
}
function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG', { day: 'numeric', month: 'long', year: 'numeric' })
}

export default function TargetPayoutsPage() {
  const navigate   = useNavigate()
  const location   = useLocation()
  const can        = useAuthStore(s => s.can)
  const canCalculate = can(PERMISSIONS.HR_PAYROLL_CALCULATE)

  // قراءة target_id من URL إذا تمت إحالة من TargetDetail
  const urlTargetId = useMemo(() => {
    return new URLSearchParams(location.search).get('target_id') ?? ''
  }, [location.search])

  // ── Filters
  const [selectedPeriodId, setSelectedPeriodId] = useState('')
  const [filterStatus,     setFilterStatus]     = useState<'committed' | 'cancelled' | ''>('')
  const [filterTargetId,   setFilterTargetId]   = useState(urlTargetId)
  const [filterEmployeeId, setFilterEmployeeId] = useState('')
  const [confirmOpen,      setConfirmOpen]       = useState(false)
  const [running,          setRunning]           = useState(false)

  // ── Data
  const { data: periods = [] }    = useHRPayrollPeriods()
  const { data: employeesRes }    = useHREmployees({ pageSize: 300 })
  const employees = useMemo(() => employeesRes?.data ?? [], [employeesRes])

  const payoutFilters = useMemo(() => ({
    period_id:   selectedPeriodId || undefined,
    status:      filterStatus     || undefined,
    target_id:   filterTargetId   || undefined,
    employee_id: filterEmployeeId || undefined,
  }), [selectedPeriodId, filterStatus, filterTargetId, filterEmployeeId])

  const { data: payouts = [], isLoading: loadingPayouts } = useTargetPayouts(payoutFilters as any)
  const preparePayouts = usePrepareTargetPayouts()

  // ── Stats
  const totalPayout    = payouts.reduce((sum, p) => sum + ((p as any).payout_amount ?? 0), 0)
  const committedCount = payouts.filter((p: any) => p.status === 'committed').length
  const cancelledCount = payouts.filter((p: any) => p.status === 'cancelled').length

  const selectedPeriod = (periods as any[]).find(p => p.id === selectedPeriodId)

  const handleRun = async () => {
    if (!selectedPeriodId) { toast.error('اختر فترة الرواتب أولاً'); return }
    setRunning(true); setConfirmOpen(false)
    try {
      await preparePayouts.mutateAsync(selectedPeriodId)
      toast.success('تم حساب وتثبيت مكافآت الأهداف بنجاح ✅')
    } catch (e: any) {
      toast.error(e?.message || 'فشل تشغيل دورة حساب المكافآت')
    } finally {
      setRunning(false)
    }
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="مكافآت الأهداف — الرواتب"
        subtitle="حساب وتثبيت استحقاقات مكافآت الأهداف حسب فترة الرواتب"
        breadcrumbs={[
          { label: 'الرواتب', path: '/hr/payroll' },
          { label: 'مكافآت الأهداف' },
        ]}
        actions={
          <Button variant="secondary" icon={<ChevronRight size={16} />} onClick={() => navigate('/hr/payroll')}>
            العودة للرواتب
          </Button>
        }
      />

      {/* ── Context banner when filtered by target ── */}
      {filterTargetId && (
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px',
          padding: '10px 16px', background: 'var(--color-primary-light)', border: '1px solid var(--color-primary)',
          borderRadius: 'var(--radius-lg)', marginBottom: 'var(--space-4)',
          fontSize: '13px', color: 'var(--color-primary)', fontWeight: 600,
        }}>
          <span>🎯 عرض الاستحقاقات المرتبطة بهدف محدد فقط</span>
          <button
            style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--color-primary)', fontWeight: 700, fontSize: '13px' }}
            onClick={() => navigate(`/activities/targets/${filterTargetId}`)}
          >
            عرض الهدف ←
          </button>
          <button
            style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--color-danger)', fontSize: '12px' }}
            onClick={() => setFilterTargetId('')}
          >
            إلغاء التصفية
          </button>
        </div>
      )}

      {/* ── Control Panel ── */}
      <div className="edara-card tp-control-card">
        <div className="tp-control-header">
          <h3 className="tp-section-title" style={{ margin: 0, border: 'none', padding: 0 }}>
            <Gift size={18} className="inline align-middle ml-1" /> تشغيل دورة الحساب
          </h3>
          <p className="tp-control-desc">
            اختر فترة رواتب ثم اضغط "حساب وتثبيت" — سيقوم النظام بحساب استحقاقات كل موظف وتثبيتها مباشرةً.
          </p>
        </div>

        <div className="tp-run-row">
          <div className="form-group" style={{ flex: 1, margin: 0 }}>
            <label className="form-label">فترة الرواتب</label>
            <select className="form-select" value={selectedPeriodId} onChange={e => setSelectedPeriodId(e.target.value)}>
              <option value="">-- اختر فترة الرواتب --</option>
              {(periods as any[]).map((p: any) => (
                <option key={p.id} value={p.id}>
                  {p.name ?? `${p.year} / ${String(p.month).padStart(2, '0')}`}
                  {p.status === 'closed' ? ' (مغلقة)' : p.status === 'processing' ? ' (جارية)' : ' (مفتوحة)'}
                </option>
              ))}
            </select>
          </div>

          {canCalculate && (
            <Button
              variant="primary"
              icon={<Play size={16} />}
              disabled={!selectedPeriodId || running}
              onClick={() => setConfirmOpen(true)}
              style={{ alignSelf: 'flex-end', minWidth: 180 }}
            >
              {running ? 'جاري الحساب...' : 'حساب وتثبيت المكافآت'}
            </Button>
          )}
        </div>

        {selectedPeriod && (
          <div className="tp-period-info">
            <span><strong>الفترة:</strong> {selectedPeriod.name ?? `${selectedPeriod.year} / ${selectedPeriod.month}`}</span>
            {selectedPeriod.date_from && <span>{fmtDate(selectedPeriod.date_from)} — {fmtDate(selectedPeriod.date_to)}</span>}
            <span className={`tp-period-status tp-period-status--${selectedPeriod.status}`}>
              {selectedPeriod.status === 'open' ? '🟢 مفتوحة' : selectedPeriod.status === 'processing' ? '🟡 جارية' : '🔴 مغلقة'}
            </span>
          </div>
        )}

        <div className="tp-warning">
          <AlertCircle size={15} />
          <span>
            عملية الحساب والتثبيت <strong>غير قابلة للتراجع</strong>. السجلات المثبتة تُدرج تلقائياً في مسير الرواتب.
          </span>
        </div>
      </div>

      {/* ── Stats Strip ── */}
      {payouts.length > 0 && (
        <div className="tp-stats-strip">
          <div className="tp-stat">
            <TrendingUp size={16} />
            <div>
              <div className="tp-stat-value">{payouts.length}</div>
              <div className="tp-stat-label">إجمالي السجلات</div>
            </div>
          </div>
          <div className="tp-stat">
            <CheckCircle size={16} style={{ color: 'var(--color-success)' }} />
            <div>
              <div className="tp-stat-value" style={{ color: 'var(--color-success)' }}>{committedCount}</div>
              <div className="tp-stat-label">مثبتة</div>
            </div>
          </div>
          {cancelledCount > 0 && (
            <div className="tp-stat">
              <div className="tp-stat-value" style={{ color: 'var(--color-danger)' }}>{cancelledCount}</div>
              <div className="tp-stat-label">ملغية</div>
            </div>
          )}
          <div className="tp-stat">
            <Gift size={16} style={{ color: 'var(--color-primary)' }} />
            <div>
              <div className="tp-stat-value" style={{ color: 'var(--color-primary)' }}>{fmtN(totalPayout, true)}</div>
              <div className="tp-stat-label">إجمالي المصروف</div>
            </div>
          </div>
        </div>
      )}

      {/* ── Records Table ── */}
      <div className="edara-card" style={{ padding: 0, overflow: 'hidden' }}>
        {/* Table Header */}
        <div className="tp-table-header">
          <h3 className="tp-section-title" style={{ margin: 0, border: 'none', padding: 0 }}>
            <Users size={16} className="inline align-middle ml-1" /> سجل الاستحقاقات
          </h3>
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center', flexWrap: 'wrap' }}>
            <Filter size={14} style={{ color: 'var(--text-muted)' }} />
            <select className="form-select" style={{ minWidth: 140, padding: '6px 12px', fontSize: '13px' }}
              value={filterStatus} onChange={e => setFilterStatus(e.target.value as any)}>
              <option value="">كل الحالات</option>
              <option value="committed">مثبتة فقط</option>
              <option value="cancelled">ملغية فقط</option>
            </select>
            <select className="form-select" style={{ minWidth: 160, padding: '6px 12px', fontSize: '13px' }}
              value={filterEmployeeId} onChange={e => setFilterEmployeeId(e.target.value)}>
              <option value="">كل الموظفين</option>
              {(employees as any[]).map((e: any) => (
                <option key={e.id} value={e.id}>{e.full_name}</option>
              ))}
            </select>
          </div>
        </div>

        {loadingPayouts ? (
          <div style={{ padding: '24px' }}>
            {[1, 2, 3, 4].map(i => (
              <div key={i} className="skeleton" style={{ height: 56, marginBottom: '8px', borderRadius: '6px' }} />
            ))}
          </div>
        ) : payouts.length === 0 ? (
          <div className="empty-state" style={{ padding: '48px 0' }}>
            <Gift size={40} style={{ opacity: 0.3, marginBottom: '12px' }} />
            <p className="empty-state-title">لا توجد سجلات</p>
            <p className="empty-state-text">
              {selectedPeriodId
                ? 'لا توجد استحقاقات لهذه الفترة. استخدم زر "حساب وتثبيت" لبدء الدورة.'
                : 'اختر فترة رواتب لعرض السجلات، أو اتركها فارغة لعرض كل السجلات.'}
            </p>
          </div>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
              <thead>
                <tr style={{ borderBottom: '2px solid var(--border-primary)', background: 'var(--bg-surface-2)' }}>
                  <th className="tp-th">الموظف</th>
                  <th className="tp-th">الهدف</th>
                  <th className="tp-th">الفترة / التاريخ</th>
                  <th className="tp-th tp-th--center">الإنجاز</th>
                  <th className="tp-th tp-th--center">الشريحة</th>
                  <th className="tp-th tp-th--center">المبلغ</th>
                  <th className="tp-th tp-th--center">مرجع الرواتب</th>
                  <th className="tp-th tp-th--center">الحالة</th>
                </tr>
              </thead>
              <tbody>
                {(payouts as any[]).map((p: any) => (
                  <tr key={p.id} className="tp-table-row"
                    style={{ borderBottom: '1px solid var(--border-secondary)', transition: 'background 0.15s' }}>
                    {/* Employee */}
                    <td style={{ padding: '12px 16px' }}>
                      {p.employee?.full_name ? (
                        <div style={{ fontWeight: 600, fontSize: '13px', color: 'var(--text-primary)' }}>
                          {p.employee.full_name}
                        </div>
                      ) : (
                        <span style={{ color: 'var(--text-muted)', fontSize: '12px' }}>—</span>
                      )}
                    </td>
                    {/* Target */}
                    <td style={{ padding: '12px 16px' }}>
                      <div style={{ fontWeight: 600, color: 'var(--text-primary)', marginBottom: '2px', maxWidth: 180 }}>
                        {p.target?.name ?? '—'}
                      </div>
                      <div
                        style={{ fontSize: '11px', color: 'var(--color-primary)', cursor: 'pointer', display: 'inline' }}
                        onClick={() => navigate(`/activities/targets/${p.target_id}`)}
                      >
                        عرض الهدف ←
                      </div>
                    </td>
                    {/* Period / Date */}
                    <td style={{ padding: '12px' }}>
                      <div style={{ fontWeight: 500 }}>
                        {p.period?.name ?? (selectedPeriod?.name ?? '—')}
                      </div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                        {new Date(p.computed_at).toLocaleDateString('ar-EG', { day: 'numeric', month: 'short', year: 'numeric' })}
                      </div>
                    </td>
                    {/* Achievement */}
                    <td style={{ padding: '12px', textAlign: 'center', fontWeight: 700, fontSize: '14px' }}>
                      {p.achievement_pct?.toFixed(1) ?? '—'}%
                    </td>
                    {/* Tier */}
                    <td style={{ padding: '12px', textAlign: 'center' }}>
                      {p.tier_reached ? (
                        <span style={{ fontSize: '11px', fontWeight: 600, padding: '3px 8px', background: 'var(--color-primary-light)', color: 'var(--color-primary)', borderRadius: '99px' }}>
                          {`شريحة ${p.tier_reached}`}
                        </span>
                      ) : (
                        <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>—</span>
                      )}
                    </td>
                    {/* Amount */}
                    <td style={{ padding: '12px', textAlign: 'center', fontWeight: 800, fontSize: '14px', color: 'var(--color-success)' }}>
                      {fmtN((p.payout_amount ?? 0) as number, true)}
                    </td>
                    {/* Adjustment ref */}
                    <td style={{ padding: '12px', textAlign: 'center' }}>
                      {p.adjustment_id ? (
                        <span style={{
                          fontSize: '10px', fontFamily: 'monospace', fontWeight: 600,
                          padding: '3px 7px', background: 'var(--bg-body)',
                          border: '1px solid var(--border-primary)', borderRadius: '6px',
                          color: 'var(--text-secondary)',
                        }}>
                          #{p.adjustment_id.slice(-8)}
                        </span>
                      ) : (
                        <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>—</span>
                      )}
                    </td>
                    {/* Status */}
                    <td style={{ padding: '12px', textAlign: 'center' }}>
                      {p.status === 'committed' ? (
                        <span style={{ fontSize: '11px', fontWeight: 600, padding: '4px 10px', background: 'var(--color-success-light)', color: 'var(--color-success)', border: '1px solid rgba(16,185,129,0.3)', borderRadius: '6px' }}>
                          مثبتة ✓
                        </span>
                      ) : p.status === 'cancelled' ? (
                        <span style={{ fontSize: '11px', fontWeight: 600, padding: '4px 10px', background: 'var(--color-danger-light)', color: 'var(--color-danger)', borderRadius: '6px' }}>
                          ملغية ✕
                        </span>
                      ) : (
                        <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{p.status}</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* ── Confirmation Dialog ── */}
      {confirmOpen && (
        <div className="tp-overlay" onClick={() => setConfirmOpen(false)}>
          <div className="tp-confirm-dialog" onClick={e => e.stopPropagation()}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '16px' }}>
              <div style={{ width: 44, height: 44, borderRadius: '50%', background: 'var(--color-warning-light)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                <AlertCircle size={22} style={{ color: 'var(--color-warning)' }} />
              </div>
              <h3 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>تأكيد تشغيل دورة الحساب</h3>
            </div>
            <p style={{ margin: '0 0 8px', fontSize: '14px', color: 'var(--text-secondary)', lineHeight: 1.7 }}>
              ستقوم الآن بـ <strong>حساب وتثبيت</strong> مكافآت الأهداف لفترة:
            </p>
            <div style={{ padding: '10px 16px', background: 'var(--color-primary-light)', border: '1px solid var(--color-primary)', borderRadius: '8px', marginBottom: '12px', fontWeight: 700, color: 'var(--color-primary)' }}>
              {selectedPeriod?.name ?? selectedPeriodId}
            </div>
            <p style={{ margin: '0 0 20px', fontSize: '13px', color: 'var(--color-warning)', display: 'flex', alignItems: 'center', gap: '6px', fontWeight: 600 }}>
              <AlertCircle size={14} /> السجلات المثبتة <u>لا يمكن التراجع عنها</u> وتُدرج في مسير الرواتب مباشرةً.
            </p>
            <div style={{ display: 'flex', gap: '12px', justifyContent: 'flex-end' }}>
              <Button variant="secondary" onClick={() => setConfirmOpen(false)}>إلغاء</Button>
              <Button variant="primary" icon={<Play size={14} />} onClick={handleRun} disabled={running}>
                {running ? 'جاري...' : 'تأكيد التشغيل'}
              </Button>
            </div>
          </div>
        </div>
      )}

      <style>{`
        .tp-control-card { padding: var(--space-5); margin-bottom: var(--space-4); }
        .tp-control-header { margin-bottom: var(--space-4); }
        .tp-control-desc { font-size: 13px; color: var(--text-secondary); margin: 4px 0 0; line-height: 1.6; }
        .tp-section-title { font-size: var(--text-base); font-weight: 700; color: var(--text-primary); border-bottom: 1px solid var(--border-primary); padding-bottom: var(--space-3); margin-bottom: var(--space-4); }
        .tp-run-row { display: flex; gap: var(--space-3); align-items: flex-start; flex-wrap: wrap; margin-bottom: var(--space-3); }
        .tp-period-info { display: flex; gap: var(--space-4); flex-wrap: wrap; align-items: center; padding: var(--space-2) var(--space-3); background: var(--bg-surface-2); border-radius: var(--radius-md); font-size: 13px; color: var(--text-secondary); margin-bottom: var(--space-3); }
        .tp-period-status { font-weight: 700; }
        .tp-warning { display: flex; align-items: flex-start; gap: 8px; padding: var(--space-3) var(--space-4); background: var(--color-warning-light); border: 1px solid rgba(245,158,11,0.4); border-radius: var(--radius-md); font-size: 13px; color: var(--text-secondary); line-height: 1.6; }
        .tp-stats-strip { display: flex; gap: var(--space-3); flex-wrap: wrap; margin-bottom: var(--space-4); }
        .tp-stat { display: flex; align-items: center; gap: var(--space-2); padding: var(--space-3) var(--space-4); background: var(--bg-surface); border: 1px solid var(--border-primary); border-radius: var(--radius-lg); flex: 1; min-width: 120px; }
        .tp-stat-value { font-size: var(--text-lg); font-weight: 800; color: var(--text-primary); }
        .tp-stat-label { font-size: 11px; color: var(--text-muted); }
        .tp-table-header { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px; padding: var(--space-4) var(--space-5); border-bottom: 1px solid var(--border-primary); }
        .tp-th { padding: 12px 16px; text-align: right; font-weight: 700; color: var(--text-muted); font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; white-space: nowrap; }
        .tp-th--center { text-align: center; }
        .tp-table-row:hover { background: var(--bg-hover); }
        .tp-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.5); z-index: 900; display: flex; align-items: center; justify-content: center; padding: 16px; }
        .tp-confirm-dialog { background: var(--bg-surface); border: 1px solid var(--border-primary); border-radius: var(--radius-xl); padding: 28px; max-width: 440px; width: 100%; box-shadow: var(--shadow-xl); }
        @media (max-width: 600px) { .tp-run-row { flex-direction: column; } .tp-stats-strip .tp-stat { min-width: 140px; } }
      `}</style>
    </div>
  )
}
