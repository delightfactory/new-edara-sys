import { useState, useEffect, useMemo, useCallback, useRef } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, Plus, Trash2, Save, Package, Search, X,
  CheckCircle, AlertTriangle, Loader2, FileText, RotateCcw,
  TrendingDown, DollarSign,
} from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import { supabase } from '@/lib/supabase/client'
import { getMyWarehouses } from '@/lib/services/inventory'
import {
  getPurchaseReturn,
  createPurchaseReturn,
  updatePurchaseReturn,
  confirmPurchaseReturn,
} from '@/lib/services/purchase-returns'
import { getProductCostMetrics } from '@/lib/services/products'
import { formatNumber } from '@/lib/utils/format'
import type {
  PurchaseReturn,
  PurchaseReturnItemInput,
  Supplier,
  Warehouse,
} from '@/lib/types/master-data'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'

// ─── Styles ──────────────────────────────────────────────────
const sCard: React.CSSProperties = {
  background: 'var(--bg-surface)',
  border: '1px solid var(--border-color)',
  borderRadius: 'var(--radius-lg)',
  padding: '20px 24px',
  marginBottom: 16,
}

function FieldLabel({ children, required }: { children: React.ReactNode; required?: boolean }) {
  return (
    <label style={{ display: 'block', marginBottom: 6, fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-secondary)' }}>
      {children}
      {required && <span style={{ color: 'var(--color-danger)', marginRight: 4 }}>*</span>}
    </label>
  )
}

function SectionHead({ icon, title }: { icon: React.ReactNode; title: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16, fontWeight: 700, fontSize: '0.9rem' }}>
      <span style={{ color: 'var(--color-primary)' }}>{icon}</span>
      {title}
    </div>
  )
}

function StatusBadge({ status }: { status: 'draft' | 'confirmed' }) {
  const map = {
    draft:     { label: 'مسودة', color: '#92400e', bg: '#fef3c7' },
    confirmed: { label: 'مؤكد',  color: '#166534', bg: '#dcfce7' },
  }
  const { label, color, bg } = map[status]
  return (
    <span style={{ padding: '3px 12px', borderRadius: 99, fontWeight: 700, fontSize: '0.78rem', color, background: bg }}>
      {label}
    </span>
  )
}

// ─── Inline Combobox ─────────────────────────────────────────

interface ComboItem { id: string; primary: string; secondary?: string }

