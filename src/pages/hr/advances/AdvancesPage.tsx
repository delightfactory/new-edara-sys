import { useState } from 'react'
import {
  Wallet, CheckCircle, XCircle, Plus, ChevronDown,
  AlertCircle, Building2, CreditCard, DollarSign
} from 'lucide-react'
import {
  useHRAdvances,
  useDisburseAdvance, useUpdateAdvanceStatus,
  useVaults,
  useCurrentEmployee,
} from '@/hooks/useQueryHooks'
import { cancelAdvance } from '@/lib/services/hr'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useAuthStore } from '@/stores/auth-store'
import type { HRAdvance, HRAdvanceStatus } from '@/lib/types/hr'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import PermissionGuard from '@/components/shared/PermissionGuard'
import AdvanceRequestForm from './AdvanceRequestForm'
import { toast } from 'sonner'
import StatCard from '@/components/shared/StatCard'
import DetailRow from '@/components/shared/DetailRow'

// ─── حالات السلفة ─────────────────────────────────────
const STATUS_LABEL: Record<HRAdvanceStatus, string> = {
  pending_supervisor: 'بانتظار المشرف',
  pending_hr:         'بانتظار الموارد البشرية',
  pending_finance:    'بانتظار المالية',
  approved:           'مُعتمدة (سارية)',
  rejected:           'مرفوضة',
  paid:               'مصروفة',
  fully_repaid:       'مسددة بالكامل',
  cancelled:          'ملغاة',
}

const STATUS_VARIANT: Record<HRAdvanceStatus, 'success' | 'warning' | 'danger' | 'info' | 'neutral'> = {
  pending_supervisor: 'warning',
  pending_hr:         'warning',
  pending_finance:    'info',
  approved:           'success',
  rejected:           'danger',
  paid:               'success',
  fully_repaid:       'neutral',
  cancelled:          'neutral',
}

const TYPE_LABEL: Record<string, string> = {
  instant:   'فورية',
  scheduled: 'مجدولة',
}

const INSTALLMENT_STATUS_LABEL: Record<string, string> = {
  pending:  'قادم',
  deducted: 'مُخصوم',
  deferred: 'مؤجل',
  skipped:  'متخطى',
}

const INSTALLMENT_BADGE: Record<string, 'success' | 'warning' | 'neutral' | 'info'> = {
  pending:  'info',
  deducted: 'success',
  deferred: 'warning',
  skipped:  'neutral',
}

