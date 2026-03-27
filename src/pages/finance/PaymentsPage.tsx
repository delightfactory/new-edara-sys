import { useState, useRef } from 'react'
import { toast } from 'sonner'
import { Receipt, Plus, Check, XCircle, Upload, Search, ExternalLink, AlertCircle, Wallet } from 'lucide-react'
import {
  createPaymentReceipt, confirmPaymentReceipt, rejectPaymentReceipt,
  uploadPaymentProof, getOpenOrdersForCustomer,
} from '@/lib/services/payments'
import { usePaymentReceipts, useVaults, useInvalidate } from '@/hooks/useQueryHooks'
import { supabase } from '@/lib/supabase/client'
import { useQuery } from '@tanstack/react-query'
import { useAuthStore } from '@/stores/auth-store'
import type { PaymentReceipt, PaymentReceiptInput, PaymentMethod } from '@/lib/types/master-data'
import { formatCurrency, formatDateTime } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Modal from '@/components/ui/Modal'
import AsyncCombobox from '@/components/ui/AsyncCombobox'
import type { ComboboxOption } from '@/components/ui/AsyncCombobox'
import { Link } from 'react-router-dom'

// ════════════════════════════════════════════════════════════
// Constants
// ════════════════════════════════════════════════════════════

interface PaymentMethodConfig {
  value: PaymentMethod
  label: string
  /** نوع الخزنة المطلوبة عند التأكيد — null = شيك (أوراق قبض) */
  vaultType: 'cash' | 'bank' | 'mobile_wallet' | null
  /** هل يتطلب إثبات دفع إجباري */
  requiresProof: boolean
}

const PAYMENT_METHODS: PaymentMethodConfig[] = [
  { value: 'cash',          label: 'نقدي',             vaultType: 'cash',          requiresProof: false },
  { value: 'bank_transfer', label: 'تحويل بنكي',       vaultType: 'bank',          requiresProof: true  },
  { value: 'instapay',      label: 'إنستاباي',         vaultType: 'mobile_wallet', requiresProof: true  },
  { value: 'mobile_wallet', label: 'محفظة إلكترونية', vaultType: 'mobile_wallet', requiresProof: true  },
  { value: 'cheque',        label: 'شيك',              vaultType: null,            requiresProof: true  },
]

const statusConfig: Record<string, { label: string; variant: 'warning' | 'success' | 'danger' }> = {
  pending:   { label: 'معلق',   variant: 'warning' },
  confirmed: { label: 'مؤكد',  variant: 'success' },
  rejected:  { label: 'مرفوض', variant: 'danger'  },
}

const getMethodLabel = (m: string) => PAYMENT_METHODS.find(x => x.value === m)?.label || m

// ════════════════════════════════════════════════════════════
// Component
// ════════════════════════════════════════════════════════════

