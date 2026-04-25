import { useState, useEffect, useCallback } from 'react'
import { toast } from 'sonner'
import { Plus, Edit, Trash2, Tags, Loader2, LinkIcon, Unlink, ToggleLeft, ToggleRight, Star, Save, X } from 'lucide-react'
import {
  getPriceLists, createPriceList, updatePriceList,
  getPriceListItems, addPriceListItem, deletePriceListItem,
  updatePriceListItem,
  getPriceListAssignments, assignPriceList, unassignPriceList,
} from '@/lib/services/price-lists'
import { getProducts, getProductUnits } from '@/lib/services/products'
import { getGovernorates, getCities } from '@/lib/services/geography'
import { useAuthStore } from '@/stores/auth-store'
import AsyncCombobox from '@/components/ui/AsyncCombobox'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import type { PriceList, PriceListItem, PriceListAssignment, Product, Governorate, City } from '@/lib/types/master-data'

// ── نوع خاص بالمنتج المختار في نموذج الإضافة ──────────────
interface SelectedProduct {
  id: string
  name: string
  sku: string
  base_unit?: { id: string; name: string; symbol: string } | null
}

// ── حالة التعديل المؤقت على بند موجود ────────────────────
interface EditingItem {
  id: string
  price: number
  min_qty: number
  max_qty: number | null
}

