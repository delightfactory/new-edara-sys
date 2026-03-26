import { useState, useRef } from 'react'
import { toast } from 'sonner'
import { Receipt, Plus, Check, XCircle, Upload } from 'lucide-react'
import { createPaymentReceipt, confirmPaymentReceipt, rejectPaymentReceipt, uploadPaymentProof } from '@/lib/services/payments'
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

const PAYMENT_METHODS: { value: PaymentMethod; label: string }[] = [
  { value: 'cash', label: 'نقدي' },
  { value: 'bank_transfer', label: 'تحويل بنكي' },
  { value: 'instapay', label: 'إنستاباي' },
  { value: 'cheque', label: 'شيك' },
  { value: 'wallet', label: 'محفظة إلكترونية' },
]

const statusConfig: Record<string, { label: string; variant: 'warning' | 'success' | 'danger' }> = {
  pending: { label: 'معلق', variant: 'warning' },
  confirmed: { label: 'مؤكد', variant: 'success' },
  rejected: { label: 'مرفوض', variant: 'danger' },
}

export default function PaymentsPage() {
  const can = useAuthStore(s => s.can)
  const invalidate = useInvalidate()

  const [page, setPage] = useState(1)
  const [filterStatus, setFilterStatus] = useState('')

  // React Query — cached & shared
  const { data: vaults = [] } = useVaults({ isActive: true })
  const { data: result, isLoading: loading } = usePaymentReceipts({ page, pageSize: 25, status: filterStatus || undefined })
  const receipts = result?.data ?? []
  const totalPages = result?.totalPages ?? 0
  const totalCount = result?.count ?? 0

  // Customers for create modal
  const { data: customers = [] } = useQuery({
    queryKey: ['customers-active-list'],
    queryFn: async () => {
      const { data } = await supabase.from('customers').select('id, name, code').eq('is_active', true).order('name').limit(500)
      return data as { id: string; name: string; code: string }[] || []
    },
    staleTime: 5 * 60 * 1000,
  })

  // Create
  const [createOpen, setCreateOpen] = useState(false)
  const [form, setForm] = useState<PaymentReceiptInput>({ customer_id: '', amount: 0, payment_method: 'cash' })
  const [proofFile, setProofFile] = useState<File | null>(null)
  const [saving, setSaving] = useState(false)
  const [custSearch, setCustSearch] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)

  // Confirm
  const [confirmReceipt, setConfirmReceipt] = useState<PaymentReceipt | null>(null)
  const [confirmVaultId, setConfirmVaultId] = useState('')
  const [confirming, setConfirming] = useState(false)

  // Reject
  const [rejectReceipt, setRejectReceipt] = useState<PaymentReceipt | null>(null)
  const [rejectReason, setRejectReason] = useState('')
  const [rejecting, setRejecting] = useState(false)

  // ── Create ──
  const openCreate = () => { setForm({ customer_id: '', amount: 0, payment_method: 'cash' }); setProofFile(null); setCustSearch(''); setCreateOpen(true) }

  const handleCreate = async () => {
    if (!form.customer_id) { toast.error('العميل مطلوب'); return }
    if (!form.amount || form.amount <= 0) { toast.error('المبلغ يجب أن يكون أكبر من صفر'); return }
    setSaving(true)
    try {
      let proofUrl: string | undefined
      if (proofFile) proofUrl = await uploadPaymentProof(proofFile)
      await createPaymentReceipt({ ...form, proof_url: proofUrl || null })
      toast.success('تم إنشاء الإيصال'); setCreateOpen(false); invalidate('payment-receipts')
    } catch (err: any) { toast.error(err.message || 'فشل الإنشاء') }
    finally { setSaving(false) }
  }

  // ── Confirm ──
  const handleConfirm = async () => {
    if (!confirmReceipt || !confirmVaultId) { toast.error('اختر خزنة'); return }
    setConfirming(true)
    try { await confirmPaymentReceipt(confirmReceipt.id, confirmVaultId); toast.success('تم تأكيد الإيصال'); setConfirmReceipt(null); invalidate('payment-receipts') }
    catch (err: any) { toast.error(err.message) }
    finally { setConfirming(false) }
  }

  // ── Reject ──
  const handleReject = async () => {
    if (!rejectReceipt || !rejectReason.trim()) { toast.error('سبب الرفض مطلوب'); return }
    setRejecting(true)
    try { await rejectPaymentReceipt(rejectReceipt.id, rejectReason); toast.success('تم رفض الإيصال'); setRejectReceipt(null); invalidate('payment-receipts') }
    catch (err: any) { toast.error(err.message) }
    finally { setRejecting(false) }
  }

  const filteredCustomers = custSearch
    ? customers.filter(c => c.name.includes(custSearch) || c.code.includes(custSearch)).slice(0, 20)
    : customers.slice(0, 20)

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="إيصالات الدفع"
        subtitle={loading ? '...' : `${totalCount} إيصال`}
        actions={can('finance.payments.create') ? <Button icon={<Plus size={16} />} onClick={openCreate}>إيصال جديد</Button> : undefined}
      />

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-3" style={{ flexWrap: 'wrap' }}>
          <select className="form-select" style={{ width: 130 }} value={filterStatus} onChange={e => setFilterStatus(e.target.value)}>
            <option value="">كل الحالات</option>
            <option value="pending">معلق</option>
            <option value="confirmed">مؤكد</option>
            <option value="rejected">مرفوض</option>
          </select>
        </div>
      </div>

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        <DataTable<PaymentReceipt>
          columns={[
            { key: 'number', label: 'الرقم', render: (r) => <span style={{ fontWeight: 600, fontFamily: 'monospace' }}>{r.number}</span> },
            { key: 'customer', label: 'العميل', render: (r) => (
              <>
                <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{r.customer?.name || '—'}</div>
                {r.customer?.code && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{r.customer.code}</div>}
              </>
            )},
            { key: 'amount', label: 'المبلغ', render: (r) => <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{formatCurrency(r.amount)}</span> },
            { key: 'payment_method', label: 'الطريقة', hideOnMobile: true, render: (r) => PAYMENT_METHODS.find(m => m.value === r.payment_method)?.label || r.payment_method },
            { key: 'status', label: 'الحالة', render: (r) => {
              const sc = statusConfig[r.status]
              return sc ? <Badge variant={sc.variant}>{sc.label}</Badge> : <Badge>{r.status}</Badge>
            }},
            { key: 'created_at', label: 'التاريخ', hideOnMobile: true, render: (r) => formatDateTime(r.created_at) },
            { key: 'actions', label: 'إجراءات', width: 100, render: (r) => (
              r.status === 'pending' && can('finance.payments.confirm') ? (
                <div className="action-group" onClick={e => e.stopPropagation()}>
                  <Button variant="success" size="sm" title="تأكيد" onClick={() => { setConfirmReceipt(r); setConfirmVaultId(vaults[0]?.id || '') }}><Check size={14} /></Button>
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
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>

      {/* ── Create Modal ── */}
      <Modal open={createOpen} onClose={() => setCreateOpen(false)} title="إيصال دفع جديد" size="md" disableOverlayClose
        footer={<><Button variant="ghost" onClick={() => setCreateOpen(false)}>إلغاء</Button><Button onClick={handleCreate} loading={saving}>حفظ</Button></>}
      >
        <div className="flex-col gap-4">
          {/* Customer search */}
          <div className="form-group">
            <label className="form-label required">العميل</label>
            <input className="form-input" placeholder="بحث بالاسم أو الكود..." value={custSearch} onChange={e => setCustSearch(e.target.value)} />
            {custSearch && (
              <div className="search-dropdown">
                {filteredCustomers.map(c => (
                  <div key={c.id} className="search-dropdown-item" onClick={() => { setForm(f => ({ ...f, customer_id: c.id })); setCustSearch(c.name) }}>
                    <span>{c.name}</span>
                    <span style={{ color: 'var(--text-muted)', fontFamily: 'monospace', fontSize: 'var(--text-xs)' }}>{c.code}</span>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="form-row">
            <div className="form-group">
              <label className="form-label required">المبلغ</label>
              <input className="form-input" type="number" min="0.01" step="0.01" value={form.amount || ''} onChange={e => setForm(f => ({ ...f, amount: parseFloat(e.target.value) || 0 }))} placeholder="0.00" />
            </div>
            <div className="form-group">
              <label className="form-label required">طريقة الدفع</label>
              <select className="form-select" value={form.payment_method} onChange={e => setForm(f => ({ ...f, payment_method: e.target.value as PaymentMethod }))}>
                {PAYMENT_METHODS.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
              </select>
            </div>
          </div>

          {(form.payment_method === 'bank_transfer' || form.payment_method === 'instapay') && (
            <div className="form-group">
              <label className="form-label">رقم المرجع البنكي</label>
              <input className="form-input" value={form.bank_reference || ''} onChange={e => setForm(f => ({ ...f, bank_reference: e.target.value || null }))} />
            </div>
          )}
          {form.payment_method === 'cheque' && (
            <div className="form-row">
              <div className="form-group">
                <label className="form-label">رقم الشيك</label>
                <input className="form-input" value={form.check_number || ''} onChange={e => setForm(f => ({ ...f, check_number: e.target.value || null }))} />
              </div>
              <div className="form-group">
                <label className="form-label">تاريخ الشيك</label>
                <input className="form-input" type="date" value={form.check_date || ''} onChange={e => setForm(f => ({ ...f, check_date: e.target.value || null }))} />
              </div>
            </div>
          )}

          <div className="form-group">
            <label className="form-label">إثبات الدفع</label>
            <input ref={fileRef} type="file" accept="image/*,.pdf" style={{ display: 'none' }} onChange={e => setProofFile(e.target.files?.[0] || null)} />
            <Button variant="ghost" onClick={() => fileRef.current?.click()} icon={<Upload size={14} />}>{proofFile ? proofFile.name : 'رفع ملف'}</Button>
          </div>

          <div className="form-group">
            <label className="form-label">ملاحظات</label>
            <textarea className="form-textarea" rows={2} value={form.notes || ''} onChange={e => setForm(f => ({ ...f, notes: e.target.value || null }))} />
          </div>
        </div>
      </Modal>

      {/* ── Confirm Modal ── */}
      <Modal open={!!confirmReceipt} onClose={() => setConfirmReceipt(null)} title="تأكيد الإيصال" size="sm"
        footer={<><Button variant="ghost" onClick={() => setConfirmReceipt(null)}>إلغاء</Button><Button onClick={handleConfirm} loading={confirming}>تأكيد الاستلام</Button></>}
      >
        {confirmReceipt && (
          <div className="flex-col gap-4">
            <div className="info-box">
              <span className="info-box-label">المبلغ</span>
              <span className="info-box-value">{formatCurrency(confirmReceipt.amount)}</span>
              <span className="info-box-label">{confirmReceipt.customer?.name}</span>
            </div>
            <div className="form-group">
              <label className="form-label required">إيداع في خزنة</label>
              <select className="form-select" value={confirmVaultId} onChange={e => setConfirmVaultId(e.target.value)}>
                {vaults.map(v => <option key={v.id} value={v.id}>{v.name}</option>)}
              </select>
            </div>
          </div>
        )}
      </Modal>

      {/* ── Reject Modal ── */}
      <Modal open={!!rejectReceipt} onClose={() => setRejectReceipt(null)} title="رفض الإيصال" size="sm"
        footer={<><Button variant="ghost" onClick={() => setRejectReceipt(null)}>إلغاء</Button><Button variant="danger" onClick={handleReject} loading={rejecting}>تأكيد الرفض</Button></>}
      >
        <div className="form-group">
          <label className="form-label required">سبب الرفض</label>
          <textarea className="form-textarea" rows={3} value={rejectReason} onChange={e => setRejectReason(e.target.value)} placeholder="اذكر سبب الرفض..." />
        </div>
      </Modal>

    </div>
  )
}
