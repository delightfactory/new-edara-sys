import { useState, useEffect, useCallback } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, Edit, CheckCircle, Truck, XCircle,
  RotateCcw, FileText, Clock, User, CreditCard,
  Package, Building2, Banknote, Warehouse, AlertTriangle,
  TrendingUp, TrendingDown, Info, Copy, ChevronDown, Receipt,
  CheckCircle2, XOctagon, AlertCircle, ImageIcon,
} from 'lucide-react'
import ProofUploadButton from '@/components/ui/ProofUploadButton'
import { useAuthStore } from '@/stores/auth-store'
import { useWarehouses, useInvalidate } from '@/hooks/useQueryHooks'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase/client'
import { getMyWarehouses } from '@/lib/services/inventory'
import {
  getSalesOrder,
  confirmSalesOrderWithWarehouse,
  deliverSalesOrder,
  cancelSalesOrder,
  checkCustomerCredit,
  getUserPaymentOptions,
} from '@/lib/services/sales'
import { uploadPaymentProof } from '@/lib/services/payments'
import type { CustomerCreditInfo, UserPaymentOptions } from '@/lib/services/sales'
import { formatNumber } from '@/lib/utils/format'
import type { SalesOrder, PaymentTerms, SalesOrderStatus } from '@/lib/types/master-data'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'

// ── Labels ─────────────────────────────────────────────────────
const statusLabels: Record<SalesOrderStatus, string> = {
  draft: 'مسودة', confirmed: 'مؤكد', partially_delivered: 'مسلّم جزئياً',
  delivered: 'مُسلّم', completed: 'مكتمل', cancelled: 'ملغي',
}
const statusColors: Record<SalesOrderStatus, { bg: string; color: string }> = {
  draft:               { bg: 'var(--bg-secondary, #f3f4f6)', color: 'var(--text-muted, #6b7280)' },
  confirmed:           { bg: 'var(--color-info-light, #eff6ff)', color: 'var(--color-info, #2563eb)' },
  partially_delivered: { bg: 'var(--color-info-light, #f0f9ff)', color: 'var(--color-info, #0284c7)' },
  delivered:           { bg: 'var(--color-success-light, #f0fdf4)', color: 'var(--color-success, #16a34a)' },
  completed:           { bg: 'var(--color-success-light, #f0fdf4)', color: 'var(--color-success, #16a34a)' },
  cancelled:           { bg: 'var(--color-danger-light, #fef2f2)', color: 'var(--color-danger, #dc2626)' },
}
const termLabels: Record<string, string> = { cash: 'نقدي', credit: 'آجل', mixed: 'مختلط' }

// طرق الدفع الفورية (نقدي فعلي) مقابل المؤجلة (تنتظر تأكيد المحاسب)
const COLLECT_METHODS = [
  { value: 'cash',          label: 'نقدي',             isCash: true  },
  { value: 'bank_transfer', label: 'تحويل بنكي',       isCash: false },
  { value: 'instapay',      label: 'إنستاباي',         isCash: false },
  { value: 'mobile_wallet', label: 'محفظة إلكترونية', isCash: false },
  { value: 'cheque',        label: 'شيك بنكي',      isCash: false },
]

// ── Deliver Form ────────────────────────────────────────────
interface DeliverFormState {
  paymentTerms: PaymentTerms
  cashAmount: number
  paymentMethod: string     // 'cash' | 'bank_transfer' | 'instapay' | 'mobile_wallet' | 'cheque'
  vaultId: string
  custodyId: string
  overrideCredit: boolean
  bankReference: string     // مرجع التحويل البنكي / إنستاباي
  checkNumber: string       // رقم الشيك
  checkDate: string         // تاريخ استحقاق الشيك
}

const defaultDeliverForm = (remaining: number): DeliverFormState => ({
  paymentTerms: 'cash', cashAmount: remaining,
  paymentMethod: 'cash',
  vaultId: '', custodyId: '', overrideCredit: false,
  bankReference: '', checkNumber: '', checkDate: '',
})

// طرق الدفع التي تستلزم إثبات إجباري
const PROOF_REQUIRED_METHODS = ['bank_transfer', 'instapay', 'mobile_wallet', 'cheque']

