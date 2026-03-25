import { useState, useEffect, useCallback, useRef } from 'react'
import { toast } from 'sonner'
import { ReceiptText, Plus, Check, XCircle, Upload, Send } from 'lucide-react'
import { getExpenses, createExpense, submitExpenseForApproval, approveExpense, rejectExpense, getExpenseCategories, uploadExpenseReceipt } from '@/lib/services/payments'
import { getVaults } from '@/lib/services/vaults'
import { getCustodyAccounts } from '@/lib/services/custody'
import { useAuthStore } from '@/stores/auth-store'
import type { Expense, ExpenseInput, ExpenseCategory, Vault, CustodyAccount, PaymentSource } from '@/lib/types/master-data'
import { formatCurrency, formatDate } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Modal from '@/components/ui/Modal'

const statusConfig: Record<string, { label: string; variant: 'neutral' | 'warning' | 'success' | 'danger' }> = {
  draft: { label: 'مسودة', variant: 'neutral' },
  pending_approval: { label: 'بانتظار الموافقة', variant: 'warning' },
  approved: { label: 'معتمد', variant: 'success' },
  rejected: { label: 'مرفوض', variant: 'danger' },
}

export default function ExpensesPage() {
  const can = useAuthStore(s => s.can)
  const userId = useAuthStore(s => s.profile?.id)

  const [expenses, setExpenses] = useState<Expense[]>([])
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [totalPages, setTotalPages] = useState(0)
  const [totalCount, setTotalCount] = useState(0)
  const [filterStatus, setFilterStatus] = useState('')
  const [categories, setCategories] = useState<ExpenseCategory[]>([])
  const [vaults, setVaults] = useState<Vault[]>([])
  const [custodyAccounts, setCustodyAccounts] = useState<CustodyAccount[]>([])

  // Create
  const [createOpen, setCreateOpen] = useState(false)
  const [form, setForm] = useState<ExpenseInput>({ amount: 0, description: '', payment_source: 'vault' })
  const [receiptFile, setReceiptFile] = useState<File | null>(null)
  const [saving, setSaving] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  // Approve/Reject
  const [targetExpense, setTargetExpense] = useState<Expense | null>(null)
  const [approveAction, setApproveAction] = useState<'approve' | 'reject' | null>(null)
  const [rejectReason, setRejectReason] = useState('')
  const [processing, setProcessing] = useState(false)

  const load = useCallback(async (p = 1) => {
    setLoading(true)
    try {
      const res = await getExpenses({ page: p, pageSize: 25, status: filterStatus || undefined })
      setExpenses(res.data); setPage(res.page); setTotalPages(res.totalPages); setTotalCount(res.count)
    } catch { toast.error('فشل تحميل المصروفات') }
    finally { setLoading(false) }
  }, [filterStatus])

  useEffect(() => {
    const init = async () => {
      const [cats, vs, custs] = await Promise.all([getExpenseCategories(), getVaults({ isActive: true }), getCustodyAccounts({ isActive: true })])
      setCategories(cats); setVaults(vs); setCustodyAccounts(custs)
      await load()
    }
    init()
  }, [load])

  useEffect(() => { load(1) }, [filterStatus, load])

  // ── Create ──
  const openCreate = () => {
    setForm({ amount: 0, description: '', payment_source: 'vault', expense_date: new Date().toISOString().split('T')[0] })
    setReceiptFile(null); setCreateOpen(true)
  }

  const handleCreate = async () => {
    if (!form.description.trim()) { toast.error('الوصف مطلوب'); return }
    if (!form.amount || form.amount <= 0) { toast.error('المبلغ يجب أن يكون أكبر من صفر'); return }
    if (form.payment_source === 'vault' && !form.vault_id) { toast.error('اختر خزنة'); return }
    if (form.payment_source === 'custody' && !form.custody_id) { toast.error('اختر عهدة'); return }
    setSaving(true)
    try {
      let receiptUrl: string | undefined
      if (receiptFile) receiptUrl = await uploadExpenseReceipt(receiptFile)
      await createExpense({ ...form, receipt_url: receiptUrl || null })
      toast.success('تم إنشاء المصروف'); setCreateOpen(false); load()
    } catch (err: any) { toast.error(err.message || 'فشل الإنشاء') }
    finally { setSaving(false) }
  }

  const handleSubmit = async (exp: Expense) => {
    try { await submitExpenseForApproval(exp.id); toast.success('تم تقديم المصروف للموافقة'); load() }
    catch (err: any) { toast.error(err.message) }
  }

  const handleApproveAction = async () => {
    if (!targetExpense || !approveAction) return
    setProcessing(true)
    try {
      if (approveAction === 'approve') { await approveExpense(targetExpense.id); toast.success('تم اعتماد المصروف') }
      else {
        if (!rejectReason.trim()) { toast.error('سبب الرفض مطلوب'); setProcessing(false); return }
        await rejectExpense(targetExpense.id, rejectReason); toast.success('تم رفض المصروف')
      }
      setTargetExpense(null); setApproveAction(null); load()
    } catch (err: any) { toast.error(err.message) }
    finally { setProcessing(false) }
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="المصروفات"
        subtitle={loading ? '...' : `${totalCount} مصروف`}
        actions={can('finance.expenses.create') ? <Button icon={<Plus size={16} />} onClick={openCreate}>مصروف جديد</Button> : undefined}
      />

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-3" style={{ flexWrap: 'wrap' }}>
          <select className="form-select" style={{ width: 160 }} value={filterStatus} onChange={e => setFilterStatus(e.target.value)}>
            <option value="">كل الحالات</option>
            <option value="draft">مسودة</option>
            <option value="pending_approval">بانتظار الموافقة</option>
            <option value="approved">معتمد</option>
            <option value="rejected">مرفوض</option>
          </select>
        </div>
      </div>

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        <DataTable<Expense>
          columns={[
            { key: 'number', label: 'الرقم', render: (e) => <span style={{ fontWeight: 600, fontFamily: 'monospace' }}>{e.number}</span> },
            { key: 'description', label: 'الوصف', render: (e) => (
              <div style={{ maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{e.description}</div>
            )},
            { key: 'amount', label: 'المبلغ', render: (e) => <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{formatCurrency(e.amount)}</span> },
            { key: 'category', label: 'التصنيف', hideOnMobile: true, render: (e) => e.category?.name || <span style={{ color: 'var(--text-muted)' }}>—</span> },
            { key: 'status', label: 'الحالة', render: (e) => {
              const sc = statusConfig[e.status]; return sc ? <Badge variant={sc.variant}>{sc.label}</Badge> : <Badge>{e.status}</Badge>
            }},
            { key: 'expense_date', label: 'التاريخ', hideOnMobile: true, render: (e) => formatDate(e.expense_date) },
            { key: 'actions', label: 'إجراءات', width: 120, render: (e) => (
              <div className="action-group" onClick={ev => ev.stopPropagation()}>
                {e.status === 'draft' && e.created_by === userId && (
                  <Button variant="primary" size="sm" title="تقديم للموافقة" onClick={() => handleSubmit(e)}><Send size={14} /></Button>
                )}
                {e.status === 'pending_approval' && can('finance.expenses.approve') && (
                  <>
                    <Button variant="success" size="sm" title="موافقة" onClick={() => { setTargetExpense(e); setApproveAction('approve') }}><Check size={14} /></Button>
                    <Button variant="danger" size="sm" title="رفض" onClick={() => { setTargetExpense(e); setApproveAction('reject'); setRejectReason('') }}><XCircle size={14} /></Button>
                  </>
                )}
              </div>
            )},
          ]}
          data={expenses}
          loading={loading}
          emptyIcon={<ReceiptText size={48} />}
          emptyTitle="لا توجد مصروفات"
          emptyText="لم يتم العثور على مصروفات مطابقة"
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={(p) => load(p)}
        />
      </div>

      {/* ── Create Modal ── */}
      <Modal open={createOpen} onClose={() => setCreateOpen(false)} title="مصروف جديد" size="md" disableOverlayClose
        footer={<><Button variant="ghost" onClick={() => setCreateOpen(false)}>إلغاء</Button><Button onClick={handleCreate} loading={saving}>حفظ</Button></>}
      >
        <div className="flex-col gap-4">
          <div className="form-group">
            <label className="form-label required">الوصف</label>
            <textarea className="form-textarea" rows={2} value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} placeholder="مثال: مصاريف نقل بضاعة" />
          </div>
          <div className="form-row">
            <div className="form-group">
              <label className="form-label required">المبلغ</label>
              <input className="form-input" type="number" min="0.01" step="0.01" value={form.amount || ''} onChange={e => setForm(f => ({ ...f, amount: parseFloat(e.target.value) || 0 }))} placeholder="0.00" />
            </div>
            <div className="form-group">
              <label className="form-label">تاريخ المصروف</label>
              <input className="form-input" type="date" value={form.expense_date || ''} onChange={e => setForm(f => ({ ...f, expense_date: e.target.value }))} />
            </div>
          </div>
          <div className="form-row">
            <div className="form-group">
              <label className="form-label">التصنيف</label>
              <select className="form-select" value={form.category_id || ''} onChange={e => setForm(f => ({ ...f, category_id: e.target.value || null }))}>
                <option value="">— بدون تصنيف —</option>
                {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label required">مصدر الدفع</label>
              <select className="form-select" value={form.payment_source} onChange={e => setForm(f => ({ ...f, payment_source: e.target.value as PaymentSource, vault_id: null, custody_id: null }))}>
                <option value="vault">خزنة</option>
                <option value="custody">عهدة</option>
              </select>
            </div>
          </div>
          {form.payment_source === 'vault' && (
            <div className="form-group">
              <label className="form-label required">الخزنة</label>
              <select className="form-select" value={form.vault_id || ''} onChange={e => setForm(f => ({ ...f, vault_id: e.target.value || null }))}>
                <option value="">— اختر —</option>
                {vaults.map(v => <option key={v.id} value={v.id}>{v.name}</option>)}
              </select>
            </div>
          )}
          {form.payment_source === 'custody' && (
            <div className="form-group">
              <label className="form-label required">العهدة</label>
              <select className="form-select" value={form.custody_id || ''} onChange={e => setForm(f => ({ ...f, custody_id: e.target.value || null }))}>
                <option value="">— اختر —</option>
                {custodyAccounts.map(c => <option key={c.id} value={c.id}>{c.employee?.full_name} ({formatCurrency(c.current_balance)})</option>)}
              </select>
            </div>
          )}
          <div className="form-group">
            <label className="form-label">إيصال المصروف</label>
            <input ref={fileRef} type="file" accept="image/*,.pdf" style={{ display: 'none' }} onChange={e => setReceiptFile(e.target.files?.[0] || null)} />
            <Button variant="ghost" onClick={() => fileRef.current?.click()} icon={<Upload size={14} />}>{receiptFile ? receiptFile.name : 'رفع ملف'}</Button>
          </div>
        </div>
      </Modal>

      {/* ── Approve/Reject Modal ── */}
      <Modal open={!!targetExpense && !!approveAction} onClose={() => { setTargetExpense(null); setApproveAction(null) }}
        title={approveAction === 'approve' ? 'اعتماد المصروف' : 'رفض المصروف'} size="sm"
        footer={
          <>
            <Button variant="ghost" onClick={() => { setTargetExpense(null); setApproveAction(null) }}>إلغاء</Button>
            <Button variant={approveAction === 'reject' ? 'danger' : 'primary'} onClick={handleApproveAction} loading={processing}>
              {approveAction === 'approve' ? 'اعتماد' : 'رفض'}
            </Button>
          </>
        }
      >
        {targetExpense && (
          <div className="flex-col gap-4">
            <div className="info-box">
              <span className="info-box-label">{targetExpense.number}</span>
              <span className="info-box-value">{formatCurrency(targetExpense.amount)}</span>
              <span className="info-box-label">{targetExpense.description}</span>
            </div>
            {approveAction === 'reject' && (
              <div className="form-group">
                <label className="form-label required">سبب الرفض</label>
                <textarea className="form-textarea" rows={3} value={rejectReason} onChange={e => setRejectReason(e.target.value)} placeholder="اذكر سبب الرفض..." />
              </div>
            )}
          </div>
        )}
      </Modal>

    </div>
  )
}
