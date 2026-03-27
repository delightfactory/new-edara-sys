import { useState, useEffect, useMemo, useRef, useCallback } from 'react'
import { createPortal } from 'react-dom'
import { useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, Plus, Trash2, Save, ChevronDown, X,
  User, MapPin, Package, Truck, AlertTriangle, Search,
  Calculator,
} from 'lucide-react'
import {
  useWarehouses, useShippingCompanies, useProfiles, useSalesSettings,
} from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { supabase } from '@/lib/supabase/client'
import {
  createSalesOrder, updateSalesOrder, getSalesOrder,
  saveSalesOrderItems, recalcOrderTotals,
} from '@/lib/services/sales'
import { getCustomerBranches } from '@/lib/services/customers'
import { formatNumber } from '@/lib/utils/format'
import type {
  SalesOrderInput, SalesOrderItemInput,
  Product, ProductUnit, Customer, CustomerBranch, DeliveryMethod,
} from '@/lib/types/master-data'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'

// ─────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────

interface LineItem {
  _key: string
  product_id: string
  productName: string
  productSku: string
  unit_id: string
  unitLabel: string
  available_units: ProductUnit[]
  base_unit_id: string
  base_unit_label: string
  conversion_factor: number
  quantity: number
  base_quantity: number
  unit_price: number
  discount_percent: number
  discount_amount: number
  tax_rate: number
  tax_amount: number
  line_total: number
  availableQty: number  // من search_products_with_stock — للتحذير
}

function newLine(): LineItem {
  return {
    _key: crypto.randomUUID(),
    product_id: '', productName: '', productSku: '',
    unit_id: '', unitLabel: '', available_units: [],
    base_unit_id: '', base_unit_label: '',
    conversion_factor: 1, quantity: 1, base_quantity: 1,
    unit_price: 0, discount_percent: 0, discount_amount: 0,
    tax_rate: 0, tax_amount: 0, line_total: 0,
    availableQty: Infinity,
  }
}

function calcLine(l: LineItem): LineItem {
  const sub = Math.round(l.quantity * l.unit_price * 100) / 100
  const discount_amount = Math.round(sub * l.discount_percent / 100 * 100) / 100
  const afterDisc = sub - discount_amount
  const tax_amount = Math.round(afterDisc * l.tax_rate / 100 * 100) / 100
  const line_total = Math.round((afterDisc + tax_amount) * 100) / 100
  const base_quantity = Math.round(l.quantity * l.conversion_factor * 100) / 100
  return { ...l, discount_amount, tax_amount, line_total, base_quantity }
}

// ─────────────────────────────────────────────
// Combobox: reusable autocomplete field
// ─────────────────────────────────────────────

interface ComboItem { id: string; primary: string; secondary?: string; meta?: string }
interface ComboboxProps {
  placeholder: string
  value: string         // display value (not id)
  items: ComboItem[]
  onSearch: (q: string) => void
  onSelect: (item: ComboItem) => void
  onClear?: () => void
  loading?: boolean
  selected?: boolean
  selectedLabel?: string
  required?: boolean
}

