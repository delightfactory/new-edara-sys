import { useState, useEffect, useCallback } from 'react'
import { toast } from 'sonner'
import { ShieldCheck, Plus, Edit, ArrowDownToLine, ArrowUpFromLine, Eye } from 'lucide-react'
import { getCustodyAccounts, createCustodyAccount, updateCustodyAccount, getCustodyTransactions, loadCustodyFromVault, settleCustodyToVault } from '@/lib/services/custody'
import { getVaults } from '@/lib/services/vaults'
import { useAuthStore } from '@/stores/auth-store'
import type { CustodyAccount, CustodyTransaction, Vault } from '@/lib/types/master-data'
import { formatCurrency, formatDateTime } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Modal from '@/components/ui/Modal'

export default function CustodyPage() {
  const can = useAuthStore(s => s.can)

  const [accounts, setAccounts] = useState<CustodyAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [vaults, setVaults] = useState<Vault[]>([])
  const [profiles, setProfiles] = useState<{ id: string; full_name: string }[]>([])

  // Form
  const [formOpen, setFormOpen] = useState(false)
  const [editingAccount, setEditingAccount] = useState<CustodyAccount | null>(null)
  const [formEmployee, setFormEmployee] = useState('')
  const [formMaxBalance, setFormMaxBalance] = useState('5000')
  const [formActive, setFormActive] = useState(true)
  const [saving, setSaving] = useState(false)

  // Load/Settle
  const [opMode, setOpMode] = useState<'load' | 'settle' | null>(null)
  const [opAccount, setOpAccount] = useState<CustodyAccount | null>(null)
  const [opVaultId, setOpVaultId] = useState('')
  const [opAmount, setOpAmount] = useState('')
  const [opSaving, setOpSaving] = useState(false)

  // Statement
  const [stmtAccount, setStmtAccount] = useState<CustodyAccount | null>(null)
  const [stmtTxs, setStmtTxs] = useState<CustodyTransaction[]>([])
  const [stmtLoading, setStmtLoading] = useState(false)
  const [stmtPage, setStmtPage] = useState(1)
  const [stmtTotal, setStmtTotal] = useState(0)
  const [stmtTotalPages, setStmtTotalPages] = useState(0)

  const load = useCallback(async () => {
    setLoading(true)
    try { setAccounts(await getCustodyAccounts()) }
    catch { toast.error('فشل تحميل العُهد') }
    finally { setLoading(false) }
  }, [])

  useEffect(() => {
    const init = async () => {
      const [vs] = await Promise.all([getVaults({ isActive: true })])
      setVaults(vs)
      const { data } = await (await import('@/lib/supabase/client')).supabase
        .from('profiles').select('id, full_name').eq('status', 'active').order('full_name')
      if (data) setProfiles(data)
      await load()
    }
    init()
  }, [load])

  // ── Form ──
  const openCreate = () => { setEditingAccount(null); setFormEmployee(''); setFormMaxBalance('5000'); setFormActive(true); setFormOpen(true) }
  const openEdit = (acc: CustodyAccount) => { setEditingAccount(acc); setFormEmployee(acc.employee_id); setFormMaxBalance(String(acc.max_balance)); setFormActive(acc.is_active); setFormOpen(true) }

  const handleSave = async () => {
    const maxBal = parseFloat(formMaxBalance)
    if (editingAccount) {
      setSaving(true)
      try { await updateCustodyAccount(editingAccount.id, { max_balance: maxBal, is_active: formActive }); toast.success('تم التعديل'); setFormOpen(false); load() }
      catch (err: any) { toast.error(err.message) }
      finally { setSaving(false) }
    } else {
      if (!formEmployee) { toast.error('الموظف مطلوب'); return }
      setSaving(true)
      try { await createCustodyAccount({ employee_id: formEmployee, max_balance: maxBal }); toast.success('تم إنشاء العهدة'); setFormOpen(false); load() }
      catch (err: any) { toast.error(err.message) }
      finally { setSaving(false) }
    }
  }

  // ── Operations ──
  const openOp = (acc: CustodyAccount, mode: 'load' | 'settle') => { setOpAccount(acc); setOpMode(mode); setOpVaultId(vaults[0]?.id || ''); setOpAmount('') }
  const handleOp = async () => {
    if (!opAccount || !opMode) return
    const amt = parseFloat(opAmount)
    if (!amt || amt <= 0) { toast.error('المبلغ يجب أن يكون أكبر من صفر'); return }
    if (!opVaultId) { toast.error('اختر خزنة'); return }
    setOpSaving(true)
    try {
      if (opMode === 'load') await loadCustodyFromVault(opAccount.id, opVaultId, amt)
      else await settleCustodyToVault(opAccount.id, opVaultId, amt)
      toast.success(opMode === 'load' ? 'تم تحميل العهدة' : 'تم التسوية')
      setOpMode(null); load()
    } catch (err: any) { toast.error(err.message || 'فشلت العملية') }
    finally { setOpSaving(false) }
  }

  // ── Statement ──
  const openStatement = async (acc: CustodyAccount) => {
    setStmtAccount(acc); setStmtPage(1); setStmtLoading(true)
    try { const res = await getCustodyTransactions(acc.id, { page: 1, pageSize: 25 }); setStmtTxs(res.data); setStmtTotal(res.count); setStmtTotalPages(res.totalPages) }
    catch { toast.error('فشل تحميل الحركات') }
    finally { setStmtLoading(false) }
  }
  const loadStmtPage = async (p: number) => {
    if (!stmtAccount) return; setStmtPage(p); setStmtLoading(true)
    try { const res = await getCustodyTransactions(stmtAccount.id, { page: p, pageSize: 25 }); setStmtTxs(res.data) }
    catch { toast.error('فشل') }
    finally { setStmtLoading(false) }
  }

  const txTypeLabel: Record<string, string> = { load: 'تحميل', collection: 'تحصيل', expense: 'مصروف', settlement: 'تسوية', return: 'إرجاع' }
  const txTypeBadge = (t: string): 'success' | 'danger' | 'info' => {
    if (t === 'load') return 'success'; if (['settlement', 'return', 'expense'].includes(t)) return 'danger'; return 'info'
  }

  const totalCustody = accounts.reduce((s, a) => s + a.current_balance, 0)

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="إدارة العُهد"
        subtitle={loading ? '...' : `${accounts.length} عهدة`}
        actions={can('finance.custody.create') ? <Button icon={<Plus size={16} />} onClick={openCreate}>عهدة جديدة</Button> : undefined}
      />

      {/* Stats */}
      <div className="edara-stats-row">
        <div className="edara-card stat-card">
          <span className="stat-label">إجمالي العُهد المحمّلة</span>
          <span className="stat-value" style={{ color: 'var(--color-primary)' }}>{formatCurrency(totalCustody)}</span>
        </div>
        <div className="edara-card stat-card">
          <span className="stat-label">عدد العُهد</span>
          <span className="stat-value">{accounts.length}</span>
        </div>
      </div>

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        <DataTable<CustodyAccount>
          columns={[
            { key: 'employee', label: 'الموظف', render: (a) => <span style={{ fontWeight: 600 }}>{a.employee?.full_name || '—'}</span> },
            { key: 'current_balance', label: 'الرصيد', render: (a) => (
              <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: 'var(--color-primary)' }}>{formatCurrency(a.current_balance)}</span>
            )},
            { key: 'max_balance', label: 'الحد الأقصى', hideOnMobile: true, render: (a) => (
              <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatCurrency(a.max_balance)}</span>
            )},
            { key: 'usage', label: 'الاستخدام', hideOnMobile: true, render: (a) => {
              const pct = a.max_balance > 0 ? (a.current_balance / a.max_balance) * 100 : 0
              return (
                <div className="flex gap-2" style={{ alignItems: 'center' }}>
                  <div className="usage-bar"><div className="usage-fill" style={{ width: `${Math.min(pct, 100)}%`, background: pct > 80 ? 'var(--color-danger)' : 'var(--color-primary)' }} /></div>
                  <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', minWidth: 32 }}>{pct.toFixed(0)}%</span>
                </div>
              )
            }},
            { key: 'is_active', label: 'الحالة', render: (a) => <Badge variant={a.is_active ? 'success' : 'neutral'}>{a.is_active ? 'نشطة' : 'معطلة'}</Badge> },
            { key: 'actions', label: 'إجراءات', width: 150, render: (a) => (
              <div className="action-group" onClick={e => e.stopPropagation()}>
                <Button variant="ghost" size="sm" title="كشف حساب" onClick={() => openStatement(a)}><Eye size={14} /></Button>
                {can('finance.custody.transact') && (
                  <>
                    <Button variant="success" size="sm" title="تحميل" onClick={() => openOp(a, 'load')}><ArrowDownToLine size={14} /></Button>
                    <Button variant="ghost" size="sm" title="تسوية" onClick={() => openOp(a, 'settle')}><ArrowUpFromLine size={14} /></Button>
                  </>
                )}
                {can('finance.custody.create') && (
                  <Button variant="ghost" size="sm" title="تعديل" onClick={() => openEdit(a)}><Edit size={14} /></Button>
                )}
              </div>
            )},
          ]}
          data={accounts}
          loading={loading}
          emptyIcon={<ShieldCheck size={48} />}
          emptyTitle="لا توجد عُهد"
          emptyText="قم بإنشاء عهدة لموظف"
          emptyAction={can('finance.custody.create') ? <Button icon={<Plus size={16} />} onClick={openCreate}>عهدة جديدة</Button> : undefined}
        />
      </div>

      {/* Form Modal */}
      <Modal open={formOpen} onClose={() => setFormOpen(false)} title={editingAccount ? 'تعديل العهدة' : 'عهدة جديدة'} size="sm"
        footer={<><Button variant="ghost" onClick={() => setFormOpen(false)}>إلغاء</Button><Button onClick={handleSave} loading={saving}>حفظ</Button></>}
      >
        <div className="flex-col gap-4">
          {!editingAccount && (
            <div className="form-group">
              <label className="form-label required">الموظف</label>
              <select className="form-select" value={formEmployee} onChange={e => setFormEmployee(e.target.value)}>
                <option value="">— اختر —</option>
                {profiles.map(p => <option key={p.id} value={p.id}>{p.full_name}</option>)}
              </select>
            </div>
          )}
          <div className="form-group">
            <label className="form-label">الحد الأقصى</label>
            <input className="form-input" type="number" min="0" value={formMaxBalance} onChange={e => setFormMaxBalance(e.target.value)} />
          </div>
          {editingAccount && (
            <div className="form-group">
              <label className="form-label-check"><input type="checkbox" checked={formActive} onChange={e => setFormActive(e.target.checked)} /> نشطة</label>
            </div>
          )}
        </div>
      </Modal>

      {/* Load/Settle Modal */}
      <Modal open={!!opMode} onClose={() => setOpMode(null)} title={opMode === 'load' ? `تحميل عهدة: ${opAccount?.employee?.full_name}` : `تسوية عهدة: ${opAccount?.employee?.full_name}`} size="sm"
        footer={<><Button variant="ghost" onClick={() => setOpMode(null)}>إلغاء</Button><Button onClick={handleOp} loading={opSaving}>تأكيد</Button></>}
      >
        <div className="flex-col gap-4">
          {opAccount && (
            <div className="info-box">
              <span className="info-box-label">رصيد العهدة الحالي</span>
              <span className="info-box-value">{formatCurrency(opAccount.current_balance)}</span>
              <span className="info-box-label">الحد الأقصى: {formatCurrency(opAccount.max_balance)}</span>
            </div>
          )}
          <div className="form-group">
            <label className="form-label required">الخزنة</label>
            <select className="form-select" value={opVaultId} onChange={e => setOpVaultId(e.target.value)}>
              {vaults.map(v => <option key={v.id} value={v.id}>{v.name} ({formatCurrency(v.current_balance)})</option>)}
            </select>
          </div>
          <div className="form-group">
            <label className="form-label required">المبلغ</label>
            <input className="form-input" type="number" min="0.01" step="0.01" value={opAmount} onChange={e => setOpAmount(e.target.value)} placeholder="0.00" autoFocus />
          </div>
        </div>
      </Modal>

      {/* Statement Modal */}
      <Modal open={!!stmtAccount} onClose={() => setStmtAccount(null)} title={`كشف حساب العهدة: ${stmtAccount?.employee?.full_name || ''}`} size="lg">
        <DataTable<CustodyTransaction>
          columns={[
            { key: 'created_at', label: 'التاريخ', render: (tx) => formatDateTime(tx.created_at) },
            { key: 'type', label: 'النوع', render: (tx) => <Badge variant={txTypeBadge(tx.type)}>{txTypeLabel[tx.type] || tx.type}</Badge> },
            { key: 'amount', label: 'المبلغ', render: (tx) => <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{formatCurrency(tx.amount)}</span> },
            { key: 'balance_after', label: 'الرصيد بعد', render: (tx) => formatCurrency(tx.balance_after) },
            { key: 'vault', label: 'الخزنة', hideOnMobile: true, render: (tx) => tx.vault?.name || '—' },
            { key: 'description', label: 'الوصف', hideOnMobile: true, render: (tx) => tx.description || '—' },
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

    </div>
  )
}
