import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { Plus, Edit, Trash2, Tags, Loader2, LinkIcon, Unlink, ToggleLeft, ToggleRight, Star } from 'lucide-react'
import { getPriceLists, createPriceList, updatePriceList, getPriceListItems, addPriceListItem, deletePriceListItem, getPriceListAssignments, assignPriceList, unassignPriceList } from '@/lib/services/price-lists'
import { getProducts, getProductUnits } from '@/lib/services/products'
import { getGovernorates, getCities } from '@/lib/services/geography'
import { useAuthStore } from '@/stores/auth-store'
import type { PriceList, PriceListItem, PriceListAssignment, Product, Governorate, City } from '@/lib/types/master-data'

export default function PriceListsPage() {
  const can = useAuthStore(s => s.can)
  const [lists, setLists] = useState<PriceList[]>([])
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState<PriceList | null>(null)
  const [tab, setTab] = useState<'items' | 'assignments'>('items')

  // Items state
  const [items, setItems] = useState<PriceListItem[]>([])
  const [itemsLoading, setItemsLoading] = useState(false)
  const [products, setProducts] = useState<Product[]>([])
  const [selectedProductUnits, setSelectedProductUnits] = useState<{ id: string; name: string; symbol: string }[]>([])
  const [itemForm, setItemForm] = useState({ product_id: '', unit_id: '', price: 0, min_qty: 1, max_qty: '' as string | number })

  // Assignments state
  const [assignments, setAssignments] = useState<PriceListAssignment[]>([])
  const [governorates, setGovernorates] = useState<Governorate[]>([])
  const [cities, setCities] = useState<City[]>([])
  const [assignForm, setAssignForm] = useState({ entity_type: 'governorate' as 'customer' | 'city' | 'governorate', entity_id: '' })

  // Modal
  const [modal, setModal] = useState<{ open: boolean; editing?: PriceList }>({ open: false })
  const [form, setForm] = useState({ name: '', description: '', valid_from: '' as string | null, valid_to: '' as string | null, is_default: false, is_active: true })
  const [saving, setSaving] = useState(false)

  const load = async () => {
    setLoading(true)
    try { setLists(await getPriceLists()) }
    catch { toast.error('فشل تحميل قوائم الأسعار') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [])

  const selectList = async (list: PriceList) => {
    setSelected(list)
    setTab('items')
    setItemsLoading(true)
    try {
      const [itemsRes, prods] = await Promise.all([
        getPriceListItems(list.id),
        products.length ? Promise.resolve({ data: products }) : getProducts({ pageSize: 500 }),
      ])
      setItems(itemsRes.data)
      if (!products.length) setProducts(prods.data)
    } catch { toast.error('فشل تحميل البنود') }
    finally { setItemsLoading(false) }
  }

  const loadAssignments = async () => {
    if (!selected) return
    try {
      const [asgn, govs, cts] = await Promise.all([
        getPriceListAssignments(selected.id),
        governorates.length ? Promise.resolve(governorates) : getGovernorates(),
        cities.length ? Promise.resolve(cities) : getCities(),
      ])
      setAssignments(asgn)
      if (!governorates.length) setGovernorates(govs)
      if (!cities.length) setCities(cts)
    } catch { toast.error('فشل تحميل الربط') }
  }

  useEffect(() => { if (selected && tab === 'assignments') loadAssignments() }, [tab, selected])

  const handleSaveList = async () => {
    if (!form.name.trim()) { toast.error('يرجى إدخال اسم القائمة'); return }
    setSaving(true)
    const payload = {
      name: form.name,
      description: form.description,
      valid_from: form.valid_from || null,
      valid_to: form.valid_to || null,
      is_default: form.is_default,
      is_active: form.is_active,
    }
    try {
      if (modal.editing) {
        const updated = await updatePriceList(modal.editing.id, payload)
        toast.success('تم التحديث')
        if (selected?.id === modal.editing.id) setSelected(updated)
      } else {
        await createPriceList(payload)
        toast.success('تم الإنشاء')
      }
      setModal({ open: false })
      load()
    } catch (e: any) { toast.error(e?.message || 'فشلت العملية') }
    finally { setSaving(false) }
  }

  const handleProductSelect = async (pid: string) => {
    setItemForm(f => ({ ...f, product_id: pid, unit_id: '' }))
    setSelectedProductUnits([])
    if (pid) {
      try {
        const pUnits = await getProductUnits(pid)
        const product = products.find(p => p.id === pid)
        const unitsList: { id: string; name: string; symbol: string }[] = []
        if (product?.base_unit) unitsList.push({ id: product.base_unit.id, name: product.base_unit.name, symbol: product.base_unit.symbol })
        pUnits.forEach(pu => { if (pu.unit && !unitsList.some(u => u.id === pu.unit!.id)) unitsList.push({ id: pu.unit!.id, name: pu.unit!.name, symbol: pu.unit!.symbol }) })
        setSelectedProductUnits(unitsList)
        if (unitsList.length === 1) setItemForm(f => ({ ...f, unit_id: unitsList[0].id }))
      } catch {}
    }
  }

  const handleAddItem = async () => {
    if (!selected || !itemForm.product_id || !itemForm.unit_id) { toast.error('اختر المنتج والوحدة'); return }
    if (itemForm.price <= 0) { toast.error('يرجى إدخال سعر صحيح'); return }
    try {
      await addPriceListItem(selected.id, {
        product_id: itemForm.product_id,
        unit_id: itemForm.unit_id,
        price: itemForm.price,
        min_qty: itemForm.min_qty || 1,
        max_qty: itemForm.max_qty ? Number(itemForm.max_qty) : null,
      })
      toast.success('تمت الإضافة')
      setItemForm({ product_id: '', unit_id: '', price: 0, min_qty: 1, max_qty: '' })
      setSelectedProductUnits([])
      selectList(selected)
    } catch (e: any) { toast.error(e?.message || 'فشلت الإضافة') }
  }

  const handleDeleteItem = async (id: string) => {
    if (!confirm('حذف هذا البند؟')) return
    try { await deletePriceListItem(id); toast.success('تم الحذف'); selectList(selected!) }
    catch { toast.error('فشل الحذف') }
  }

  const handleToggleActive = async (list: PriceList) => {
    try {
      const updated = await updatePriceList(list.id, { is_active: !list.is_active })
      toast.success(list.is_active ? 'تم تعطيل القائمة' : 'تم تفعيل القائمة')
      if (selected?.id === list.id) setSelected(updated)
      load()
    } catch (e: any) { toast.error(e?.message || 'فشلت العملية') }
  }

  const handleSetDefault = async (list: PriceList) => {
    if (list.is_default) return
    if (!confirm(`تعيين "${list.name}" كقائمة افتراضية؟ سيُلغى الافتراضي الحالي.`)) return
    try {
      // أولاً إلغاء الافتراضي الحالي
      const currentDefault = lists.find(l => l.is_default)
      if (currentDefault) await updatePriceList(currentDefault.id, { is_default: false })
      const updated = await updatePriceList(list.id, { is_default: true })
      toast.success('تم تعيينها كافتراضية')
      if (selected?.id === list.id) setSelected(updated)
      load()
    } catch (e: any) { toast.error(e?.message || 'فشلت العملية') }
  }

  const handleAssign = async () => {
    if (!selected || !assignForm.entity_id) { toast.error('اختر الكيان'); return }
    try {
      await assignPriceList(selected.id, assignForm.entity_type, assignForm.entity_id)
      toast.success('تم الربط')
      setAssignForm(f => ({ ...f, entity_id: '' }))
      loadAssignments()
    } catch (e: any) { toast.error(e?.message || 'فشل الربط') }
  }

  const handleUnassign = async (id: string) => {
    try { await unassignPriceList(id); toast.success('تم إلغاء الربط'); loadAssignments() }
    catch { toast.error('فشلت العملية') }
  }

  // دالة مساعدة لعرض اسم الكيان المربوط
  const getEntityName = (a: PriceListAssignment): string => {
    if (a.entity_type === 'governorate') {
      return governorates.find(g => g.id === a.entity_id)?.name || a.entity_id.substring(0, 8) + '...'
    }
    if (a.entity_type === 'city') {
      return cities.find(c => c.id === a.entity_id)?.name || a.entity_id.substring(0, 8) + '...'
    }
    return a.entity_id.substring(0, 8) + '...'
  }

  const formatPrice = (v: number) => v.toLocaleString('en-US', { minimumFractionDigits: 2 })

  const isExpired = (l: PriceList) => l.valid_to && new Date(l.valid_to) < new Date()

  return (
    <div className="page-container animate-enter">
      <div className="page-header">
        <div className="page-header-info">
          <h1 className="page-title">قوائم الأسعار</h1>
          <p className="page-subtitle">{loading ? '...' : `${lists.length} قائمة`}</p>
        </div>
        {can('price_lists.update') && (
          <div className="page-actions">
            <button className="btn btn-primary" onClick={() => { setForm({ name: '', description: '', valid_from: '', valid_to: '', is_default: false, is_active: true }); setModal({ open: true }) }}>
              <Plus size={16} /> قائمة جديدة
            </button>
          </div>
        )}
      </div>

      <div className="detail-grid-sidebar">
        {/* Price Lists sidebar */}
        <div className="edara-card">
          {loading ? (
            <div style={{ padding: 'var(--space-4)' }}>
              {[1,2,3].map(i => <div key={i} className="skeleton skeleton-row" />)}
            </div>
          ) : lists.length === 0 ? (
            <div className="empty-state">
              <Tags size={40} className="empty-state-icon" />
              <p className="empty-state-title">لا يوجد قوائم</p>
            </div>
          ) : lists.map(l => (
            <div
              key={l.id}
              onClick={() => selectList(l)}
              style={{
                padding: 'var(--space-4)',
                borderBottom: '1px solid var(--divider)',
                cursor: 'pointer',
                background: selected?.id === l.id ? 'var(--bg-active)' : '',
                opacity: l.is_active ? 1 : 0.6,
                transition: 'background 0.15s',
              }}
              onMouseEnter={e => { if (selected?.id !== l.id) e.currentTarget.style.background = 'var(--bg-hover)' }}
              onMouseLeave={e => { if (selected?.id !== l.id) e.currentTarget.style.background = '' }}
            >
              <div className="flex items-center justify-between">
                <div style={{ flex: 1 }}>
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>
                    {l.name}
                  </div>
                  {l.description && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{l.description}</div>}
                  {(l.valid_from || l.valid_to) && (
                    <div style={{ fontSize: 'var(--text-xs)', color: isExpired(l) ? 'var(--color-danger)' : 'var(--text-muted)', marginTop: 2 }}>
                      📅 {l.valid_from ? new Date(l.valid_from).toLocaleDateString('ar-EG-u-nu-latn') : '∞'} — {l.valid_to ? new Date(l.valid_to).toLocaleDateString('ar-EG-u-nu-latn') : '∞'}
                      {isExpired(l) && ' (منتهية)'}
                    </div>
                  )}
                </div>
                <div className="flex items-center gap-1" style={{ flexShrink: 0 }}>
                  {l.is_default && <span className="badge badge-primary" style={{ fontSize: 'var(--text-xs)' }}>افتراضية</span>}
                  <span className={`badge ${l.is_active ? 'badge-success' : 'badge-danger'}`} style={{ fontSize: 'var(--text-xs)' }}>{l.is_active ? 'نشط' : 'معطل'}</span>
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* Detail panel */}
        {selected && (
          <div className="edara-card" style={{ overflow: 'auto' }}>
            <div style={{ padding: 'var(--space-4)', borderBottom: '1px solid var(--border-primary)' }}>
              <div className="flex items-center justify-between">
                <div>
                  <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>{selected.name}</h2>
                  {selected.description && <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', margin: 'var(--space-1) 0 0' }}>{selected.description}</p>}
                </div>
                {can('price_lists.update') && (
                  <div className="flex items-center gap-2">
                    {/* زر الافتراضية */}
                    <button className={`btn btn-sm ${selected.is_default ? 'btn-primary' : 'btn-ghost'}`}
                      title={selected.is_default ? 'قائمة افتراضية' : 'تعيين كافتراضية'}
                      onClick={() => handleSetDefault(selected)}>
                      <Star size={14} fill={selected.is_default ? 'currentColor' : 'none'} />
                    </button>
                    {/* زر تفعيل/تعطيل */}
                    <button className="btn btn-ghost btn-sm" onClick={() => handleToggleActive(selected)}
                      title={selected.is_active ? 'تعطيل' : 'تفعيل'}>
                      {selected.is_active
                        ? <ToggleRight size={18} style={{ color: 'var(--color-success)' }} />
                        : <ToggleLeft size={18} />}
                    </button>
                    {/* زر تعديل */}
                    <button className="btn btn-ghost btn-sm" onClick={() => {
                      setForm({
                        name: selected.name,
                        description: selected.description || '',
                        valid_from: selected.valid_from || '',
                        valid_to: selected.valid_to || '',
                        is_default: selected.is_default,
                        is_active: selected.is_active,
                      })
                      setModal({ open: true, editing: selected })
                    }}>
                      <Edit size={14} /> تعديل
                    </button>
                  </div>
                )}
              </div>
              {/* معلومات الحالة */}
              <div className="flex gap-2" style={{ marginTop: 'var(--space-2)' }}>
                <span className={`badge ${selected.is_active ? 'badge-success' : 'badge-danger'}`}>{selected.is_active ? 'نشطة' : 'معطلة'}</span>
                {selected.is_default && <span className="badge badge-primary">افتراضية</span>}
                {isExpired(selected) && <span className="badge badge-danger">منتهية الصلاحية</span>}
                {(selected.valid_from || selected.valid_to) && (
                  <span className="badge badge-neutral">
                    📅 {selected.valid_from ? new Date(selected.valid_from).toLocaleDateString('ar-EG-u-nu-latn') : '∞'} — {selected.valid_to ? new Date(selected.valid_to).toLocaleDateString('ar-EG-u-nu-latn') : '∞'}
                  </span>
                )}
              </div>
            </div>

            {/* Tabs */}
            <div className="tabs">
              <button className={`tab ${tab === 'items' ? 'active' : ''}`} onClick={() => setTab('items')}>البنود ({items.length})</button>
              <button className={`tab ${tab === 'assignments' ? 'active' : ''}`} onClick={() => setTab('assignments')}>الربط ({assignments.length})</button>
            </div>

            {tab === 'items' && (
              <div style={{ padding: 'var(--space-4)' }}>
                {/* Add item form */}
                {can('price_lists.update') && (
                  <div style={{ marginBottom: 'var(--space-4)', padding: 'var(--space-3)', background: 'var(--bg-secondary)', borderRadius: 'var(--radius-lg)' }}>
                    <div className="flex gap-3" style={{ flexWrap: 'wrap', marginBottom: 'var(--space-3)' }}>
                      <select className="form-select" style={{ flex: 2, minWidth: 160 }} value={itemForm.product_id} onChange={e => handleProductSelect(e.target.value)}>
                        <option value="">اختر المنتج</option>
                        {products.map(p => <option key={p.id} value={p.id}>{p.name} ({p.sku})</option>)}
                      </select>
                      <select className="form-select" style={{ flex: 1, minWidth: 100 }} value={itemForm.unit_id} onChange={e => setItemForm(f => ({ ...f, unit_id: e.target.value }))} disabled={!selectedProductUnits.length}>
                        <option value="">الوحدة</option>
                        {selectedProductUnits.map(u => <option key={u.id} value={u.id}>{u.name} ({u.symbol})</option>)}
                      </select>
                      <input type="number" className="form-input" dir="ltr" placeholder="السعر" style={{ flex: 1, minWidth: 80 }} value={itemForm.price || ''} onChange={e => setItemForm(f => ({ ...f, price: +e.target.value }))} />
                    </div>
                    <div className="flex gap-3 items-end" style={{ flexWrap: 'wrap' }}>
                      <div className="form-group" style={{ flex: 1, minWidth: 80, marginBottom: 0 }}>
                        <label className="form-label" style={{ fontSize: 'var(--text-xs)' }}>الحد الأدنى (كمية)</label>
                        <input type="number" className="form-input" dir="ltr" min={0} step={1} value={itemForm.min_qty} onChange={e => setItemForm(f => ({ ...f, min_qty: +e.target.value }))} />
                      </div>
                      <div className="form-group" style={{ flex: 1, minWidth: 80, marginBottom: 0 }}>
                        <label className="form-label" style={{ fontSize: 'var(--text-xs)' }}>الحد الأقصى (كمية)</label>
                        <input type="number" className="form-input" dir="ltr" min={0} step={1} placeholder="بلا حد" value={itemForm.max_qty} onChange={e => setItemForm(f => ({ ...f, max_qty: e.target.value }))} />
                      </div>
                      <button className="btn btn-primary btn-sm" onClick={handleAddItem} style={{ flexShrink: 0 }}><Plus size={14} /> إضافة</button>
                    </div>
                  </div>
                )}

                {itemsLoading ? (
                  <div>{[1,2,3].map(i => <div key={i} className="skeleton skeleton-row" />)}</div>
                ) : items.length === 0 ? (
                  <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا يوجد بنود في هذه القائمة</p>
                ) : (
                  <table className="data-table">
                    <thead><tr><th>المنتج</th><th>الوحدة</th><th>السعر</th><th className="hide-mobile">الحد الأدنى</th><th className="hide-mobile">الحد الأقصى</th><th style={{ width: 60 }}></th></tr></thead>
                    <tbody>
                      {items.map(item => (
                        <tr key={item.id}>
                          <td>
                            <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{item.product?.name || '—'}</div>
                            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }} dir="ltr">{item.product?.sku}</div>
                          </td>
                          <td>{item.unit?.name || '—'} <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>({item.unit?.symbol})</span></td>
                          <td style={{ fontWeight: 700, color: 'var(--color-primary)' }}>{formatPrice(item.price)}</td>
                          <td className="hide-mobile">{item.min_qty}</td>
                          <td className="hide-mobile">{item.max_qty ?? '∞'}</td>
                          <td>
                            {can('price_lists.update') && (
                              <button className="btn btn-danger btn-sm" onClick={() => handleDeleteItem(item.id)}><Trash2 size={12} /></button>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
            )}

            {tab === 'assignments' && (
              <div style={{ padding: 'var(--space-4)' }}>
                {can('price_lists.update') && (
                  <div className="flex gap-3" style={{ marginBottom: 'var(--space-4)', flexWrap: 'wrap' }}>
                    <select className="form-select" style={{ width: 140 }} value={assignForm.entity_type}
                      onChange={e => setAssignForm({ entity_type: e.target.value as any, entity_id: '' })}>
                      <option value="governorate">محافظة</option>
                      <option value="city">مدينة</option>
                    </select>
                    <select className="form-select" style={{ flex: 1, minWidth: 160 }} value={assignForm.entity_id}
                      onChange={e => setAssignForm(f => ({ ...f, entity_id: e.target.value }))}>
                      <option value="">اختر...</option>
                      {assignForm.entity_type === 'governorate'
                        ? governorates.map(g => <option key={g.id} value={g.id}>{g.name}</option>)
                        : cities.map(c => <option key={c.id} value={c.id}>{c.name}</option>)
                      }
                    </select>
                    <button className="btn btn-primary btn-sm" onClick={handleAssign}><LinkIcon size={14} /> ربط</button>
                  </div>
                )}

                {assignments.length === 0 ? (
                  <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا يوجد ربط لهذه القائمة</p>
                ) : (
                  <table className="data-table">
                    <thead><tr><th>النوع</th><th>الاسم</th><th style={{ width: 60 }}></th></tr></thead>
                    <tbody>
                      {assignments.map(a => (
                        <tr key={a.id}>
                          <td><span className={`badge badge-${a.entity_type === 'governorate' ? 'info' : a.entity_type === 'city' ? 'primary' : 'warning'}`}>
                            {a.entity_type === 'governorate' ? 'محافظة' : a.entity_type === 'city' ? 'مدينة' : 'عميل'}
                          </span></td>
                          <td style={{ fontWeight: 600 }}>{getEntityName(a)}</td>
                          <td>
                            <button className="btn btn-danger btn-sm" onClick={() => handleUnassign(a.id)}><Unlink size={12} /></button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Create/Edit Modal */}
      {modal.open && (
        <div className="modal-overlay" onClick={() => setModal({ open: false })}>
          <div className="modal-box modal-sm" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <span className="modal-title">{modal.editing ? 'تعديل قائمة' : 'قائمة أسعار جديدة'}</span>
              <button className="btn btn-ghost btn-icon" onClick={() => setModal({ open: false })}>✕</button>
            </div>
            <div className="modal-body">
              <div className="flex-col gap-4" style={{ display: 'flex' }}>
                <div className="form-group">
                  <label className="form-label required">اسم القائمة</label>
                  <input className="form-input" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} autoFocus />
                </div>
                <div className="grid grid-2 gap-4">
                  <div className="form-group">
                    <label className="form-label">صالحة من</label>
                    <input type="date" className="form-input" dir="ltr" value={form.valid_from || ''} onChange={e => setForm(f => ({ ...f, valid_from: e.target.value || null }))} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">صالحة حتى</label>
                    <input type="date" className="form-input" dir="ltr" value={form.valid_to || ''} onChange={e => setForm(f => ({ ...f, valid_to: e.target.value || null }))} />
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label">الوصف</label>
                  <textarea className="form-textarea" value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} />
                </div>
                <div className="flex gap-4">
                  <label style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', cursor: 'pointer', fontSize: 'var(--text-sm)' }}>
                    <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} />
                    نشطة
                  </label>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', cursor: 'pointer', fontSize: 'var(--text-sm)' }}>
                    <input type="checkbox" checked={form.is_default} onChange={e => setForm(f => ({ ...f, is_default: e.target.checked }))} />
                    افتراضية
                  </label>
                </div>
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setModal({ open: false })}>إلغاء</button>
              <button className="btn btn-primary" onClick={handleSaveList} disabled={saving}>
                {saving && <Loader2 size={14} className="animate-spin" />}
                {modal.editing ? 'تحديث' : 'إنشاء'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