function Combobox({ placeholder, value, items, onSearch, onSelect, onClear, selected, selectedLabel, required }: ComboboxProps) {
  const [open, setOpen] = useState(false)
  const [q, setQ] = useState('')
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [])

  const handleInput = (v: string) => {
    setQ(v)
    onSearch(v)
    setOpen(v.length > 0)
  }

  if (selected && selectedLabel) {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '8px 12px',
        background: 'var(--color-primary-light, rgba(37,99,235,0.07))',
        border: '1.5px solid var(--color-primary)',
        borderRadius: 8,
        minHeight: 42,
      }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 600, fontSize: '0.875rem', lineHeight: 1.3, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {selectedLabel}
          </div>
          {value && value !== selectedLabel && (
            <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{value}</div>
          )}
        </div>
        {onClear && (
          <button onClick={onClear} type="button" style={{
            background: 'none', border: 'none', cursor: 'pointer',
            color: 'var(--text-muted)', padding: 4, borderRadius: 4,
            display: 'flex', alignItems: 'center',
            flexShrink: 0,
          }}>
            <X size={14} />
          </button>
        )}
      </div>
    )
  }

  return (
    <div ref={ref} style={{ position: 'relative' }}>
      <div style={{ position: 'relative' }}>
        <Search size={14} style={{
          position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)',
          color: 'var(--text-muted)', pointerEvents: 'none',
        }} />
        <input
          className="form-input"
          style={{ paddingRight: 32 }}
          placeholder={placeholder}
          value={q}
          onChange={e => handleInput(e.target.value)}
          onFocus={() => { if (q.length > 0) setOpen(true) }}
          autoComplete="off"
        />
      </div>

      {open && items.length > 0 && (
        <div style={{
          position: 'absolute', zIndex: 999, top: 'calc(100% + 4px)',
          left: 0, right: 0,
          background: 'var(--bg-surface)',
          border: '1px solid var(--border-color)',
          borderRadius: 10,
          boxShadow: '0 12px 40px rgba(0,0,0,0.15)',
          maxHeight: 280, overflowY: 'auto',
        }}>
          {items.map((item, i) => (
            <div
              key={item.id}
              onMouseDown={e => { e.preventDefault(); onSelect(item); setQ(''); setOpen(false) }}
              style={{
                padding: '10px 14px', cursor: 'pointer',
                borderBottom: i < items.length - 1 ? '1px solid var(--border-color)' : 'none',
                display: 'flex', justifyContent: 'space-between', alignItems: 'center',
              }}
              onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
              onMouseLeave={e => (e.currentTarget.style.background = '')}
            >
              <div style={{ minWidth: 0, flex: 1 }}>
                <div style={{ fontWeight: 600, fontSize: '0.875rem', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{item.primary}</div>
                {item.secondary && <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{item.secondary}</div>}
              </div>
              {item.meta && (
                <div style={{ fontSize: '0.875rem', fontWeight: 700, color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap', marginRight: 12 }}>
                  {item.meta}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ─────────────────────────────────────────────
// Main Form
// ─────────────────────────────────────────────

export default function SalesOrderForm() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const copyFromId = searchParams.get('copyFrom') // نسخ الطلب
  const can = useAuthStore(s => s.can)
  const profile = useAuthStore(s => s.profile)
  const isEdit = !!id

  const { data: warehouses = [] } = useWarehouses({ isActive: true })
  const { data: shippingCos = [] } = useShippingCompanies(true)
  const { data: allProfiles = [] } = useProfiles()
  const { data: settings } = useSalesSettings()

  // فلترة المناديب: يُعرض فقط أصحاب دور sales_rep أو كل الموظفين للمدراء
  // MyProfile.roles هي مصفوفة أدوار — نتحقق باسم الدور
  const isSalesRep = (profile?.roles ?? []).some(r => r.name === 'sales_rep')
  // عرض كل الموظفين في قائمة المناديب (فلترة الدور تحتاج join مع user_roles)
  const reps = allProfiles

  const [saving, setSaving] = useState(false)
  const [formLoading, setFormLoading] = useState(isEdit)

  // Customer
  const [selectedCustomer, setSelectedCustomer] = useState<Customer | null>(null)
  const [customerResults, setCustomerResults] = useState<Customer[]>([])
  const [customerBranches, setCustomerBranches] = useState<CustomerBranch[]>([])

  // Product search per row
  const [productQuery, setProductQuery] = useState('')
  const [productResults, setProductResults] = useState<any[]>([])
  const [activeProductIdx, setActiveProductIdx] = useState<number | null>(null)

  // Lines
  const [lines, setLines] = useState<LineItem[]>([newLine()])

  // Header form
  const [form, setForm] = useState<SalesOrderInput>({
    customer_id: '',
    // إذا المستخدم مندوب مبيعات → يُعيَّن تلقائياً
    rep_id: isSalesRep ? (profile?.id || '') : '',
    branch_id: null,
    order_date: new Date().toISOString().split('T')[0],
    delivery_method: 'direct' as DeliveryMethod,
    warehouse_id: null,
    shipping_company_id: null,
    shipping_cost: 0,
    shipping_on_customer: false,
    delivery_address_id: null,
    notes: null,
  })

  // Permissions
  const canEditPrice = can('sales.orders.edit_price')
  const canOverrideDiscount = can('sales.discounts.override')
  const maxDiscount = settings?.maxDiscountPercent ?? 100
  const minOrder = settings?.minOrderAmount ?? 0

  // ─── Computed totals ───
  const totals = useMemo(() => {
    const subtotal = lines.reduce((s, l) => s + l.quantity * l.unit_price, 0)
    const discount = lines.reduce((s, l) => s + l.discount_amount, 0)
    const tax = lines.reduce((s, l) => s + l.tax_amount, 0)
    const items = lines.reduce((s, l) => s + l.line_total, 0)
    const shipping = form.shipping_on_customer ? (form.shipping_cost || 0) : 0
    return { subtotal, discount, tax, items, shipping, total: items + shipping }
  }, [lines, form.shipping_cost, form.shipping_on_customer])

  const validLines = lines.filter(l => l.product_id && l.quantity > 0)
  const isUnderMin = minOrder > 0 && validLines.length > 0 && totals.total < minOrder

  // ─── Customer search ───
  const searchCustomers = useCallback(async (q: string) => {
    if (q.length < 2) { setCustomerResults([]); return }
    const { data } = await supabase
      .from('customers')
      .select('id, name, code, phone, payment_terms, credit_limit, credit_days')
      .eq('is_active', true)
      .or(`name.ilike.%${q}%,code.ilike.%${q}%,phone.ilike.%${q}%`)
      .limit(10)
    setCustomerResults(data as Customer[] || [])
  }, [])

  const selectCustomer = async (c: Customer) => {
    setSelectedCustomer(c)
    setForm(f => ({ ...f, customer_id: c.id, delivery_address_id: null }))
    setCustomerResults([])
    const branches = await getCustomerBranches(c.id).catch(() => [])
    setCustomerBranches(branches)
    // Auto-select primary branch
    const primary = branches.find(b => b.is_primary)
    if (primary) {
      setForm(f => ({ ...f, delivery_address_id: primary.id }))
    }
  }

  const clearCustomer = () => {
    setSelectedCustomer(null)
    setForm(f => ({ ...f, customer_id: '', delivery_address_id: null }))
    setCustomerBranches([])
    setCustomerResults([])
  }

  // ─── Product search — uses RPC search_products_with_stock ───
  // يستعلم عن الكمية الإجمالية عبر كل المخازن النشطة (بدون تحديد مخزن في مرحلة المسودة)
  const searchProducts = useCallback(async (q: string) => {
    if (q.length < 2) { setProductResults([]); return }
    const { data, error } = await supabase.rpc('search_products_with_stock', {
      p_query: q,
      p_limit: 15,
    })
    if (!error) setProductResults(data || [])
  }, [])

  const selectProduct = (lineIdx: number, p: any) => {
    const taxRate = settings?.taxEnabled ? (p.tax_rate ?? settings?.defaultTaxRate ?? 0) : 0

    // Build units list: base unit first, then all additional units
    const allUnits: ProductUnit[] = []
    if (p.base_unit) {
      allUnits.push({
        id: '__base__', product_id: p.id, unit_id: p.base_unit_id,
        conversion_factor: 1, selling_price: p.selling_price,
        is_purchase_unit: true, is_sales_unit: true, created_at: '',
        unit: p.base_unit,
      })
    }
    for (const pu of (p.product_units || [])) {
      if (pu.unit_id !== p.base_unit_id) allUnits.push(pu)
    }

    const def = allUnits[0]

    setLines(prev => {
      const copy = [...prev]
      copy[lineIdx] = calcLine({
        ...copy[lineIdx],
        product_id: p.id,
        productName: p.name,
        productSku: p.sku,
        unit_id: def?.unit_id || p.base_unit_id,
        unitLabel: def?.unit?.symbol || def?.unit?.name || '',
        available_units: allUnits,
        base_unit_id: p.base_unit_id,
        base_unit_label: p.base_unit?.symbol || p.base_unit?.name || '',
        conversion_factor: def?.conversion_factor || 1,
        unit_price: def?.selling_price ?? p.selling_price ?? 0,
        tax_rate: taxRate,
        // حفظ الكمية المتاحة للتحذير لاحقاً
        availableQty: typeof p.available_qty === 'number' ? p.available_qty : Infinity,
      })
      return copy
    })
    setProductQuery('')
    setProductResults([])
    setActiveProductIdx(null)
  }

  // ─── Line helpers ───
  const updateLine = (idx: number, field: keyof LineItem, value: any) => {
    setLines(prev => {
      const copy = [...prev]
      copy[idx] = calcLine({ ...copy[idx], [field]: value })
      return copy
    })
  }

  const changeUnit = (lineIdx: number, unitId: string) => {
    setLines(prev => {
      const copy = [...prev]
      const line = copy[lineIdx]
      const pu = line.available_units.find(u => u.unit_id === unitId)
      if (!pu) return prev
      copy[lineIdx] = calcLine({
        ...line,
        unit_id: unitId,
        unitLabel: pu.unit?.symbol || pu.unit?.name || '',
        conversion_factor: pu.conversion_factor,
        unit_price: pu.selling_price ?? line.unit_price,
      })
      return copy
    })
  }

  const removeLine = (idx: number) => setLines(p => p.filter((_, i) => i !== idx))
  const addLine = () => setLines(p => [...p, newLine()])

  // ─── Load existing order (edit) ─────────────────────────────────
  useEffect(() => {
    if (!id) return
    ;(async () => {
      try {
        setFormLoading(true)
        const order = await getSalesOrder(id)
        if (order.status !== 'draft') {
          toast.error('لا يمكن تعديل طلب غير مسودة')
          navigate(`/sales/orders/${id}`)
          return
        }
        setForm({
          customer_id: order.customer_id,
          rep_id: order.rep_id,
          branch_id: order.branch_id,
          order_date: order.order_date,
          delivery_method: order.delivery_method,
          warehouse_id: order.warehouse_id,
          shipping_company_id: order.shipping_company_id,
          shipping_cost: order.shipping_cost,
          shipping_on_customer: order.shipping_on_customer,
          delivery_address_id: order.delivery_address_id,
          notes: order.notes,
        })
        if (order.customer) {
          setSelectedCustomer(order.customer as any)
          const branches = await getCustomerBranches(order.customer_id).catch(() => [])
          setCustomerBranches(branches)
        }
        if (order.items?.length) {
          const initialLines = order.items.map(i => calcLine({
            _key: i.id,
            product_id: i.product_id,
            productName: i.product?.name || '',
            productSku: i.product?.sku || '',
            unit_id: i.unit_id,
            unitLabel: i.unit?.symbol || i.unit?.name || '',
            available_units: [],
            base_unit_id: i.product?.base_unit?.id || '',
            base_unit_label: i.product?.base_unit?.symbol || '',
            conversion_factor: i.conversion_factor,
            quantity: i.quantity,
            base_quantity: i.base_quantity,
            unit_price: i.unit_price,
            discount_percent: i.discount_percent,
            discount_amount: i.discount_amount,
            tax_rate: i.tax_rate,
            tax_amount: i.tax_amount,
            line_total: i.line_total,
            availableQty: Infinity, // [FE-01] سيُحدَّث أدناه إذا كان المخزن محدداً
          }))
          setLines(initialLines)

          // [FE-01] جلب الكمية المتاحة الفعلية من المخزن لكل منتج
          // نفحص فقط إذا كان warehouse_id محدداً (قد يكون null في مسودة لم تؤكد)
          if (order.warehouse_id) {
            const stockChecks = order.items.map(i =>
              supabase.rpc('get_available_stock', {
                p_warehouse_id: order.warehouse_id,
                p_product_id: i.product_id,
              }).then(({ data }) => ({
                product_id: i.product_id,
                qty: typeof data === 'number' ? data : Infinity,
              }))
            )
            const results = await Promise.allSettled(stockChecks)
            setLines(prev => prev.map(line => {
              const hit = results.find(
                r => r.status === 'fulfilled' && r.value.product_id === line.product_id
              )
              return hit && hit.status === 'fulfilled'
                ? { ...line, availableQty: hit.value.qty }
                : line
            }))
          }
        }
      } catch { toast.error('فشل تحميل الطلب') }
      finally { setFormLoading(false) }
    })()
  }, [id])

  // ─── copyFrom: نسخ طلب موجود إلى مسودة جديدة ─────────────────────
  useEffect(() => {
    if (!copyFromId || isEdit) return
    ;(async () => {
      try {
        setFormLoading(true)
        const src = await getSalesOrder(copyFromId)
        setForm(f => ({
          ...f,
          customer_id:         src.customer_id,
          rep_id:              src.rep_id      || f.rep_id,
          branch_id:           src.branch_id  || null,
          delivery_method:     (src.delivery_method as DeliveryMethod) || 'direct',
          shipping_company_id: src.shipping_company_id || null,
          shipping_cost:       src.shipping_cost       || 0,
          shipping_on_customer: src.shipping_on_customer || false,
          order_date:          new Date().toISOString().split('T')[0],
          warehouse_id:        null, // يُحدّد عند التأكيد
          notes:               null,
        }))
        if (src.customer) {
          setSelectedCustomer(src.customer as any)
          const branches = await getCustomerBranches(src.customer_id).catch(() => [])
          setCustomerBranches(branches)
        }
        if (src.items?.length) {
          setLines(src.items.map((item: any) => calcLine({
            _key:             crypto.randomUUID(),
            product_id:       item.product_id,
            productName:      item.product?.name || '',
            productSku:       item.product?.sku  || '',
            unit_id:          item.unit_id,
            unitLabel:        item.unit?.symbol || item.unit?.name || '',
            available_units:  [],
            base_unit_id:     item.product?.base_unit?.id || '',
            base_unit_label:  item.product?.base_unit?.symbol || '',
            conversion_factor: item.conversion_factor || 1,
            quantity:          item.quantity,
            base_quantity:     item.base_quantity || item.quantity,
            unit_price:        item.unit_price,
            discount_percent:  item.discount_percent || 0,
            discount_amount:   item.discount_amount  || 0,
            tax_rate:          item.tax_rate          || 0,
            tax_amount:        item.tax_amount         || 0,
            line_total:        item.line_total          || 0,
            availableQty:      Infinity,
          })))
        }
        toast.info('تم نسخ بيانات الطلب — يُرجى المراجعة قبل الحفظ')
      } catch {
        toast.error('فشل تحميل الطلب الأصلي')
      } finally {
        setFormLoading(false)
      }
    })()
  }, [copyFromId, isEdit])

  // ─── Save ───
  const handleSave = async () => {
    if (!form.customer_id) { toast.error('يرجى اختيار العميل أولاً'); return }
    if (validLines.length === 0) { toast.error('يرجى إضافة منتج واحد على الأقل'); return }
    if (isUnderMin) { toast.error(`الحد الأدنى للطلب ${formatNumber(minOrder)} ج.م`); return }

    setSaving(true)
    try {
      let orderId = id
      if (isEdit) {
        await updateSalesOrder(id!, form)
      } else {
        const order = await createSalesOrder(form)
        orderId = order.id
      }

      const itemInputs: SalesOrderItemInput[] = validLines.map(l => ({
        product_id: l.product_id,
        unit_id: l.unit_id,
        conversion_factor: l.conversion_factor,
        quantity: l.quantity,
        base_quantity: l.base_quantity,
        unit_price: l.unit_price,
        discount_percent: l.discount_percent,
        discount_amount: l.discount_amount,
        tax_rate: l.tax_rate,
        tax_amount: l.tax_amount,
        line_total: l.line_total,
      }))

      await saveSalesOrderItems(orderId!, itemInputs)
      await recalcOrderTotals(orderId!)

      toast.success(isEdit ? 'تم تحديث الطلب' : 'تم إنشاء الطلب كمسودة ✓')
      navigate(`/sales/orders/${orderId}`)
    } catch (err: any) {
      toast.error(err.message || 'فشلت العملية')
    } finally {
      setSaving(false)
    }
  }

  if (formLoading) return (
    <div className="page-container animate-enter">
      <div className="edara-card" style={{ padding: 48, textAlign: 'center', color: 'var(--text-muted)' }}>
        جاري تحميل الطلب...
      </div>
    </div>
  )

  /* ════════════════════════════════════════════
     RENDER
  ════════════════════════════════════════════ */
  return (
    <div className="page-container animate-enter">
      <PageHeader
        title={isEdit ? 'تعديل أمر بيع' : 'أمر بيع جديد'}
        subtitle={selectedCustomer ? `للعميل: ${selectedCustomer.name}` : 'اختر العميل وأضف المنتجات'}
        actions={
          <Button variant="ghost" onClick={() => navigate(-1)}>
            <ArrowRight size={16} /> رجوع
          </Button>
        }
      />

      {/* ══════ Section 1: Customer & Header ══════ */}
      <section style={sCard}>
        <SectionHead icon={<User size={16} />} title="بيانات الطلب" />

        <div style={grid2}>
          {/* Customer */}
          <div style={{ gridColumn: '1 / -1' }}>
            <FieldLabel required>العميل</FieldLabel>
            <Combobox
              placeholder="ابحث بالاسم أو الكود أو الهاتف..."
              value={selectedCustomer?.code || ''}
              items={customerResults.map(c => ({
                id: c.id,
                primary: c.name,
                secondary: c.code,
                meta: c.phone || undefined,
              }))}
              onSearch={searchCustomers}
              onSelect={item => {
                const c = customerResults.find(c => c.id === item.id)
                if (c) selectCustomer(c)
              }}
              onClear={clearCustomer}
              selected={!!selectedCustomer}
              selectedLabel={selectedCustomer?.name}
            />
          </div>

          {/* Customer info strip */}
          {selectedCustomer && (
            <div style={{ gridColumn: '1 / -1', display: 'flex', flexWrap: 'wrap', gap: 12 }}>
              {selectedCustomer.phone && (
                <InfoPill label="الهاتف" value={selectedCustomer.phone} />
              )}
              {selectedCustomer.payment_terms && (
                <InfoPill label="شروط الدفع" value={
                  selectedCustomer.payment_terms === 'cash' ? 'نقدي' :
                  selectedCustomer.payment_terms === 'credit' ? `آجل${selectedCustomer.credit_days ? ` — ${selectedCustomer.credit_days} يوم` : ''}` : selectedCustomer.payment_terms
                } />
              )}
              {selectedCustomer.credit_limit && selectedCustomer.credit_limit > 0 && (
                <InfoPill label="حد الائتمان" value={`${formatNumber(selectedCustomer.credit_limit)} ج.م`} warn />
              )}
            </div>
          )}

          {/* Rep */}
          <div>
            <FieldLabel>المندوب</FieldLabel>
            {isSalesRep ? (
              // المندوب يرى اسمه مقروءاً فقط — لا يُغير المُعيَّن
              <div className="form-input" style={{ background: 'var(--bg-surface-2, var(--bg-hover))', cursor: 'default', color: 'var(--text-secondary)' }}>
                {profile?.full_name || 'أنت'}
              </div>
            ) : (
              <select className="form-select" value={form.rep_id || ''}
                onChange={e => setForm(f => ({ ...f, rep_id: e.target.value || null }))}>
                <option value="">— اختر المندوب —</option>
                {reps.map((r: any) => <option key={r.id} value={r.id}>{r.full_name}</option>)}
              </select>
            )}
          </div>

          {/* Date */}
          <div>
            <FieldLabel>تاريخ الطلب</FieldLabel>
            <input
              className="form-input" type="date"
              value={form.order_date}
              onChange={e => setForm(f => ({ ...f, order_date: e.target.value }))}
            />
          </div>

          {/* ملاحظة: المخزن يُحدد عند التسليم لا في مرحلة إنشاء المسودة */}

          {/* Branch (delivery address) */}
          {customerBranches.length > 0 && (
            <div>
              <FieldLabel>عنوان التسليم</FieldLabel>
              <select className="form-select" value={form.delivery_address_id || ''}
                onChange={e => setForm(f => ({ ...f, delivery_address_id: e.target.value || null }))}>
                <option value="">— اختر فرع التسليم —</option>
                {customerBranches.map(b => <option key={b.id} value={b.id}>{b.name}{b.is_primary ? ' ⭐' : ''}</option>)}
              </select>
              {/* Show selected branch address */}
              {form.delivery_address_id && (() => {
                const branch = customerBranches.find(b => b.id === form.delivery_address_id)
                return branch?.address ? (
                  <div style={{ marginTop: 6, fontSize: '0.75rem', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 4 }}>
                    <MapPin size={12} style={{ flexShrink: 0 }} />
                    {branch.address}
                  </div>
                ) : null
              })()}
            </div>
          )}
        </div>
      </section>

      {/* ══════ Section 2: Delivery ══════ */}
      <section style={sCard}>
        <SectionHead icon={<Truck size={16} />} title="طريقة التوصيل" />

        {/* Toggle buttons: direct / shipping / pickup */}
        <div style={{ display: 'flex', gap: 8, marginBottom: 16, flexWrap: 'wrap' }}>
          {([
            { v: 'direct', label: 'توصيل مباشر' },
            { v: 'shipping', label: '🚚 شحن' },
            { v: 'pickup', label: '🏢 استلام ذاتي' },
          ] as const).map(opt => (
            <button
              key={opt.v} type="button"
              onClick={() => setForm(f => ({ ...f, delivery_method: opt.v as DeliveryMethod }))}
              style={{
                padding: '8px 16px', borderRadius: 8, fontSize: '0.875rem', cursor: 'pointer',
                fontWeight: form.delivery_method === opt.v ? 700 : 400,
                background: form.delivery_method === opt.v ? 'var(--color-primary)' : 'var(--bg-surface-2, var(--bg-hover))',
                color: form.delivery_method === opt.v ? '#fff' : 'var(--text-secondary)',
                border: form.delivery_method === opt.v ? '2px solid var(--color-primary)' : '2px solid var(--border-color)',
                transition: 'all 0.15s',
              }}
            >
              {opt.label}
            </button>
          ))}
        </div>

        {form.delivery_method === 'shipping' && (
          <div style={grid3}>
            <div>
              <FieldLabel>شركة الشحن</FieldLabel>
              <select className="form-select" value={form.shipping_company_id || ''}
                onChange={e => setForm(f => ({ ...f, shipping_company_id: e.target.value || null }))}>
                <option value="">— اختر شركة —</option>
                {shippingCos.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </div>
            <div>
              <FieldLabel>تكلفة الشحن (ج.م)</FieldLabel>
              <input className="form-input" type="number" min={0} step="0.01"
                value={form.shipping_cost || 0}
                onChange={e => setForm(f => ({ ...f, shipping_cost: Number(e.target.value) }))} />
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', paddingBottom: 2 }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', userSelect: 'none', padding: '10px 0' }}>
                <input type="checkbox" checked={!!form.shipping_on_customer}
                  onChange={e => setForm(f => ({ ...f, shipping_on_customer: e.target.checked }))}
                  style={{ width: 16, height: 16, accentColor: 'var(--color-primary)' }} />
                <span style={{ fontSize: '0.875rem' }}>على حساب العميل</span>
              </label>
            </div>
          </div>
        )}
      </section>

      {/* ══════ Section 3: Items ══════ */}
      <section style={{ ...sCard, padding: 0, overflow: 'hidden' }}>
        {/* Header */}
        <div style={{
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          padding: '16px 20px', borderBottom: '1px solid var(--border-color)',
        }}>
          <SectionHead icon={<Package size={16} />} title={`بنود الطلب`} style={{ marginBottom: 0 }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
              {validLines.length} منتج
            </span>
            <Button variant="ghost" size="sm" icon={<Plus size={14} />} onClick={addLine}>
              إضافة بند
            </Button>
          </div>
        </div>

        {/* ── Desktop Table (md+) ── */}
        <div className="hide-mobile" style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.875rem', minWidth: 780 }}>
            <thead>
              <tr style={{ background: 'var(--bg-surface-2, var(--bg-hover))', textAlign: 'right' }}>
                <TH w={240}>المنتج</TH>
                <TH w={110}>الوحدة</TH>
                <TH w={85}>الكمية</TH>
                <TH w={105}>سعر الوحدة</TH>
                <TH w={80}>خصم %</TH>
                <TH w={85}>الضريبة</TH>
                <TH w={110}>الإجمالي</TH>
                <TH w={44}></TH>
              </tr>
            </thead>
            <tbody>
              {lines.map((line, idx) => (
                <tr key={line._key} style={{ borderBottom: '1px solid var(--border-color)' }}>
                  {/* Product cell */}
                  <td style={{ padding: '8px 12px', position: 'relative' }}>
                    {line.product_id ? (
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ fontWeight: 600, lineHeight: 1.3, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                            {line.productName}
                          </div>
                          <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', fontFamily: 'monospace' }}>
                            {line.productSku}
                          </div>
                        </div>
                        <button type="button" onClick={() => setLines(p => { const c = [...p]; c[idx] = newLine(); return c })}
                          style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', padding: 3, borderRadius: 4, flexShrink: 0 }}
                          title="تغيير المنتج">
                          <X size={13} />
                        </button>
                      </div>
                    ) : (
                      <ProductComboCell
                        lineIdx={idx}
                        productQuery={activeProductIdx === idx ? productQuery : ''}
                        productResults={activeProductIdx === idx ? productResults : []}
                        onSearch={q => { setActiveProductIdx(idx); setProductQuery(q); searchProducts(q) }}
                        onSelect={p => selectProduct(idx, p)}
                        onFocus={() => setActiveProductIdx(idx)}
                        onBlur={() => setTimeout(() => setActiveProductIdx(null), 200)}
                      />
                    )}
                  </td>

                  {/* Unit */}
                  <td style={{ padding: '8px 6px' }}>
                    {line.available_units.length > 1 ? (
                      <select className="form-select"
                        style={{ fontSize: '0.875rem', padding: '5px 6px', minWidth: 90 }}
                        value={line.unit_id}
                        onChange={e => changeUnit(idx, e.target.value)}>
                        {line.available_units.map(u => (
                          <option key={u.unit_id} value={u.unit_id}>
                            {u.unit?.symbol || u.unit?.name}
                            {u.conversion_factor !== 1 ? ` ×${u.conversion_factor}` : ''}
                          </option>
                        ))}
                      </select>
                    ) : (
                      <span style={{ fontWeight: 500, color: line.unitLabel ? 'inherit' : 'var(--text-muted)' }}>
                        {line.unitLabel || line.base_unit_label || '—'}
                      </span>
                    )}
                  </td>

                  {/* Qty */}
                  <td style={{ padding: '8px 4px' }}>
                    <NumInput value={line.quantity} min={0.01} step={1}
                      onChange={v => updateLine(idx, 'quantity', v)} width={72}
                      style={line.product_id && isFinite(line.availableQty) && line.quantity > line.availableQty
                        ? { borderColor: 'var(--color-danger)' } : undefined} />
                    {line.product_id && isFinite(line.availableQty) && line.quantity > line.availableQty && (
                      <div style={{ fontSize: '0.68rem', color: 'var(--color-danger)', marginTop: 2, whiteSpace: 'nowrap' }}>
                        ⚠️ متاح: {formatNumber(line.availableQty)}
                      </div>
                    )}
                  </td>

                  {/* Price */}
                  <td style={{ padding: '8px 4px' }}>
                    <NumInput value={line.unit_price} min={0} step={0.01}
                      disabled={!canEditPrice}
                      title={!canEditPrice ? 'ليس لديك صلاحية تعديل السعر' : undefined}
                      onChange={v => updateLine(idx, 'unit_price', v)} width={90} />
                  </td>

                  {/* Discount % */}
                  <td style={{ padding: '8px 4px' }}>
                    <NumInput value={line.discount_percent} min={0} max={canOverrideDiscount ? 100 : maxDiscount}
                      step={0.5} width={68}
                      onChange={v => {
                        if (v > maxDiscount && !canOverrideDiscount) {
                          toast.error(`الحد الأقصى للخصم ${maxDiscount}%`)
                          return
                        }
                        updateLine(idx, 'discount_percent', v)
                      }}
                      style={{ borderColor: line.discount_percent > maxDiscount ? 'var(--color-danger)' : undefined }}
                    />
                  </td>

                  {/* Tax */}
                  <td style={{ padding: '8px 6px', color: 'var(--text-muted)', fontVariantNumeric: 'tabular-nums', fontSize: '0.8125rem', textAlign: 'left' }}>
                    {line.tax_amount > 0 ? formatNumber(line.tax_amount) : '—'}
                  </td>

                  {/* Total */}
                  <td style={{ padding: '8px 6px', fontWeight: 700, fontVariantNumeric: 'tabular-nums', textAlign: 'left', color: line.line_total > 0 ? 'var(--text-primary)' : 'var(--text-muted)' }}>
                    {line.line_total > 0 ? formatNumber(line.line_total) : '—'}
                  </td>

                  {/* Delete */}
                  <td style={{ padding: '8px 4px', textAlign: 'center' }}>
                    {lines.length > 1 && (
                      <button type="button" onClick={() => removeLine(idx)}
                        style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--color-danger)', padding: 4, borderRadius: 4 }}
                        title="حذف البند"
                        onMouseEnter={e => (e.currentTarget.style.background = 'rgba(220,38,38,0.08)')}
                        onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
                      >
                        <Trash2 size={14} />
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* ── Mobile Cards (<md) ── */}
        <div className="show-mobile" style={{ display: 'none', flexDirection: 'column' }}>
          {lines.map((line, idx) => (
            <div key={line._key} style={{
              padding: 16, borderBottom: '1px solid var(--border-color)',
              background: !line.product_id ? 'rgba(245,158,11,0.03)' : undefined,
            }}>
              {/* Product search */}
              {!line.product_id ? (
                <div style={{ marginBottom: 12 }}>
                  <FieldLabel>المنتج</FieldLabel>
                  <ProductComboCell
                    lineIdx={idx}
                    productQuery={activeProductIdx === idx ? productQuery : ''}
                    productResults={activeProductIdx === idx ? productResults : []}
                    onSearch={q => { setActiveProductIdx(idx); setProductQuery(q); searchProducts(q) }}
                    onSelect={p => selectProduct(idx, p)}
                    onFocus={() => setActiveProductIdx(idx)}
                    onBlur={() => setTimeout(() => setActiveProductIdx(null), 200)}
                  />
                </div>
              ) : (
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 12 }}>
                  <div>
                    <div style={{ fontWeight: 700 }}>{line.productName}</div>
                    <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{line.productSku}</div>
                  </div>
                  <button type="button" onClick={() => setLines(p => { const c = [...p]; c[idx] = newLine(); return c })}
                    style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', padding: 4 }}>
                    <X size={14} />
                  </button>
                </div>
              )}

              {/* حقول التفاصيل — تظهر فقط بعد اختيار المنتج */}
              {line.product_id && (
                <>
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                    {/* Unit */}
                    <div>
                      <FieldLabel>الوحدة</FieldLabel>
                      {line.available_units.length > 1 ? (
                        <select className="form-select" value={line.unit_id} onChange={e => changeUnit(idx, e.target.value)}>
                          {line.available_units.map(u => (
                            <option key={u.unit_id} value={u.unit_id}>
                              {u.unit?.symbol || u.unit?.name}
                              {u.conversion_factor !== 1 ? ` ×${u.conversion_factor}` : ''}
                            </option>
                          ))}
                        </select>
                      ) : (
                        <div className="form-input" style={{ background: 'var(--bg-surface-2, var(--bg-hover))', cursor: 'default' }}>
                          {line.unitLabel || line.base_unit_label || '—'}
                        </div>
                      )}
                    </div>

                    {/* Qty */}
                    <div>
                      <FieldLabel>الكمية</FieldLabel>
                      <input className="form-input" type="number" min={0.01} step={1}
                        value={line.quantity}
                        style={isFinite(line.availableQty) && line.quantity > line.availableQty
                          ? { borderColor: 'var(--color-danger)' } : undefined}
                        onChange={e => updateLine(idx, 'quantity', Number(e.target.value))} />
                      {isFinite(line.availableQty) && line.quantity > line.availableQty && (
                        <div style={{ fontSize: '0.7rem', color: 'var(--color-danger)', marginTop: 2 }}>
                          ⚠️ متاح: {formatNumber(line.availableQty)}
                        </div>
                      )}
                    </div>

                    {/* Price */}
                    <div>
                      <FieldLabel>السعر</FieldLabel>
                      <input className="form-input" type="number" min={0} step={0.01}
                        disabled={!canEditPrice}
                        value={line.unit_price} onChange={e => updateLine(idx, 'unit_price', Number(e.target.value))} />
                    </div>

                    {/* Discount */}
                    <div>
                      <FieldLabel>خصم %</FieldLabel>
                      <input className="form-input" type="number" min={0}
                        max={canOverrideDiscount ? 100 : maxDiscount}
                        value={line.discount_percent}
                        onChange={e => {
                          const v = Number(e.target.value)
                          if (v > maxDiscount && !canOverrideDiscount) { toast.error(`الحد الأقصى ${maxDiscount}%`); return }
                          updateLine(idx, 'discount_percent', v)
                        }} />
                    </div>
                  </div>

                  {/* Line totals */}
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 10, paddingTop: 10, borderTop: '1px dashed var(--border-color)', alignItems: 'center' }}>
                    <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
                      {line.discount_amount > 0 && `خصم: ${formatNumber(line.discount_amount)} — `}
                      {line.tax_amount > 0 && `ضريبة: ${formatNumber(line.tax_amount)}`}
                    </div>
                    <div style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: 'var(--color-primary)' }}>
                      {formatNumber(line.line_total)} ج.م
                    </div>
                  </div>
                </>
              )}

              {lines.length > 1 && (
                <button type="button" onClick={() => removeLine(idx)}
                  style={{ marginTop: 10, background: 'none', border: 'none', cursor: 'pointer', color: 'var(--color-danger)', fontSize: '0.875rem', display: 'flex', alignItems: 'center', gap: 4 }}>
                  <Trash2 size={14} /> حذف البند
                </button>
              )}
            </div>
          ))}
        </div>

        {/* Add line button */}
        <div style={{ padding: 12, borderTop: '1px dashed var(--border-color)', textAlign: 'center' }}>
          <button type="button" onClick={addLine} style={{
            background: 'none', border: 'none', cursor: 'pointer',
            color: 'var(--color-primary)', fontSize: '0.875rem', fontWeight: 600,
            display: 'inline-flex', alignItems: 'center', gap: 6, padding: '6px 12px', borderRadius: 6,
          }}
            onMouseEnter={e => (e.currentTarget.style.background = 'var(--color-primary-light, rgba(37,99,235,0.06))')}
            onMouseLeave={e => (e.currentTarget.style.background = 'none')}>
            <Plus size={16} /> إضافة بند آخر
          </button>
        </div>
      </section>

      {/* ══════ Section 4: Notes ══════ */}
      <section style={sCard}>
        <FieldLabel>ملاحظات</FieldLabel>
        <textarea className="form-input" rows={2} value={form.notes || ''}
          onChange={e => setForm(f => ({ ...f, notes: e.target.value || null }))}
          placeholder="ملاحظات إضافية على الطلب..." />
      </section>

      {/* ══════ Section 5: Totals & Actions ══════ */}
      <section style={sCard}>
        <div style={{ display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: 24 }}>
          {/* Totals */}
          <div style={{ minWidth: 260, maxWidth: 360, flex: 1 }}>
            <SectionHead icon={<Calculator size={16} />} title="الإجمالي" />
            <TotalRow label="المجموع" value={totals.subtotal} />
            {totals.discount > 0 && <TotalRow label="إجمالي الخصومات" value={totals.discount} minus />}
            {totals.tax > 0 && <TotalRow label="الضريبة" value={totals.tax} />}
            {totals.shipping > 0 && <TotalRow label="الشحن" value={totals.shipping} />}
            <div style={{ display: 'flex', justifyContent: 'space-between', paddingTop: 12, marginTop: 8, borderTop: '2px solid var(--border-color)' }}>
              <span style={{ fontWeight: 700, fontSize: '1.0625rem' }}>الإجمالي الكلي</span>
              <span style={{ fontWeight: 800, fontSize: '1.125rem', fontVariantNumeric: 'tabular-nums', color: 'var(--color-primary)' }}>
                {formatNumber(totals.total)} ج.م
              </span>
            </div>
          </div>

          {/* Actions */}
          <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', gap: 12, minWidth: 200 }}>
            {isUnderMin && (
              <div style={{
                display: 'flex', alignItems: 'center', gap: 8,
                padding: '8px 12px', borderRadius: 8,
                background: 'rgba(217,119,6,0.08)', border: '1px solid rgba(217,119,6,0.2)',
                color: 'var(--color-warning)', fontSize: '0.875rem',
              }}>
                <AlertTriangle size={14} />
                <span>الحد الأدنى {formatNumber(minOrder)} ج.م</span>
              </div>
            )}
            <div style={{ display: 'flex', gap: 10 }}>
              <Button variant="ghost" onClick={() => navigate(-1)} style={{ flex: '0 0 auto' }}>إلغاء</Button>
              <Button
                icon={<Save size={15} />}
                onClick={handleSave}
                disabled={saving || !form.customer_id || validLines.length === 0 || isUnderMin}
                style={{ flex: 1 }}
              >
                {saving ? 'جاري الحفظ...' : isEdit ? 'حفظ التعديلات' : 'حفظ المسودة'}
              </Button>
            </div>
          </div>
        </div>
      </section>
    </div>
  )
}

// ─────────────────────────────────────────────
// Sub-components
// ─────────────────────────────────────────────

const sCard: React.CSSProperties = {
  background: 'var(--bg-surface)',
  border: '1px solid var(--border-color)',
  borderRadius: 12,
  padding: 20,
  marginBottom: 16,
}

const grid2: React.CSSProperties = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))',
  gap: 16,
}

const grid3: React.CSSProperties = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))',
  gap: 16,
}

function SectionHead({ icon, title, style }: { icon: React.ReactNode; title: string; style?: React.CSSProperties }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16, ...style }}>
      <span style={{
        width: 28, height: 28, borderRadius: 8,
        background: 'var(--color-primary-light, rgba(37,99,235,0.08))',
        color: 'var(--color-primary)', display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>{icon}</span>
      <span style={{ fontWeight: 700, fontSize: '0.9375rem' }}>{title}</span>
    </div>
  )
}

