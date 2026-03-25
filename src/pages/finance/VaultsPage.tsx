import { useState, useEffect, useCallback } from 'react'
import { toast } from 'sonner'
import { Landmark, Plus, Edit, ArrowDownToLine, ArrowUpFromLine, Eye, Building2, Wallet, ArrowLeftRight } from 'lucide-react'
import { getVaults, createVault, updateVault, getVaultTransactions, addVaultDeposit, addVaultWithdrawal, addVaultOpeningBalance, transferBetweenVaults } from '@/lib/services/vaults'
import { getBranches } from '@/lib/services/geography'
import { useAuthStore } from '@/stores/auth-store'
import type { Vault, VaultInput, VaultTransaction, Branch, VaultType } from '@/lib/types/master-data'
import { formatCurrency, formatDateTime } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Modal from '@/components/ui/Modal'

const VAULT_TYPES: { value: VaultType; label: string }[] = [
  { value: 'cash', label: 'نقدي' },
  { value: 'bank', label: 'بنكي' },
  { value: 'mobile_wallet', label: 'محفظة إلكترونية' },
]

const vaultTypeLabel = (t: VaultType) => VAULT_TYPES.find(v => v.value === t)?.label || t
const vaultTypeBadge = (t: VaultType): 'primary' | 'success' | 'info' => {
  const map: Record<VaultType, 'primary' | 'success' | 'info'> = { cash: 'success', bank: 'primary', mobile_wallet: 'info' }
  return map[t] || 'primary'
}

