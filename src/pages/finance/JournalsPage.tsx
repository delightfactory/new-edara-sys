import { useState, useEffect, useRef } from 'react'
import { toast } from 'sonner'
import {
  BookOpen, Plus, Eye, TrendingUp, TrendingDown, Scale
} from 'lucide-react'
import {
  getJournalEntries, getJournalEntry,
  createUIManualJournalEntry, getChartOfAccounts
} from '@/lib/services/finance'
import { useAuthStore } from '@/stores/auth-store'
import type { JournalEntry, JournalEntryLine, ChartOfAccount, JournalEntryLineInput } from '@/lib/types/master-data'
import { formatCurrency, formatDate } from '@/lib/utils/format'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import { useIsAnyModalOpen } from '@/hooks/useModalStack'

const sourceLabel: Record<string, string> = {
  sales_order: 'طلب بيع', sales_return: 'مرتجع بيع', payment: 'دفعة',
  purchase_order: 'أمر شراء', purchase_return: 'مرتجع شراء',
  expense: 'مصروف', custody: 'عهدة', transfer: 'تحويل', manual: 'يدوي',
}

export default function JournalsPage() {
  const can = useAuthStore(s => s.can)
  const qc = useQueryClient()
  const isAnyModalOpen = useIsAnyModalOpen()
  const [scrollHidden, setScrollHidden] = useState(false)
  const lastScrollY = useRef(0)
  useEffect(() => {
    const onScroll = () => {
      const y = window.scrollY
      setScrollHidden(y > lastScrollY.current && y > 100)
      lastScrollY.current = y
    }
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  const [page, setPage] = useState(1)
  const [filterSource, setFilterSource] = useState('')
  const [accounts, setAccounts] = useState<ChartOfAccount[]>([])

  // Detail
  const [detail, setDetail] = useState<(JournalEntry & { lines: JournalEntryLine[] }) | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)

  // Create
  const [createOpen, setCreateOpen] = useState(false)
  const [manualDesc, setManualDesc] = useState('')
  const [manualDate, setManualDate] = useState(new Date().toISOString().split('T')[0])
  const [manualLines, setManualLines] = useState<JournalEntryLineInput[]>([
    { account_code: '', debit: 0, credit: 0 },
    { account_code: '', debit: 0, credit: 0 },
  ])
  const [saving, setSaving] = useState(false)

  const { data: result, isLoading: loading } = useQuery({
    queryKey: ['journals', page, filterSource],
    queryFn: () => getJournalEntries({ page, pageSize: 25, sourceType: filterSource || undefined }),
    staleTime: 30_000,
  })
  const entries: JournalEntry[] = (result as any)?.data ?? []
  const totalPages: number = (result as any)?.totalPages ?? 1
  const totalCount: number = (result as any)?.count ?? 0

  const openDetail = async (entry: JournalEntry) => {
    setDetailLoading(true); setDetail(null)
    try { setDetail(await getJournalEntry(entry.id)) }
    catch { toast.error('فشل تحميل القيد') }
    finally { setDetailLoading(false) }
  }

  const openCreate = async () => {
    setManualDesc(''); setManualDate(new Date().toISOString().split('T')[0])
    setManualLines([{ account_code: '', debit: 0, credit: 0 }, { account_code: '', debit: 0, credit: 0 }])
    if (accounts.length === 0) setAccounts(await getChartOfAccounts())
    setCreateOpen(true)
  }

  const addLine = () => setManualLines(l => [...l, { account_code: '', debit: 0, credit: 0 }])
  const removeLine = (idx: number) => setManualLines(l => l.filter((_, i) => i !== idx))
  const updateLine = (idx: number, field: keyof JournalEntryLineInput, val: any) =>
    setManualLines(l => l.map((line, i) => i === idx ? { ...line, [field]: val } : line))

  const totalDebit = manualLines.reduce((s, l) => s + (l.debit || 0), 0)
  const totalCredit = manualLines.reduce((s, l) => s + (l.credit || 0), 0)
  const isBalanced = totalDebit > 0 && totalDebit === totalCredit

  const handleCreate = async () => {
    if (!manualDesc.trim()) { toast.error('الوصف مطلوب'); return }
    if (!isBalanced) { toast.error('القيد غير متوازن'); return }
    if (manualLines.some(l => !l.account_code)) { toast.error('كل السطور تحتاج كود حساب'); return }
    setSaving(true)
    try {
      await createUIManualJournalEntry(
        { source_type: 'manual', description: manualDesc, entry_date: manualDate },
        manualLines.filter(l => l.debit > 0 || l.credit > 0),
      )
      toast.success('تم إنشاء القيد')
      setCreateOpen(false)
      qc.invalidateQueries({ queryKey: ['journals'] })
    } catch (err: any) { toast.error(err.message || 'فشل الإنشاء') }
    finally { setSaving(false) }
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="القيود المحاسبية"
        subtitle={loading ? '...' : `${totalCount} قيد`}
        actions={can('finance.journal.create') ? (
          <Button icon={<Plus size={16} />} onClick={openCreate} className="desktop-only-btn">قيد يدوي</Button>
        ) : undefined}
      />

      {/* Filter */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <select className="form-select" style={{ width: 160 }} value={filterSource}
          onChange={e => { setFilterSource(e.target.value); setPage(1) }}>
          <option value="">كل المصادر</option>
          {Object.entries(sourceLabel).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
      </div>

      {/* ── DESKTOP: DataTable ──────────────────────────────── */}
      <div className="jrn-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<JournalEntry>
          columns={[
            { key: 'number', label: 'الرقم', render: e => <span style={{ fontWeight: 600, fontFamily: 'monospace' }}>{e.number}</span> },
            { key: 'entry_date', label: 'التاريخ', render: e => formatDate(e.entry_date) },
            { key: 'source_type', label: 'المصدر', render: e => <Badge variant={e.is_auto ? 'info' : 'primary'}>{sourceLabel[e.source_type] || e.source_type}</Badge> },
            { key: 'description', label: 'الوصف', hideOnMobile: true, render: e => (
              <div style={{ maxWidth: 250, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {e.description || <span style={{ color: 'var(--text-muted)' }}>—</span>}
              </div>
            )},
            { key: 'total_debit', label: 'مدين', render: e => <span style={{ fontVariantNumeric: 'tabular-nums', color: 'var(--color-danger)' }}>{formatCurrency(e.total_debit)}</span> },
            { key: 'total_credit', label: 'دائن', render: e => <span style={{ fontVariantNumeric: 'tabular-nums', color: 'var(--color-success)' }}>{formatCurrency(e.total_credit)}</span> },
            { key: 'actions', label: '', width: 50, render: e => (
              <Button variant="ghost" size="sm" onClick={(ev: React.MouseEvent) => { ev.stopPropagation(); openDetail(e) }}><Eye size={14} /></Button>
            )},
          ]}
          data={entries}
          loading={loading}
          onRowClick={openDetail}
          emptyIcon={<BookOpen size={48} />}
          emptyTitle="لا توجد قيود"
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>

      {/* ── MOBILE: Journal Entry Card with Debit/Credit Split ── */}
      <div className="jrn-card-view">
        {loading ? (
          <div className="mobile-card-list">
            {[1, 2, 3].map(i => <div key={i} className="edara-card" style={{ height: 110 }}><div className="skeleton" style={{ height: '100%' }} /></div>)}
          </div>
        ) : entries.length === 0 ? (
          <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)' }}>
            <BookOpen size={40} style={{ margin: '0 auto 12px', display: 'block', opacity: 0.3 }} />
            <p>لا توجد قيود</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {entries.map((e: JournalEntry) => {
              const balanced = Math.abs(e.total_debit - e.total_credit) < 0.001
              return (
                <div key={e.id} className="edara-card jrn-mobile-card" onClick={() => openDetail(e)}>
                  {/* Header */}
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <span style={{ fontFamily: 'monospace', fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--color-primary)' }}>
                        {e.number}
                      </span>
                      <Badge variant={e.is_auto ? 'info' : 'primary'}>{sourceLabel[e.source_type] || e.source_type}</Badge>
                    </div>
                    <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                      {!balanced && <Badge variant="danger"><Scale size={9} /> غير متوازن</Badge>}
                      <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{formatDate(e.entry_date)}</span>
                    </div>
                  </div>

                  {/* Description */}
                  {e.description && (
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginBottom: 10, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {e.description}
                    </div>
                  )}

                  {/* Debit / Credit split — the key UX element */}
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
                    <div style={{ background: 'rgba(239,68,68,0.07)', borderRadius: 'var(--radius-md)', padding: '8px 12px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginBottom: 3 }}>
                        <TrendingDown size={11} style={{ color: 'var(--color-danger)' }} />
                        <span style={{ fontSize: '10px', color: 'var(--color-danger)', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.05em' }}>مدين</span>
                      </div>
                      <span style={{ fontWeight: 800, fontSize: 'var(--text-sm)', color: 'var(--color-danger)', fontVariantNumeric: 'tabular-nums' }}>
                        {formatCurrency(e.total_debit)}
                      </span>
                    </div>
                    <div style={{ background: 'rgba(34,197,94,0.07)', borderRadius: 'var(--radius-md)', padding: '8px 12px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginBottom: 3 }}>
                        <TrendingUp size={11} style={{ color: 'var(--color-success)' }} />
                        <span style={{ fontSize: '10px', color: 'var(--color-success)', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.05em' }}>دائن</span>
                      </div>
                      <span style={{ fontWeight: 800, fontSize: 'var(--text-sm)', color: 'var(--color-success)', fontVariantNumeric: 'tabular-nums' }}>
                        {formatCurrency(e.total_credit)}
                      </span>
                    </div>
                  </div>
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

      {/* Smart local FAB for Journal creation */}
      {can('finance.journal.create') && (
        <button
          className={`jrn-fab${isAnyModalOpen || scrollHidden ? ' jrn-fab--hidden' : ''}`}
          onClick={openCreate}
          aria-label="قيد يدوي"
          aria-hidden={isAnyModalOpen || scrollHidden}
        >
          <Plus size={22} />
          <span style={{ fontSize: 'var(--text-sm)', fontWeight: 700 }}>قيد +</span>
        </button>
      )}

      {/* ── Detail Modal ── */}
      <ResponsiveModal
        open={!!detail || detailLoading}
        onClose={() => setDetail(null)}
        title={`تفاصيل القيد: ${detail?.number || '...'}`}
      >
        {detailLoading ? (
          <div>{[1, 2, 3].map(i => <div key={i} className="skeleton skeleton-row" />)}</div>
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
                    <td className="j-num-col" style={{ color: line.debit > 0 ? 'var(--color-danger)' : 'var(--text-muted)' }}>{line.debit > 0 ? formatCurrency(line.debit) : '—'}</td>
                    <td className="j-num-col" style={{ color: line.credit > 0 ? 'var(--color-success)' : 'var(--text-muted)' }}>{line.credit > 0 ? formatCurrency(line.credit) : '—'}</td>
                  </tr>
                ))}
                <tr className="j-total-row">
                  <td style={{ fontWeight: 700 }}>المجموع</td>
                  <td className="j-num-col" style={{ fontWeight: 700, color: 'var(--color-danger)' }}>{formatCurrency(detail.total_debit)}</td>
                  <td className="j-num-col" style={{ fontWeight: 700, color: 'var(--color-success)' }}>{formatCurrency(detail.total_credit)}</td>
                </tr>
              </tbody>
            </table>
          </>
        )}
      </ResponsiveModal>

      {/* ── Create Manual Entry Modal ── */}
      <ResponsiveModal
        open={createOpen}
        onClose={() => setCreateOpen(false)}
        title="قيد محاسبي يدوي"
        disableOverlayClose
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', alignItems: 'center', width: '100%', justifyContent: 'flex-end' }}>
            <Button variant="ghost" onClick={() => setCreateOpen(false)}>إلغاء</Button>
            <span className="j-balance-badge" data-balanced={isBalanced}>
              {isBalanced ? '✓ متوازن' : `✗ فرق: ${formatCurrency(Math.abs(totalDebit - totalCredit))}`}
            </span>
            <Button onClick={handleCreate} loading={saving} disabled={!isBalanced}>حفظ القيد</Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div className="form-row">
            <div className="form-group" style={{ flex: 2 }}>
              <label className="form-label required">الوصف</label>
              <input className="form-input" value={manualDesc} onChange={e => setManualDesc(e.target.value)} placeholder="مثال: قيد تسوية" />
            </div>
            <div className="form-group">
              <label className="form-label">التاريخ</label>
              <input className="form-input" type="date" value={manualDate} onChange={e => setManualDate(e.target.value)} />
            </div>
          </div>

          <div>
            <div style={{ display: 'flex', gap: 'var(--space-3)', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-2)' }}>
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
                    <td>
                      <input className="form-input form-compact" type="number" inputMode="decimal" min="0" step="0.01"
                        value={line.debit || ''} onChange={e => updateLine(idx, 'debit', parseFloat(e.target.value) || 0)} />
                    </td>
                    <td>
                      <input className="form-input form-compact" type="number" inputMode="decimal" min="0" step="0.01"
                        value={line.credit || ''} onChange={e => updateLine(idx, 'credit', parseFloat(e.target.value) || 0)} />
                    </td>
                    <td>{manualLines.length > 2 && <Button variant="danger" size="sm" onClick={() => removeLine(idx)}>✕</Button>}</td>
                  </tr>
                ))}
                <tr className="j-total-row">
                  <td style={{ fontWeight: 700 }}>المجموع</td>
                  <td className="j-num-col" style={{ fontWeight: 700, color: 'var(--color-danger)' }}>{formatCurrency(totalDebit)}</td>
                  <td className="j-num-col" style={{ fontWeight: 700, color: 'var(--color-success)' }}>{formatCurrency(totalCredit)}</td>
                  <td />
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </ResponsiveModal>

      <style>{`
        .jrn-table-view { display: block; }
        .jrn-card-view  { display: none; }
        .jrn-mobile-card { padding: var(--space-4); cursor: pointer; transition: background 0.12s; }
        .jrn-mobile-card:hover { background: var(--bg-hover); }
        .mobile-card-list { display: flex; flex-direction: column; gap: var(--space-3); }
        .mobile-pagination { display: flex; align-items: center; justify-content: center; gap: var(--space-4); padding: var(--space-4) 0; }
        .form-row { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-4); }
        .form-compact { padding: 6px 10px !important; font-size: var(--text-sm) !important; }
        .j-detail-header { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-4); margin-bottom: var(--space-4); }
        .j-detail-field { display: flex; flex-direction: column; gap: var(--space-1); }
        .j-detail-label { font-size: var(--text-xs); color: var(--text-muted); font-weight: 500; }
        .j-detail-desc { margin-bottom: var(--space-4); padding: var(--space-3); background: var(--bg-surface-2); border-radius: var(--radius-md); font-size: var(--text-sm); color: var(--text-secondary); }
        .j-lines-table { width: 100%; border-collapse: collapse; font-size: var(--text-sm); }
        .j-lines-table th { padding: var(--space-2) var(--space-3); text-align: right; font-weight: 600; font-size: var(--text-xs); color: var(--text-muted); border-bottom: 2px solid var(--border-primary); }
        .j-lines-table td { padding: var(--space-2) var(--space-3); border-bottom: 1px solid var(--border-primary); }
        .j-num-col { text-align: center; font-variant-numeric: tabular-nums; min-width: 90px; }
        .j-total-row { border-top: 2px solid var(--border-primary); }
        .j-total-row td { font-weight: 700; }
        .j-account-code { font-family: monospace; color: var(--text-muted); margin-left: var(--space-2); font-size: var(--text-xs); }
        .j-balance-badge { font-size: var(--text-sm); font-weight: 600; padding: var(--space-1) var(--space-3); border-radius: var(--radius-md); }
        .j-balance-badge[data-balanced="true"] { color: var(--color-success); background: rgba(34,197,94,0.12); }
        .j-balance-badge[data-balanced="false"] { color: var(--color-danger); background: rgba(239,68,68,0.12); }
        .j-editable td { padding: var(--space-1) var(--space-2); }
        @media (max-width: 768px) {
          .desktop-only-btn { display: none !important; }
          .jrn-table-view { display: none; }
          .jrn-card-view  { display: block; }
          .form-row { grid-template-columns: 1fr; }
          .j-num-col { min-width: 70px; }
          .jrn-fab {
            display: flex; align-items: center; gap: var(--space-2);
            position: fixed;
            bottom: calc(var(--bottom-nav-height, 64px) + var(--space-4));
            inset-inline-end: var(--space-4);
            z-index: var(--z-fab, 300);
            height: var(--fab-size, 48px);
            padding: 0 var(--space-4);
            border-radius: var(--radius-full);
            background: var(--color-primary); color: white;
            border: none; cursor: pointer;
            font-family: var(--font-sans);
            box-shadow: var(--shadow-lg);
            transition: opacity 0.25s ease, transform 0.25s ease;
            -webkit-tap-highlight-color: transparent;
          }
          .jrn-fab--hidden { opacity: 0; transform: translateY(16px) scale(0.92); pointer-events: none; }
          .jrn-fab:active { transform: scale(0.95); }
        }
      `}</style>
    </div>
  )
}
