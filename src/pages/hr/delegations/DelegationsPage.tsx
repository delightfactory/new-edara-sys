import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Plus, Trash2, UserCheck, Clock, Shield } from 'lucide-react'
import { getDelegations, createDelegation, cancelDelegation, getEmployees } from '@/lib/services/hr'
import type { HRDelegationInput, HRDelegationScopeType } from '@/lib/types/hr'
import { useAuthStore } from '@/stores/auth-store'
import { useCurrentEmployee } from '@/hooks/useQueryHooks'
import Button from '@/components/ui/Button'
import Badge from '@/components/ui/Badge'
import Input from '@/components/ui/Input'
import Select from '@/components/ui/Select'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import { toast } from 'sonner'

// صلاحيات قابلة للتفويض
const DELEGATABLE_PERMISSIONS = [
  { value: 'hr.leaves.approve',      label: 'اعتماد طلبات الإجازة' },
  { value: 'hr.advances.approve',    label: 'اعتماد طلبات السلف' },
  { value: 'hr.attendance.approve',  label: 'اعتماد الحضور' },
  { value: 'hr.permissions.approve', label: 'اعتماد أذونات الانصراف' },
]

// نوع الفورم الداخلي
type DelegForm = {
  delegate_id: string
  permissions: string[]
  scope_type: HRDelegationScopeType
  valid_from: string
  valid_until: string
  reason: string
}

const EMPTY_FORM: DelegForm = {
  delegate_id: '', permissions: [], scope_type: 'all', valid_from: '', valid_until: '', reason: '',
}