export default function VaultsPage() {
  const can = useAuthStore(s => s.can)

  const [vaults, setVaults] = useState<Vault[]>([])
  const [loading, setLoading] = useState(true)
  const [branches, setBranches] = useState<Branch[]>([])
  const [profiles, setProfiles] = useState<{ id: string; full_name: string }[]>([])

  // Form modal
  const [formOpen, setFormOpen] = useState(false)
  const [editingVault, setEditingVault] = useState<Vault | null>(null)
  const [form, setForm] = useState<VaultInput>({ name: '', type: 'cash' })
  const [saving, setSaving] = useState(false)

  // Transaction modal
  const [txMode, setTxMode] = useState<'deposit' | 'withdrawal' | 'opening' | null>(null)
  const [txVault, setTxVault] = useState<Vault | null>(null)
  const [txAmount, setTxAmount] = useState('')
  const [txDesc, setTxDesc] = useState('')
  const [txSaving, setTxSaving] = useState(false)

  // Statement modal
  const [stmtVault, setStmtVault] = useState<Vault | null>(null)
  const [stmtTxs, setStmtTxs] = useState<VaultTransaction[]>([])
  const [stmtLoading, setStmtLoading] = useState(false)
  const [stmtPage, setStmtPage] = useState(1)
  const [stmtTotal, setStmtTotal] = useState(0)
  const [stmtTotalPages, setStmtTotalPages] = useState(0)

  // Transfer modal
  const [transferOpen, setTransferOpen] = useState(false)
  const [transferFrom, setTransferFrom] = useState('')
  const [transferTo, setTransferTo] = useState('')
  const [transferAmount, setTransferAmount] = useState('')
  const [transferDesc, setTransferDesc] = useState('')
  const [transferSaving, setTransferSaving] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    try { setVaults(await getVaults()) }
    catch { toast.error('فشل تحميل الخزائن') }
    finally { setLoading(false) }
  }, [])

  useEffect(() => {
    const init = async () => {
      const [brs] = await Promise.all([getBranches()])
      setBranches(brs)
      const { data } = await (await import('@/lib/supabase/client')).supabase
        .from('profiles').select('id, full_name').eq('status', 'active').order('full_name')
      if (data) setProfiles(data)
      await load()
    }
    init()
  }, [load])

  // ── Form handlers ──
  const openCreate = () => {
    setEditingVault(null)
    setForm({ name: '', type: 'cash' })
    setFormOpen(true)
  }

  const openEdit = (v: Vault) => {
    setEditingVault(v)
    setForm({
      name: v.name,
      type: v.type,
      account_number: v.account_number,
      bank_name: v.bank_name,
      responsible_id: v.responsible_id,
      branch_id: v.branch_id,
      is_active: v.is_active,
    })
    setFormOpen(true)
  }

  const handleSave = async () => {
    if (!form.name.trim()) { toast.error('الاسم مطلوب'); return }
    setSaving(true)
    try {
      if (editingVault) {
        await updateVault(editingVault.id, form)
        toast.success('تم تعديل الخزنة')
      } else {
        await createVault(form)
        toast.success('تم إنشاء الخزنة')
      }
      setFormOpen(false)
      load()
    } catch (err: any) {
      toast.error(err.message || 'فشل الحفظ')
    } finally {
      setSaving(false)
    }
  }

  // ── Transaction handlers ──
  const openTx = (vault: Vault, mode: 'deposit' | 'withdrawal' | 'opening') => {
    setTxVault(vault)
    setTxMode(mode)
    setTxAmount('')
    setTxDesc(mode === 'opening' ? 'رصيد افتتاحي' : '')
  }

  const handleTx = async () => {
    if (!txVault || !txMode) return
    const amt = parseFloat(txAmount)
    if (!amt || amt <= 0) { toast.error('المبلغ يجب أن يكون أكبر من صفر'); return }
    if (txMode !== 'opening' && !txDesc.trim()) { toast.error('الوصف مطلوب'); return }
    setTxSaving(true)
    try {
      if (txMode === 'deposit') await addVaultDeposit(txVault.id, amt, txDesc)
      else if (txMode === 'withdrawal') await addVaultWithdrawal(txVault.id, amt, txDesc)
      else await addVaultOpeningBalance(txVault.id, amt)

      toast.success(txMode === 'deposit' ? 'تم الإيداع بنجاح' : txMode === 'withdrawal' ? 'تم السحب بنجاح' : 'تم إضافة الرصيد الافتتاحي')
      setTxMode(null)
      load()
    } catch (err: any) {
      toast.error(err.message || 'فشلت العملية')
    } finally {
      setTxSaving(false)
    }
  }

  // ── Transfer handler ──
  const openTransfer = () => {
    setTransferFrom(''); setTransferTo(''); setTransferAmount(''); setTransferDesc('')
    setTransferOpen(true)
  }

  const handleTransfer = async () => {
    if (!transferFrom) { toast.error('اختر خزنة المصدر'); return }
    if (!transferTo) { toast.error('اختر خزنة الوجهة'); return }
    if (transferFrom === transferTo) { toast.error('لا يمكن التحويل من وإلى نفس الخزنة'); return }
    const amt = parseFloat(transferAmount)
    if (!amt || amt <= 0) { toast.error('المبلغ يجب أن يكون أكبر من صفر'); return }
    if (!transferDesc.trim()) { toast.error('الوصف مطلوب'); return }
    setTransferSaving(true)
    try {
      await transferBetweenVaults(transferFrom, transferTo, amt, transferDesc)
      toast.success('تم التحويل بنجاح')
      setTransferOpen(false)
      load()
    } catch (err: any) {
      toast.error(err.message || 'فشل التحويل')
    } finally {
      setTransferSaving(false)
    }
  }

  // ── Statement ──
  const openStatement = async (vault: Vault) => {
    setStmtVault(vault)
    setStmtPage(1)
    setStmtLoading(true)
    try {
      const res = await getVaultTransactions(vault.id, { page: 1, pageSize: 25 })
      setStmtTxs(res.data)
      setStmtTotal(res.count)
      setStmtTotalPages(res.totalPages)
    } catch { toast.error('فشل تحميل الحركات') }
    finally { setStmtLoading(false) }
  }

  const loadStmtPage = async (p: number) => {
    if (!stmtVault) return
    setStmtPage(p)
    setStmtLoading(true)
    try {
      const res = await getVaultTransactions(stmtVault.id, { page: p, pageSize: 25 })
      setStmtTxs(res.data)
    } catch { toast.error('فشل تحميل الحركات') }
    finally { setStmtLoading(false) }
  }

  const txTypeLabel: Record<string, string> = {
    deposit: 'إيداع', withdrawal: 'سحب', collection: 'تحصيل', expense: 'مصروف',
    custody_load: 'تحميل عهدة', custody_return: 'إرجاع عهدة',
    transfer_in: 'تحويل وارد', transfer_out: 'تحويل صادر', opening_balance: 'رصيد افتتاحي',
  }
  const txTypeBadgeVariant = (t: string): 'success' | 'danger' | 'neutral' => {
    if (['deposit', 'collection', 'custody_return', 'transfer_in', 'opening_balance'].includes(t)) return 'success'
    if (['withdrawal', 'expense', 'custody_load', 'transfer_out'].includes(t)) return 'danger'
    return 'neutral'
  }

  // ── Totals ──
  const totalBalance = vaults.reduce((s, v) => s + v.current_balance, 0)
  const activeCount = vaults.filter(v => v.is_active).length

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="الخزائن"
        subtitle={loading ? '...' : `${vaults.length} خزنة`}
        actions={
          <div className="flex gap-2">
            {can('finance.vaults.transact') && vaults.filter(v => v.is_active).length >= 2 && (
              <Button variant="secondary" icon={<ArrowLeftRight size={16} />} onClick={openTransfer}>تحويل بين الخزائن</Button>
            )}
            {can('finance.vaults.create') && (
              <Button icon={<Plus size={16} />} onClick={openCreate}>خزنة جديدة</Button>
            )}
          </div>
        }
      />

      {/* Stats */}
      <div className="edara-stats-row">
        <div className="edara-card stat-card">
          <span className="stat-label">إجمالي الرصيد</span>
          <span className="stat-value" style={{ color: totalBalance >= 0 ? 'var(--color-success)' : 'var(--color-danger)' }}>{formatCurrency(totalBalance)}</span>
        </div>
        <div className="edara-card stat-card">
          <span className="stat-label">الخزائن النشطة</span>
          <span className="stat-value">{activeCount}</span>
        </div>
        <div className="edara-card stat-card">
          <span className="stat-label">إجمالي الخزائن</span>
          <span className="stat-value">{vaults.length}</span>
        </div>
      </div>

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        <DataTable<Vault>
          columns={[
            { key: 'name', label: 'اسم الخزنة', render: (v) => (
              <div className="flex gap-2" style={{ alignItems: 'center' }}>
                {v.type === 'cash' ? <Wallet size={16} /> : v.type === 'bank' ? <Building2 size={16} /> : <Landmark size={16} />}
                <span style={{ fontWeight: 600 }}>{v.name}</span>
              </div>
            )},
            { key: 'type', label: 'النوع', render: (v) => <Badge variant={vaultTypeBadge(v.type)}>{vaultTypeLabel(v.type)}</Badge> },
            { key: 'current_balance', label: 'الرصيد', render: (v) => (
              <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: v.current_balance >= 0 ? 'var(--color-success)' : 'var(--color-danger)' }}>
                {formatCurrency(v.current_balance)}
              </span>
            )},
            { key: 'branch', label: 'الفرع', hideOnMobile: true, render: (v) => v.branch?.name || <span style={{ color: 'var(--text-muted)' }}>—</span> },
            { key: 'responsible', label: 'المسؤول', hideOnMobile: true, render: (v) => v.responsible?.full_name || <span style={{ color: 'var(--text-muted)' }}>—</span> },
            { key: 'is_active', label: 'الحالة', render: (v) => <Badge variant={v.is_active ? 'success' : 'neutral'}>{v.is_active ? 'نشطة' : 'معطلة'}</Badge> },
            { key: 'actions', label: 'إجراءات', width: 140, render: (v) => (
              <div className="action-group" onClick={e => e.stopPropagation()}>
                <Button variant="ghost" size="sm" title="كشف حساب" onClick={() => openStatement(v)}><Eye size={14} /></Button>
                {can('finance.vaults.transact') && (
                  <>
                    <Button variant="success" size="sm" title="إيداع" onClick={() => openTx(v, 'deposit')}><ArrowDownToLine size={14} /></Button>
                    <Button variant="danger" size="sm" title="سحب" onClick={() => openTx(v, 'withdrawal')}><ArrowUpFromLine size={14} /></Button>
                  </>
                )}
                {can('finance.vaults.update') && (
                  <Button variant="ghost" size="sm" title="تعديل" onClick={() => openEdit(v)}><Edit size={14} /></Button>
                )}
              </div>
            )},
          ]}
          data={vaults}
          loading={loading}
          emptyIcon={<Landmark size={48} />}
          emptyTitle="لا توجد خزائن"
          emptyText="قم بإنشاء أول خزنة لبدء العمل"
          emptyAction={can('finance.vaults.create') ? <Button icon={<Plus size={16} />} onClick={openCreate}>خزنة جديدة</Button> : undefined}
        />
      </div>

      {/* ── Form Modal ── */}
      <Modal
        open={formOpen}
        onClose={() => setFormOpen(false)}
        title={editingVault ? 'تعديل الخزنة' : 'خزنة جديدة'}
        size="md"
        footer={
          <>
            <Button variant="ghost" onClick={() => setFormOpen(false)}>إلغاء</Button>
            <Button onClick={handleSave} loading={saving}>حفظ</Button>
          </>
        }
      >
        <div className="flex-col gap-4">
          <div className="form-group">
            <label className="form-label required">الاسم</label>
            <input className="form-input" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} placeholder="مثال: الخزنة الرئيسية" />
          </div>
          <div className="form-group">
            <label className="form-label required">النوع</label>
            <select className="form-select" value={form.type} onChange={e => setForm(f => ({ ...f, type: e.target.value as VaultType }))}>
              {VAULT_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
          </div>
          {(form.type === 'bank' || form.type === 'mobile_wallet') && (
            <>
              <div className="form-group">
                <label className="form-label">{form.type === 'bank' ? 'اسم البنك' : 'اسم المحفظة'}</label>
                <input className="form-input" value={form.bank_name || ''} onChange={e => setForm(f => ({ ...f, bank_name: e.target.value || null }))} />
              </div>
              <div className="form-group">
                <label className="form-label">رقم الحساب</label>
                <input className="form-input" value={form.account_number || ''} onChange={e => setForm(f => ({ ...f, account_number: e.target.value || null }))} />
              </div>
            </>
          )}
          <div className="form-group">
            <label className="form-label">الفرع</label>
            <select className="form-select" value={form.branch_id || ''} onChange={e => setForm(f => ({ ...f, branch_id: e.target.value || null }))}>
              <option value="">— لا يوجد —</option>
              {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
            </select>
          </div>
          <div className="form-group">
            <label className="form-label">المسؤول</label>
            <select className="form-select" value={form.responsible_id || ''} onChange={e => setForm(f => ({ ...f, responsible_id: e.target.value || null }))}>
              <option value="">— لا يوجد —</option>
              {profiles.map(p => <option key={p.id} value={p.id}>{p.full_name}</option>)}
            </select>
          </div>
          {editingVault && (
            <div className="form-group">
              <label className="form-label-check">
                <input type="checkbox" checked={form.is_active !== false} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} />
                نشطة
              </label>
            </div>
          )}
        </div>
      </Modal>

      {/* ── Transaction Modal ── */}
      <Modal
        open={!!txMode}
        onClose={() => setTxMode(null)}
        title={txMode === 'deposit' ? `إيداع في: ${txVault?.name}` : txMode === 'withdrawal' ? `سحب من: ${txVault?.name}` : `رصيد افتتاحي: ${txVault?.name}`}
        size="sm"
        footer={
          <>
            <Button variant="ghost" onClick={() => setTxMode(null)}>إلغاء</Button>
            <Button
              onClick={handleTx}
              loading={txSaving}
              variant={txMode === 'withdrawal' ? 'danger' : 'primary'}
            >
              {txMode === 'deposit' ? 'تأكيد الإيداع' : txMode === 'withdrawal' ? 'تأكيد السحب' : 'تأكيد'}
            </Button>
          </>
        }
      >
        <div className="flex-col gap-4">
          {txVault && (
            <div className="info-box">
              <span className="info-box-label">الرصيد الحالي</span>
              <span className="info-box-value">{formatCurrency(txVault.current_balance)}</span>
            </div>
          )}
          <div className="form-group">
            <label className="form-label required">المبلغ</label>
            <input className="form-input" type="number" min="0.01" step="0.01" value={txAmount} onChange={e => setTxAmount(e.target.value)} placeholder="0.00" autoFocus />
          </div>
          {txMode !== 'opening' && (
            <div className="form-group">
              <label className="form-label required">الوصف</label>
              <input className="form-input" value={txDesc} onChange={e => setTxDesc(e.target.value)} placeholder="مثال: إيداع نقدي" />
            </div>
          )}
        </div>
      </Modal>

      {/* ── Statement Modal ── */}
      <Modal
        open={!!stmtVault}
        onClose={() => setStmtVault(null)}
        title={`كشف حساب: ${stmtVault?.name || ''}`}
        size="lg"
      >
        <DataTable<VaultTransaction>
          columns={[
            { key: 'created_at', label: 'التاريخ', render: (tx) => formatDateTime(tx.created_at) },
            { key: 'type', label: 'النوع', render: (tx) => <Badge variant={txTypeBadgeVariant(tx.type)}>{txTypeLabel[tx.type] || tx.type}</Badge> },
            { key: 'amount', label: 'المبلغ', render: (tx) => <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{formatCurrency(tx.amount)}</span> },
            { key: 'balance_after', label: 'الرصيد بعد', render: (tx) => formatCurrency(tx.balance_after) },
            { key: 'description', label: 'الوصف', hideOnMobile: true, render: (tx) => tx.description || <span style={{ color: 'var(--text-muted)' }}>—</span> },
          ]}
          data={stmtTxs}
          loading={stmtLoading}
          emptyTitle="لا توجد حركات"
          page={stmtPage}
          totalPages={stmtTotalPages}
          totalCount={stmtTotal}
          onPageChange={loadStmtPage}
        />
      </Modal>

      {/* ── Transfer Modal ── */}
      <Modal
        open={transferOpen}
        onClose={() => setTransferOpen(false)}
        title="تحويل بين الخزائن"
        size="sm"
        disableOverlayClose
        footer={
          <>
            <Button variant="ghost" onClick={() => setTransferOpen(false)}>إلغاء</Button>
            <Button onClick={handleTransfer} loading={transferSaving} icon={<ArrowLeftRight size={16} />}>تأكيد التحويل</Button>
          </>
        }
      >
        <div className="flex-col gap-4">
          <div className="form-group">
            <label className="form-label required">من خزنة</label>
            <select className="form-select" value={transferFrom} onChange={e => { setTransferFrom(e.target.value); if (e.target.value === transferTo) setTransferTo('') }}>
              <option value="">— اختر خزنة المصدر —</option>
              {vaults.filter(v => v.is_active).map(v => (
                <option key={v.id} value={v.id}>{v.name} ({formatCurrency(v.current_balance)})</option>
              ))}
            </select>
          </div>
          <div className="form-group">
            <label className="form-label required">إلى خزنة</label>
            <select className="form-select" value={transferTo} onChange={e => setTransferTo(e.target.value)}>
              <option value="">— اختر خزنة الوجهة —</option>
              {vaults.filter(v => v.is_active && v.id !== transferFrom).map(v => (
                <option key={v.id} value={v.id}>{v.name} ({formatCurrency(v.current_balance)})</option>
              ))}
            </select>
          </div>
          {transferFrom && (
            <div className="info-box">
              <span className="info-box-label">رصيد خزنة المصدر</span>
              <span className="info-box-value">{formatCurrency(vaults.find(v => v.id === transferFrom)?.current_balance || 0)}</span>
            </div>
          )}
          <div className="form-group">
            <label className="form-label required">المبلغ</label>
            <input className="form-input" type="number" min="0.01" step="0.01" value={transferAmount} onChange={e => setTransferAmount(e.target.value)} placeholder="0.00" />
          </div>
          <div className="form-group">
            <label className="form-label required">الوصف</label>
            <input className="form-input" value={transferDesc} onChange={e => setTransferDesc(e.target.value)} placeholder="مثال: تحويل نقدي لصندوق الفرع" />
          </div>
        </div>
      </Modal>

    </div>
  )
}
