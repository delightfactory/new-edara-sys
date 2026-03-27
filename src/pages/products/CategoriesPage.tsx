import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { FolderTree, Plus, Edit, Loader2 } from 'lucide-react'
import { getCategories, buildCategoryTree, createCategory, updateCategory } from '@/lib/services/products'
import type { ProductCategory } from '@/lib/types/master-data'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'

export default function CategoriesPage() {
  const [categories, setCategories] = useState<ProductCategory[]>([])
  const [tree, setTree] = useState<ProductCategory[]>([])
  const [loading, setLoading] = useState(true)
  const [modal, setModal] = useState<{ open: boolean; editing?: ProductCategory }>({ open: false })
  const [form, setForm] = useState({ name: '', parent_id: '' as string | null, icon: '', sort_order: 0 })
  const [saving, setSaving] = useState(false)

  const load = async () => {
    setLoading(true)
    try {
      const cats = await getCategories()
      setCategories(cats)
      setTree(buildCategoryTree(cats))
    } catch { toast.error('فشل تحميل التصنيفات') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [])

  const openCreate = (parentId?: string) => {
    setForm({ name: '', parent_id: parentId || null, icon: '', sort_order: 0 })
    setModal({ open: true })
  }

  const openEdit = (cat: ProductCategory) => {
    setForm({ name: cat.name, parent_id: cat.parent_id, icon: cat.icon || '', sort_order: cat.sort_order })
    setModal({ open: true, editing: cat })
  }

  const handleSave = async () => {
    if (!form.name.trim()) { toast.error('يرجى إدخال اسم التصنيف'); return }
    setSaving(true)
    try {
      const payload = { name: form.name, parent_id: form.parent_id || null, icon: form.icon || undefined, sort_order: form.sort_order }
      if (modal.editing) {
        await updateCategory(modal.editing.id, payload)
        toast.success('تم تحديث التصنيف')
      } else {
        await createCategory(payload)
        toast.success('تم إنشاء التصنيف')
      }
      setModal({ open: false })
      load()
    } catch { toast.error('فشلت العملية') }
    finally { setSaving(false) }
  }

  const CategoryNode = ({ cat, depth = 0 }: { cat: ProductCategory; depth?: number }) => (
    <div>
      <div
        className="flex items-center justify-between"
        style={{
          padding: 'var(--space-3) var(--space-4)',
          paddingRight: `calc(var(--space-4) + ${depth * 24}px)`,
          borderBottom: '1px solid var(--divider)',
          transition: 'background 0.15s',
          cursor: 'default',
          minHeight: 52, // generous touch target
        }}
        onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
        onMouseLeave={e => (e.currentTarget.style.background = '')}
      >
        <div className="flex items-center gap-3">
          {cat.icon && <span style={{ fontSize: 'var(--text-lg)' }}>{cat.icon}</span>}
          <div>
            <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{cat.name}</div>
            {cat.children && cat.children.length > 0 && (
              <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{cat.children.length} تصنيف فرعي</span>
            )}
          </div>
          <span className={`badge ${cat.is_active ? 'badge-success' : 'badge-danger'}`} style={{ marginRight: 'var(--space-2)' }}>
            {cat.is_active ? 'نشط' : 'معطل'}
          </span>
        </div>
        <div className="flex gap-1">
          <button className="btn btn-ghost btn-sm" title="إضافة تصنيف فرعي" onClick={() => openCreate(cat.id)}>
            <Plus size={14} />
          </button>
          <button className="btn btn-ghost btn-sm" title="تعديل" onClick={() => openEdit(cat)}>
            <Edit size={14} />
          </button>
        </div>
      </div>
      {cat.children?.map(child => <CategoryNode key={child.id} cat={child} depth={depth + 1} />)}
    </div>
  )

  return (
    <div className="page-container animate-enter">
      <div className="page-header">
        <div className="page-header-info">
          <h1 className="page-title">التصنيفات</h1>
          <p className="page-subtitle">{loading ? '...' : `${categories.length} تصنيف`}</p>
        </div>
        <div className="page-actions">
          <button className="btn btn-primary" onClick={() => openCreate()}>
            <Plus size={16} /> إضافة تصنيف
          </button>
        </div>
      </div>

      <div className="edara-card">
        {loading ? (
          <div style={{ padding: 'var(--space-6)' }}>
            {[1,2,3,4].map(i => <div key={i} className="skeleton skeleton-row" />)}
          </div>
        ) : tree.length === 0 ? (
          <div className="empty-state">
            <FolderTree size={48} className="empty-state-icon" />
            <p className="empty-state-title">لا يوجد تصنيفات</p>
            <p className="empty-state-text">أضف التصنيفات لتنظيم المنتجات</p>
            <button className="btn btn-primary" onClick={() => openCreate()}>
              <Plus size={16} /> إضافة أول تصنيف
            </button>
          </div>
        ) : (
          tree.map(cat => <CategoryNode key={cat.id} cat={cat} />)
        )}
      </div>

      {/* ── Bottom-sheet form (ResponsiveModal) ── */}
      <ResponsiveModal
        open={modal.open}
        onClose={() => setModal({ open: false })}
        title={modal.editing ? 'تعديل التصنيف' : 'تصنيف جديد'}
      >
        <div className="flex-col gap-4" style={{ display: 'flex' }}>
          <div className="form-group">
            <label className="form-label required">اسم التصنيف</label>
            <input className="form-input" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} autoFocus />
          </div>
          <div className="form-group">
            <label className="form-label">التصنيف الأب</label>
            <select className="form-select" value={form.parent_id || ''} onChange={e => setForm(f => ({ ...f, parent_id: e.target.value || null }))}>
              <option value="">بدون (تصنيف رئيسي)</option>
              {categories.filter(c => c.id !== modal.editing?.id).map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </div>
          <div className="grid grid-2 gap-4">
            <div className="form-group">
              <label className="form-label">أيقونة (Emoji)</label>
              <input className="form-input" value={form.icon} onChange={e => setForm(f => ({ ...f, icon: e.target.value }))} placeholder="📦" />
            </div>
            <div className="form-group">
              <label className="form-label">الترتيب</label>
              <input type="number" className="form-input" value={form.sort_order} onChange={e => setForm(f => ({ ...f, sort_order: +e.target.value }))} />
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, paddingTop: 4 }}>
            <Button onClick={handleSave} loading={saving} style={{ width: '100%', justifyContent: 'center' }}>
              {modal.editing ? 'تحديث' : 'إنشاء'}
            </Button>
            <Button variant="ghost" onClick={() => setModal({ open: false })} style={{ width: '100%', justifyContent: 'center' }}>
              إلغاء
            </Button>
          </div>
        </div>
      </ResponsiveModal>
    </div>
  )
}