export default function DelegationsPage() {
  const qc = useQueryClient()
  const can = useAuthStore(s => s.can)
  const { data: currentEmployee } = useCurrentEmployee()

  const [createOpen, setCreateOpen] = useState(false)
  const [form, setForm] = useState<DelegForm>(EMPTY_FORM)

  // جلب كل الموظفين للـ dropdown
  const { data: employeesResult } = useQuery({
    queryKey: ['hr-employees-dropdown'],
    queryFn: () => getEmployees({ status: 'active', pageSize: 200 }),
  })
  const allEmployees = employeesResult?.data ?? []

  // تفويضاتي (التي أعطيتها)
  const { data: myDelegations = [], isLoading } = useQuery({
    queryKey: ['hr-delegations-me', currentEmployee?.id],
    queryFn: () => currentEmployee
      ? getDelegations({ delegatorId: currentEmployee.id })
      : Promise.resolve([]),
    enabled: !!currentEmployee,
  })

  // التفويضات الممنوحة لي (delegate_id = me)
  const { data: delegatedToMe = [] } = useQuery({
    queryKey: ['hr-delegations-to-me', currentEmployee?.id],
    queryFn: () => currentEmployee
      ? getDelegations({ delegateId: currentEmployee.id, activeOnly: true })
      : Promise.resolve([]),
    enabled: !!currentEmployee,
  })

  const createMut = useMutation({
    mutationFn: (input: HRDelegationInput) => createDelegation(input),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['hr-delegations-me'] })
      toast.success('تم إنشاء التفويض')
      setCreateOpen(false)
      setForm(EMPTY_FORM)
    },
    onError: (e: any) => toast.error(e.message ?? 'فشل إنشاء التفويض'),
  })

  const cancelMut = useMutation({
    mutationFn: (id: string) => cancelDelegation(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['hr-delegations-me'] })
      toast.success('تم إلغاء التفويض')
    },
    onError: (e: any) => toast.error(e.message ?? 'فشل إلغاء التفويض'),
  })

  const handleCreate = () => {
    if (!currentEmployee || !form.delegate_id || form.permissions.length === 0 || !form.valid_from || !form.valid_until) {
      toast.error('يرجى تعبئة جميع الحقول المطلوبة واختيار صلاحية')
      return
    }
    if (form.valid_until <= form.valid_from) {
      toast.error('تاريخ الانتهاء يجب أن يكون بعد تاريخ البداية')
      return
    }
    createMut.mutate({
      delegator_id: currentEmployee.id,
      delegate_id:  form.delegate_id,
      permissions:  form.permissions,
      scope_type:   form.scope_type,
      valid_from:   form.valid_from,
      valid_until:  form.valid_until,
      reason:       form.reason || null,
    })
  }

  const togglePermission = (perm: string) => {
    setForm(p => ({
      ...p,
      permissions: p.permissions.includes(perm)
        ? p.permissions.filter(x => x !== perm)
        : [...p.permissions, perm],
    }))
  }

  const now = new Date().toISOString()
  const formatDate = (d: string) => new Date(d).toLocaleDateString('ar-EG-u-nu-latn', { day: 'numeric', month: 'short', year: 'numeric' })
  const permLabel = (perms: string[]) =>
    perms.map(p => DELEGATABLE_PERMISSIONS.find(x => x.value === p)?.label ?? p).join('، ')

  return (
    <div className="page-container animate-enter" style={{ maxWidth: 900 }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 'var(--space-6)' }}>
        <div>
          <h1 style={{ fontWeight: 800, fontSize: 'var(--text-2xl)', marginBottom: 'var(--space-1)' }}>التفويضات الزمنية</h1>
          <p style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>
            فوِّض صلاحياتك مؤقتاً إلى زميل خلال غيابك
          </p>
        </div>
        {can('hr.employees.read') && (
          <Button icon={<Plus size={16} />} onClick={() => setCreateOpen(true)}>
            تفويض جديد
          </Button>
        )}
      </div>

      {/* تفويضات أعطيتها */}
      <div className="edara-card" style={{ marginBottom: 'var(--space-5)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginBottom: 'var(--space-4)' }}>
          <UserCheck size={16} style={{ color: 'var(--color-primary)' }} />
          <h2 style={{ fontWeight: 700, fontSize: 'var(--text-base)', margin: 0 }}>التفويضات التي أعطيتها</h2>
        </div>

        {isLoading ? (
          <div style={{ textAlign: 'center', padding: 'var(--space-6)', color: 'var(--text-muted)' }}>جارٍ التحميل...</div>
        ) : myDelegations.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 'var(--space-6)', color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>
            <Shield size={28} style={{ display: 'block', margin: '0 auto var(--space-2)', opacity: 0.3 }} />
            لا توجد تفويضات حالية
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            {myDelegations.map(d => {
              const isActive = d.is_active && d.valid_from <= now && d.valid_until >= now
              return (
                <div key={d.id} style={{
                  display: 'flex', alignItems: 'flex-start', gap: 'var(--space-3)',
                  padding: 'var(--space-3) var(--space-4)',
                  borderRadius: 'var(--radius-md)',
                  border: `1px solid ${isActive ? 'color-mix(in srgb, var(--color-success) 25%, transparent)' : 'var(--border-color)'}`,
                  background: isActive ? 'color-mix(in srgb, var(--color-success) 5%, transparent)' : 'var(--bg-surface-2)',
                }}>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>
                      {d.delegate?.full_name ?? '—'}
                    </div>
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                      {permLabel(d.permissions)} · {formatDate(d.valid_from)} — {formatDate(d.valid_until)}
                    </div>
                    {d.scope_type !== 'all' && (
                      <div style={{ fontSize: 'var(--text-xs)', color: 'var(--color-info)' }}>
                        نطاق: {d.scope_type === 'branch' ? 'فرع' : 'فريق'} محدد
                      </div>
                    )}
                    {d.reason && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontStyle: 'italic' }}>{d.reason}</div>}
                  </div>
                  <Badge variant={isActive ? 'success' : 'neutral'}>
                    {isActive ? 'نشط' : (d.is_active ? 'قادم' : 'منتهٍ')}
                  </Badge>
                  {d.is_active && (
                    <Button
                      size="sm" variant="danger"
                      icon={<Trash2 size={13} />}
                      loading={cancelMut.isPending}
                      onClick={() => cancelMut.mutate(d.id)}
                    >
                      إلغاء
                    </Button>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </div>

      {/* تفويضات أُعطيت لي */}
      <div className="edara-card">
        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginBottom: 'var(--space-4)' }}>
          <Clock size={16} style={{ color: 'var(--color-warning)' }} />
          <h2 style={{ fontWeight: 700, fontSize: 'var(--text-base)', margin: 0 }}>التفويضات الممنوحة لي</h2>
        </div>

        {delegatedToMe.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 'var(--space-6)', color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>
            لا توجد تفويضات ممنوحة لك حالياً
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            {delegatedToMe.map(d => (
              <div key={d.id} style={{
                display: 'flex', alignItems: 'flex-start', gap: 'var(--space-3)',
                padding: 'var(--space-3) var(--space-4)',
                borderRadius: 'var(--radius-md)',
                border: '1px solid color-mix(in srgb, var(--color-warning) 25%, transparent)',
                background: 'color-mix(in srgb, var(--color-warning) 5%, transparent)',
              }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>
                    من: {d.delegator?.full_name ?? '—'}
                  </div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    {permLabel(d.permissions)} · حتى {formatDate(d.valid_until)}
                  </div>
                </div>
                <Badge variant="warning">نشط</Badge>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Create Modal */}
      <ResponsiveModal
        open={createOpen}
        onClose={() => { setCreateOpen(false); setForm(EMPTY_FORM) }}
        title="تفويض جديد"
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => { setCreateOpen(false); setForm(EMPTY_FORM) }} style={{ flex: 1 }}>إلغاء</Button>
            <Button onClick={handleCreate} loading={createMut.isPending} disabled={form.permissions.length === 0} style={{ flex: 2 }}>حفظ التفويض</Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <Select
            label="المُفوَّض إليه"
            required
            value={form.delegate_id}
            onChange={e => setForm(p => ({ ...p, delegate_id: e.target.value }))}
            options={[
              { value: '', label: 'اختر موظفاً...' },
              ...allEmployees
                .filter(e => e.id !== currentEmployee?.id)
                .map(e => ({ value: e.id, label: e.full_name })),
            ]}
          />

          <div>
            <label style={{ fontSize: 'var(--text-xs)', fontWeight: 600, color: 'var(--text-muted)', display: 'block', marginBottom: 'var(--space-2)' }}>
              الصلاحيات المُفوَّضة <span style={{ color: 'var(--color-danger)' }}>*</span>
            </label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
              {DELEGATABLE_PERMISSIONS.map(opt => (
                <label key={opt.value} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 'var(--text-sm)', cursor: 'pointer' }}>
                  <input
                    type="checkbox"
                    checked={form.permissions.includes(opt.value)}
                    onChange={() => togglePermission(opt.value)}
                  />
                  {opt.label}
                </label>
              ))}
            </div>
          </div>

          <Select
            label="نطاق التفويض"
            value={form.scope_type}
            onChange={e => setForm(p => ({ ...p, scope_type: e.target.value as HRDelegationScopeType }))}
            options={[
              { value: 'all',    label: 'كل الشركة' },
              { value: 'branch', label: 'فرع محدد' },
              { value: 'team',   label: 'فريق محدد' },
            ]}
          />

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
            <Input
              label="من تاريخ" type="date" required
              value={form.valid_from}
              onChange={e => setForm(p => ({ ...p, valid_from: e.target.value }))}
            />
            <Input
              label="إلى تاريخ" type="date" required
              value={form.valid_until}
              onChange={e => setForm(p => ({ ...p, valid_until: e.target.value }))}
            />
          </div>
          <Input
            label="سبب التفويض"
            value={form.reason}
            onChange={e => setForm(p => ({ ...p, reason: e.target.value }))}
            placeholder="سفر، إجازة، دورة تدريبية..."
          />
        </div>
      </ResponsiveModal>
    </div>
  )
}
