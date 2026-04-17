import React, { useState, useEffect, useMemo, useCallback, useRef } from 'react'
import { createPortal } from 'react-dom'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, Plus, Trash2, Save, Package, Search, X,
  CheckCircle, DollarSign, AlertTriangle, Loader2, Building2,
  FileText, Eye, Banknote, XCircle,
} from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import { supabase } from '@/lib/supabase/client'
import { getMyWarehouses } from '@/lib/services/inventory'
import {
  getPurchaseInvoice,
  createPurchaseInvoice,
  updatePurchaseInvoice,
  updateItemReceivedQty,
  updateLandedCosts,
  receivePurchaseInvoice,
  billPurchaseInvoice,
  paySupplier,
} from '@/lib/services/purchases'
import { getProductCostMetrics } from '@/lib/services/products'
import { cancelPurchaseInvoice } from '@/lib/services/purchase-returns'
import { getVaults } from '@/lib/services/vaults'
import { formatNumber } from '@/lib/utils/format'
import type {
  PurchaseInvoice,
  PurchaseInvoiceItemInput,
  PurchaseInvoiceStatus,
  PurchasePaymentMethod,
  Supplier,
  Warehouse,
  Vault,
} from '@/lib/types/master-data'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import { DocumentActions } from '@/features/output/components/DocumentActions'

// ── Step definitions (new/draft mode only) ─────────────────────────
const STEPS = [
  { label: 'المورد واللوجستيات', icon: <Building2 size={14} /> },
  { label: 'المنتجات المستلمة',  icon: <Package size={14} /> },
  { label: 'التكاليف والضرائب', icon: <DollarSign size={14} /> },
  { label: 'مراجعة وحفظ',    icon: <CheckCircle size={14} /> },
]

// ─────────────────────────────────────────────
// Small UI helpers
// ─────────────────────────────────────────────

const sCard: React.CSSProperties = {
  background: 'var(--bg-surface)',
  border: '1px solid var(--border-color)',
  borderRadius: 'var(--radius-lg)',
  padding: '20px 24px',
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

function StatusBadge({ status }: { status: PurchaseInvoiceStatus }) {
  const map: Record<PurchaseInvoiceStatus, { label: string; color: string; bg: string }> = {
    draft:     { label: 'مسودة',    color: '#92400e', bg: '#fef3c7' },
    received:  { label: 'مستلمة',   color: '#1e40af', bg: '#dbeafe' },
    billed:    { label: 'معتمدة',   color: '#6b21a8', bg: '#f3e8ff' },
    paid:      { label: 'مدفوعة',   color: '#166534', bg: '#dcfce7' },
    cancelled: { label: 'ملغاة',    color: '#991b1b', bg: '#fee2e2' },
  }
  const { label, color, bg } = map[status] ?? map.draft
  return (
    <span style={{
      padding: '3px 12px', borderRadius: 99, fontWeight: 700,
      fontSize: '0.78rem', color, background: bg, whiteSpace: 'nowrap',
    }}>{label}</span>
  )
}

// ─── Inline Combobox (matches SalesOrderForm pattern) ─────────────────────────
interface ComboItem { id: string; primary: string; secondary?: string; meta?: string }
interface ComboboxProps {
  placeholder: string
  items: ComboItem[]
  onSearch: (q: string) => void
  onSelect: (item: ComboItem) => void
  onClear?: () => void
  selected?: boolean
  selectedLabel?: string
  disabled?: boolean
}

function InlineCombobox({ placeholder, items, onSearch, onSelect, onClear, selected, selectedLabel, disabled }: ComboboxProps) {
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
        background: disabled ? 'var(--bg-surface-2)' : 'rgba(37,99,235,0.07)',
        border: `1.5px solid ${disabled ? 'var(--border-color)' : 'var(--color-primary)'}`,
        borderRadius: 8, minHeight: 42,
      }}>
        <div style={{ flex: 1, fontWeight: 600, fontSize: '0.875rem', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {selectedLabel}
        </div>
        {onClear && !disabled && (
          <button onClick={onClear} type="button" style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', padding: 4, display: 'flex', alignItems: 'center' }}>
            <X size={14} />
          </button>
        )}
      </div>
    )
  }

  if (disabled) {
    return (
      <div className="form-input" style={{ background: 'var(--bg-surface-2)', color: 'var(--text-muted)', cursor: 'default', minHeight: 42 }}>
        {placeholder}
      </div>
    )
  }

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
          borderRadius: 10, boxShadow: '0 12px 40px rgba(0,0,0,0.15)',
          maxHeight: 260, overflowY: 'auto',
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
              {item.meta && <div style={{ fontSize: '0.75rem', color: 'var(--color-primary)', fontWeight: 600 }}>{item.meta}</div>}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ─── PurchaseProductComboCell — Portal-based product search for table rows ─────
/**
 * مخصص فقط لخلية المنتج في جدول البنود.
 * يستخدم createPortal لرسم القائمة المنسدلة في document.body
 * حتى لا يُقطع بـ overflow:auto على حاوية الجدول.
 * لا يُعدَّل InlineCombobox الخاص باختيار المورد.
 */
interface PurchaseProductComboCellProps {
  productQuery: string
  productResults: any[]
  onSearch: (q: string) => void
  onSelect: (p: any) => void
  onFocus: () => void
  onBlur: () => void
}

