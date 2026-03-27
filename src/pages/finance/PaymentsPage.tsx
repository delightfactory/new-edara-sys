import { useState, useRef } from 'react'
import { toast } from 'sonner'
import {
  Receipt, Plus, Check, XCircle, Upload, Search,
  ExternalLink, AlertCircle, Wallet, X, Info, ImageIcon, FileText,
} from 'lucide-react'
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
import { Link, useNavigate } from 'react-router-dom'

// ════════════════════════════════════════════════════════════
// Types & Constants
// ════════════════════════════════════════════════════════════

interface PaymentMethodConfig {
  value: PaymentMethod
  label: string
  icon: string
  vaultType: 'cash' | 'bank' | 'mobile_wallet' | null
  requiresProof: boolean
  refLabel?: string
}

const PAYMENT_METHODS: PaymentMethodConfig[] = [
  { value: 'cash',          label: 'نقدي',              icon: '💵', vaultType: 'cash',          requiresProof: false },
  { value: 'bank_transfer', label: 'تحويل بنكي',        icon: '🏦', vaultType: 'bank',          requiresProof: true,  refLabel: 'رقم مرجع التحويل' },
  { value: 'instapay',      label: 'إنستاباي',          icon: '⚡', vaultType: 'mobile_wallet', requiresProof: true,  refLabel: 'رقم مرجع إنستاباي' },
  { value: 'mobile_wallet', label: 'محفظة إلكترونية',  icon: '📱', vaultType: 'mobile_wallet', requiresProof: true,  refLabel: 'رقم مرجع المحفظة' },
  { value: 'cheque',        label: 'شيك',               icon: '📋', vaultType: null,            requiresProof: true },
]

const STATUS_CONFIG: Record<string, { label: string; variant: 'warning' | 'success' | 'danger' }> = {
  pending:   { label: 'معلق',   variant: 'warning' },
  confirmed: { label: 'مؤكد',  variant: 'success' },
  rejected:  { label: 'مرفوض', variant: 'danger'  },
}

const getMethodLabel = (m: string) => PAYMENT_METHODS.find(x => x.value === m)?.label || m
const getMethodIcon  = (m: string) => PAYMENT_METHODS.find(x => x.value === m)?.icon  || '💳'

// ════════════════════════════════════════════════════════════
// Sub-components
// ════════════════════════════════════════════════════════════

/** بطاقة معلومات موحدة داخل النوافذ */
function InfoCard({ rows }: { rows: { label: string; value: React.ReactNode }[] }) {
  return (
    <div style={{
      background: 'var(--bg-surface-2)',
      border: '1px solid var(--border-primary)',
      borderRadius: 'var(--radius-md)',
      overflow: 'hidden',
    }}>
      {rows.map((row, i) => (
        <div key={i} style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          padding: 'var(--space-3) var(--space-4)',
          borderBottom: i < rows.length - 1 ? '1px solid var(--border-primary)' : 'none',
          gap: 'var(--space-4)',
        }}>
          <span style={{
            fontSize: 'var(--text-sm)',
            color: 'var(--text-secondary)',
            flexShrink: 0,
          }}>
            {row.label}
          </span>
          <span style={{
            fontSize: 'var(--text-sm)',
            fontWeight: 600,
            color: 'var(--text-primary)',
            textAlign: 'start',
          }}>
            {row.value}
          </span>
        </div>
      ))}
    </div>
  )
}

