import { useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import {
  CheckCircle, ArrowRight, Users, TrendingDown,
  TrendingUp, DollarSign, BookOpen, AlertCircle, Edit3, RefreshCw, Calculator,
} from 'lucide-react'
import {
  useHRPayrollRuns,
  useHRPayrollLines,
  useApprovePayrollRun,
  useCalculatePayrollRun,
  useHRAdjustments,
  useAttendanceReviewSummary,
  useHRPayrollPayments,
  useDisbursePayrollPayment,
  useVaults,
} from '@/hooks/useQueryHooks'
import { updatePayrollLine } from '@/lib/services/hr'
import type { HRPayrollRun, HRPayrollLine, HRPayrollRunStatus } from '@/lib/types/hr'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Input from '@/components/ui/Input'
import Select from '@/components/ui/Select'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import PermissionGuard from '@/components/shared/PermissionGuard'
import { toast } from 'sonner'

// ─── حالات المسير ─────────────────────────────────────
const STATUS_LABEL: Record<HRPayrollRunStatus, string> = {
  draft:       'مسودة',
  calculating: 'قيد الحساب',
  review:      'مراجعة',
  approved:    'مُعتمد',
  paid:        'مدفوع',
  cancelled:   'ملغي',
}

const STATUS_VARIANT: Record<HRPayrollRunStatus, 'neutral' | 'warning' | 'info' | 'success' | 'danger'> = {
  draft:       'neutral',
  calculating: 'warning',
  review:      'info',
  approved:    'success',
  paid:        'success',
  cancelled:   'danger',
}

const fmt = (n: number) =>
  n.toLocaleString('ar-EG-u-nu-latn', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' ج.م'

// ─── StatCard ─────────────────────────────────────────
function StatCard({ label, value, icon, color }: {
  label: string; value: string; icon: React.ReactNode; color: string
}) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 'var(--space-3)',
      padding: 'var(--space-4)',
      background: `color-mix(in srgb, ${color} 7%, transparent)`,
      border: `1px solid color-mix(in srgb, ${color} 20%, transparent)`,
      borderRadius: 'var(--radius-lg)',
    }}>
      <div style={{
        width: 40, height: 40, borderRadius: 'var(--radius-md)',
        background: `color-mix(in srgb, ${color} 15%, transparent)`,
        color, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
      }}>
        {icon}
      </div>
      <div>
        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 2 }}>{label}</div>
        <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', color, fontVariantNumeric: 'tabular-nums' }}>
          {value}
        </div>
      </div>
    </div>
  )
}

// ═════════════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════════════