function FieldLabel({ children, required }: { children: React.ReactNode; required?: boolean }) {
  return (
    <div style={{ fontSize: '0.8125rem', fontWeight: 600, color: 'var(--text-secondary, var(--text-muted))', marginBottom: 6 }}>
      {children}
      {required && <span style={{ color: 'var(--color-danger)', marginRight: 3 }}>*</span>}
    </div>
  )
}

function InfoPill({ label, value, warn }: { label: string; value: string; warn?: boolean }) {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      padding: '4px 10px', borderRadius: 20, fontSize: '0.8125rem',
      background: warn ? 'rgba(217,119,6,0.08)' : 'var(--bg-surface-2, var(--bg-hover))',
      color: warn ? 'var(--color-warning)' : 'var(--text-secondary)',
      border: `1px solid ${warn ? 'rgba(217,119,6,0.2)' : 'var(--border-color)'}`,
    }}>
      <span style={{ color: 'var(--text-muted)', fontSize: '0.75rem' }}>{label}:</span>
      <span style={{ fontWeight: 600 }}>{value}</span>
    </div>
  )
}

function TH({ children, w }: { children?: React.ReactNode; w?: number }) {
  return (
    <th style={{
      padding: '10px 8px', textAlign: 'right',
      fontWeight: 600, fontSize: '0.8125rem', color: 'var(--text-secondary, var(--text-muted))',
      width: w, whiteSpace: 'nowrap',
    }}>{children}</th>
  )
}

