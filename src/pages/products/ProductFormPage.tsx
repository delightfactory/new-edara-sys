import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { ArrowRight, Save, Loader2 } from 'lucide-react'
import { getProduct, createProduct, updateProduct, getCategories, getBrands, getUnits, getProductUnits, saveProductUnits } from '@/lib/services/products'
import { useAuthStore } from '@/stores/auth-store'
import type { Product, ProductInput, ProductCategory, Brand, Unit, ProductUnit } from '@/lib/types/master-data'

export default function ProductFormPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const canViewCosts = can('finance.view_costs')
  const isEdit = !!id

  const [loading, setLoading] = useState(isEdit)
  const [saving, setSaving] = useState(false)
  const [categories, setCategories] = useState<ProductCategory[]>([])
  const [brands, setBrands] = useState<Brand[]>([])
  const [units, setUnits] = useState<Unit[]>([])
  const [productUnits, setProductUnits] = useState<{ unit_id: string; conversion_factor: number; selling_price: number | null; is_purchase_unit: boolean; is_sales_unit: boolean }[]>([])

  const [form, setForm] = useState<ProductInput>({
    sku: '',
    name: '',
    barcode: '',
    category_id: null,
    brand_id: null,
    base_unit_id: '',
    selling_price: 0,
    cost_price: 0,
    tax_rate: 14,
    description: '',
    image_url: '',
    is_active: true,
    min_stock_level: 0,
  })

  useEffect(() => {
    const load = async () => {
      const [cats, brds, uts] = await Promise.all([getCategories(), getBrands(), getUnits()])
      setCategories(cats)
      setBrands(brds)
      setUnits(uts)
      if (id) {
        try {
          const p = await getProduct(id)
          setForm({
            sku: p.sku, name: p.name, barcode: p.barcode || '',
            category_id: p.category_id, brand_id: p.brand_id, base_unit_id: p.base_unit_id,
            selling_price: p.selling_price, cost_price: p.cost_price, tax_rate: p.tax_rate,
            description: p.description || '', image_url: p.image_url || '',
            is_active: p.is_active, min_stock_level: p.min_stock_level,
          })
          const pUnits = await getProductUnits(id)
          setProductUnits(pUnits.map(u => ({
            unit_id: u.unit_id, conversion_factor: u.conversion_factor,
            selling_price: u.selling_price, is_purchase_unit: u.is_purchase_unit, is_sales_unit: u.is_sales_unit,
          })))
        } catch { toast.error('فشل تحميل بيانات المنتج') }
      }
      setLoading(false)
    }
    load()
  }, [id])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.name.trim() || !form.sku.trim() || !form.base_unit_id) {
      toast.error('يرجى ملء الحقول المطلوبة')
      return
    }
    setSaving(true)
    try {
      const data = isEdit ? await updateProduct(id!, form) : await createProduct(form)
      // Save product units
      if (productUnits.length > 0) {
        await saveProductUnits(data.id, productUnits)
      }
      toast.success(isEdit ? 'تم تحديث المنتج' : 'تم إنشاء المنتج')
      navigate('/products')
    } catch (err: any) {
      toast.error(err?.message || 'فشلت العملية')
    } finally { setSaving(false) }
  }

  const updateForm = (key: string, value: any) => setForm(f => ({ ...f, [key]: value }))

  const addUnit = () => setProductUnits(prev => [...prev, { unit_id: '', conversion_factor: 1, selling_price: null, is_purchase_unit: false, is_sales_unit: true }])
  const removeUnit = (i: number) => setProductUnits(prev => prev.filter((_, idx) => idx !== i))
  const updateUnit = (i: number, key: string, val: any) => setProductUnits(prev => prev.map((u, idx) => idx === i ? { ...u, [key]: val } : u))

  if (loading) return (
    <div className="page-container animate-enter">
      <div style={{ padding: 'var(--space-6)' }}>
        {[1,2,3].map(i => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 'var(--space-4)' }} />)}
      </div>
    </div>
  )

  return (
    <div className="page-container animate-enter">
      <div className="page-header">
        <div className="page-header-info">
          <button className="btn btn-ghost btn-sm" onClick={() => navigate('/products')} style={{ marginBottom: 'var(--space-2)' }}>
            <ArrowRight size={14} /> العودة للمنتجات
          </button>
          <h1 className="page-title">{isEdit ? 'تعديل المنتج' : 'إضافة منتج جديد'}</h1>
        </div>
      </div>

      <form onSubmit={handleSubmit}>
        {/* Basic Info */}
        <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-4)' }}>
          <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-5)' }}>البيانات الأساسية</h2>
          <div className="grid grid-2 gap-4">
            <div className="form-group">
              <label className="form-label required">اسم المنتج</label>
              <input className="form-input" value={form.name} onChange={e => updateForm('name', e.target.value)} placeholder="اسم المنتج" autoFocus />
            </div>
            <div className="form-group">
              <label className="form-label required">كود المنتج (SKU)</label>
              <input className="form-input" dir="ltr" value={form.sku} onChange={e => updateForm('sku', e.target.value)} placeholder="PRD-001" />
            </div>
            <div className="form-group">
              <label className="form-label">الباركود</label>
              <input className="form-input" dir="ltr" value={form.barcode || ''} onChange={e => updateForm('barcode', e.target.value)} placeholder="6221234567890" />
            </div>
            <div className="form-group">
              <label className="form-label required">الوحدة الأساسية</label>
              <select className="form-select" value={form.base_unit_id} onChange={e => updateForm('base_unit_id', e.target.value)}>
                <option value="">اختر الوحدة</option>
                {units.map(u => <option key={u.id} value={u.id}>{u.name} ({u.symbol})</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label">التصنيف</label>
              <select className="form-select" value={form.category_id || ''} onChange={e => updateForm('category_id', e.target.value || null)}>
                <option value="">بدون تصنيف</option>
                {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label">العلامة التجارية</label>
              <select className="form-select" value={form.brand_id || ''} onChange={e => updateForm('brand_id', e.target.value || null)}>
                <option value="">بدون علامة</option>
                {brands.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
            </div>
          </div>
          <div className="form-group" style={{ marginTop: 'var(--space-4)' }}>
            <label className="form-label">الوصف</label>
            <textarea className="form-textarea" rows={3} value={form.description || ''} onChange={e => updateForm('description', e.target.value)} placeholder="وصف المنتج..." />
          </div>
        </div>

        {/* Pricing */}
        <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-4)' }}>
          <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-5)' }}>التسعير</h2>
          <div className="grid grid-3 gap-4">
            <div className="form-group">
              <label className="form-label required">سعر البيع</label>
              <input type="number" className="form-input" dir="ltr" min={0} step="0.01"
                value={form.selling_price} onChange={e => updateForm('selling_price', +e.target.value)} />
            </div>
            {canViewCosts && (
              <div className="form-group">
                <label className="form-label required">سعر التكلفة</label>
                <input type="number" className="form-input" dir="ltr" min={0} step="0.01"
                  value={form.cost_price} onChange={e => updateForm('cost_price', +e.target.value)} />
              </div>
            )}
            <div className="form-group">
              <label className="form-label">نسبة الضريبة %</label>
              <input type="number" className="form-input" dir="ltr" min={0} max={100}
                value={form.tax_rate} onChange={e => updateForm('tax_rate', +e.target.value)} />
            </div>
            <div className="form-group">
              <label className="form-label">حد المخزون الأدنى</label>
              <input type="number" className="form-input" dir="ltr" min={0}
                value={form.min_stock_level} onChange={e => updateForm('min_stock_level', +e.target.value)} />
            </div>
          </div>
        </div>

        {/* Product Units */}
        <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-4)' }}>
          <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-5)' }}>
            <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>وحدات إضافية</h2>
            <button type="button" className="btn btn-secondary btn-sm" onClick={addUnit}>+ إضافة وحدة</button>
          </div>
          {productUnits.length === 0 ? (
            <p style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)', textAlign: 'center', padding: 'var(--space-4)' }}>
              لا توجد وحدات إضافية — يمكنك إضافة وحدات مثل كرتون أو باكت
            </p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
              {productUnits.map((pu, i) => (
                <div key={i} className="edara-card" style={{ padding: 'var(--space-3)', background: 'var(--bg-surface-2)' }}>
                  <div className="grid grid-4 gap-3" style={{ alignItems: 'end' }}>
                    <div className="form-group">
                      <label className="form-label">الوحدة</label>
                      <select className="form-select" value={pu.unit_id} onChange={e => updateUnit(i, 'unit_id', e.target.value)}>
                        <option value="">اختر</option>
                        {units.map(u => <option key={u.id} value={u.id}>{u.name}</option>)}
                      </select>
                    </div>
                    <div className="form-group">
                      <label className="form-label">معامل التحويل</label>
                      <input type="number" className="form-input" dir="ltr" min={1} value={pu.conversion_factor}
                        onChange={e => updateUnit(i, 'conversion_factor', +e.target.value)} />
                    </div>
                    <div className="form-group">
                      <label className="form-label">سعر البيع</label>
                      <input type="number" className="form-input" dir="ltr" min={0} step="0.01"
                        value={pu.selling_price ?? ''} onChange={e => updateUnit(i, 'selling_price', e.target.value ? +e.target.value : null)} />
                    </div>
                    <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
                      <label style={{ fontSize: 'var(--text-xs)', display: 'flex', alignItems: 'center', gap: 4 }}>
                        <input type="checkbox" checked={pu.is_sales_unit} onChange={e => updateUnit(i, 'is_sales_unit', e.target.checked)} /> بيع
                      </label>
                      <label style={{ fontSize: 'var(--text-xs)', display: 'flex', alignItems: 'center', gap: 4 }}>
                        <input type="checkbox" checked={pu.is_purchase_unit} onChange={e => updateUnit(i, 'is_purchase_unit', e.target.checked)} /> شراء
                      </label>
                      <button type="button" className="btn btn-danger btn-sm" onClick={() => removeUnit(i)}>✕</button>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Submit */}
        <div className="flex justify-between" style={{ paddingTop: 'var(--space-4)' }}>
          <button type="button" className="btn btn-secondary" onClick={() => navigate('/products')}>إلغاء</button>
          <button type="submit" className="btn btn-primary btn-lg" disabled={saving}>
            {saving ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />}
            {saving ? 'جاري الحفظ...' : isEdit ? 'تحديث المنتج' : 'حفظ المنتج'}
          </button>
        </div>
      </form>
    </div>
  )
}