// ── Main Component ──────────────────────────────────────────────
export default function SalesOrderDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const invalidate = useInvalidate()

  const [order, setOrder] = useState<SalesOrder | null>(null)
  const [loading, setLoading] = useState(true)
  const [actionLoading, setActionLoading] = useState(false)
  const [showItems, setShowItems] = useState(false)

  const [showConfirmModal, setShowConfirmModal] = useState(false)
  const [confirmWarehouseId, setConfirmWarehouseId] = useState('')
  const [stockAvailability, setStockAvailability] = useState<{ productName: string; required: number; available: number; ok: boolean }[]>([])
  const [stockCheckLoading, setStockCheckLoading] = useState(false)

  const [showDeliverModal, setShowDeliverModal] = useState(false)
  const [deliverLoading, setDeliverLoading] = useState(false)
  const [creditInfo, setCreditInfo] = useState<CustomerCreditInfo | null>(null)
  const [paymentOptions, setPaymentOptions] = useState<UserPaymentOptions | null>(null)
  const [deliverForm, setDeliverForm] = useState<DeliverFormState>(defaultDeliverForm(0))
  const [proofFile, setProofFile] = useState<File | null>(null)

  const [showCancelModal, setShowCancelModal] = useState(false)
  const [cancelReason, setCancelReason] = useState('')

  const { data: warehouses = [] } = useWarehouses({ isActive: true })
  const isAdmin = can('inventory.read_all')

  // مخازن المستخدم — cached React Query (نجلب دائماً حتى لو isAdmin)
  const { data: myWarehouses = [] } = useQuery({
    queryKey: ['my-warehouses'],
    queryFn: () => getMyWarehouses(),
    staleTime: 5 * 60 * 1000,
  })

  const loadOrder = useCallback(async () => {
    if (!id) return
    try {
      setLoading(true)
      const data = await getSalesOrder(id)
      setOrder(data)
    } catch {
      toast.error('فشل تحميل الطلب')
    } finally {
      setLoading(false)
    }
  }, [id])

  useEffect(() => { loadOrder() }, [loadOrder])

  // جلب إيصالات الدفع المرتبطة بالطلب
  const { data: orderReceipts = [] } = useQuery({
    queryKey: ['order-receipts', id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('payment_receipts')
        .select('id, number, amount, payment_method, status, created_at, proof_url, bank_reference, check_number, check_date')
        .eq('sales_order_id', id!)
        .order('created_at', { ascending: false })
      if (error) return []
      return data as {
        id: string; number: string; amount: number; payment_method: string
        status: string; created_at: string; proof_url: string | null
        bank_reference: string | null; check_number: string | null; check_date: string | null
      }[]
    },
    enabled: !!id && !!order && order.status !== 'draft' && order.status !== 'cancelled',
  })

  const remaining = order
    ? Math.max(order.total_amount - (order.paid_amount || 0) - (order.returned_amount || 0), 0)
    : 0

  // ── Open Deliver Modal ──────────────────────────────────────
  const openDeliverModal = async () => {
    if (!order) return
    setShowDeliverModal(true)
    setDeliverLoading(true)
    setDeliverForm(defaultDeliverForm(remaining))
    setProofFile(null)
    try {
      const [credit, opts] = await Promise.all([
        checkCustomerCredit(order.customer_id, remaining),
        getUserPaymentOptions(order.branch_id),
      ])
      setCreditInfo(credit)
      setPaymentOptions(opts)

      // تحديد شروط الدفع الافتراضية بناءً على بيانات العميل
      let initialTerms: PaymentTerms = 'cash'
      let initialCash = remaining
      if (credit.payment_terms === 'credit' && credit.credit_ok) {
        initialTerms = 'credit'; initialCash = 0
      } else if (credit.can_use_credit && credit.available_credit > 0 && credit.available_credit < remaining) {
        initialTerms = 'mixed'; initialCash = Math.max(remaining - credit.available_credit, 0)
      } else if (credit.can_use_credit && credit.available_credit >= remaining) {
        initialTerms = 'credit'; initialCash = 0
      }

      let initCustodyId = '', initVaultId = ''
      if (opts.cash_destination === 'custody' && opts.custody_id) initCustodyId = opts.custody_id
      else if (opts.cash_destination === 'vault' && opts.available_vaults.length > 0)
        initVaultId = opts.available_vaults[0].id

      setDeliverForm(f => ({ ...f, paymentTerms: initialTerms, cashAmount: initialCash, custodyId: initCustodyId, vaultId: initVaultId }))
    } catch (e: any) {
      toast.error('فشل تحميل بيانات التسليم: ' + e.message)
    } finally {
      setDeliverLoading(false)
    }
  }

  const onChangePaymentTerms = (terms: PaymentTerms) => {
    let newCash = remaining
    if (terms === 'credit') newCash = 0
    else if (terms === 'mixed' && creditInfo) newCash = Math.max(remaining - creditInfo.available_credit, 0)
    // نقدي = كامل المبلغ (قابل للتعديل من حقل المبلغ)
    setDeliverForm(f => ({ ...f, paymentTerms: terms, cashAmount: newCash }))
  }

  // عند تعديل المبلغ النقدي: لو أقل من الإجمالي → مختلط تلقائياً
  const onChangeCashAmount = (val: number) => {
    const v = Math.min(Math.max(val, 0), remaining)
    let terms = deliverForm.paymentTerms as PaymentTerms
    if (v <= 0 && creditInfo?.can_use_credit) terms = 'credit'
    else if (v < remaining && creditInfo?.can_use_credit) terms = 'mixed'
    else if (v >= remaining) terms = 'cash'
    setDeliverForm(f => ({ ...f, cashAmount: v, paymentTerms: terms }))
  }

  const creditAmount = deliverForm.paymentTerms === 'credit' ? remaining
    : deliverForm.paymentTerms === 'mixed' ? Math.max(remaining - deliverForm.cashAmount, 0) : 0

  const canDeliverCredit = !creditInfo || creditInfo.credit_ok || deliverForm.overrideCredit
    || (creditInfo.can_use_credit && creditAmount <= creditInfo.available_credit)
  const minCash = creditInfo ? Math.max(0, remaining - creditInfo.available_credit) : 0

  // هل طريقة الدفع المختارة نقدية فورية؟
  const isCashNow = COLLECT_METHODS.find(m => m.value === deliverForm.paymentMethod)?.isCash ?? true
  // هل الطريقة الحالية تتطلب إثبات إجباري؟
  const isProofRequired = PROOF_REQUIRED_METHODS.includes(deliverForm.paymentMethod)

  // التحقق من جاهزية التسليم
  const canDeliverAction = (
    deliverForm.paymentTerms === 'cash' || canDeliverCredit
  ) && (
    // الآجل الصريح لا يحتاج وجهة
    deliverForm.paymentTerms === 'credit' ||
    // غير نقدي (تحويل/إنستاباي/محفظة) → pending receipt، لا يحتاج خزنة الآن
    !isCashNow ||
    // نقدي → يحتاج عهدة أو خزينة
    !!(deliverForm.custodyId || deliverForm.vaultId)
  ) && (
    // إثبات الدفع إجباري لغير النقدي
    !isProofRequired || !!proofFile
  )

  // ── Handle Deliver ───────────────────────────────────────────
  const handleDeliver = async () => {
    if (!order) return

    // النقدي الفوري يحتاج وجهة تحصيل
    if (deliverForm.paymentTerms !== 'credit' && isCashNow && !deliverForm.custodyId && !deliverForm.vaultId) {
      toast.error('يجب تحديد العهدة أو الخزينة لاستقبال المبلغ النقدي'); return
    }
    // إثبات الدفع إجباري للتحويلات والشيكات
    if (isProofRequired && !proofFile) {
      toast.error('إثبات الدفع مطلوب لهذه الطريقة — يرجى رفع صورة أو ملف')
      return
    }

    setActionLoading(true)
    try {
      // رفع الإثبات (إن وُجد) قبل الاتصال بالـ RPC
      let proofUrl: string | undefined
      if (proofFile) {
        proofUrl = await uploadPaymentProof(proofFile)
      }

      await deliverSalesOrder(id!, {
        paymentTerms: deliverForm.paymentTerms,
        cashAmount: deliverForm.paymentTerms === 'credit' ? 0 : deliverForm.cashAmount,
        paymentMethod: deliverForm.paymentTerms === 'credit' ? null : deliverForm.paymentMethod as any,
        vaultId: isCashNow ? (deliverForm.vaultId || null) : null,
        custodyId: isCashNow ? (deliverForm.custodyId || null) : null,
        overrideCredit: deliverForm.overrideCredit,
        bankReference: deliverForm.bankReference || null,
        checkNumber: deliverForm.checkNumber || null,
        checkDate: deliverForm.checkDate || null,
        proofUrl: proofUrl || null,
      })

      const msg = isCashNow
        ? 'تم التسليم وتسجيل التحصيل بنجاح ✓'
        : 'تم التسليم — الإيصال بانتظار مراجعة المحاسب المالي ✓'
      toast.success(msg)
      setShowDeliverModal(false)
      invalidate('sales-orders', 'sales-stats', 'stock', 'vaults', 'custody-accounts', 'payment-receipts', 'targets', 'target-detail', 'target-progress-history', 'target-reward-summary')
      await loadOrder()
    } catch (e: any) { toast.error(e.message || 'فشل التسليم') }
    finally { setActionLoading(false) }
  }

  const handleConfirm = async () => {
    if (!confirmWarehouseId) { toast.error('يرجى اختيار المخزن'); return }
    setActionLoading(true)
    try {
      await confirmSalesOrderWithWarehouse(id!, confirmWarehouseId)
      toast.success('تم تأكيد الطلب وحجز المخزون ✓')
      setShowConfirmModal(false)
      invalidate('sales-orders', 'sales-stats', 'stock')
      await loadOrder()
    } catch (e: any) { toast.error(e.message || 'فشل التأكيد') }
    finally { setActionLoading(false) }
  }

  // Stock availability check when warehouse is selected in confirm modal
  const checkStockAvailability = async (warehouseId: string) => {
    setConfirmWarehouseId(warehouseId)
    if (!warehouseId || !order?.items?.length) { setStockAvailability([]); return }
    setStockCheckLoading(true)
    try {
      const { getAvailableStock } = await import('@/lib/services/inventory')
      const checks = await Promise.all(
        order.items.map(async (item: any) => {
          try {
            const available = await getAvailableStock(warehouseId, item.product_id)
            return {
              productName: item.product?.name || item.product_id,
              required: item.base_quantity || item.quantity,
              available,
              ok: available >= (item.base_quantity || item.quantity),
            }
          } catch {
            return {
              productName: item.product?.name || item.product_id,
              required: item.base_quantity || item.quantity,
              available: 0,
              ok: false,
            }
          }
        })
      )
      setStockAvailability(checks)
    } catch { setStockAvailability([]) }
    finally { setStockCheckLoading(false) }
  }

  const handleCancel = async () => {
    setActionLoading(true)
    try {
      await cancelSalesOrder(id!, cancelReason)
      toast.success('تم إلغاء الطلب')
      setShowCancelModal(false)
      invalidate('sales-orders', 'sales-stats', 'stock')
      await loadOrder()
    } catch (e: any) { toast.error(e.message || 'فشل الإلغاء') }
    finally { setActionLoading(false) }
  }

  // ── Loading / Not Found ────────────────────────────────────
  if (loading) return (
    <div style={{ padding: '16px', maxWidth: 800, margin: '0 auto' }}>
      {[1, 2, 3].map(i => <div key={i} className="skeleton" style={{ height: i === 1 ? 80 : 120, marginBottom: 12, borderRadius: 12 }} />)}
    </div>
  )
  if (!order) return (
    <div style={{ padding: 24, textAlign: 'center', color: 'var(--text-muted)' }}>الطلب غير موجود</div>
  )

  const sc = statusColors[order.status]
  const paidRatio = order.total_amount > 0 ? ((order.paid_amount || 0)) / order.total_amount : 0
  const itemCount = order.items?.length || 0

  // ══════════════════════════════════════════════════════════════
  // RENDER
  // ══════════════════════════════════════════════════════════════
  return (
    <div style={{ maxWidth: 800, margin: '0 auto', padding: '0 0 80px' }}>

      {/* ══ Hero Header ══════════════════════════════════════════ */}
      <div style={{
        background: `linear-gradient(135deg, ${sc.color}12, ${sc.color}06)`,
        borderBottom: `3px solid ${sc.color}30`,
        padding: '16px 16px 14px',
        position: 'sticky', top: 0, zIndex: 10,
        backdropFilter: 'blur(12px)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
          <button onClick={() => navigate('/sales/orders')}
            style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 10, padding: '7px 10px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4, fontSize: 13, color: 'var(--text-secondary)', flexShrink: 0 }}>
            <ArrowRight size={14} /> رجوع
          </button>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <h1 style={{ fontSize: 18, fontWeight: 800, margin: 0, whiteSpace: 'nowrap' }}>
                طلب #{order.order_number}
              </h1>
              <span style={{ fontSize: 11, fontWeight: 700, padding: '3px 10px', borderRadius: 99, background: sc.bg, color: sc.color }}>
                {statusLabels[order.status]}
              </span>
            </div>
            <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 2 }}>
              {order.customer?.name}
            </div>
          </div>
        </div>

        {/* Action Buttons — scrollable */}
        <div style={{ display: 'flex', gap: 8, overflowX: 'auto', paddingBottom: 2, scrollbarWidth: 'none' }}>
          {order.status === 'draft' && can('sales.orders.update') && (
            <ActionBtn icon={<Edit size={13} />} label="تعديل"
              onClick={() => navigate(`/sales/orders/${id}/edit`)} />
          )}
          {order.status === 'draft' && can('sales.orders.confirm') && (
            <ActionBtn icon={<CheckCircle size={13} />} label="تأكيد" primary
              onClick={async () => {
                // تعيين ذكي: من cache أو من الخادم مباشرة إن لم تكتمل بعد
                let resolvedMyWh = myWarehouses as typeof myWarehouses
                if (resolvedMyWh.length === 0) {
                  try { resolvedMyWh = await getMyWarehouses() } catch { resolvedMyWh = [] }
                }
                const defaultWh = resolvedMyWh.length > 0 ? resolvedMyWh[0].id : ''
                setConfirmWarehouseId(defaultWh)
                setShowConfirmModal(true)
                if (defaultWh) checkStockAvailability(defaultWh)
              }}
              disabled={actionLoading} />
          )}
          {order.status === 'confirmed' && can('sales.orders.deliver') && (
            <ActionBtn icon={<Truck size={13} />} label="تسليم" primary
              onClick={openDeliverModal} disabled={actionLoading} />
          )}
          {(order.status === 'delivered' || order.status === 'completed') && can('sales.returns.create') && (
            <ActionBtn icon={<RotateCcw size={13} />} label="مرتجع"
              onClick={() => navigate(`/sales/returns/new?orderId=${order.id}`)} />
          )}
          {can('sales.orders.create') && (
            <ActionBtn icon={<Copy size={13} />} label="نسخ"
              onClick={() => navigate(`/sales/orders/new?copyFrom=${id}`)} />
          )}
          {(order.status === 'draft' || order.status === 'confirmed') && can('sales.orders.cancel') && (
            <ActionBtn icon={<XCircle size={13} />} label="إلغاء" danger
              onClick={() => setShowCancelModal(true)} disabled={actionLoading} />
          )}
        </div>
      </div>

      {/* ══ Financial Summary Bar ════════════════════════════════ */}
      <div style={{ display: 'flex', gap: 0, background: 'var(--bg-surface)', borderBottom: '1px solid var(--border-primary)' }}>
        <FinBadge label="الإجمالي" value={`${formatNumber(order.total_amount)}`} unit="ج.م" color="var(--color-primary)" />
        {order.status !== 'draft' && order.status !== 'cancelled' && (
          <>
            <div style={{ width: 1, background: 'var(--border-primary)' }} />
            <FinBadge label="مدفوع" value={`${formatNumber(order.paid_amount || 0)}`} unit="ج.م"
              color={paidRatio >= 1 ? 'var(--color-success)' : 'var(--color-warning)'} />
            <div style={{ width: 1, background: 'var(--border-primary)' }} />
            <FinBadge label="متبقي" value={`${formatNumber(remaining)}`} unit="ج.م"
              color={remaining <= 0 ? 'var(--color-success)' : 'var(--color-danger)'} />
          </>
        )}
      </div>

      <div style={{ padding: '12px 12px 0' }}>

        {/* ══ Order Info Card ══════════════════════════════════════ */}
        <div style={card}>
          <SectionHead icon={<FileText size={14} />} title="بيانات الطلب" />
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '10px 16px' }}>
            <InfoPair icon={<User size={12} />} label="العميل" value={order.customer?.name} />
            <InfoPair icon={<User size={12} />} label="المندوب" value={order.rep?.full_name || '—'} />
            <InfoPair icon={<Clock size={12} />} label="تاريخ الطلب" value={new Date(order.order_date).toLocaleDateString('ar-EG-u-nu-latn')} />
            <InfoPair icon={<Building2 size={12} />} label="الفرع" value={order.branch?.name || '—'} />
            <InfoPair icon={<Warehouse size={12} />} label="المخزن"
              value={order.warehouse?.name || (order.status === 'draft' ? 'يُحدَّد عند التأكيد' : '—')}
              muted={!order.warehouse_id} />
            <InfoPair icon={<Banknote size={12} />} label="شروط الدفع"
              value={termLabels[order.payment_terms || ''] || order.payment_terms || '—'} />
            {order.due_date && (
              <InfoPair icon={<Clock size={12} />} label="الاستحقاق"
                value={new Date(order.due_date).toLocaleDateString('ar-EG-u-nu-latn')} />
            )}
          </div>
        </div>

        {/* ══ Financial Details Card ═══════════════════════════════ */}
        {order.status !== 'draft' && (
          <div style={card}>
            <SectionHead icon={<CreditCard size={14} />} title="الملخص المالي" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <FinRow label="الإجمالي الفرعي" value={`${formatNumber(order.subtotal)} ج.م`} />
              {order.discount_amount > 0 && (
                <FinRow label="الخصم" value={`- ${formatNumber(order.discount_amount)} ج.م`} valueColor="var(--color-danger)" />
              )}
              {order.tax_amount > 0 && <FinRow label="الضريبة" value={`${formatNumber(order.tax_amount)} ج.م`} />}
              {order.shipping_on_customer && order.shipping_cost > 0 && (
                <FinRow label="الشحن" value={`${formatNumber(order.shipping_cost)} ج.م`} />
              )}
              <div style={{ borderTop: '2px solid var(--border-primary)', paddingTop: 8, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontWeight: 700, fontSize: 14 }}>الإجمالي</span>
                <span style={{ fontWeight: 800, fontSize: 16, color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>
                  {formatNumber(order.total_amount)} ج.م
                </span>
              </div>
              <FinRow icon={<TrendingDown size={12} />} label="المدفوع"
                value={`${formatNumber(order.paid_amount || 0)} ج.م`}
                valueColor={paidRatio >= 1 ? 'var(--color-success)' : 'var(--color-warning)'} />
              {(order.returned_amount || 0) > 0 && (
                <FinRow label="المرتجع" value={`${formatNumber(order.returned_amount)} ج.م`} valueColor="var(--color-info)" />
              )}
              <FinRow icon={<TrendingUp size={12} />} label="المتبقي"
                value={`${formatNumber(remaining)} ج.م`}
                valueColor={remaining <= 0 ? 'var(--color-success)' : 'var(--color-danger)'} />
            </div>
          </div>
        )}

        {/* ══ Payment Receipts Card ═════════════════════════════════════ */}
        {order.status !== 'draft' && order.status !== 'cancelled' && orderReceipts.length > 0 && (
          <div style={card}>
            <SectionHead icon={<Receipt size={14} />} title={`إيصالات الدفع (${orderReceipts.length})`} />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {orderReceipts.map(r => {
                const sBg = r.status === 'confirmed' ? '#f0fdf4' : r.status === 'pending' ? '#fffbeb' : '#fef2f2'
                const sColor = r.status === 'confirmed' ? '#16a34a' : r.status === 'pending' ? '#d97706' : '#dc2626'
                const sLabel = r.status === 'confirmed' ? 'مؤكد' : r.status === 'pending' ? 'معلق' : 'مرفوض'
                const mIcon: Record<string, string> = { cash: '💵', bank_transfer: '🏦', instapay: '⚡', cheque: '📋', mobile_wallet: '📱' }
                const mLabel: Record<string, string> = { cash: 'نقدي', bank_transfer: 'تحويل بنكي', instapay: 'إنستاباي', cheque: 'شيك', mobile_wallet: 'محفظة' }
                return (
                  <div key={r.id} style={{
                    borderRadius: 10, border: '1px solid var(--border-primary)',
                    overflow: 'hidden', background: 'var(--bg-surface-2)',
                  }}>
                    {/* Header row */}
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 12px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                        <span>{mIcon[r.payment_method] || '💳'}</span>
                        <div>
                          <div style={{ fontSize: 12, fontWeight: 700, direction: 'ltr', display: 'inline-block' }}>#{r.number}</div>
                          <div style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 1 }}>
                            {mLabel[r.payment_method] || r.payment_method} • {new Date(r.created_at).toLocaleDateString('ar-EG-u-nu-latn')}
                          </div>
                        </div>
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                        <span style={{ fontWeight: 700, fontSize: 14, fontVariantNumeric: 'tabular-nums', color: 'var(--color-primary)' }}>
                          {formatNumber(r.amount)} ج.م
                        </span>
                        <span style={{ fontSize: 10, fontWeight: 700, padding: '3px 9px', borderRadius: 99, background: sBg, color: sColor }}>
                          {sLabel}
                        </span>
                      </div>
                    </div>
                    {/* Reference / cheque details */}
                    {(r.bank_reference || r.check_number) && (
                      <div style={{ padding: '4px 12px 6px', fontSize: 10, color: 'var(--text-muted)', fontFamily: 'monospace', direction: 'ltr', textAlign: 'start', borderTop: '1px solid var(--border-primary)' }}>
                        {r.bank_reference && <span>Ref: {r.bank_reference}</span>}
                        {r.check_number && <span>  شيك #{r.check_number}{r.check_date ? ` | ${r.check_date}` : ''}</span>}
                      </div>
                    )}
                    {/* Proof image */}
                    {r.proof_url && (
                      <div style={{ padding: '6px 12px 8px', borderTop: '1px solid var(--border-primary)' }}>
                        <a href={r.proof_url} target="_blank" rel="noreferrer"
                          style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 11, color: 'var(--color-primary)', textDecoration: 'none', fontWeight: 600 }}>
                          <ImageIcon size={12} />
                          عرض إثبات الدفع
                        </a>
                      </div>
                    )}
                  </div>
                )
              })}
            </div>

            {/* ⚠️ تحذير: مرتجع نقدي مقابل شيك/تحويل قيد التأكيد */}
            {orderReceipts.some(r =>
              (r.payment_method === 'cheque' || r.payment_method === 'bank_transfer' || r.payment_method === 'instapay')
              && r.status !== 'rejected'
            ) && (
              <div style={{
                marginTop: 8, padding: '8px 10px', borderRadius: 8, fontSize: 11,
                background: '#fffbeb', border: '1px solid #fde68a',
                color: '#92400e', display: 'flex', gap: 6, alignItems: 'flex-start',
              }}>
                <AlertTriangle size={12} style={{ flexShrink: 0, marginTop: 1 }} />
                <span>
                  <strong>تنبيه مالي:</strong> بعض إيصالات هذا الطلب بشيكات أو تحويلات بنكية.
                  تأكّد من تحصيلها فعلياً قبل صرف أي مرتجع نقدي.
                </span>
              </div>
            )}
          </div>
        )}

        {/* ══ Items Card ═══════════════════════════════════════════ */}
        <div style={card}>
          <button
            onClick={() => setShowItems(v => !v)}
            style={{ width: '100%', background: 'none', border: 'none', cursor: 'pointer', padding: 0, textAlign: 'right' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ ...iconBox, background: '#6366f115', color: '#6366f1' }}><Package size={14} /></span>
                <span style={{ fontWeight: 700, fontSize: 13 }}>البنود ({itemCount} منتج)</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ fontSize: 12, color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>
                  {formatNumber(order.total_amount)} ج.م
                </span>
                <ChevronDown size={16} style={{ color: 'var(--text-muted)', transform: showItems ? 'rotate(180deg)' : 'none', transition: 'transform 0.2s' }} />
              </div>
            </div>
          </button>

          {showItems && (
            <div style={{ marginTop: 12 }}>
              {(order.items || []).map((item, i) => (
                <div key={item.id} style={{ padding: '10px 0', borderTop: '1px solid var(--divider)' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 8 }}>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontWeight: 600, fontSize: 13, marginBottom: 2 }}>{item.product?.name}</div>
                      <div style={{ fontSize: 11, color: 'var(--text-muted)', fontFamily: 'monospace' }}>{item.product?.sku}</div>
                    </div>
                    <div style={{ textAlign: 'left', flexShrink: 0 }}>
                      <div style={{ fontWeight: 700, fontSize: 13, color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>
                        {formatNumber(item.line_total)} ج.م
                      </div>
                    </div>
                  </div>
                  <div style={{ display: 'flex', gap: 12, marginTop: 6, fontSize: 12, color: 'var(--text-muted)' }}>
                    <span>{item.quantity} {item.unit?.symbol || item.unit?.name || ''}</span>
                    <span>×</span>
                    <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatNumber(item.unit_price)} ج.م</span>
                    {item.discount_percent > 0 && <span style={{ color: 'var(--color-danger)' }}>خصم {item.discount_percent}%</span>}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* ══ Notes ════════════════════════════════════════════════ */}
        {order.notes && (
          <div style={{ ...card, fontSize: 13, color: 'var(--text-secondary)', lineHeight: 1.7 }}>
            <SectionHead icon={<FileText size={14} />} title="ملاحظات" />
            <p style={{ margin: 0 }}>{order.notes}</p>
          </div>
        )}
      </div>

      {/* ══════════════════════════════════════════ CONFIRM MODAL */}
      <ResponsiveModal open={showConfirmModal} onClose={() => { setShowConfirmModal(false); setStockAvailability([]) }} title="تأكيد الطلب">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div style={{ padding: '10px 12px', background: 'var(--color-info-light, #eff6ff)', borderRadius: 8, fontSize: 13, display: 'flex', gap: 8, alignItems: 'flex-start' }}>
            <Info size={15} style={{ color: 'var(--color-info, var(--color-primary))', flexShrink: 0, marginTop: 1 }} />
            <span>سيتم حجز المخزون عند التأكيد. اختر المخزن الذي سيُسلَّم الطلب منه.</span>
          </div>
          <div>
            <label className="form-label" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <Warehouse size={13} /> المخزن *
            </label>
            <select className="form-select" value={confirmWarehouseId}
              onChange={e => checkStockAvailability(e.target.value)}>
              <option value="">— اختر المخزن —</option>
              {(isAdmin ? warehouses : (myWarehouses.length > 0 ? myWarehouses : warehouses)).map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </div>

          {/* Stock availability results */}
          {stockCheckLoading && (
            <div style={{ textAlign: 'center', padding: 12, color: 'var(--text-muted)', fontSize: 12 }}>⏳ جاري فحص التوافر...</div>
          )}
          {stockAvailability.length > 0 && !stockCheckLoading && (
            <div style={{ borderRadius: 8, border: '1px solid var(--border-primary)', overflow: 'hidden', fontSize: 12 }}>
              {stockAvailability.map((s, i) => (
                <div key={i} style={{
                  padding: '8px 12px', display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                  borderBottom: i < stockAvailability.length - 1 ? '1px solid var(--border-primary)' : 'none',
                  background: s.ok ? 'var(--color-success-light, #f0fdf4)' : 'var(--color-danger-light, #fef2f2)',
                }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                    {s.ok
                      ? <CheckCircle2 size={14} style={{ color: 'var(--color-success)' }} />
                      : <XOctagon size={14} style={{ color: 'var(--color-danger)' }} />}
                    <span style={{ fontWeight: 500 }}>{s.productName}</span>
                  </div>
                  <span style={{ fontWeight: 600, color: s.ok ? 'var(--color-success)' : 'var(--color-danger)' }}>
                    {s.ok ? `✓ متاح (${formatNumber(s.available)})` : `متاح ${formatNumber(s.available)} من ${formatNumber(s.required)}`}
                  </span>
                </div>
              ))}
            </div>
          )}

          <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
            <button className="btn btn-secondary" onClick={() => { setShowConfirmModal(false); setStockAvailability([]) }}>إلغاء</button>
            <button className="btn btn-primary" onClick={handleConfirm}
              disabled={actionLoading || !confirmWarehouseId || (stockAvailability.length > 0 && stockAvailability.some(s => !s.ok))}>
              <CheckCircle size={15} />
              {actionLoading ? 'جاري...' : 'تأكيد'}
            </button>
          </div>
        </div>
      </ResponsiveModal>

      {/* ══════════════════════════════════════════ DELIVER MODAL */}
      <ResponsiveModal
        open={showDeliverModal}
        onClose={() => setShowDeliverModal(false)}
        title={`تسليم #${order.order_number}`}
        disableOverlayClose
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>

          {deliverLoading && (
            <div style={{ textAlign: 'center', padding: 24, color: 'var(--text-muted)', fontSize: 13 }}>
              ⏳ جاري فحص الائتمان...
            </div>
          )}

          {/* Credit Info Panel */}
          {creditInfo && !deliverLoading && (
            <div style={{ borderRadius: 10, border: '1px solid var(--border-primary)', overflow: 'hidden', fontSize: 13 }}>
              <div style={{ padding: '9px 14px', background: 'var(--bg-surface-2)', fontWeight: 600, display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 6 }}>
                <span style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12 }}>
                  <User size={13} /> {creditInfo.customer_name}
                </span>
                <span style={{ fontSize: 11, fontWeight: 700, padding: '2px 8px', borderRadius: 99,
                  background: creditInfo.payment_terms === 'cash' ? 'var(--bg-secondary, #f3f4f6)' : creditInfo.credit_ok ? 'var(--color-success-light, #f0fdf4)' : 'var(--color-danger-light, #fef2f2)',
                  color: creditInfo.payment_terms === 'cash' ? 'var(--text-muted, #6b7280)' : creditInfo.credit_ok ? 'var(--color-success, #16a34a)' : 'var(--color-danger, #dc2626)' }}>
                  {termLabels[creditInfo.payment_terms] || creditInfo.payment_terms}
                </span>
              </div>
              {creditInfo.can_use_credit && (
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', padding: '10px 14px', gap: 6, borderBottom: '1px solid var(--border-primary)' }}>
                  <CreditTile label="الرصيد" value={`${formatNumber(creditInfo.current_balance)} ج.م`} />
                  <CreditTile label="الحد" value={`${formatNumber(creditInfo.credit_limit)} ج.م`} />
                  <CreditTile label="المتاح" value={`${formatNumber(creditInfo.available_credit)} ج.م`}
                    color={creditInfo.credit_ok ? 'var(--color-success)' : 'var(--color-danger)'} />
                </div>
              )}
              {creditInfo.has_overdue && (
                <div style={{ padding: '8px 14px', display: 'flex', gap: 6, alignItems: 'center', background: 'var(--color-danger-light, #fef2f2)', color: 'var(--color-danger)', fontSize: 11 }}>
                  <AlertTriangle size={13} />
                  {creditInfo.overdue_count} فاتورة متأخرة ({creditInfo.overdue_days} يوم)
                </div>
              )}
              <div style={{ padding: '7px 14px', fontSize: 11, display: 'flex', alignItems: 'center', gap: 6,
                color: creditInfo.credit_ok ? 'var(--color-success)' : 'var(--color-danger)',
                background: creditInfo.credit_ok ? 'var(--color-success-light, #f0fdf4)' : 'var(--color-danger-light, #fef2f2)' }}>
                {creditInfo.credit_ok
                  ? `✅ الائتمان متاح — ${formatNumber(creditInfo.available_credit)} ج.م`
                  : creditInfo.can_use_credit
                  ? `❌ تجاوز الحد — المطلوب ${formatNumber(remaining)} ج.م`
                  : '💵 عميل نقدي فقط'}
              </div>
            </div>
          )}

          {/* Total Remaining */}
          {!deliverLoading && (
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '9px 14px', background: 'var(--bg-surface-2)', borderRadius: 8, fontWeight: 600 }}>
              <span style={{ fontSize: 13 }}>المتبقي للسداد</span>
              <span style={{ color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums', fontSize: 16 }}>
                {formatNumber(remaining)} ج.م
              </span>
            </div>
          )}

          {!deliverLoading && (
            <>
              {/* Payment Terms Selector: نقدي / آجل / مختلط */}
              <div>
                <label className="form-label" style={{ fontSize: 12 }}>طريقة السداد *</label>
                <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                  {([
                    { v: 'cash',   emoji: '💵', label: 'نقدي',  show: true },
                    { v: 'credit', emoji: '📋', label: 'آجل',   show: !creditInfo || creditInfo.can_use_credit },
                    { v: 'mixed',  emoji: '🔀', label: 'مختلط', show: !creditInfo || (creditInfo.can_use_credit && creditInfo.available_credit > 0 && creditInfo.available_credit < remaining) },
                  ] as const).filter(o => o.show).map(opt => (
                    <button key={opt.v} type="button"
                      onClick={() => onChangePaymentTerms(opt.v as PaymentTerms)}
                      style={{
                        flex: 1, minWidth: 80, padding: '8px 10px', borderRadius: 8, cursor: 'pointer', fontSize: 12,
                        fontWeight: deliverForm.paymentTerms === opt.v ? 700 : 400,
                        background: deliverForm.paymentTerms === opt.v ? 'var(--color-primary)' : 'var(--bg-hover)',
                        color: deliverForm.paymentTerms === opt.v ? '#fff' : 'var(--text-secondary)',
                        border: deliverForm.paymentTerms === opt.v ? '2px solid var(--color-primary)' : '2px solid var(--border-primary)',
                        transition: 'all 0.15s',
                      }}>
                      {opt.emoji} {opt.label}
                    </button>
                  ))}
                </div>
              </div>

              {/* Cash Amount — للنقدي والمختلط */}
              {deliverForm.paymentTerms !== 'credit' && (
                <div>
                  <label className="form-label" style={{ fontSize: 12 }}>
                    المبلغ النقدي المحصّل
                    {creditInfo?.can_use_credit && minCash < remaining && (
                      <span style={{ color: 'var(--text-muted)', fontWeight: 400, marginRight: 6 }}>
                        (حد أدنى {formatNumber(minCash)} ج.م)
                      </span>
                    )}
                  </label>
                  {/* Cash-only customers: field is locked */}
                  {creditInfo && !creditInfo.can_use_credit ? (
                    <>
                      <input className="form-input" type="number" value={remaining} disabled
                        style={{ background: 'var(--bg-secondary)', fontWeight: 700, cursor: 'not-allowed' }} />
                      <div style={{ fontSize: 11, color: 'var(--color-success)', marginTop: 4, display: 'flex', alignItems: 'center', gap: 4 }}>
                        <Banknote size={12} />
                        💵 دفع نقدي كامل — هذا العميل لا يملك سقف ائتمان
                      </div>
                    </>
                  ) : (
                    <>
                      <input className="form-input" type="number" inputMode="decimal" min={minCash} max={remaining} step="0.01"
                        value={deliverForm.cashAmount}
                        onChange={e => onChangeCashAmount(Number(e.target.value))} />
                      {creditAmount > 0 && (
                        <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
                          الآجل: <strong style={{ color: 'var(--color-primary)' }}>{formatNumber(creditAmount)} ج.م</strong>
                          {minCash > 0 && (
                            <span style={{ marginRight: 8, color: 'var(--color-warning)' }}>
                              الحد الأدنى المطلوب نقداً: {formatNumber(minCash)} ج.م
                            </span>
                          )}
                        </div>
                      )}
                    </>
                  )}
                </div>
              )}

              {/* ── Payment Method Selector: كيف استلمت المبلغ؟ ── */}
              {deliverForm.paymentTerms !== 'credit' && (
                <div>
                  <label className="form-label" style={{ fontSize: 12 }}>طريقة الاستلام</label>
                  <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                    {COLLECT_METHODS.map(m => (
                      <button key={m.value} type="button"
                        onClick={() => setDeliverForm(f => ({ ...f, paymentMethod: m.value }))}
                        style={{
                          flex: 1, minWidth: 80, padding: '7px 8px', borderRadius: 8,
                          fontSize: 11, cursor: 'pointer', transition: 'all 0.15s',
                          fontWeight: deliverForm.paymentMethod === m.value ? 700 : 400,
                          background: deliverForm.paymentMethod === m.value
                            ? (m.isCash ? 'var(--color-success)' : 'var(--color-primary)')
                            : 'var(--bg-hover)',
                          color: deliverForm.paymentMethod === m.value ? '#fff' : 'var(--text-secondary)',
                          border: `2px solid ${deliverForm.paymentMethod === m.value
                            ? (m.isCash ? 'var(--color-success)' : 'var(--color-primary)')
                            : 'var(--border-primary)'}`,
                        }}>
                        {m.label}
                      </button>
                    ))}
                  </div>
                  {!isCashNow && (
                    <div style={{ fontSize: 11, marginTop: 6, padding: '6px 10px', borderRadius: 6,
                      background: 'var(--color-info-light, #eff6ff)', color: 'var(--color-info, #2563eb)',
                      display: 'flex', gap: 5, alignItems: 'center' }}>
                      سيُنشأ إيصال بانتظار مراجعة المحاسب المالي — لن يُحدَّث رصيد الفاتورة إلا بعد التأكيد
                    </div>
                  )}

                  {/* ── حقول المرجع حسب الطريقة ── */}
                  {(deliverForm.paymentMethod === 'bank_transfer' ||
                    deliverForm.paymentMethod === 'instapay' ||
                    deliverForm.paymentMethod === 'mobile_wallet') && (
                    <div style={{ marginTop: 8 }}>
                      <label className="form-label" style={{ fontSize: 11 }}>
                        رقم المرجع {deliverForm.paymentMethod === 'instapay' ? '(إنستاباي)' : deliverForm.paymentMethod === 'mobile_wallet' ? '(المحفظة)' : '(التحويل البنكي)'}
                      </label>
                      <input className="form-input" style={{ fontSize: 12 }} dir="ltr"
                        placeholder="أدخل رقم المرجع أو الحوالة..."
                        value={deliverForm.bankReference}
                        onChange={e => setDeliverForm(f => ({ ...f, bankReference: e.target.value }))} />
                    </div>
                  )}

                  {deliverForm.paymentMethod === 'cheque' && (
                    <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
                      <div style={{ flex: 1 }}>
                        <label className="form-label" style={{ fontSize: 11 }}>رقم الشيك</label>
                        <input className="form-input" style={{ fontSize: 12 }} dir="ltr"
                          placeholder="رقم الشيك..."
                          value={deliverForm.checkNumber}
                          onChange={e => setDeliverForm(f => ({ ...f, checkNumber: e.target.value }))} />
                      </div>
                      <div style={{ flex: 1 }}>
                        <label className="form-label" style={{ fontSize: 11 }}>تاريخ الاستحقاق</label>
                        <input className="form-input" type="date" style={{ fontSize: 12 }} dir="ltr"
                          value={deliverForm.checkDate}
                          onChange={e => setDeliverForm(f => ({ ...f, checkDate: e.target.value }))} />
                      </div>
                    </div>
                  )}

                  {/* ── إثبات الدفع (إجباري للتحويلات والشيكات) ── */}
                  {isProofRequired && (
                    <div style={{ marginTop: 10 }}>
                      <ProofUploadButton
                        file={proofFile}
                        onChange={setProofFile}
                        required
                        label="إثبات الدفع"
                      />
                    </div>
                  )}
                </div>
              )}

              {/* ── Destination — for CASH ONLY (تحويل/إنستاباي لا يحتاجها الآن) ── */}
              {deliverForm.paymentTerms !== 'credit' && isCashNow && paymentOptions && (
                <div style={{ borderRadius: 8, border: '1px solid var(--border-primary)', padding: '10px 12px' }}>
                  <div style={{ fontSize: 11, fontWeight: 600, color: 'var(--text-muted)', marginBottom: 6 }}>وجهة التحصيل النقدي</div>
                  {paymentOptions.cash_destination === null ? (
                    <div style={{ color: 'var(--color-danger)', fontSize: 12, display: 'flex', gap: 6, alignItems: 'center' }}>
                      <AlertTriangle size={13} /> لا توجد عهدة أو خزينة متاحة
                    </div>
                  ) : paymentOptions.cash_destination === 'custody' ? (
                    <div style={{ fontSize: 12, display: 'flex', alignItems: 'center', gap: 6 }}>
                      🔒 عهدتك — رصيد: {formatNumber(paymentOptions.custody_balance)} ج.م
                      <span style={{ fontSize: 10, color: 'var(--text-muted)' }}>(تلقائي)</span>
                    </div>
                  ) : (
                    <select className="form-select" value={deliverForm.vaultId}
                      onChange={e => setDeliverForm(f => ({ ...f, vaultId: e.target.value, custodyId: '' }))}>
                      <option value="">— اختر خزينة —</option>
                      {paymentOptions.available_vaults.map(v => (
                        <option key={v.id} value={v.id}>
                          {v.name} — {formatNumber(v.balance)} ج.م
                        </option>
                      ))}
                    </select>
                  )}
                </div>
              )}

              {/* Override Credit */}
              {creditInfo && creditAmount > 0 && creditInfo.exceeds_limit && can('sales.orders.override_credit') && (
                <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', fontSize: 13 }}>
                  <input type="checkbox" checked={deliverForm.overrideCredit}
                    onChange={e => setDeliverForm(f => ({ ...f, overrideCredit: e.target.checked }))} />
                  تجاوز حد الائتمان (أنت مسؤول)
                </label>
              )}

              <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end', paddingTop: 4 }}>
                <button className="btn btn-secondary" onClick={() => setShowDeliverModal(false)}>إلغاء</button>
                <button className="btn btn-primary" onClick={handleDeliver}
                  disabled={actionLoading || deliverLoading || !canDeliverAction}>
                  <Truck size={14} />
                  {actionLoading ? 'جاري...' : 'تأكيد التسليم'}
                </button>
              </div>
            </>
          )}
        </div>
      </ResponsiveModal>

      {/* ══════════════════════════════════════════ CANCEL MODAL */}
      <ResponsiveModal open={showCancelModal} onClose={() => setShowCancelModal(false)} title="إلغاء الطلب">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <p style={{ color: 'var(--color-danger)', fontSize: 13, margin: 0 }}>
            سيتم إلغاء الطلب وإعادة المخزون المحجوز. هذا الإجراء لا يمكن التراجع عنه.
          </p>
          <div>
            <label className="form-label" style={{ fontSize: 12 }}>سبب الإلغاء</label>
            <textarea className="form-input" rows={3} value={cancelReason}
              onChange={e => setCancelReason(e.target.value)} placeholder="اكتب سبب الإلغاء..." />
          </div>
          <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
            <button className="btn btn-secondary" onClick={() => setShowCancelModal(false)}>تراجع</button>
            <button className="btn btn-danger" onClick={handleCancel} disabled={actionLoading}>
              <XCircle size={14} />
              {actionLoading ? 'جاري...' : 'تأكيد الإلغاء'}
            </button>
          </div>
        </div>
      </ResponsiveModal>
    </div>
  )
}

// ── Shared Sub-components ───────────────────────────────────────

const card: React.CSSProperties = {
  background: 'var(--bg-surface)', border: '1px solid var(--border-primary)',
  borderRadius: 12, padding: 14, marginBottom: 10,
}
const iconBox: React.CSSProperties = {
  width: 28, height: 28, borderRadius: 8,
  display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
}

function SectionHead({ icon, title }: { icon: React.ReactNode; title: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
      <span style={{ ...iconBox, background: 'var(--bg-surface-2)', color: 'var(--color-primary)' }}>{icon}</span>
      <span style={{ fontWeight: 700, fontSize: 13 }}>{title}</span>
    </div>
  )
}

function InfoPair({ icon, label, value, muted }: { icon?: React.ReactNode; label: string; value?: string | null; muted?: boolean }) {
  return (
    <div style={{ minWidth: 0 }}>
      <div style={{ fontSize: 10, color: 'var(--text-muted)', marginBottom: 2, display: 'flex', alignItems: 'center', gap: 3 }}>{icon} {label}</div>
      <div style={{ fontSize: 12, fontWeight: 600, color: muted ? 'var(--text-muted)' : 'var(--text-primary)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{value || '—'}</div>
    </div>
  )
}

function FinRow({ icon, label, value, valueColor }: { icon?: React.ReactNode; label: string; value: string; valueColor?: string }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
      <span style={{ fontSize: 12, color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 4 }}>{icon} {label}</span>
      <span style={{ fontSize: 12, fontWeight: 600, fontVariantNumeric: 'tabular-nums', color: valueColor || 'inherit' }}>{value}</span>
    </div>
  )
}

function FinBadge({ label, value, unit, color }: { label: string; value: string; unit: string; color: string }) {
  return (
    <div style={{ flex: 1, padding: '10px 12px', textAlign: 'center' }}>
      <div style={{ fontSize: 10, color: 'var(--text-muted)', marginBottom: 3 }}>{label}</div>
      <div style={{ fontSize: 14, fontWeight: 800, color, fontVariantNumeric: 'tabular-nums', lineHeight: 1.2 }}>{value}</div>
      <div style={{ fontSize: 10, color: 'var(--text-muted)' }}>{unit}</div>
    </div>
  )
}

function CreditTile({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div style={{ textAlign: 'center' }}>
      <div style={{ fontSize: 10, color: 'var(--text-muted)', marginBottom: 3 }}>{label}</div>
      <div style={{ fontSize: 12, fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: color || 'inherit' }}>{value}</div>
    </div>
  )
}

function ActionBtn({
  icon, label, onClick, primary, danger, disabled
}: { icon: React.ReactNode; label: string; onClick: () => void; primary?: boolean; danger?: boolean; disabled?: boolean }) {
  return (
    <button onClick={onClick} disabled={disabled}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 5,
        padding: '7px 12px', borderRadius: 8, cursor: disabled ? 'not-allowed' : 'pointer',
        fontSize: 12, fontWeight: 600, whiteSpace: 'nowrap', flexShrink: 0,
        opacity: disabled ? 0.5 : 1, transition: 'all 0.15s',
        border: primary ? '2px solid var(--color-primary)' : danger ? '2px solid var(--color-danger)' : '2px solid var(--border-primary)',
        background: primary ? 'var(--color-primary)' : danger ? 'var(--color-danger-light)' : 'var(--bg-surface)',
        color: primary ? '#fff' : danger ? 'var(--color-danger)' : 'var(--text-secondary)',
      }}>
      {icon} {label}
    </button>
  )
}
