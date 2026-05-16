import { useState, useEffect, useMemo, useRef, useCallback } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { toast } from 'sonner'
import { ArrowRight, RotateCcw, Save, AlertTriangle, Search, X, User, FileText, Package } from 'lucide-react'
import { useWarehouses } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { supabase } from '@/lib/supabase/client'
import { getSalesOrder, createSalesReturn, getReturnableItems, getReturnableSalesOrdersForCustomer } from '@/lib/services/sales'
import { formatNumber } from '@/lib/utils/format'
import type {
  SalesOrder, SalesOrderItem, SalesReturnInput, SalesReturnItemInput, Customer
} from '@/lib/types/master-data'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import Badge from '@/components/ui/Badge'

interface ReturnLine {
  orderItemId: string
  productName: string
  productSku: string
  unitSymbol: string
  unitId: string
  conversionFactor: number
  unitPrice: number
  deliveredQty: number     // total delivered (base)
  returnedQty: number      // already returned (base)
  maxQty: number           // max returnable
  returnQty: number        // user input — qty to return
  lineTotal: number
}

interface ComboItem { id: string; primary: string; secondary?: string; meta?: string; original?: any }
interface ComboboxProps {
  placeholder: string
  value: string
  items: ComboItem[]
  onSearch: (q: string) => void
  onSelect: (item: ComboItem) => void
  onClear?: () => void
  loading?: boolean
  selected?: boolean
  selectedLabel?: string
  required?: boolean
}