/** شريط تنبيه ملوّن */
function AlertBanner({
  variant = 'warning',
  icon,
  title,
  body,
}: {
  variant?: 'warning' | 'info' | 'success'
  icon?: React.ReactNode
  title?: string
  body: React.ReactNode
}) {
  const colors: Record<string, { bg: string; border: string; title: string }> = {
    warning: {
      bg:     'color-mix(in srgb, var(--color-warning) 8%, transparent)',
      border: 'color-mix(in srgb, var(--color-warning) 25%, transparent)',
      title:  'var(--color-warning)',
    },
    info: {
      bg:     'color-mix(in srgb, var(--color-info) 8%, transparent)',
      border: 'color-mix(in srgb, var(--color-info) 25%, transparent)',
      title:  'var(--color-info)',
    },
    success: {
      bg:     'color-mix(in srgb, var(--color-success) 8%, transparent)',
      border: 'color-mix(in srgb, var(--color-success) 25%, transparent)',
      title:  'var(--color-success)',
    },
  }
  const c = colors[variant]
  return (
    <div style={{
      padding: 'var(--space-3) var(--space-4)',
      borderRadius: 'var(--radius-md)',
      background: c.bg,
      border: `1px solid ${c.border}`,
      display: 'flex',
      alignItems: 'flex-start',
      gap: 'var(--space-2)',
    }}>
      {icon && (
        <span style={{ color: c.title, flexShrink: 0, marginTop: 1 }}>
          {icon}
        </span>
      )}
      <div style={{ fontSize: 'var(--text-sm)', lineHeight: 1.6 }}>
        {title && (
          <div style={{ fontWeight: 700, color: c.title, marginBottom: 'var(--space-1)' }}>
            {title}
          </div>
        )}
        <div style={{ color: 'var(--text-secondary)' }}>{body}</div>
      </div>
    </div>
  )
}

// ════════════════════════════════════════════════════════════
// Main Component
// ════════════════════════════════════════════════════════════