const fmtCurrency = (n: number) =>
  n.toLocaleString('ar-EG-u-nu-latn', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' ج.م'

const fmtDate = (d?: string | null) =>
  d ? new Date(d).toLocaleDateString('ar-EG-u-nu-latn', { day: 'numeric', month: 'short', year: 'numeric' }) : '—'

// هل السلفة تحتاج إجراءً؟
const isPending = (status: HRAdvanceStatus) =>
  ['pending_supervisor', 'pending_hr', 'pending_finance'].includes(status)

// ═════════════════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════════════════

export default function AdvancesPage() {
  const can = useAuthStore(s => s.can)

  const { data: currentEmployee } = useCurrentEmployee()
  const isManager  = can('hr.advances.approve') || can('finance.payments.create')
  const isFinance  = can('finance.payments.create')

  // فلاتر
  const [statusFilter, setStatusFilter] = useState<string>('')
  const [page,         setPage]         = useState(1)

  const { data: result, isLoading } = useHRAdvances({
    employeeId: isManager ? undefined : (currentEmployee?.id ?? undefined),
    status:     (statusFilter as HRAdvanceStatus) || undefined,
    page,
    pageSize:   20,
  })
  const advances = result?.data ?? []

  // ── نموذج الطلب الجديد
  const [formOpen, setFormOpen] = useState(false)

  // ── مودال التفاصيل
  const [selected,     setSelected]     = useState<HRAdvance | null>(null)
  const [actionMode,   setActionMode]   = useState<'approve' | 'reject' | 'disburse' | null>(null)
  const [rejectReason, setRejectReason] = useState('')
  const [notes,        setNotes]        = useState('')

  // ── مودال اختيار الخزنة (نقطة التقاطع المالي)
  const [vaultId, setVaultId] = useState<string>('')
  const { data: vaults = [] } = useVaults({ isActive: true })

  // Mutations
  const disburseMutation = useDisburseAdvance()
  const statusMutation   = useUpdateAdvanceStatus()

  // ── موافقة المشرف / HR
  const handleApproveStep = async (adv: HRAdvance) => {
    const nextStatus: HRAdvanceStatus =
      adv.status === 'pending_supervisor' ? 'pending_hr' :
      adv.status === 'pending_hr'         ? 'pending_finance' : 'approved'

    try {
      await statusMutation.mutateAsync({ id: adv.id, status: nextStatus, notes: notes || null })
      toast.success('تمت الموافقة — تم تحويل الطلب للمرحلة التالية')
      setSelected(null); setActionMode(null); setNotes('')
    } catch (err) {
      toast.error(`فشل التحديث: ${err instanceof Error ? err.message : String(err)}`)
    }
  }

  // ── رفض
  const handleReject = async (adv: HRAdvance) => {
    if (!rejectReason.trim()) { toast.error('يرجى كتابة سبب الرفض'); return }
    try {
      await statusMutation.mutateAsync({
        id: adv.id, status: 'rejected',
        rejectionReason: rejectReason.trim(),
      })
      toast.success('تم رفض طلب السلفة')
      setSelected(null); setActionMode(null); setRejectReason('')
    } catch (err) {
      toast.error(`فشل الرفض: ${err instanceof Error ? err.message : String(err)}`)
    }
  }

  // ── صرف السلفة (Finance Crossing)
  const handleDisburse = async (adv: HRAdvance) => {
    if (!vaultId) { toast.error('يرجى اختيار الخزنة'); return }
    try {
      await disburseMutation.mutateAsync({ id: adv.id, vaultId, notes: notes || null })
      toast.success('✅ تم صرف السلفة وتوليد جدول الأقساط تلقائياً')
      setSelected(null); setActionMode(null); setVaultId(''); setNotes('')
    } catch (err) {
      toast.error(`فشل الصرف: ${err instanceof Error ? err.message : String(err)}`)
    }
  }

  // ── إلغاء السلفة من قِبَل الموظف (pending_supervisor / pending_hr فقط)
  const qc = useQueryClient()
  const cancelMutation = useMutation({
    mutationFn: (id: string) => cancelAdvance(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['hr-advances'] })
      toast.success('تم إلغاء طلب السلفة')
    },
    onError: (err: Error) => toast.error(err.message),
  })

  // ─── أعمدة الجدول
  const columns = [
    ...(isManager ? [{
      key: 'employee',
      label: 'الموظف',
      render: (r: HRAdvance) => (
        <span style={{ fontWeight: 600 }}>{r.employee?.full_name ?? '—'}</span>
      ),
    }] : []),
    {
      key: 'number',
      label: 'رقم السلفة',
      render: (r: HRAdvance) => (
        <span style={{ fontFamily: 'monospace', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
          {r.number ?? '—'}
        </span>
      ),
    },
    {
      key: 'advance_type',
      label: 'النوع',
      render: (r: HRAdvance) => TYPE_LABEL[r.advance_type] ?? r.advance_type,
      hideOnMobile: true,
    },
    {
      key: 'amount',
      label: 'المبلغ',
      align: 'end' as const,
      render: (r: HRAdvance) => (
        <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
          {fmtCurrency(r.amount)}
        </span>
      ),
    },
    {
      key: 'remaining_amount',
      label: 'المتبقي',
      align: 'end' as const,
      hideOnMobile: true,
      render: (r: HRAdvance) => (
        <span style={{
          fontVariantNumeric: 'tabular-nums',
          color: r.remaining_amount > 0 ? 'var(--color-warning)' : 'var(--color-success)',
        }}>
          {fmtCurrency(r.remaining_amount)}
        </span>
      ),
    },
    {
      key: 'status',
      label: 'الحالة',
      render: (r: HRAdvance) => (
        <Badge variant={STATUS_VARIANT[r.status]}>
          {STATUS_LABEL[r.status]}
        </Badge>
      ),
    },
    ...(isManager ? [{
      key: 'actions',
      label: 'إجراءات',
      align: 'end' as const,
      width: 140,
      render: (r: HRAdvance) => {
        if (!isPending(r.status)) return null
        const isFinanceStep = r.status === 'pending_finance'
        return (
          <div style={{ display: 'flex', gap: 'var(--space-1)', justifyContent: 'flex-end' }}>
            <Button
              id={`approve-adv-${r.id}`}
              size="sm"
              variant="secondary"
              icon={isFinanceStep ? <CreditCard size={13} /> : <CheckCircle size={13} />}
              onClick={e => {
                e.stopPropagation()
                setSelected(r)
                setActionMode(isFinanceStep ? 'disburse' : 'approve')
                setVaultId(''); setNotes('')
              }}
              style={{ color: isFinanceStep ? 'var(--color-primary)' : 'var(--color-success)' }}
            >
              {isFinanceStep ? 'صرف' : 'موافقة'}
            </Button>
            <Button
              id={`reject-adv-${r.id}`}
              size="sm"
              variant="ghost"
              icon={<XCircle size={13} />}
              onClick={e => {
                e.stopPropagation()
                setSelected(r)
                setActionMode('reject')
                setRejectReason('')
              }}
              style={{ color: 'var(--color-danger)' }}
            >
              رفض
            </Button>
          </div>
        )
      },
    }] : [{
      // الموظف: إلغاء طلبه فقط إذا لم يُصرف بعد
      key: 'actions',
      label: '',
      align: 'end' as const,
      width: 80,
      render: (r: HRAdvance) => {
        const canCancel = (r.status === 'pending_supervisor' || r.status === 'pending_hr')
          && r.employee_id === currentEmployee?.id
        return canCancel ? (
          <Button
            id={`cancel-adv-${r.id}`}
            size="sm"
            variant="ghost"
            icon={<XCircle size={13} />}
            onClick={e => { e.stopPropagation(); cancelMutation.mutate(r.id) }}
            loading={cancelMutation.isPending}
            style={{ color: 'var(--color-danger)' }}
          >
            إلغاء
          </Button>
        ) : null
      },
    }]),
  ]


  return (
    <div className="page-container animate-enter">

      {/* ★ تنبيه: لا يوجد سجل موظف مربوط */}
      {!isManager && !currentEmployee && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 'var(--space-3)',
          padding: 'var(--space-4)',
          background: 'color-mix(in srgb, var(--color-danger) 8%, transparent)',
          border: '1px solid color-mix(in srgb, var(--color-danger) 25%, transparent)',
          borderRadius: 'var(--radius-md)',
          marginBottom: 'var(--space-4)',
        }}>
          <AlertCircle size={18} style={{ color: 'var(--color-danger)', flexShrink: 0 }} />
          <div>
            <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)', color: 'var(--color-danger)' }}>
              حسابك غير مربوط بسجل موظف
            </div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
              لن تتمكن من تقديم طلبات السلف. يرجى التواصل مع مدير الموارد البشرية لربط حسابك.
            </div>
          </div>
        </div>
      )}

      <PageHeader
        title="السلف والأقساط"
        subtitle={isManager ? 'إدارة طلبات السلف' : 'سلفي وأقساطي'}
        breadcrumbs={[
          { label: 'الموارد البشرية' },
          { label: 'السلف' },
        ]}
        actions={
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
            {/* فلتر الحالة */}
            <div style={{ position: 'relative' }}>
              <select
                id="advance-status-filter"
                className="form-input"
                value={statusFilter}
                onChange={e => { setStatusFilter(e.target.value); setPage(1) }}
                style={{ paddingInlineStart: 'var(--space-6)', width: 'auto', minWidth: 170 }}
              >
                <option value="">كل الحالات</option>
                {Object.entries(STATUS_LABEL).map(([k, v]) => (
                  <option key={k} value={k}>{v}</option>
                ))}
              </select>
              <ChevronDown size={13} style={{
                position: 'absolute', insetInlineStart: 'var(--space-2)', top: '50%',
                transform: 'translateY(-50%)', pointerEvents: 'none', color: 'var(--text-muted)',
              }} />
            </div>

            <Button
              id="btn-new-advance"
              icon={<Plus size={14} />}
              onClick={() => setFormOpen(true)}
            >
              طلب سلفة
            </Button>
          </div>
        }
      />

      {/* ── الجدول ── */}
      <div className="edara-card" style={{ padding: 0, overflow: 'hidden' }}>
        <DataTable
          columns={columns}
          data={advances}
          loading={isLoading}
          keyField="id"
          onRowClick={r => { setSelected(r); setActionMode(null) }}
          emptyIcon={<Wallet size={40} />}
          emptyTitle="لا توجد سلف"
          emptyText={isManager ? 'لم يُقدَّم أي طلب سلفة بعد' : 'لم تقدم أي طلب سلفة بعد'}
          emptyAction={
            <Button size="sm" icon={<Plus size={13} />} onClick={() => setFormOpen(true)}>
              طلب سلفة جديدة
            </Button>
          }
          page={page}
          totalPages={result?.totalPages}
          totalCount={result?.count}
          onPageChange={setPage}
          rowClassName={r => isPending(r.status) && isManager ? 'tr-pending' : undefined}
        />
      </div>

      {/* ══ نموذج طلب سلفة ══ */}
      <AdvanceRequestForm open={formOpen} onClose={() => setFormOpen(false)} />

      {/* ══ مودال التفاصيل ══ */}
      {selected && (
        <ResponsiveModal
          open={!!selected}
          onClose={() => { setSelected(null); setActionMode(null); setRejectReason(''); setNotes(''); setVaultId('') }}
          title={`سلفة — ${selected.employee?.full_name ?? ''}`}
          size="md"
          footer={
            isManager && isPending(selected.status) ? (
              <div style={{ display: 'flex', gap: 'var(--space-2)', width: '100%' }}>
                <Button
                  variant="secondary"
                  onClick={() => { setSelected(null); setActionMode(null) }}
                  style={{ flex: 1 }}
                >
                  إغلاق
                </Button>
                <PermissionGuard permission={['hr.advances.approve', 'finance.payments.create']}>
                  <Button
                    variant="ghost"
                    icon={<XCircle size={14} />}
                    onClick={() => setActionMode('reject')}
                    style={{ flex: 1, color: 'var(--color-danger)' }}
                    disabled={statusMutation.isPending || disburseMutation.isPending}
                  >
                    رفض
                  </Button>
                  {selected.status === 'pending_finance' ? (
                    <Button
                      id="modal-disburse-btn"
                      icon={<CreditCard size={14} />}
                      onClick={() => setActionMode('disburse')}
                      style={{ flex: 1 }}
                      disabled={disburseMutation.isPending}
                    >
                      صرف السلفة
                    </Button>
                  ) : (
                    <Button
                      id="modal-approve-btn"
                      icon={<CheckCircle size={14} />}
                      onClick={() => handleApproveStep(selected)}
                      style={{ flex: 1 }}
                      loading={statusMutation.isPending && actionMode === 'approve'}
                    >
                      موافقة
                    </Button>
                  )}
                </PermissionGuard>
              </div>
            ) : (
              <Button
                variant="secondary"
                onClick={() => { setSelected(null); setActionMode(null) }}
                style={{ width: '100%' }}
              >
                إغلاق
              </Button>
            )
          }
        >
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>

            {/* ملخص السلفة */}
            <div style={{
              display: 'grid', gridTemplateColumns: '1fr 1fr',
              gap: 'var(--space-3)',
            }}>
              <StatCard label="المبلغ الكلي"  value={fmtCurrency(selected.amount)}           color="var(--color-primary)" icon={<DollarSign size={18} />} />
              <StatCard label="المتبقي"        value={fmtCurrency(selected.remaining_amount)}  color={selected.remaining_amount > 0 ? 'var(--color-warning)' : 'var(--color-success)'} icon={<CreditCard size={18} />} />
            </div>

            {/* تفاصيل */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              <DetailRow label="رقم السلفة"   value={selected.number ?? '—'} />
              <DetailRow label="النوع"          value={TYPE_LABEL[selected.advance_type] ?? selected.advance_type} />
              <DetailRow label="عدد الأقساط"   value={`${selected.installments_count} قسط`} />
              {selected.monthly_installment && (
                <DetailRow label="القسط الشهري" value={fmtCurrency(selected.monthly_installment)} highlight />
              )}
              <DetailRow label="الحالة"
                value={<Badge variant={STATUS_VARIANT[selected.status]}>{STATUS_LABEL[selected.status]}</Badge>}
              />
              <DetailRow label="تاريخ الطلب"  value={fmtDate(selected.created_at)} />
              {selected.vault_id && (
                <DetailRow label="خزنة الصرف" value={
                  <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                    <Building2 size={12} /> مُصرَّفة
                  </span>
                } />
              )}
            </div>

            {/* سبب الطلب */}
            {selected.reason && (
              <div style={{
                padding: 'var(--space-3)', background: 'var(--bg-surface-2)',
                borderRadius: 'var(--radius-md)', fontSize: 'var(--text-sm)',
                color: 'var(--text-secondary)', lineHeight: 1.7,
              }}>
                <div style={{ fontWeight: 600, fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 4 }}>السبب</div>
                {selected.reason}
              </div>
            )}

            {/* جدول الأقساط — للسلفة المجدولة فقط */}
            {selected.advance_type === 'scheduled' && selected.installments && selected.installments.length > 0 && (
              <div>
                <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--text-primary)', marginBottom: 'var(--space-2)' }}>
                  جدول الأقساط
                </div>
                <div style={{ border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-md)', overflow: 'hidden' }}>
                  <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--text-xs)' }}>
                    <thead style={{ background: 'var(--bg-surface-2)' }}>
                      <tr>
                        {['#', 'الشهر / السنة', 'المبلغ', 'الحالة'].map(h => (
                          <th key={h} style={{ padding: '6px 10px', textAlign: 'right', color: 'var(--text-muted)', fontWeight: 600 }}>{h}</th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {selected.installments.map(inst => (
                        <tr key={inst.id} style={{ borderTop: '1px solid var(--border-primary)' }}>
                          <td style={{ padding: '6px 10px', color: 'var(--text-muted)' }}>{inst.installment_number}</td>
                          <td style={{ padding: '6px 10px', fontVariantNumeric: 'tabular-nums' }}>
                            {inst.due_month}/{inst.due_year}
                          </td>
                          <td style={{ padding: '6px 10px', fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
                            {fmtCurrency(inst.amount)}
                          </td>
                          <td style={{ padding: '6px 10px' }}>
                            <Badge variant={INSTALLMENT_BADGE[inst.status] ?? 'neutral'}>
                              {INSTALLMENT_STATUS_LABEL[inst.status] ?? inst.status}
                            </Badge>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}

            {/* ── نقطة التقاطع المالي: اختيار الخزنة ── */}
            {actionMode === 'disburse' && selected.status === 'pending_finance' && (
              <div style={{
                padding: 'var(--space-4)',
                background: 'color-mix(in srgb, var(--color-primary) 5%, transparent)',
                border: '1px solid color-mix(in srgb, var(--color-primary) 20%, transparent)',
                borderRadius: 'var(--radius-md)',
                display: 'flex', flexDirection: 'column', gap: 'var(--space-3)',
              }}>
                <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--color-primary)', display: 'flex', alignItems: 'center', gap: 6 }}>
                  <CreditCard size={14} /> صرف السلفة — اختر الخزنة
                </div>

                <div className="form-group" style={{ margin: 0 }}>
                  <label className="form-label" htmlFor="vault-select">
                    الخزنة <span style={{ color: 'var(--color-danger)' }}>*</span>
                  </label>
                  <div style={{ position: 'relative' }}>
                    <select
                      id="vault-select"
                      className="form-input"
                      value={vaultId}
                      onChange={e => setVaultId(e.target.value)}
                      disabled={disburseMutation.isPending}
                      style={{ paddingInlineStart: 'var(--space-6)' }}
                    >
                      <option value="">اختر الخزنة...</option>
                      {vaults.map(v => (
                        <option key={v.id} value={v.id}>
                          {v.name}
                          {v.current_balance != null
                            ? ` — رصيد: ${fmtCurrency(v.current_balance)}`
                            : ''}
                        </option>
                      ))}
                    </select>
                    <ChevronDown size={13} style={{
                      position: 'absolute', insetInlineStart: 'var(--space-2)', top: '50%',
                      transform: 'translateY(-50%)', pointerEvents: 'none', color: 'var(--text-muted)',
                    }} />
                  </div>
                </div>

                <div className="form-group" style={{ margin: 0 }}>
                  <label className="form-label" htmlFor="disburse-notes">ملاحظات (اختياري)</label>
                  <input
                    id="disburse-notes"
                    type="text"
                    className="form-input"
                    placeholder="أي ملاحظات للسجل..."
                    value={notes}
                    onChange={e => setNotes(e.target.value)}
                    disabled={disburseMutation.isPending}
                  />
                </div>

                <div style={{ display: 'flex', gap: 'var(--space-2)' }}>
                  <Button
                    variant="secondary"
                    onClick={() => { setActionMode(null); setVaultId(''); setNotes('') }}
                    style={{ flex: 1 }}
                    disabled={disburseMutation.isPending}
                  >
                    إلغاء
                  </Button>
                  <Button
                    id="confirm-disburse-btn"
                    icon={<CreditCard size={14} />}
                    onClick={() => handleDisburse(selected)}
                    loading={disburseMutation.isPending}
                    disabled={!vaultId}
                    style={{ flex: 1 }}
                  >
                    تأكيد الصرف
                  </Button>
                </div>

                <div style={{
                  display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-start',
                  fontSize: 'var(--text-xs)', color: 'var(--color-warning)',
                }}>
                  <AlertCircle size={11} style={{ flexShrink: 0, marginTop: 1 }} />
                  سيتم خصم المبلغ من الخزنة المختارة وتوليد جدول الأقساط تلقائياً.
                </div>
              </div>
            )}

            {/* حقل سبب الرفض */}
            {actionMode === 'reject' && isPending(selected.status) && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
                <label className="form-label" htmlFor="adv-reject-reason">
                  سبب الرفض <span style={{ color: 'var(--color-danger)' }}>*</span>
                </label>
                <textarea
                  id="adv-reject-reason"
                  className="form-input"
                  rows={3}
                  placeholder="اكتب سبب رفض طلب السلفة..."
                  value={rejectReason}
                  onChange={e => setRejectReason(e.target.value)}
                  disabled={statusMutation.isPending}
                  style={{ resize: 'vertical' }}
                  autoFocus
                />
                <Button
                  variant="secondary"
                  onClick={() => handleReject(selected)}
                  loading={statusMutation.isPending}
                  disabled={!rejectReason.trim()}
                  style={{ color: 'var(--color-danger)' }}
                >
                  تأكيد الرفض
                </Button>
              </div>
            )}

            {/* سبب الرفض السابق */}
            {selected.rejection_reason && (
              <div style={{
                display: 'flex', gap: 'var(--space-2)',
                padding: 'var(--space-3)',
                background: 'color-mix(in srgb, var(--color-danger) 6%, transparent)',
                border: '1px solid color-mix(in srgb, var(--color-danger) 20%, transparent)',
                borderRadius: 'var(--radius-md)',
                fontSize: 'var(--text-xs)', color: 'var(--text-secondary)',
              }}>
                <AlertCircle size={13} style={{ color: 'var(--color-danger)', flexShrink: 0, marginTop: 2 }} />
                <div><strong style={{ color: 'var(--color-danger)' }}>سبب الرفض: </strong>{selected.rejection_reason}</div>
              </div>
            )}
          </div>
        </ResponsiveModal>
      )}

      <style>{`
        .tr-pending { background: color-mix(in srgb, var(--color-warning) 4%, transparent); }
        .tr-pending:hover { background: color-mix(in srgb, var(--color-warning) 8%, transparent) !important; }
      `}</style>
    </div>
  )
}

// ─── مكونات مساعدة ───────────────────────────────────
      {/* removed helper components */}
