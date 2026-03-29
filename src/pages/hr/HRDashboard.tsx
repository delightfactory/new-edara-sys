import { useState } from 'react'
import { useNavigate, Navigate } from 'react-router-dom'
import {
  Users, Calendar, CreditCard, FileSpreadsheet,
  UserPlus, Play, TrendingUp, Clock,
  CheckCircle, AlertCircle, ArrowLeft, Check, X,
} from 'lucide-react'
import {
  useHREmployees,
  useHRLeaveRequests,
  useHRAdvances,
  useHRPayrollRuns,
} from '@/hooks/useQueryHooks'
import { updateLeaveRequestStatus, updateAdvanceStatus, getAttendanceDays } from '@/lib/services/hr'
import type { HRLeaveRequest, HRLeaveRequestStatus } from '@/lib/types/hr'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuthStore } from '@/stores/auth-store'
import { toast } from 'sonner'
import Button from '@/components/ui/Button'
import PermissionGuard from '@/components/shared/PermissionGuard'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import PageHeader from '@/components/shared/PageHeader'
import StatCard from '@/components/shared/StatCard'

// ─── QuickAction ──────────────────────────────────────
function QuickAction({ id, label, desc, icon, color, onClick }: {
  id: string; label: string; desc: string
  icon: React.ReactNode; color: string; onClick: () => void
}) {
  return (
    <button
      id={id}
      onClick={onClick}
      style={{
        display: 'flex', alignItems: 'center', gap: 'var(--space-3)',
        padding: 'var(--space-4)',
        background: 'var(--bg-surface-2)',
        border: '1px solid var(--border-primary)',
        borderRadius: 'var(--radius-lg)',
        cursor: 'pointer', textAlign: 'start', width: '100%',
        transition: 'all 0.2s cubic-bezier(0.4, 0, 0.2, 1)',
        position: 'relative', overflow: 'hidden',
      }}
      className="quick-action-btn"
    >
      <div style={{
        position: 'absolute', top: 0, insetInlineStart: 0, width: 4, height: '100%',
        background: `linear-gradient(to bottom, ${color}, color-mix(in srgb, ${color} 40%, transparent))`
      }} />
      <div style={{
        width: 44, height: 44, borderRadius: 'var(--radius-md)', flexShrink: 0,
        background: `color-mix(in srgb, ${color} 12%, transparent)`,
        color, display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        {icon}
      </div>
      <div style={{ flex: 1, textAlign: 'start' }}>
        <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--text-primary)' }}>{label}</div>
        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginTop: 2 }}>{desc}</div>
      </div>
      <div className="qa-arrow-icon" style={{ 
        width: 28, height: 28, borderRadius: '50%',
        background: `color-mix(in srgb, ${color} 8%, transparent)`,
        display: 'flex', alignItems: 'center', justifyContent: 'center', color 
      }}>
        <ArrowLeft size={14} />
      </div>
    </button>
  )
}

// ═════════════════════════════════════════════════════
// HRDashboard
// ═════════════════════════════════════════════════════