function NumInput({ value, min = 0, max, step = 1, disabled, title, onChange, width = 80, style }: {
  value: number; min?: number; max?: number; step?: number
  disabled?: boolean; title?: string; onChange: (v: number) => void
  width?: number; style?: React.CSSProperties
}) {
  return (
    <input
      className="form-input"
      type="number" min={min} max={max} step={step}
      value={value} disabled={disabled} title={title}
      onChange={e => onChange(Number(e.target.value))}
      style={{ width, padding: '5px 6px', fontSize: '0.875rem', textAlign: 'center', ...style }}
    />
  )
}

function TotalRow({ label, value, minus }: { label: string; value: number; minus?: boolean }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8, fontSize: '0.875rem' }}>
      <span style={{ color: 'var(--text-muted)' }}>{label}</span>
      <span style={{ fontVariantNumeric: 'tabular-nums', color: minus ? 'var(--color-danger)' : undefined }}>
        {minus ? '- ' : ''}{formatNumber(value)} ج.م
      </span>
    </div>
  )
}

interface ProductComboCellProps {
  lineIdx: number
  productQuery: string
  productResults: any[]
  onSearch: (q: string) => void
  onSelect: (p: any) => void
  onFocus: () => void
  onBlur: () => void
}

/**
 * ProductComboCell — يستخدم createPortal لرسم الـ dropdown
 * خارج شجرة DOM مباشرةً في document.body
 * حتى لا يُقطع بـ overflow:auto على الجدول.
 */