function Combobox({ placeholder, value, items, onSearch, onSelect, onClear, selected, selectedLabel }: ComboboxProps) {
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
        borderRadius: 'var(--radius-md)',
        minHeight: 42,
      }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)', lineHeight: 1.3, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {selectedLabel}
          </div>
          {value && value !== selectedLabel && (
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{value}</div>
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
          borderRadius: 'var(--radius-md)',
          boxShadow: 'var(--shadow-lg)',
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
                <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{item.primary}</div>
                {item.secondary && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{item.secondary}</div>}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

export default function SalesReturnForm() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const orderId = searchParams.get('orderId') || ''

  const { data: warehouses = [] } = useWarehouses({ isActive: true })

  const [loading, setLoading] = useState(false)
  const [orderLoading, setOrderLoading] = useState(true)
  const [order, setOrder] = useState<SalesOrder | null>(null)

  // Customer search states
  const [selectedCustomer, setSelectedCustomer] = useState<Customer | null>(null)
  const [customerResults, setCustomerResults] = useState<Customer[]>([])
  const selectedCustomerIdRef = useRef<string>('')
  
  // Returnable orders state
  const [returnableOrders, setReturnableOrders] = useState<any[]>([])
  const [loadingOrders, setLoadingOrders] = useState(false)
  const [productSearch, setProductSearch] = useState('')

  // Computed filtered orders
  const filteredOrders = useMemo(() => {
    if (!productSearch.trim()) return returnableOrders
    const q = productSearch.toLowerCase()
    return returnableOrders.filter(o => {
      // match order number
      if (o.order_number.toLowerCase().includes(q)) return true
      // match items
      return o.returnableItems?.some((item: any) => 
        item.product?.name?.toLowerCase().includes(q) ||
        (item.product?.sku && item.product.sku.toLowerCase().includes(q))
      )
    })
  }, [returnableOrders, productSearch])

  const [lines, setLines] = useState<ReturnLine[]>([])
  const [reason, setReason] = useState('')
  const [notes, setNotes] = useState('')
  const [warehouseId, setWarehouseId] = useState('')

  // Load order from URL param
  useEffect(() => {
    if (!orderId) { setOrderLoading(false); return }
    loadOrder(orderId)
  }, [orderId])

  const loadOrder = async (id: string) => {
    setOrderLoading(true)
    try {
      const o = await getSalesOrder(id)
      if (!['delivered', 'completed'].includes(o.status)) {
        toast.error('لا يمكن إنشاء مرتجع لطلب لم يُسلّم بعد')
        navigate('/sales/orders')
        return
      }
      setOrder(o)
      setWarehouseId(o.warehouse_id || '')

      // Load returnable items
      const items = await getReturnableItems(id)
      setLines(items.map(i => ({
        orderItemId: i.id,
        productName: i.product?.name || 'منتج',
        productSku: i.product?.sku || '',
        unitSymbol: i.unit?.symbol || i.unit?.name || '',
        unitId: i.unit_id,
        conversionFactor: i.conversion_factor,
        unitPrice: i.unit_price,
        deliveredQty: i.delivered_quantity,
        returnedQty: i.returned_quantity,
        maxQty: i.delivered_quantity - i.returned_quantity,
        returnQty: 0,
        lineTotal: 0,
      })))
    } catch (err: any) {
      toast.error(err.message || 'فشل تحميل الطلب')
    } finally {
      setOrderLoading(false)
    }
  }

  // Customer search
  const handleSearchCustomers = useCallback(async (q: string) => {
    if (q.length < 2) { setCustomerResults([]); return }
    const { data } = await supabase
      .from('customers')
      .select('id, name, code, phone, mobile')
      .eq('is_active', true)
      .or(`name.ilike.%${q}%,code.ilike.%${q}%,phone.ilike.%${q}%,mobile.ilike.%${q}%`)
      .limit(10)
    setCustomerResults(data as Customer[] || [])
  }, [])

  const handleSelectCustomer = async (c: any) => {
    setSelectedCustomer(c)
    selectedCustomerIdRef.current = c.id
    setCustomerResults([])
    setLoadingOrders(true)
    try {
      const orders = await getReturnableSalesOrdersForCustomer(c.id)
      if (selectedCustomerIdRef.current === c.id) {
        setReturnableOrders(orders)
      }
    } catch (err: any) {
      if (selectedCustomerIdRef.current === c.id) {
        toast.error('فشل جلب فواتير العميل')
      }
    } finally {
      if (selectedCustomerIdRef.current === c.id) {
        setLoadingOrders(false)
      }
    }
  }

  const handleClearCustomer = () => {
    selectedCustomerIdRef.current = ''
    setSelectedCustomer(null)
    setReturnableOrders([])
    setLoadingOrders(false)
    setProductSearch('')
  }

  const handleSelectOrder = (o: any) => {
    navigate(`/sales/returns/new?orderId=${o.id}`, { replace: true })
  }

  // Update line qty
  const updateQty = (idx: number, qty: number) => {
    setLines(prev => {
      const copy = [...prev]
      const line = copy[idx]
      const qtyVal = Math.min(Math.max(0, qty), line.maxQty)
      const baseQty = qtyVal * line.conversionFactor
      copy[idx] = {
        ...line,
        returnQty: qtyVal,
        lineTotal: Math.round(baseQty * line.unitPrice * 100) / 100,
      }
      return copy
    })
  }

  // Set all to max
  const returnAll = () => {
    setLines(prev => prev.map(l => ({
      ...l,
      returnQty: l.maxQty,
      lineTotal: Math.round(l.maxQty * l.unitPrice * 100) / 100,
    })))
  }

  // Totals
  const selectedLines = lines.filter(l => l.returnQty > 0)
  const totalAmount = useMemo(() =>
    selectedLines.reduce((s, l) => s + l.lineTotal, 0),
    [selectedLines]
  )

  // Save
  const handleSave = async () => {
    if (!order) { toast.error('يرجى اختيار الفاتورة'); return }
    if (selectedLines.length === 0) { toast.error('يرجى تحديد كمية مرتجعة لبند واحد على الأقل'); return }

    setLoading(true)
    try {
      const input: SalesReturnInput = {
        order_id: order.id,
        customer_id: order.customer_id,
        warehouse_id: warehouseId || null,
        return_date: new Date().toISOString().split('T')[0],
        reason: reason || null,
        notes: notes || null,
      }

      const items: SalesReturnItemInput[] = selectedLines.map(l => ({
        order_item_id: l.orderItemId,
        product_id: '', // will use join from order_item_id
        unit_id: l.unitId,
        conversion_factor: l.conversionFactor,
        quantity: l.returnQty,
        base_quantity: Math.round(l.returnQty * l.conversionFactor * 100) / 100,
        unit_price: l.unitPrice,
        line_total: l.lineTotal,
      }))

      // Need product_id from orig items
      for (const item of items) {
        const origLine = lines.find(l => l.orderItemId === item.order_item_id)
        if (origLine) {
          // Get product_id from order items
          const origItem = order.items?.find(i => i.id === item.order_item_id)
          item.product_id = origItem?.product_id || ''
        }
      }

      const result = await createSalesReturn(input, items)
      toast.success('تم إنشاء المرتجع بنجاح')
      navigate(`/sales/returns/${result.id}`)
    } catch (err: any) {
      toast.error(err.message || 'فشل إنشاء المرتجع')
    } finally {
      setLoading(false)
    }
  }

  if (orderLoading) {
    return <div className="page-container animate-enter">
      <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center' }}>جاري التحميل...</div>
    </div>
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="مرتجع مبيعات جديد"
        subtitle={order ? `من الفاتورة #${order.order_number}` : 'اختر العميل ثم الفاتورة'}
        actions={
          <Button variant="ghost" onClick={() => navigate('/sales/returns')}>
            <ArrowRight size={16} /> رجوع
          </Button>
        }
      />

      {/* Customer & Order selection (when no orderId) */}
      {!order && (
        <div className="edara-card" style={{ padding: 'var(--space-5)', marginBottom: 'var(--space-4)' }}>
          <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 600, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
            <span style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: 24, height: 24, background: 'var(--color-primary-light, rgba(37,99,235,0.1))', color: 'var(--color-primary)', borderRadius: '50%', fontSize: 'var(--text-xs)' }}>1</span>
            اختر العميل
          </h3>
          <div style={{ maxWidth: 400, marginBottom: 'var(--space-5)' }}>
            <Combobox
              placeholder="ابحث باسم العميل، الكود، الهاتف، أو الموبايل..."
              value={selectedCustomer?.code || ''}
              items={customerResults.map(c => ({
                id: c.id,
                primary: c.name,
                secondary: [c.code, c.phone, c.mobile].filter(Boolean).join(' - '),
                original: c
              })) as any}
              onSearch={handleSearchCustomers}
              onSelect={(item: any) => handleSelectCustomer(item.original)}
              selected={!!selectedCustomer}
              selectedLabel={selectedCustomer?.name}
              onClear={handleClearCustomer}
            />
          </div>

          {selectedCustomer && (
            <div className="animate-enter">
              <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 600, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
                <span style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: 24, height: 24, background: 'var(--color-primary-light, rgba(37,99,235,0.1))', color: 'var(--color-primary)', borderRadius: '50%', fontSize: 'var(--text-xs)' }}>2</span>
                اختر الفاتورة للإرجاع
              </h3>

              <div style={{ marginBottom: 'var(--space-4)', maxWidth: 400, position: 'relative' }}>
                <Search size={16} style={{ position: 'absolute', right: 12, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
                <input 
                  className="form-input" 
                  placeholder="ابحث داخل فواتير العميل باسم المنتج أو الكود..."
                  style={{ paddingRight: 36 }}
                  value={productSearch}
                  onChange={e => setProductSearch(e.target.value)}
                />
              </div>

              <div style={{ fontSize: 'var(--text-sm)', color: 'var(--color-warning)', background: 'rgba(245, 158, 11, 0.1)', padding: 'var(--space-3)', borderRadius: 'var(--radius-md)', marginBottom: 'var(--space-4)', display: 'flex', alignItems: 'flex-start', gap: 'var(--space-2)' }}>
                <AlertTriangle size={16} style={{ flexShrink: 0, marginTop: 2 }} />
                <div>النظام يُنشئ مرتجعاً لفاتورة واحدة فقط. لا يمكن اختيار منتجات من فواتير متعددة في نفس عملية الإرجاع.</div>
              </div>

              {loadingOrders ? (
                <div style={{ padding: 'var(--space-4)', textAlign: 'center', color: 'var(--text-muted)' }}>جاري جلب فواتير العميل...</div>
              ) : filteredOrders.length === 0 ? (
                <div style={{ padding: 'var(--space-6)', textAlign: 'center', color: 'var(--text-muted)', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 'var(--space-2)', background: 'var(--bg-hover)', borderRadius: 'var(--radius-md)' }}>
                  <FileText size={40} style={{ opacity: 0.3 }} />
                  <div style={{ fontWeight: 500 }}>{productSearch ? 'لا توجد فواتير تحتوي هذا المنتج ضمن الفواتير القابلة للإرجاع' : 'هذا العميل ليس لديه فواتير قابلة للمرتجع'}</div>
                  {!productSearch && <div style={{ fontSize: 'var(--text-xs)' }}>تظهر فقط الفواتير المُسلّمة بالكامل أو جزئياً.</div>}
                </div>
              ) : (
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: 'var(--space-4)' }}>
                  {filteredOrders.map(o => {
                    const netAvail = o.total_amount - (o.returned_amount || 0)
                    const items = o.returnableItems || []
                    const itemsCount = items.length
                    const displayItems = items.slice(0, 3)
                    const remainingItemsCount = itemsCount - displayItems.length

                    return (
                      <div key={o.id} onClick={() => handleSelectOrder(o)}
                        style={{
                          border: '1px solid var(--border-color)', borderRadius: 'var(--radius-md)',
                          padding: 'var(--space-4)', cursor: 'pointer', transition: 'all 0.2s ease',
                          display: 'flex', flexDirection: 'column', gap: 'var(--space-2)',
                          background: 'var(--bg-surface)'
                        }}
                        onMouseEnter={e => {
                          e.currentTarget.style.borderColor = 'var(--color-primary)'
                          e.currentTarget.style.boxShadow = 'var(--shadow-sm)'
                        }}
                        onMouseLeave={e => {
                          e.currentTarget.style.borderColor = 'var(--border-color)'
                          e.currentTarget.style.boxShadow = 'none'
                        }}
                      >
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                          <div>
                            <div style={{ fontWeight: 600, fontFamily: 'monospace', fontSize: 'var(--text-base)' }}>{o.order_number}</div>
                            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{o.order_date}</div>
                          </div>
                          <Badge variant={o.payment_terms === 'cash' ? 'success' : o.payment_terms === 'credit' ? 'warning' : 'info'}>
                            {o.payment_terms === 'cash' ? 'نقدي' : o.payment_terms === 'credit' ? 'آجل' : 'مختلط'}
                          </Badge>
                        </div>
                        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 'var(--text-sm)', marginTop: 'var(--space-1)' }}>
                          <span style={{ color: 'var(--text-muted)' }}>الإجمالي:</span>
                          <span style={{ fontWeight: 500, fontVariantNumeric: 'tabular-nums' }}>{formatNumber(o.total_amount)} ج.م</span>
                        </div>
                        {(o.returned_amount || 0) > 0 && (
                          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 'var(--text-sm)', color: 'var(--color-warning)' }}>
                            <span>مرتجع سابق:</span>
                            <span style={{ fontWeight: 500, fontVariantNumeric: 'tabular-nums' }}>{formatNumber(o.returned_amount)} ج.م</span>
                          </div>
                        )}
                        
                        {/* Returnable Items Summary */}
                        <div style={{ marginTop: 'var(--space-2)', paddingTop: 'var(--space-2)', borderTop: '1px dashed var(--border-color)' }}>
                          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 'var(--space-2)', display: 'flex', alignItems: 'center', gap: 4 }}>
                            <Package size={12} />
                            المنتجات القابلة للإرجاع ({itemsCount})
                          </div>
                          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                            {displayItems.map((item: any) => {
                              const availQty = item.delivered_quantity - item.returned_quantity
                              return (
                                <div key={item.id} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 'var(--text-xs)' }}>
                                  <span style={{ fontWeight: 500, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', flex: 1, paddingLeft: 8 }} title={item.product?.name}>
                                    {item.product?.name} {item.product?.sku ? `(${item.product.sku})` : ''}
                                  </span>
                                  <span style={{ color: 'var(--color-primary)', fontWeight: 600, fontVariantNumeric: 'tabular-nums', flexShrink: 0 }}>
                                    {availQty} {item.unit?.symbol || item.unit?.name}
                                  </span>
                                </div>
                              )
                            })}
                            {remainingItemsCount > 0 && (
                              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontStyle: 'italic', marginTop: 2 }}>
                                + {remainingItemsCount} منتجات أخرى
                              </div>
                            )}
                          </div>
                        </div>

                        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 'var(--text-sm)', paddingTop: 'var(--space-3)', borderTop: '1px solid var(--border-color)', marginTop: 'auto' }}>
                          <span style={{ color: 'var(--text-muted)' }}>صافي متاح تقريبياً:</span>
                          <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: 'var(--color-primary)' }}>{formatNumber(netAvail)} ج.م</span>
                        </div>
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {/* Order info */}
      {order && (
        <>
          <div className="edara-card" style={{ padding: 'var(--space-5)', marginBottom: 'var(--space-4)' }}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 'var(--space-4)' }}>
              <div>
                <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>الفاتورة</div>
                <div style={{ fontWeight: 600, fontFamily: 'monospace' }}>{order.order_number}</div>
              </div>
              <div>
                <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>العميل</div>
                <div style={{ fontWeight: 600 }}>{order.customer?.name}</div>
              </div>
              <div>
                <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>طريقة الدفع</div>
                <Badge variant={order.payment_terms === 'cash' ? 'success' : order.payment_terms === 'credit' ? 'warning' : 'info'}>
                  {order.payment_terms === 'cash' ? 'نقدي' : order.payment_terms === 'credit' ? 'آجل' : 'مختلط'}
                </Badge>
              </div>
              <div>
                <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>إجمالي الفاتورة</div>
                <div style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{formatNumber(order.total_amount)} ج.م</div>
              </div>
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 'var(--space-4)', marginTop: 'var(--space-4)' }}>
              <div>
                <label className="form-label">المخزن</label>
                <select className="form-select" value={warehouseId} onChange={e => setWarehouseId(e.target.value)}>
                  <option value="">— نفس مخزن الفاتورة —</option>
                  {warehouses.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
                </select>
              </div>
              <div>
                <label className="form-label">سبب الإرجاع</label>
                <input className="form-input" value={reason} onChange={e => setReason(e.target.value)}
                  placeholder="منتج تالف / خطأ كمية / ..." />
              </div>
              <div>
                <label className="form-label">ملاحظات</label>
                <input className="form-input" value={notes} onChange={e => setNotes(e.target.value)}
                  placeholder="ملاحظات إضافية..." />
              </div>
            </div>
          </div>

          {/* Items */}
          <div className="edara-card" style={{ padding: 'var(--space-5)', marginBottom: 'var(--space-4)' }}>
            <div className="flex" style={{ justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-4)' }}>
              <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 600 }}>
                بنود الفاتورة القابلة للإرجاع ({lines.length})
              </h3>
              <Button variant="ghost" size="sm" onClick={returnAll}>
                إرجاع الكل
              </Button>
            </div>

            {lines.length === 0 ? (
              <div style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)' }}>
                <AlertTriangle size={40} style={{ opacity: 0.4, marginBottom: 'var(--space-2)' }} />
                <div>لا توجد بنود قابلة للإرجاع</div>
              </div>
            ) : (
              <div style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--text-sm)' }}>
                  <thead>
                    <tr style={{ borderBottom: '2px solid var(--border-color)', textAlign: 'right' }}>
                      <th style={{ padding: 'var(--space-2)' }}>المنتج</th>
                      <th style={{ padding: 'var(--space-2)', width: 80 }}>الوحدة</th>
                      <th style={{ padding: 'var(--space-2)', width: 90 }}>المسلّم</th>
                      <th style={{ padding: 'var(--space-2)', width: 90 }}>تم إرجاعه</th>
                      <th style={{ padding: 'var(--space-2)', width: 90 }}>الحد الأقصى</th>
                      <th style={{ padding: 'var(--space-2)', width: 100 }}>كمية الإرجاع</th>
                      <th style={{ padding: 'var(--space-2)', width: 90 }}>السعر</th>
                      <th style={{ padding: 'var(--space-2)', width: 110 }}>الإجمالي</th>
                    </tr>
                  </thead>
                  <tbody>
                    {lines.map((line, idx) => (
                      <tr key={line.orderItemId} style={{
                        borderBottom: '1px solid var(--border-color)',
                        background: line.returnQty > 0 ? 'rgba(var(--color-primary-rgb, 59,130,246), 0.04)' : undefined,
                      }}>
                        <td style={{ padding: 'var(--space-2)' }}>
                          <div style={{ fontWeight: 500 }}>{line.productName}</div>
                          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{line.productSku}</div>
                        </td>
                        <td style={{ padding: 'var(--space-2)' }}>{line.unitSymbol}</td>
                        <td style={{ padding: 'var(--space-2)', fontVariantNumeric: 'tabular-nums' }}>{line.deliveredQty}</td>
                        <td style={{ padding: 'var(--space-2)', fontVariantNumeric: 'tabular-nums', color: line.returnedQty > 0 ? 'var(--color-warning)' : 'var(--text-muted)' }}>
                          {line.returnedQty}
                        </td>
                        <td style={{ padding: 'var(--space-2)', fontVariantNumeric: 'tabular-nums', fontWeight: 600 }}>
                          {line.maxQty}
                        </td>
                        <td style={{ padding: 'var(--space-2)' }}>
                          <input className="form-input" type="number"
                            min={0} max={line.maxQty} step="1"
                            style={{
                              width: 80, fontSize: 'var(--text-sm)', padding: 'var(--space-1)',
                              borderColor: line.returnQty > 0 ? 'var(--color-primary)' : undefined,
                              fontWeight: line.returnQty > 0 ? 600 : undefined,
                            }}
                            value={line.returnQty}
                            onChange={e => updateQty(idx, Number(e.target.value))} />
                        </td>
                        <td style={{ padding: 'var(--space-2)', fontVariantNumeric: 'tabular-nums' }}>
                          {formatNumber(line.unitPrice)}
                        </td>
                        <td style={{ padding: 'var(--space-2)', fontWeight: 600, fontVariantNumeric: 'tabular-nums', color: line.lineTotal > 0 ? 'var(--color-primary)' : 'var(--text-muted)' }}>
                          {line.lineTotal > 0 ? formatNumber(line.lineTotal) : '—'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* Totals & Save */}
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', flexWrap: 'wrap', gap: 'var(--space-4)' }}>
              <div style={{ minWidth: 250 }}>
                <div className="flex" style={{ justifyContent: 'space-between', marginBottom: 'var(--space-2)' }}>
                  <span style={{ color: 'var(--text-muted)' }}>بنود محددة</span>
                  <span style={{ fontWeight: 600 }}>{selectedLines.length} من {lines.length}</span>
                </div>
                <div className="flex" style={{
                  justifyContent: 'space-between', paddingTop: 'var(--space-3)',
                  borderTop: '2px solid var(--border-color)', fontWeight: 700, fontSize: 'var(--text-lg)',
                }}>
                  <span>إجمالي المرتجع</span>
                  <span style={{ fontVariantNumeric: 'tabular-nums', color: 'var(--color-primary)' }}>
                    {formatNumber(totalAmount)} ج.م
                  </span>
                </div>
                {order.payment_terms === 'cash' && (
                  <div style={{ marginTop: 'var(--space-2)', fontSize: 'var(--text-xs)', color: 'var(--color-warning)', display: 'flex', alignItems: 'center', gap: 'var(--space-1)' }}>
                    <AlertTriangle size={12} />
                    <span>مرتجع نقدي — سيتطلب تحديد خزينة/عهدة عند التأكيد</span>
                  </div>
                )}
                {order.payment_terms === 'credit' && (
                  <div style={{ marginTop: 'var(--space-2)', fontSize: 'var(--text-xs)', color: 'var(--color-info)' }}>
                    مرتجع آجل — سيُخصم المبلغ تلقائياً من مديونية العميل
                  </div>
                )}
              </div>
              <div className="flex gap-3">
                <Button variant="ghost" onClick={() => navigate(-1)}>إلغاء</Button>
                <Button icon={<Save size={16} />} onClick={handleSave}
                  disabled={loading || selectedLines.length === 0}>
                  {loading ? 'جاري الحفظ...' : 'حفظ المرتجع'}
                </Button>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
