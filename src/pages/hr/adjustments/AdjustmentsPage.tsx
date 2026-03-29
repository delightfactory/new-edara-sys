import { useState } from 'react'
import { Award, Minus, AlertTriangle, Plus, CheckCircle, XCircle } from 'lucide-react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import {
  useHRAdjustments, useCreateAdjustment, useApproveAdjustment,
  useHREmployees, useHRPayrollPeriods,
} from '@/hooks/useQueryHooks'
import type { HRPayrollAdjustment, HRAdjustmentType, HRAdjustmentStatus } from '@/lib/types/hr'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Input from '@/components/ui/Input'
import Select from '@/components/ui/Select'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import PermissionGuard from '@/components/shared/PermissionGuard'

// ─── Constants ──────────────────────────────────────
const TYPE_LABEL: Record<HRAdjustmentType, string> = {
  bonus:     'مكافأة',
  deduction: 'خصم',
  penalty:   'جزاء يدوي',
}

const TYPE_ICON: Record<HRAdjustmentType, React.ReactNode> = {
  bonus:     <Award size={14} />,
  deduction: <Minus size={14} />,
  penalty:   <AlertTriangle size={14} />,
}

const TYPE_COLOR: Record<HRAdjustmentType, string> = {
  bonus:     'var(--color-success)',
  deduction: 'var(--color-warning)',
  penalty:   'var(--color-danger)',
}

const STATUS_LABEL: Record<HRAdjustmentStatus, string> = {
  pending:  'في الانتظار',
  approved: 'معتمد',
  rejected: 'مرفوض',
}

const STATUS_VARIANT: Record<HRAdjustmentStatus, 'warning' | 'success' | 'danger'> = {
  pending:  'warning',
  approved: 'success',
  rejected: 'danger',
}