function PurchaseProductComboCell({
  productQuery, productResults, onSearch, onSelect, onFocus, onBlur,
}: PurchaseProductComboCellProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [dropPos, setDropPos] = useState<{ top: number; left: number; width: number } | null>(null)

  // احسب موضع الـ dropdown كلما تغيرت النتائج
  useEffect(() => {
    if (productResults.length === 0) { setDropPos(null); return }
    if (!inputRef.current) return
    const rect = inputRef.current.getBoundingClientRect()
    setDropPos({
      top: rect.bottom + window.scrollY + 4,
      left: rect.left + window.scrollX,
      width: Math.max(rect.width, 300),
    })
  }, [productResults])

  // أعد الحساب عند Scroll أو Resize
  useEffect(() => {
    if (!dropPos) return
    const recalc = () => {
      if (!inputRef.current) return
      const rect = inputRef.current.getBoundingClientRect()
      setDropPos({
        top: rect.bottom + window.scrollY + 4,
        left: rect.left + window.scrollX,
        width: Math.max(rect.width, 300),
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

      {/* Portal Dropdown — يُرسَم في document.body خارج أي overflow container */}
      {dropPos && productResults.length > 0 && createPortal(
        <div style={{
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
        }}>
          {productResults.map((p, i) => (
            <div
              key={p.id}
              onMouseDown={e => { e.preventDefault(); onSelect(p) }}
              style={{
                padding: '10px 14px',
                cursor: 'pointer',
                borderBottom: i < productResults.length - 1 ? '1px solid var(--border-color)' : 'none',
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                gap: 12,
                transition: 'background 0.12s',
              }}
              onMouseEnter={e => { e.currentTarget.style.background = 'var(--bg-hover)' }}
              onMouseLeave={e => (e.currentTarget.style.background = '')}
            >
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontWeight: 600, fontSize: '0.875rem', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {p.name}
                </div>
                <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', fontFamily: 'monospace', marginTop: 2 }}>
                  {p.sku}
                </div>
              </div>
            </div>
          ))}
        </div>,
        document.body
      )}
    </div>
  )
}

// ─────────────────────────────────────────────
// Line item state type
// ─────────────────────────────────────────────

interface AvailableUnit {
  unit_id: string
  unit_name: string
  unit_symbol: string
  conversion_factor: number
  purchase_price: number | null   // null = حسابي (base × conversion)
}

interface DraftLine {
  _key: string
  product_id: string
  productName: string
  productSku: string
  // Unit support
  unit_id: string | null
  unitLabel: string
  available_units: AvailableUnit[]
  base_unit_id: string
  conversion_factor: number
  base_last_purchase_price: number  // سعر الشراء للوحدة الأساسية — لإعادة الحساب عند تغيير الوحدة
  // Pricing + discounts
  ordered_quantity: number
  unit_price: number
  discount_rate: number
  tax_rate: number
  // Computed
  lineSubtotal: number
  lineDiscount: number
  lineTax: number
  lineTotal: number
}

interface ReceiveLine extends DraftLine {
  item_id: string
  received_quantity: number
}

function calcDraftLine(l: DraftLine): DraftLine {
  const sub  = Math.round(l.ordered_quantity * l.unit_price * 100) / 100
  const disc = Math.round(sub * l.discount_rate / 100 * 100) / 100
  const afterDisc = sub - disc
  const tax  = Math.round(afterDisc * l.tax_rate / 100 * 100) / 100
  return { ...l, lineSubtotal: sub, lineDiscount: disc, lineTax: tax, lineTotal: afterDisc + tax }
}

function newDraftLine(): DraftLine {
  return {
    _key: crypto.randomUUID(),
    product_id: '', productName: '', productSku: '',
    unit_id: null, unitLabel: '', available_units: [],
    base_unit_id: '', conversion_factor: 1, base_last_purchase_price: 0,
    ordered_quantity: 1, unit_price: 0, discount_rate: 0, tax_rate: 0,
    lineSubtotal: 0, lineDiscount: 0, lineTax: 0, lineTotal: 0,
  }
}

// ─────────────────────────────────────────────
// Main Component
// ─────────────────────────────────────────────

export default function PurchaseInvoiceForm() {
  const { id } = useParams<{ id?: string }>()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const isAdmin = can('inventory.read_all')

  const isNew = !id
  const [loading, setLoading] = useState(!isNew)
  const [saving, setSaving] = useState(false)
  const [cancelling, setCancelling] = useState(false)
  const [invoice, setInvoice] = useState<PurchaseInvoice | null>(null)

  // ── Stepper state (only active in new/draft mode) ───────────────────
  const [step, setStep] = useState(0)

  // ── Mobile item-add sheet ─────────────────────────────────────
  const [itemSheet, setItemSheet] = useState(false)
  const [sheetQuery, setSheetQuery] = useState('')
  const [sheetResults, setSheetResults] = useState<any[]>([])
  const [sheetDraftLine, setSheetDraftLine] = useState<DraftLine | null>(null)

  const searchSheetProducts = useCallback(async (q: string) => {
    if (q.length < 2) { setSheetResults([]); return }
    const { data } = await supabase
      .from('products')
      .select(`id, name, sku, tax_rate,
        base_unit_id,
        base_unit:units!products_base_unit_id_fkey(id, name, symbol),
        product_units(id, unit_id, conversion_factor, selling_price, is_purchase_unit, unit:units(id, name, symbol))`)
      .eq('is_active', true)
      .or(`name.ilike.%${q}%,sku.ilike.%${q}%`)
      .limit(10)
    setSheetResults(data || [])
  }, [])

  const selectSheetProduct = async (p: any) => {
    const baseUnitId = p.base_unit_id || ''
    const baseSymbol = p.base_unit?.symbol || p.base_unit?.name || ''

    // Fallback: last_purchase_price -> global_wac -> cost_price -> 0
    // All three come from the RPC (never from the products query)
    let basePrice: number = 0
    if (can('finance.view_costs')) {
      try {
        const metrics = await getProductCostMetrics([p.id])
        const m = metrics[p.id]
        if (m) {
          if (m.last_purchase_price != null) {
            basePrice = m.last_purchase_price
          } else if (m.global_wac != null) {
            basePrice = m.global_wac
          } else if (m.cost_price != null) {
            basePrice = m.cost_price
          }
        }
      } catch { /* ignore — user gets 0 */ }
    }
    const allUnits: AvailableUnit[] = []
    if (p.base_unit_id) allUnits.push({ unit_id: p.base_unit_id, unit_name: p.base_unit?.name || '', unit_symbol: baseSymbol, conversion_factor: 1, purchase_price: null })
    for (const pu of (p.product_units || [])) {
      if (pu.unit_id === p.base_unit_id) continue
      allUnits.push({ unit_id: pu.unit_id, unit_name: pu.unit?.name || '', unit_symbol: pu.unit?.symbol || pu.unit?.name || '', conversion_factor: pu.conversion_factor || 1, purchase_price: pu.selling_price ?? null })
    }
    setSheetDraftLine(calcDraftLine({
      ...newDraftLine(),
      product_id: p.id, productName: p.name, productSku: p.sku,
      unit_id: baseUnitId || null, unitLabel: baseSymbol,
      available_units: allUnits, base_unit_id: baseUnitId,
      conversion_factor: 1, base_last_purchase_price: basePrice,
      unit_price: basePrice, tax_rate: p.tax_rate || 0,
    }))
    setSheetQuery('')
    setSheetResults([])
  }

  const confirmSheetLine = () => {
    if (!sheetDraftLine || !sheetDraftLine.product_id) return
    setDraftLines(prev => [...prev.filter(l => l.product_id), calcDraftLine(sheetDraftLine)])
    setSheetDraftLine(null)
    setSheetQuery('')
    setItemSheet(false)
  }

  // ─── Vault list (for bill/pay panels) ──────────────────────────────
  const [vaults, setVaults] = useState<Vault[]>([])
  useEffect(() => {
    getVaults({ isActive: true }).then(r => setVaults(Array.isArray(r) ? r : (r as any).data || [])).catch(() => {})
  }, [])

  // ─── Supplier search ────────────────────────────────────────────────
  const [selectedSupplier, setSelectedSupplier] = useState<Supplier | null>(null)
  const [supplierResults, setSupplierResults] = useState<Supplier[]>([])

  const searchSuppliers = useCallback(async (q: string) => {
    if (q.length < 2) { setSupplierResults([]); return }
    const { data } = await supabase
      .from('suppliers')
      .select('id, name, code, phone')
      .eq('is_active', true)
      .or(`name.ilike.%${q}%,code.ilike.%${q}%,phone.ilike.%${q}%`)
      .limit(10)
    setSupplierResults(data as Supplier[] || [])
  }, [])

  // ─── Warehouse list ─────────────────────────────────────────────────
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [myWarehouses, setMyWarehouses] = useState<Warehouse[]>([])
  useEffect(() => {
    // جلب كل المخازن للقائمة + مخازن المستخدم للافتراضي
    supabase.from('warehouses').select('id, name').eq('is_active', true).order('name')
      .then(({ data }) => setWarehouses(data as Warehouse[] || []))
    // نجلب دائماً — حتى لو isAdmin — لأن الأدمن قد يملك مخزناً شخصياً
    getMyWarehouses().then(whs => {
      setMyWarehouses(whs)
      // تعيين المخزن الافتراضي للفاتورة الجديدة
      if (isNew && whs.length > 0) setWarehouseId(whs[0].id)
    }).catch(() => {})
  }, [])

  // ─── Product search ─────────────────────────────────────────────────
  const [productResults, setProductResults] = useState<any[]>([])
  const [activeProductIdx, setActiveProductIdx] = useState<number | null>(null)
  const [productQuery, setProductQuery] = useState('')

  const searchProducts = useCallback(async (q: string) => {
    if (q.length < 2) { setProductResults([]); return }
    const { data } = await supabase
      .from('products')
      .select(`
        id, name, sku, tax_rate,
        base_unit_id,
        base_unit:units!products_base_unit_id_fkey(id, name, symbol),
        product_units(
          id, unit_id, conversion_factor, selling_price, is_purchase_unit,
          unit:units(id, name, symbol)
        )
      `)
      .eq('is_active', true)
      .or(`name.ilike.%${q}%,sku.ilike.%${q}%`)
      .limit(12)
    setProductResults(data || [])
  }, [])

  // ─── Draft mode state ───────────────────────────────────────────────
  const [supplierId, setSupplierId] = useState('')
  const [warehouseId, setWarehouseId] = useState('')
  const [invoiceDate, setInvoiceDate] = useState(new Date().toISOString().split('T')[0])
  const [supplierRef, setSupplierRef] = useState('')
  const [notes, setNotes] = useState('')
  const [draftLines, setDraftLines] = useState<DraftLine[]>([newDraftLine()])

  // ─── Receive mode state ─────────────────────────────────────────────
  const [receiveLines, setReceiveLines] = useState<ReceiveLine[]>([])
  const [landedCosts, setLandedCosts] = useState(0)

  // ─── Cancelling state ───────────────────────────────────────────────
  // (handled inline above, state declared with saving)

  // ─── fetchInvoice — refetch after cancel/state-change ──────────────
  const fetchInvoice = async (invoiceId: string) => {
    try {
      const inv = await getPurchaseInvoice(invoiceId)
      setInvoice(inv)
    } catch { /* ignore */ }
  }

  // ─── Bill/Pay mode state ────────────────────────────────────────────
  const [paymentMethod, setPaymentMethod] = useState<PurchasePaymentMethod | 'deferred'>('deferred')
  const [billVaultId, setBillVaultId] = useState('')

  // ─── Load existing invoice ──────────────────────────────────────────
  useEffect(() => {
    if (!id) return
    ;(async () => {
      try {
        setLoading(true)
        const inv = await getPurchaseInvoice(id)
        setInvoice(inv)
        // Hydrate draft fields (for display even in non-draft modes)
        setSupplierId(inv.supplier_id)
        setWarehouseId(inv.warehouse_id)
        setInvoiceDate(inv.invoice_date)
        setSupplierRef(inv.supplier_invoice_ref || '')
        setNotes(inv.notes || '')
        setLandedCosts(inv.landed_costs || 0)
        if (inv.supplier) setSelectedSupplier(inv.supplier as any)
        // Hydrate draft lines
        if (inv.items?.length) {
          const lines: DraftLine[] = inv.items.map(item => calcDraftLine({
            _key: item.id,
            product_id: item.product_id,
            productName: item.product?.name || '',
            productSku: item.product?.sku || '',
            unit_id: item.unit_id,
            unitLabel: item.unit?.symbol || item.unit?.name || '',
            // Unit fields (not in DB item, will be empty on load — OK for view/receive)
            available_units: [],
            base_unit_id: item.unit_id || '',
            conversion_factor: 1,
            base_last_purchase_price: item.unit_price,
            ordered_quantity: item.ordered_quantity,
            unit_price: item.unit_price,
            discount_rate: item.discount_rate,
            tax_rate: item.tax_rate,
            lineSubtotal: 0, lineDiscount: 0, lineTax: 0, lineTotal: 0,
          }))
          setDraftLines(lines)
          // Hydrate receive lines (defaults: received = ordered)
          const rLines: ReceiveLine[] = inv.items.map(item => ({
            ...calcDraftLine({
              _key: item.id,
              product_id: item.product_id,
              productName: item.product?.name || '',
              productSku: item.product?.sku || '',
              unit_id: item.unit_id,
              unitLabel: item.unit?.symbol || item.unit?.name || '',
              available_units: [], base_unit_id: item.unit_id || '',
              conversion_factor: 1, base_last_purchase_price: item.unit_price,
              ordered_quantity: item.ordered_quantity,
              unit_price: item.unit_price,
              discount_rate: item.discount_rate,
              tax_rate: item.tax_rate,
              lineSubtotal: 0, lineDiscount: 0, lineTax: 0, lineTotal: 0,
            }),
            item_id: item.id,
            received_quantity: item.received_quantity ?? item.ordered_quantity,
          }))
          setReceiveLines(rLines)
        }
      } catch {
        toast.error('فشل تحميل الفاتورة')
        navigate('/purchases/invoices')
      } finally {
        setLoading(false)
      }
    })()
  }, [id])

  // ─── Computed totals (draft mode) ──────────────────────────────────
  const draftTotals = useMemo(() => {
    const subtotal = draftLines.reduce((s, l) => s + l.lineSubtotal, 0)
    const discount = draftLines.reduce((s, l) => s + l.lineDiscount, 0)
    const tax      = draftLines.reduce((s, l) => s + l.lineTax, 0)
    const total    = subtotal - discount + tax
    return { subtotal, discount, tax, total }
  }, [draftLines])

  const validDraftLines = draftLines.filter(l => l.product_id && l.ordered_quantity > 0)

  // ─── [Flaw 1 Fix] Live receive-mode totals from LOCAL state ────────────────
  // Recalculates instantly on every received_quantity or landedCosts keystroke
  const receiveTotals = useMemo(() => {
    const subtotal = receiveLines.reduce((s, l) => s + l.received_quantity * l.unit_price, 0)
    const discount = receiveLines.reduce(
      (s, l) => s + l.received_quantity * l.unit_price * l.discount_rate / 100, 0
    )
    const afterDisc = subtotal - discount
    const tax = receiveLines.reduce(
      (s, l) => s + (l.received_quantity * l.unit_price * (1 - l.discount_rate / 100)) * l.tax_rate / 100, 0
    )
    const total = afterDisc + tax + landedCosts
    return { subtotal, discount, tax, total }
  }, [receiveLines, landedCosts])

  // ─── [Flaw 3 Fix] Validation guard: any received_qty > ordered_qty ──────────
  const hasReceiveError = receiveLines.some(l => l.received_quantity > l.ordered_quantity)

  // ─── Determine current mode ─────────────────────────────────────────
  type Mode = 'new' | 'draft' | 'receive' | 'bill' | 'readonly'
  const mode: Mode = useMemo(() => {
    if (!invoice) return 'new'
    const s = invoice.status
    if (s === 'draft') return 'draft'
    if (s === 'received') return 'bill'
    return 'readonly'
  }, [invoice])

  // Decide whether to show Receive panel (draft invoice that exists in DB)
  const showReceivePanel = mode === 'draft' && !!id

  // ─── [Fix 2 & 3 & Metrics] Select product: correct pricing + build unit list ─────────────
  const selectProduct = async (lineIdx: number, p: any) => {
    const baseUnitId = p.base_unit_id || ''
    const baseSymbol = p.base_unit?.symbol || p.base_unit?.name || ''

    // Fallback: last_purchase_price -> global_wac -> cost_price -> 0
    // All three come from the RPC (never from the products query)
    let basePrice: number = 0
    if (can('finance.view_costs')) {
      try {
        const metrics = await getProductCostMetrics([p.id])
        const m = metrics[p.id]
        if (m) {
          if (m.last_purchase_price != null) {
            basePrice = m.last_purchase_price
          } else if (m.global_wac != null) {
            basePrice = m.global_wac
          } else if (m.cost_price != null) {
            basePrice = m.cost_price
          }
        }
      } catch { /* ignore — user gets 0 */ }
    }

    const allUnits: AvailableUnit[] = []
    if (p.base_unit_id) {
      allUnits.push({ unit_id: p.base_unit_id, unit_name: p.base_unit?.name || '',
        unit_symbol: baseSymbol, conversion_factor: 1, purchase_price: null })
    }
    for (const pu of (p.product_units || [])) {
      if (pu.unit_id === p.base_unit_id) continue
      allUnits.push({ unit_id: pu.unit_id, unit_name: pu.unit?.name || '',
        unit_symbol: pu.unit?.symbol || pu.unit?.name || '',
        conversion_factor: pu.conversion_factor || 1, purchase_price: pu.selling_price ?? null })
    }

    setDraftLines(prev => {
      const copy = [...prev]
      copy[lineIdx] = calcDraftLine({
        ...copy[lineIdx],
        product_id: p.id, productName: p.name, productSku: p.sku,
        unit_id: baseUnitId || null, unitLabel: baseSymbol,
        available_units: allUnits, base_unit_id: baseUnitId,
        conversion_factor: 1, base_last_purchase_price: basePrice,
        unit_price: basePrice, tax_rate: p.tax_rate || 0,
      })
      return copy
    })
    setProductResults([])
    setActiveProductIdx(null)
  }

  // [Fix 3] Change unit: recalculate price = base_price * conversion_factor
  const changeUnit = (lineIdx: number, unitId: string) => {
    setDraftLines(prev => {
      const copy = [...prev]
      const line = copy[lineIdx]
      const u = line.available_units.find(u => u.unit_id === unitId)
      if (!u) return prev
      const newPrice = u.purchase_price != null
        ? u.purchase_price
        : Math.round(line.base_last_purchase_price * u.conversion_factor * 1000) / 1000
      copy[lineIdx] = calcDraftLine({
        ...line, unit_id: unitId, unitLabel: u.unit_symbol,
        conversion_factor: u.conversion_factor, unit_price: newPrice,
      })
      return copy
    })
  }

  const updateDraftLine = (idx: number, field: keyof DraftLine, value: any) => {
    setDraftLines(prev => {
      const copy = [...prev]
      copy[idx] = calcDraftLine({ ...copy[idx], [field]: value })
      return copy
    })
  }
  const removeDraftLine = (idx: number) => setDraftLines(p => p.filter((_, i) => i !== idx))
  const resetDraftLine  = (idx: number) => setDraftLines(prev => { const copy = [...prev]; copy[idx] = newDraftLine(); return copy })
  const addDraftLine    = () => setDraftLines(p => [...p, newDraftLine()])

  // ─── Save Draft ─────────────────────────────────────────────────────
  const handleSaveDraft = async () => {
    if (!supplierId) { toast.error('يرجى اختيار المورد أولاً'); return }
    if (!warehouseId) { toast.error('يرجى اختيار المخزن'); return }
    if (validDraftLines.length === 0) { toast.error('يرجى إضافة منتج واحد على الأقل'); return }

    setSaving(true)
    try {
      const header = {
        supplier_id: supplierId,
        warehouse_id: warehouseId,
        invoice_date: invoiceDate,
        supplier_invoice_ref: supplierRef || null,
        notes: notes || null,
        landed_costs: 0,
      }
      const items: PurchaseInvoiceItemInput[] = validDraftLines.map(l => ({
        product_id: l.product_id,
        unit_id: l.unit_id,
        ordered_quantity: l.ordered_quantity,
        unit_price: l.unit_price,
        discount_rate: l.discount_rate,
        tax_rate: l.tax_rate,
      }))

      if (isNew) {
        const created = await createPurchaseInvoice(header, items)
        toast.success('✅ تم حفظ الفاتورة كمسودة')
        // Stay on page with ID so user can proceed to receive
        navigate(`/purchases/invoices/${created.id}`, { replace: true })
      } else {
        await updatePurchaseInvoice(id!, header, items)
        const refreshed = await getPurchaseInvoice(id!)
        setInvoice(refreshed)
        toast.success('✅ تم تحديث المسودة')
      }
    } catch (err: any) {
      toast.error(err.message || 'فشل حفظ الفاتورة')
    } finally {
      setSaving(false)
    }
  }

  // ─── Confirm Receipt (Mode: receive) ───────────────────────────────
  const handleConfirmReceipt = async () => {
    if (!id) return
    if (receiveLines.every(l => l.received_quantity === 0)) {
      toast.error('يجب إدخال كمية مستلمة لبند واحد على الأقل'); return
    }

    setSaving(true)
    try {
      // 1. Batch-update received_quantity for each item
      await Promise.all(
        receiveLines.map(l => updateItemReceivedQty(l.item_id, l.received_quantity))
      )
      // 2. Update landed_costs on the header
      await updateLandedCosts(id, landedCosts)
      // 3. Fire the WAC engine RPC
      await receivePurchaseInvoice(id)
      // 4. Refetch
      const refreshed = await getPurchaseInvoice(id)
      setInvoice(refreshed)
      toast.success('✅ تم تسجيل الاستلام وتحديث المخزون')
    } catch (err: any) {
      toast.error(err.message || 'فشل تسجيل الاستلام')
    } finally {
      setSaving(false)
    }
  }

  // ─── Approve Financials (Mode: bill) ─────────────────────────────── 
  const handleBill = async () => {
    if (!id) return
    if (paymentMethod !== 'deferred' && paymentMethod !== 'cheque' && !billVaultId) {
      toast.error('يرجى اختيار الخزينة'); return
    }

    setSaving(true)
    try {
      await billPurchaseInvoice(id, {
        vaultId:       paymentMethod !== 'deferred' && paymentMethod !== 'cheque' ? billVaultId : null,
        paymentMethod: paymentMethod !== 'deferred' ? paymentMethod : null,
      })
      const refreshed = await getPurchaseInvoice(id)
      setInvoice(refreshed)
      toast.success('✅ تم الاعتماد المالي وإنشاء القيود المحاسبية')
    } catch (err: any) {
      toast.error(err.message || 'فشل الاعتماد المالي')
    } finally {
      setSaving(false)
    }
  }

  // ── Step helpers ────────────────────────────────────────────────
  const canProceedStep0 = !!supplierId && !!warehouseId
  const canProceedStep1 = validDraftLines.length > 0

  const goNext = () => {
    if (step === 0 && !canProceedStep0) { toast.error('يرجى اختيار المورد والمخزن أولاً'); return }
    if (step === 1 && !canProceedStep1) { toast.error('يرجى إضافة منتج واحد على الأقل'); return }
    setStep(s => Math.min(s + 1, STEPS.length - 1))
  }

  // ─── Loading ────────────────────────────────────────────────────────
  if (loading) {
    return (
      <div className="page-container animate-enter">
        <div className="edara-card" style={{ padding: 48, textAlign: 'center', color: 'var(--text-muted)' }}>
          <Loader2 size={32} style={{ margin: '0 auto 12px', display: 'block', animation: 'spin 1.2s linear infinite' }} />
          جاري تحميل الفاتورة...
        </div>
      </div>
    )
  }

  const readOnly = mode === 'readonly'

  /* ════════════════════════════════════════════
     RENDER
  ════════════════════════════════════════════ */
  return (
    <div className="page-container animate-enter">
      <PageHeader
        title={
          isNew ? 'فاتورة شراء جديدة' :
          invoice?.number ? `فاتورة ${invoice.number}` :
          'فاتورة شراء'
        }
        subtitle={
          mode === 'new' ? 'أدخل بيانات الفاتورة والبنود' :
          mode === 'draft' && !showReceivePanel ? 'راجع البنود ثم احفظ' :
          mode === 'draft' && showReceivePanel ? 'سجّل الكميات المستلمة ومصاريف الشحن' :
          mode === 'bill' ? 'الفاتورة جاهزة للاعتماد المالي' :
          'فاتورة نهائية — للقراءة فقط'
        }
        actions={
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            {invoice && <StatusBadge status={invoice.status} />}
            {invoice && <DocumentActions kind="purchase-invoice" entityId={invoice.id} />}
            <Button variant="ghost" onClick={() => navigate('/purchases/invoices')}>
              <ArrowRight size={16} /> رجوع
            </Button>
          </div>
        }
      />

      {/* ══════ STEPPER BAR (only in new/draft mode) ══════ */}
      {(mode === 'new' || (mode === 'draft' && !showReceivePanel)) && (
        <div className="edara-card" style={{ padding: 'var(--space-3) var(--space-4)', marginBottom: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 0 }}>
            {STEPS.map((s, i) => (
              <React.Fragment key={i}>
                <button
                  onClick={() => { if (i < step || i === 0 || (i === 1 && canProceedStep0) || (i === 2 && canProceedStep0 && canProceedStep1)) setStep(i) }}
                  style={{
                    display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
                    padding: '6px 12px', borderRadius: 'var(--radius-md)',
                    border: 'none', cursor: 'pointer', flex: 1, minWidth: 0,
                    background: i === step ? 'var(--color-primary)' : i < step ? 'var(--bg-accent)' : 'transparent',
                    color: i === step ? '#fff' : i < step ? 'var(--color-primary)' : 'var(--text-muted)',
                    transition: 'all 0.2s',
                  }}
                >
                  <span style={{ display: 'flex', alignItems: 'center', gap: 4, fontWeight: i === step ? 700 : 500, fontSize: 'var(--text-xs)', whiteSpace: 'nowrap' }}>
                    {i < step ? <CheckCircle size={13} /> : s.icon}
                    <span className="stepper-label">{s.label}</span>
                  </span>
                </button>
                {i < STEPS.length - 1 && (
                  <div style={{ flex: '0 0 16px', height: 2, background: i < step ? 'var(--color-primary)' : 'var(--border-color)', transition: 'background 0.3s' }} />
                )}
              </React.Fragment>
            ))}
          </div>
        </div>
      )}

      {/* ══════ STEP 0 / always-visible: Supplier & Header ══════ */}
      {(mode === 'bill' || mode === 'readonly' || step === 0 || showReceivePanel) && <section style={sCard}>
        <SectionHead icon={<FileText size={16} />} title="بيانات الفاتورة" />
        <div style={grid2}>
          {/* Supplier */}
          <div style={{ gridColumn: '1 / -1' }}>
            <FieldLabel required>المورد</FieldLabel>
            <InlineCombobox
              placeholder="ابحث بالاسم أو الكود..."
              items={supplierResults.map(s => ({ id: s.id, primary: s.name, secondary: s.code || undefined }))}
              onSearch={searchSuppliers}
              onSelect={item => {
                const s = supplierResults.find(s => s.id === item.id)
                if (s) { setSelectedSupplier(s); setSupplierId(s.id) }
              }}
              onClear={() => { setSelectedSupplier(null); setSupplierId('') }}
              selected={!!selectedSupplier}
              selectedLabel={selectedSupplier?.name}
              disabled={readOnly || mode === 'bill'}
            />
          </div>

          {/* Warehouse */}
          <div>
            <FieldLabel required>المخزن</FieldLabel>
            <select
              className="form-select"
              value={warehouseId}
              onChange={e => setWarehouseId(e.target.value)}
              disabled={readOnly || mode === 'bill' || (mode === 'draft' && showReceivePanel)}
            >
              <option value="">— اختر المخزن —</option>
              {(isAdmin ? warehouses : (myWarehouses.length > 0 ? myWarehouses : warehouses)).map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </div>

          {/* Date */}
          <div>
            <FieldLabel>تاريخ الفاتورة</FieldLabel>
            <input
              className="form-input" type="date"
              value={invoiceDate}
              onChange={e => setInvoiceDate(e.target.value)}
              disabled={readOnly || mode === 'bill'}
            />
          </div>

          {/* Supplier ref */}
          <div>
            <FieldLabel>رقم فاتورة المورد</FieldLabel>
            <input
              className="form-input"
              placeholder="اختياري — رقم فاتورة المورد الأصلية"
              value={supplierRef}
              onChange={e => setSupplierRef(e.target.value)}
              disabled={readOnly || mode === 'bill'}
            />
          </div>

          {/* Landed costs (shown in receive mode only) */}
          {(showReceivePanel || mode === 'bill' || readOnly) && (
            <div>
              <FieldLabel>مصاريف الشحن / الجمارك (ج.م)</FieldLabel>
              <input
                className="form-input" type="number" min={0} step="0.01" inputMode="decimal"
                value={landedCosts}
                onChange={e => setLandedCosts(Number(e.target.value))}
                disabled={mode !== 'draft'}
              />
            </div>
          )}

          {/* Notes */}
          <div style={{ gridColumn: '1 / -1' }}>
            <FieldLabel>ملاحظات</FieldLabel>
            <textarea
              className="form-input"
              rows={2}
              placeholder="ملاحظات اختيارية..."
              value={notes}
              onChange={e => setNotes(e.target.value)}
              disabled={readOnly || mode === 'bill'}
              style={{ resize: 'vertical' }}
            />
          </div>
        </div>
      </section>}

      {/* ══════ STEP 1: Items ══════ */}
      {(mode === 'bill' || mode === 'readonly' || step === 1 || showReceivePanel) && <section style={{ ...sCard, padding: 0, overflow: 'hidden' }}>
        <div style={{
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          padding: '14px 20px',
          background: 'linear-gradient(135deg, var(--bg-surface-2) 0%, var(--bg-surface) 100%)',
          borderBottom: '2px solid var(--border-color)',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              width: 32, height: 32, borderRadius: 8,
              background: 'var(--color-primary)', color: '#fff',
            }}>
              <Package size={16} />
            </span>
            <div>
              <div style={{ fontWeight: 700, fontSize: '0.9rem' }}>بنود الفاتورة</div>
              <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
                {validDraftLines.length > 0 ? `${validDraftLines.length} منتج` : 'لم يُضف منتج بعد'}
              </div>
            </div>
          </div>
          {(mode === 'new' || (mode === 'draft' && !showReceivePanel)) && (
            <>
              {/* Desktop: inline row */}
              <Button variant="ghost" size="sm" icon={<Plus size={14} />} onClick={addDraftLine}
                className="desktop-only-btn">
                إضافة بند
              </Button>
              {/* Mobile: open bottom sheet */}
              <Button variant="primary" size="sm" icon={<Plus size={14} />}
                onClick={() => { setSheetDraftLine(null); setSheetQuery(''); setSheetResults([]); setItemSheet(true) }}
                className="mobile-only-btn">
                إضافة منتج
              </Button>
            </>
          )}
        </div>

        {/* Receive mode info banner */}
        {showReceivePanel && (
          <div style={{
            padding: '9px 20px', display: 'flex', alignItems: 'center', gap: 8,
            background: 'rgba(37,99,235,0.06)', borderBottom: '1px solid rgba(37,99,235,0.15)',
            fontSize: '0.82rem', color: 'var(--color-primary)', fontWeight: 600,
          }}>
            <CheckCircle size={14} />
            أدخل الكميات المستلمة فعلياً في العمود الأزرق — يمكن استلام كمية أقل من المطلوبة
          </div>
        )}

        {/* Table — hidden on mobile, replaced by cards below */}
        <div className="hide-mobile" style={{ overflowX: 'auto', WebkitOverflowScrolling: 'touch' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.875rem', minWidth: showReceivePanel ? 860 : 760 }}>
            <thead>
              <tr style={{
                background: 'linear-gradient(to left, var(--bg-surface-2), rgba(37,99,235,0.04))',
                textAlign: 'right', borderBottom: '2px solid var(--border-color)',
              }}>
                <th style={{ ...thStyle(200), paddingRight: 20 }}>المنتج</th>
                <th style={thStyle(90)}>الوحدة</th>
                <th style={thStyle(85)}>الكمية المطلوبة</th>
                {showReceivePanel && (
                  <th style={{
                    ...thStyle(105),
                    background: 'rgba(37,99,235,0.1)',
                    color: 'var(--color-primary)',
                    borderInline: '1px solid rgba(37,99,235,0.2)',
                  }}>الكمية المستلمة ✎</th>
                )}
                <th style={thStyle(105)}>سعر الوحدة</th>
                <th style={thStyle(72)}>خصم %</th>
                <th style={thStyle(72)}>ضريبة %</th>
                <th style={{ ...thStyle(115), color: 'var(--color-primary)' }}>الإجمالي</th>
                {!readOnly && !showReceivePanel && mode !== 'bill' && <th style={thStyle(44)} />}
              </tr>
            </thead>
            <tbody>
              {(showReceivePanel ? receiveLines : draftLines).map((line, idx) => {
                const rl = line as ReceiveLine
                const isReceiveMode = showReceivePanel
                const totalLine = isReceiveMode
                  ? Math.round(rl.received_quantity * rl.unit_price * (1 - rl.discount_rate / 100) * (1 + rl.tax_rate / 100) * 100) / 100
                  : (line as DraftLine).lineTotal
                const isEven = idx % 2 === 0
                return (
                  <tr
                    key={line._key}
                    style={{
                      borderBottom: '1px solid var(--border-color)',
                      background: isEven ? 'transparent' : 'rgba(0,0,0,0.012)',
                      transition: 'background 0.1s',
                    }}
                    onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
                    onMouseLeave={e => (e.currentTarget.style.background = isEven ? 'transparent' : 'rgba(0,0,0,0.012)')}
                  >
                    {/* ── Product cell ── */}
                    <td style={{ padding: '10px 12px 10px 20px' }}>
                      {line.product_id ? (
                        // المنتج مختار — في الوضع القابل للتعديل يظهر زر X للتغيير
                        !isReceiveMode && !readOnly && mode !== 'bill' ? (
                          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                            <div style={{ flex: 1, minWidth: 0 }}>
                              <div style={{ fontWeight: 600, fontSize: '0.875rem', lineHeight: 1.3, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                {line.productName}
                              </div>
                              <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', fontFamily: 'monospace', letterSpacing: '0.03em' }}>
                                {line.productSku}
                              </div>
                            </div>
                            <button
                              type="button"
                              onClick={() => resetDraftLine(idx)}
                              title="تغيير المنتج"
                              style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', padding: 3, borderRadius: 4, flexShrink: 0 }}
                              onMouseEnter={e => (e.currentTarget.style.color = 'var(--color-danger)')}
                              onMouseLeave={e => (e.currentTarget.style.color = 'var(--text-muted)')}
                            >
                              <X size={13} />
                            </button>
                          </div>
                        ) : (
                          // عرض للقراءة فقط (وضع الاستلام / bill / readonly)
                          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                            <span style={{ fontWeight: 600, fontSize: '0.875rem', lineHeight: 1.3 }}>{line.productName}</span>
                            <span style={{ fontSize: '0.72rem', color: 'var(--text-muted)', fontFamily: 'monospace', letterSpacing: '0.03em' }}>{line.productSku}</span>
                          </div>
                        )
                      ) : (
                        mode !== 'readonly' && mode !== 'bill' && (
                          <PurchaseProductComboCell
                            productQuery={activeProductIdx === idx ? productQuery : ''}
                            productResults={activeProductIdx === idx ? productResults : []}
                            onSearch={q => { setActiveProductIdx(idx); setProductQuery(q); searchProducts(q) }}
                            onSelect={p => { selectProduct(idx, p); setProductQuery(''); setActiveProductIdx(null) }}
                            onFocus={() => setActiveProductIdx(idx)}
                            onBlur={() => setTimeout(() => { setActiveProductIdx(null); setProductQuery('') }, 150)}
                          />
                        )
                      )}
                    </td>

                    {/* ── Unit selector (BEFORE Ordered Qty — matches thead order) ── */}
                    <td style={{ padding: '10px 12px' }}>
                      {!isReceiveMode && !readOnly && mode !== 'bill' && line.available_units.length > 1 ? (
                        <select
                          className="form-select"
                          style={{ padding: '5px 8px', fontSize: '0.8rem', minWidth: 78 }}
                          value={line.unit_id || ''}
                          onChange={e => changeUnit(idx, e.target.value)}
                        >
                          {line.available_units.map(u => (
                            <option key={u.unit_id} value={u.unit_id}>
                              {u.unit_symbol || u.unit_name}
                            </option>
                          ))}
                        </select>
                      ) : (
                        <span style={{
                          display: 'inline-block', padding: '3px 10px', borderRadius: 6,
                          background: 'var(--bg-surface-2)', fontSize: '0.8rem',
                          color: 'var(--text-secondary)', fontWeight: 600,
                        }}>
                          {line.unitLabel || '—'}
                        </span>
                      )}
                    </td>

                    {/* ── Ordered Qty ── */}
                    <td style={{ padding: '10px 12px' }}>
                      {isReceiveMode || readOnly || mode === 'bill' ? (
                        <span style={{ fontWeight: 600 }}>{line.ordered_quantity}</span>
                      ) : (
                        <input
                          className="form-input" type="number" dir="ltr" min={1} step="any"
                          style={{ width: 76, padding: '5px 8px', textAlign: 'center' }}
                          value={line.ordered_quantity}
                          onChange={e => updateDraftLine(idx, 'ordered_quantity', Number(e.target.value))}
                        />
                      )}
                    </td>

                    {/* ── Received Qty (receive mode only) ── */}
                    {showReceivePanel && (
                      <td style={{ padding: '10px 12px', background: 'rgba(37,99,235,0.05)', borderInline: '1px solid rgba(37,99,235,0.12)' }}>
                        <div style={{ display: 'inline-block' }}>
                          <input
                            className="form-input" type="number" dir="ltr" min={0} step="any"
                            style={{
                              width: 90, padding: '5px 8px', fontWeight: 700, textAlign: 'center',
                              borderColor: rl.received_quantity > rl.ordered_quantity
                                ? 'var(--color-danger)'
                                : rl.received_quantity > 0
                                  ? 'var(--color-success)'
                                  : 'var(--color-primary)',
                            }}
                            value={rl.received_quantity}
                            onChange={e => {
                              const v = Number(e.target.value)
                              setReceiveLines(prev => prev.map((l, i) => i === idx ? { ...l, received_quantity: v } : l))
                            }}
                          />
                          {rl.received_quantity > rl.ordered_quantity && (
                            <div style={{ fontSize: '0.68rem', color: 'var(--color-danger)', marginTop: 2, whiteSpace: 'nowrap', display: 'flex', alignItems: 'center', gap: 3 }}>
                              <AlertTriangle size={10} /> تجاوز ({rl.ordered_quantity})
                            </div>
                          )}
                          {rl.received_quantity > 0 && rl.received_quantity < rl.ordered_quantity && (
                            <div style={{ fontSize: '0.68rem', color: 'var(--color-warning)', marginTop: 2 }}>
                              استلام جزئي
                            </div>
                          )}
                        </div>
                      </td>
                    )}

                    {/* ── Unit price ── */}
                    <td style={{ padding: '10px 12px' }}>
                      {readOnly || mode === 'bill' || isReceiveMode ? (
                        <span style={{ fontVariantNumeric: 'tabular-nums', fontWeight: 500 }}>{formatNumber(line.unit_price)}</span>
                      ) : (
                        <input
                          className="form-input" type="number" dir="ltr" min={0} step="any"
                          style={{ width: 100, padding: '5px 8px', textAlign: 'left' }}
                          value={line.unit_price}
                          onChange={e => updateDraftLine(idx, 'unit_price', Number(e.target.value))}
                        />
                      )}
                    </td>

                    {/* ── Discount ── */}
                    <td style={{ padding: '10px 12px' }}>
                      {readOnly || mode === 'bill' || isReceiveMode ? (
                        <span style={{ color: line.discount_rate > 0 ? 'var(--color-danger)' : 'var(--text-muted)' }}>
                          {line.discount_rate}%
                        </span>
                      ) : (
                        <input
                          className="form-input" type="number" dir="ltr" min={0} max={100} step="0.1"
                          style={{ width: 68, padding: '5px 8px', textAlign: 'center' }}
                          value={line.discount_rate}
                          onChange={e => updateDraftLine(idx, 'discount_rate', Number(e.target.value))}
                        />
                      )}
                    </td>

                    {/* ── Tax ── */}
                    <td style={{ padding: '10px 12px' }}>
                      {readOnly || mode === 'bill' || isReceiveMode ? (
                        <span style={{ color: 'var(--text-secondary)' }}>{line.tax_rate}%</span>
                      ) : (
                        <input
                          className="form-input" type="number" dir="ltr" min={0} max={100} step="0.1"
                          style={{ width: 68, padding: '5px 8px', textAlign: 'center' }}
                          value={line.tax_rate}
                          onChange={e => updateDraftLine(idx, 'tax_rate', Number(e.target.value))}
                        />
                      )}
                    </td>

                    {/* ── Line total ── */}
                    <td style={{ padding: '10px 12px' }}>
                      <span style={{
                        fontWeight: 700, fontVariantNumeric: 'tabular-nums',
                        color: totalLine > 0 ? 'var(--color-primary)' : 'var(--text-muted)',
                        fontSize: '0.9rem',
                      }}>
                        {formatNumber(totalLine)}
                      </span>
                      <span style={{ fontSize: '0.7rem', color: 'var(--text-muted)', marginRight: 2 }}>ج.م</span>
                    </td>

                    {/* ── Delete ── */}
                    {!readOnly && !isReceiveMode && mode !== 'bill' && (
                      <td style={{ padding: '10px 12px', textAlign: 'center' }}>
                        <button
                          type="button"
                          onClick={() => removeDraftLine(idx)}
                          style={{
                            background: 'none', border: 'none', cursor: 'pointer',
                            color: 'var(--text-muted)', padding: 6, borderRadius: 6,
                            display: 'inline-flex', alignItems: 'center', transition: 'all 0.15s',
                          }}
                          onMouseEnter={e => {
                            (e.currentTarget as HTMLButtonElement).style.color = 'var(--color-danger)'
                            ;(e.currentTarget as HTMLButtonElement).style.background = 'rgba(220,38,38,0.08)'
                          }}
                          onMouseLeave={e => {
                            (e.currentTarget as HTMLButtonElement).style.color = 'var(--text-muted)'
                            ;(e.currentTarget as HTMLButtonElement).style.background = 'none'
                          }}
                        >
                          <Trash2 size={15} />
                        </button>
                      </td>
                    )}
                  </tr>
                )
              })}

              {/* Empty state */}
              {(showReceivePanel ? receiveLines : draftLines).length === 0 && (
                <tr>
                  <td colSpan={8} style={{ padding: '48px 24px', textAlign: 'center' }}>
                    <Package size={40} style={{ color: 'var(--text-muted)', opacity: 0.3, margin: '0 auto 12px', display: 'block' }} />
                    <div style={{ color: 'var(--text-muted)', fontSize: '0.875rem' }}>لا توجد بنود — اضغط "إضافة بند" للبدء</div>
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        {/* ── Mobile Cards (≤768px) — بديل الجدول، يغطي جميع الأوضاع ── */}
        <div className="show-mobile" style={{ display: 'none', flexDirection: 'column' }}>
          {(() => {
            /* وضع المسودة / الإنشاء (new أو draft قبل showReceivePanel) */
            if (!showReceivePanel && !readOnly && mode !== 'bill') {
              const editableLines = draftLines.filter(l => l.product_id)
              if (editableLines.length === 0) return (
                <div style={{ padding: '32px 16px', textAlign: 'center', color: 'var(--text-muted)', fontSize: '0.875rem' }}>
                  <Package size={32} style={{ margin: '0 auto 10px', display: 'block', opacity: 0.3 }} />
                  لا توجد بنود — اضغط «إضافة منتج»
                </div>
              )
              return editableLines.map((line, cardIdx) => {
                const idx = draftLines.indexOf(line)
                return (
                  <div key={line._key} style={{ padding: '16px', borderBottom: '1px solid var(--border-color)', background: cardIdx % 2 === 0 ? 'transparent' : 'rgba(0,0,0,0.012)' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 12 }}>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontWeight: 700, fontSize: '0.9rem', lineHeight: 1.3 }}>{line.productName}</div>
                        <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', fontFamily: 'monospace', marginTop: 2 }}>{line.productSku}</div>
                      </div>
                      <button type="button" onClick={() => resetDraftLine(idx)} title="تغيير المنتج"
                        style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', padding: '4px 6px', borderRadius: 4, flexShrink: 0 }}>
                        <X size={15} />
                      </button>
                    </div>
                    <div style={{ marginBottom: 10 }}>
                      <FieldLabel>الوحدة</FieldLabel>
                      {line.available_units.length > 1 ? (
                        <select className="form-select" value={line.unit_id || ''} onChange={e => changeUnit(idx, e.target.value)}>
                          {line.available_units.map(u => (
                            <option key={u.unit_id} value={u.unit_id}>{u.unit_symbol || u.unit_name}{u.conversion_factor !== 1 ? ` ×${u.conversion_factor}` : ''}</option>
                          ))}
                        </select>
                      ) : (
                        <div className="form-input" style={{ background: 'var(--bg-surface-2)', cursor: 'default', color: 'var(--text-secondary)' }}>{line.unitLabel || '—'}</div>
                      )}
                    </div>
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginBottom: 12 }}>
                      <div>
                        <FieldLabel>الكمية</FieldLabel>
                        <input className="form-input" type="number" inputMode="decimal" min={1} step="any" value={line.ordered_quantity} onChange={e => updateDraftLine(idx, 'ordered_quantity', Number(e.target.value))} />
                      </div>
                      <div>
                        <FieldLabel>السعر (ج.م)</FieldLabel>
                        <input className="form-input" type="number" inputMode="decimal" min={0} step="any" value={line.unit_price} onChange={e => updateDraftLine(idx, 'unit_price', Number(e.target.value))} />
                      </div>
                      <div>
                        <FieldLabel>خصم %</FieldLabel>
                        <input className="form-input" type="number" inputMode="decimal" min={0} max={100} step="0.1" value={line.discount_rate} onChange={e => updateDraftLine(idx, 'discount_rate', Number(e.target.value))} />
                      </div>
                      <div>
                        <FieldLabel>ضريبة %</FieldLabel>
                        <input className="form-input" type="number" inputMode="decimal" min={0} max={100} step="0.1" value={line.tax_rate} onChange={e => updateDraftLine(idx, 'tax_rate', Number(e.target.value))} />
                      </div>
                    </div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingTop: 10, borderTop: '1px dashed var(--border-color)' }}>
                      <button type="button" onClick={() => removeDraftLine(idx)}
                        style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--color-danger)', fontSize: '0.82rem', display: 'flex', alignItems: 'center', gap: 4 }}>
                        <Trash2 size={14} /> حذف
                      </button>
                      <div style={{ textAlign: 'left' }}>
                        {line.lineDiscount > 0 && <div style={{ fontSize: '0.72rem', color: 'var(--color-danger)' }}>خصم: -{formatNumber(line.lineDiscount)} ج.م</div>}
                        <div style={{ fontWeight: 700, color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>{formatNumber(line.lineTotal)} ج.م</div>
                      </div>
                    </div>
                  </div>
                )
              })
            }

            /* وضع الاستلام (showReceivePanel = mode === 'draft' && !!id) */
            if (showReceivePanel) {
              return receiveLines.map((rl, idx) => {
                const totalLine = Math.round(rl.received_quantity * rl.unit_price * (1 - rl.discount_rate / 100) * (1 + rl.tax_rate / 100) * 100) / 100
                return (
                  <div key={rl._key} style={{ padding: '16px', borderBottom: '1px solid var(--border-color)' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 10 }}>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontWeight: 700, fontSize: '0.9rem' }}>{rl.productName}</div>
                        <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', fontFamily: 'monospace', marginTop: 2 }}>{rl.productSku}</div>
                      </div>
                      <span style={{ padding: '2px 8px', borderRadius: 6, background: 'var(--bg-surface-2)', fontSize: '0.8rem', color: 'var(--text-secondary)', fontWeight: 600, flexShrink: 0, marginRight: 4 }}>{rl.unitLabel || '—'}</span>
                    </div>
                    <div style={{ padding: '8px 12px', borderRadius: 8, background: 'rgba(100,116,139,0.07)', fontSize: '0.85rem', marginBottom: 10, display: 'flex', justifyContent: 'space-between' }}>
                      <span style={{ color: 'var(--text-muted)' }}>الكمية المطلوبة</span>
                      <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{rl.ordered_quantity}</span>
                    </div>
                    <div style={{ marginBottom: 10 }}>
                      <FieldLabel>الكمية المستلمة فعلياً</FieldLabel>
                      <input className="form-input" type="number" inputMode="decimal" min={0} step="any"
                        value={rl.received_quantity}
                        style={{ fontWeight: 700, borderColor: rl.received_quantity > rl.ordered_quantity ? 'var(--color-danger)' : rl.received_quantity > 0 ? 'var(--color-success)' : 'var(--color-primary)' }}
                        onChange={e => { const v = Number(e.target.value); setReceiveLines(prev => prev.map((l, i) => i === idx ? { ...l, received_quantity: v } : l)) }}
                      />
                      {rl.received_quantity > rl.ordered_quantity && (
                        <div style={{ fontSize: '0.75rem', color: 'var(--color-danger)', marginTop: 4, display: 'flex', alignItems: 'center', gap: 4 }}>
                          <AlertTriangle size={12} /> تجاوز المطلوب ({rl.ordered_quantity})
                        </div>
                      )}
                      {rl.received_quantity > 0 && rl.received_quantity < rl.ordered_quantity && (
                        <div style={{ fontSize: '0.75rem', color: 'var(--color-warning)', marginTop: 4 }}>⚠ استلام جزئي</div>
                      )}
                    </div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingTop: 8, borderTop: '1px dashed var(--border-color)', fontSize: '0.82rem' }}>
                      <span style={{ color: 'var(--text-muted)' }}>
                        {formatNumber(rl.unit_price)} ج.م{rl.discount_rate > 0 && ` • خصم ${rl.discount_rate}%`}{rl.tax_rate > 0 && ` • ضريبة ${rl.tax_rate}%`}
                      </span>
                      <span style={{ fontWeight: 700, color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>{formatNumber(totalLine)} ج.م</span>
                    </div>
                  </div>
                )
              })
            }

            /* وضع bill / readonly — قراءة فقط */
            return draftLines.map((line, cardIdx) => (
              <div key={line._key} style={{ padding: '16px', borderBottom: '1px solid var(--border-color)', background: cardIdx % 2 === 0 ? 'transparent' : 'rgba(0,0,0,0.012)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 8 }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontWeight: 700, fontSize: '0.9rem', lineHeight: 1.3 }}>{line.productName}</div>
                    <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', fontFamily: 'monospace', marginTop: 2 }}>{line.productSku}</div>
                  </div>
                  <span style={{ padding: '2px 8px', borderRadius: 6, background: 'var(--bg-surface-2)', fontSize: '0.8rem', color: 'var(--text-secondary)', fontWeight: 600, flexShrink: 0 }}>{line.unitLabel || '—'}</span>
                </div>
                <div style={{ fontSize: '0.85rem', color: 'var(--text-muted)', marginBottom: 6 }}>
                  {line.ordered_quantity} × {formatNumber(line.unit_price)} ج.م{line.discount_rate > 0 && ` — خصم ${line.discount_rate}%`}{line.tax_rate > 0 && ` — ضريبة ${line.tax_rate}%`}
                </div>
                <div style={{ display: 'flex', justifyContent: 'flex-end', fontWeight: 700, color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>
                  {formatNumber(line.lineTotal)} ج.م
                </div>
              </div>
            ))
          })()}
        </div>

        {/* Totals footer */}
        <div style={{
          padding: '16px 24px',
          borderTop: '2px solid var(--border-color)',
          background: 'linear-gradient(135deg, var(--bg-surface-2) 0%, var(--bg-surface) 100%)',
          display: 'flex', justifyContent: 'flex-end',
        }}>
          <div className="purch-totals-inner" style={{
            display: 'grid', gridTemplateColumns: 'auto auto',
            gap: '8px 28px', fontSize: '0.875rem',
            background: 'var(--bg-surface)', borderRadius: 10,
            padding: '14px 20px', border: '1px solid var(--border-color)',
            boxShadow: 'var(--shadow-sm)',
          }}>
            {!showReceivePanel ? (<>
              <span style={{ color: 'var(--text-muted)' }}>الإجمالي قبل الخصم:</span>
              <span style={{ fontVariantNumeric: 'tabular-nums', textAlign: 'left', fontWeight: 500 }}>{formatNumber(invoice?.subtotal ?? draftTotals.subtotal)} ج.م</span>
              <span style={{ color: 'var(--text-muted)' }}>الخصم:</span>
              <span style={{ color: 'var(--color-danger)', fontVariantNumeric: 'tabular-nums', textAlign: 'left' }}>- {formatNumber(invoice?.discount_amount ?? draftTotals.discount)} ج.م</span>
              <span style={{ color: 'var(--text-muted)' }}>الضريبة:</span>
              <span style={{ fontVariantNumeric: 'tabular-nums', textAlign: 'left' }}>{formatNumber(invoice?.tax_amount ?? draftTotals.tax)} ج.م</span>
              {((invoice?.landed_costs ?? 0) > 0) && (<>
                <span style={{ color: 'var(--text-muted)' }}>مصاريف الشحن:</span>
                <span style={{ fontVariantNumeric: 'tabular-nums', textAlign: 'left' }}>{formatNumber(invoice?.landed_costs ?? 0)} ج.م</span>
              </>)}
            </>) : (<>
              <span style={{ color: 'var(--text-muted)' }}>إجمالي المستلم (قبل خصم):</span>
              <span style={{ fontVariantNumeric: 'tabular-nums', textAlign: 'left', fontWeight: 500 }}>{formatNumber(receiveTotals.subtotal)} ج.م</span>
              <span style={{ color: 'var(--text-muted)' }}>الخصم:</span>
              <span style={{ color: 'var(--color-danger)', fontVariantNumeric: 'tabular-nums', textAlign: 'left' }}>- {formatNumber(receiveTotals.discount)} ج.م</span>
              <span style={{ color: 'var(--text-muted)' }}>الضريبة:</span>
              <span style={{ fontVariantNumeric: 'tabular-nums', textAlign: 'left' }}>{formatNumber(receiveTotals.tax)} ج.م</span>
              {landedCosts > 0 && (<>
                <span style={{ color: 'var(--text-muted)' }}>مصاريف الشحن:</span>
                <span style={{ fontVariantNumeric: 'tabular-nums', textAlign: 'left' }}>{formatNumber(landedCosts)} ج.م</span>
              </>)}
            </>)}
            <span style={{ fontWeight: 700, fontSize: '1rem', borderTop: '1.5px solid var(--border-color)', paddingTop: 8, marginTop: 2 }}>الإجمالي النهائي:</span>
            <span style={{ fontWeight: 800, fontSize: '1.15rem', color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums', textAlign: 'left', borderTop: '1.5px solid var(--border-color)', paddingTop: 8, marginTop: 2 }}>
              {formatNumber(
                showReceivePanel
                  ? receiveTotals.total
                  : (invoice?.total_amount ?? (draftTotals.total + landedCosts))
              )} ج.م
            </span>
          </div>
        </div>
      </section>}

      {/* ══════ STEP 2: Financials & Landed Costs ══════ */}
      {(mode === 'new' || mode === 'draft') && step === 2 && !showReceivePanel && <section style={sCard}>
        <SectionHead icon={<DollarSign size={16} />} title="التكاليف والضرائب" />

        <div style={grid2}>
          <div>
            <FieldLabel>مصاريف الشحن / الجمارك (ج.م)</FieldLabel>
            <input className="form-input" type="number" inputMode="decimal" min={0} step="0.01"
              value={landedCosts}
              onChange={e => setLandedCosts(Number(e.target.value))}
              placeholder="0.00" />
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 4 }}>
              تُضاف إلى تكلفة المخزون (حساب التكلفة المرجحة)
            </div>
          </div>
          <div>
            <FieldLabel>ملاحظات</FieldLabel>
            <textarea className="form-input" rows={2} value={notes}
              onChange={e => setNotes(e.target.value)}
              placeholder="ملاحظات اختيارية..." />
          </div>
        </div>

        {/* Financial preview */}
        <div style={{ marginTop: 16, padding: '14px 16px', borderRadius: 'var(--radius-md)', background: 'var(--bg-accent)', display: 'flex', flexDirection: 'column', gap: 8 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 'var(--text-sm)' }}>
            <span style={{ color: 'var(--text-muted)' }}>إجمالي البنود</span>
            <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatNumber(draftTotals.subtotal)} ج.م</span>
          </div>
          {draftTotals.discount > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 'var(--text-sm)' }}>
            <span style={{ color: 'var(--color-danger)' }}>إجمالي الخصومات</span>
            <span style={{ fontVariantNumeric: 'tabular-nums', color: 'var(--color-danger)' }}>- {formatNumber(draftTotals.discount)} ج.م</span>
          </div>}
          {draftTotals.tax > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 'var(--text-sm)' }}>
            <span style={{ color: 'var(--text-muted)' }}>الضرائب</span>
            <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatNumber(draftTotals.tax)} ج.م</span>
          </div>}
          {landedCosts > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 'var(--text-sm)' }}>
            <span style={{ color: 'var(--text-muted)' }}>مصاريف الشحن / الجمارك</span>
            <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatNumber(landedCosts)} ج.م</span>
          </div>}
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 'var(--text-sm)', fontWeight: 800, borderTop: '1px solid var(--border-color)', paddingTop: 8, marginTop: 4, color: 'var(--color-primary)' }}>
            <span>الإجمالي الكلي</span>
            <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatNumber(draftTotals.total + landedCosts)} ج.م</span>
          </div>
        </div>
      </section>}

      {/* ══════ STEP 3: Review & Save ══════ */}
      {(mode === 'new' || mode === 'draft') && step === 3 && !showReceivePanel && <section style={sCard}>
        <SectionHead icon={<CheckCircle size={16} />} title="مراجعة الفاتورة" />

        {/* Supplier + warehouse summary */}
        <div style={{ display: 'flex', gap: 12, marginBottom: 16, flexWrap: 'wrap' }}>
          {selectedSupplier && (
            <div style={{ flex: 1, minWidth: 160, padding: '10px 14px', borderRadius: 'var(--radius-md)', background: 'var(--bg-accent)' }}>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 2 }}>المورد</div>
              <div style={{ fontWeight: 700 }}>{selectedSupplier.name}</div>
            </div>
          )}
          <div style={{ flex: 1, minWidth: 120, padding: '10px 14px', borderRadius: 'var(--radius-md)', background: 'var(--bg-accent)' }}>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 2 }}>التاريخ</div>
            <div style={{ fontWeight: 600 }}>{new Date(invoiceDate).toLocaleDateString('ar-EG-u-nu-latn')}</div>
          </div>
        </div>

        {/* Items summary */}
        <div style={{ marginBottom: 16 }}>
          {validDraftLines.map(l => (
            <div key={l._key} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 0', borderBottom: '1px solid var(--border-color)', fontSize: 'var(--text-sm)' }}>
              <div>
                <span style={{ fontWeight: 600 }}>{l.productName}</span>
                <span style={{ color: 'var(--text-muted)', marginRight: 8 }}>× {l.ordered_quantity} {l.unitLabel}</span>
              </div>
              <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{formatNumber(l.lineTotal)} ج.م</span>
            </div>
          ))}
        </div>

        {/* Totals */}
        <div style={{ padding: '14px 16px', borderRadius: 'var(--radius-md)', background: 'var(--bg-accent)', display: 'flex', flexDirection: 'column', gap: 8 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 'var(--text-sm)' }}>
            <span style={{ color: 'var(--text-muted)' }}>إجمالي البنود</span>
            <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatNumber(draftTotals.subtotal)} ج.م</span>
          </div>
          {draftTotals.discount > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 'var(--text-sm)' }}>
            <span style={{ color: 'var(--color-danger)' }}>خصومات</span>
            <span style={{ color: 'var(--color-danger)', fontVariantNumeric: 'tabular-nums' }}>- {formatNumber(draftTotals.discount)} ج.م</span>
          </div>}
          {draftTotals.tax > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 'var(--text-sm)' }}>
            <span style={{ color: 'var(--text-muted)' }}>ضرائب</span>
            <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatNumber(draftTotals.tax)} ج.م</span>
          </div>}
          {landedCosts > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 'var(--text-sm)' }}>
            <span style={{ color: 'var(--text-muted)' }}>مصاريف شحن / جمارك</span>
            <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatNumber(landedCosts)} ج.م</span>
          </div>}
          <div style={{ display: 'flex', justifyContent: 'space-between', fontWeight: 800, fontSize: '1.05rem', borderTop: '1.5px solid var(--border-color)', paddingTop: 8, marginTop: 4, color: 'var(--color-primary)' }}>
            <span>الإجمالي الكلي</span>
            <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatNumber(draftTotals.total + landedCosts)} ج.م</span>
          </div>
        </div>
      </section>}

      {/* ══════ Step Navigation Bar (new/draft only) ══════ */}
      {(mode === 'new' || (mode === 'draft' && !showReceivePanel)) && (
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, marginBottom: 'var(--space-4)' }}>
          <Button variant="ghost" onClick={step === 0 ? () => navigate('/purchases/invoices') : () => setStep(s => s - 1)}>
            {step === 0 ? 'إلغاء' : <>‹ السابق</>}
          </Button>
          {step < STEPS.length - 1 ? (
            <Button onClick={goNext} style={{ minWidth: 140 }}>{'التالي ›'}</Button>
          ) : (
            <Button icon={<Save size={15} />} onClick={handleSaveDraft}
              disabled={saving || !supplierId || !warehouseId || validDraftLines.length === 0}
              style={{ minWidth: 160 }}>
              {saving ? 'جاري الحفظ...' : isNew ? 'حفظ المسودة' : 'تحديث المسودة'}
            </Button>
          )}
        </div>
      )}

      {/* ══════ MOBILE: Add-Item Bottom Sheet ══════ */}
      <ResponsiveModal
        open={itemSheet}
        onClose={() => { setItemSheet(false); setSheetDraftLine(null); setSheetQuery('') }}
        title="إضافة منتج مستلم"
        footer={
          sheetDraftLine ? (
            <>
              <Button variant="secondary" onClick={() => setSheetDraftLine(null)}>تغيير المنتج</Button>
              <Button onClick={confirmSheetLine}>إضافة للفاتورة</Button>
            </>
          ) : undefined
        }
      >
        {!sheetDraftLine ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
            <div style={{ position: 'relative' }}>
              <Search size={14} style={{ position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
              <input className="form-input" placeholder="ابحث عن منتج بالاسم أو الكود..." value={sheetQuery} autoFocus
                style={{ paddingRight: 32 }}
                onChange={e => { setSheetQuery(e.target.value); searchSheetProducts(e.target.value) }} />
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', maxHeight: 340, overflowY: 'auto' }}>
              {sheetResults.map(p => (
                <button key={p.id} onClick={() => selectSheetProduct(p)}
                  style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 14px', borderRadius: 'var(--radius-md)', border: '1px solid var(--border-color)', cursor: 'pointer', background: 'var(--bg-surface)', textAlign: 'right', gap: 12 }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{p.name}</div>
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{p.sku}</div>
                  </div>
                  <div style={{ flexShrink: 0, fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontStyle: 'italic' }}>
                    سيتم تحديد السعر
                  </div>
                </button>
              ))}
              {sheetQuery.length >= 2 && sheetResults.length === 0 && (
                <p style={{ textAlign: 'center', color: 'var(--text-muted)', fontSize: 'var(--text-sm)', padding: 'var(--space-4)' }}>لا توجد نتائج</p>
              )}
            </div>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
            <div style={{ padding: '12px 16px', borderRadius: 'var(--radius-md)', background: 'var(--bg-accent)' }}>
              <div style={{ fontWeight: 700 }}>{sheetDraftLine.productName}</div>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }} dir="ltr">{sheetDraftLine.productSku}</div>
            </div>

            {sheetDraftLine.available_units.length > 1 && (
              <div className="form-group">
                <label className="form-label">الوحدة</label>
                <select className="form-select" value={sheetDraftLine.unit_id || ''}
                  onChange={e => {
                    const u = sheetDraftLine.available_units.find(u => u.unit_id === e.target.value)
                    if (u) setSheetDraftLine(calcDraftLine({ ...sheetDraftLine, unit_id: e.target.value, unitLabel: u.unit_symbol, conversion_factor: u.conversion_factor, unit_price: u.purchase_price ?? Math.round(sheetDraftLine.base_last_purchase_price * u.conversion_factor * 1000) / 1000 }))
                  }}>
                  {sheetDraftLine.available_units.map(u => (
                    <option key={u.unit_id} value={u.unit_id}>{u.unit_symbol}{u.conversion_factor !== 1 ? ` ×${u.conversion_factor}` : ''}</option>
                  ))}
                </select>
              </div>
            )}

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
              <div className="form-group">
                <label className="form-label">الكمية المطلوبة</label>
                <input type="number" inputMode="decimal" enterKeyHint="next" className="form-input" min={0.01} step={1}
                  value={sheetDraftLine.ordered_quantity}
                  onChange={e => setSheetDraftLine(calcDraftLine({ ...sheetDraftLine, ordered_quantity: Number(e.target.value) }))} />
              </div>
              <div className="form-group">
                <label className="form-label">سعر الشراء (ج.م)</label>
                <input type="number" inputMode="decimal" enterKeyHint="next" className="form-input" min={0} step={0.001}
                  value={sheetDraftLine.unit_price}
                  onChange={e => setSheetDraftLine(calcDraftLine({ ...sheetDraftLine, unit_price: Number(e.target.value) }))} />
              </div>
              <div className="form-group">
                <label className="form-label">خصم %</label>
                <input type="number" inputMode="decimal" enterKeyHint="next" className="form-input" min={0} max={100} step={0.5}
                  value={sheetDraftLine.discount_rate}
                  onChange={e => setSheetDraftLine(calcDraftLine({ ...sheetDraftLine, discount_rate: Number(e.target.value) }))} />
              </div>
              {sheetDraftLine.tax_rate > 0 && <div className="form-group">
                <label className="form-label">ضريبة %</label>
                <input type="number" inputMode="decimal" enterKeyHint="done" className="form-input" min={0} max={100} step={0.5}
                  value={sheetDraftLine.tax_rate}
                  onChange={e => setSheetDraftLine(calcDraftLine({ ...sheetDraftLine, tax_rate: Number(e.target.value) }))} />
              </div>}
            </div>

            <div style={{ display: 'flex', justifyContent: 'space-between', padding: '12px 16px', borderRadius: 'var(--radius-md)', background: 'var(--bg-accent)', fontWeight: 700 }}>
              <span>صافي البند</span>
              <span style={{ color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>{formatNumber(sheetDraftLine.lineTotal)} ج.م</span>
            </div>
          </div>
        )}
      </ResponsiveModal>

      <style>{`
        @media (max-width: 768px) {
          .desktop-only-btn { display: none !important; }
          .mobile-only-btn  { display: inline-flex !important; }
          .stepper-label    { display: none; }
        }
        @media (min-width: 769px) {
          .mobile-only-btn  { display: none !important; }
        }
      `}</style>
      {mode === 'bill' && (
        <section style={{ ...sCard, border: '2px solid var(--color-primary)' }}>
          <SectionHead icon={<DollarSign size={16} />} title="التسوية المالية — اعتماد الفاتورة" />

          <div style={{ marginBottom: 16 }}>
            <FieldLabel>طريقة الدفع</FieldLabel>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {([
                { v: 'deferred',      label: '⏳ تأجيل (آجل)' },
                { v: 'cash',          label: '💵 نقدي' },
                { v: 'bank_transfer', label: '🏦 تحويل بنكي' },
                { v: 'cheque',        label: '📝 شيك' },
                { v: 'mobile_wallet', label: '📱 محفظة إلكترونية' },
              ] as const).map(opt => (
                <button
                  key={opt.v} type="button"
                  onClick={() => setPaymentMethod(opt.v)}
                  style={{
                    padding: '8px 16px', borderRadius: 8, fontSize: '0.875rem', cursor: 'pointer',
                    fontWeight: paymentMethod === opt.v ? 700 : 400,
                    background: paymentMethod === opt.v ? 'var(--color-primary)' : 'var(--bg-surface-2)',
                    color: paymentMethod === opt.v ? '#fff' : 'var(--text-secondary)',
                    border: paymentMethod === opt.v ? '2px solid var(--color-primary)' : '2px solid var(--border-color)',
                    transition: 'all 0.15s',
                  }}
                >
                  {opt.label}
                </button>
              ))}
            </div>
          </div>

          {/* Vault selector — shown for cash/bank/wallet but NOT for deferred/cheque */}
          {paymentMethod !== 'deferred' && paymentMethod !== 'cheque' && (
            <div style={{ maxWidth: 360 }}>
              <FieldLabel required>الخزينة / البنك</FieldLabel>
              <select
                className="form-select"
                value={billVaultId}
                onChange={e => setBillVaultId(e.target.value)}
              >
                <option value="">— اختر الخزينة —</option>
                {vaults.map(v => (
                  <option key={v.id} value={v.id}>
                    {v.name} — {formatNumber(v.current_balance)} ج.م
                  </option>
                ))}
              </select>
            </div>
          )}

          {paymentMethod === 'deferred' && (
            <div style={{ marginTop: 12, padding: '12px 16px', background: 'rgba(107,114,128,0.08)', borderRadius: 8, fontSize: '0.875rem', color: 'var(--text-muted)', display: 'flex', gap: 8, alignItems: 'center' }}>
              <AlertTriangle size={16} />
              سيُضاف إجمالي الفاتورة ({formatNumber(invoice?.total_amount ?? 0)} ج.م) كدين مؤجل في دفتر المورد.
            </div>
          )}
          {paymentMethod === 'cheque' && (
            <div style={{ marginTop: 12, padding: '12px 16px', background: 'rgba(107,114,128,0.08)', borderRadius: 8, fontSize: '0.875rem', color: 'var(--text-muted)', display: 'flex', gap: 8, alignItems: 'center' }}>
              <Banknote size={16} />
              سيُسجَّل الشيك في حساب "أوراق دفع" (2110) — لا تُخصم من الخزينة الآن.
            </div>
          )}
        </section>
      )}

      {/* ══════ Section 4: Read-Only Summary (paid/billed) ══════ */}
      {readOnly && invoice && (
        <section style={sCard}>
          <SectionHead icon={<Eye size={16} />} title="ملخص التسوية" />
          <div style={grid3}>
            <div>
              <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>طريقة الدفع</div>
              <div style={{ fontWeight: 700, marginTop: 4 }}>
                {invoice.payment_method === 'cash' ? 'نقدي' :
                 invoice.payment_method === 'bank_transfer' ? 'تحويل بنكي' :
                 invoice.payment_method === 'cheque' ? 'شيك' :
                 invoice.payment_method === 'mobile_wallet' ? 'محفظة إلكترونية' :
                 'مؤجل'}
              </div>
            </div>
            <div>
              <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>المدفوع</div>
              <div style={{ fontWeight: 700, color: 'var(--color-success)', marginTop: 4 }}>{formatNumber(invoice.paid_amount)} ج.م</div>
            </div>
            <div>
              <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>المتبقي</div>
              <div style={{ fontWeight: 700, color: invoice.total_amount - invoice.paid_amount > 0 ? 'var(--color-danger)' : 'var(--color-success)', marginTop: 4 }}>
                {formatNumber(invoice.total_amount - invoice.paid_amount)} ج.م
              </div>
            </div>
          </div>
        </section>
      )}

      {/* ══════ Action Bar ══════ */}
      <div className="purch-action-bar" style={{ display: 'flex', justifyContent: 'flex-end', gap: 12, marginTop: 8, flexWrap: 'wrap' }}>
        <Button variant="ghost" onClick={() => navigate('/purchases/invoices')}>
          رجوع
        </Button>

        {/* ── زر الإلغاء — RBAC + no-payment guard ── */}
        {invoice &&
          (invoice.status === 'received' || invoice.status === 'billed') &&
          (invoice.paid_amount ?? 0) === 0 &&
          can('procurement.invoices.cancel') && (
          <Button
            variant="danger"
            loading={cancelling}
            icon={<XCircle size={16} />}
            onClick={async () => {
              const confirmed = window.confirm(
                'تحذير: هذه العملية ستسحب البضاعة من المخزن وتعكس القيود المحاسبية.\nهل أنت متأكد من إلغاء الفاتورة؟'
              )
              if (!confirmed) return
              setCancelling(true)
              try {
                await cancelPurchaseInvoice(invoice.id)
                toast.success('تم إلغاء الفاتورة بنجاح')
                await fetchInvoice(invoice.id)
              } catch (err: any) {
                toast.error(err.message || 'فشلت عملية الإلغاء')
              } finally {
                setCancelling(false)
              }
            }}
          >
            إلغاء الفاتورة
          </Button>
        )}

        {/* Mode: new or draft (before receive panel) — any user with create can save */}
        {(mode === 'new' || (mode === 'draft' && !showReceivePanel)) && (
          <Button
            variant="primary"
            loading={saving}
            icon={<Save size={16} />}
            onClick={handleSaveDraft}
          >
            حفظ المسودة
          </Button>
        )}

        {/* Mode: draft with receive panel — guard: procurement.invoices.receive */}
        {showReceivePanel && can('procurement.invoices.receive') && (
          <Button
            variant="primary"
            loading={saving}
            icon={<CheckCircle size={16} />}
            onClick={handleConfirmReceipt}
            disabled={hasReceiveError}  // [Flaw 3 Fix] block submit on validation error
          >
            {hasReceiveError ? 'صحح الكميات أولاً ❗' : 'تأكيد الاستلام'}
          </Button>
        )}
        {showReceivePanel && !can('procurement.invoices.receive') && (
          <div style={{ padding: '8px 16px', borderRadius: 8, background: 'var(--bg-surface-2)', color: 'var(--text-muted)', fontSize: '0.8rem', display: 'flex', alignItems: 'center', gap: 6, border: '1px solid var(--border-color)' }}>
            <AlertTriangle size={14} /> لا تملك صلاحية تأكيد الاستلام
          </div>
        )}

        {/* Mode: received → bill — guard: procurement.invoices.bill */}
        {mode === 'bill' && can('procurement.invoices.bill') && (
          <Button
            variant="primary"
            loading={saving}
            icon={<DollarSign size={16} />}
            onClick={handleBill}
          >
            اعتماد مالي وسداد
          </Button>
        )}
        {mode === 'bill' && !can('procurement.invoices.bill') && (
          <div style={{ padding: '8px 16px', borderRadius: 8, background: 'var(--bg-surface-2)', color: 'var(--text-muted)', fontSize: '0.8rem', display: 'flex', alignItems: 'center', gap: 6, border: '1px solid var(--border-color)' }}>
            <AlertTriangle size={14} /> لا تملك صلاحية الاعتماد المالي
          </div>
        )}
      </div>

      <style>{`
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
        /* ── Mobile ≤768px ── */
        @media (max-width: 768px) {
          .hide-mobile         { display: none !important; }
          .show-mobile         { display: flex !important; }
          .desktop-only-btn    { display: none !important; }
          .mobile-only-btn     { display: inline-flex !important; }
          .purch-action-bar    { flex-direction: column-reverse !important; gap: 8px !important; }
          .purch-action-bar > * { width: 100% !important; justify-content: center !important; }
          .purch-totals-inner  { width: 100% !important; }
        }
        @media (min-width: 769px) {
          .show-mobile         { display: none !important; }
          .mobile-only-btn     { display: none !important; }
          .hide-mobile         { display: block; }
        }
      `}</style>
    </div>
  )
}

// ─── TH helper ────────────────────────────────────────────────────────────────
function thStyle(w: number): React.CSSProperties {
  return {
    padding: '10px 12px',
    fontWeight: 600,
    fontSize: '0.8rem',
    whiteSpace: 'nowrap',
    width: w,
    minWidth: w,
  }
}