function ProductComboCell({ productQuery, productResults, onSearch, onSelect, onFocus, onBlur }: ProductComboCellProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [dropPos, setDropPos] = useState<{ top: number; left: number; width: number } | null>(null)

  // احسب موقع الـ input كلما تغيرت النتائج
  useEffect(() => {
    if (productResults.length === 0) { setDropPos(null); return }
    if (!inputRef.current) return
    const rect = inputRef.current.getBoundingClientRect()
    setDropPos({
      top: rect.bottom + window.scrollY + 4,
      left: rect.left + window.scrollX,
      width: Math.max(rect.width, 320),
    })
  }, [productResults])

  // أعد الحساب عند Scroll أو Resize (Viewport)
  useEffect(() => {
    if (!dropPos) return
    const recalc = () => {
      if (!inputRef.current) return
      const rect = inputRef.current.getBoundingClientRect()
      setDropPos({
        top: rect.bottom + window.scrollY + 4,
        left: rect.left + window.scrollX,
        width: Math.max(rect.width, 320),
      })
    }
    window.addEventListener('scroll', recalc, true)
    window.addEventListener('resize', recalc)
    return () => {
      window.removeEventListener('scroll', recalc, true)
      window.removeEventListener('resize', recalc)
    }
  }, [dropPos])

  return (
    <div style={{ position: 'relative' }}>
      <div style={{ position: 'relative' }}>
        <Search size={13} style={{
          position: 'absolute', right: 8, top: '50%', transform: 'translateY(-50%)',
          color: 'var(--text-muted)', pointerEvents: 'none',
        }} />
        <input
          ref={inputRef}
          className="form-input"
          placeholder="ابحث عن منتج..."
          value={productQuery}
          style={{ paddingRight: 28, fontSize: '0.875rem', padding: '6px 28px 6px 8px' }}
          onChange={e => onSearch(e.target.value)}
          onFocus={onFocus}
          onBlur={onBlur}
          autoComplete="off"
        />
      </div>

      {/* ── Portal Dropdown ──
          يُرسَم في document.body خارج أي overflow container
          ويُعالج `onMouseDown` بـ preventDefault لمنع blur قبل الاختيار */}
      {dropPos && productResults.length > 0 && createPortal(
        <div
          style={{
            position: 'absolute',
            top: dropPos.top,
            left: dropPos.left,
            width: dropPos.width,
            zIndex: 9999,
            background: 'var(--bg-surface)',
            border: '1px solid var(--border-color)',
            borderRadius: 10,
            boxShadow: '0 16px 48px rgba(0,0,0,0.16)',
            maxHeight: 300,
            overflowY: 'auto',
          }}
        >
          {productResults.map((p, i) => {
            const isOut = p.stock_status === 'out'
            const isLow = p.stock_status === 'low'
            const stockColor = isOut ? 'var(--color-danger)' : isLow ? 'var(--color-warning)' : 'var(--color-success)'
            const stockDot = isOut ? '🔴' : isLow ? '🟡' : '🟢'
            return (
              <div
                key={p.id}
                onMouseDown={e => {
                  e.preventDefault()
                  if (!isOut) onSelect(p)
                }}
                style={{
                  padding: '10px 14px',
                  cursor: isOut ? 'not-allowed' : 'pointer',
                  opacity: isOut ? 0.5 : 1,
                  borderBottom: i < productResults.length - 1 ? '1px solid var(--border-color)' : 'none',
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  gap: 12,
                  transition: 'background 0.12s',
                }}
                onMouseEnter={e => { if (!isOut) e.currentTarget.style.background = 'var(--bg-hover)' }}
                onMouseLeave={e => (e.currentTarget.style.background = '')}
              >
                {/* Product info */}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontWeight: 600, fontSize: '0.875rem', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {stockDot} {p.name}
                  </div>
                  <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', display: 'flex', gap: 8, marginTop: 2 }}>
                    <span style={{ fontFamily: 'monospace' }}>{p.sku}</span>
                    {p.base_unit && <span>• {p.base_unit.symbol || p.base_unit.name}</span>}
                  </div>
                </div>

                {/* Right: price + stock */}
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 2, flexShrink: 0 }}>
                  <span style={{ fontWeight: 700, fontSize: '0.875rem', color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>
                    {formatNumber(p.selling_price)} ج.م
                  </span>
                  <span style={{ fontSize: '0.7rem', color: stockColor, fontVariantNumeric: 'tabular-nums', fontWeight: 600 }}>
                    {isOut ? 'نفذ' : `متاح: ${formatNumber(p.available_qty)}`}
                  </span>
                </div>
              </div>
            )
          })}
        </div>,
        document.body
      )}
    </div>
  )
}