function InlineCombobox({
  placeholder, items, onSearch, onSelect, onClear, selected, selectedLabel, disabled,
}: {
  placeholder: string; items: ComboItem[]; onSearch: (q: string) => void
  onSelect: (item: ComboItem) => void; onClear?: () => void
  selected?: boolean; selectedLabel?: string; disabled?: boolean
}) {
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

  if (selected && selectedLabel) {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, padding: '8px 12px',
        background: 'rgba(37,99,235,0.07)', border: '1.5px solid var(--color-primary)',
        borderRadius: 8, minHeight: 42,
      }}>
        <div style={{ flex: 1, fontWeight: 600, fontSize: '0.875rem', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {selectedLabel}
        </div>
        {onClear && !disabled && (
          <button onClick={onClear} type="button" style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', padding: 4 }}>
            <X size={14} />
          </button>
        )}
      </div>
    )
  }

  if (disabled) return (
    <div className="form-input" style={{ background: 'var(--bg-surface-2)', color: 'var(--text-muted)', cursor: 'default', minHeight: 42 }}>
      {placeholder}
    </div>
  )

  return (
    <div ref={ref} style={{ position: 'relative' }}>
      <div style={{ position: 'relative' }}>
        <Search size={14} style={{ position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
        <input
          className="form-input"
          style={{ paddingRight: 32 }}
          placeholder={placeholder}
          value={q}
          onChange={e => { setQ(e.target.value); onSearch(e.target.value); setOpen(e.target.value.length > 0) }}
          autoComplete="off"
        />
      </div>
      {open && items.length > 0 && (
        <div style={{
          position: 'absolute', zIndex: 999, top: 'calc(100% + 4px)', left: 0, right: 0,
          background: 'var(--bg-surface)', border: '1px solid var(--border-color)',
          borderRadius: 10, boxShadow: '0 12px 40px rgba(0,0,0,0.15)', maxHeight: 240, overflowY: 'auto',
        }}>
          {items.map((item, i) => (
            <div
              key={item.id}
              onMouseDown={e => { e.preventDefault(); onSelect(item); setQ(''); setOpen(false) }}
              style={{ padding: '10px 14px', cursor: 'pointer', borderBottom: i < items.length - 1 ? '1px solid var(--border-color)' : 'none' }}
              onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
              onMouseLeave={e => (e.currentTarget.style.background = '')}
            >
              <div style={{ fontWeight: 600, fontSize: '0.875rem' }}>{item.primary}</div>
              {item.secondary && <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>{item.secondary}</div>}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ─── Draft line type ──────────────────────────────────────────

interface ReturnLine {
  _key: string
  product_id: string
  productName: string
  unit_id: string
  unitName: string
  // [Bug-1 Fix] base price needed to recalculate on unit change
  base_last_purchase_price: number
  availableUnits: Array<{ unit_id: string; unit_name: string; unit_symbol: string; conversion_factor: number; purchase_price: number | null }>
  quantity: number
  unit_price: number
  discount_rate: number
  tax_rate: number
}

function newLine(): ReturnLine {
  return {
    _key: Math.random().toString(36).slice(2),
    product_id: '', productName: '', unit_id: '', unitName: '',
    base_last_purchase_price: 0,
    availableUnits: [], quantity: 1, unit_price: 0, discount_rate: 0, tax_rate: 0,
  }
}

// ─── TH helper ───────────────────────────────────────────────

function thStyle(w: number): React.CSSProperties {
  return { padding: '10px 12px', fontWeight: 600, fontSize: '0.8rem', whiteSpace: 'nowrap', width: w, minWidth: w }
}

// ─── Main Component ───────────────────────────────────────────

export default function PurchaseReturnForm() {
  const { id } = useParams<{ id?: string }>()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const isAdmin = can('inventory.read_all')

  const isNew = !id
  const [loading, setLoading]     = useState(!isNew)
  const [saving, setSaving]       = useState(false)
  const [confirming, setConfirming] = useState(false)
  const [returnData, setReturnData] = useState<PurchaseReturn | null>(null)

  // ─── Header fields ───────────────────────────────────────────
  const [supplierId, setSupplierId]         = useState('')
  const [warehouseId, setWarehouseId]       = useState('')
  const [originalInvoiceId, setOriginalInvoiceId] = useState('')
  const [returnDate, setReturnDate]         = useState(new Date().toISOString().split('T')[0])
  const [notes, setNotes]                   = useState('')
  const [returnLines, setReturnLines]       = useState<ReturnLine[]>([newLine()])

  // ─── UI search state ─────────────────────────────────────────────────────────
  const [selectedSupplier, setSelectedSupplier]         = useState<Supplier | null>(null)
  const [supplierResults, setSupplierResults]           = useState<Supplier[]>([])
  const [warehouses, setWarehouses]                     = useState<Warehouse[]>([])
  const [myWarehouses, setMyWarehouses]                 = useState<Warehouse[]>([])
  const [productResults, setProductResults]             = useState<any[]>([])
  const [activeProductIdx, setActiveProductIdx]         = useState<number | null>(null)
  // [Bug-2 Fix] invoice UUID combobox state
  const [selectedInvoiceLabel, setSelectedInvoiceLabel] = useState('')
  const [invoiceResults, setInvoiceResults]             = useState<any[]>([])

  useEffect(() => {
    supabase.from('warehouses').select('id, name').eq('is_active', true).order('name')
      .then(({ data }) => setWarehouses(data as Warehouse[] || []))
    // نجلب دائماً — حتى لو isAdmin
    getMyWarehouses().then(whs => {
      setMyWarehouses(whs)
      if (isNew && whs.length > 0) setWarehouseId(whs[0].id)
    }).catch(() => {})
  }, [])

  const searchSuppliers = useCallback(async (q: string) => {
    if (q.length < 2) { setSupplierResults([]); return }
    const { data } = await supabase
      .from('suppliers').select('id, name, code').eq('is_active', true)
      .or(`name.ilike.%${q}%,code.ilike.%${q}%`).limit(10)
    setSupplierResults(data as Supplier[] || [])
  }, [])

  const searchProducts = useCallback(async (q: string) => {
    if (q.length < 2) { setProductResults([]); return }
    const { data } = await supabase
      .from('products')
      .select(`
        id, name, sku, tax_rate, base_unit_id,
        base_unit:units!products_base_unit_id_fkey(id, name, symbol),
        product_units(id, unit_id, conversion_factor, selling_price, is_purchase_unit, unit:units(id, name, symbol))
      `)
      .eq('is_active', true)
      .or(`name.ilike.%${q}%,sku.ilike.%${q}%`)
      .limit(12)
    setProductResults(data || [])
  }, [])

  // [Bug-2 Fix] search purchase_invoices by number, filter by supplier if selected
  const searchInvoices = useCallback(async (q: string) => {
    if (q.length < 2) { setInvoiceResults([]); return }
    let query = supabase
      .from('purchase_invoices')
      .select('id, number, total_amount, status')
      .in('status', ['received', 'billed', 'paid'])
      .ilike('number', `%${q}%`)
      .limit(10)
    if (supplierId) query = query.eq('supplier_id', supplierId)
    const { data } = await query
    setInvoiceResults(data || [])
  }, [supplierId])

  // ─── Load existing return ──────────────────────────────────

  useEffect(() => {
    if (!id) return
    ;(async () => {
      try {
        setLoading(true)
        const ret = await getPurchaseReturn(id)
        setReturnData(ret)
        setSupplierId(ret.supplier_id)
        setWarehouseId(ret.warehouse_id)
        setOriginalInvoiceId(ret.original_invoice_id || '')
        // [Bug-2 Fix] restore invoice display label
        if (ret.original_invoice) {
          setSelectedInvoiceLabel((ret.original_invoice as any).number || '')
        }
        setReturnDate(ret.return_date)
        setNotes(ret.notes || '')
        if (ret.supplier) setSelectedSupplier(ret.supplier as Supplier)

        // Hydrate lines (for display in draft mode)
        if (ret.items && ret.items.length > 0) {
          setReturnLines(ret.items.map(item => ({
            _key:                    item.id,
            product_id:              item.product_id,
            productName:             item.product?.name || '',
            unit_id:                 item.unit_id || '',
            unitName:                item.unit?.name || '',
            base_last_purchase_price: item.unit_price, // best approximation when re-loading
            availableUnits:          [],
            quantity:                item.quantity,
            unit_price:              item.unit_price,
            discount_rate:           item.discount_rate,
            tax_rate:                item.tax_rate,
          })))
        }
      } catch (err: any) {
        toast.error(err.message)
        navigate('/purchases/returns')
      } finally {
        setLoading(false)
      }
    })()
  }, [id])

  // ─── Product select (per line) ────────────────────────────

  const selectProduct = async (idx: number, prod: any) => {
    const baseUnit = prod.base_unit || {}
    const purchaseUnits = (prod.product_units || []).filter((u: any) => u.is_purchase_unit)

    // Fallback: last_purchase_price -> global_wac -> cost_price -> 0
    // All three come from the RPC (never from the products query)
    let baseLpp: number = 0
    if (can('finance.view_costs')) {
      try {
        const metrics = await getProductCostMetrics([prod.id])
        const m = metrics[prod.id]
        if (m) {
          if (m.last_purchase_price != null) {
            baseLpp = m.last_purchase_price
          } else if (m.global_wac != null) {
            baseLpp = m.global_wac
          } else if (m.cost_price != null) {
            baseLpp = m.cost_price
          }
        }
      } catch { /* ignore — user gets 0 */ }
    }

    const allUnits = [
      { unit_id: prod.base_unit_id, unit_name: baseUnit.name || '', unit_symbol: baseUnit.symbol || '', conversion_factor: 1, purchase_price: baseLpp },
      ...purchaseUnits.map((pu: any) => ({
        unit_id: pu.unit_id,
        unit_name: pu.unit?.name || '',
        unit_symbol: pu.unit?.symbol || '',
        conversion_factor: pu.conversion_factor,
        // explicit purchase_price on the unit, or derive: base × conversion
        purchase_price: pu.selling_price ?? null,
      })),
    ]

    // Default to first purchase unit, price derived correctly
    let defaultUnitId   = prod.base_unit_id
    let defaultUnitName = baseUnit.name || ''
    let defaultPrice    = baseLpp

    if (purchaseUnits.length > 0) {
      const pu = purchaseUnits[0]
      defaultUnitId   = pu.unit_id
      defaultUnitName = pu.unit?.name || ''
      // if explicit price → use it; else base × factor
      defaultPrice = pu.selling_price != null ? pu.selling_price : baseLpp * pu.conversion_factor
    }

    setReturnLines(prev => prev.map((line, i) => i !== idx ? line : {
      ...line,
      product_id: prod.id,
      productName: prod.name,
      unit_id: defaultUnitId,
      unitName: defaultUnitName,
      base_last_purchase_price: baseLpp,
      availableUnits: allUnits,
      unit_price: defaultPrice,
      tax_rate: prod.tax_rate ?? 0,
    }))
    setProductResults([])
    setActiveProductIdx(null)
  }

  const updateLine = (idx: number, field: keyof ReturnLine, value: any) => {
    setReturnLines(prev => prev.map((l, i) => i !== idx ? l : { ...l, [field]: value }))
  }

  // [Bug-1 Fix] changeUnit: recalculates unit_price based on conversion_factor
  const changeUnit = (idx: number, newUnitId: string) => {
    setReturnLines(prev => prev.map((line, i) => {
      if (i !== idx) return line
      const sel = line.availableUnits.find(u => u.unit_id === newUnitId)
      if (!sel) return line
      // If unit has an explicit purchase_price → use it; else base_lpp × factor
      const newPrice = sel.purchase_price != null
        ? sel.purchase_price
        : line.base_last_purchase_price * sel.conversion_factor
      return { ...line, unit_id: sel.unit_id, unitName: sel.unit_name, unit_price: newPrice }
    }))
  }
  const removeLine = (idx: number) => {
    if (returnLines.length === 1) return
    setReturnLines(prev => prev.filter((_, i) => i !== idx))
  }

  // ─── Live totals via useMemo (no API spam) ─────────────────

  const totals = useMemo(() => {
    let displaySubtotal = 0
    let displayDiscount = 0
    let displayTax      = 0
    for (const l of returnLines) {
      if (!l.product_id) continue
      const gross    = l.quantity * l.unit_price
      const discount = gross * (l.discount_rate / 100)
      const net      = gross - discount
      const tax      = net * (l.tax_rate / 100)
      displaySubtotal += gross
      displayDiscount += discount
      displayTax      += tax
    }
    const displayTotal = displaySubtotal - displayDiscount + displayTax
    return { displaySubtotal, displayDiscount, displayTax, displayTotal }
  }, [returnLines])

  // ─── Derived mode ──────────────────────────────────────────

  const mode = isNew ? 'new' : (returnData?.status === 'confirmed' ? 'confirmed' : 'draft')
  const isReadOnly = mode === 'confirmed'

  // ─── Save draft ───────────────────────────────────────────

  const handleSaveDraft = async () => {
    if (!supplierId) { toast.error('اختر المورد أولاً'); return }
    if (!warehouseId) { toast.error('اختر المخزن أولاً'); return }
    const validLines = returnLines.filter(l => l.product_id && l.quantity > 0 && l.unit_price >= 0)
    if (validLines.length === 0) { toast.error('أضف منتجاً واحداً على الأقل'); return }

    setSaving(true)
    try {
      const header = {
        supplier_id: supplierId, warehouse_id: warehouseId,
        original_invoice_id: originalInvoiceId || null,
        return_date: returnDate, notes: notes || null,
      }
      const items: PurchaseReturnItemInput[] = validLines.map(l => ({
        product_id: l.product_id, unit_id: l.unit_id || null,
        quantity: l.quantity, unit_price: l.unit_price,
        discount_rate: l.discount_rate, tax_rate: l.tax_rate,
      }))

      if (isNew) {
        const ret = await createPurchaseReturn(header, items)
        toast.success('تم حفظ مسودة المرتجع')
        navigate(`/purchases/returns/${ret.id}`, { replace: true })
      } else {
        await updatePurchaseReturn(returnData!.id, header, items)
        const updated = await getPurchaseReturn(returnData!.id)
        setReturnData(updated)
        toast.success('تم تحديث المرتجع')
      }
    } catch (err: any) {
      toast.error(err.message || 'فشل حفظ المرتجع')
    } finally {
      setSaving(false)
    }
  }

  // ─── Confirm return ───────────────────────────────────────

  const handleConfirm = async () => {
    if (!returnData) return
    const ok = window.confirm(
      'تأكيد: سيتم خصم البضاعة من المخزن واعتماد القيد المحاسبي.\nهل أنت متأكد؟'
    )
    if (!ok) return

    setConfirming(true)
    try {
      await confirmPurchaseReturn(returnData.id)
      toast.success('تم تأكيد المرتجع المالي والمخزني بنجاح')
      const updated = await getPurchaseReturn(returnData.id)
      setReturnData(updated)
    } catch (err: any) {
      toast.error(err.message || 'فشل تأكيد المرتجع')
    } finally {
      setConfirming(false)
    }
  }

  // ─── Loading state ─────────────────────────────────────────

  if (loading) return (
    <div style={{ padding: 'var(--space-6)' }}>
      {[1, 2, 3].map(i => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 12, height: 48 }} />)}
    </div>
  )

  const pageTitle = isNew
    ? 'مرتجع مشتريات جديد'
    : returnData?.number || 'مرتجع مشتريات'

  return (
    <div style={{ padding: 'var(--space-4)', maxWidth: 1200, margin: '0 auto', animation: 'fade-in 0.3s ease' }}>
      {/* ══ Header ══════════════════════════════════════════════ */}
      <PageHeader
        title={pageTitle}
        subtitle="تسجيل مرتجع بضاعة للمورد مع تسوية محاسبية"
        breadcrumbs={[
          { label: 'المشتريات' },
          { label: 'مرتجعات المشتريات', path: '/purchases/returns' },
          { label: pageTitle },
        ]}
        actions={
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            {returnData?.status && <StatusBadge status={returnData.status} />}
            <Button variant="ghost" icon={<ArrowRight size={16} />} onClick={() => navigate('/purchases/returns')}>
              رجوع
            </Button>
          </div>
        }
      />

      {/* ══ Header fields card ══════════════════════════════════ */}
      <div style={sCard}>
        <SectionHead icon={<FileText size={16} />} title="بيانات المرتجع" />
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 16 }}>

          {/* Supplier */}
          <div>
            <FieldLabel required>المورد</FieldLabel>
            <InlineCombobox
              placeholder="ابحث عن مورد..."
              items={supplierResults.map(s => ({ id: s.id, primary: s.name, secondary: s.code }))}
              onSearch={searchSuppliers}
              onSelect={item => { setSupplierId(item.id); setSelectedSupplier(supplierResults.find(s => s.id === item.id) || null) }}
              onClear={() => { setSupplierId(''); setSelectedSupplier(null) }}
              selected={!!supplierId}
              selectedLabel={selectedSupplier?.name}
              disabled={isReadOnly}
            />
          </div>

          {/* Warehouse */}
          <div>
            <FieldLabel required>المخزن</FieldLabel>
            <select
              className="form-input"
              value={warehouseId}
              onChange={e => setWarehouseId(e.target.value)}
              disabled={isReadOnly}
            >
              <option value="">-- اختر المخزن --</option>
              {(isAdmin ? warehouses : (myWarehouses.length > 0 ? myWarehouses : warehouses)).map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </div>

          {/* Original Invoice — [Bug-2 Fix] UUID Combobox, not text input */}
          <div>
            <FieldLabel>الفاتورة الأصلية (اختياري)</FieldLabel>
            <InlineCombobox
              placeholder="ابحث برقم الفاتورة..."
              items={invoiceResults.map((inv: any) => ({
                id: inv.id,
                primary: inv.number,
                secondary: `${formatNumber(inv.total_amount)} ج.م — ${inv.status}`,
              }))}
              onSearch={searchInvoices}
              onSelect={item => {
                setOriginalInvoiceId(item.id)  // UUID
                setSelectedInvoiceLabel(item.primary)
              }}
              onClear={() => { setOriginalInvoiceId(''); setSelectedInvoiceLabel('') }}
              selected={!!originalInvoiceId}
              selectedLabel={selectedInvoiceLabel}
              disabled={isReadOnly}
            />
          </div>

          {/* Return Date */}
          <div>
            <FieldLabel required>تاريخ المرتجع</FieldLabel>
            <input
              type="date"
              className="form-input"
              value={returnDate}
              onChange={e => setReturnDate(e.target.value)}
              disabled={isReadOnly}
            />
          </div>

          {/* Notes (full width) */}
          <div style={{ gridColumn: '1 / -1' }}>
            <FieldLabel>ملاحظات</FieldLabel>
            <textarea
              className="form-input"
              rows={2}
              value={notes}
              onChange={e => setNotes(e.target.value)}
              placeholder="سبب الإرجاع، حالة البضاعة..."
              disabled={isReadOnly}
              style={{ resize: 'vertical' }}
            />
          </div>
        </div>
      </div>

      {/* ══ Settlement Summary (confirmed only) ════════════════ */}
      {mode === 'confirmed' && returnData && (
        <div style={{
          ...sCard,
          background: 'linear-gradient(135deg, rgba(22,163,74,0.08), rgba(5,150,105,0.05))',
          border: '1.5px solid rgba(22,163,74,0.25)',
        }}>
          <SectionHead icon={<TrendingDown size={16} />} title="ملخص التسوية المالية" />
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 16 }}>
            {[
              { label: 'الإجمالي قبل الخصم', value: returnData.subtotal },
              { label: 'إجمالي الخصم',        value: returnData.discount_amount },
              { label: 'ضريبة القيمة المضافة', value: returnData.tax_amount },
              { label: 'إجمالي المرتجع',       value: returnData.total_amount, highlight: true },
            ].map(({ label, value, highlight }) => (
              <div key={label} style={{
                textAlign: 'center', padding: '12px 8px',
                background: highlight ? 'rgba(22,163,74,0.12)' : 'var(--bg-surface)',
                borderRadius: 10, border: `1px solid ${highlight ? 'rgba(22,163,74,0.3)' : 'var(--border-color)'}`,
              }}>
                <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginBottom: 4 }}>{label}</div>
                <div style={{ fontSize: highlight ? '1.15rem' : '1rem', fontWeight: 700, color: highlight ? '#166534' : 'var(--text-primary)' }}>
                  {formatNumber(value)} ج.م
                </div>
              </div>
            ))}
          </div>
          {returnData.confirmed_at && (
            <div style={{ marginTop: 12, fontSize: '0.78rem', color: 'var(--text-muted)', display: 'flex', gap: 8, alignItems: 'center' }}>
              <CheckCircle size={13} />
              تم التأكيد بتاريخ: {new Date(returnData.confirmed_at).toLocaleString('ar-EG-u-nu-latn')}
            </div>
          )}
        </div>
      )}

      {/* ══ Items Grid ══════════════════════════════════════════ */}
      <div style={sCard}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
          <SectionHead icon={<Package size={16} />} title="بنود المرتجع" />
          {!isReadOnly && (
            <button
              type="button"
              onClick={() => setReturnLines(prev => [...prev, newLine()])}
              style={{
                display: 'flex', alignItems: 'center', gap: 6, padding: '6px 14px',
                background: 'var(--color-primary-light)', color: 'var(--color-primary)',
                border: '1px dashed var(--color-primary)', borderRadius: 8,
                cursor: 'pointer', fontWeight: 600, fontSize: '0.82rem', fontFamily: 'var(--font-sans)',
              }}
            >
              <Plus size={14} /> إضافة منتج
            </button>
          )}
        </div>

        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.84rem' }}>
            <thead>
              <tr style={{ background: 'linear-gradient(90deg, rgba(220,38,38,0.08), rgba(185,28,28,0.05))', borderBottom: '2px solid rgba(220,38,38,0.2)' }}>
                <th style={{ ...thStyle(40), textAlign: 'center' }}>#</th>
                <th style={thStyle(260)}>المنتج</th>
                <th style={thStyle(130)}>الوحدة</th>
                <th style={thStyle(90)}>الكمية</th>
                <th style={thStyle(110)}>سعر الإرجاع</th>
                <th style={thStyle(80)}>خصم %</th>
                <th style={thStyle(80)}>ضريبة %</th>
                <th style={{ ...thStyle(120), textAlign: 'left' }}>الإجمالي</th>
                {!isReadOnly && <th style={thStyle(44)} />}
              </tr>
            </thead>
            <tbody>
              {returnLines.map((line, idx) => {
                const gross    = line.quantity * line.unit_price
                const discount = gross * (line.discount_rate / 100)
                const net      = gross - discount
                const lineTotal = net * (1 + line.tax_rate / 100)
                const isEven   = idx % 2 === 1

                return (
                  <tr
                    key={line._key}
                    style={{ background: isEven ? 'var(--bg-surface-2)' : 'var(--bg-surface)', borderBottom: '1px solid var(--border-color)' }}
                  >
                    {/* Row Number */}
                    <td style={{ padding: '8px 12px', textAlign: 'center', color: 'var(--text-muted)', fontWeight: 600, fontSize: '0.78rem' }}>
                      {idx + 1}
                    </td>

                    {/* Product */}
                    <td style={{ padding: '6px 10px', position: 'relative' }}>
                      {line.product_id ? (
                        <div style={{
                          display: 'flex', alignItems: 'center', gap: 6, padding: '6px 10px',
                          background: 'rgba(37,99,235,0.06)', border: '1.5px solid var(--color-primary)',
                          borderRadius: 7, fontWeight: 600, fontSize: '0.82rem',
                        }}>
                          <span style={{ flex: 1 }}>{line.productName}</span>
                          {!isReadOnly && (
                            <button type="button" onClick={() => updateLine(idx, 'product_id', '')}
                              style={{ background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', padding: 2 }}>
                              <X size={12} />
                            </button>
                          )}
                        </div>
                      ) : (
                        <div style={{ position: 'relative' }}>
                          <Search size={13} style={{ position: 'absolute', right: 8, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
                          <input
                            className="form-input"
                            style={{ paddingRight: 28, fontSize: '0.82rem' }}
                            placeholder="ابحث عن منتج..."
                            onChange={e => { setActiveProductIdx(idx); searchProducts(e.target.value) }}
                            autoComplete="off"
                          />
                          {activeProductIdx === idx && productResults.length > 0 && (
                            <div style={{
                              position: 'absolute', zIndex: 999, top: 'calc(100% + 4px)', left: 0, right: 0,
                              background: 'var(--bg-surface)', border: '1px solid var(--border-color)',
                              borderRadius: 10, boxShadow: '0 12px 40px rgba(0,0,0,0.15)', maxHeight: 220, overflowY: 'auto',
                            }}>
                              {productResults.map((p, pi) => (
                                <div
                                  key={p.id}
                                  onMouseDown={e => { e.preventDefault(); selectProduct(idx, p) }}
                                  style={{ padding: '9px 12px', cursor: 'pointer', borderBottom: pi < productResults.length - 1 ? '1px solid var(--border-color)' : 'none' }}
                                  onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
                                  onMouseLeave={e => (e.currentTarget.style.background = '')}
                                >
                                  <div style={{ fontWeight: 600, fontSize: '0.82rem' }}>{p.name}</div>
                                  <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>
                                    {p.sku}
                                  </div>
                                </div>
                              ))}
                            </div>
                          )}
                        </div>
                      )}
                    </td>

                    {/* Unit — [Bug-1 Fix] use changeUnit to recalculate price */}
                    <td style={{ padding: '6px 8px' }}>
                      {line.availableUnits.length > 1 ? (
                        <select
                          className="form-input"
                          style={{ fontSize: '0.82rem' }}
                          value={line.unit_id}
                          onChange={e => changeUnit(idx, e.target.value)}
                          disabled={isReadOnly}
                        >
                          {line.availableUnits.map(u => <option key={u.unit_id} value={u.unit_id}>{u.unit_name}</option>)}
                        </select>
                      ) : (
                        <div style={{ padding: '6px 10px', fontSize: '0.82rem', color: 'var(--text-muted)' }}>
                          {line.unitName || '—'}
                        </div>
                      )}
                    </td>

                    {/* Quantity */}
                    <td style={{ padding: '6px 8px' }}>
                      <input
                        type="number" className="form-input" min={0.01} step="0.01"
                        style={{ textAlign: 'center', fontSize: '0.82rem' }}
                        value={line.quantity}
                        onChange={e => updateLine(idx, 'quantity', parseFloat(e.target.value) || 0)}
                        disabled={isReadOnly}
                      />
                    </td>

                    {/* Unit Price */}
                    <td style={{ padding: '6px 8px' }}>
                      <input
                        type="number" className="form-input" min={0} step="0.01"
                        style={{ textAlign: 'center', fontSize: '0.82rem' }}
                        value={line.unit_price}
                        onChange={e => updateLine(idx, 'unit_price', parseFloat(e.target.value) || 0)}
                        disabled={isReadOnly}
                      />
                    </td>

                    {/* Discount % */}
                    <td style={{ padding: '6px 8px' }}>
                      <input
                        type="number" className="form-input" min={0} max={100} step="0.1"
                        style={{ textAlign: 'center', fontSize: '0.82rem' }}
                        value={line.discount_rate}
                        onChange={e => updateLine(idx, 'discount_rate', parseFloat(e.target.value) || 0)}
                        disabled={isReadOnly}
                      />
                    </td>

                    {/* Tax % */}
                    <td style={{ padding: '6px 8px' }}>
                      <input
                        type="number" className="form-input" min={0} max={100} step="0.1"
                        style={{ textAlign: 'center', fontSize: '0.82rem' }}
                        value={line.tax_rate}
                        onChange={e => updateLine(idx, 'tax_rate', parseFloat(e.target.value) || 0)}
                        disabled={isReadOnly}
                      />
                    </td>

                    {/* Line Total */}
                    <td style={{ padding: '8px 12px', textAlign: 'left', fontWeight: 700, color: lineTotal > 0 ? 'var(--color-primary)' : 'var(--text-muted)', whiteSpace: 'nowrap' }}>
                      {formatNumber(lineTotal)} ج.م
                    </td>

                    {/* Delete */}
                    {!isReadOnly && (
                      <td style={{ padding: '6px 4px', textAlign: 'center' }}>
                        <button
                          type="button" onClick={() => removeLine(idx)}
                          disabled={returnLines.length === 1}
                          style={{
                            background: 'none', border: 'none', cursor: returnLines.length === 1 ? 'default' : 'pointer',
                            color: returnLines.length === 1 ? 'var(--border-color)' : 'var(--color-danger)',
                            padding: 6, borderRadius: 6, display: 'flex', alignItems: 'center',
                          }}
                        >
                          <Trash2 size={15} />
                        </button>
                      </td>
                    )}
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>

        {/* ─── Totals Footer ─── */}
        <div style={{
          marginTop: 16,
          background: 'linear-gradient(135deg, rgba(37,99,235,0.07), rgba(109,40,217,0.04))',
          border: '1px solid rgba(37,99,235,0.15)',
          borderRadius: 12, padding: '14px 20px',
          display: 'flex', gap: 24, flexWrap: 'wrap', justifyContent: 'flex-end',
        }}>
          {[
            { label: 'الإجمالي الخام',  value: totals.displaySubtotal },
            { label: 'إجمالي الخصم',    value: totals.displayDiscount, neg: true },
            { label: 'الضريبة',          value: totals.displayTax },
            { label: 'الإجمالي الكلي',  value: totals.displayTotal, primary: true },
          ].map(({ label, value, neg, primary }) => (
            <div key={label} style={{ textAlign: 'center', minWidth: 110 }}>
              <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', marginBottom: 2 }}>{label}</div>
              <div style={{
                fontWeight: 700,
                fontSize: primary ? '1.1rem' : '0.9rem',
                color: primary ? 'var(--color-primary)' : neg ? 'var(--color-danger)' : 'var(--text-primary)',
              }}>
                {neg && value > 0 ? '-' : ''}{formatNumber(value)} ج.م
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* ══ Action Bar ══════════════════════════════════════════ */}
      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 12, marginTop: 8, flexWrap: 'wrap' }}>
        <Button variant="ghost" onClick={() => navigate('/purchases/returns')}>
          رجوع
        </Button>

        {/* Draft: Save */}
        {!isReadOnly && (
          <Button
            variant="secondary"
            loading={saving}
            icon={<Save size={16} />}
            onClick={handleSaveDraft}
          >
            حفظ المسودة
          </Button>
        )}

        {/* Draft (saved): Confirm */}
        {mode === 'draft' && returnData && can('procurement.returns.confirm') && (
          <Button
            variant="primary"
            loading={confirming}
            icon={<CheckCircle size={16} />}
            onClick={handleConfirm}
          >
            تأكيد المرتجع المالي والمخزني
          </Button>
        )}

        {/* No-permission hint */}
        {mode === 'draft' && returnData && !can('procurement.returns.confirm') && (
          <div style={{
            display: 'flex', alignItems: 'center', gap: 6, padding: '8px 16px',
            borderRadius: 8, background: 'var(--bg-surface-2)', color: 'var(--text-muted)',
            fontSize: '0.8rem', border: '1px solid var(--border-color)',
          }}>
            <AlertTriangle size={14} /> لا تملك صلاحية تأكيد المرتجع
          </div>
        )}
      </div>

      <style>{`
        @keyframes fade-in {
          from { opacity: 0; transform: translateY(8px); }
          to   { opacity: 1; transform: translateY(0); }
        }
      `}</style>
    </div>
  )
}