export default function PaymentsPage() {
  const can     = useAuthStore(s => s.can)
  const profile = useAuthStore(s => s.profile)
  const invalidate = useInvalidate()

  // Pagination + Filters
  const [page, setPage]                     = useState(1)
  const [filterStatus, setFilterStatus]     = useState('')
  const [filterCustomer, setFilterCustomer] = useState('')
  const [filterDateFrom, setFilterDateFrom] = useState('')
  const [filterDateTo, setFilterDateTo]     = useState('')

  // ── Vaults (all — filtered per method at confirm time) ──
  const { data: vaults = [] } = useVaults({ isActive: true })

  // ── Current user's custody account (if any) ──
  // يُستخدم لاكتشاف عهدة المستخدم الحالى تلقائياً عند التحصيل النقدي
  const { data: myCustody } = useQuery({
    queryKey: ['my-custody', profile?.id],
    queryFn: async () => {
      if (!profile?.id) return null
      const { data } = await supabase
        .from('custody_accounts')
        .select('id, current_balance, max_balance, is_active')
        .eq('employee_id', profile.id)
        .eq('is_active', true)
        .maybeSingle()
      return data as { id: string; current_balance: number; max_balance: number; is_active: boolean } | null
    },
    enabled: !!profile?.id,
    staleTime: 5 * 60 * 1000,
  })

  // ── Receipts list ──
  const { data: result, isLoading: loading } = usePaymentReceipts({
    page, pageSize: 25,
    status:     filterStatus   || undefined,
    customerId: filterCustomer || undefined,
    dateFrom:   filterDateFrom || undefined,
    dateTo:     filterDateTo   || undefined,
  })
  const receipts   = result?.data       ?? []
  const totalPages = result?.totalPages ?? 0
  const totalCount = result?.count      ?? 0

  // ── Customer Async Search ──
  // loadOptions مرر مباشرة إلى AsyncCombobox — لا state إضافي
  const loadCustomers = async (search: string): Promise<ComboboxOption[]> => {
    const { data } = await supabase
      .from('customers')
      .select('id, name, code')
      .eq('is_active', true)
      .or(search
        ? `name.ilike.%${search}%,code.ilike.%${search}%`
        : 'id.neq.00000000-0000-0000-0000-000000000000'
      )
      .order('name')
      .limit(20)
    return (data || []).map(c => ({
      value: c.id,
      label: c.name,
      code: c.code,
    }))
  }

  const [selectedCust, setSelectedCust] = useState<{ id: string; name: string; code: string } | null>(null)


  // ── Open orders for selected customer ──
  const [openOrders, setOpenOrders] = useState<
    { id: string; order_number: string; total_amount: number; paid_amount: number }[]
  >([])

  // ── Create form state ──
  const [createOpen, setCreateOpen] = useState(false)
  const [form, setForm] = useState<PaymentReceiptInput & { sales_order_id?: string | null }>(
    { customer_id: '', amount: 0, payment_method: 'cash', sales_order_id: null }
  )
  const [proofFile, setProofFile] = useState<File | null>(null)
  const [saving, setSaving]       = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  // الطريقة الحالية والمتطلبات
  const currentMethodCfg = PAYMENT_METHODS.find(m => m.value === form.payment_method)
  const isProofRequired  = currentMethodCfg?.requiresProof ?? false
  const isCashCreate     = form.payment_method === 'cash'

  // هل سيتم التوجيه لعهدة المستخدم (نقدي + لديه عهدة + لا يملك صلاحية إدارة الخزن)
  const routeToCustody = isCashCreate && !!myCustody && !can('finance.vaults.transact')

  const openCreate = () => {
    setForm({ customer_id: '', amount: 0, payment_method: 'cash', sales_order_id: null })
    setProofFile(null); setSelectedCust(null); setOpenOrders([])
    setCreateOpen(true)
  }

  // يُستدعى بواسطة AsyncCombobox عند اختيار عميل
  const handleCustSelect = async (_value: string | null, option?: { value: string; label: string; code?: string } | null) => {
    if (!option) {
      setSelectedCust(null)
      setForm(f => ({ ...f, customer_id: '', sales_order_id: null }))
      setOpenOrders([])
      return
    }
    const c = { id: option.value, name: option.label, code: option.code || '' }
    setSelectedCust(c)
    setForm(f => ({ ...f, customer_id: c.id, sales_order_id: null }))
    try {
      const orders = await getOpenOrdersForCustomer(c.id)
      setOpenOrders(orders)
    } catch { setOpenOrders([]) }
  }

  const handleCreate = async () => {
    if (!form.customer_id) { toast.error('العميل مطلوب'); return }
    if (!form.amount || form.amount <= 0) { toast.error('المبلغ يجب أن يكون أكبر من صفر'); return }
    // إلزامية الإثبات للطرق غير النقدية
    if (isProofRequired && !proofFile) {
      toast.error('إثبات الدفع إجباري لهذه الطريقة — برجاء رفع صورة أو ملف')
      return
    }
    setSaving(true)
    try {
      let proofUrl: string | undefined
      if (proofFile) proofUrl = await uploadPaymentProof(proofFile)

      // حقن custody_id تلقائياً إذا كان المستخدم مندوباً لديه عهدة وطريقة الدفع نقدية
      const payload: PaymentReceiptInput & { sales_order_id?: string | null } = {
        ...form,
        proof_url: proofUrl || null,
        ...(routeToCustody && myCustody ? { custody_id: myCustody.id } : {}),
      }

      await createPaymentReceipt(payload)
      toast.success(routeToCustody
        ? 'تم إنشاء الإيصال — سيُحسب على عهدتك بعد التأكيد'
        : 'تم إنشاء الإيصال بنجاح'
      )
      setCreateOpen(false)
      invalidate('payment-receipts')
    } catch (err: any) { toast.error(err.message || 'فشل الإنشاء') }
    finally { setSaving(false) }
  }

  // ── Confirm modal ──
  const [confirmReceipt, setConfirmReceipt] = useState<PaymentReceipt | null>(null)
  const [confirmVaultId, setConfirmVaultId] = useState('')
  const [confirming, setConfirming]         = useState(false)

  const methodConfig    = PAYMENT_METHODS.find(m => m.value === confirmReceipt?.payment_method)
  const isCheque        = confirmReceipt?.payment_method === 'cheque'
  const hasCustodyLink  = !!confirmReceipt?.custody_id  // تم تسجيل مؤقت في عهدة
  const filteredVaults  = vaults.filter(v =>
    !methodConfig?.vaultType || v.type === methodConfig.vaultType
  )

  const openConfirm = (r: PaymentReceipt) => {
    setConfirmReceipt(r)
    const mc    = PAYMENT_METHODS.find(m => m.value === r.payment_method)
    const first = vaults.find(v => !mc?.vaultType || v.type === mc.vaultType)
    setConfirmVaultId(first?.id || '')
  }

  const handleConfirm = async () => {
    if (!confirmReceipt) return
    if (!isCheque && !hasCustodyLink && !confirmVaultId) {
      toast.error('اختر الوجهة المالية'); return
    }
    setConfirming(true)
    try {
      // إذا كان الإيصال مرتبط بعهدة → vaultId = null (السيرفر سيوجه للعهدة)
      // إذا شيك → vaultId = null (السيرفر يوجه لـ 1210)
      // غير ذلك → vaultId = الخزنة/البنك المختار
      const vaultId = (isCheque || hasCustodyLink) ? null : confirmVaultId
      await confirmPaymentReceipt(confirmReceipt.id, vaultId)
      toast.success('تم تأكيد الإيصال وتوزيع المبلغ')
      setConfirmReceipt(null)
      invalidate('payment-receipts')
    } catch (err: any) { toast.error(err.message) }
    finally { setConfirming(false) }
  }

  // ── Reject modal ──
  const [rejectReceipt, setRejectReceipt] = useState<PaymentReceipt | null>(null)
  const [rejectReason, setRejectReason]   = useState('')
  const [rejecting, setRejecting]         = useState(false)

  const handleReject = async () => {
    if (!rejectReceipt || !rejectReason.trim()) { toast.error('سبب الرفض مطلوب'); return }
    setRejecting(true)
    try {
      await rejectPaymentReceipt(rejectReceipt.id, rejectReason)
      toast.success('تم رفض الإيصال')
      setRejectReceipt(null)
      invalidate('payment-receipts')
    } catch (err: any) { toast.error(err.message) }
    finally { setRejecting(false) }
  }

  // ════════════════════════════════════════════════════════════
  // Render
  // ════════════════════════════════════════════════════════════

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="إيصالات الدفع"
        subtitle={loading ? '...' : `${totalCount} إيصال`}
        actions={
          can('finance.payments.create')
            ? <Button icon={<Plus size={16} />} onClick={openCreate}>إيصال جديد</Button>
            : undefined
        }
      />

      {/* ── Filters ── */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-3" style={{ flexWrap: 'wrap', alignItems: 'flex-end' }}>
          <div className="form-group" style={{ margin: 0, minWidth: 130 }}>
            <label className="form-label" style={{ fontSize: 'var(--text-xs)' }}>الحالة</label>
            <select className="form-select" value={filterStatus}
              onChange={e => { setFilterStatus(e.target.value); setPage(1) }}>
              <option value="">كل الحالات</option>
              <option value="pending">معلق</option>
              <option value="confirmed">مؤكد</option>
              <option value="rejected">مرفوض</option>
            </select>
          </div>
          <div className="form-group" style={{ margin: 0, minWidth: 200 }}>
            <label className="form-label" style={{ fontSize: 'var(--text-xs)' }}>العميل</label>
            <div style={{ position: 'relative' }}>
              <Search size={14} style={{ position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
              <input className="form-input" style={{ paddingRight: 32 }} placeholder="بحث بالاسم..."
                value={filterCustomer} onChange={e => { setFilterCustomer(e.target.value); setPage(1) }} />
            </div>
          </div>
          <div className="form-group" style={{ margin: 0 }}>
            <label className="form-label" style={{ fontSize: 'var(--text-xs)' }}>من تاريخ</label>
            <input className="form-input" type="date" value={filterDateFrom}
              onChange={e => { setFilterDateFrom(e.target.value); setPage(1) }} />
          </div>
          <div className="form-group" style={{ margin: 0 }}>
            <label className="form-label" style={{ fontSize: 'var(--text-xs)' }}>إلى تاريخ</label>
            <input className="form-input" type="date" value={filterDateTo}
              onChange={e => { setFilterDateTo(e.target.value); setPage(1) }} />
          </div>
          {(filterStatus || filterCustomer || filterDateFrom || filterDateTo) && (
            <Button variant="ghost" size="sm" onClick={() => {
              setFilterStatus(''); setFilterCustomer(''); setFilterDateFrom(''); setFilterDateTo(''); setPage(1)
            }}>مسح</Button>
          )}
        </div>
      </div>

      {/* ── Table ── */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        <DataTable<PaymentReceipt>
          columns={[
            { key: 'number', label: 'الرقم',
              render: r => <span style={{ fontWeight: 600, fontFamily: 'monospace' }}>{r.number}</span> },
            { key: 'customer', label: 'العميل',
              render: r => (
                <>
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{r.customer?.name || '—'}</div>
                  {r.customer?.code && (
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{r.customer.code}</div>
                  )}
                </>
              )},
            { key: 'amount', label: 'المبلغ',
              render: r => <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{formatCurrency(r.amount)}</span> },
            { key: 'payment_method', label: 'الطريقة', hideOnMobile: true,
              render: r => (
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  {getMethodLabel(r.payment_method)}
                  {r.custody_id && (
                    <span title="مرتبط بعهدة" style={{ color: 'var(--color-warning)' }}><Wallet size={12} /></span>
                  )}
                </div>
              )},
            { key: 'sales_order', label: 'الفاتورة', hideOnMobile: true,
              render: r => r.sales_order ? (
                <Link to={`/sales/${r.sales_order_id}`} onClick={e => e.stopPropagation()}
                  style={{ color: 'var(--color-primary)', fontSize: 'var(--text-sm)', display: 'flex', alignItems: 'center', gap: 4 }}>
                  {r.sales_order.order_number}<ExternalLink size={11} />
                </Link>
              ) : <span style={{ color: 'var(--text-muted)' }}>—</span> },
            { key: 'status', label: 'الحالة',
              render: r => {
                const sc = statusConfig[r.status]
                return sc ? <Badge variant={sc.variant}>{sc.label}</Badge> : <Badge>{r.status}</Badge>
              }},
            { key: 'created_at', label: 'التاريخ', hideOnMobile: true,
              render: r => formatDateTime(r.created_at) },
            { key: 'actions', label: 'إجراءات', width: 100,
              render: r => (
                r.status === 'pending' && can('finance.payments.confirm') ? (
                  <div className="action-group" onClick={e => e.stopPropagation()}>
                    <Button variant="success" size="sm" title="تأكيد" onClick={() => openConfirm(r)}><Check size={14} /></Button>
                    <Button variant="danger" size="sm" title="رفض" onClick={() => { setRejectReceipt(r); setRejectReason('') }}><XCircle size={14} /></Button>
                  </div>
                ) : null
              )},
          ]}
          data={receipts}
          loading={loading}
          emptyIcon={<Receipt size={48} />}
          emptyTitle="لا توجد إيصالات"
          emptyText="لم يتم العثور على إيصالات مطابقة"
          page={page} totalPages={totalPages} totalCount={totalCount} onPageChange={setPage}
        />
      </div>

      {/* ════════════════════════════════════════════════════════ */}
      {/* ── Create Modal ── */}
      {/* ════════════════════════════════════════════════════════ */}
      <Modal
        open={createOpen} onClose={() => setCreateOpen(false)}
        title="إيصال دفع جديد" size="md" disableOverlayClose
        footer={
          <>
            <Button variant="ghost" onClick={() => setCreateOpen(false)}>إلغاء</Button>
            <Button onClick={handleCreate} loading={saving}>حفظ</Button>
          </>
        }
      >
        <div className="flex-col gap-4">

          {/* ── إشعار التوجيه التلقائي للعهدة ── */}
          {routeToCustody && (
            <div style={{
              padding: 'var(--space-3)', borderRadius: 'var(--radius-md)',
              background: 'color-mix(in srgb, var(--color-warning) 10%, transparent)',
              border: '1px solid color-mix(in srgb, var(--color-warning) 30%, transparent)',
              fontSize: 'var(--text-sm)', display: 'flex', alignItems: 'flex-start', gap: 10,
            }}>
              <Wallet size={16} style={{ color: 'var(--color-warning)', flexShrink: 0, marginTop: 2 }} />
              <div>
                <strong style={{ color: 'var(--color-warning)' }}>تحصيل ميداني (عهدة)</strong>
                <div style={{ color: 'var(--text-secondary)', marginTop: 2 }}>
                  سيُحسب هذا التحصيل على عهدتك الشخصية بعد مراجعة الإدارة.
                  رصيد عهدتك الحالي: <strong>{formatCurrency(myCustody?.current_balance ?? 0)}</strong>
                </div>
              </div>
            </div>
          )}

          {/* ── Customer AsyncCombobox ── */}
          <AsyncCombobox
            label="العميل"
            placeholder="ابحث باسم العميل أو الكود..."
            value={form.customer_id || null}
            onChange={handleCustSelect}
            loadOptions={loadCustomers}
            required
            noOptionsText="لا يوجد عميل بهذا الاسم"
          />

          {/* ── Amount + Method ── */}
          <div className="form-row">
            <div className="form-group">
              <label className="form-label required">المبلغ</label>
              <input className="form-input" type="number" min="0.01" step="0.01"
                value={form.amount || ''} placeholder="0.00"
                onChange={e => setForm(f => ({ ...f, amount: parseFloat(e.target.value) || 0 }))} />
            </div>
            <div className="form-group">
              <label className="form-label required">طريقة الدفع</label>
              <select className="form-select" value={form.payment_method}
                onChange={e => {
                  setForm(f => ({ ...f, payment_method: e.target.value as PaymentMethod }))
                  setProofFile(null)
                }}>
                {PAYMENT_METHODS.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
              </select>
            </div>
          </div>

          {/* ── Conditional fields per payment method ── */}
          {(form.payment_method === 'bank_transfer' || form.payment_method === 'instapay') && (
            <div className="form-group">
              <label className="form-label">رقم المرجع {form.payment_method === 'instapay' ? '(إنستاباي)' : '(التحويل البنكي)'}</label>
              <input className="form-input" value={form.bank_reference || ''}
                onChange={e => setForm(f => ({ ...f, bank_reference: e.target.value || null }))} />
            </div>
          )}
          {form.payment_method === 'mobile_wallet' && (
            <div className="form-group">
              <label className="form-label">رقم المرجع (المحفظة)</label>
              <input className="form-input" value={form.bank_reference || ''}
                onChange={e => setForm(f => ({ ...f, bank_reference: e.target.value || null }))} />
            </div>
          )}
          {form.payment_method === 'cheque' && (
            <div className="form-row">
              <div className="form-group">
                <label className="form-label">رقم الشيك</label>
                <input className="form-input" value={form.check_number || ''}
                  onChange={e => setForm(f => ({ ...f, check_number: e.target.value || null }))} />
              </div>
              <div className="form-group">
                <label className="form-label">تاريخ الاستحقاق</label>
                <input className="form-input" type="date" value={form.check_date || ''}
                  onChange={e => setForm(f => ({ ...f, check_date: e.target.value || null }))} />
              </div>
            </div>
          )}

          {/* ── Link to open order (optional) ── */}
          {selectedCust && openOrders.length > 0 && (
            <div className="form-group">
              <label className="form-label">ربط بفاتورة (اختياري)</label>
              <select className="form-select"
                value={form.sales_order_id || ''}
                onChange={e => setForm(f => ({ ...f, sales_order_id: e.target.value || null }))}>
                <option value="">— توزيع ذكي تلقائي على الأقدم —</option>
                {openOrders.map(o => (
                  <option key={o.id} value={o.id}>
                    {o.order_number} — متبقي {formatCurrency(o.total_amount - (o.paid_amount ?? 0))}
                  </option>
                ))}
              </select>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 4 }}>
                إذا لم تختر، سيُوزَّع تلقائياً على أقدم الفواتير المفتوحة
              </div>
            </div>
          )}

          {/* ── Overpayment Warning ── */}
          {(() => {
            if (!form.sales_order_id || !form.amount) return null
            const linked = openOrders.find(o => o.id === form.sales_order_id)
            if (!linked) return null
            const remaining = linked.total_amount - (linked.paid_amount ?? 0)
            if (form.amount <= remaining) return null
            const excess = form.amount - remaining
            return (
              <div style={{
                padding: '8px 12px', borderRadius: 8, fontSize: 'var(--text-xs)',
                background: 'color-mix(in srgb, var(--color-warning) 10%, transparent)',
                border: '1px solid color-mix(in srgb, var(--color-warning) 30%, transparent)',
                color: 'var(--color-warning-dark, #92400e)',
                display: 'flex', gap: 8, alignItems: 'flex-start',
              }}>
                <AlertCircle size={13} style={{ flexShrink: 0, marginTop: 1 }} />
                <span>
                  المبلغ المُدخَل أكبر من المتبقي بـ <strong>{formatCurrency(excess)}</strong>.
                  الزيادة ستُسجَّل كـ <strong>دفعة مقدمة</strong> يمكن توزيعها لاحقاً.
                </span>
              </div>
            )
          })()}

          {/* ── Proof upload — إجباري لغير النقدي ── */}
          <div className="form-group">
            <label className={`form-label ${isProofRequired ? 'required' : ''}`}>
              إثبات الدفع
              {isProofRequired && (
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--color-warning)', marginRight: 6, fontWeight: 400 }}>
                  (إجباري لهذه الطريقة)
                </span>
              )}
            </label>
            <input ref={fileRef} type="file" accept="image/*,.pdf" style={{ display: 'none' }}
              onChange={e => setProofFile(e.target.files?.[0] || null)} />
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <Button variant={isProofRequired && !proofFile ? 'danger' : 'ghost'}
                onClick={() => fileRef.current?.click()} icon={<Upload size={14} />}>
                {proofFile ? proofFile.name : 'رفع ملف'}
              </Button>
              {isProofRequired && !proofFile && (
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--color-danger)', display: 'flex', alignItems: 'center', gap: 4 }}>
                  <AlertCircle size={12} /> مطلوب
                </span>
              )}
            </div>
          </div>

          <div className="form-group">
            <label className="form-label">ملاحظات</label>
            <textarea className="form-textarea" rows={2} value={form.notes || ''}
              onChange={e => setForm(f => ({ ...f, notes: e.target.value || null }))} />
          </div>
        </div>
      </Modal>

      {/* ════════════════════════════════════════════════════════ */}
      {/* ── Confirm Modal ── */}
      {/* ════════════════════════════════════════════════════════ */}
      <Modal
        open={!!confirmReceipt} onClose={() => setConfirmReceipt(null)}
        title="تأكيد استلام الإيصال" size="sm"
        footer={
          <>
            <Button variant="ghost" onClick={() => setConfirmReceipt(null)}>إلغاء</Button>
            <Button onClick={handleConfirm} loading={confirming}>تأكيد الاستلام</Button>
          </>
        }
      >
        {confirmReceipt && (
          <div className="flex-col gap-4">
            {/* Summary */}
            <div className="info-box">
              <span className="info-box-label">العميل</span>
              <span className="info-box-value">{confirmReceipt.customer?.name}</span>
              <span className="info-box-label">المبلغ</span>
              <span className="info-box-value" style={{ color: 'var(--color-success)', fontWeight: 700 }}>
                {formatCurrency(confirmReceipt.amount)}
              </span>
              <span className="info-box-label">طريقة الدفع</span>
              <span className="info-box-value">{getMethodLabel(confirmReceipt.payment_method)}</span>
              {confirmReceipt.sales_order && (
                <>
                  <span className="info-box-label">الفاتورة</span>
                  <span className="info-box-value">{confirmReceipt.sales_order.order_number}</span>
                </>
              )}
            </div>

            {/* ── مسار التوجيه المالي حسب الحالة ── */}
            {isCheque ? (
              /* شيك → أوراق قبض 1210 */
              <div style={{ padding: 'var(--space-3)', borderRadius: 'var(--radius-md)',
                background: 'color-mix(in srgb, var(--color-warning) 10%, transparent)',
                border: '1px solid color-mix(in srgb, var(--color-warning) 30%, transparent)',
                fontSize: 'var(--text-sm)' }}>
                <strong style={{ color: 'var(--color-warning)' }}>📋 توجيه: أوراق قبض (1210)</strong>
                <div style={{ color: 'var(--text-secondary)', marginTop: 4 }}>
                  سيُسجَّل هذا الشيك في "أوراق القبض" حتى تاريخ استحقاقه وتحصيله الفعلي من البنك.
                </div>
                {confirmReceipt.check_number && (
                  <div style={{ fontFamily: 'monospace', fontSize: 'var(--text-xs)', marginTop: 4, color: 'var(--text-muted)' }}>
                    شيك: {confirmReceipt.check_number} | تاريخ: {confirmReceipt.check_date || '—'}
                  </div>
                )}
              </div>
            ) : hasCustodyLink ? (
              /* عهدة → تلقائي بدون اختيار */
              <div style={{ padding: 'var(--space-3)', borderRadius: 'var(--radius-md)',
                background: 'color-mix(in srgb, var(--color-warning) 10%, transparent)',
                border: '1px solid color-mix(in srgb, var(--color-warning) 30%, transparent)',
                fontSize: 'var(--text-sm)' }}>
                <strong style={{ color: 'var(--color-warning)' }}>💼 توجيه: عهدة ميدانية</strong>
                <div style={{ color: 'var(--text-secondary)', marginTop: 4 }}>
                  هذا التحصيل مُسجَّل على العهدة الشخصية للمحصّل. بتأكيدك سيتم إضافته لرصيد العهدة.
                </div>
              </div>
            ) : (
              /* خزنة / بنك / محفظة → اختيار مفلتر */
              <div className="form-group">
                <label className="form-label required">
                  {methodConfig?.vaultType === 'bank'          ? 'الحساب البنكي المستقبِل' :
                   methodConfig?.vaultType === 'mobile_wallet' ? 'المحفظة الإلكترونية'     :
                   'الخزنة النقدية'}
                </label>
                {filteredVaults.length === 0 ? (
                  <div style={{ color: 'var(--color-danger)', fontSize: 'var(--text-sm)', display: 'flex', alignItems: 'center', gap: 6 }}>
                    <AlertCircle size={14} />
                    لا توجد {methodConfig?.vaultType === 'bank' ? 'حسابات بنكية' : 'خزائن'} نشطة من هذا النوع
                  </div>
                ) : (
                  <>
                    <select className="form-select" value={confirmVaultId}
                      onChange={e => setConfirmVaultId(e.target.value)}>
                      {filteredVaults.map(v => <option key={v.id} value={v.id}>{v.name}</option>)}
                    </select>
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 4 }}>
                      {methodConfig?.vaultType === 'bank' && '⚡ يُعرض الحسابات البنكية فقط لهذا النوع من التحويلات'}
                      {methodConfig?.vaultType === 'mobile_wallet' && '⚡ يُعرض المحافظ الإلكترونية فقط'}
                      {methodConfig?.vaultType === 'cash' && '⚡ يُعرض الخزائن النقدية فقط'}
                    </div>
                  </>
                )}
              </div>
            )}
          </div>
        )}
      </Modal>

      {/* ── Reject Modal ── */}
      <Modal
        open={!!rejectReceipt} onClose={() => setRejectReceipt(null)}
        title="رفض الإيصال" size="sm"
        footer={
          <>
            <Button variant="ghost" onClick={() => setRejectReceipt(null)}>إلغاء</Button>
            <Button variant="danger" onClick={handleReject} loading={rejecting}>تأكيد الرفض</Button>
          </>
        }
      >
        <div className="form-group">
          <label className="form-label required">سبب الرفض</label>
          <textarea className="form-textarea" rows={3} value={rejectReason}
            onChange={e => setRejectReason(e.target.value)} placeholder="اذكر سبب الرفض..." />
        </div>
      </Modal>

    </div>
  )
}
