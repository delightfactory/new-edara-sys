import { useState } from 'react'
import {
  Calendar, CheckCircle, XCircle, Clock, Plus,
  ChevronDown, AlertCircle,
} from 'lucide-react'
import {
  useHRLeaveRequests,
  useUpdateLeaveRequestStatus,
  useCurrentEmployee,
} from '@/hooks/useQueryHooks'
import { cancelLeaveRequest } from '@/lib/services/hr'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useAuthStore } from '@/stores/auth-store'
import type { HRLeaveRequest, HRLeaveRequestStatus } from '@/lib/types/hr'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import PermissionGuard from '@/components/shared/PermissionGuard'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import LeaveRequestForm from './LeaveRequestForm'
import { toast } from 'sonner'

// ─── تحويل الحالات ──────────────────────────────────────
const STATUS_LABEL: Record<HRLeaveRequestStatus, string> = {
  draft:               'مسودة',
  pending_supervisor:  'بانتظار المشرف',
  approved_supervisor: 'موافقة المشرف',
  pending_hr:          'بانتظار الموارد البشرية',
  approved:            'مُعتمدة',
  rejected:            'مرفوضة',
  cancelled:           'ملغاة',
}

const STATUS_VARIANT: Record<HRLeaveRequestStatus, 'info' | 'success' | 'warning' | 'danger' | 'neutral'> = {
  draft:               'neutral',
  pending_supervisor:  'warning',
  approved_supervisor: 'info',
  pending_hr:          'warning',
  approved:            'success',
  rejected:            'danger',
  cancelled:           'neutral',
}

const fmtDate = (d?: string | null) =>
  d ? new Date(d).toLocaleDateString('ar-EG-u-nu-latn', { day: 'numeric', month: 'short', year: 'numeric' }) : '—'

// هل الطلب قابل للمعالجة (قبول/رفض)؟
function isPending(status: HRLeaveRequestStatus) {
  return status === 'pending_supervisor' || status === 'pending_hr'
}

// ═════════════════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════════════════

