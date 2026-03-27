import { useState, useRef } from 'react'
import { toast } from 'sonner'
import { ReceiptText, Plus, Check, XCircle, Upload, Send, Eye, TrendingDown } from 'lucide-react'
import { createExpense, submitExpenseForApproval, approveExpense, rejectExpense, uploadExpenseReceipt } from '@/lib/services/payments'
import { useExpenses, useExpenseCategories, useVaults, useCustodyAccounts, useInvalidate } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { Expense, ExpenseInput, PaymentSource } from '@/lib/types/master-data'
import { formatCurrency, formatDate } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Modal from '@/components/ui/Modal'
import ResponsiveModal from '@/components/ui/ResponsiveModal'

const statusConfig: Record<string, { label: string; variant: 'neutral' | 'warning' | 'success' | 'danger' }> = {
  draft: { label: 'مسودة', variant: 'neutral' },
  pending_approval: { label: 'بانتظار الموافقة', variant: 'warning' },
  approved: { label: 'معتمد', variant: 'success' },
  rejected: { label: 'مرفوض', variant: 'danger' },
}

export default function ExpensesPage() {
  const can = useAuthStore(s => s.can)
  const userId = useAuthStore(s => s.profile?.id)
  const invalidate = useInvalidate()

  const [page, setPage] = useState(1)
  const [filterStatus, setFilterStatus] = useState('')

  // React Query — cached & shared
  const { data: categories = [] } = useExpenseCategories()
  const { data: vaults = [] } = useVaults({ isActive: true })
  const { data: custodyAccounts = [] } = useCustodyAccounts({ isActive: true })
  const { data: result, isLoading: loading } = useExpenses({ page, pageSize: 25, status: filterStatus || undefined })
  const expenses = result?.data ?? []
  const totalPages = result?.totalPages ?? 0
  const totalCount = result?.count ?? 0

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

  // Detail view
  const [detailExpense, setDetailExpense] = useState<Expense | null>(null)

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
      toast.success('تم إنشاء المصروف'); setCreateOpen(false); invalidate('expenses')
    } catch (err: any) { toast.error(err.message || 'فشل الإنشاء') }
    finally { setSaving(false) }
  }

  const handleSubmit = async (exp: Expense) => {
    try { await submitExpenseForApproval(exp.id); toast.success('تم تقديم المصروف للموافقة'); invalidate('expenses') }
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
      setTargetExpense(null); setApproveAction(null); invalidate('expenses')
    } catch (err: any) { toast.error(err.message) }
    finally { setProcessing(false) }
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="المصروفات"
        subtitle={loading ? '...' : `${totalCount} مصروف`}
        actions={can('finance.expenses.create') ? (
          <Button icon={<Plus size={16} />} onClick={openCreate} className="desktop-only-btn">
            مصروف جديد
          </Button>
        ) : undefined}
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

      {/* ── DESKTOP: DataTable ── */}
      <div className="exp-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<Expense>
          columns={[
            { key: 'number', label: 'الرقم', render: (e) => <span style={{ fontWeight: 600, fontFamily: 'monospace' }}>{e.number}</span> },
            { key: 'description', label: 'الوصف', render: (e) => (
              <div style={{ maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{e.description}</div>
            )},
            { key: 'amount', label: 'المبلغ', render: (e) => <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: 'var(--color-danger)' }}>{formatCurrency(e.amount)}</span> },
            { key: 'category', label: 'التصنيف', hideOnMobile: true, render: (e) => e.category?.name || <span style={{ color: 'var(--text-muted)' }}>—</span> },
            { key: 'status', label: 'الحالة', render: (e) => {
              const sc = statusConfig[e.status]; return sc ? <Badge variant={sc.variant}>{sc.label}</Badge> : <Badge>{e.status}</Badge>
            }},
            { key: 'expense_date', label: 'التاريخ', hideOnMobile: true, render: (e) => formatDate(e.expense_date) },
            { key: 'actions', label: 'إجراءات', width: 160, render: (e) => (
              <div className="action-group" onClick={ev => ev.stopPropagation()}>
                <Button variant="ghost" size="sm" title="عرض التفاصيل" onClick={() => setDetailExpense(e)}><Eye size={14} /></Button>
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
          onPageChange={setPage}
        />
      </div>

      {/* ── MOBILE: Expense Card List ── */}
      <div className="exp-card-view">
        {loading ? (
          <div className="mobile-card-list">
            {[1,2,3].map(i => <div key={i} className="edara-card" style={{ height: 96 }}><div className="skeleton" style={{ height: '100%' }} /></div>)}
          </div>
        ) : expenses.length === 0 ? (
          <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)' }}>
            <ReceiptText size={40} style={{ margin: '0 auto 12px', display: 'block', opacity: 0.3 }} />
            <p>لا توجد مصروفات</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {expenses.map((e: Expense) => {
              const sc = statusConfig[e.status]
              return (
                <div key={e.id} className="edara-card exp-mobile-card" onClick={() => setDetailExpense(e)}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 8 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                      <div style={{ width: 36, height: 36, borderRadius: 'var(--radius-md)', background: 'rgba(239,68,68,0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                        <TrendingDown size={16} style={{ color: 'var(--color-danger)' }} />
                      </div>
                      <div>
                        <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', maxWidth: 160, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{e.description}</div>
                        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{e.number}</div>
                      </div>
                    </div>
                    <div style={{ textAlign: 'left', flexShrink: 0 }}>
                      <div style={{ fontWeight: 800, fontSize: '1rem', color: 'var(--color-danger)', fontVariantNumeric: 'tabular-nums' }}>{formatCurrency(e.amount)}</div>
                      <div style={{ textAlign: 'left', marginTop: 4 }}>{sc ? <Badge variant={sc.variant}>{sc.label}</Badge> : <Badge>{e.status}</Badge>}</div>
                    </div>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    <span>{e.category?.name || '—'}</span>
                    <span>{formatDate(e.expense_date)}</span>
                  </div>
                  {(e.status === 'draft' && e.created_by === userId) && (
                    <div style={{ marginTop: 10, paddingTop: 10, borderTop: '1px solid var(--border-color)' }} onClick={ev => ev.stopPropagation()}>
                      <Button variant="primary" size="sm" icon={<Send size={13} />} style={{ width: '100%', justifyContent: 'center' }} onClick={() => handleSubmit(e)}>
                        تقديم للموافقة
                      </Button>
                    </div>
                  )}
                  {(e.status === 'pending_approval' && can('finance.expenses.approve')) && (
                    <div style={{ marginTop: 10, paddingTop: 10, borderTop: '1px solid var(--border-color)', display: 'flex', gap: 8 }} onClick={ev => ev.stopPropagation()}>
                      <Button variant="success" size="sm" icon={<Check size={13} />} style={{ flex: 1, justifyContent: 'center' }} onClick={() => { setTargetExpense(e); setApproveAction('approve') }}>موافقة</Button>
                      <Button variant="danger" size="sm" icon={<XCircle size={13} />} style={{ flex: 1, justifyContent: 'center' }} onClick={() => { setTargetExpense(e); setApproveAction('reject'); setRejectReason('') }}>رفض</Button>
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}
        {totalPages > 1 && (
          <div className="mobile-pagination">
            <Button variant="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>السابق</Button>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>{page} / {totalPages}</span>
            <Button variant="ghost" size="sm" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>التالي</Button>
          </div>
        )}
      </div>

      {/* FAB for mobile */}
      {can('finance.expenses.create') && (
        <button className="mobile-fab" onClick={openCreate} aria-label="مصروف جديد">
          <Plus size={24} />
        </button>
      )}

      {/* ── Create: ResponsiveModal (Bottom Sheet on mobile) ── */}
      <ResponsiveModal open={createOpen} onClose={() => setCreateOpen(false)} title="مصروف جديد"
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
            <input className="form-input" type="number" inputMode="decimal" enterKeyHint="next" min="0.01" step="0.01" value={form.amount || ''} onChange={e => setForm(f => ({ ...f, amount: parseFloat(e.target.value) || 0 }))} placeholder="0.00" />
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
      </ResponsiveModal>

      {/* ── Approve/Reject Modal ── */}
      <Modal open={!!targetExpense && !!approveAction} onClose={() => { setTargetExpense(null); setApproveAction(null) }}
        title={approveAction === 'approve' ? 'اعتماد المصروف' : 'رفض المصروف'} size="md"
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
            {/* بيانات المصروف */}
            <div style={{
              display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)',
              background: 'var(--bg-surface-2)', padding: 'var(--space-4)', borderRadius: 'var(--radius-lg)',
            }}>
              <div>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>الرقم</span>
                <div style={{ fontWeight: 700, fontFamily: 'monospace', fontSize: 'var(--text-sm)' }}>{targetExpense.number}</div>
              </div>
              <div>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>المبلغ</span>
                <div style={{ fontWeight: 700, fontSize: 'var(--text-lg)', color: 'var(--color-primary)' }}>{formatCurrency(targetExpense.amount)}</div>
              </div>
              <div style={{ gridColumn: '1 / -1' }}>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>الوصف</span>
                <div style={{ fontSize: 'var(--text-sm)' }}>{targetExpense.description}</div>
              </div>
              <div>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>التاريخ</span>
                <div style={{ fontSize: 'var(--text-sm)' }}>{formatDate(targetExpense.expense_date)}</div>
              </div>
              <div>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>التصنيف</span>
                <div style={{ fontSize: 'var(--text-sm)' }}>{targetExpense.category?.name || '—'}</div>
              </div>
              <div>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>مصدر الدفع</span>
                <div style={{ fontSize: 'var(--text-sm)' }}>
                  {targetExpense.payment_source === 'vault' ? `خزنة: ${targetExpense.vault?.name || '—'}` : targetExpense.payment_source === 'custody' ? `عهدة: ${targetExpense.custody?.employee?.full_name || '—'}` : '—'}
                </div>
              </div>
              <div>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>المُنشئ</span>
                <div style={{ fontSize: 'var(--text-sm)' }}>{targetExpense.created_by_profile?.full_name || '—'}</div>
              </div>
            </div>

            {/* إثبات المصروف (الإيصال) */}
            {targetExpense.receipt_url ? (
              <div style={{
                border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)',
                overflow: 'hidden', background: 'var(--bg-surface-2)',
              }}>
                <div style={{ padding: 'var(--space-2) var(--space-3)', borderBottom: '1px solid var(--border-primary)', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <span style={{ fontSize: 'var(--text-xs)', fontWeight: 600, color: 'var(--text-muted)' }}>📎 إثبات المصروف</span>
                  <a href={targetExpense.receipt_url} target="_blank" rel="noopener noreferrer"
                    style={{ fontSize: 'var(--text-xs)', color: 'var(--color-primary)', textDecoration: 'none' }}>
                    فتح في نافذة جديدة ↗
                  </a>
                </div>
                {targetExpense.receipt_url.match(/\.(jpg|jpeg|png|gif|webp|bmp|svg)(\?.*)?$/i) ? (
                  <a href={targetExpense.receipt_url} target="_blank" rel="noopener noreferrer">
                    <img
                      src={targetExpense.receipt_url}
                      alt="إثبات المصروف"
                      style={{
                        display: 'block', width: '100%', maxHeight: 400,
                        objectFit: 'contain', cursor: 'zoom-in',
                        background: 'var(--bg-app)', padding: 'var(--space-2)',
                      }}
                    />
                  </a>
                ) : (
                  <div style={{ padding: 'var(--space-4)', textAlign: 'center' }}>
                    <a href={targetExpense.receipt_url} target="_blank" rel="noopener noreferrer"
                      style={{ color: 'var(--color-primary)', fontWeight: 600, textDecoration: 'none' }}>
                      📄 عرض الملف المرفق
                    </a>
                  </div>
                )}
              </div>
            ) : (
              <div style={{
                padding: 'var(--space-4)', textAlign: 'center',
                background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-lg)',
                color: 'var(--text-muted)', fontSize: 'var(--text-sm)',
              }}>
                لا يوجد إثبات مرفق
              </div>
            )}

            {approveAction === 'reject' && (
              <div className="form-group">
                <label className="form-label required">سبب الرفض</label>
                <textarea className="form-textarea" rows={3} value={rejectReason} onChange={e => setRejectReason(e.target.value)} placeholder="اذكر سبب الرفض..." />
              </div>
            )}
          </div>
        )}
      </Modal>

      {/* ── Detail View Modal ── */}
      <Modal open={!!detailExpense} onClose={() => setDetailExpense(null)}
        title="تفاصيل المصروف" size="md"
        footer={<Button variant="ghost" onClick={() => setDetailExpense(null)}>إغلاق</Button>}
      >
        {detailExpense && (
          <div className="flex-col gap-4">
            <div style={{
              display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)',
              background: 'var(--bg-surface-2)', padding: 'var(--space-4)', borderRadius: 'var(--radius-lg)',
            }}>
              <div>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>الرقم</span>
                <div style={{ fontWeight: 700, fontFamily: 'monospace', fontSize: 'var(--text-sm)' }}>{detailExpense.number}</div>
              </div>
              <div>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>المبلغ</span>
                <div style={{ fontWeight: 700, fontSize: 'var(--text-lg)', color: 'var(--color-primary)' }}>{formatCurrency(detailExpense.amount)}</div>
              </div>
              <div style={{ gridColumn: '1 / -1' }}>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>الوصف</span>
                <div style={{ fontSize: 'var(--text-sm)' }}>{detailExpense.description}</div>
              </div>
              <div>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>التاريخ</span>
                <div style={{ fontSize: 'var(--text-sm)' }}>{formatDate(detailExpense.expense_date)}</div>
              </div>
              <div>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>التصنيف</span>
                <div style={{ fontSize: 'var(--text-sm)' }}>{detailExpense.category?.name || '—'}</div>
              </div>
              <div>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>مصدر الدفع</span>
                <div style={{ fontSize: 'var(--text-sm)' }}>
                  {detailExpense.payment_source === 'vault' ? `خزنة: ${detailExpense.vault?.name || '—'}` : detailExpense.payment_source === 'custody' ? `عهدة: ${detailExpense.custody?.employee?.full_name || '—'}` : '—'}
                </div>
              </div>
              <div>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>المُنشئ</span>
                <div style={{ fontSize: 'var(--text-sm)' }}>{detailExpense.created_by_profile?.full_name || '—'}</div>
              </div>
              <div>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>الحالة</span>
                <div style={{ fontSize: 'var(--text-sm)' }}>
                  {(() => { const sc = statusConfig[detailExpense.status]; return sc ? <Badge variant={sc.variant}>{sc.label}</Badge> : <Badge>{detailExpense.status}</Badge> })()}
                </div>
              </div>
              {detailExpense.approved_by_profile && (
                <div>
                  <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>المُعتمد</span>
                  <div style={{ fontSize: 'var(--text-sm)' }}>{detailExpense.approved_by_profile.full_name}</div>
                </div>
              )}
              {detailExpense.rejection_reason && (
                <div style={{ gridColumn: '1 / -1' }}>
                  <span style={{ fontSize: 'var(--text-xs)', color: 'var(--color-danger)' }}>سبب الرفض</span>
                  <div style={{ fontSize: 'var(--text-sm)', color: 'var(--color-danger)' }}>{detailExpense.rejection_reason}</div>
                </div>
              )}
            </div>

            {/* إثبات المصروف */}
            {detailExpense.receipt_url ? (
              <div style={{
                border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-lg)',
                overflow: 'hidden', background: 'var(--bg-surface-2)',
              }}>
                <div style={{ padding: 'var(--space-2) var(--space-3)', borderBottom: '1px solid var(--border-primary)', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <span style={{ fontSize: 'var(--text-xs)', fontWeight: 600, color: 'var(--text-muted)' }}>📎 إثبات المصروف</span>
                  <a href={detailExpense.receipt_url} target="_blank" rel="noopener noreferrer"
                    style={{ fontSize: 'var(--text-xs)', color: 'var(--color-primary)', textDecoration: 'none' }}>
                    فتح في نافذة جديدة ↗
                  </a>
                </div>
                {detailExpense.receipt_url.match(/\.(jpg|jpeg|png|gif|webp|bmp|svg)(\?.*)?$/i) ? (
                  <a href={detailExpense.receipt_url} target="_blank" rel="noopener noreferrer">
                    <img
                      src={detailExpense.receipt_url}
                      alt="إثبات المصروف"
                      style={{
                        display: 'block', width: '100%', maxHeight: 400,
                        objectFit: 'contain', cursor: 'zoom-in',
                        background: 'var(--bg-app)', padding: 'var(--space-2)',
                      }}
                    />
                  </a>
                ) : (
                  <div style={{ padding: 'var(--space-4)', textAlign: 'center' }}>
                    <a href={detailExpense.receipt_url} target="_blank" rel="noopener noreferrer"
                      style={{ color: 'var(--color-primary)', fontWeight: 600, textDecoration: 'none' }}>
                      📄 عرض الملف المرفق
                    </a>
                  </div>
                )}
              </div>
            ) : (
              <div style={{
                padding: 'var(--space-4)', textAlign: 'center',
                background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-lg)',
                color: 'var(--text-muted)', fontSize: 'var(--text-sm)',
              }}>
                لا يوجد إثبات مرفق
              </div>
            )}
          </div>
        )}
      </Modal>

      {/* Scoped CSS */}
      <style>{`
        .exp-table-view { display: block; }
        .exp-card-view  { display: none; }
        .exp-mobile-card { padding: var(--space-4); cursor: pointer; transition: background 0.12s; }
        .exp-mobile-card:hover { background: var(--bg-hover); }
        .mobile-card-list { display: flex; flex-direction: column; gap: var(--space-3); }
        .mobile-pagination { display: flex; align-items: center; justify-content: center; gap: var(--space-4); padding: var(--space-4) 0; }
        .mobile-fab {
          position: fixed; bottom: calc(70px + var(--space-4)); left: var(--space-4);
          width: 56px; height: 56px; border-radius: 50%;
          background: var(--color-danger); color: #fff;
          border: none; cursor: pointer; display: flex; align-items: center; justify-content: center;
          box-shadow: 0 4px 20px rgba(239,68,68,0.4);
          z-index: var(--z-modal, 400); transition: transform 0.15s;
        }
        .mobile-fab:hover { transform: scale(1.06); }
        @media (max-width: 768px) {
          .desktop-only-btn { display: none !important; }
          .exp-table-view { display: none; }
          .exp-card-view  { display: block; }
        }
        @media (min-width: 769px) { .mobile-fab { display: none; } }
      `}</style>
    </div>
  )
}
