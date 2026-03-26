import { useState, useEffect, useMemo } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { toast } from 'sonner'
import { ArrowRight, RotateCcw, Save, AlertTriangle } from 'lucide-react'
import { useWarehouses } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { supabase } from '@/lib/supabase/client'
import { getSalesOrder, createSalesReturn, getReturnableItems } from '@/lib/services/sales'
import { formatNumber } from '@/lib/utils/format'
import type {
  SalesOrder, SalesOrderItem, SalesReturnInput, SalesReturnItemInput,
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

export default function SalesReturnForm() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const orderId = searchParams.get('orderId') || ''

  const { data: warehouses = [] } = useWarehouses({ isActive: true })

  const [loading, setLoading] = useState(false)
  const [orderLoading, setOrderLoading] = useState(true)
  const [order, setOrder] = useState<SalesOrder | null>(null)
  const [orderSearch, setOrderSearch] = useState('')
  const [orderResults, setOrderResults] = useState<SalesOrder[]>([])

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

  // Order search (when no orderId in URL)
  useEffect(() => {
    if (orderSearch.length < 3 || orderId) { setOrderResults([]); return }
    const timeout = setTimeout(async () => {
      const { data } = await supabase
        .from('sales_orders')
        .select('id, order_number, customer:customers(id, name, code), total_amount, status')
        .in('status', ['delivered', 'completed'])
        .ilike('order_number', `%${orderSearch}%`)
        .limit(8)
      setOrderResults(data as any[] || [])
    }, 300)
    return () => clearTimeout(timeout)
  }, [orderSearch, orderId])

  const handleSelectOrder = (o: any) => {
    setOrderResults([])
    setOrderSearch('')
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
        subtitle={order ? `من الفاتورة #${order.order_number}` : 'اختر الفاتورة أولاً'}
        actions={
          <Button variant="ghost" onClick={() => navigate('/sales/returns')}>
            <ArrowRight size={16} /> رجوع
          </Button>
        }
      />

      {/* Order selection (when no orderId) */}
      {!order && (
        <div className="edara-card" style={{ padding: 'var(--space-5)', marginBottom: 'var(--space-4)' }}>
          <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 600, marginBottom: 'var(--space-3)' }}>اختر الفاتورة</h3>
          <div style={{ position: 'relative', maxWidth: 400 }}>
            <input className="form-input" placeholder="ابحث برقم الفاتورة..."
              value={orderSearch}
              onChange={e => setOrderSearch(e.target.value)} />
            {orderResults.length > 0 && (
              <div style={{
                position: 'absolute', zIndex: 50, top: '100%', left: 0, right: 0,
                background: 'var(--bg-surface)', border: '1px solid var(--border-color)',
                borderRadius: 'var(--radius-md)', boxShadow: 'var(--shadow-lg)',
                maxHeight: 250, overflow: 'auto',
              }}>
                {orderResults.map(o => (
                  <div key={o.id} onClick={() => handleSelectOrder(o)}
                    style={{ padding: 'var(--space-3)', cursor: 'pointer', borderBottom: '1px solid var(--border-color)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}
                    onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
                    onMouseLeave={e => (e.currentTarget.style.background = '')}>
                    <div>
                      <div style={{ fontWeight: 600, fontFamily: 'monospace' }}>{o.order_number}</div>
                      <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{(o as any).customer?.name}</div>
                    </div>
                    <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
                      {formatNumber(o.total_amount)} ج.م
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
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
