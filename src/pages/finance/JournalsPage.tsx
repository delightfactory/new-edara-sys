import { useState, useEffect, useCallback } from 'react'
import { toast } from 'sonner'
import { BookOpen, Plus, Eye } from 'lucide-react'
import { getJournalEntries, getJournalEntry, createManualJournalEntry, getChartOfAccounts } from '@/lib/services/finance'
import { useAuthStore } from '@/stores/auth-store'
import type { JournalEntry, JournalEntryLine, ChartOfAccount, JournalEntryLineInput } from '@/lib/types/master-data'
import { formatCurrency, formatDate } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Modal from '@/components/ui/Modal'

const sourceLabel: Record<string, string> = {
  sales_order: 'طلب بيع', sales_return: 'مرتجع بيع', payment: 'دفعة',
  purchase_order: 'أمر شراء', purchase_return: 'مرتجع شراء',
  expense: 'مصروف', custody: 'عهدة', transfer: 'تحويل', manual: 'يدوي',
}

export default function JournalsPage() {
  const can = useAuthStore(s => s.can)

  const [entries, setEntries] = useState<JournalEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [totalPages, setTotalPages] = useState(0)
  const [totalCount, setTotalCount] = useState(0)
  const [filterSource, setFilterSource] = useState('')
  const [accounts, setAccounts] = useState<ChartOfAccount[]>([])

  // Detail
  const [detail, setDetail] = useState<(JournalEntry & { lines: JournalEntryLine[] }) | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)

  // Create
  const [createOpen, setCreateOpen] = useState(false)
  const [manualDesc, setManualDesc] = useState('')
  const [manualDate, setManualDate] = useState(new Date().toISOString().split('T')[0])
  const [manualLines, setManualLines] = useState<JournalEntryLineInput[]>([{ account_code: '', debit: 0, credit: 0 }, { account_code: '', debit: 0, credit: 0 }])
  const [saving, setSaving] = useState(false)

  const load = useCallback(async (p = 1) => {
    setLoading(true)
    try {
      const res = await getJournalEntries({ page: p, pageSize: 25, sourceType: filterSource || undefined })
      setEntries(res.data); setPage(res.page); setTotalPages(res.totalPages); setTotalCount(res.count)
    } catch { toast.error('فشل تحميل القيود') }
    finally { setLoading(false) }
  }, [filterSource])

  useEffect(() => {
    const init = async () => { const accs = await getChartOfAccounts(); setAccounts(accs); await load() }
    init()
  }, [load])

  useEffect(() => { load(1) }, [filterSource, load])

  const openDetail = async (entry: JournalEntry) => {
    setDetailLoading(true); setDetail(null)
    try { setDetail(await getJournalEntry(entry.id)) }
    catch { toast.error('فشل تحميل القيد') }
    finally { setDetailLoading(false) }
  }

  const openCreate = () => {
    setManualDesc(''); setManualDate(new Date().toISOString().split('T')[0])
    setManualLines([{ account_code: '', debit: 0, credit: 0 }, { account_code: '', debit: 0, credit: 0 }])
    setCreateOpen(true)
  }

  const addLine = () => setManualLines(l => [...l, { account_code: '', debit: 0, credit: 0 }])
  const removeLine = (idx: number) => setManualLines(l => l.filter((_, i) => i !== idx))
  const updateLine = (idx: number, field: keyof JournalEntryLineInput, val: any) => {
    setManualLines(l => l.map((line, i) => i === idx ? { ...line, [field]: val } : line))
  }

  const totalDebit = manualLines.reduce((s, l) => s + (l.debit || 0), 0)
  const totalCredit = manualLines.reduce((s, l) => s + (l.credit || 0), 0)
  const isBalanced = totalDebit > 0 && totalDebit === totalCredit

  const handleCreate = async () => {
    if (!manualDesc.trim()) { toast.error('الوصف مطلوب'); return }
    if (!isBalanced) { toast.error('القيد غير متوازن'); return }
    if (manualLines.some(l => !l.account_code)) { toast.error('كل السطور يجب أن تحتوي على كود حساب'); return }
    setSaving(true)
    try {
      await createManualJournalEntry(
        { source_type: 'manual', description: manualDesc, entry_date: manualDate },
        manualLines.filter(l => l.debit > 0 || l.credit > 0),
      )
      toast.success('تم إنشاء القيد'); setCreateOpen(false); load()
    } catch (err: any) { toast.error(err.message || 'فشل الإنشاء') }
    finally { setSaving(false) }
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="القيود المحاسبية"
        subtitle={loading ? '...' : `${totalCount} قيد`}
        actions={can('finance.journal.create') ? <Button icon={<Plus size={16} />} onClick={openCreate}>قيد يدوي</Button> : undefined}
      />

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-3" style={{ flexWrap: 'wrap' }}>
          <select className="form-select" style={{ width: 130 }} value={filterSource} onChange={e => setFilterSource(e.target.value)}>
            <option value="">كل المصادر</option>
            {Object.entries(sourceLabel).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </div>
      </div>

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        <DataTable<JournalEntry>
          columns={[
            { key: 'number', label: 'الرقم', render: (e) => <span style={{ fontWeight: 600, fontFamily: 'monospace' }}>{e.number}</span> },
            { key: 'entry_date', label: 'التاريخ', render: (e) => formatDate(e.entry_date) },
            { key: 'source_type', label: 'المصدر', render: (e) => <Badge variant={e.is_auto ? 'info' : 'primary'}>{sourceLabel[e.source_type] || e.source_type}</Badge> },
            { key: 'description', label: 'الوصف', hideOnMobile: true, render: (e) => (
              <div style={{ maxWidth: 250, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{e.description || <span style={{ color: 'var(--text-muted)' }}>—</span>}</div>
            )},
            { key: 'total_debit', label: 'مدين', render: (e) => <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatCurrency(e.total_debit)}</span> },
            { key: 'total_credit', label: 'دائن', render: (e) => <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatCurrency(e.total_credit)}</span> },
            { key: 'actions', label: '', width: 50, render: (e) => (
              <Button variant="ghost" size="sm" title="تفاصيل" onClick={(ev: React.MouseEvent) => { ev.stopPropagation(); openDetail(e) }}><Eye size={14} /></Button>
            )},
          ]}
          data={entries}
          loading={loading}
          emptyIcon={<BookOpen size={48} />}
          emptyTitle="لا توجد قيود"
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={(p) => load(p)}
        />
      </div>

      {/* ── Detail Modal ── */}
      <Modal open={!!detail || detailLoading} onClose={() => setDetail(null)} title={`تفاصيل القيد: ${detail?.number || '...'}`} size="lg">
        {detailLoading ? (
          <div style={{ padding: 'var(--space-6)' }}>{[1,2,3].map(i => <div key={i} className="skeleton skeleton-row" />)}</div>
        ) : detail && (
          <>
            <div className="j-detail-header">
              <div className="j-detail-field">
                <span className="j-detail-label">التاريخ</span>
                <span>{formatDate(detail.entry_date)}</span>
              </div>
              <div className="j-detail-field">
                <span className="j-detail-label">المصدر</span>
                <Badge variant={detail.is_auto ? 'info' : 'primary'}>{sourceLabel[detail.source_type] || detail.source_type}</Badge>
              </div>
            </div>
            {detail.description && <div className="j-detail-desc">{detail.description}</div>}
            <table className="j-lines-table">
              <thead><tr><th>الحساب</th><th className="j-num-col">مدين</th><th className="j-num-col">دائن</th></tr></thead>
              <tbody>
                {detail.lines?.map(line => (
                  <tr key={line.id}>
                    <td><span className="j-account-code">{line.account?.code}</span>{line.account?.name}</td>
                    <td className="j-num-col" style={{ color: line.debit > 0 ? 'var(--color-primary)' : 'var(--text-muted)' }}>{line.debit > 0 ? formatCurrency(line.debit) : '—'}</td>
                    <td className="j-num-col" style={{ color: line.credit > 0 ? 'var(--color-success)' : 'var(--text-muted)' }}>{line.credit > 0 ? formatCurrency(line.credit) : '—'}</td>
                  </tr>
                ))}
                <tr className="j-total-row">
                  <td style={{ fontWeight: 700 }}>المجموع</td>
                  <td className="j-num-col" style={{ fontWeight: 700 }}>{formatCurrency(detail.total_debit)}</td>
                  <td className="j-num-col" style={{ fontWeight: 700 }}>{formatCurrency(detail.total_credit)}</td>
                </tr>
              </tbody>
            </table>
          </>
        )}
      </Modal>

      {/* ── Create Manual Entry Modal ── */}
      <Modal open={createOpen} onClose={() => setCreateOpen(false)} title="قيد محاسبي يدوي" size="lg" disableOverlayClose
        footer={
          <>
            <Button variant="ghost" onClick={() => setCreateOpen(false)}>إلغاء</Button>
            <span className="j-balance-badge" data-balanced={isBalanced}>
              {isBalanced ? '✓ متوازن' : `✗ فرق: ${formatCurrency(Math.abs(totalDebit - totalCredit))}`}
            </span>
            <Button onClick={handleCreate} loading={saving} disabled={!isBalanced}>حفظ القيد</Button>
          </>
        }
      >
        <div className="flex-col gap-4">
          <div className="form-row">
            <div className="form-group" style={{ flex: 2 }}>
              <label className="form-label required">الوصف</label>
              <input className="form-input" value={manualDesc} onChange={e => setManualDesc(e.target.value)} placeholder="مثال: قيد تسوية رصيد" />
            </div>
            <div className="form-group">
              <label className="form-label">التاريخ</label>
              <input className="form-input" type="date" value={manualDate} onChange={e => setManualDate(e.target.value)} />
            </div>
          </div>

          <div>
            <div className="flex gap-3" style={{ justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-2)' }}>
              <label className="form-label" style={{ margin: 0 }}>سطور القيد</label>
              <Button variant="ghost" size="sm" icon={<Plus size={14} />} onClick={addLine}>سطر</Button>
            </div>
            <table className="j-lines-table j-editable">
              <thead><tr><th style={{ width: '45%' }}>الحساب</th><th className="j-num-col">مدين</th><th className="j-num-col">دائن</th><th style={{ width: 36 }}></th></tr></thead>
              <tbody>
                {manualLines.map((line, idx) => (
                  <tr key={idx}>
                    <td>
                      <select className="form-select form-compact" value={line.account_code} onChange={e => updateLine(idx, 'account_code', e.target.value)}>
                        <option value="">— اختر —</option>
                        {accounts.map(a => <option key={a.id} value={a.code}>{a.code} — {a.name}</option>)}
                      </select>
                    </td>
                    <td><input className="form-input form-compact" type="number" min="0" step="0.01" value={line.debit || ''} onChange={e => updateLine(idx, 'debit', parseFloat(e.target.value) || 0)} /></td>
                    <td><input className="form-input form-compact" type="number" min="0" step="0.01" value={line.credit || ''} onChange={e => updateLine(idx, 'credit', parseFloat(e.target.value) || 0)} /></td>
                    <td>{manualLines.length > 2 && <Button variant="danger" size="sm" onClick={() => removeLine(idx)}>✕</Button>}</td>
                  </tr>
                ))}
                <tr className="j-total-row">
                  <td style={{ fontWeight: 700 }}>المجموع</td>
                  <td className="j-num-col" style={{ fontWeight: 700, color: 'var(--color-primary)' }}>{formatCurrency(totalDebit)}</td>
                  <td className="j-num-col" style={{ fontWeight: 700, color: 'var(--color-success)' }}>{formatCurrency(totalCredit)}</td>
                  <td />
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </Modal>

      <style>{`
        .flex-col { display: flex; flex-direction: column; }
        .form-row { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-4); }
        .form-compact { padding: 6px 10px !important; font-size: var(--text-sm) !important; }
        .j-detail-header { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-4); margin-bottom: var(--space-4); }
        .j-detail-field { display: flex; flex-direction: column; gap: var(--space-1); }
        .j-detail-label { font-size: var(--text-xs); color: var(--text-muted); font-weight: 500; }
        .j-detail-desc { margin-bottom: var(--space-4); padding: var(--space-3); background: var(--bg-surface-2); border-radius: var(--radius-md); font-size: var(--text-sm); color: var(--text-secondary); }
        .j-lines-table { width: 100%; border-collapse: collapse; font-size: var(--text-sm); }
        .j-lines-table th { padding: var(--space-2) var(--space-3); text-align: right; font-weight: 600; font-size: var(--text-xs); color: var(--text-muted); border-bottom: 2px solid var(--border-primary); text-transform: uppercase; }
        .j-lines-table td { padding: var(--space-2) var(--space-3); border-bottom: 1px solid var(--border-primary); }
        .j-num-col { text-align: center; font-variant-numeric: tabular-nums; min-width: 100px; }
        .j-total-row { border-top: 2px solid var(--border-primary); }
        .j-total-row td { font-weight: 700; }
        .j-account-code { font-family: monospace; color: var(--text-muted); margin-left: var(--space-2); font-size: var(--text-xs); }
        .j-balance-badge { font-size: var(--text-sm); font-weight: 600; padding: var(--space-1) var(--space-3); border-radius: var(--radius-md); }
        .j-balance-badge[data-balanced="true"] { color: var(--color-success); background: var(--color-success-light); }
        .j-balance-badge[data-balanced="false"] { color: var(--color-danger); background: var(--color-danger-light); }
        .j-editable td { padding: var(--space-1) var(--space-2); }
        @media (max-width: 768px) {
          .form-row { grid-template-columns: 1fr; }
          .j-num-col { min-width: 70px; }
        }
      `}</style>
    </div>
  )
}
