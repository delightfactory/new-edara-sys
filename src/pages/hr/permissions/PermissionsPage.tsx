import { useState } from 'react'
import { Clock, Plus, CheckCircle, XCircle, AlertCircle } from 'lucide-react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { getPermissionRequests, createPermissionRequest, approvePermissionRequest, rejectPermissionRequest } from '@/lib/services/hr'
import type { HRPermissionRequestInput } from '@/lib/types/hr'
import { useCurrentEmployee, useCompletePermissionReturn } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import DataCard from '@/components/ui/DataCard'
import Input from '@/components/ui/Input'
import Button from '@/components/ui/Button'
import Badge from '@/components/ui/Badge'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import PermissionGuard from '@/components/shared/PermissionGuard'

const STATUS_LABEL = { pending: 'قيد المراجعة', approved: 'مُعتمد', rejected: 'مرفوض' }
const STATUS_VARIANT: Record<string, 'warning' | 'success' | 'danger'> = {
  pending: 'warning', approved: 'success', rejected: 'danger',
}

const fmtDate = (d: string) =>
  new Date(d).toLocaleDateString('ar-EG', { weekday: 'short', day: 'numeric', month: 'short' })
const fmtTime = (t: string) => {
  const [h, m] = t.split(':')
  const hr = parseInt(h)
  return `${hr > 12 ? hr - 12 : hr}:${m} ${hr >= 12 ? 'م' : 'ص'}`
}

function normalizeTime(t: string): string {
  // تطبيع HH:MM أو HH:MM:SS إلى HH:MM:SS للمقارنة الآمنة
  const parts = t.split(':')
  return `${(parts[0] ?? '00').padStart(2, '0')}:${(parts[1] ?? '00').padStart(2, '0')}:${(parts[2] ?? '00').padStart(2, '0')}`
}

function getPermissionOperationalState(r: { status: string; expected_return: string | null; actual_return: string | null }) {
  if (r.status === 'rejected') return { label: 'مرفوض', variant: 'danger' as const }
  if (r.status === 'pending') return { label: 'بانتظار الاعتماد', variant: 'warning' as const }
  if (!r.actual_return) return { label: 'خرج ولم يعد بعد', variant: 'warning' as const }
  if (r.expected_return && normalizeTime(r.actual_return) <= normalizeTime(r.expected_return)) return { label: 'عاد في الوقت', variant: 'success' as const }
  return { label: 'عاد متأخرًا', variant: 'danger' as const }
}

