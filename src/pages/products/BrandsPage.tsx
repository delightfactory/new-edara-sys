import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { Plus, Tag, Edit, Loader2, ToggleLeft, ToggleRight } from 'lucide-react'
import { getBrands, createBrand, updateBrand } from '@/lib/services/products'
import { useAuthStore } from '@/stores/auth-store'
import type { Brand } from '@/lib/types/master-data'

export default function BrandsPage() {
  const can = useAuthStore(s => s.can)
  const [brands, setBrands] = useState<Brand[]>([])
  const [loading, setLoading] = useState(true)
  const [modal, setModal] = useState<{ open: boolean; editing?: Brand }>({ open: false })
  const [form, setForm] = useState({ name: '', logo_url: '' })
  const [saving, setSaving] = useState(false)

  const load = async () => {
    setLoading(true)
    try { setBrands(await getBrands()) }
    catch { toast.error('فشل تحميل العلامات التجارية') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [])

  const openCreate = () => { setForm({ name: '', logo_url: '' }); setModal({ open: true }) }
  const openEdit = (b: Brand) => { setForm({ name: b.name, logo_url: b.logo_url || '' }); setModal({ open: true, editing: b }) }

  const handleSave = async () => {
    if (!form.name.trim()) { toast.error('يرجى إدخال الاسم'); return }
    setSaving(true)
    try {
      if (modal.editing) {
        await updateBrand(modal.editing.id, form)
        toast.success('تم التحديث')
      } else {
        await createBrand(form)
        toast.success('تم الإنشاء')
      }
      setModal({ open: false })
      load()
    } catch { toast.error('فشلت العملية') }
    finally { setSaving(false) }
  }

  const toggleActive = async (b: Brand) => {
    try {
      await updateBrand(b.id, { is_active: !b.is_active })
      toast.success(b.is_active ? 'تم التعطيل' : 'تم التفعيل')
      load()
    } catch { toast.error('فشلت العملية') }
  }

  return (
    <div className="page-container animate-enter">
      <div className="page-header">
        <div className="page-header-info">
          <h1 className="page-title">العلامات التجارية</h1>
          <p className="page-subtitle">{loading ? '...' : `${brands.length} علامة`}</p>
        </div>
        {can('products.create') && (
          <div className="page-actions">
            <button className="btn btn-primary" onClick={openCreate}><Plus size={16} /> إضافة علامة</button>
          </div>
        )}
      </div>

      {loading ? (
        <div className="grid grid-4 gap-4">
          {[1,2,3,4].map(i => <div key={i} className="skeleton" style={{ height: 100, borderRadius: 'var(--radius-lg)' }} />)}
        </div>
      ) : brands.length === 0 ? (
        <div className="edara-card">
          <div className="empty-state">
            <Tag size={48} className="empty-state-icon" />
            <p className="empty-state-title">لا يوجد علامات تجارية</p>
            <button className="btn btn-primary" onClick={openCreate}><Plus size={16} /> إضافة أول علامة</button>
          </div>
        </div>
      ) : (
        <div className="grid grid-4 gap-4">
          {brands.map(b => (
            <div key={b.id} className="edara-card edara-card-interactive" style={{ padding: 'var(--space-4)', textAlign: 'center' }}>
              <div style={{ width: 48, height: 48, borderRadius: 'var(--radius-full)', background: 'var(--color-primary-light)', margin: '0 auto var(--space-3)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                {b.logo_url ? (
                  <img src={b.logo_url} alt={b.name} style={{ width: 32, height: 32, borderRadius: '50%', objectFit: 'cover' }} />
                ) : (
                  <Tag size={20} style={{ color: 'var(--color-primary)' }} />
                )}
              </div>
              <h3 style={{ fontWeight: 700, fontSize: 'var(--text-sm)', marginBottom: 'var(--space-2)' }}>{b.name}</h3>
              <span className={`badge ${b.is_active ? 'badge-success' : 'badge-danger'}`} style={{ marginBottom: 'var(--space-3)' }}>{b.is_active ? 'نشط' : 'معطل'}</span>
              <div className="flex gap-1 justify-center" style={{ marginTop: 'var(--space-3)', borderTop: '1px solid var(--divider)', paddingTop: 'var(--space-3)' }}>
                {can('products.create') && (
                  <>
                    <button className="btn btn-ghost btn-sm" onClick={() => openEdit(b)}><Edit size={12} /></button>
                    <button className="btn btn-ghost btn-sm" onClick={() => toggleActive(b)}>
                      {b.is_active ? <ToggleRight size={16} style={{ color: 'var(--color-success)' }} /> : <ToggleLeft size={16} />}
                    </button>
                  </>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {modal.open && (
        <div className="modal-overlay" onClick={() => setModal({ open: false })}>
          <div className="modal-box modal-sm" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <span className="modal-title">{modal.editing ? 'تعديل علامة' : 'علامة جديدة'}</span>
              <button className="btn btn-ghost btn-icon" onClick={() => setModal({ open: false })}>✕</button>
            </div>
            <div className="modal-body">
              <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
                <div className="form-group">
                  <label className="form-label required">الاسم</label>
                  <input className="form-input" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} autoFocus />
                </div>
                <div className="form-group">
                  <label className="form-label">رابط الشعار</label>
                  <input className="form-input" dir="ltr" placeholder="https://..." value={form.logo_url} onChange={e => setForm(f => ({ ...f, logo_url: e.target.value }))} />
                </div>
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setModal({ open: false })}>إلغاء</button>
              <button className="btn btn-primary" onClick={handleSave} disabled={saving}>
                {saving && <Loader2 size={14} className="animate-spin" />} {modal.editing ? 'تحديث' : 'إنشاء'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