export default function HRDashboard() {
  const navigate = useNavigate()
  const qc = useQueryClient()
  const can = useAuthStore(s => s.can)
  const isManager = can('hr.employees.read')

  // GAP-01: state لنموذج الرفض — يجب تعريف الـ Hooks قبل أي return مبكر
  const [rejectLeave, setRejectLeave]     = useState<HRLeaveRequest | null>(null)
  const [rejectReason, setRejectReason]   = useState('')
  const [rejecting, setRejecting]         = useState(false)

  // ── بيانات الإحصائيات ────────────────────────────────
  const { data: empData, isLoading: empLoading } =
    useHREmployees(isManager ? { status: 'active', pageSize: 1 } : undefined)

  const { data: leaveData, isLoading: leaveLoading } =
    useHRLeaveRequests(isManager ? { status: ['pending_supervisor', 'pending_hr'], pageSize: 10 } : undefined)

  const { data: advanceData, isLoading: advLoading } =
    useHRAdvances(isManager ? { status: ['pending_supervisor', 'pending_hr'], pageSize: 10 } : undefined)

  const { data: payrollRuns = [], isLoading: payrollLoading } =
    useHRPayrollRuns(isManager ? undefined : undefined)

  // FIX-11: إحصائيات حضور اليوم
  const todayStr = new Date().toISOString().split('T')[0]
  const { data: todayAttendance } = useQuery({
    queryKey: ['hr-dashboard-attendance-today', todayStr],
    queryFn: () => getAttendanceDays({ dateFrom: todayStr, dateTo: todayStr, pageSize: 500 }),
    enabled: isManager,
  })
  const todayDays = todayAttendance?.data ?? []
  const todayPresent = todayDays.filter(d => ['present', 'late', 'half_day'].includes(d.status)).length
  const todayLate    = todayDays.filter(d => d.status === 'late').length
  const todayAbsent  = todayDays.filter(d => ['absent_unauthorized', 'absent_authorized'].includes(d.status)).length
  const todayOnLeave = todayDays.filter(d => d.status === 'on_leave').length

  // الموظف العادي (بدون hr.employees.read) يُعاد توجيهه لملفه الشخصي
  // هذا الـ return يأتي بعد كل الـ Hooks
  if (!isManager) {
    return <Navigate to="/hr/my-profile" replace />
  }

  // حساب الإحصائيات
  const activeEmployees  = empData?.count ?? 0
  const pendingLeaves    = leaveData?.count ?? leaveData?.data?.length ?? 0
  const pendingAdvances  = advanceData?.count ?? advanceData?.data?.length ?? 0

  const pendingPayrolls  = payrollRuns.filter(r => r.status === 'review').length
  const lastRun          = payrollRuns[0]

  // آخر 5 إجازات معلقة
  const recentLeaves  = leaveData?.data?.slice(0, 5) ?? []
  // آخر 5 سلف معلقة
  const recentAdvances = advanceData?.data?.slice(0, 5) ?? []

  const fmtDate = (d?: string | null) =>
    d ? new Date(d).toLocaleDateString('ar-EG-u-nu-latn', { day: 'numeric', month: 'short' }) : '—'

  const fmt = (n: number) =>
    n.toLocaleString('ar-EG-u-nu-latn', { maximumFractionDigits: 0 }) + ' ج.م'

  // GAP-02: موافقة تحترم دورة الاعتماد — pending_hr → approved
  const handleQuickApproveLeave = async (req: HRLeaveRequest) => {
    // احترام دورة الاعتماد: pending_supervisor → approved_supervisor → pending_hr → approved
    const nextStatus: HRLeaveRequestStatus = req.status === 'pending_supervisor'
      ? 'approved_supervisor'
      : 'approved'
    try {
      await updateLeaveRequestStatus(req.id, nextStatus)
      toast.success(nextStatus === 'approved' ? 'اعتمدت الإجازة بنجاح' : 'موافقة المشرف — بانتظار موافقة HR')
      qc.invalidateQueries({ queryKey: ['hr-leave-requests'] })
    } catch (e: any) {
      toast.error(e.message)
    }
  }

  // GAP-01: تنفيذ رفض فعلي مع سبب
  const handleQuickRejectLeave = async () => {
    if (!rejectLeave || !rejectReason.trim()) return
    setRejecting(true)
    try {
      await updateLeaveRequestStatus(rejectLeave.id, 'rejected', undefined, rejectReason.trim())
      toast.success('تم رفض طلب الإجازة')
      qc.invalidateQueries({ queryKey: ['hr-leave-requests'] })
      setRejectLeave(null)
      setRejectReason('')
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      setRejecting(false)
    }
  }

  return (
    <div className="page-container animate-enter" style={{ maxWidth: 1100 }}>

      {/* ── Header ── */}
      <PageHeader
        title="لوحة الموارد البشرية"
        subtitle="نظرة شاملة على الموظفين، الإجازات، السلف، ومسير الرواتب"
      />

      {/* ══ Stat Cards ══ */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
        gap: 'var(--space-4)',
        marginBottom: 'var(--space-6)',
      }}>

        <StatCard
          id="stat-active-employees"
          label="الموظفون النشطون"
          value={activeEmployees}
          sub="موظف نشط حالياً"
          icon={<Users size={22} />}
          color="var(--color-primary)"
          onClick={() => navigate('/hr/employees')}
          loading={empLoading}
        />

        <StatCard
          id="stat-pending-leaves"
          label="إجازات معلقة"
          value={pendingLeaves}
          sub="تنتظر موافقة HR"
          icon={<Calendar size={22} />}
          color={pendingLeaves > 0 ? 'var(--color-warning)' : 'var(--color-success)'}
          onClick={() => navigate('/hr/leaves')}
          loading={leaveLoading}
        />

        <StatCard
          id="stat-pending-advances"
          label="سلف معلقة"
          value={pendingAdvances}
          sub="تنتظر موافقة HR"
          icon={<CreditCard size={22} />}
          color={pendingAdvances > 0 ? 'var(--color-warning)' : 'var(--color-success)'}
          onClick={() => navigate('/hr/advances')}
          loading={advLoading}
        />

        <StatCard
          id="stat-payroll-review"
          label="مسيرات للمراجعة"
          value={pendingPayrolls}
          sub={lastRun ? `آخر مسير: ${lastRun.period?.name ?? ''}` : 'لا توجد مسيرات'}
          icon={<FileSpreadsheet size={22} />}
          color={pendingPayrolls > 0 ? 'var(--color-danger)' : 'var(--color-info)'}
          onClick={() => navigate('/hr/payroll')}
          loading={payrollLoading}
        />

        {/* FIX-11: إحصائيات حضور اليوم */}
        <StatCard
          id="stat-today-attendance"
          label="حاضرون اليوم"
          value={todayPresent}
          sub={`${todayLate > 0 ? todayLate + ' متأخر · ' : ''}${todayAbsent} غائب · ${todayOnLeave} إجازة`}
          icon={<Clock size={22} />}
          color={todayAbsent > 0 ? 'var(--color-danger)' : 'var(--color-success)'}
          onClick={() => navigate('/hr/attendance')}
          loading={!todayAttendance}
        />
      </div>

      {/* ══ المحتوى الرئيسي ══ */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
        gap: 'var(--space-5)',
        alignItems: 'start',
      }}>

        {/* ── الإجراءات السريعة ── */}
        <div className="edara-card">
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            marginBottom: 'var(--space-4)',
          }}>
            <h2 style={{ fontWeight: 700, fontSize: 'var(--text-base)', margin: 0 }}>
              إجراءات سريعة
            </h2>
            <TrendingUp size={16} style={{ color: 'var(--text-muted)' }} />
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
            <PermissionGuard permission="hr.employees.create">
              <QuickAction
                id="qa-add-employee"
                label="إضافة موظف جديد"
                desc="تسجيل موظف وبياناته الكاملة"
                icon={<UserPlus size={17} />}
                color="var(--color-primary)"
                onClick={() => navigate('/hr/employees/new')}
              />
            </PermissionGuard>

            <PermissionGuard permission="hr.payroll.calculate">
              <QuickAction
                id="qa-new-payroll"
                label="إنشاء مسير رواتب"
                desc="بدء دورة حساب رواتب شهرية"
                icon={<Play size={17} />}
                color="var(--color-success)"
                onClick={() => navigate('/hr/payroll')}
              />
            </PermissionGuard>

            {/* UX-08: إجراءات للموظف العادي — تظهر لمن ليس لديه صلاحية hr.leaves.approve */}
            {!can('hr.leaves.approve') && (
              <QuickAction
                id="qa-my-leaves"
                label="طلب إجازة"
                desc="تقديم طلب إجازة جديد"
                icon={<Calendar size={17} />}
                color="var(--color-warning)"
                onClick={() => navigate('/hr/leaves')}
              />
            )}

            {!can('hr.advances.approve') && (
              <QuickAction
                id="qa-my-advance"
                label="طلب سلفة"
                desc="تقديم طلب سلفة جديد"
                icon={<CreditCard size={17} />}
                color="var(--color-info)"
                onClick={() => navigate('/hr/advances')}
              />
            )}

            {/* للمديرين: مراجعة الطلبات */}
            <PermissionGuard permission="hr.leaves.approve">
              <QuickAction
                id="qa-leaves"
                label="مراجعة الإجازات"
                desc="الطلبات المعلقة في انتظار الموافقة"
                icon={<Calendar size={17} />}
                color="var(--color-warning)"
                onClick={() => navigate('/hr/leaves')}
              />
            </PermissionGuard>

            <PermissionGuard permission="hr.advances.approve">
              <QuickAction
                id="qa-advances"
                label="مراجعة طلبات السلف"
                desc="السلف المعلقة في انتظار الموافقة"
                icon={<CreditCard size={17} />}
                color="var(--color-info)"
                onClick={() => navigate('/hr/advances')}
              />
            </PermissionGuard>
          </div>
        </div>

        {/* ── آخر إجازات معلقة ── */}
        <div className="edara-card">
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            marginBottom: 'var(--space-4)',
          }}>
            <h2 style={{ fontWeight: 700, fontSize: 'var(--text-base)', margin: 0 }}>
              إجازات تنتظر الموافقة
            </h2>
            <Button
              variant="ghost" size="sm"
              onClick={() => navigate('/hr/leaves')}
              style={{ fontSize: 'var(--text-xs)' }}
            >
              عرض الكل
            </Button>
          </div>

          {leaveLoading ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              {[1, 2, 3].map(i => (
                <div key={i} className="skeleton" style={{ height: 48, borderRadius: 8 }} />
              ))}
            </div>
          ) : recentLeaves.length === 0 ? (
            <div style={{
              textAlign: 'center', padding: 'var(--space-6)',
              color: 'var(--text-muted)', fontSize: 'var(--text-sm)',
            }}>
              <CheckCircle size={28} style={{ display: 'block', margin: '0 auto var(--space-2)', opacity: 0.4 }} />
              لا توجد إجازات معلقة — رائع!
            </div>
          ) : (
            recentLeaves.map(req => (
              <div key={req.id} style={{
                padding: 'var(--space-3)',
                background: 'var(--bg-surface-2)',
                border: '1px solid var(--border-primary)',
                borderRadius: 'var(--radius-md)',
                marginBottom: 'var(--space-3)',
                transition: 'all 0.15s ease',
              }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  <div style={{ display: 'flex', gap: 'var(--space-3)', alignItems: 'center' }}>
                    <div style={{
                      width: 40, height: 40, borderRadius: '50%', background: 'color-mix(in srgb, var(--color-warning) 15%, transparent)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--color-warning)', flexShrink: 0
                    }}>
                      <Calendar size={18} />
                    </div>
                    <div>
                      <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--text-primary)' }}>{req.employee?.full_name ?? '—'}</div>
                      <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>
                        {`${req.leave_type?.name ?? ''} · ${fmtDate(req.start_date)}`}
                      </div>
                    </div>
                  </div>
                  <span style={{
                    padding: '2px 10px', borderRadius: 99,
                    background: 'color-mix(in srgb, var(--color-warning) 12%, transparent)',
                    color: 'var(--color-warning)', fontSize: 'var(--text-xs)', fontWeight: 800,
                  }}>
                    {req.days_count} يوم
                  </span>
                </div>
                <PermissionGuard permission="hr.leaves.approve">
                  <div style={{ display: 'flex', gap: 'var(--space-2)', marginTop: 'var(--space-3)' }}>
                    <Button
                      size="sm" variant="secondary"
                      icon={<Check size={14} />}
                      style={{ flex: 1, color: 'var(--color-success)', borderColor: 'color-mix(in srgb, var(--color-success) 30%, transparent)', background: 'transparent' }}
                      onClick={() => handleQuickApproveLeave(req)}
                    >
                      موافقة
                    </Button>
                    <Button
                      size="sm" variant="secondary"
                      icon={<X size={14} />}
                      style={{ flex: 1, color: 'var(--color-danger)', borderColor: 'color-mix(in srgb, var(--color-danger) 30%, transparent)', background: 'transparent' }}
                      onClick={() => { setRejectLeave(req); setRejectReason('') }}
                    >
                      رفض
                    </Button>
                  </div>
                </PermissionGuard>
              </div>
            ))
          )}
        </div>

        {/* ── آخر سلف معلقة ── */}
        <div className="edara-card">
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            marginBottom: 'var(--space-4)',
          }}>
            <h2 style={{ fontWeight: 700, fontSize: 'var(--text-base)', margin: 0 }}>
              سلف تنتظر الموافقة
            </h2>
            <Button
              variant="ghost" size="sm"
              onClick={() => navigate('/hr/advances')}
              style={{ fontSize: 'var(--text-xs)' }}
            >
              عرض الكل
            </Button>
          </div>

          {advLoading ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              {[1, 2, 3].map(i => (
                <div key={i} className="skeleton" style={{ height: 48, borderRadius: 8 }} />
              ))}
            </div>
          ) : recentAdvances.length === 0 ? (
            <div style={{
              textAlign: 'center', padding: 'var(--space-6)',
              color: 'var(--text-muted)', fontSize: 'var(--text-sm)',
            }}>
              <CheckCircle size={28} style={{ display: 'block', margin: '0 auto var(--space-2)', opacity: 0.4 }} />
              لا توجد سلف معلقة
            </div>
          ) : (
            recentAdvances.map(adv => (
              <div key={adv.id} style={{
                padding: 'var(--space-3)',
                background: 'var(--bg-surface-2)',
                border: '1px solid var(--border-primary)',
                borderRadius: 'var(--radius-md)',
                marginBottom: 'var(--space-3)',
                transition: 'all 0.15s ease',
              }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  <div style={{ display: 'flex', gap: 'var(--space-3)', alignItems: 'center' }}>
                    <div style={{
                      width: 40, height: 40, borderRadius: '50%', background: 'color-mix(in srgb, var(--color-info) 15%, transparent)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--color-info)', flexShrink: 0
                    }}>
                      <CreditCard size={18} />
                    </div>
                    <div>
                      <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--text-primary)' }}>{adv.employee?.full_name ?? '—'}</div>
                      <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>
                        {`${adv.advance_type === 'instant' ? 'فوري' : 'مجدول'} · ${fmtDate(adv.created_at)}`}
                      </div>
                    </div>
                  </div>
                  <span style={{
                    padding: '2px 10px', borderRadius: 99,
                    background: 'color-mix(in srgb, var(--color-info) 12%, transparent)',
                    color: 'var(--color-info)', fontSize: 'var(--text-xs)', fontWeight: 800,
                  }}>
                    {fmt(adv.amount)}
                  </span>
                </div>
                <PermissionGuard permission="hr.advances.approve">
                  <div style={{ display: 'flex', gap: 'var(--space-2)', marginTop: 'var(--space-3)' }}>
                    <Button
                      size="sm" variant="secondary"
                      icon={<Check size={14} />}
                      style={{ flex: 1, color: 'var(--color-success)', borderColor: 'color-mix(in srgb, var(--color-success) 30%, transparent)', background: 'transparent' }}
                      onClick={() => {
                        updateAdvanceStatus(adv.id, 'pending_finance')
                          .then(() => { toast.success('موافقة HR تمت'); qc.invalidateQueries({ queryKey: ['hr-advances'] }) })
                          .catch((e: any) => toast.error(e.message))
                      }}
                    >
                      موافقة HR
                    </Button>
                    <Button
                      size="sm" variant="secondary"
                      icon={<X size={14} />}
                      style={{ flex: 1, color: 'var(--color-danger)', borderColor: 'color-mix(in srgb, var(--color-danger) 30%, transparent)', background: 'transparent' }}
                      onClick={() => {
                        updateAdvanceStatus(adv.id, 'rejected')
                          .then(() => { toast.success('تم رفض السلفة'); qc.invalidateQueries({ queryKey: ['hr-advances'] }) })
                          .catch((e: any) => toast.error(e.message))
                      }}
                    >
                      رفض
                    </Button>
                  </div>
                </PermissionGuard>
              </div>
            ))
          )}
        </div>

        {/* ── حالة آخر مسير ── */}
        <div className="edara-card">
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            marginBottom: 'var(--space-4)',
          }}>
            <h2 style={{ fontWeight: 700, fontSize: 'var(--text-base)', margin: 0 }}>
              آخر مسير رواتب
            </h2>
            <Button
              variant="ghost" size="sm"
              onClick={() => navigate('/hr/payroll')}
              style={{ fontSize: 'var(--text-xs)' }}
            >
              كل المسيرات
            </Button>
          </div>

          {payrollLoading ? (
            <div className="skeleton" style={{ height: 80, borderRadius: 8 }} />
          ) : !lastRun ? (
            <div style={{
              textAlign: 'center', padding: 'var(--space-6)',
              color: 'var(--text-muted)', fontSize: 'var(--text-sm)',
            }}>
              <FileSpreadsheet size={28} style={{ display: 'block', margin: '0 auto var(--space-2)', opacity: 0.4 }} />
              لا توجد مسيرات بعد
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
              {/* معلومات المسير */}
              <div style={{
                padding: 'var(--space-4)',
                background: 'var(--bg-card)',
                borderRadius: 'var(--radius-lg)',
                border: '1px solid var(--border-primary)',
                boxShadow: '0 4px 12px rgba(0,0,0,0.02)',
              }}>
                <div style={{ fontWeight: 800, fontSize: '1.1rem', marginBottom: 'var(--space-3)', color: 'var(--text-primary)' }}>
                  {lastRun.period?.name ?? lastRun.number ?? '—'}
                </div>
                <div style={{
                  display: 'grid', gridTemplateColumns: '1fr 1fr',
                  gap: 'var(--space-3)', fontSize: 'var(--text-sm)',
                }}>
                  <div style={{ background: 'var(--bg-surface-2)', padding: 'var(--space-3)', borderRadius: 'var(--radius-md)' }}>
                    <div style={{ color: 'var(--text-secondary)', fontSize: 'var(--text-xs)', marginBottom: 2 }}>إجمالي الموظفين</div>
                    <div style={{ fontWeight: 800, color: 'var(--text-primary)' }}>{lastRun.total_employees}</div>
                  </div>
                  <div style={{ background: 'color-mix(in srgb, var(--color-primary) 5%, var(--bg-surface-2))', padding: 'var(--space-3)', borderRadius: 'var(--radius-md)' }}>
                    <div style={{ color: 'var(--color-primary)', opacity: 0.85, fontSize: 'var(--text-xs)', marginBottom: 2 }}>الصافي النهائي</div>
                    <div style={{ fontWeight: 800, color: 'var(--color-primary)' }}>
                      {fmt(lastRun.total_net)}
                    </div>
                  </div>
                </div>
              </div>

              {/* حالة المسير */}
              {lastRun.status === 'review' ? (
                <div style={{
                  display: 'flex', alignItems: 'center', gap: 'var(--space-2)',
                  padding: 'var(--space-3)',
                  background: 'color-mix(in srgb, var(--color-warning) 8%, transparent)',
                  border: '1px solid color-mix(in srgb, var(--color-warning) 20%, transparent)',
                  borderRadius: 'var(--radius-md)',
                  fontSize: 'var(--text-xs)',
                }}>
                  <AlertCircle size={13} style={{ color: 'var(--color-warning)', flexShrink: 0 }} />
                  <span>ينتظر الاعتماد المالي</span>
                  <PermissionGuard permission="hr.payroll.approve">
                    <Button
                      size="sm"
                      style={{ marginInlineEnd: 'auto', fontSize: 'var(--text-xs)', padding: '2px 10px' }}
                      onClick={() => navigate(`/hr/payroll/${lastRun.id}`)}
                    >
                      مراجعة واعتماد
                    </Button>
                  </PermissionGuard>
                </div>
              ) : lastRun.status === 'approved' ? (
                <div style={{
                  display: 'flex', alignItems: 'center', gap: 'var(--space-2)',
                  fontSize: 'var(--text-xs)', color: 'var(--color-success)',
                }}>
                  <CheckCircle size={13} />
                  <span>مُعتمد — {fmtDate(lastRun.approved_at)}</span>
                </div>
              ) : (
                <div style={{
                  display: 'flex', alignItems: 'center', gap: 'var(--space-2)',
                  fontSize: 'var(--text-xs)', color: 'var(--text-muted)',
                }}>
                  <Clock size={13} />
                  <span>الحالة: {lastRun.status}</span>
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      <style>{`
        .quick-action-btn:hover {
          transform: translateY(-2px);
          box-shadow: 0 4px 12px -2px var(--border-primary);
          background: var(--bg-card) !important;
        }
        .qa-arrow-icon {
          transition: transform 0.2s;
        }
        .quick-action-btn:hover .qa-arrow-icon {
          transform: translateX(-3px);
        }
        html[dir="ltr"] .quick-action-btn:hover .qa-arrow-icon {
          transform: translateX(3px);
        }
      `}</style>

      {/* GAP-01: مودال رفض الإجازة مع سبب */}
      <ResponsiveModal
        open={!!rejectLeave}
        onClose={() => { setRejectLeave(null); setRejectReason('') }}
        title={`رفض إجازة — ${rejectLeave?.employee?.full_name ?? ''}`}
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => { setRejectLeave(null); setRejectReason('') }} style={{ flex: 1 }}>إلغاء</Button>
            <Button
              onClick={handleQuickRejectLeave}
              loading={rejecting}
              disabled={!rejectReason.trim()}
              style={{ flex: 2, background: 'var(--color-danger)' }}
            >
              تأكيد الرفض
            </Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <div style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)', background: 'var(--bg-surface-2)', padding: 'var(--space-3)', borderRadius: 'var(--radius-md)' }}>
            {rejectLeave?.leave_type?.name} · {rejectLeave?.days_count} يوم
          </div>
          <div className="form-group">
            <label className="form-label">سبب الرفض <span style={{ color: 'var(--color-danger)' }}>*</span></label>
            <textarea
              className="form-input"
              rows={3}
              value={rejectReason}
              onChange={e => setRejectReason(e.target.value)}
              placeholder="اكتب سبب رفض طلب الإجازة..."
              style={{ resize: 'vertical', minHeight: 80 }}
              autoFocus
            />
          </div>
        </div>
      </ResponsiveModal>
    </div>
  )
}
