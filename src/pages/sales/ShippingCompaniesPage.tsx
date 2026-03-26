import { useState } from 'react'
import { toast } from 'sonner'
import { Truck, Plus, Edit, ToggleLeft, ToggleRight } from 'lucide-react'
import { useShippingCompanies, useInvalidate } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { saveShippingCompany, toggleShippingCompany } from '@/lib/services/sales'
import type { ShippingCompany, ShippingCompanyInput } from '@/lib/types/master-data'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Modal from '@/components/ui/Modal'

export default function ShippingCompaniesPage() {
  const can = useAuthStore(s => s.can)
  const invalidate = useInvalidate()
  const { data: companies = [], isLoading } = useShippingCompanies(false)

  const [modalOpen, setModalOpen] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState<ShippingCompanyInput>({ name: '', phone: null, email: null, notes: null })
  const [saving, setSaving] = useState(false)

  const openCreate = () => {
    setEditId(null)
    setForm({ name: '', phone: null, email: null, notes: null })
    setModalOpen(true)
  }

  const openEdit = (c: ShippingCompany) => {
    setEditId(c.id)
    setForm({ name: c.name, phone: c.phone, email: c.email, notes: c.notes })
    setModalOpen(true)
  }

  const handleSave = async () => {
    if (!form.name.trim()) { toast.error('اسم الشركة مطلوب'); return }
    setSaving(true)
    try {
      await saveShippingCompany(form, editId || undefined)
      toast.success(editId ? 'تم التحديث' : 'تم الإضافة')
      setModalOpen(false)
      invalidate('shipping-companies')
    } catch (err: any) {
      toast.error(err.message || 'فشلت العملية')
    } finally { setSaving(false) }
  }

  const handleToggle = async (c: ShippingCompany) => {
    try {
      await toggleShippingCompany(c.id, !c.is_active)
      toast.success(c.is_active ? 'تم التعطيل' : 'تم التفعيل')
      invalidate('shipping-companies')
    } catch (err: any) { toast.error(err.message) }
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="شركات الشحن"
        subtitle={`${companies.length} شركة`}
        actions={can('sales.shipping.manage') ? (
          <Button icon={<Plus size={16} />} onClick={openCreate}>شركة جديدة</Button>
        ) : undefined}
      />

      <div className="edara-card" style={{ overflow: 'auto' }}>
        <DataTable<ShippingCompany>
          columns={[
            { key: 'name', label: 'الاسم', render: c => <span style={{ fontWeight: 600 }}>{c.name}</span> },
            { key: 'phone', label: 'الهاتف', hideOnMobile: true, render: c => c.phone || <span style={{ color: 'var(--text-muted)' }}>—</span> },
            { key: 'email', label: 'البريد', hideOnMobile: true, render: c => c.email || <span style={{ color: 'var(--text-muted)' }}>—</span> },
            {
              key: 'status', label: 'الحالة',
              render: c => <Badge variant={c.is_active ? 'success' : 'danger'}>{c.is_active ? 'نشط' : 'معطل'}</Badge>,
            },
            {
              key: 'actions', label: '', width: 100,
              render: c => can('sales.shipping.manage') ? (
                <div className="flex gap-1" onClick={e => e.stopPropagation()}>
                  <Button variant="ghost" size="sm" onClick={() => openEdit(c)} title="تعديل"><Edit size={14} /></Button>
                  <Button variant="ghost" size="sm" onClick={() => handleToggle(c)} title={c.is_active ? 'تعطيل' : 'تفعيل'}>
                    {c.is_active ? <ToggleRight size={14} color="var(--color-success)" /> : <ToggleLeft size={14} />}
                  </Button>
                </div>
              ) : null,
            },
          ]}
          data={companies}
          loading={isLoading}
          emptyIcon={<Truck size={48} />}
          emptyTitle="لا توجد شركات شحن"
          emptyText="ابدأ بإضافة شركات الشحن المتعامل معها"
          emptyAction={can('sales.shipping.manage') ? (
            <Button icon={<Plus size={16} />} onClick={openCreate}>شركة جديدة</Button>
          ) : undefined}
        />
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editId ? 'تعديل شركة شحن' : 'شركة شحن جديدة'} size="sm">
        <div style={{ display: 'grid', gap: 'var(--space-4)' }}>
          <div>
            <label className="form-label">اسم الشركة *</label>
            <input className="form-input" value={form.name}
              onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
              placeholder="مثال: أرامكس، فيد إكس..." />
          </div>
          <div>
            <label className="form-label">الهاتف</label>
            <input className="form-input" value={form.phone || ''}
              onChange={e => setForm(f => ({ ...f, phone: e.target.value || null }))}
              placeholder="رقم الهاتف..." />
          </div>
          <div>
            <label className="form-label">البريد الإلكتروني</label>
            <input className="form-input" type="email" value={form.email || ''}
              onChange={e => setForm(f => ({ ...f, email: e.target.value || null }))}
              placeholder="email@company.com" />
          </div>
          <div>
            <label className="form-label">ملاحظات</label>
            <textarea className="form-input" rows={2} value={form.notes || ''}
              onChange={e => setForm(f => ({ ...f, notes: e.target.value || null }))}
              placeholder="ملاحظات إضافية..." />
          </div>
          <div className="flex gap-3" style={{ justifyContent: 'flex-end' }}>
            <Button variant="ghost" onClick={() => setModalOpen(false)}>إلغاء</Button>
            <Button onClick={handleSave} disabled={saving}>
              {saving ? 'جاري الحفظ...' : 'حفظ'}
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  )
}