const fmt = (n: number) =>
  n.toLocaleString('ar-EG-u-nu-latn', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' ج.م'

// ═════════════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════════════

export default function AdjustmentsPage() {
  const qc = useQueryClient()
  const [statusFilter, setStatusFilter] = useState<string>('')
  const [showCreate, setShowCreate] = useState(false)
  const [confirmAction, setConfirmAction] = useState<{
    adj: HRPayrollAdjustment; action: 'approve' | 'reject'
  } | null>(null)

  // Data
  const { data: adjustments = [], isLoading } = useHRAdjustments(
    statusFilter ? { status: statusFilter } : undefined
  )
  const empResult = useHREmployees()
  const employees = Array.isArray(empResult.data) ? empResult.data : (empResult.data?.data ?? [])

  // Mutations
  const createMut = useCreateAdjustment()
  const approveMut = useApproveAdjustment()

  // ─── Create form state ──────────────────────────────
  const [formEmployeeId, setFormEmployeeId] = useState('')
  const [formType, setFormType] = useState<HRAdjustmentType>('bonus')
  const [formAmount, setFormAmount] = useState('')
  const [formReason, setFormReason] = useState('')
  const [formDate, setFormDate] = useState(new Date().toISOString().split('T')[0])

  const resetForm = () => {
    setFormEmployeeId('')
    setFormType('bonus')
    setFormAmount('')
    setFormReason('')
    setFormDate(new Date().toISOString().split('T')[0])
  }

  const handleCreate = () => {
    if (!formEmployeeId || !formAmount || !formReason) {
      toast.error('يرجى ملء جميع الحقول المطلوبة')
      return
    }
    createMut.mutate({
      employee_id: formEmployeeId,
      type: formType,
      amount: parseFloat(formAmount),
      reason: formReason,
      effective_date: formDate,
    }, {
      onSuccess: () => {
        toast.success(`تم إنشاء ${TYPE_LABEL[formType]} بنجاح`)
        setShowCreate(false)
        resetForm()
      },
      onError: (e: Error) => toast.error(e.message),
    })
  }

  const handleAction = () => {
    if (!confirmAction) return
    approveMut.mutate(
      { id: confirmAction.adj.id, action: confirmAction.action },
      {
        onSuccess: () => {
          toast.success(confirmAction.action === 'approve' ? 'تم الاعتماد ✅' : 'تم الرفض ❌')
          setConfirmAction(null)
        },
        onError: (e: Error) => toast.error(e.message),
      }
    )
  }

  // ─── Stats ──────────────────────────────────────────
  const pendingCount  = adjustments.filter(a => a.status === 'pending').length
  const approvedCount = adjustments.filter(a => a.status === 'approved').length
  const totalBonuses  = adjustments.filter(a => a.type === 'bonus' && a.status === 'approved')
    .reduce((s, a) => s + a.amount, 0)
  const totalDeductions = adjustments.filter(a => a.type !== 'bonus' && a.status === 'approved')
    .reduce((s, a) => s + a.amount, 0)

  // ─── Table columns ─────────────────────────────────
  const columns = [
    {
      key: 'employee',
      label: 'الموظف',
      render: (r: HRPayrollAdjustment) => (
        <div>
          <div style={{ fontWeight: 600 }}>{r.employee?.full_name ?? '—'}</div>
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
            {r.employee?.employee_number}
          </div>
        </div>
      ),
    },
    {
      key: 'type',
      label: 'النوع',
      render: (r: HRPayrollAdjustment) => (
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span style={{
            width: 24, height: 24, borderRadius: 'var(--radius-sm)',
            background: `color-mix(in srgb, ${TYPE_COLOR[r.type]} 12%, transparent)`,
            color: TYPE_COLOR[r.type],
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            {TYPE_ICON[r.type]}
          </span>
          <span style={{ fontWeight: 500 }}>{TYPE_LABEL[r.type]}</span>
        </div>
      ),
    },
    {
      key: 'amount',
      label: 'المبلغ',
      align: 'end' as const,
      render: (r: HRPayrollAdjustment) => (
        <span style={{
          fontWeight: 700, fontVariantNumeric: 'tabular-nums',
          color: r.type === 'bonus' ? 'var(--color-success)' : 'var(--color-danger)',
        }}>
          {r.type === 'bonus' ? '+' : '-'}{fmt(r.amount)}
        </span>
      ),
    },
    {
      key: 'reason',
      label: 'السبب',
      hideOnMobile: true,
      render: (r: HRPayrollAdjustment) => (
        <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' as const, display: 'inline-block' }}>
          {r.reason}
        </span>
      ),
    },
    {
      key: 'effective_date',
      label: 'التاريخ',
      hideOnMobile: true,
      render: (r: HRPayrollAdjustment) => (
        <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)' }}>
          {new Date(r.effective_date).toLocaleDateString('ar-EG')}
        </span>
      ),
    },
    {
      key: 'status',
      label: 'الحالة',
      render: (r: HRPayrollAdjustment) => (
        <Badge variant={STATUS_VARIANT[r.status]}>
          {STATUS_LABEL[r.status]}
        </Badge>
      ),
    },
    {
      key: 'actions',
      label: '',
      render: (r: HRPayrollAdjustment) =>
        r.status === 'pending' ? (
          <PermissionGuard permission="hr.adjustments.approve">
            <div style={{ display: 'flex', gap: 4 }}>
              <Button
                size="sm"
                variant="ghost"
                icon={<CheckCircle size={14} />}
                onClick={(e) => { e.stopPropagation(); setConfirmAction({ adj: r, action: 'approve' }) }}
                style={{ color: 'var(--color-success)' }}
                title="اعتماد"
              />
              <Button
                size="sm"
                variant="ghost"
                icon={<XCircle size={14} />}
                onClick={(e) => { e.stopPropagation(); setConfirmAction({ adj: r, action: 'reject' }) }}
                style={{ color: 'var(--color-danger)' }}
                title="رفض"
              />
            </div>
          </PermissionGuard>
        ) : null,
    },
  ]

  // ─── Employee options for select ────────────────────
  const employeeOptions = employees.map((e: { id: string; employee_number: string; full_name: string }) => ({
    value: e.id,
    label: `${e.employee_number} — ${e.full_name}`,
  }))

  return (
    <div style={{ padding: 'var(--space-4)', maxWidth: 1200, margin: '0 auto' }}>
      <PageHeader
        title="مكافآت وخصومات"
        subtitle="إضافة واعتماد المكافآت والخصومات والجزاءات اليدوية"
        breadcrumbs={[
          { label: 'الموارد البشرية' },
          { label: 'مكافآت وخصومات' },
        ]}
        actions={
          <PermissionGuard permission="hr.adjustments.create">
            <Button icon={<Plus size={15} />} onClick={() => setShowCreate(true)}>
              إضافة تعديل
            </Button>
          </PermissionGuard>
        }
      />

      {/* ── بطاقات إحصائية ── */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
        gap: 'var(--space-3)',
        marginBottom: 'var(--space-4)',
      }}>
        {[
          { label: 'في الانتظار', value: String(pendingCount), color: 'var(--color-warning)', icon: <AlertTriangle size={18} /> },
          { label: 'معتمدة', value: String(approvedCount), color: 'var(--color-success)', icon: <CheckCircle size={18} /> },
          { label: 'إجمالي المكافآت', value: fmt(totalBonuses), color: 'var(--color-success)', icon: <Award size={18} /> },
          { label: 'إجمالي الخصومات', value: fmt(totalDeductions), color: 'var(--color-danger)', icon: <Minus size={18} /> },
        ].map((card, i) => (
          <div key={i} style={{
            display: 'flex', alignItems: 'center', gap: 'var(--space-3)',
            padding: 'var(--space-4)',
            background: `color-mix(in srgb, ${card.color} 7%, transparent)`,
            border: `1px solid color-mix(in srgb, ${card.color} 20%, transparent)`,
            borderRadius: 'var(--radius-lg)',
          }}>
            <div style={{
              width: 40, height: 40, borderRadius: 'var(--radius-md)',
              background: `color-mix(in srgb, ${card.color} 15%, transparent)`,
              color: card.color, display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              {card.icon}
            </div>
            <div>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{card.label}</div>
              <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: card.color, fontVariantNumeric: 'tabular-nums' }}>
                {card.value}
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* ── فلتر الحالة ── */}
      <div style={{ marginBottom: 'var(--space-3)', maxWidth: 200 }}>
        <Select
          label="الحالة"
          value={statusFilter}
          onChange={e => setStatusFilter(e.target.value)}
          options={[
            { value: '', label: 'الكل' },
            { value: 'pending', label: 'في الانتظار' },
            { value: 'approved', label: 'معتمد' },
            { value: 'rejected', label: 'مرفوض' },
          ]}
        />
      </div>

      {/* ── جدول التعديلات ── */}
      <DataTable
        data={adjustments}
        columns={columns}
        loading={isLoading}
        emptyIcon={<Award size={40} />}
        emptyTitle="لا توجد تعديلات"
        emptyText="أضف مكافأة أو خصم أو جزاء يدوي للموظفين"
      />

      {/* ── Modal إنشاء تعديل جديد ── */}
      <ResponsiveModal
        open={showCreate}
        onClose={() => { setShowCreate(false); resetForm() }}
        title="إضافة تعديل جديد"
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => { setShowCreate(false); resetForm() }} style={{ flex: 1 }}>
              إلغاء
            </Button>
            <Button
              icon={<Plus size={15} />}
              onClick={handleCreate}
              loading={createMut.isPending}
              disabled={!formEmployeeId || !formAmount || !formReason}
              style={{ flex: 2 }}
            >
              إضافة
            </Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          {/* نوع التعديل */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 'var(--space-2)' }}>
            {(['bonus', 'deduction', 'penalty'] as HRAdjustmentType[]).map(t => (
              <button
                key={t}
                onClick={() => setFormType(t)}
                style={{
                  padding: 'var(--space-3)',
                  borderRadius: 'var(--radius-md)',
                  border: `2px solid ${formType === t ? TYPE_COLOR[t] : 'var(--border-color)'}`,
                  background: formType === t
                    ? `color-mix(in srgb, ${TYPE_COLOR[t]} 10%, transparent)`
                    : 'transparent',
                  cursor: 'pointer',
                  display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
                  transition: 'all 0.15s ease',
                }}
              >
                <span style={{ color: TYPE_COLOR[t] }}>{TYPE_ICON[t]}</span>
                <span style={{ fontSize: 'var(--text-sm)', fontWeight: formType === t ? 700 : 400,
                  color: formType === t ? TYPE_COLOR[t] : 'var(--text-secondary)' }}>
                  {TYPE_LABEL[t]}
                </span>
              </button>
            ))}
          </div>

          {/* الموظف */}
          <Select
            label="الموظف *"
            value={formEmployeeId}
            onChange={e => setFormEmployeeId(e.target.value)}
            options={[{ value: '', label: 'اختر الموظف...' }, ...employeeOptions]}
          />

          {/* المبلغ + التاريخ */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
            <Input
              label="المبلغ (ج.م) *"
              type="number"
              min="0.01"
              step="0.01"
              value={formAmount}
              onChange={e => setFormAmount(e.target.value)}
              placeholder="0.00"
            />
            <Input
              label="التاريخ *"
              type="date"
              value={formDate}
              onChange={e => setFormDate(e.target.value)}
            />
          </div>

          {/* السبب */}
          <Input
            label="السبب / المبرر *"
            value={formReason}
            onChange={e => setFormReason(e.target.value)}
            placeholder={
              formType === 'bonus' ? 'مثال: مكافأة تحقيق هدف المبيعات' :
              formType === 'deduction' ? 'مثال: خصم إتلاف عهدة' :
              'مثال: مخالفة سلوكية — إنذار ثاني'
            }
          />

          {/* معاينة */}
          <div style={{
            padding: 'var(--space-3)',
            background: `color-mix(in srgb, ${TYPE_COLOR[formType]} 6%, transparent)`,
            borderRadius: 'var(--radius-md)',
            border: `1px solid color-mix(in srgb, ${TYPE_COLOR[formType]} 15%, transparent)`,
            fontSize: 'var(--text-sm)', color: 'var(--text-secondary)',
          }}>
            {formType === 'bonus' ? '✅' : '⚠️'} سيتم {formType === 'bonus' ? 'إضافة' : 'خصم'}{' '}
            <strong style={{ color: TYPE_COLOR[formType] }}>
              {formAmount ? fmt(parseFloat(formAmount)) : '0.00 ج.م'}
            </strong>{' '}
            {formType === 'bonus' ? 'إلى' : 'من'} راتب الموظف في الفترة المناسبة —{' '}
            <strong>تحتاج اعتماد</strong> قبل التطبيق.
          </div>
        </div>
      </ResponsiveModal>

      {/* ── Modal تأكيد الاعتماد/الرفض ── */}
      <ResponsiveModal
        open={!!confirmAction}
        onClose={() => setConfirmAction(null)}
        title={confirmAction?.action === 'approve' ? 'تأكيد الاعتماد' : 'تأكيد الرفض'}
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => setConfirmAction(null)} style={{ flex: 1 }}>
              إلغاء
            </Button>
            <Button
              variant={confirmAction?.action === 'approve' ? 'primary' : 'danger' as any}
              onClick={handleAction}
              loading={approveMut.isPending}
              style={{ flex: 2 }}
            >
              {confirmAction?.action === 'approve' ? '✅ اعتماد' : '❌ رفض'}
            </Button>
          </div>
        }
      >
        {confirmAction && (
          <div style={{ textAlign: 'center', padding: 'var(--space-4) 0' }}>
            <div style={{
              width: 56, height: 56, borderRadius: '50%', margin: '0 auto var(--space-3)',
              background: `color-mix(in srgb, ${TYPE_COLOR[confirmAction.adj.type]} 12%, transparent)`,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: TYPE_COLOR[confirmAction.adj.type],
            }}>
              {TYPE_ICON[confirmAction.adj.type]}
            </div>
            <div style={{ fontWeight: 700, fontSize: 'var(--text-lg)', marginBottom: 8 }}>
              {TYPE_LABEL[confirmAction.adj.type]} — {fmt(confirmAction.adj.amount)}
            </div>
            <div style={{ color: 'var(--text-secondary)', marginBottom: 4 }}>
              الموظف: <strong>{confirmAction.adj.employee?.full_name}</strong>
            </div>
            <div style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>
              السبب: {confirmAction.adj.reason}
            </div>
          </div>
        )}
      </ResponsiveModal>
    </div>
  )
}