export default function PayrollRunDetail() {
  const { runId } = useParams<{ runId: string }>()
  const navigate  = useNavigate()
  const qc        = useQueryClient()
  const [confirmApprove, setConfirmApprove] = useState(false)

  // F-E+F-F: inline edit state
  const [editLine, setEditLine]       = useState<HRPayrollLine | null>(null)
  const [editBonus, setEditBonus]     = useState('')
  const [editDeduction, setEditDeduction] = useState('')
  const [editOverride, setEditOverride]   = useState('')
  const [saving, setSaving]           = useState(false)

  // DSN-07: row expand لعرض التفاصيل على الموبايل
  const [expandedLine, setExpandedLine] = useState<HRPayrollLine | null>(null)

  // -- Disbursement Form State --
  const [showDisburseModal, setShowDisburseModal] = useState(false)
  const [disburseVaultId, setDisburseVaultId] = useState('')
  const [disburseAmount, setDisburseAmount] = useState('')
  const [disburseDate, setDisburseDate] = useState(new Date().toISOString().split('T')[0])
  const [disburseNotes, setDisburseNotes] = useState('')

  // جلب الخزائن النشطة
  const { data: vaults = [] } = useVaults({ isActive: true })

  // جلب بيانات المسير (تحديث تلقائي كل 15 ثانية)
  const { data: runs = [], isLoading: runsLoading, dataUpdatedAt: runsUpdatedAt, refetch: refetchRuns } = useHRPayrollRuns()
  const run: HRPayrollRun | undefined = runs.find(r => r.id === runId)
  const periodStart = run?.period?.start_date ?? null
  const periodEnd = run?.period?.end_date ?? null
  const { data: attendanceReview } = useAttendanceReviewSummary(periodStart, periodEnd, run?.branch_id)

  // سطور الرواتب (تحديث تلقائي كل 15 ثانية)
  const { data: lines = [], isLoading: linesLoading, dataUpdatedAt: linesUpdatedAt, refetch: refetchLines } = useHRPayrollLines(runId ?? null)

  const lastUpdate = Math.max(runsUpdatedAt || 0, linesUpdatedAt || 0)
  const handleManualRefresh = () => { refetchRuns(); refetchLines() }

  // دفعات مسير الرواتب
  const { data: payments = [] } = useHRPayrollPayments(runId ?? null)
  const disburseMut = useDisbursePayrollPayment()

  // mutation الاعتماد
  const approveMutation = useApprovePayrollRun()
  const calculateMut = useCalculatePayrollRun()
  const [recalculating, setRecalculating] = useState(false)

  // تعديلات معتمدة لم تُحتسب بعد
  const { data: allAdjustments = [] } = useHRAdjustments({ status: 'approved' })
  const pendingAdj = run ? allAdjustments.filter(a => a.payroll_line_id === null) : []
  const hasPendingAdjustments = pendingAdj.length > 0

  const hasAttendanceRisk = !!attendanceReview && attendanceReview.total_blocking_items > 0
  const canApprove = run && ['review', 'calculating'].includes(run.status) && !hasAttendanceRisk

  const handleCalculatePayroll = async () => {
    if (!runId) return
    setRecalculating(true)
    try {
      const result = await calculateMut.mutateAsync({ runId })
      toast.success(`✅ تم الحساب بنجاح — ${result.calculated} موظف`)
    } catch (err) {
      toast.error(`فشل الحساب: ${err instanceof Error ? err.message : String(err)}`)
    } finally {
      setRecalculating(false)
    }
  }

  const handleApprove = async () => {
    if (!runId) return
    try {
      const result = await approveMutation.mutateAsync(runId)
      toast.success(
        <div>
          <div style={{ fontWeight: 700 }}>✅ تم اعتماد مسير الرواتب!</div>
          <div style={{ fontSize: '0.85em', marginTop: 4, fontFamily: 'monospace', opacity: 0.8 }}>
            قيد: {result.journal_entry_id?.slice(0, 8)}...
          </div>
          <div style={{ fontSize: '0.85em', opacity: 0.7 }}>
            {result.total_employees} موظف · صافي: {fmt(result.accounting_summary?.credit?.cr_2310_net_payable ?? 0)}
          </div>
        </div>
      )
      setConfirmApprove(false)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      // رسائل الأخطاء المالية المعروفة
      if (msg.includes('يجب أن يكون') || msg.includes('متوازن') || msg.includes('balanced')) {
        toast.error(`❌ القيد المحاسبي غير متوازن — تحقق من بيانات الموظفين قبل إعادة المحاولة`)
      } else {
        toast.error(`فشل الاعتماد: ${msg}`)
      }
    }
  }

  const handleDisburse = async () => {
    if (!runId || !disburseVaultId || !disburseAmount) return
    const amountNum = parseFloat(disburseAmount)
    if (isNaN(amountNum) || amountNum <= 0) {
      toast.error('المبلغ غير صحيح')
      return
    }

    try {
      await disburseMut.mutateAsync({
        run_id: runId,
        vault_id: disburseVaultId,
        amount: amountNum,
        payment_date: disburseDate,
        notes: disburseNotes || undefined,
      })
      toast.success('تم تسجيل الدفعة بنجاح وخصم المبلغ من الخزنة')
      setShowDisburseModal(false)
      setDisburseVaultId('')
      setDisburseAmount('')
      setDisburseNotes('')
    } catch (err: any) {
      toast.error(`فشل الصرف: ${err.message}`)
    }
  }

  // ── تحديث سطر الراتب (F-E+F-F) ──────────────────────
  const handleSaveEdit = async () => {
    if (!editLine) return
    setSaving(true)
    try {
      await updatePayrollLine(editLine.id, {
        bonus_amount:     editBonus     ? parseFloat(editBonus)     : undefined,
        other_deductions: editDeduction ? parseFloat(editDeduction) : undefined,
        override_net:     editOverride  ? parseFloat(editOverride)  : undefined,
      })
      toast.success(`تم تحديث سطر ${editLine.employee?.full_name ?? ''}`)
      setEditLine(null)
      // GAP-09: إعادة تحميل سطور الراتب فوراً لتحديث الجدول
      qc.invalidateQueries({ queryKey: ['hr-payroll-lines', runId] })
      qc.invalidateQueries({ queryKey: ['hr-payroll-runs'] })
    } catch (e: any) {
      toast.error(e.message ?? 'فشل التحديث')
    } finally {
      setSaving(false)
    }
  }

  const openEdit = (line: HRPayrollLine) => {
    setEditLine(line)
    setEditBonus(line.bonus_amount ? String(line.bonus_amount) : '')
    setEditDeduction(line.other_deductions ? String(line.other_deductions) : '')
    setEditOverride(line.override_net   ? String(line.override_net)   : '')
  }

  // ── أعمدة الجدول ────────────────────────────────────
  const isEditable = run?.status === 'review'

  const columns = [
    {
      key: 'employee',
      label: 'الموظف',
      render: (r: HRPayrollLine) => (
        <div>
          <div style={{ fontWeight: 600 }}>{r.employee?.full_name ?? '—'}</div>
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
            {r.employee?.employee_number}
          </div>
        </div>
      ),
    },
    {
      key: 'gross_earned',
      label: 'الإجمالي',
      align: 'end' as const,
      render: (r: HRPayrollLine) => (
        <span style={{ fontVariantNumeric: 'tabular-nums', color: 'var(--color-success)', fontWeight: 600 }}>
          {fmt(r.gross_earned)}
        </span>
      ),
    },
    {
      key: 'overtime_amount',
      label: 'إضافي',
      align: 'end' as const,
      hideOnMobile: true,
      render: (r: HRPayrollLine) => (
        <span style={{ fontVariantNumeric: 'tabular-nums', fontSize: 'var(--text-xs)', color: r.overtime_amount > 0 ? 'var(--color-info)' : 'var(--text-muted)' }}>
          {r.overtime_amount > 0 ? fmt(r.overtime_amount) : '—'}
        </span>
      ),
    },
    {
      key: 'commission_amount',
      label: 'عمولات',
      align: 'end' as const,
      hideOnMobile: true,
      render: (r: HRPayrollLine) => (
        <span style={{ fontVariantNumeric: 'tabular-nums', fontSize: 'var(--text-xs)', color: r.commission_amount > 0 ? 'var(--color-primary)' : 'var(--text-muted)' }}>
          {r.commission_amount > 0 ? fmt(r.commission_amount) : '—'}
        </span>
      ),
    },
    {
      key: 'bonus',
      label: 'مكافأة',
      align: 'end' as const,
      hideOnMobile: true,
      render: (r: HRPayrollLine) => (
        <span style={{ fontVariantNumeric: 'tabular-nums', fontSize: 'var(--text-xs)', color: (r.bonus_amount ?? 0) > 0 ? 'var(--color-success)' : 'var(--text-muted)' }}>
          {(r.bonus_amount ?? 0) > 0 ? fmt(r.bonus_amount ?? 0) : '—'}
        </span>
      ),
    },
    {
      key: 'absence_deduction',
      label: 'غياب',
      align: 'end' as const,
      hideOnMobile: true,
      render: (r: HRPayrollLine) => (
        <span style={{ fontVariantNumeric: 'tabular-nums', fontSize: 'var(--text-xs)', color: r.absence_deduction > 0 ? 'var(--color-warning)' : 'var(--text-muted)' }}>
          {r.absence_deduction > 0 ? `(${fmt(r.absence_deduction)})` : '—'}
        </span>
      ),
    },
    {
      key: 'advance_deduction',
      label: 'سلف',
      align: 'end' as const,
      hideOnMobile: true,
      render: (r: HRPayrollLine) => (
        <span style={{ fontVariantNumeric: 'tabular-nums', fontSize: 'var(--text-xs)', color: r.advance_deduction > 0 ? 'var(--color-danger)' : 'var(--text-muted)' }}>
          {r.advance_deduction > 0 ? `(${fmt(r.advance_deduction)})` : '—'}
        </span>
      ),
    },
    {
      key: 'other_deductions',
      label: 'خصومات يدوية',
      align: 'end' as const,
      hideOnMobile: true,
      render: (r: HRPayrollLine) => (
        <span style={{ fontVariantNumeric: 'tabular-nums', fontSize: 'var(--text-xs)', color: (r.other_deductions ?? 0) > 0 ? 'var(--color-danger)' : 'var(--text-muted)' }}>
          {(r.other_deductions ?? 0) > 0 ? `(${fmt(r.other_deductions ?? 0)})` : '—'}
        </span>
      ),
    },
    {
      key: 'net_salary',
      label: 'الصافي',
      align: 'end' as const,
      render: (r: HRPayrollLine) => (
        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', justifyContent: 'flex-end' }}>
          <span style={{
            fontWeight: 700, fontVariantNumeric: 'tabular-nums',
            color: r.override_net ? 'var(--color-warning)' : 'var(--color-primary)',
          }}>
            {fmt(r.override_net ?? r.net_salary)}
          </span>
          {r.override_net && (
            <span style={{ fontSize: 9, color: 'var(--color-warning)', background: 'color-mix(in srgb, var(--color-warning) 15%, transparent)', padding: '1px 4px', borderRadius: 4 }}>
              تجاوز
            </span>
          )}
          {(r.deficit_carryover ?? 0) > 0 && (
            <span title={`عجز مُرحّل: ${fmt(r.deficit_carryover)}`} style={{
              fontSize: 9, color: 'var(--color-danger)',
              background: 'color-mix(in srgb, var(--color-danger) 15%, transparent)',
              padding: '1px 4px', borderRadius: 4, cursor: 'help',
            }}>
              عجز {fmt(r.deficit_carryover)}
            </span>
          )}
          {isEditable && (
            <Button size="sm" variant="ghost" onClick={() => openEdit(r)} style={{ padding: '2px 4px' }}>
              <Edit3 size={11} />
            </Button>
          )}
        </div>
      ),
    },
  ]


  if (!runId || (!runsLoading && !run)) {
    return (
      <div className="page-container" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: 300 }}>
        <div style={{ textAlign: 'center', color: 'var(--text-muted)' }}>
          <AlertCircle size={40} style={{ marginBottom: 'var(--space-3)', opacity: 0.4 }} />
          <div>مسير الرواتب غير موجود</div>
        </div>
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">

      <PageHeader
        title={run ? `مسير ${run.period?.name ?? ''}` : 'تفاصيل المسير'}
        subtitle={run?.number ?? ''}
        breadcrumbs={[
          { label: 'الموارد البشرية' },
          { label: 'مسير الرواتب', path: '/hr/payroll' },
          { label: run?.period?.name ?? '...' },
        ]}
        actions={
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap' }}>
            {/* مؤشر التحديث اللحظي */}
            {lastUpdate > 0 && (
              <div style={{
                display: 'flex', alignItems: 'center', gap: 4,
                fontSize: 'var(--text-xs)', color: 'var(--text-muted)',
                padding: '2px 8px', borderRadius: 'var(--radius-sm)',
                background: 'color-mix(in srgb, var(--color-success) 8%, transparent)',
              }}>
                <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--color-success)', display: 'inline-block' }} />
                تحديث تلقائي · {new Date(lastUpdate).toLocaleTimeString('ar-EG-u-nu-latn', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
              </div>
            )}
            <Button
              variant="ghost"
              size="sm"
              icon={<RefreshCw size={13} />}
              onClick={handleManualRefresh}
              title="تحديث يدوي"
            />
            {run && (
              <Badge variant={STATUS_VARIANT[run.status]}>
                {STATUS_LABEL[run.status]}
              </Badge>
            )}
            {run && ['draft', 'review'].includes(run.status) && (
              <PermissionGuard permission="hr.payroll.calculate">
                <Button
                  size="sm"
                  icon={<Calculator size={14} />}
                  onClick={handleCalculatePayroll}
                  loading={recalculating}
                  disabled={hasAttendanceRisk}
                  title={hasAttendanceRisk ? 'أغلق حالات الحضور أولاً لتتمكن من الحساب' : undefined}
                >
                  {run.status === 'draft' ? 'حساب المسير' : 'إعادة حساب'}
                </Button>
              </PermissionGuard>
            )}
            <Button
              variant="ghost"
              size="sm"
              icon={<ArrowRight size={14} />}
              onClick={() => navigate('/hr/payroll')}
            >
              العودة
            </Button>
          </div>
        }
      />

      {/* ── بطاقات الإجماليات ── */}
      {run && (
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
          gap: 'var(--space-3)',
          marginBottom: 'var(--space-4)',
        }}>
          <StatCard
            label="الإجمالي الكلي"
            value={fmt(run.total_gross)}
            icon={<TrendingUp size={18} />}
            color="var(--color-success)"
          />
          <StatCard
            label="إجمالي الاستقطاعات"
            value={fmt(run.total_deductions)}
            icon={<TrendingDown size={18} />}
            color="var(--color-warning)"
          />
          <StatCard
            label="الصافي الإجمالي"
            value={fmt(run.total_net)}
            icon={<DollarSign size={18} />}
            color="var(--color-primary)"
          />
          <StatCard
            label="عدد الموظفين"
            value={`${run.total_employees} موظف`}
            icon={<Users size={18} />}
            color="var(--color-info)"
          />
        </div>
      )}

      {/* ── تنبيه: تعديلات غير محتسبة ── */}
      {hasPendingAdjustments && run?.status === 'review' && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 'var(--space-3)',
          padding: 'var(--space-3) var(--space-4)', borderRadius: 'var(--radius-md)',
          background: 'color-mix(in srgb, var(--color-warning) 8%, transparent)',
          border: '1px solid color-mix(in srgb, var(--color-warning) 25%, transparent)',
          marginBottom: 'var(--space-3)',
        }}>
          <AlertCircle size={16} style={{ color: 'var(--color-warning)', flexShrink: 0 }} />
          <div style={{ flex: 1 }}>
            <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)', color: 'var(--color-warning)' }}>
              يوجد {pendingAdj.length} تعديل (مكافآت/خصومات) معتمد لم يُحتسب في المسير بعد
            </div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
              اضغط "إعادة الحساب" لتضمينها في الراتب
            </div>
          </div>
          <PermissionGuard permission="hr.payroll.calculate">
            <Button
              size="sm"
              icon={<Calculator size={14} />}
              onClick={handleCalculatePayroll}
              loading={recalculating}
              disabled={hasAttendanceRisk}
              title={hasAttendanceRisk ? 'أغلق حالات الحضور أولاً لتتمكن من الحساب' : undefined}
            >
              إعادة الحساب
            </Button>
          </PermissionGuard>
        </div>
      )}

      {/* ── شريط التعليمات عند المراجعة ── */}
      {run?.status === 'review' && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 'var(--space-2)',
          padding: 'var(--space-3) var(--space-4)', borderRadius: 'var(--radius-md)',
          background: 'color-mix(in srgb, var(--color-info) 6%, transparent)',
          border: '1px solid color-mix(in srgb, var(--color-info) 20%, transparent)',
          fontSize: 'var(--text-xs)', color: 'var(--text-muted)',
          marginBottom: 'var(--space-3)',
        }}>
          <Edit3 size={13} style={{ color: 'var(--color-info)', flexShrink: 0 }} />
          <span>وضع المراجعة — يمكنك تعديل المكافآت والخصومات الإضافية لكل موظف قبل الاعتماد</span>
          {!hasPendingAdjustments && (
            <PermissionGuard permission="hr.payroll.calculate">
              <Button
                size="sm"
                variant="ghost"
                icon={<Calculator size={13} />}
                onClick={handleCalculatePayroll}
                loading={recalculating}
                disabled={hasAttendanceRisk}
                title={hasAttendanceRisk ? 'أغلق حالات الحضور أولاً لتتمكن من الحساب' : undefined}
                style={{ marginInlineStart: 'auto', flexShrink: 0 }}
              >
                إعادة حساب
              </Button>
            </PermissionGuard>
          )}
        </div>
      )}

      {/* ── زر الاعتماد المالي ── */}
      {hasAttendanceRisk && attendanceReview && ['draft', 'review', 'calculating'].includes(run?.status || '') && (
        <div style={{
          padding: 'var(--space-4)',
          background: 'color-mix(in srgb, var(--color-danger) 7%, transparent)',
          border: '1px solid color-mix(in srgb, var(--color-danger) 24%, transparent)',
          borderRadius: 'var(--radius-lg)',
          marginBottom: 'var(--space-4)',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginBottom: 'var(--space-3)' }}>
            <AlertCircle size={18} style={{ color: 'var(--color-danger)', flexShrink: 0 }} />
            <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--color-danger)' }}>
              توجد حالات حضور غير محسومة تمنع حساب أو اعتماد المسير حالياً
            </div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', fontSize: 'var(--text-sm)' }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--color-danger)', flexShrink: 0 }} />
              <span style={{ color: 'var(--color-danger)', fontWeight: 600 }}>يوجد {attendanceReview.unclosed_days} أيام حضور بدون انصراف</span>
              <span style={{ color: 'var(--text-secondary)' }}>يرجى إغلاق أيام الحضور المفتوحة (تعديل يدوي) لتحديد أثرها المالي بدقة.</span>
            </div>
          </div>
          <div style={{ marginTop: 'var(--space-3)', fontSize: 'var(--text-xs)', color: 'var(--text-muted)', borderTop: '1px solid color-mix(in srgb, var(--color-danger) 15%, transparent)', paddingTop: 'var(--space-2)' }}>
            ارجع لصفحة الحضور وأغلق هذه الحالات قبل الحساب أو الاعتماد.
          </div>
        </div>
      )}

      {canApprove && !run?.journal_entry_id && (
        <PermissionGuard permission="hr.payroll.approve">
          <div style={{
            display: 'flex', alignItems: 'center', gap: 'var(--space-3)',
            padding: 'var(--space-4)',
            background: 'color-mix(in srgb, var(--color-primary) 5%, transparent)',
            border: '1px solid color-mix(in srgb, var(--color-primary) 20%, transparent)',
            borderRadius: 'var(--radius-lg)',
            marginBottom: 'var(--space-4)',
          }}>
            <BookOpen size={18} style={{ color: 'var(--color-primary)', flexShrink: 0 }} />
            <div style={{ flex: 1 }}>
              <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>جاهز للاعتماد المالي</div>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                عند الاعتماد سيُنشأ قيد يومية متوازن (Dr. 5310 / Cr. 2310/2320/2330) ويُغلق المسير.
              </div>
            </div>
            {!confirmApprove ? (
              <Button
                id="btn-initiate-approve"
                icon={<CheckCircle size={14} />}
                onClick={() => setConfirmApprove(true)}
              >
                اعتماد المسير
              </Button>
            ) : (
              <div style={{ display: 'flex', gap: 'var(--space-2)' }}>
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={() => setConfirmApprove(false)}
                  disabled={approveMutation.isPending}
                >
                  إلغاء
                </Button>
                <Button
                  id="btn-confirm-approve"
                  size="sm"
                  onClick={handleApprove}
                  loading={approveMutation.isPending}
                  style={{ background: 'var(--color-success)' }}
                >
                  تأكيد الاعتماد
                </Button>
              </div>
            )}
          </div>
        </PermissionGuard>
      )}

      {/* ── رابط القيد المحاسبي (بعد الاعتماد) ── */}
      {run?.journal_entry_id && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 'var(--space-2)',
          padding: 'var(--space-3) var(--space-4)',
          background: 'color-mix(in srgb, var(--color-success) 6%, transparent)',
          border: '1px solid color-mix(in srgb, var(--color-success) 20%, transparent)',
          borderRadius: 'var(--radius-md)',
          fontSize: 'var(--text-sm)',
          marginBottom: 'var(--space-4)',
        }}>
          <CheckCircle size={15} style={{ color: 'var(--color-success)', flexShrink: 0 }} />
          <span>تم الاعتماد — قيد يومية: </span>
          <code style={{
            background: 'var(--bg-surface-2)',
            padding: '1px 6px', borderRadius: 4,
            fontFamily: 'monospace', fontSize: '0.85em',
          }}>
            {run.journal_entry_id.slice(0, 16)}…
          </code>
        </div>
      )}

      {/* ── قسم دفعات مسير الرواتب ── */}
      {run?.status && ['approved', 'paid'].includes(run.status) && (
        <div style={{
          padding: 'var(--space-4)',
          background: 'var(--bg-surface)',
          border: '1px solid var(--border-primary)',
          borderRadius: 'var(--radius-lg)',
          marginBottom: 'var(--space-4)',
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-3)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 600, display: 'flex', alignItems: 'center', gap: 8 }}>
              <DollarSign size={18} style={{ color: 'var(--color-primary)' }} />
              دفعات الرواتب المنصرفة
            </h3>
            {run.status === 'approved' && (
              <PermissionGuard permission="hr.payroll.disburse">
                <Button size="sm" onClick={() => {
                  const totalPaid = payments.filter(p => p.status === 'posted').reduce((acc, p) => acc + (Number(p.amount) || 0), 0)
                  const remaining = Math.max(0, run.total_net - totalPaid)
                  setDisburseAmount(remaining.toString())
                  setShowDisburseModal(true)
                }}>
                  تسجيل دفعة صرف
                </Button>
              </PermissionGuard>
            )}
          </div>
          
          <div style={{
            display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 'var(--space-3)',
            background: 'var(--bg-surface-2)', padding: 'var(--space-3)', borderRadius: 'var(--radius-md)',
            marginBottom: 'var(--space-4)'
          }}>
            <div>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>إجمالي المستحق</div>
              <div style={{ fontWeight: 600, color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>{fmt(run.total_net)}</div>
            </div>
            <div>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>المدفوع</div>
              <div style={{ fontWeight: 600, color: 'var(--color-success)', fontVariantNumeric: 'tabular-nums' }}>
                {fmt(payments.filter(p => p.status === 'posted').reduce((acc, p) => acc + (Number(p.amount) || 0), 0))}
              </div>
            </div>
            <div>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>المتبقي (الرصيد الدائن)</div>
              <div style={{ fontWeight: 600, color: 'var(--color-warning)', fontVariantNumeric: 'tabular-nums' }}>
                {fmt(Math.max(0, run.total_net - payments.filter(p => p.status === 'posted').reduce((acc, p) => acc + (Number(p.amount) || 0), 0)))}
              </div>
            </div>
          </div>

          {payments.length > 0 ? (
            <div style={{ overflowX: 'auto' }}>
              <table className="edara-table">
                <thead>
                  <tr>
                    <th>تاريخ الدفع</th>
                    <th>الخزنة</th>
                    <th style={{ textAlign: 'left' }}>المبلغ</th>
                    <th>بواسطة</th>
                    <th>ملاحظات</th>
                  </tr>
                </thead>
                <tbody>
                  {payments.map(p => (
                    <tr key={p.id}>
                      <td style={{ fontVariantNumeric: 'tabular-nums' }}>{p.payment_date}</td>
                      <td>
                        <div style={{ fontWeight: 500 }}>{p.vault?.name}</div>
                        <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{p.vault_txn_id?.slice(0,8)}...</div>
                      </td>
                      <td style={{ textAlign: 'left', fontWeight: 600, color: 'var(--color-success)', fontVariantNumeric: 'tabular-nums' }}>
                        {fmt(p.amount)}
                      </td>
                      <td>{p.creator?.full_name}</td>
                      <td style={{ color: 'var(--text-muted)' }}>{p.notes || '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div style={{ textAlign: 'center', color: 'var(--text-muted)', fontSize: 'var(--text-sm)', padding: 'var(--space-4)' }}>
              لم يتم تسجيل أي دفعات حتى الآن.
            </div>
          )}
        </div>
      )}

      {/* ── جدول سطور الرواتب ── */}
      <div className="edara-card" style={{ padding: 0, overflow: 'hidden' }}>
        <DataTable
          columns={columns}
          data={lines}
          loading={linesLoading || runsLoading}
          keyField="id"
          emptyIcon={<Users size={40} />}
          emptyTitle={run?.status === 'draft' ? 'لم يتم حساب المسير بعد' : 'لا توجد بيانات'}
          emptyText={run?.status === 'draft' ? 'اضغط حساب المسير لتجميع بيانات الحضور والجزاءات والسلف والعمولات.' : 'لم يتم حساب الرواتب بعد — أو لا يوجد موظفون نشطون'}
          emptyAction={
            run?.status === 'draft' ? (
              <PermissionGuard permission="hr.payroll.calculate">
                <Button
                  size="sm"
                  icon={<Calculator size={14} />}
                  onClick={handleCalculatePayroll}
                  loading={recalculating}
                  disabled={hasAttendanceRisk}
                  title={hasAttendanceRisk ? 'أغلق حالات الحضور أولاً لتتمكن من الحساب' : undefined}
                  style={{ marginTop: 'var(--space-3)' }}
                >
                  حساب المسير الآن
                </Button>
              </PermissionGuard>
            ) : undefined
          }
          onRowClick={r => setExpandedLine(r)}
        />
      </div>

      {/* DSN-07: Modal تفاصيل سطر الراتب — للموبايل */}
      {expandedLine && (
        <ResponsiveModal
          open={!!expandedLine}
          onClose={() => setExpandedLine(null)}
          title={`تفاصيل: ${expandedLine.employee?.full_name ?? ''}`}
          size="sm"
          footer={
            <div style={{ display: 'flex', gap: 'var(--space-2)', width: '100%' }}>
              {isEditable && (
                <Button
                  variant="secondary"
                  icon={<Edit3 size={14} />}
                  onClick={() => { openEdit(expandedLine); setExpandedLine(null) }}
                  style={{ flex: 1 }}
                >
                  تعديل
                </Button>
              )}
              <Button onClick={() => setExpandedLine(null)} style={{ flex: 1 }}>إغلاق</Button>
            </div>
          }
        >
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            {([
              ['رقم الموظف',  expandedLine.employee?.employee_number ?? '—'],
              ['الإجمالي',    fmt(expandedLine.gross_earned)],
              ['إضافي',       expandedLine.overtime_amount > 0 ? fmt(expandedLine.overtime_amount) : '—'],
              ['عمولات',      expandedLine.commission_amount > 0 ? fmt(expandedLine.commission_amount) : '—'],
              ['مكافأة',      (expandedLine.bonus_amount ?? 0) > 0 ? fmt(expandedLine.bonus_amount ?? 0) : '—'],
              ['خصم غياب',    expandedLine.absence_deduction > 0 ? `(${fmt(expandedLine.absence_deduction)})` : '—'],
              ['خصم جزاءات',  expandedLine.penalty_deduction > 0 ? `(${fmt(expandedLine.penalty_deduction)})` : '—'],
              ['خصومات يدوية', (expandedLine.other_deductions ?? 0) > 0 ? `(${fmt(expandedLine.other_deductions ?? 0)})` : '—'],
              ['خصم سلف',     expandedLine.advance_deduction > 0 ? `(${fmt(expandedLine.advance_deduction)})` : '—'],
              ['إجمالي استقطاعات', expandedLine.total_deductions > 0 ? `(${fmt(expandedLine.total_deductions)})` : '—'],
              ['صافي الراتب', fmt(expandedLine.override_net ?? expandedLine.net_salary)],
            ] as [string, string][]).map(([label, value]) => (
              <div key={label} style={{
                display: 'flex', justifyContent: 'space-between',
                padding: 'var(--space-2) 0',
                borderBottom: '1px solid var(--border-primary)',
                fontSize: 'var(--text-sm)',
              }}>
                <span style={{ color: 'var(--text-muted)' }}>{label}</span>
                <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{value}</span>
              </div>
            ))}

            {/* ★ عجز مُرحّل للشهر التالي */}
            {(expandedLine.deficit_carryover ?? 0) > 0 && (
              <div style={{
                display: 'flex', flexDirection: 'column', gap: 'var(--space-2)',
                marginTop: 'var(--space-2)',
                padding: 'var(--space-3)',
                background: 'color-mix(in srgb, var(--color-danger) 8%, transparent)',
                border: '1px solid color-mix(in srgb, var(--color-danger) 25%, transparent)',
                borderRadius: 'var(--radius-md)',
              }}>
                <div style={{
                  display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                }}>
                  <span style={{ fontSize: 'var(--text-sm)', fontWeight: 600, color: 'var(--color-danger)', display: 'flex', alignItems: 'center', gap: 4 }}>
                    <AlertCircle size={14} /> مبلغ مُرحّل للشهر التالي
                  </span>
                  <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: 'var(--color-danger)' }}>
                    {fmt(expandedLine.deficit_carryover)}
                  </span>
                </div>
                <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', lineHeight: 1.6 }}>
                  الخصومات تجاوزت مستحقات الموظف. سيتم خصم هذا المبلغ تلقائياً من راتب الشهر التالي كتعديل مُعتمد.
                </div>
              </div>
            )}

            {expandedLine.override_net && (
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--color-warning)', textAlign: 'center', marginTop: 4 }}>
                ⚠ هذا السطر يستخدم صافي مُتجاوِز — لا يتبع الحساب التلقائي
              </div>
            )}
          </div>
        </ResponsiveModal>
      )}

      {/* ── مودال تعديل سطر الراتب (F-E+F-F) ── */}
      <ResponsiveModal
        open={!!editLine}
        onClose={() => setEditLine(null)}
        title={`تعديل: ${editLine?.employee?.full_name ?? ''}`}
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => setEditLine(null)} style={{ flex: 1 }}>إلغاء</Button>
            <Button onClick={handleSaveEdit} loading={saving} style={{ flex: 2 }}>حفظ التعديل</Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', background: 'var(--bg-surface-2)', padding: 'var(--space-2) var(--space-3)', borderRadius: 'var(--radius-sm)' }}>
            الصافي الحالي: <strong style={{ fontVariantNumeric: 'tabular-nums' }}>{fmt(editLine?.net_salary ?? 0)}</strong>
            {editLine?.override_net ? <span style={{ color: 'var(--color-warning)', marginRight: 8 }}>← تجاوز: {fmt(editLine.override_net)}</span> : null}
          </div>
          <Input
            label="مكافأة إضافية" type="number"
            value={editBonus}
            onChange={e => setEditBonus(e.target.value)}
            placeholder="0.00"
          />
          <Input
            label="خصم إضافي" type="number"
            value={editDeduction}
            onChange={e => setEditDeduction(e.target.value)}
            placeholder="0.00"
          />
          <Input
            label="تجاوز الصافي (اختياري — يُلغي الحساب)"
            type="number"
            value={editOverride}
            onChange={e => setEditOverride(e.target.value)}
            placeholder="اتركه فارغاً للحساب التلقائي"
          />
          <div style={{ fontSize: 10, color: 'var(--color-warning)', opacity: 0.8 }}>
            ⚠ تجاوز الصافي يُلغي جميع الحسابات التلقائية لهذا الموظف
          </div>
        </div>
      </ResponsiveModal>

      {/* ── مودال صرف الرواتب ── */}
      <ResponsiveModal
        open={showDisburseModal}
        onClose={() => setShowDisburseModal(false)}
        title="تسجيل دفعة صرف رواتب"
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => setShowDisburseModal(false)} style={{ flex: 1 }}>إلغاء</Button>
            <Button 
              onClick={handleDisburse} 
              loading={disburseMut.isPending} 
              style={{ flex: 2, background: 'var(--color-success)', color: 'white' }}
              disabled={!disburseVaultId || !disburseAmount}
            >
              صرف المبلغ واعتماد الدفعة
            </Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div style={{ 
            fontSize: 'var(--text-sm)', 
            color: 'var(--color-warning)', 
            background: 'color-mix(in srgb, var(--color-warning) 10%, transparent)', 
            padding: 'var(--space-3)', 
            borderRadius: 'var(--radius-md)',
            borderLeft: '4px solid var(--color-warning)',
            lineHeight: 1.5,
          }}>
            <strong>تنبيه: </strong>
            سيتم خصم المبلغ المُدخل من الخزنة المحددة وتسجيل قيد استحقاق رواتب (Dr. 2310 / Cr. 11xx). لا يمكن التراجع عن هذه العملية حالياً.
          </div>
          
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
            <Input
              label="تاريخ الصرف *"
              type="date"
              value={disburseDate}
              onChange={e => setDisburseDate(e.target.value)}
              required
            />
            
            <Input
              label="المبلغ المُراد صرفه *"
              type="number"
              value={disburseAmount}
              onChange={e => setDisburseAmount(e.target.value)}
              placeholder="0.00"
              required
            />
          </div>

          <Select
            label="خزنة الصرف *"
            value={disburseVaultId}
            onChange={e => setDisburseVaultId(e.target.value)}
            required
            options={vaults
              .filter(v => !run?.branch_id || !v.branch_id || v.branch_id === run.branch_id)
              .map(v => ({
                value: v.id,
                label: `${v.name} (رصيد: ${fmt(v.current_balance)})`
              }))}
            placeholder="-- اختر الخزنة للخصم --"
          />

          <div className="form-group">
            <label className="form-label" htmlFor="disburseNotes">ملاحظات (اختياري)</label>
            <textarea
              id="disburseNotes"
              className="form-input"
              value={disburseNotes}
              onChange={e => setDisburseNotes(e.target.value)}
              rows={2}
              placeholder="أي ملاحظات حول سبب الصرف أو المرجعية..."
            />
          </div>
        </div>
      </ResponsiveModal>
    </div>
  )
}
