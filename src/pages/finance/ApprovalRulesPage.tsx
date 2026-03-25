import { useState, useEffect, useCallback } from 'react'
import { toast } from 'sonner'
import { ShieldCheck, Plus, Edit, Trash2, ToggleLeft, ToggleRight } from 'lucide-react'
import { getApprovalRules, createApprovalRule, updateApprovalRule, deleteApprovalRule, getRolesForApproval } from '@/lib/services/finance'
import { useAuthStore } from '@/stores/auth-store'
import type { ApprovalRule, ApprovalType } from '@/lib/types/master-data'
import { formatNumber } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Modal from '@/components/ui/Modal'
import ConfirmDialog from '@/components/ui/ConfirmDialog'

const APPROVAL_TYPE_LABELS: Record<ApprovalType, string> = {
  expense: 'المصروفات',
  purchase_order: 'أوامر الشراء',
  sales_discount: 'خصومات المبيعات',
}

const APPROVAL_TYPE_BADGE: Record<ApprovalType, 'warning' | 'primary' | 'info'> = {
  expense: 'warning',
  purchase_order: 'primary',
  sales_discount: 'info',
}

export default function ApprovalRulesPage() {
  const can = useAuthStore(s => s.can)

  const [rules, setRules] = useState<ApprovalRule[]>([])
  const [loading, setLoading] = useState(true)
  const [roles, setRoles] = useState<{ id: string; name: string; name_ar: string; color: string }[]>([])
  const [filterType, setFilterType] = useState('')

  // Form
  const [formOpen, setFormOpen] = useState(false)
  const [editingRule, setEditingRule] = useState<ApprovalRule | null>(null)
  const [formType, setFormType] = useState<ApprovalType>('expense')
  const [formRoleId, setFormRoleId] = useState('')
  const [formMaxAmount, setFormMaxAmount] = useState('')
  const [formSortOrder, setFormSortOrder] = useState('0')
  const [saving, setSaving] = useState(false)

  // Delete
  const [deleteTarget, setDeleteTarget] = useState<ApprovalRule | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getApprovalRules(filterType || undefined)
      setRules(data)
    } catch { toast.error('فشل تحميل قواعد الموافقات') }
    finally { setLoading(false) }
  }, [filterType])

  useEffect(() => {
    const init = async () => {
      const rs = await getRolesForApproval()
      setRoles(rs)
      await load()
    }
    init()
  }, [load])

  useEffect(() => { load() }, [filterType, load])

  // ── Form ──
  const openCreate = () => {
    setEditingRule(null)
    setFormType('expense')
    setFormRoleId('')
    setFormMaxAmount('')
    setFormSortOrder('0')
    setFormOpen(true)
  }

  const openEdit = (rule: ApprovalRule) => {
    setEditingRule(rule)
    setFormType(rule.type)
    setFormRoleId(rule.role_id)
    setFormMaxAmount(String(rule.max_amount))
    setFormSortOrder(String(rule.sort_order))
    setFormOpen(true)
  }

  const handleSave = async () => {
    const maxAmount = parseFloat(formMaxAmount)
    const sortOrder = parseInt(formSortOrder) || 0

    if (editingRule) {
      if (!maxAmount || maxAmount <= 0) { toast.error('الحد الأقصى يجب أن يكون أكبر من صفر'); return }
      setSaving(true)
      try {
        await updateApprovalRule(editingRule.id, { max_amount: maxAmount, sort_order: sortOrder })
        toast.success('تم تعديل القاعدة')
        setFormOpen(false); load()
      } catch (err: any) { toast.error(err.message || 'فشل التعديل') }
      finally { setSaving(false) }
    } else {
      if (!formRoleId) { toast.error('الدور مطلوب'); return }
      if (!maxAmount || maxAmount <= 0) { toast.error('الحد الأقصى يجب أن يكون أكبر من صفر'); return }
      setSaving(true)
      try {
        await createApprovalRule({ type: formType, role_id: formRoleId, max_amount: maxAmount, sort_order: sortOrder })
        toast.success('تم إنشاء القاعدة')
        setFormOpen(false); load()
      } catch (err: any) {
        if (err.message?.includes('unique') || err.message?.includes('duplicate')) {
          toast.error('هذا الدور مضاف بالفعل لهذا النوع')
        } else {
          toast.error(err.message || 'فشل الإنشاء')
        }
      }
      finally { setSaving(false) }
    }
  }

  const handleToggle = async (rule: ApprovalRule) => {
    try {
      await updateApprovalRule(rule.id, { is_active: !rule.is_active })
      toast.success(rule.is_active ? 'تم تعطيل القاعدة' : 'تم تفعيل القاعدة')
      load()
    } catch (err: any) { toast.error(err.message) }
  }

  const handleDelete = async () => {
    if (!deleteTarget) return
    try {
      await deleteApprovalRule(deleteTarget.id)
      toast.success('تم حذف القاعدة')
      setDeleteTarget(null); load()
    } catch (err: any) { toast.error(err.message) }
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="قواعد الموافقات"
        subtitle="إدارة حدود الموافقة لكل دور ونوع عملية"
        actions={can('settings.update') ? <Button icon={<Plus size={16} />} onClick={openCreate}>قاعدة جديدة</Button> : undefined}
      />

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-3" style={{ flexWrap: 'wrap' }}>
          <select className="form-select" style={{ width: 160 }} value={filterType} onChange={e => setFilterType(e.target.value)}>
            <option value="">كل الأنواع</option>
            <option value="expense">المصروفات</option>
            <option value="purchase_order">أوامر الشراء</option>
            <option value="sales_discount">خصومات المبيعات</option>
          </select>
        </div>
      </div>

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        <DataTable<ApprovalRule>
          columns={[
            { key: 'type', label: 'النوع', render: (r) => <Badge variant={APPROVAL_TYPE_BADGE[r.type]}>{APPROVAL_TYPE_LABELS[r.type]}</Badge> },
            { key: 'role', label: 'الدور', render: (r) => (
              <div className="flex gap-2" style={{ alignItems: 'center' }}>
                <span className="role-dot" style={{ background: r.role?.color || 'var(--text-muted)' }} />
                <span style={{ fontWeight: 600 }}>{r.role?.name_ar || r.role?.name || '—'}</span>
              </div>
            )},
            { key: 'max_amount', label: 'الحد الأقصى', render: (r) => (
              <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: 'var(--color-primary)' }}>
                {r.max_amount >= 99999999 ? '∞ بلا حد' : formatNumber(r.max_amount) + ' ج.م'}
              </span>
            )},
            { key: 'sort_order', label: 'الأولوية', hideOnMobile: true, render: (r) => (
              <Badge variant="neutral">{r.sort_order}</Badge>
            )},
            { key: 'is_active', label: 'الحالة', render: (r) => (
              <Badge variant={r.is_active ? 'success' : 'neutral'}>{r.is_active ? 'نشطة' : 'معطلة'}</Badge>
            )},
            { key: 'actions', label: 'إجراءات', width: 130, render: (r) => (
              can('settings.update') ? (
                <div className="action-group" onClick={e => e.stopPropagation()}>
                  <Button variant="ghost" size="sm" title="تعديل" onClick={() => openEdit(r)}><Edit size={14} /></Button>
                  <Button variant={r.is_active ? 'ghost' : 'success'} size="sm" title={r.is_active ? 'تعطيل' : 'تفعيل'}
                    onClick={() => handleToggle(r)}>
                    {r.is_active ? <ToggleLeft size={14} /> : <ToggleRight size={14} />}
                  </Button>
                  <Button variant="danger" size="sm" title="حذف" onClick={() => setDeleteTarget(r)}><Trash2 size={14} /></Button>
                </div>
              ) : null
            )},
          ]}
          data={rules}
          loading={loading}
          emptyIcon={<ShieldCheck size={48} />}
          emptyTitle="لا توجد قواعد موافقات"
          emptyText="أضف قاعدة لتحديد حدود الموافقة لكل دور"
          emptyAction={can('settings.update') ? <Button icon={<Plus size={16} />} onClick={openCreate}>إضافة قاعدة</Button> : undefined}
        />
      </div>

      {/* ── Info box ── */}
      <div className="edara-card info-explanation" style={{ marginTop: 'var(--space-4)' }}>
        <h4>كيف تعمل قواعد الموافقات؟</h4>
        <ul>
          <li><strong>النوع:</strong> تحدد نوع العملية التي تنطبق عليها القاعدة (مصروفات، أوامر شراء، خصومات)</li>
          <li><strong>الدور:</strong> دور المستخدم الذي يُسمح له بالموافقة</li>
          <li><strong>الحد الأقصى:</strong> أقصى مبلغ يمكن لحامل هذا الدور الموافقة عليه</li>
          <li><strong>الأولوية:</strong> ترتيب المستوى في سلسلة الموافقات (الأقل = الأعلى أولوية)</li>
          <li><strong>ملاحظة:</strong> مدير النظام (<code>super_admin</code>) يتجاوز جميع القواعد تلقائياً</li>
        </ul>
      </div>

      {/* ── Form Modal ── */}
      <Modal open={formOpen} onClose={() => setFormOpen(false)} title={editingRule ? 'تعديل قاعدة الموافقة' : 'قاعدة موافقة جديدة'} size="sm"
        footer={<><Button variant="ghost" onClick={() => setFormOpen(false)}>إلغاء</Button><Button onClick={handleSave} loading={saving}>حفظ</Button></>}
      >
        <div className="flex-col gap-4">
          <div className="form-group">
            <label className="form-label required">نوع العملية</label>
            <select className="form-select" value={formType} disabled={!!editingRule}
              onChange={e => setFormType(e.target.value as ApprovalType)}>
              <option value="expense">المصروفات</option>
              <option value="purchase_order">أوامر الشراء</option>
              <option value="sales_discount">خصومات المبيعات</option>
            </select>
          </div>
          <div className="form-group">
            <label className="form-label required">الدور</label>
            <select className="form-select" value={formRoleId} disabled={!!editingRule}
              onChange={e => setFormRoleId(e.target.value)}>
              <option value="">— اختر الدور —</option>
              {roles.map(r => (
                <option key={r.id} value={r.id}>{r.name_ar} ({r.name})</option>
              ))}
            </select>
          </div>
          <div className="form-group">
            <label className="form-label required">الحد الأقصى للمبلغ</label>
            <input className="form-input" type="number" min="0" step="0.01" value={formMaxAmount}
              onChange={e => setFormMaxAmount(e.target.value)} placeholder="مثال: 10000" />
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>أقصى مبلغ يمكن لحامل هذا الدور الموافقة عليه</span>
          </div>
          <div className="form-group">
            <label className="form-label">ترتيب الأولوية</label>
            <input className="form-input" type="number" min="0" value={formSortOrder}
              onChange={e => setFormSortOrder(e.target.value)} placeholder="0" />
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>0 = أعلى أولوية (مدير النظام)، ثم 1، 2، ...</span>
          </div>
        </div>
      </Modal>

      {/* ── Delete Confirm ── */}
      <ConfirmDialog
        open={!!deleteTarget}
        title="حذف قاعدة الموافقة"
        message={`هل تريد حذف قاعدة الموافقة للدور "${deleteTarget?.role?.name_ar || ''}" (${APPROVAL_TYPE_LABELS[deleteTarget?.type || 'expense']})؟`}
        variant="danger"
        confirmText="حذف"
        onConfirm={handleDelete}
        onCancel={() => setDeleteTarget(null)}
      />

    </div>
  )
}
