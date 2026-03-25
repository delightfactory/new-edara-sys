import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { Package, Plus, Edit, Loader2, Trash2 } from 'lucide-react'
import { getBundles, createBundle, updateBundle } from '@/lib/services/products'
import { getProducts, getProductUnits } from '@/lib/services/products'
import { useAuthStore } from '@/stores/auth-store'
import type { ProductBundle, Product } from '@/lib/types/master-data'

export default function BundlesPage() {
  const can = useAuthStore(s => s.can)
  const [bundles, setBundles] = useState<ProductBundle[]>([])
  const [loading, setLoading] = useState(true)
  const [products, setProducts] = useState<Product[]>([])
  const [productUnitsMap, setProductUnitsMap] = useState<Record<string, { id: string; name: string; symbol: string }[]>>({})

  // Modal
  const [modal, setModal] = useState<{ open: boolean; editing?: ProductBundle }>({ open: false })
  const [form, setForm] = useState({ name: '', sku: '', price: 0 })
  const [items, setItems] = useState<{ product_id: string; unit_id: string; quantity: number }[]>([])
  const [saving, setSaving] = useState(false)

  const load = async () => {
    setLoading(true)
    try { setBundles(await getBundles()) }
    catch { toast.error('فشل تحميل الباقات') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [])

  const ensureRefs = async () => {
    if (!products.length) {
      const p = await getProducts({ pageSize: 500 })
      setProducts(p.data)
    }
  }

  const openCreate = async () => {
    await ensureRefs()
    setForm({ name: '', sku: '', price: 0 })
    setItems([{ product_id: '', unit_id: '', quantity: 1 }])
    setModal({ open: true })
  }

  const openEdit = async (b: ProductBundle) => {
    await ensureRefs()
    setForm({ name: b.name, sku: b.sku || '', price: b.price })
    setItems(b.items?.map(i => ({ product_id: i.product_id, unit_id: i.unit_id, quantity: i.quantity })) || [{ product_id: '', unit_id: '', quantity: 1 }])
    setModal({ open: true, editing: b })
  }

  const addItem = () => setItems(i => [...i, { product_id: '', unit_id: '', quantity: 1 }])
  const removeItem = (idx: number) => setItems(i => i.filter((_, j) => j !== idx))
  const updateItem = (idx: number, key: string, val: any) => setItems(i => i.map((item, j) => j === idx ? { ...item, [key]: val } : item))

  const handleProductChange = async (idx: number, productId: string) => {
    setItems(i => i.map((item, j) => j === idx ? { ...item, product_id: productId, unit_id: '' } : item))
    if (productId && !productUnitsMap[productId]) {
      try {
        const pUnits = await getProductUnits(productId)
        const product = products.find(p => p.id === productId)
        const unitsList: { id: string; name: string; symbol: string }[] = []
        if (product?.base_unit) unitsList.push({ id: product.base_unit.id, name: product.base_unit.name, symbol: product.base_unit.symbol })
        pUnits.forEach(pu => { if (pu.unit && !unitsList.some(u => u.id === pu.unit!.id)) unitsList.push({ id: pu.unit!.id, name: pu.unit!.name, symbol: pu.unit!.symbol }) })
        setProductUnitsMap(m => ({ ...m, [productId]: unitsList }))
      } catch {}
    }
  }

  const handleSave = async () => {
    if (!form.name.trim()) { toast.error('يرجى إدخال الاسم'); return }
    const validItems = items.filter(i => i.product_id && i.unit_id && i.quantity > 0)
    if (!validItems.length) { toast.error('يرجى إضافة بنود'); return }

    setSaving(true)
    try {
      if (modal.editing) {
        await updateBundle(modal.editing.id, form, validItems)
        toast.success('تم التحديث')
      } else {
        await createBundle(form, validItems)
        toast.success('تم الإنشاء')
      }
      setModal({ open: false })
      load()
    } catch { toast.error('فشلت العملية') }
    finally { setSaving(false) }
  }

  const toggleActive = async (b: ProductBundle) => {
    try {
      await updateBundle(b.id, { is_active: !b.is_active })
      toast.success(b.is_active ? 'تم التعطيل' : 'تم التفعيل')
      load()
    } catch { toast.error('فشلت العملية') }
  }

  return (
    <div className="page-container animate-enter">
      <div className="page-header">
        <div className="page-header-info">
          <h1 className="page-title">الباقات</h1>
          <p className="page-subtitle">{loading ? '...' : `${bundles.length} باقة`}</p>
        </div>
        {can('products.create') && (
          <div className="page-actions">
            <button className="btn btn-primary" onClick={openCreate}><Plus size={16} /> باقة جديدة</button>
          </div>
        )}
      </div>

      {loading ? (
        <div className="grid grid-3 gap-4">
          {[1,2,3].map(i => <div key={i} className="skeleton" style={{ height: 160, borderRadius: 'var(--radius-lg)' }} />)}
        </div>
      ) : bundles.length === 0 ? (
        <div className="edara-card">
          <div className="empty-state">
            <Package size={48} className="empty-state-icon" />
            <p className="empty-state-title">لا يوجد باقات</p>
            <p className="empty-state-text">أنشئ باقات لتجميع المنتجات بسعر موحد</p>
            <button className="btn btn-primary" onClick={openCreate}><Plus size={16} /> إنشاء أول باقة</button>
          </div>
        </div>
      ) : (
        <div className="grid grid-3 gap-4">
          {bundles.map(b => (
            <div key={b.id} className="edara-card edara-card-interactive" style={{ padding: 'var(--space-5)' }}>
              <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-3)' }}>
                <div>
                  <h3 style={{ fontWeight: 700, fontSize: 'var(--text-sm)' }}>{b.name}</h3>
                  {b.sku && <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }} dir="ltr">{b.sku}</p>}
                </div>
                <span className={`badge ${b.is_active ? 'badge-success' : 'badge-danger'}`}>{b.is_active ? 'نشط' : 'معطل'}</span>
              </div>
              <div style={{ fontSize: 'var(--text-lg)', fontWeight: 700, color: 'var(--color-primary)', marginBottom: 'var(--space-2)' }}>
                {b.price.toLocaleString('ar-EG', { minimumFractionDigits: 2 })} ج.م
              </div>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 'var(--space-3)' }}>
                {b.items?.length || 0} منتج
              </div>
              {b.items && b.items.length > 0 && (
                <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginBottom: 'var(--space-3)' }}>
                  {b.items.slice(0, 3).map((it: any, i: number) => (
                    <div key={i}>• {it.product?.name || it.product_id} × {it.quantity} {it.unit?.symbol || ''}</div>
                  ))}
                  {b.items.length > 3 && <div>... +{b.items.length - 3} أخرى</div>}
                </div>
              )}
              <div className="flex gap-2" style={{ borderTop: '1px solid var(--divider)', paddingTop: 'var(--space-3)' }}>
                {can('products.create') && (
                  <>
                    <button className="btn btn-ghost btn-sm" onClick={() => openEdit(b)}><Edit size={14} /> تعديل</button>
                    <button className="btn btn-ghost btn-sm" onClick={() => toggleActive(b)}>{b.is_active ? 'تعطيل' : 'تفعيل'}</button>
                  </>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Create/Edit Modal */}
      {modal.open && (
        <div className="modal-overlay" onClick={() => setModal({ open: false })}>
          <div className="modal-box modal-lg" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <span className="modal-title">{modal.editing ? 'تعديل باقة' : 'باقة جديدة'}</span>
              <button className="btn btn-ghost btn-icon" onClick={() => setModal({ open: false })}>✕</button>
            </div>
            <div className="modal-body">
              <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
                <div className="grid grid-3 gap-4">
                  <div className="form-group">
                    <label className="form-label required">الاسم</label>
                    <input className="form-input" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} autoFocus />
                  </div>
                  <div className="form-group">
                    <label className="form-label">SKU</label>
                    <input className="form-input" dir="ltr" value={form.sku} onChange={e => setForm(f => ({ ...f, sku: e.target.value }))} />
                  </div>
                  <div className="form-group">
                    <label className="form-label required">السعر</label>
                    <input type="number" className="form-input" dir="ltr" min={0} step={0.01} value={form.price} onChange={e => setForm(f => ({ ...f, price: +e.target.value }))} />
                  </div>
                </div>
                <h3 style={{ fontWeight: 700, fontSize: 'var(--text-sm)' }}>منتجات الباقة</h3>
                {items.map((item, idx) => (
                  <div key={idx} className="grid gap-4" style={{ gridTemplateColumns: '2fr 1fr 1fr auto', alignItems: 'end' }}>
                    <div className="form-group">
                      <label className="form-label">المنتج</label>
                      <select className="form-select" value={item.product_id} onChange={e => handleProductChange(idx, e.target.value)}>
                        <option value="">اختر</option>
                        {products.map(p => <option key={p.id} value={p.id}>{p.name} ({p.sku})</option>)}
                      </select>
                    </div>
                    <div className="form-group">
                      <label className="form-label">الوحدة</label>
                      <select className="form-select" value={item.unit_id} onChange={e => updateItem(idx, 'unit_id', e.target.value)} disabled={!productUnitsMap[item.product_id]?.length}>
                        <option value="">اختر</option>
                        {(productUnitsMap[item.product_id] || []).map(u => <option key={u.id} value={u.id}>{u.name} ({u.symbol})</option>)}
                      </select>
                    </div>
                    <div className="form-group">
                      <label className="form-label">الكمية</label>
                      <input type="number" className="form-input" dir="ltr" min={1} value={item.quantity} onChange={e => updateItem(idx, 'quantity', +e.target.value)} />
                    </div>
                    <button className="btn btn-danger btn-sm" style={{ marginBottom: 'var(--space-1)' }} disabled={items.length <= 1} onClick={() => removeItem(idx)}><Trash2 size={12} /></button>
                  </div>
                ))}
                <button className="btn btn-secondary btn-sm" onClick={addItem} style={{ alignSelf: 'flex-start' }}><Plus size={14} /> إضافة منتج</button>
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