export default function PermissionsPage() {
  const qc = useQueryClient()
  const canAny  = useAuthStore(s => s.canAny)
  const { data: currentEmp } = useCurrentEmployee()

  const isManager = canAny(['hr.permissions.approve', 'hr.attendance.approve'])

  // State
  const [activeTab, setActiveTab] = useState<'my_requests' | 'team_approvals'>(isManager ? 'team_approvals' : 'my_requests')
  const [formOpen, setFormOpen] = useState(false)
  const [rejectId, setRejectId] = useState<string | null>(null)
  const [rejectReason, setRejectReason] = useState('')
  const [returnId, setReturnId] = useState<string | null>(null)
  const [actualReturn, setActualReturn] = useState('')
  const [returnNote, setReturnNote] = useState('')
  const [form, setForm] = useState<HRPermissionRequestInput>({
    employee_id:     '',
    permission_date: new Date().toISOString().split('T')[0],
    leave_time:      '14:00',
    expected_return: '16:00',
    reason:          '',
  })

  const completeReturnMut = useCompletePermissionReturn()

  // Auto-fill employee_id when form opens
  const openForm = () => {
    if (currentEmp) setForm(p => ({ ...p, employee_id: currentEmp.id }))
    setFormOpen(true)
  }

  const openReturnModal = (requestId: string, expectedReturn?: string | null) => {
    setReturnId(requestId)
    setActualReturn(expectedReturn ? expectedReturn.slice(0, 5) : new Date().toTimeString().slice(0, 5))
    setReturnNote('')
  }

  // Queries
  const { data: requests = [], isLoading } = useQuery({
    queryKey: ['hr-permission-requests', activeTab, currentEmp?.id],
    queryFn: () => getPermissionRequests(
      activeTab === 'team_approvals' ? undefined : { employeeId: currentEmp?.id }
    ),
    enabled: !!currentEmp || activeTab === 'team_approvals',
  })

  const createMut = useMutation({
    mutationFn: () => {
      // ★ تحقق صريح من employee_id عند الإرسال (وليس عند فتح النموذج)
      const empId = form.employee_id || currentEmp?.id
      if (!empId) throw new Error('تعذر تحديد الموظف — تأكد من ربط حسابك بسجل موظف')
      if (!form.reason.trim()) throw new Error('يرجى كتابة سبب الإذن')
      if (!form.permission_date) throw new Error('يرجى تحديد تاريخ الإذن')
      return createPermissionRequest({ ...form, employee_id: empId })
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['hr-permission-requests'] })
      toast.success('تم تقديم طلب الإذن بنجاح ✅')
      setFormOpen(false)
      setActiveTab('my_requests')
    },
    onError: (e: Error) => {
      console.error('[PermissionRequest] Error:', e)
      toast.error(`فشل تقديم الطلب: ${e.message}`)
    },
  })

  const approveMut = useMutation({
    mutationFn: (id: string) => approvePermissionRequest(id, currentEmp?.id ?? ''),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['hr-permission-requests'] })
      toast.success('تم اعتماد الإذن')
    },
    onError: (e: Error) => toast.error(e.message),
  })

  const rejectMut = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) =>
      rejectPermissionRequest(id, currentEmp?.id ?? '', reason),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['hr-permission-requests'] })
      toast.success('تم رفض الطلب')
      setRejectId(null)
      setRejectReason('')
    },
    onError: (e: Error) => toast.error(e.message),
  })

  const pendingCount = requests.filter(r => r.status === 'pending').length

  // ─── Columns & DataCard Mapping ───────────────────────
  const columns = [
    ...(activeTab === 'team_approvals' ? [{
      key: 'employee',
      label: 'الموظف',
      render: (r: any) => <strong>{r.employee?.full_name ?? '—'}</strong>,
    }] : []),
    {
      key: 'date',
      label: 'التاريخ',
      render: (r: any) => <span style={{ whiteSpace: 'nowrap' }}>{fmtDate(r.permission_date)}</span>,
    },
    {
      key: 'leave_time',
      label: 'وقت الخروج',
      render: (r: any) => <span style={{ fontVariantNumeric: 'tabular-nums' }}>{fmtTime(r.leave_time)}</span>,
    },
    {
      key: 'expected_return',
      label: 'وقت العودة المتوقع',
      render: (r: any) => <span style={{ fontVariantNumeric: 'tabular-nums' }}>{r.expected_return ? fmtTime(r.expected_return) : '—'}</span>,
    },
    {
      key: 'actual_return',
      label: 'العودة الفعلية',
      render: (r: any) => <span style={{ fontVariantNumeric: 'tabular-nums' }}>{r.actual_return ? fmtTime(r.actual_return) : '—'}</span>,
    },
    {
      key: 'reason',
      label: 'السبب',
      render: (r: any) => (
        <div style={{ maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={r.reason}>
          {r.reason}
        </div>
      ),
    },
    {
      key: 'return_note',
      label: 'ملاحظة العودة',
      render: (r: any) => {
        const note = r.return_note
        if (!note) return <span style={{ color: 'var(--text-muted)' }}>—</span>
        return (
          <div style={{ maxWidth: 180, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }} title={note}>
            {note}
          </div>
        )
      },
    },
    {
      key: 'status',
      label: 'الحالة',
      render: (r: any) => <Badge variant={STATUS_VARIANT[r.status]}>{STATUS_LABEL[r.status as keyof typeof STATUS_LABEL]}</Badge>,
    },
    {
      key: 'operational_status',
      label: 'الحالة التشغيلية',
      render: (r: any) => {
        const op = getPermissionOperationalState(r)
        return <Badge variant={op.variant}>{op.label}</Badge>
      },
    },
    {
      key: 'actions',
      label: '',
      render: (r: any) => {
        const canApproveRequest = activeTab === 'team_approvals' && r.status === 'pending'
        const canRecordReturn = r.status === 'approved' && !r.actual_return && (activeTab === 'my_requests' || isManager)
        if (!canApproveRequest && !canRecordReturn) return null

        return (
          <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap', justifyContent: 'flex-end' }}>
            {canApproveRequest && (
              <PermissionGuard permission={['hr.permissions.approve', 'hr.attendance.approve']}>
                <div style={{ display: 'flex', gap: 4 }}>
                  <Button
                    size="sm"
                    variant="ghost"
                    icon={<CheckCircle size={13} />}
                    onClick={(e) => { e.stopPropagation(); approveMut.mutate(r.id); }}
                    loading={approveMut.isPending}
                    style={{ color: 'var(--color-success)' }}
                  />
                  <Button
                    size="sm"
                    variant="ghost"
                    icon={<XCircle size={13} />}
                    onClick={(e) => { e.stopPropagation(); setRejectId(r.id); }}
                    style={{ color: 'var(--color-danger)' }}
                  />
                </div>
              </PermissionGuard>
            )}
            {canRecordReturn && (
              <Button
                size="sm"
                variant="ghost"
                icon={<Clock size={13} />}
                onClick={(e) => { e.stopPropagation(); openReturnModal(r.id, r.expected_return); }}
                style={{ color: 'var(--color-primary)' }}
              >
                تسجيل العودة
              </Button>
            )}
          </div>
        )
      },
    },
  ]



  return (
    <div className="page-container animate-enter">

      {/* ★ تنبيه: لا يوجد سجل موظف مربوط */}
      {!isManager && !currentEmp && (
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
              لن تتمكن من تقديم طلبات. يرجى التواصل مع مدير الموارد البشرية لربط حسابك.
            </div>
          </div>
        </div>
      )}

      <PageHeader
        title="أذونات الانصراف"
        subtitle="طلبات الخروج المؤقت أثناء دوام العمل"
        breadcrumbs={[
          { label: 'الموارد البشرية', path: '/hr' },
          { label: 'الأذونات' },
        ]}
        actions={
          <Button icon={<Plus size={14} />} onClick={openForm}>
            طلب إذن جديد
          </Button>
        }
      />

      {/* Pending badge */}
      {isManager && activeTab === 'team_approvals' && pendingCount > 0 && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          padding: 'var(--space-3) var(--space-4)',
          background: 'color-mix(in srgb, var(--color-warning) 8%, transparent)',
          border: '1px solid color-mix(in srgb, var(--color-warning) 25%, transparent)',
          borderRadius: 'var(--radius-md)', marginBottom: 'var(--space-4)',
          fontSize: 'var(--text-sm)',
        }}>
          <AlertCircle size={15} color="var(--color-warning)" />
          <span>
            يوجد <strong>{pendingCount}</strong> {pendingCount === 1 ? 'طلب' : 'طلبات'} بانتظار موافقتك
          </span>
        </div>
      )}

      {/* Segmented Control for Managers */}
      {isManager && (
        <div style={{ display: 'flex', gap: 'var(--space-1)', marginBottom: 'var(--space-4)', padding: 'var(--space-1)', background: 'var(--bg-muted)', borderRadius: 'var(--radius-lg)', width: 'fit-content', border: '1px solid var(--border-soft)' }}>
          <Button
            variant={activeTab === 'team_approvals' ? 'primary' : 'ghost'}
            size="sm"
            onClick={() => setActiveTab('team_approvals')}
          >
            طلبات الفريق (للاعتماد)
          </Button>
          <Button
            variant={activeTab === 'my_requests' ? 'primary' : 'ghost'}
            size="sm"
            onClick={() => setActiveTab('my_requests')}
          >
            طلباتي (الخاصة)
          </Button>
        </div>
      )}

      {/* List */}
      <div className="edara-card" style={{ padding: 0, overflow: 'hidden' }}>
        {isLoading ? (
          <div style={{ textAlign: 'center', padding: 'var(--space-8)', color: 'var(--text-muted)' }}>جارٍ التحميل...</div>
        ) : requests.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 'var(--space-8)' }}>
            <Clock size={40} style={{ opacity: 0.2, marginBottom: 8 }} />
            <div style={{ color: 'var(--text-muted)', marginBottom: 12 }}>لا توجد طلبات أذونات</div>
            <Button size="sm" icon={<Plus size={13} />} onClick={openForm}>طلب إذن جديد</Button>
          </div>
        ) : (
          <>
            <div className="perm-desktop-table">
              <DataTable
                columns={columns}
                data={requests}
                loading={isLoading}
                keyField="id"
              />
            </div>
            <div className="perm-mobile-cards" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)', padding: 'var(--space-4)' }}>
              {requests.map(r => (
                <DataCard
                  key={r.id}
                  title={activeTab === 'team_approvals' ? (r.employee?.full_name ?? 'موظف مجهول') : 'إذن انصراف'}
                  subtitle={fmtDate(r.permission_date)}
                  badge={<Badge variant={STATUS_VARIANT[r.status]}>{STATUS_LABEL[r.status as keyof typeof STATUS_LABEL]}</Badge>}
                  leading={
                    <div style={{
                      width: 40, height: 40, borderRadius: 'var(--radius-md)',
                      background: 'color-mix(in srgb, var(--color-primary) 10%, transparent)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--color-primary)'
                    }}>
                      <Clock size={16} />
                    </div>
                  }
                  metadata={[
                    { label: 'وقت الخروج', value: fmtTime(r.leave_time) },
                    { label: 'متوقع عودة', value: r.expected_return ? fmtTime(r.expected_return) : '—' },
                    { label: 'عودة فعلية', value: r.actual_return ? fmtTime(r.actual_return) : '—' },
                    { label: 'حالة الإذن', value: getPermissionOperationalState(r).label, highlight: getPermissionOperationalState(r).variant !== 'success' },
                    { label: 'السبب', value: r.reason },
                    ...(r.return_note ? [{ label: 'ملاحظة العودة', value: r.return_note }] : []),
                  ]}
                  actions={
                    r.status === 'pending' ? (
                      <PermissionGuard permission={['hr.permissions.approve', 'hr.attendance.approve']}>
                        <div style={{ display: 'flex', gap: 'var(--space-2)' }}>
                          <Button
                            size="sm"
                            variant="ghost"
                            icon={<CheckCircle size={13} />}
                            onClick={(e) => { e.stopPropagation(); approveMut.mutate(r.id); }}
                            loading={approveMut.isPending}
                            style={{ color: 'var(--color-success)', flex: 1, border: '1px solid color-mix(in srgb, var(--color-success) 30%, transparent)' }}
                          >اعتماد</Button>
                          <Button
                            size="sm"
                            variant="ghost"
                            icon={<XCircle size={13} />}
                            onClick={(e) => { e.stopPropagation(); setRejectId(r.id); }}
                            style={{ color: 'var(--color-danger)', flex: 1, border: '1px solid color-mix(in srgb, var(--color-danger) 30%, transparent)' }}
                          >رفض</Button>
                        </div>
                      </PermissionGuard>
                    ) : r.status === 'approved' && !r.actual_return && (activeTab === 'my_requests' || isManager) ? (
                      <Button
                        size="sm"
                        variant="secondary"
                        style={{ width: '100%', justifyContent: 'center' }}
                        onClick={(e) => { e.stopPropagation(); openReturnModal(r.id, r.expected_return) }}
                      >
                        <Clock size={12} style={{ marginInlineEnd: 4 }} /> تسجيل العودة
                      </Button>
                    ) : undefined
                  }
                />
              ))}
            </div>
          </>
        )}
      </div>

      {/* Add Permission Modal */}
      <ResponsiveModal
        open={formOpen}
        onClose={() => setFormOpen(false)}
        title="طلب إذن انصراف مبكر"
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => setFormOpen(false)} style={{ flex: 1 }}>إلغاء</Button>
            <Button
              icon={<Clock size={14} />}
              onClick={() => createMut.mutate()}
              loading={createMut.isPending}
              disabled={!form.reason.trim() || !form.permission_date}
              style={{ flex: 2 }}
            >
              تقديم الطلب
            </Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <Input label="تاريخ الإذن" type="date" required value={form.permission_date}
            onChange={e => setForm(p => ({ ...p, permission_date: e.target.value }))} />

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
            <Input label="وقت الخروج" type="time" required value={form.leave_time}
              onChange={e => setForm(p => ({ ...p, leave_time: e.target.value }))} dir="ltr" />
            <Input label="وقت العودة المتوقع" type="time" value={form.expected_return ?? ''}
              onChange={e => setForm(p => ({ ...p, expected_return: e.target.value || null }))} dir="ltr" />
          </div>

          <Input label="سبب الإذن" required value={form.reason}
            onChange={e => setForm(p => ({ ...p, reason: e.target.value }))}
            placeholder="مراجعة طبية، إجراء حكومي، ..." />
        </div>
      </ResponsiveModal>

      {returnId && (
        <ResponsiveModal
          open={!!returnId}
          onClose={() => { setReturnId(null); setActualReturn(''); setReturnNote('') }}
          title="تسجيل العودة الفعلية"
          size="sm"
          footer={
            <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
              <Button variant="secondary" onClick={() => { setReturnId(null); setActualReturn(''); setReturnNote('') }} style={{ flex: 1 }}>
                إلغاء
              </Button>
              <Button
                icon={<CheckCircle size={14} />}
                onClick={async () => {
                  if (!returnId || !actualReturn) return
                  await completeReturnMut.mutateAsync({
                    id: returnId,
                    actualReturn,
                    note: returnNote || null,
                  })
                  toast.success('تم تسجيل العودة الفعلية')
                  setReturnId(null)
                  setActualReturn('')
                  setReturnNote('')
                }}
                loading={completeReturnMut.isPending}
                disabled={!actualReturn}
                style={{ flex: 2 }}
              >
                حفظ العودة
              </Button>
            </div>
          }
        >
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
            <Input
              label="وقت العودة الفعلي"
              type="time"
              value={actualReturn}
              onChange={e => setActualReturn(e.target.value)}
              dir="ltr"
            />
            <Input
              label="ملاحظة إدارية"
              value={returnNote}
              onChange={e => setReturnNote(e.target.value)}
              placeholder="اختياري"
            />
          </div>
        </ResponsiveModal>
      )}

      {/* Reject reason modal - simplified inline */}
      {rejectId && (
        <ResponsiveModal
          open={!!rejectId}
          onClose={() => { setRejectId(null); setRejectReason('') }}
          title="رفض طلب الإذن"
          size="sm"
          footer={
            <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
              <Button variant="secondary" onClick={() => { setRejectId(null); setRejectReason('') }} style={{ flex: 1 }}>إلغاء</Button>
              <Button
                variant="danger"
                icon={<XCircle size={14} />}
                onClick={async () => {
                  if (!rejectId) return
                  rejectMut.mutate({ id: rejectId, reason: rejectReason })
                }}
                loading={rejectMut.isPending}
                disabled={!rejectReason.trim()}
                style={{ flex: 2 }}
              >رفض الطلب</Button>
            </div>
          }
        >
          <Input
            label="سبب الرفض"
            value={rejectReason}
            onChange={e => setRejectReason(e.target.value)}
            placeholder="أدخل سبب الرفض..."
          />
        </ResponsiveModal>
      )}

      <style>{`
        .perm-desktop-table { display: block; }
        .perm-mobile-cards  { display: none; }
        @media (max-width: 768px) {
          .perm-desktop-table { display: none; }
          .perm-mobile-cards  { display: flex; }
        }
      `}</style>
    </div>
  )
}