export default function LeavesPage() {
  const can = useAuthStore(s => s.can)

  // الموظف الحالي لفلترة طلباته (إذا لم يكن مديراً)
  const { data: currentEmployee } = useCurrentEmployee()
  const isManager = can('hr.leaves.approve')

  // فلاتر
  const [statusFilter, setStatusFilter] = useState<string>('')
  const [page,         setPage]         = useState(1)

  // الجلب: المدير يرى الكل، الموظف يرى طلباته فقط (RLS تُكمّل الحماية)
  const { data: result, isLoading } = useHRLeaveRequests({
    employeeId: isManager ? undefined : (currentEmployee?.id ?? undefined),
    status:     statusFilter || undefined,
    page,
    pageSize:   20,
  })

  const requests = result?.data ?? []

  // عدد الطلبات المعلقة (للمدير فقط) — badge على الفلتر
  const { data: pendingResult } = useHRLeaveRequests(
    isManager
      ? { status: 'pending_supervisor', page: 1, pageSize: 1 }
      : undefined as unknown as { page: number; pageSize: number }
  )
  const pendingCount = isManager ? (pendingResult?.count ?? 0) : 0

  // ── نموذج الطلب الجديد
  const [formOpen, setFormOpen] = useState(false)

  // ── مودال التفاصيل وقرار المدير
  const [selected, setSelected] = useState<HRLeaveRequest | null>(null)
  const [rejectReason, setRejectReason] = useState('')
  const [actionMode, setActionMode] = useState<'approve' | 'reject' | null>(null)

  const updateMutation = useUpdateLeaveRequestStatus()

  const handleApprove = async (req: HRLeaveRequest) => {
    const newStatus = req.status === 'pending_supervisor'
      ? 'approved_supervisor'
      : 'approved'
    try {
      await updateMutation.mutateAsync({ id: req.id, status: newStatus })
      toast.success('تمت الموافقة على طلب الإجازة')
      setSelected(null)
    } catch (err) {
      toast.error(`فشل التحديث: ${err instanceof Error ? err.message : String(err)}`)
    }
  }

  const handleReject = async (req: HRLeaveRequest) => {
    if (!rejectReason.trim()) {
      toast.error('يرجى كتابة سبب الرفض')
      return
    }
    try {
      await updateMutation.mutateAsync({
        id:              req.id,
        status:          'rejected',
        rejectionReason: rejectReason.trim(),
      })
      toast.success('تم رفض الطلب')
      setSelected(null)
      setRejectReason('')
    } catch (err) {
      toast.error(`فشل التحديث: ${err instanceof Error ? err.message : String(err)}`)
    }
  }

  // إلغاء طلب الإجازة من قِبَل الموظف نفسه (draft / pending_supervisor فقط)
  const qc = useQueryClient()
  const cancelMutation = useMutation({
    mutationFn: (id: string) => cancelLeaveRequest(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['hr-leave-requests'] })
      toast.success('تم إلغاء طلب الإجازة')
    },
    onError: (err: Error) => toast.error(err.message),
  })

  // ─── أعمدة الجدول ────────────────────────────────────
  const columns = [
    ...(isManager ? [{
      key: 'employee',
      label: 'الموظف',
      render: (r: HRLeaveRequest) => (
        <span style={{ fontWeight: 600 }}>
          {r.employee?.full_name ?? '—'}
        </span>
      ),
    }] : []),
    {
      key: 'leave_type',
      label: 'نوع الإجازة',
      render: (r: HRLeaveRequest) => r.leave_type?.name ?? '—',
    },
    {
      key: 'start_date',
      label: 'من',
      render: (r: HRLeaveRequest) => fmtDate(r.start_date),
      hideOnMobile: true,
    },
    {
      key: 'end_date',
      label: 'إلى',
      render: (r: HRLeaveRequest) => fmtDate(r.end_date),
      hideOnMobile: true,
    },
    {
      key: 'days_count',
      label: 'الأيام',
      align: 'center' as const,
      width: 72,
      render: (r: HRLeaveRequest) => (
        <span style={{ fontVariantNumeric: 'tabular-nums', fontWeight: 600 }}>
          {r.days_count}
        </span>
      ),
    },
    {
      key: 'status',
      label: 'الحالة',
      render: (r: HRLeaveRequest) => (
        <Badge variant={STATUS_VARIANT[r.status]}>
          {STATUS_LABEL[r.status]}
        </Badge>
      ),
    },
    ...(isManager ? [{
      key: 'actions',
      label: 'إجراءات',
      align: 'end' as const,
      width: 120,
      render: (r: HRLeaveRequest) => (
        isPending(r.status) ? (
          <div style={{ display: 'flex', gap: 'var(--space-1)', justifyContent: 'flex-end' }}>
            <Button
              id={`approve-leave-${r.id}`}
              size="sm"
              variant="secondary"
              icon={<CheckCircle size={13} />}
              onClick={e => { e.stopPropagation(); setSelected(r); setActionMode('approve') }}
              style={{ color: 'var(--color-success)' }}
            >
              قبول
            </Button>
            <Button
              id={`reject-leave-${r.id}`}
              size="sm"
              variant="ghost"
              icon={<XCircle size={13} />}
              onClick={e => { e.stopPropagation(); setSelected(r); setActionMode('reject'); setRejectReason('') }}
              style={{ color: 'var(--color-danger)' }}
            >
              رفض
            </Button>
          </div>
        ) : null
      ),
    }] : [{
      // الموظف: زر إلغاء طلبه (draft / pending_supervisor فقط)
      key: 'actions',
      label: '',
      align: 'end' as const,
      width: 80,
      render: (r: HRLeaveRequest) => {
        const canCancel = (r.status === 'draft' || r.status === 'pending_supervisor')
          && r.employee_id === currentEmployee?.id
        return canCancel ? (
          <Button
            id={`cancel-leave-${r.id}`}
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
              لن تتمكن من تقديم طلبات الإجازات أو الأذونات أو السلف. يرجى التواصل مع مدير الموارد البشرية لربط حسابك.
            </div>
          </div>
        </div>
      )}

      <PageHeader
        title="إدارة الإجازات"
        subtitle={isManager ? 'جميع طلبات الإجازة' : 'طلبات إجازاتي'}
        breadcrumbs={[
          { label: 'الموارد البشرية' },
          { label: 'الإجازات' },
        ]}
        actions={
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>

            {/* فلتر الحالة مع بادج العدد المعلق */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
                <select
                  id="leave-status-filter"
                  className="form-input"
                  value={statusFilter}
                  onChange={e => { setStatusFilter(e.target.value); setPage(1) }}
                  style={{ paddingLeft: 'var(--space-6)', width: 'auto', minWidth: 160 }}
                >
                  <option value="">كل الحالات {result?.count ? `(${result.count})` : ''}</option>
                  {Object.entries(STATUS_LABEL).map(([k, v]) => (
                    <option key={k} value={k}>{v}</option>
                  ))}
                </select>
                <ChevronDown
                  size={13}
                  style={{
                    position: 'absolute', left: 'var(--space-2)',
                    pointerEvents: 'none', color: 'var(--text-muted)',
                  }}
                />
              </div>
              {isManager && pendingCount > 0 && (
                <span style={{
                  background: 'var(--color-warning)',
                  color: '#fff',
                  borderRadius: 'var(--radius-full)',
                  fontSize: 'var(--text-xs)',
                  fontWeight: 700,
                  padding: '2px 8px',
                  whiteSpace: 'nowrap',
                }}>
                  {pendingCount} معلق
                </span>
              )}
            </div>

            {/* زر طلب إجازة جديدة — SEC-01: محمي بـ hr.leaves.request */}
            <PermissionGuard permission="hr.leaves.request">
              <Button
                id="btn-new-leave-request"
                icon={<Plus size={14} />}
                onClick={() => setFormOpen(true)}
              >
                طلب إجازة
              </Button>
            </PermissionGuard>
          </div>
        }
      />

      {/* ── الجدول ── */}
      <div className="edara-card" style={{ padding: 0, overflow: 'hidden' }}>
        <DataTable
          columns={columns}
          data={requests}
          loading={isLoading}
          keyField="id"
          onRowClick={r => { setSelected(r); setActionMode(null) }}
          emptyIcon={<Calendar size={40} />}
          emptyTitle="لا توجد طلبات إجازة"
          emptyText={isManager ? 'لم يُقدَّم أي طلب بعد' : 'لم تقدم أي طلب إجازة بعد'}
          emptyAction={
            <Button
              size="sm"
              icon={<Plus size={13} />}
              onClick={() => setFormOpen(true)}
            >
              طلب إجازة جديدة
            </Button>
          }
          page={page}
          totalPages={result?.totalPages}
          totalCount={result?.count}
          onPageChange={setPage}
          rowClassName={r => isPending(r.status) && isManager ? 'tr-pending' : undefined}
        />
      </div>

      {/* ══ نموذج طلب إجازة جديد ══ */}
      <LeaveRequestForm
        open={formOpen}
        onClose={() => setFormOpen(false)}
      />

      {/* ══ مودال التفاصيل / قرار المدير ══ */}
      {selected && (
        <ResponsiveModal
          open={!!selected}
          onClose={() => { setSelected(null); setActionMode(null); setRejectReason('') }}
          title={`طلب إجازة — ${selected.employee?.full_name ?? 'الموظف'}`}
          size="sm"
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
                <PermissionGuard permission="hr.leaves.approve">
                  <Button
                    id="modal-reject-btn"
                    variant="ghost"
                    icon={<XCircle size={14} />}
                    onClick={() => setActionMode('reject')}
                    style={{ flex: 1, color: 'var(--color-danger)' }}
                    disabled={updateMutation.isPending}
                  >
                    رفض
                  </Button>
                  <Button
                    id="modal-approve-btn"
                    icon={<CheckCircle size={14} />}
                    onClick={() => handleApprove(selected)}
                    style={{ flex: 1 }}
                    loading={updateMutation.isPending && actionMode === 'approve'}
                  >
                    موافقة
                  </Button>
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
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>

            {/* ملخص الطلب */}
            <DetailRow label="نوع الإجازة"    value={selected.leave_type?.name ?? '—'} />
            <DetailRow label="من تاريخ"       value={fmtDate(selected.start_date)} />
            <DetailRow label="إلى تاريخ"      value={fmtDate(selected.end_date)} />
            <DetailRow label="عدد الأيام"     value={`${selected.days_count} يوم`} highlight />
            <DetailRow label="الحالة"
              value={
                <Badge variant={STATUS_VARIANT[selected.status]}>
                  {STATUS_LABEL[selected.status]}
                </Badge>
              }
            />
            {selected.reason && (
              <div style={{
                padding: 'var(--space-3)',
                background: 'var(--bg-surface-2)',
                borderRadius: 'var(--radius-md)',
                fontSize: 'var(--text-sm)',
                color: 'var(--text-secondary)',
                lineHeight: 1.7,
              }}>
                <div style={{ fontWeight: 600, color: 'var(--text-muted)', fontSize: 'var(--text-xs)', marginBottom: 4 }}>
                  السبب
                </div>
                {selected.reason}
              </div>
            )}

            {/* ملاحظات الرفض السابقة */}
            {selected.rejection_reason && (
              <div style={{
                display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-start',
                padding: 'var(--space-3)',
                background: 'color-mix(in srgb, var(--color-danger) 6%, transparent)',
                border: '1px solid color-mix(in srgb, var(--color-danger) 20%, transparent)',
                borderRadius: 'var(--radius-md)',
              }}>
                <AlertCircle size={14} style={{ color: 'var(--color-danger)', flexShrink: 0, marginTop: 2 }} />
                <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>
                  <strong style={{ color: 'var(--color-danger)' }}>سبب الرفض: </strong>
                  {selected.rejection_reason}
                </div>
              </div>
            )}

            {/* حقل سبب الرفض (يظهر عند الرفض) */}
            {actionMode === 'reject' && isPending(selected.status) && (
              <div className="form-group" style={{ marginTop: 'var(--space-2)' }}>
                <label className="form-label" htmlFor="reject-reason-input">
                  سبب الرفض <span style={{ color: 'var(--color-danger)' }}>*</span>
                </label>
                <textarea
                  id="reject-reason-input"
                  className="form-input"
                  rows={3}
                  placeholder="اكتب سبب رفض الطلب..."
                  value={rejectReason}
                  onChange={e => setRejectReason(e.target.value)}
                  disabled={updateMutation.isPending}
                  style={{ resize: 'vertical', minHeight: 80 }}
                  autoFocus
                />
                <Button
                  variant="secondary"
                  onClick={() => handleReject(selected)}
                  loading={updateMutation.isPending && actionMode === 'reject'}
                  disabled={!rejectReason.trim()}
                  style={{ marginTop: 'var(--space-2)', width: '100%', color: 'var(--color-danger)' }}
                >
                  تأكيد الرفض
                </Button>
              </div>
            )}
          </div>
        </ResponsiveModal>
      )}

      {/* ── Pending row highlight ── */}
      <style>{`
        .tr-pending { background: color-mix(in srgb, var(--color-warning) 4%, transparent); }
        .tr-pending:hover { background: color-mix(in srgb, var(--color-warning) 8%, transparent) !important; }
      `}</style>
    </div>
  )
}

// ─── مساعد عرض حقل التفاصيل ──────────────────────────
function DetailRow({ label, value, highlight }: {
  label: string
  value: React.ReactNode
  highlight?: boolean
}) {
  return (
    <div style={{
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      padding: 'var(--space-2) 0',
      borderBottom: '1px solid var(--border-primary)',
    }}>
      <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 4 }}>
        <Clock size={12} />
        {label}
      </span>
      <span style={{
        fontSize: 'var(--text-sm)',
        fontWeight: highlight ? 700 : 500,
        color: highlight ? 'var(--color-primary)' : 'var(--text-primary)',
      }}>
        {value}
      </span>
    </div>
  )
}