export default function PriceListsPage() {
  const can = useAuthStore(s => s.can)
  const [lists, setLists] = useState<PriceList[]>([])
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState<PriceList | null>(null)
  const [tab, setTab] = useState<'items' | 'assignments'>('items')

  // Items state
  const [items, setItems] = useState<PriceListItem[]>([])
  const [itemsLoading, setItemsLoading] = useState(false)
  const [selectedProduct, setSelectedProduct] = useState<SelectedProduct | null>(null)
  const [selectedProductUnits, setSelectedProductUnits] = useState<{ id: string; name: string; symbol: string }[]>([])
  const [itemForm, setItemForm] = useState({ unit_id: '', price: 0, min_qty: 1, max_qty: '' as string | number })

  // Edit item state
  const [editingItem, setEditingItem] = useState<EditingItem | null>(null)
  const [editSaving, setEditSaving] = useState(false)

  // Assignments state
  const [assignments, setAssignments] = useState<PriceListAssignment[]>([])
  const [governorates, setGovernorates] = useState<Governorate[]>([])
  const [cities, setCities] = useState<City[]>([])
  const [assignForm, setAssignForm] = useState({ entity_type: 'governorate' as 'customer' | 'city' | 'governorate', entity_id: '' })

  // Modal (create/edit price list)
  const [modal, setModal] = useState<{ open: boolean; editing?: PriceList }>({ open: false })
  const [form, setForm] = useState({ name: '', description: '', valid_from: '' as string | null, valid_to: '' as string | null, is_default: false, is_active: true })
  const [saving, setSaving] = useState(false)

  // ── جلب القوائم ─────────────────────────────────────────
  const load = async () => {
    setLoading(true)
    try { setLists(await getPriceLists()) }
    catch { toast.error('فشل تحميل قوائم الأسعار') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [])

  // ── اختيار قائمة — تحميل بنودها فقط (بلا منتجات) ───────
  const selectList = async (list: PriceList) => {
    setSelected(list)
    setTab('items')
    setItemsLoading(true)
    // Finding 5: reset form+edit state on list switch
    setSelectedProduct(null)
    setSelectedProductUnits([])
    setItemForm({ unit_id: '', price: 0, min_qty: 1, max_qty: '' })
    setEditingItem(null)
    try {
      const itemsRes = await getPriceListItems(list.id)
      setItems(itemsRes.data)
    } catch { toast.error('فشل تحميل البنود') }
    finally { setItemsLoading(false) }
  }

  // ── بحث المنتجات عبر AsyncCombobox ──────────────────────
  const loadProductOptions = useCallback(async (search: string) => {
    const res = await getProducts({ search: search || undefined, pageSize: 20, isActive: true })
    return res.data.map(p => ({
      value: p.id,
      label: p.name,
      sublabel: p.sku,
      // نحتفظ بكامل كائن المنتج داخل الخيار للوصول لـ base_unit
      _product: p,
    }))
  }, [])

  // ── عند اختيار منتج من Combobox ─────────────────────────
  const handleProductSelect = async (productId: string | null, option?: any) => {
    if (!productId || !option) {
      setSelectedProduct(null)
      setSelectedProductUnits([])
      setItemForm(f => ({ ...f, unit_id: '' }))
      return
    }

    const product = option._product as Product
    // Finding 6: capture id before await
    const requestedId = product.id
    setSelectedProduct({ id: product.id, name: product.name, sku: product.sku, base_unit: product.base_unit })
    setSelectedProductUnits([])
    setItemForm(f => ({ ...f, unit_id: '' }))

    try {
      const pUnits = await getProductUnits(requestedId)
      const unitsList: { id: string; name: string; symbol: string }[] = []
      if (product.base_unit) unitsList.push({ id: product.base_unit.id, name: product.base_unit.name, symbol: product.base_unit.symbol })
      pUnits.forEach(pu => {
        if (pu.unit && !unitsList.some(u => u.id === pu.unit!.id)) {
          unitsList.push({ id: pu.unit!.id, name: pu.unit!.name, symbol: pu.unit!.symbol })
        }
      })
      // Finding 6: only apply if product unchanged
      setSelectedProduct(prev => {
        if (!prev || prev.id !== requestedId) return prev
        setSelectedProductUnits(unitsList)
        if (unitsList.length === 1) setItemForm(f => ({ ...f, unit_id: unitsList[0].id }))
        return prev
      })
    } catch { /* تجاهل أخطاء تحميل الوحدات */ }
  }

  // ── إضافة بند جديد ───────────────────────────────────────
  const handleAddItem = async () => {
    if (!selected || !selectedProduct?.id || !itemForm.unit_id) { toast.error('اختر المنتج والوحدة'); return }
    // Finding 3: تحقق صارم من السعر + نطاق الكميات
    if (!Number.isFinite(itemForm.price) || itemForm.price <= 0) { toast.error('يرجى إدخال سعر صحيح أكبر من صفر'); return }
    const minQty = Math.max(1, Math.round(itemForm.min_qty || 1))
    const maxQty = itemForm.max_qty ? Number(itemForm.max_qty) : null
    if (!Number.isFinite(minQty) || minQty < 1) { toast.error('الحد الأدنى يجب أن يكون 1 على الأقل'); return }
    if (maxQty !== null && (!Number.isFinite(maxQty) || maxQty < minQty)) {
      toast.error('الحد الأقصى يجب أن يكون أكبر من أو يساوي الحد الأدنى'); return
    }
    try {
      await addPriceListItem(selected.id, {
        product_id: selectedProduct.id,
        unit_id: itemForm.unit_id,
        price: itemForm.price,
        min_qty: minQty,   // Finding 4: القيمة المُطهّرة المتحقق منها أعلاه
        max_qty: maxQty,   // Finding 4: وليس إعادة حساب من itemForm
      })
      toast.success('تمت الإضافة')
      setSelectedProduct(null)
      setSelectedProductUnits([])
      setItemForm({ unit_id: '', price: 0, min_qty: 1, max_qty: '' })
      selectList(selected)
    } catch (e: any) { toast.error(e?.message || 'فشلت الإضافة') }
  }

  // ── حذف بند ──────────────────────────────────────────────
  const handleDeleteItem = async (id: string) => {
    if (!confirm('حذف هذا البند؟')) return
    try { await deletePriceListItem(id); toast.success('تم الحذف'); selectList(selected!) }
    catch { toast.error('فشل الحذف') }
  }

  // ── بدء تعديل بند ────────────────────────────────────────
  const startEditItem = (item: PriceListItem) => {
    setEditingItem({ id: item.id, price: item.price, min_qty: item.min_qty, max_qty: item.max_qty ?? null })
  }

  // ── حفظ تعديل البند ──────────────────────────────────────
  const handleUpdateItem = async () => {
    if (!editingItem) return
    // Finding 3: strict price + qty range validation
    // Finding 3: strict price + qty range validation
    if (!Number.isFinite(editingItem.price) || editingItem.price <= 0) {
      toast.error('\u064a\u0631\u062c\u0649 \u0625\u062f\u062e\u0627\u0644 \u0633\u0639\u0631 \u0635\u062d\u064a\u062d \u0623\u0643\u0628\u0631 \u0645\u0646 \u0635\u0641\u0631'); return
    }
    if (!Number.isFinite(editingItem.min_qty) || editingItem.min_qty < 1) {
      toast.error('\u0627\u0644\u062d\u062f \u0627\u0644\u0623\u062f\u0646\u0649 \u064a\u062c\u0628 \u0623\u0646 \u064a\u0643\u0648\u0646 1 \u0639\u0644\u0649 \u0627\u0644\u0623\u0642\u0644'); return
    }
    if (editingItem.max_qty !== null && (!Number.isFinite(editingItem.max_qty) || editingItem.max_qty < editingItem.min_qty)) {
      toast.error('الحد الأقصى يجب أن يكون رقماً صحيحاً أكبر من أو يساوي الحد الأدنى'); return
    }
    setEditSaving(true)
    try {
      const updated = await updatePriceListItem(editingItem.id, {
        price: editingItem.price,
        min_qty: editingItem.min_qty,
        max_qty: editingItem.max_qty,
      })
      setItems(prev => prev.map(item => item.id === updated.id ? updated : item))
      toast.success('تم التحديث')
      setEditingItem(null)
    } catch (e: any) { toast.error(e?.message || 'فشل التحديث') }
    finally { setEditSaving(false) }
  }

  // ── الدوال الأخرى (بدون تغيير) ───────────────────────────
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

  const getEntityName = (a: PriceListAssignment): string => {
    if (a.entity_type === 'governorate') return governorates.find(g => g.id === a.entity_id)?.name || a.entity_id.substring(0, 8) + '...'
    if (a.entity_type === 'city') return cities.find(c => c.id === a.entity_id)?.name || a.entity_id.substring(0, 8) + '...'
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
        {/* ── قائمة القوائم الجانبية ─────────────────────────── */}
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
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
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
                <div className="flex items-center gap-1" style={{ flexShrink: 0, marginInlineStart: 'var(--space-2)' }}>
                  {l.is_default && <span className="badge badge-primary" style={{ fontSize: 'var(--text-xs)' }}>افتراضية</span>}
                  <span className={`badge ${l.is_active ? 'badge-success' : 'badge-danger'}`} style={{ fontSize: 'var(--text-xs)' }}>{l.is_active ? 'نشط' : 'معطل'}</span>
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* ── لوحة التفاصيل ──────────────────────────────────── */}
        {selected && (
          <div className="edara-card" style={{ overflow: 'hidden' }}>
            {/* رأس القائمة المحددة */}
            <div style={{ padding: 'var(--space-4)', borderBottom: '1px solid var(--border-primary)' }}>
              <div className="flex items-center justify-between" style={{ flexWrap: 'wrap', gap: 'var(--space-2)' }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{selected.name}</h2>
                  {selected.description && <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', margin: 'var(--space-1) 0 0' }}>{selected.description}</p>}
                </div>
                {can('price_lists.update') && (
                  <div className="flex items-center gap-2">
                    <button className={`btn btn-sm ${selected.is_default ? 'btn-primary' : 'btn-ghost'}`}
                      title={selected.is_default ? 'قائمة افتراضية' : 'تعيين كافتراضية'}
                      onClick={() => handleSetDefault(selected)}>
                      <Star size={14} fill={selected.is_default ? 'currentColor' : 'none'} />
                    </button>
                    <button className="btn btn-ghost btn-sm" onClick={() => handleToggleActive(selected)}
                      title={selected.is_active ? 'تعطيل' : 'تفعيل'}>
                      {selected.is_active
                        ? <ToggleRight size={18} style={{ color: 'var(--color-success)' }} />
                        : <ToggleLeft size={18} />}
                    </button>
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
              <div className="flex gap-2" style={{ marginTop: 'var(--space-2)', flexWrap: 'wrap' }}>
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

            {/* ══ تبويب البنود ══════════════════════════════════ */}
            {tab === 'items' && (
              <div style={{ padding: 'var(--space-4)' }}>

                {/* ── نموذج إضافة بند محسّن ──────────────────── */}
                {can('price_lists.update') && (
                  <div style={{ marginBottom: 'var(--space-4)', padding: 'var(--space-4)', background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-lg)', border: '1px solid var(--border-secondary)' }}>
                    <div style={{ fontSize: 'var(--text-xs)', fontWeight: 700, color: 'var(--text-muted)', marginBottom: 'var(--space-3)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                      إضافة بند جديد
                    </div>

                    {/* السطر 1: بحث المنتج (عرض كامل) */}
                    <div style={{ marginBottom: 'var(--space-3)' }}>
                      <AsyncCombobox
                        placeholder="ابحث عن منتج باسمه أو SKU..."
                        value={selectedProduct?.id ?? null}
                        onChange={handleProductSelect}
                        loadOptions={loadProductOptions}
                        noOptionsText="لا توجد منتجات مطابقة"
                      />
                    </div>

                    {/* السطر 2: الوحدة + السعر */}
                    <div className="pli-form-row" style={{ marginBottom: 'var(--space-3)' }}>
                      <select
                        className="form-select"
                        value={itemForm.unit_id}
                        onChange={e => setItemForm(f => ({ ...f, unit_id: e.target.value }))}
                        disabled={!selectedProductUnits.length}
                      >
                        <option value="">الوحدة</option>
                        {selectedProductUnits.map(u => <option key={u.id} value={u.id}>{u.name} ({u.symbol})</option>)}
                      </select>
                      <input
                        type="number"
                        className="form-input"
                        dir="ltr"
                        placeholder="السعر"
                        value={itemForm.price || ''}
                        onChange={e => setItemForm(f => ({ ...f, price: +e.target.value }))}
                      />
                    </div>

                    {/* السطر 3: الحد الأدنى + الأقصى + زر الإضافة */}
                    <div className="pli-form-row">
                      <div className="form-group" style={{ marginBottom: 0 }}>
                        <label className="form-label" style={{ fontSize: 'var(--text-xs)' }}>الحد الأدنى للكمية</label>
                        <input type="number" className="form-input" dir="ltr" min={0} step={1}
                          value={itemForm.min_qty}
                          onChange={e => setItemForm(f => ({ ...f, min_qty: +e.target.value }))} />
                      </div>
                      <div className="form-group" style={{ marginBottom: 0 }}>
                        <label className="form-label" style={{ fontSize: 'var(--text-xs)' }}>الحد الأقصى للكمية</label>
                        <input type="number" className="form-input" dir="ltr" min={0} step={1}
                          placeholder="بلا حد"
                          value={itemForm.max_qty}
                          onChange={e => setItemForm(f => ({ ...f, max_qty: e.target.value }))} />
                      </div>
                      <div style={{ display: 'flex', alignItems: 'flex-end' }}>
                        <button className="btn btn-primary" onClick={handleAddItem} style={{ whiteSpace: 'nowrap', width: '100%', justifyContent: 'center' }}>
                          <Plus size={14} /> إضافة
                        </button>
                      </div>
                    </div>
                  </div>
                )}

                {/* ── قائمة البنود ───────────────────────────── */}
                {itemsLoading ? (
                  <div>{[1,2,3].map(i => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 8 }} />)}</div>
                ) : items.length === 0 ? (
                  <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا يوجد بنود في هذه القائمة</p>
                ) : (
                  <>
                    {/* جدول الديسكتوب */}
                    <table className="data-table pli-desktop-table">
                      <thead>
                        <tr>
                          <th>المنتج</th>
                          <th>الوحدة</th>
                          <th>السعر</th>
                          <th>الأدنى</th>
                          <th>الأقصى</th>
                          {can('price_lists.update') && <th style={{ width: 90 }}></th>}
                        </tr>
                      </thead>
                      <tbody>
                        {items.map(item => (
                            // ── صف العرض (التعديل يتم عبر ResponsiveModal) ──
                            <tr key={item.id} style={editingItem?.id === item.id ? { background: 'var(--bg-active)' } : undefined}>
                              <td>
                                <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{item.product?.name || '—'}</div>
                                <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }} dir="ltr">{item.product?.sku}</div>
                              </td>
                              <td>{item.unit?.name || '—'} <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>({item.unit?.symbol})</span></td>
                              <td style={{ fontWeight: 700, color: 'var(--color-primary)' }}>{formatPrice(item.price)}</td>
                              <td>{item.min_qty}</td>
                              <td>{item.max_qty ?? '∞'}</td>
                              {can('price_lists.update') && (
                                <td>
                                  <div style={{ display: 'flex', gap: 4 }}>
                                    <button className="btn btn-ghost btn-sm" onClick={() => startEditItem(item)} title="تعديل">
                                      <Edit size={12} />
                                    </button>
                                    <button className="btn btn-danger btn-sm" onClick={() => handleDeleteItem(item.id)} title="حذف">
                                      <Trash2 size={12} />
                                    </button>
                                  </div>
                                </td>
                              )}
                            </tr>
                          )
                        )}
                      </tbody>
                    </table>

                    {/* بطاقات الموبايل */}
                    <div className="pli-mobile-cards">
                      {items.map(item => (
                        <div key={item.id} style={{
                          padding: 'var(--space-3)',
                          borderRadius: 'var(--radius-md)',
                          border: '1px solid var(--border-secondary)',
                          background: 'var(--bg-surface)',
                          marginBottom: 'var(--space-2)',
                        }}>
                          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 6 }}>
                            <div style={{ flex: 1, minWidth: 0 }}>
                              <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                {item.product?.name || '—'}
                              </div>
                              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }} dir="ltr">
                                {item.product?.sku}
                              </div>
                            </div>
                            {can('price_lists.update') && (
                              <div style={{ display: 'flex', gap: 6, marginInlineStart: 'var(--space-2)', flexShrink: 0 }}>
                                <button className="btn btn-ghost btn-sm" onClick={() => startEditItem(item)} title="تعديل">
                                  <Edit size={14} />
                                </button>
                                <button className="btn btn-danger btn-sm" onClick={() => handleDeleteItem(item.id)} title="حذف">
                                  <Trash2 size={14} />
                                </button>
                              </div>
                            )}
                          </div>
                          <div style={{ display: 'flex', gap: 'var(--space-3)', flexWrap: 'wrap', fontSize: 'var(--text-xs)' }}>
                            <span style={{ color: 'var(--text-muted)' }}>
                              الوحدة: <strong style={{ color: 'var(--text-primary)' }}>{item.unit?.name} ({item.unit?.symbol})</strong>
                            </span>
                            <span style={{ color: 'var(--text-muted)' }}>
                              السعر: <strong style={{ color: 'var(--color-primary)', fontSize: 'var(--text-sm)' }}>{formatPrice(item.price)}</strong>
                            </span>
                            <span style={{ color: 'var(--text-muted)' }}>
                              الكمية: <strong style={{ color: 'var(--text-secondary)' }}>{item.min_qty} — {item.max_qty ?? '∞'}</strong>
                            </span>
                          </div>
                        </div>
                      ))}
                    </div>
                  </>
                )}
              </div>
            )}

            {/* ══ تبويب الربط (بدون تغيير) ═══════════════════ */}
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
                          <td><button className="btn btn-danger btn-sm" onClick={() => handleUnassign(a.id)}><Unlink size={12} /></button></td>
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

      {/* ══ مودال إنشاء/تعديل القائمة ═══════════════════════ */}
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

      {/* ══ مودال تعديل البند (موبايل: bottom sheet، ديسكتوب: modal) ══ */}
      <ResponsiveModal
        open={!!editingItem}
        onClose={() => setEditingItem(null)}
        title="تعديل بيانات البند"
        size="sm"
        footer={
          <>
            <button className="btn btn-secondary" onClick={() => setEditingItem(null)}>إلغاء</button>
            <button className="btn btn-primary" onClick={handleUpdateItem} disabled={editSaving}>
              {editSaving ? <Loader2 size={14} className="animate-spin" /> : <Save size={14} />}
              حفظ
            </button>
          </>
        }
      >
        {editingItem && (() => {
          const item = items.find(i => i.id === editingItem.id)
          return (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
              {item && (
                <div style={{ padding: 'var(--space-3)', background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-md)' }}>
                  <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)' }}>{item.product?.name}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }} dir="ltr">{item.product?.sku}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginTop: 2 }}>
                    الوحدة: {item.unit?.name} ({item.unit?.symbol})
                  </div>
                </div>
              )}
              <div className="form-group">
                <label className="form-label required">السعر</label>
                <input type="number" className="form-input" dir="ltr"
                  value={editingItem.price}
                  onChange={e => setEditingItem(p => p ? { ...p, price: +e.target.value } : null)} />
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
                <div className="form-group">
                  <label className="form-label">الحد الأدنى</label>
                  <input type="number" className="form-input" dir="ltr" min={0}
                    value={editingItem.min_qty}
                    onChange={e => setEditingItem(p => p ? { ...p, min_qty: +e.target.value } : null)} />
                </div>
                <div className="form-group">
                  <label className="form-label">الحد الأقصى</label>
                  <input type="number" className="form-input" dir="ltr" min={0}
                    placeholder="بلا حد"
                    value={editingItem.max_qty ?? ''}
                    onChange={e => setEditingItem(p => p ? { ...p, max_qty: e.target.value ? +e.target.value : null } : null)} />
                </div>
              </div>
            </div>
          )
        })()}
      </ResponsiveModal>

      {/* ══ CSS محلي للصفحة ═════════════════════════════════ */}
      <style>{`
        /* نموذج الإضافة — grid responsive */
        .pli-form-row {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-3);
        }

        /* جدول البنود — ديسكتوب فقط */
        .pli-desktop-table { display: table; width: 100%; }

        /* بطاقات الموبايل — مخفية على الديسكتوب */
        .pli-mobile-cards { display: none; }

        @media (max-width: 768px) {
          /* نموذج الإضافة: عمود واحد */
          .pli-form-row {
            grid-template-columns: 1fr;
          }

          /* إخفاء الجدول على الموبايل */
          .pli-desktop-table { display: none !important; }

          /* إظهار البطاقات على الموبايل */
          .pli-mobile-cards { display: block; }
        }
      `}</style>
    </div>
  )
}
