import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { Plus, Building2, Edit, MapPin, Phone, ToggleLeft, ToggleRight } from 'lucide-react'
import { getBranches, createBranch, updateBranch } from '@/lib/services/geography'
import { getGovernorates, getCities } from '@/lib/services/geography'
import { useAuthStore } from '@/stores/auth-store'
import type { Branch, BranchInput, BranchType, Governorate, City } from '@/lib/types/master-data'
import PageHeader from '@/components/shared/PageHeader'
import EmptyState from '@/components/shared/EmptyState'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Modal from '@/components/ui/Modal'
import ConfirmDialog from '@/components/ui/ConfirmDialog'

export default function BranchesPage() {
  const can = useAuthStore(s => s.can)
  const [branches, setBranches] = useState<Branch[]>([])
  const [loading, setLoading] = useState(true)
  const [modal, setModal] = useState<{ open: boolean; editing?: Branch }>({ open: false })
  const [governorates, setGovernorates] = useState<Governorate[]>([])
  const [cities, setCities] = useState<City[]>([])
  const [profiles, setProfiles] = useState<{ id: string; full_name: string }[]>([])
  const [saving, setSaving] = useState(false)
  const [selectedGov, setSelectedGov] = useState('')
  const [confirmTarget, setConfirmTarget] = useState<Branch | null>(null)

  const [form, setForm] = useState<BranchInput>({
    name: '', type: 'distribution',
    city_id: null, address: '', phone: '', manager_id: null,
  })

  const load = async () => {
    setLoading(true)
    try { setBranches(await getBranches()) }
    catch { toast.error('فشل تحميل الفروع') }
    finally { setLoading(false) }
  }

  useEffect(() => {
    const init = async () => {
      const [govs] = await Promise.all([getGovernorates()])
      setGovernorates(govs)
      const { data } = await (await import('@/lib/supabase/client')).supabase
        .from('profiles').select('id, full_name').eq('status', 'active').order('full_name')
      if (data) setProfiles(data)
      await load()
    }
    init()
  }, [])

  const handleGovChange = async (govId: string) => {
    setSelectedGov(govId)
    setForm(f => ({ ...f, city_id: null }))
    setCities(govId ? await getCities(govId) : [])
  }

  const openCreate = () => {
    setForm({ name: '', type: 'distribution', city_id: null, address: '', phone: '', manager_id: null })
    setSelectedGov('')
    setCities([])
    setModal({ open: true })
  }

  const openEdit = async (b: Branch) => {
    const govId = b.city?.governorate?.id || ''
    setSelectedGov(govId)
    if (govId) setCities(await getCities(govId))
    setForm({
      name: b.name, type: b.type,
      city_id: b.city_id, address: b.address || '', phone: b.phone || '', manager_id: b.manager_id,
    })
    setModal({ open: true, editing: b })
  }

  const handleSave = async () => {
    if (!form.name.trim()) { toast.error('يرجى ملء اسم الفرع'); return }
    setSaving(true)
    try {
      if (modal.editing) {
        await updateBranch(modal.editing.id, form)
        toast.success('تم التحديث')
      } else {
        await createBranch(form)
        toast.success('تم الإنشاء')
      }
      setModal({ open: false })
      load()
    } catch { toast.error('فشلت العملية') }
    finally { setSaving(false) }
  }

  const executeToggle = async () => {
    if (!confirmTarget) return
    try {
      await updateBranch(confirmTarget.id, { is_active: !confirmTarget.is_active } as Partial<BranchInput> & { is_active: boolean })
      toast.success(confirmTarget.is_active ? 'تم التعطيل' : 'تم التفعيل')
      load()
    } catch { toast.error('فشلت العملية') }
    finally { setConfirmTarget(null) }
  }

  const typeLabels: Record<string, { label: string; variant: 'primary' | 'info' | 'warning' }> = {
    distribution: { label: 'توزيع', variant: 'primary' },
    retail: { label: 'تجزئة', variant: 'info' },
    warehouse: { label: 'مخزن', variant: 'warning' },
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="الفروع"
        subtitle={loading ? '...' : `${branches.length} فرع`}
        actions={can('branches.create') ? (
          <Button icon={<Plus size={16} />} onClick={openCreate}>إضافة فرع</Button>
        ) : undefined}
      />

      {loading ? (
        <div className="grid grid-3 gap-4">
          {[1,2,3].map(i => <div key={i} className="skeleton" style={{ height: 180, borderRadius: 'var(--radius-lg)' }} />)}
        </div>
      ) : branches.length === 0 ? (
        <div className="edara-card">
          <EmptyState
            icon={<Building2 size={48} />}
            title="لا يوجد فروع"
            text="أضف الفروع لتنظيم هيكل الشركة"
            action={<Button icon={<Plus size={16} />} onClick={openCreate}>إضافة أول فرع</Button>}
          />
        </div>
      ) : (
        <div className="grid grid-3 gap-4">
          {branches.map(b => (
            <div key={b.id} className="edara-card edara-card-interactive" style={{ padding: 'var(--space-5)' }}>
              <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-3)' }}>
                <div className="flex items-center gap-3">
                  <div style={{ width: 42, height: 42, borderRadius: 'var(--radius-md)', background: 'var(--color-info-light)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <Building2 size={20} style={{ color: 'var(--color-info)' }} />
                  </div>
                  <div>
                    <h3 style={{ fontWeight: 700, fontSize: 'var(--text-sm)' }}>{b.name}</h3>
                    {b.manager && <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>مدير: {b.manager.full_name}</p>}
                  </div>
                </div>
                <Badge variant={typeLabels[b.type]?.variant || 'neutral'}>{typeLabels[b.type]?.label || b.type}</Badge>
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', marginBottom: 'var(--space-3)' }}>
                {b.city?.governorate?.name && (
                  <div className="flex items-center gap-2" style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>
                    <MapPin size={12} /> {b.city.governorate.name}{b.city?.name ? ` — ${b.city.name}` : ''}
                  </div>
                )}
                {b.phone && (
                  <div className="flex items-center gap-2" style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}>
                    <Phone size={12} /> <span dir="ltr">{b.phone}</span>
                  </div>
                )}
              </div>

              <div style={{ borderTop: '1px solid var(--divider)', paddingTop: 'var(--space-3)' }} className="flex items-center justify-between">
                <Badge variant={b.is_active ? 'success' : 'danger'}>{b.is_active ? 'نشط' : 'معطل'}</Badge>
                <div className="flex gap-1">
                  {can('branches.create') && (
                    <Button variant="ghost" size="sm" title={b.is_active ? 'تعطيل' : 'تفعيل'} onClick={() => setConfirmTarget(b)}>
                      {b.is_active ? <ToggleRight size={16} style={{ color: 'var(--color-success)' }} /> : <ToggleLeft size={16} style={{ color: 'var(--text-muted)' }} />}
                    </Button>
                  )}
                  {can('branches.create') && (
                    <Button variant="ghost" size="sm" onClick={() => openEdit(b)}>
                      <Edit size={14} /> تعديل
                    </Button>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Create/Edit Modal */}
      <Modal open={modal.open} onClose={() => setModal({ open: false })} title={modal.editing ? 'تعديل فرع' : 'فرع جديد'} size="md"
        footer={
          <div className="flex gap-2 justify-end" style={{ width: '100%' }}>
            <Button variant="secondary" onClick={() => setModal({ open: false })}>إلغاء</Button>
            <Button onClick={handleSave} loading={saving}>{modal.editing ? 'تحديث' : 'إنشاء'}</Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div className="grid grid-2 gap-4">
            <div className="form-group">
              <label className="form-label required">اسم الفرع</label>
              <input className="form-input" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} autoFocus />
            </div>
            <div className="form-group">
              <label className="form-label">النوع</label>
              <select className="form-select" value={form.type} onChange={e => setForm(f => ({ ...f, type: e.target.value as BranchType }))}>
                <option value="distribution">توزيع</option>
                <option value="retail">تجزئة</option>
                <option value="warehouse">مخزن</option>
              </select>
            </div>
          </div>
          <div className="grid grid-2 gap-4">
            <div className="form-group">
              <label className="form-label">المحافظة</label>
              <select className="form-select" value={selectedGov} onChange={e => handleGovChange(e.target.value)}>
                <option value="">اختر المحافظة</option>
                {governorates.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label">المدينة</label>
              <select className="form-select" value={form.city_id || ''} onChange={e => setForm(f => ({ ...f, city_id: e.target.value || null }))} disabled={!cities.length}>
                <option value="">اختر المدينة</option>
                {cities.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
            </div>
          </div>
          <div className="grid grid-2 gap-4">
            <div className="form-group">
              <label className="form-label">العنوان</label>
              <input className="form-input" value={form.address || ''} onChange={e => setForm(f => ({ ...f, address: e.target.value }))} />
            </div>
            <div className="form-group">
              <label className="form-label">الهاتف</label>
              <input className="form-input" dir="ltr" value={form.phone || ''} onChange={e => setForm(f => ({ ...f, phone: e.target.value }))} />
            </div>
          </div>
          <div className="form-group">
            <label className="form-label">المدير المسؤول</label>
            <select className="form-select" value={form.manager_id || ''} onChange={e => setForm(f => ({ ...f, manager_id: e.target.value || null }))}>
              <option value="">بدون مدير</option>
              {profiles.map(p => <option key={p.id} value={p.id}>{p.full_name}</option>)}
            </select>
          </div>
        </div>
      </Modal>

      <ConfirmDialog
        open={!!confirmTarget}
        title={confirmTarget?.is_active ? 'تعطيل الفرع' : 'تفعيل الفرع'}
        message={`هل تريد ${confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'} الفرع "${confirmTarget?.name}"؟`}
        variant={confirmTarget?.is_active ? 'danger' : 'info'}
        confirmText={confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'}
        onConfirm={executeToggle}
        onCancel={() => setConfirmTarget(null)}
      />
    </div>
  )
}