export default function PaymentsPage() {
  const can      = useAuthStore(s => s.can)
  const profile  = useAuthStore(s => s.profile)
  const navigate = useNavigate()
  const invalidate = useInvalidate()

  // ── Filters & Pagination ──
  const [page, setPage]                     = useState(1)
  const [filterStatus, setFilterStatus]     = useState('')
  const [filterCustomer, setFilterCustomer] = useState('')
  const [filterDateFrom, setFilterDateFrom] = useState('')
  const [filterDateTo, setFilterDateTo]     = useState('')
  const hasFilters = !!(filterStatus || filterCustomer || filterDateFrom || filterDateTo)

  // ── Vaults ──
  const { data: vaults = [] } = useVaults({ isActive: true })

  // ── My Custody ──
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

  // ── Receipts List ──
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

  // ── Customer Search ──
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
    return (data || []).map(c => ({ value: c.id, label: c.name, code: c.code }))
  }

  const [selectedCust, setSelectedCust] = useState<{ id: string; name: string; code: string } | null>(null)
  const [openOrders, setOpenOrders]     = useState<
    { id: string; order_number: string; total_amount: number; paid_amount: number }[]
  >([])

  // ════════════════════════════════════════════════════════════
  // Create Form
  // ════════════════════════════════════════════════════════════
  const [createOpen, setCreateOpen] = useState(false)
  const [form, setForm] = useState<PaymentReceiptInput & { sales_order_id?: string | null }>(
    { customer_id: '', amount: 0, payment_method: 'cash', sales_order_id: null }
  )
  const [proofFile, setProofFile] = useState<File | null>(null)
  const [saving, setSaving]       = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  const currentMethodCfg = PAYMENT_METHODS.find(m => m.value === form.payment_method)
  const isProofRequired  = currentMethodCfg?.requiresProof ?? false
  const isCashCreate     = form.payment_method === 'cash'
  const routeToCustody   = isCashCreate && !!myCustody && !can('finance.vaults.transact')
  const hasReference     = ['bank_transfer', 'instapay', 'mobile_wallet'].includes(form.payment_method)

  const openCreate = () => {
    setForm({ customer_id: '', amount: 0, payment_method: 'cash', sales_order_id: null })
    setProofFile(null)
    setSelectedCust(null)
    setOpenOrders([])
    setCreateOpen(true)
  }

  const handleCustSelect = async (
    _value: string | null,
    option?: { value: string; label: string; code?: string } | null
  ) => {
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
    if (!form.customer_id)           { toast.error('يرجى اختيار العميل أولاً'); return }
    if (!form.amount || form.amount <= 0) { toast.error('المبلغ يجب أن يكون أكبر من صفر'); return }
    if (isProofRequired && !proofFile) {
      toast.error('إثبات الدفع مطلوب لهذه الطريقة')
      return
    }
    setSaving(true)
    try {
      let proofUrl: string | undefined
      if (proofFile) proofUrl = await uploadPaymentProof(proofFile)

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
    } catch (err: any) {
      toast.error(err.message || 'فشل إنشاء الإيصال')
    } finally {
      setSaving(false)
    }
  }

  // مبلغ متبقي للفاتورة المختارة
  const linkedOrder   = openOrders.find(o => o.id === form.sales_order_id)
  const remaining     = linkedOrder ? linkedOrder.total_amount - (linkedOrder.paid_amount ?? 0) : null
  const overpayAmount = remaining !== null && form.amount > remaining ? form.amount - remaining : 0

  // ════════════════════════════════════════════════════════════
  // Confirm Modal
  // ════════════════════════════════════════════════════════════
  const [confirmReceipt, setConfirmReceipt] = useState<PaymentReceipt | null>(null)
  const [confirmVaultId, setConfirmVaultId] = useState('')
  const [confirming, setConfirming]         = useState(false)

  const methodConfig   = PAYMENT_METHODS.find(m => m.value === confirmReceipt?.payment_method)
  const isCheque       = confirmReceipt?.payment_method === 'cheque'
  const hasCustodyLink = !!confirmReceipt?.custody_id
  const filteredVaults = vaults.filter(v =>
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
      toast.error('يرجى اختيار الوجهة المالية')
      return
    }
    setConfirming(true)
    try {
      const vaultId = (isCheque || hasCustodyLink) ? null : confirmVaultId
      await confirmPaymentReceipt(confirmReceipt.id, vaultId)
      toast.success('تم تأكيد الإيصال وتوزيع المبلغ على الفواتير')
      setConfirmReceipt(null)
      invalidate('payment-receipts')
    } catch (err: any) {
      toast.error(err.message || 'فشل التأكيد')
    } finally {
      setConfirming(false)
    }
  }

  // ════════════════════════════════════════════════════════════
  // Reject Modal
  // ════════════════════════════════════════════════════════════
  const [rejectReceipt, setRejectReceipt] = useState<PaymentReceipt | null>(null)
  const [rejectReason, setRejectReason]   = useState('')
  const [rejecting, setRejecting]         = useState(false)

  const handleReject = async () => {
    if (!rejectReceipt || !rejectReason.trim()) {
      toast.error('سبب الرفض مطلوب')
      return
    }
    setRejecting(true)
    try {
      await rejectPaymentReceipt(rejectReceipt.id, rejectReason)
      toast.success('تم رفض الإيصال')
      setRejectReceipt(null)
      invalidate('payment-receipts')
    } catch (err: any) {
      toast.error(err.message || 'فشل الرفض')
    } finally {
      setRejecting(false)
    }
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

      {/* ── شريط الفلترة ── */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div style={{ display: 'flex', gap: 'var(--space-3)', flexWrap: 'wrap', alignItems: 'flex-end' }}>

          {/* الحالة */}
          <div className="form-group" style={{ margin: 0, minWidth: 140 }}>
            <label className="form-label">الحالة</label>
            <select className="form-select" value={filterStatus}
              onChange={e => { setFilterStatus(e.target.value); setPage(1) }}>
              <option value="">كل الحالات</option>
              <option value="pending">معلق</option>
              <option value="confirmed">مؤكد</option>
              <option value="rejected">مرفوض</option>
            </select>
          </div>

          {/* العميل — نص حر لأن الفلتر يعمل بـ customerId text في الخدمة */}
          <div className="form-group" style={{ margin: 0, minWidth: 220, flex: 1 }}>
            <label className="form-label">بحث بالعميل</label>
            <div style={{ position: 'relative' }}>
              <Search size={14} style={{
                position: 'absolute',
                insetInlineEnd: 10,
                top: '50%',
                transform: 'translateY(-50%)',
                color: 'var(--text-muted)',
                pointerEvents: 'none',
              }} />
              <input
                className="form-input"
                style={{ paddingInlineEnd: 32 }}
                placeholder="اسم العميل..."
                value={filterCustomer}
                onChange={e => { setFilterCustomer(e.target.value); setPage(1) }}
              />
            </div>
          </div>

          {/* من تاريخ */}
          <div className="form-group" style={{ margin: 0 }}>
            <label className="form-label">من</label>
            <input className="form-input" type="date" dir="ltr"
              value={filterDateFrom}
              onChange={e => { setFilterDateFrom(e.target.value); setPage(1) }} />
          </div>

          {/* إلى تاريخ */}
          <div className="form-group" style={{ margin: 0 }}>
            <label className="form-label">إلى</label>
            <input className="form-input" type="date" dir="ltr"
              value={filterDateTo}
              onChange={e => { setFilterDateTo(e.target.value); setPage(1) }} />
          </div>

          {/* مسح الفلاتر */}
          {hasFilters && (
            <Button variant="ghost" size="sm"
              icon={<X size={14} />}
              onClick={() => {
                setFilterStatus('')
                setFilterCustomer('')
                setFilterDateFrom('')
                setFilterDateTo('')
                setPage(1)
              }}>
              مسح
            </Button>
          )}
        </div>
      </div>

      {/* ── الجدول ── */}
      <div className="edara-card" style={{ overflow: 'hidden' }}>
        <DataTable<PaymentReceipt>
          onRowClick={r => navigate(`/finance/payments/${r.id}`)}
          columns={[
            {
              key: 'number', label: 'الرقم',
              render: r => (
                <span style={{
                  fontWeight: 700,
                  fontFamily: 'monospace',
                  fontSize: 'var(--text-sm)',
                  color: 'var(--color-primary)',
                  direction: 'ltr',
                  display: 'inline-block',
                }}>
                  {r.number}
                </span>
              ),
            },
            {
              key: 'customer', label: 'العميل',
              render: r => (
                <>
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>
                    {r.customer?.name || '—'}
                  </div>
                  {r.customer?.code && (
                    <div style={{
                      fontSize: 'var(--text-xs)',
                      color: 'var(--text-muted)',
                      fontFamily: 'monospace',
                      direction: 'ltr',
                      textAlign: 'start',
                    }}>
                      {r.customer.code}
                    </div>
                  )}
                </>
              ),
            },
            {
              key: 'amount', label: 'المبلغ',
              render: r => (
                <span style={{
                  fontWeight: 700,
                  fontVariantNumeric: 'tabular-nums',
                  color: 'var(--color-success)',
                  fontSize: 'var(--text-sm)',
                }}>
                  {formatCurrency(r.amount)}
                </span>
              ),
            },
            {
              key: 'payment_method', label: 'طريقة الدفع', hideOnMobile: true,
              render: r => (
                <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
                  <span>{getMethodIcon(r.payment_method)}</span>
                  <span style={{ fontSize: 'var(--text-sm)' }}>{getMethodLabel(r.payment_method)}</span>
                  {r.custody_id && (
                    <span title="مرتبط بعهدة ميدانية" style={{ color: 'var(--color-warning)' }}>
                      <Wallet size={12} />
                    </span>
                  )}
                </div>
              ),
            },
            {
              key: 'sales_order', label: 'الفاتورة', hideOnMobile: true,
              render: r => r.sales_order ? (
                <Link
                  to={`/sales/${r.sales_order_id}`}
                  onClick={e => e.stopPropagation()}
                  style={{
                    color: 'var(--color-primary)',
                    fontSize: 'var(--text-sm)',
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: 'var(--space-1)',
                    fontFamily: 'monospace',
                    fontWeight: 600,
                    direction: 'ltr',
                  }}>
                  {r.sales_order.order_number} <ExternalLink size={11} />
                </Link>
              ) : (
                <span style={{ color: 'var(--text-muted)' }}>—</span>
              ),
            },
            {
              key: 'status', label: 'الحالة',
              render: r => {
                const sc = STATUS_CONFIG[r.status]
                return sc
                  ? <Badge variant={sc.variant}>{sc.label}</Badge>
                  : <Badge>{r.status}</Badge>
              },
            },
            {
              key: 'created_at', label: 'التاريخ', hideOnMobile: true,
              render: r => (
                <span style={{
                  fontSize: 'var(--text-xs)',
                  color: 'var(--text-secondary)',
                  direction: 'ltr',
                  display: 'inline-block',
                }}>
                  {formatDateTime(r.created_at)}
                </span>
              ),
            },
            {
              key: 'actions', label: '', width: 90,
              render: r => (
                r.status === 'pending' && can('finance.payments.confirm') ? (
                  <div
                    className="action-group"
                    onClick={e => e.stopPropagation()}
                    style={{ display: 'flex', gap: 'var(--space-1)', justifyContent: 'flex-end' }}
                  >
                    <Button
                      variant="success" size="sm"
                      title="تأكيد الإيصال"
                      onClick={() => openConfirm(r)}
                      icon={<Check size={14} />}
                    />
                    <Button
                      variant="danger" size="sm"
                      title="رفض الإيصال"
                      onClick={() => { setRejectReceipt(r); setRejectReason('') }}
                      icon={<XCircle size={14} />}
                    />
                  </div>
                ) : null
              ),
            },
          ]}
          data={receipts}
          loading={loading}
          emptyIcon={<Receipt size={48} />}
          emptyTitle="لا توجد إيصالات"
          emptyText={hasFilters ? 'لا توجد إيصالات مطابقة للفلاتر' : 'لم يتم إنشاء أي إيصالات بعد'}
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>

      {/* ════════════════════════════════════════════════════════════ */}
      {/* ── نافذة إنشاء إيصال جديد ── */}
      {/* ════════════════════════════════════════════════════════════ */}
      <Modal
        open={createOpen}
        onClose={() => setCreateOpen(false)}
        title="إيصال دفع جديد"
        size="md"
        disableOverlayClose
        footer={
          <>
            <Button variant="ghost" onClick={() => setCreateOpen(false)} disabled={saving}>
              إلغاء
            </Button>
            <Button onClick={handleCreate} loading={saving}>
              حفظ الإيصال
            </Button>
          </>
        }
      >
        <div className="flex-col gap-4">

          {/* تنبيه توجيه العهدة */}
          {routeToCustody && (
            <AlertBanner
              variant="warning"
              icon={<Wallet size={16} />}
              title="تحصيل ميداني — عهدة شخصية"
              body={
                <>
                  سيُحسب هذا المبلغ على عهدتك الشخصية بعد مراجعة الإدارة.{' '}
                  رصيد عهدتك الحالي:{' '}
                  <strong>{formatCurrency(myCustody?.current_balance ?? 0)}</strong>
                </>
              }
            />
          )}

          {/* العميل */}
          <AsyncCombobox
            label="العميل"
            placeholder="ابحث باسم العميل أو كود الحساب..."
            value={form.customer_id || null}
            onChange={handleCustSelect}
            loadOptions={loadCustomers}
            required
            noOptionsText="لا يوجد عميل بهذا الاسم"
          />

          {/* المبلغ + طريقة الدفع */}
          <div className="form-row">
            <div className="form-group">
              <label className="form-label required">المبلغ</label>
              <input
                className="form-input"
                type="number"
                dir="ltr"
                min="0.01"
                step="0.01"
                value={form.amount || ''}
                placeholder="0.00"
                style={{ textAlign: 'end' }}
                onChange={e => setForm(f => ({ ...f, amount: parseFloat(e.target.value) || 0 }))}
              />
            </div>
            <div className="form-group">
              <label className="form-label required">طريقة الدفع</label>
              <select
                className="form-select"
                value={form.payment_method}
                onChange={e => {
                  setForm(f => ({ ...f, payment_method: e.target.value as PaymentMethod }))
                  setProofFile(null)
                }}
              >
                {PAYMENT_METHODS.map(m => (
                  <option key={m.value} value={m.value}>
                    {m.icon} {m.label}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* رقم المرجع (بنك / إنستاباي / محفظة) */}
          {hasReference && currentMethodCfg?.refLabel && (
            <div className="form-group">
              <label className="form-label">{currentMethodCfg.refLabel}</label>
              <input
                className="form-input"
                dir="ltr"
                placeholder="أدخل الرقم المرجعي..."
                value={form.bank_reference || ''}
                onChange={e => setForm(f => ({ ...f, bank_reference: e.target.value || null }))}
              />
            </div>
          )}

          {/* حقول الشيك */}
          {form.payment_method === 'cheque' && (
            <div className="form-row">
              <div className="form-group">
                <label className="form-label">رقم الشيك</label>
                <input
                  className="form-input"
                  dir="ltr"
                  placeholder="XXXX-XXXX"
                  value={form.check_number || ''}
                  onChange={e => setForm(f => ({ ...f, check_number: e.target.value || null }))}
                />
              </div>
              <div className="form-group">
                <label className="form-label">تاريخ الاستحقاق</label>
                <input
                  className="form-input"
                  type="date"
                  dir="ltr"
                  value={form.check_date || ''}
                  onChange={e => setForm(f => ({ ...f, check_date: e.target.value || null }))}
                />
              </div>
            </div>
          )}

          {/* ربط بفاتورة */}
          {selectedCust && openOrders.length > 0 && (
            <div className="form-group">
              <label className="form-label">تخصيص للفاتورة (اختياري)</label>
              <select
                className="form-select"
                value={form.sales_order_id || ''}
                onChange={e => setForm(f => ({ ...f, sales_order_id: e.target.value || null }))}
              >
                <option value="">— توزيع ذكي تلقائي على أقدم الفواتير —</option>
                {openOrders.map(o => (
                  <option key={o.id} value={o.id}>
                    {o.order_number} ← متبقي {formatCurrency(o.total_amount - (o.paid_amount ?? 0))}
                  </option>
                ))}
              </select>
              <div style={{
                fontSize: 'var(--text-xs)',
                color: 'var(--text-muted)',
                marginTop: 'var(--space-1)',
              }}>
                <Info size={11} style={{ display: 'inline', verticalAlign: 'middle', marginLeft: 3 }} />
                إذا لم تحدد، يُوزَّع المبلغ تلقائياً (FIFO) على أقدم الفواتير المفتوحة
              </div>
            </div>
          )}

          {/* تحذير الدفع الزائد */}
          {overpayAmount > 0 && (
            <AlertBanner
              variant="warning"
              icon={<AlertCircle size={15} />}
              body={
                <>
                  المبلغ المدخل أكبر من المتبقي بـ{' '}
                  <strong>{formatCurrency(overpayAmount)}</strong>.{' '}
                  الزيادة ستسجَّل كـ <strong>دفعة مقدمة</strong> قابلة للتوزيع لاحقاً.
                </>
              }
            />
          )}

          {/* رفع الإثبات */}
          <div className="form-group">
            <label className={`form-label${isProofRequired ? ' required' : ''}`}>
              إثبات الدفع
              {isProofRequired && (
                <span style={{
                  fontSize: 'var(--text-xs)',
                  color: 'var(--color-danger)',
                  fontWeight: 400,
                  marginInlineStart: 'var(--space-1)',
                }}>
                  (إجباري)
                </span>
              )}
            </label>

            <input
              ref={fileRef}
              type="file"
              accept="image/*,.pdf"
              style={{ display: 'none' }}
              onChange={e => setProofFile(e.target.files?.[0] || null)}
            />

            <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
              <Button
                variant={isProofRequired && !proofFile ? 'danger' : 'ghost'}
                size="sm"
                onClick={() => fileRef.current?.click()}
                icon={<Upload size={14} />}
              >
                {proofFile ? proofFile.name : 'اختر ملف'}
              </Button>

              {proofFile && (
                <Button
                  variant="ghost"
                  size="sm"
                  icon={<X size={13} />}
                  title="إزالة الملف"
                  onClick={() => setProofFile(null)}
                />
              )}

              {isProofRequired && !proofFile && (
                <span style={{
                  fontSize: 'var(--text-xs)',
                  color: 'var(--color-danger)',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 'var(--space-1)',
                }}>
                  <AlertCircle size={12} /> مطلوب
                </span>
              )}
            </div>

            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 'var(--space-1)' }}>
              صور أو PDF — بحد أقصى 5MB
            </div>
          </div>

          {/* ملاحظات */}
          <div className="form-group">
            <label className="form-label">ملاحظات</label>
            <textarea
              className="form-textarea"
              rows={2}
              placeholder="أي تفاصيل إضافية..."
              value={form.notes || ''}
              onChange={e => setForm(f => ({ ...f, notes: e.target.value || null }))}
            />
          </div>
        </div>
      </Modal>

      {/* ════════════════════════════════════════════════════════════ */}
      {/* ── نافذة تأكيد الإيصال ── */}
      {/* ════════════════════════════════════════════════════════════ */}
      <Modal
        open={!!confirmReceipt}
        onClose={() => setConfirmReceipt(null)}
        title="تأكيد استلام الإيصال"
        size="sm"
        footer={
          <>
            <Button variant="ghost" onClick={() => setConfirmReceipt(null)} disabled={confirming}>
              إلغاء
            </Button>
            <Button onClick={handleConfirm} loading={confirming}>
              تأكيد الاستلام
            </Button>
          </>
        }
      >
        {confirmReceipt && (
          <div className="flex-col gap-4">

            {/* ملخص الإيصال */}
            <InfoCard rows={[
              { label: 'العميل',      value: confirmReceipt.customer?.name || '—' },
              {
                label: 'المبلغ',
                value: (
                  <span style={{ color: 'var(--color-success)', fontSize: 'var(--text-base)' }}>
                    {formatCurrency(confirmReceipt.amount)}
                  </span>
                ),
              },
              {
                label: 'طريقة الدفع',
                value: (
                  <span style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-1)' }}>
                    {getMethodIcon(confirmReceipt.payment_method)}
                    {getMethodLabel(confirmReceipt.payment_method)}
                  </span>
                ),
              },
              ...(confirmReceipt.sales_order ? [{
                label: 'الفاتورة',
                value: (
                  <span style={{ fontFamily: 'monospace', direction: 'ltr' as const }}>
                    {confirmReceipt.sales_order.order_number}
                  </span>
                ),
              }] : []),
              ...(confirmReceipt.check_number ? [{
                label: 'رقم الشيك',
                value: (
                  <span style={{ fontFamily: 'monospace', direction: 'ltr' as const }}>
                    {confirmReceipt.check_number}
                    {confirmReceipt.check_date && ` | ${confirmReceipt.check_date}`}
                  </span>
                ),
              }] : []),
            ]} />

            {/* إثبات الدفع — يُعرض للمحاسب قبل التأكيد */}
            {confirmReceipt.proof_url && (
              <div style={{
                borderRadius: 'var(--radius-md)',
                border: '1px solid var(--border-primary)',
                overflow: 'hidden',
              }}>
                <div style={{
                  padding: 'var(--space-2) var(--space-4)',
                  background: 'var(--bg-surface-2)',
                  fontSize: 'var(--text-xs)',
                  fontWeight: 600,
                  color: 'var(--text-secondary)',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 'var(--space-2)',
                }}>
                  <ImageIcon size={12} /> إثبات الدفع
                </div>
                {/* عرض مصغّر للصورة مع رابط الفتح */}
                {/\.(jpg|jpeg|png|gif|webp)$/i.test(confirmReceipt.proof_url) ? (
                  <a href={confirmReceipt.proof_url} target="_blank" rel="noreferrer"
                    style={{ display: 'block', textDecoration: 'none' }}>
                    <img
                      src={confirmReceipt.proof_url}
                      alt="إثبات الدفع"
                      style={{
                        width: '100%',
                        maxHeight: 200,
                        objectFit: 'cover',
                        display: 'block',
                        cursor: 'zoom-in',
                      }}
                    />
                    <div style={{
                      padding: 'var(--space-2) var(--space-4)',
                      fontSize: 'var(--text-xs)',
                      color: 'var(--color-primary)',
                      display: 'flex',
                      alignItems: 'center',
                      gap: 'var(--space-1)',
                    }}>
                      <ExternalLink size={11} /> فتح في نافذة جديدة
                    </div>
                  </a>
                ) : (
                  <a href={confirmReceipt.proof_url} target="_blank" rel="noreferrer"
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 'var(--space-2)',
                      padding: 'var(--space-3) var(--space-4)',
                      fontSize: 'var(--text-sm)',
                      color: 'var(--color-primary)',
                      textDecoration: 'none',
                      fontWeight: 600,
                    }}>
                    <FileText size={14} /> فتح ملف PDF
                    <ExternalLink size={11} />
                  </a>
                )}
              </div>
            )}

            {/* مسار التوجيه المالي */}
            {isCheque ? (
              <AlertBanner
                variant="info"
                icon={<Info size={15} />}
                title="توجيه: أوراق قبض (حساب 1210)"
                body="سيُسجَّل هذا الشيك في أوراق القبض حتى تاريخ استحقاقه وتحصيله الفعلي."
              />
            ) : hasCustodyLink ? (
              <AlertBanner
                variant="warning"
                icon={<Wallet size={15} />}
                title="توجيه: عهدة ميدانية"
                body="هذا التحصيل مسجَّل على عهدة المندوب. بالتأكيد سيُضاف لرصيد العهدة."
              />
            ) : (
              <div className="form-group" style={{ margin: 0 }}>
                <label className="form-label required">
                  {methodConfig?.vaultType === 'bank'          ? 'الحساب البنكي المستقبِل' :
                   methodConfig?.vaultType === 'mobile_wallet' ? 'المحفظة الإلكترونية المستقبِلة' :
                   'الخزنة النقدية'}
                </label>
                {filteredVaults.length === 0 ? (
                  <AlertBanner
                    variant="warning"
                    icon={<AlertCircle size={15} />}
                    body={
                      `لا توجد ${methodConfig?.vaultType === 'bank' ? 'حسابات بنكية' : 'خزائن'} نشطة من هذا النوع`
                    }
                  />
                ) : (
                  <>
                    <select
                      className="form-select"
                      value={confirmVaultId}
                      onChange={e => setConfirmVaultId(e.target.value)}
                    >
                      {filteredVaults.map(v => (
                        <option key={v.id} value={v.id}>{v.name}</option>
                      ))}
                    </select>
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 'var(--space-1)' }}>
                      {methodConfig?.vaultType === 'bank'          && 'يُعرض الحسابات البنكية فقط'}
                      {methodConfig?.vaultType === 'mobile_wallet' && 'يُعرض المحافظ الإلكترونية فقط'}
                      {methodConfig?.vaultType === 'cash'          && 'يُعرض الخزائن النقدية فقط'}
                    </div>
                  </>
                )}
              </div>
            )}
          </div>
        )}
      </Modal>

      {/* ════════════════════════════════════════════════════════════ */}
      {/* ── نافذة رفض الإيصال ── */}
      {/* ════════════════════════════════════════════════════════════ */}
      <Modal
        open={!!rejectReceipt}
        onClose={() => setRejectReceipt(null)}
        title="رفض الإيصال"
        size="sm"
        footer={
          <>
            <Button variant="ghost" onClick={() => setRejectReceipt(null)} disabled={rejecting}>
              إلغاء
            </Button>
            <Button variant="danger" onClick={handleReject} loading={rejecting}
              icon={<XCircle size={15} />}>
              تأكيد الرفض
            </Button>
          </>
        }
      >
        {rejectReceipt && (
          <div className="flex-col gap-3">
            {/* معلومات الإيصال المراد رفضه */}
            <InfoCard rows={[
              { label: 'العميل', value: rejectReceipt.customer?.name || '—' },
              {
                label: 'المبلغ',
                value: (
                  <span style={{ color: 'var(--color-danger)' }}>
                    {formatCurrency(rejectReceipt.amount)}
                  </span>
                ),
              },
              {
                label: 'الطريقة',
                value: `${getMethodIcon(rejectReceipt.payment_method)} ${getMethodLabel(rejectReceipt.payment_method)}`,
              },
            ]} />

            <div className="form-group" style={{ margin: 0 }}>
              <label className="form-label required">سبب الرفض</label>
              <textarea
                className="form-textarea"
                rows={3}
                value={rejectReason}
                onChange={e => setRejectReason(e.target.value)}
                placeholder="اذكر سبب رفض هذا الإيصال بوضوح..."
                style={{ resize: 'vertical' }}
              />
            </div>
          </div>
        )}
      </Modal>

    </div>
  )
}
