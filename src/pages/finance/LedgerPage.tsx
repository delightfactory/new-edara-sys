import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { BookText, Users, Truck, TrendingDown, TrendingUp, ArrowLeftRight } from 'lucide-react'
import { getCustomerLedger, getCustomerBalance, getSupplierLedger, getSupplierBalance } from '@/lib/services/finance'
import { supabase } from '@/lib/supabase/client'
import type { CustomerLedgerEntry, CustomerBalance, SupplierLedgerEntry, SupplierBalance } from '@/lib/types/master-data'
import { formatCurrency, formatDateTime } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'

type LedgerTab = 'customers' | 'suppliers'

const sourceLabel: Record<string, string> = {
  sales_order: 'طلب بيع', sales_return: 'مرتجع', payment: 'دفعة', opening_balance: 'رصيد افتتاحي', adjustment: 'تسوية',
  purchase_order: 'أمر شراء', purchase_return: 'مرتجع شراء',
}

const sourceIcon: Record<string, string> = {
  sales_order: '🧾', sales_return: '↩️', payment: '💵', opening_balance: '🏁', adjustment: '📊',
  purchase_order: '📦', purchase_return: '↩️',
}

export default function LedgerPage() {
  const [tab, setTab] = useState<LedgerTab>('customers')
  const [entities, setEntities] = useState<{ id: string; name: string; code: string }[]>([])
  const [search, setSearch] = useState('')
  const [selectedId, setSelectedId] = useState('')
  const [selectedName, setSelectedName] = useState('')
  const [balance, setBalance] = useState<CustomerBalance | SupplierBalance | null>(null)
  const [ledger, setLedger] = useState<(CustomerLedgerEntry | SupplierLedgerEntry)[]>([])
  const [loading, setLoading] = useState(false)
  const [entitiesLoading, setEntitiesLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [totalPages, setTotalPages] = useState(0)
  const [totalCount, setTotalCount] = useState(0)

  // Mobile: show entity list or ledger view
  const [mobileView, setMobileView] = useState<'list' | 'ledger'>('list')

  useEffect(() => {
    const loadEntities = async () => {
      setEntitiesLoading(true); setSelectedId(''); setLedger([]); setBalance(null); setMobileView('list')
      try {
        const table = tab === 'customers' ? 'customers' : 'suppliers'
        const { data, error } = await supabase.from(table).select('id, name, code').eq('is_active', true).order('name').limit(500)
        if (error) throw error
        setEntities(data || [])
      } catch { toast.error('فشل تحميل البيانات') }
      finally { setEntitiesLoading(false) }
    }
    loadEntities()
  }, [tab])

  const loadLedger = async (entityId: string, name: string, p = 1) => {
    setSelectedId(entityId); setSelectedName(name); setLoading(true); setPage(p); setMobileView('ledger')
    try {
      if (tab === 'customers') {
        const [bal, txs] = await Promise.all([getCustomerBalance(entityId), getCustomerLedger(entityId, { page: p, pageSize: 25 })])
        setBalance(bal); setLedger(txs.data); setTotalPages(txs.totalPages); setTotalCount(txs.count)
      } else {
        const [bal, txs] = await Promise.all([getSupplierBalance(entityId), getSupplierLedger(entityId, { page: p, pageSize: 25 })])
        setBalance(bal); setLedger(txs.data); setTotalPages(txs.totalPages); setTotalCount(txs.count)
      }
    } catch { toast.error('فشل تحميل الدفتر') }
    finally { setLoading(false) }
  }

  const filteredEntities = search
    ? entities.filter(e => e.name.includes(search) || e.code.includes(search))
    : entities

  const balanceValue = balance?.balance || 0
  const isDebt = balanceValue > 0
  const balanceColor = isDebt ? 'var(--color-danger)' : 'var(--color-success)'
  const balanceLabel = tab === 'customers'
    ? (isDebt ? 'مدين لنا' : 'دائن')
    : (isDebt ? 'ندين له' : 'دائن لنا')

  /* ── Statement timeline item component ────────────────────────── */
  const StatementRow = ({ entry }: { entry: any }) => {
    const isDebit = entry.type === 'debit'
    return (
      <div className="stmt-row">
        {/* Timestamp + source badge */}
        <div className="stmt-left">
          <div className="stmt-date">{new Date(entry.created_at).toLocaleDateString('ar-EG-u-nu-latn', { day: '2-digit', month: 'short' })}</div>
          <div className="stmt-time">{new Date(entry.created_at).toLocaleTimeString('ar-EG-u-nu-latn', { hour: '2-digit', minute: '2-digit' })}</div>
        </div>

        {/* Timeline spine */}
        <div className="stmt-spine">
          <div className={`stmt-dot ${isDebit ? 'debit-dot' : 'credit-dot'}`}>
            {isDebit ? <TrendingDown size={10} /> : <TrendingUp size={10} />}
          </div>
        </div>

        {/* Content */}
        <div className="stmt-body">
          <div className="stmt-source">
            <span>{sourceIcon[entry.source_type] || '📄'}</span>
            <span>{sourceLabel[entry.source_type] || entry.source_type}</span>
          </div>
          {entry.description && <div className="stmt-desc">{entry.description}</div>}
        </div>

        {/* Amount */}
        <div className={`stmt-amount ${isDebit ? 'debit-amount' : 'credit-amount'}`}>
          <div className="stmt-amount-val">{isDebit ? '−' : '+'}{formatCurrency(entry.amount)}</div>
          <div className="stmt-amount-label">{isDebit ? 'مدين' : 'دائن'}</div>
        </div>
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="دفتر الحسابات"
        subtitle="كشف حساب العملاء والموردين"
      />

      {/* Tab bar */}
      <div className="edara-card" style={{ padding: 'var(--space-3) var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div style={{ display: 'flex', gap: 'var(--space-2)' }}>
          <Button variant={tab === 'customers' ? 'primary' : 'ghost'} icon={<Users size={16} />}
            onClick={() => setTab('customers')}>العملاء</Button>
          <Button variant={tab === 'suppliers' ? 'primary' : 'ghost'} icon={<Truck size={16} />}
            onClick={() => setTab('suppliers')}>الموردين</Button>
        </div>
      </div>

      <div className="ledger-layout">
        {/* ── Entity list panel ──────────────────────────────────── */}
        <div className={`edara-card ledger-entity-list ${mobileView === 'ledger' ? 'mobile-hidden' : ''}`}>
          <div className="ledger-search-box">
            <input
              className="form-input"
              placeholder={`بحث ${tab === 'customers' ? 'العملاء' : 'الموردين'}...`}
              value={search}
              onChange={e => setSearch(e.target.value)}
            />
          </div>
          <div className="ledger-entity-scroll">
            {entitiesLoading ? (
              <div style={{ padding: 'var(--space-4)' }}>
                {[1, 2, 3, 4, 5].map(i => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 8 }} />)}
              </div>
            ) : filteredEntities.length === 0 ? (
              <div className="ledger-empty-list">لا توجد نتائج</div>
            ) : (
              filteredEntities.map(e => (
                <div
                  key={e.id}
                  className={`ledger-entity-item ${selectedId === e.id ? 'active' : ''}`}
                  onClick={() => loadLedger(e.id, e.name)}
                >
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{e.name}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }} dir="ltr">{e.code}</div>
                </div>
              ))
            )}
          </div>
        </div>

        {/* ── Ledger content panel ──────────────────────────────── */}
        <div className={`ledger-content ${mobileView === 'list' ? 'mobile-hidden' : ''}`}>
          {/* Mobile back button */}
          <button className="ledger-back-btn" onClick={() => setMobileView('list')}>
            ← العودة للقائمة
          </button>

          {selectedId && balance ? (
            <>
              {/* Balance summary card */}
              <div className="edara-card" style={{ marginBottom: 'var(--space-4)', padding: 'var(--space-4)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 12 }}>
                  <div>
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 4 }}>كشف حساب</div>
                    <div style={{ fontWeight: 700, fontSize: 'var(--text-lg)' }}>{selectedName}</div>
                  </div>
                  <div style={{ textAlign: 'left' }}>
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 4 }}>الرصيد الحالي</div>
                    <div style={{ fontWeight: 800, fontSize: '1.35rem', color: balanceColor, fontVariantNumeric: 'tabular-nums', lineHeight: 1 }}>
                      {formatCurrency(Math.abs(balanceValue))}
                    </div>
                    <div style={{ fontSize: 'var(--text-xs)', color: balanceColor, fontWeight: 600, marginTop: 2 }}>{balanceLabel}</div>
                  </div>
                </div>
                <div style={{ display: 'flex', gap: 8, marginTop: 12, flexWrap: 'wrap' }}>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', background: 'var(--bg-surface-2)', padding: '4px 10px', borderRadius: 99 }}>
                    <ArrowLeftRight size={10} style={{ display: 'inline', marginLeft: 4 }} />
                    {balance.transaction_count} حركة
                  </div>
                  {balance.last_transaction_at && (
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', background: 'var(--bg-surface-2)', padding: '4px 10px', borderRadius: 99 }}>
                      آخر حركة: {new Date(balance.last_transaction_at).toLocaleDateString('ar-EG-u-nu-latn')}
                    </div>
                  )}
                </div>
              </div>

              {/* DESKTOP: DataTable */}
              <div className="edara-card ledger-table-view" style={{ overflow: 'auto' }}>
                <DataTable
                  columns={[
                    { key: 'created_at', label: 'التاريخ', render: (e: any) => formatDateTime(e.created_at) },
                    { key: 'type', label: 'النوع', render: (e: any) => <Badge variant={e.type === 'debit' ? 'danger' : 'success'}>{e.type === 'debit' ? 'مدين' : 'دائن'}</Badge> },
                    {
                      key: 'amount', label: 'المبلغ',
                      render: (e: any) => (
                        <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: e.type === 'debit' ? 'var(--color-danger)' : 'var(--color-success)' }}>
                          {e.type === 'debit' ? '−' : '+'}{formatCurrency(e.amount)}
                        </span>
                      ),
                    },
                    { key: 'source_type', label: 'المصدر', render: (e: any) => `${sourceIcon[e.source_type] || '📄'} ${sourceLabel[e.source_type] || e.source_type}` },
                    { key: 'description', label: 'الوصف', hideOnMobile: true, render: (e: any) => e.description || <span style={{ color: 'var(--text-muted)' }}>—</span> },
                  ]}
                  data={ledger}
                  loading={loading}
                  emptyTitle="لا توجد حركات"
                  page={page}
                  totalPages={totalPages}
                  totalCount={totalCount}
                  onPageChange={(p) => loadLedger(selectedId, selectedName, p)}
                />
              </div>

              {/* MOBILE: Bank Statement Timeline */}
              <div className="ledger-stmt-view">
                {loading ? (
                  <div style={{ padding: 'var(--space-4)' }}>
                    {[1, 2, 3, 4].map(i => <div key={i} className="skeleton" style={{ height: 72, borderRadius: 12, marginBottom: 12 }} />)}
                  </div>
                ) : ledger.length === 0 ? (
                  <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)' }}>
                    <BookText size={40} style={{ margin: '0 auto 12px', display: 'block', opacity: 0.3 }} />
                    لا توجد حركات
                  </div>
                ) : (
                  <div className="edara-card stmt-container">
                    {ledger.map((entry: any) => <StatementRow key={entry.id} entry={entry} />)}
                    {totalPages > 1 && (
                      <div className="mobile-pagination">
                        <Button variant="ghost" size="sm" disabled={page <= 1} onClick={() => loadLedger(selectedId, selectedName, page - 1)}>السابق</Button>
                        <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>{page} / {totalPages}</span>
                        <Button variant="ghost" size="sm" disabled={page >= totalPages} onClick={() => loadLedger(selectedId, selectedName, page + 1)}>التالي</Button>
                      </div>
                    )}
                  </div>
                )}
              </div>
            </>
          ) : (
            <div className="edara-card ledger-placeholder">
              <BookText size={48} strokeWidth={1} />
              <p>اختر {tab === 'customers' ? 'عميل' : 'مورد'} لعرض كشف الحساب</p>
            </div>
          )}
        </div>
      </div>

      <style>{`
        /* ── Layout ─────────────────────────── */
        .ledger-layout {
          display: grid;
          grid-template-columns: 300px 1fr;
          gap: var(--space-4);
          min-height: 500px;
        }
        .ledger-entity-list { overflow: hidden; display: flex; flex-direction: column; }
        .ledger-search-box { padding: var(--space-3); border-bottom: 1px solid var(--border-primary); }
        .ledger-entity-scroll { flex: 1; overflow-y: auto; max-height: 600px; }
        .ledger-entity-item {
          padding: var(--space-3) var(--space-4);
          border-bottom: 1px solid var(--border-primary);
          cursor: pointer;
          transition: background var(--transition-fast);
        }
        .ledger-entity-item:hover { background: var(--bg-hover); }
        .ledger-entity-item.active { background: rgba(37,99,235,0.06); border-right: 3px solid var(--color-primary); }
        .ledger-empty-list { padding: var(--space-8); text-align: center; color: var(--text-muted); }
        .ledger-placeholder {
          display: flex; flex-direction: column; align-items: center; justify-content: center;
          min-height: 400px; gap: var(--space-3); color: var(--text-muted); text-align: center;
        }
        .ledger-content { min-width: 0; }
        .ledger-back-btn { display: none; }

        /* Toggle views depending on screen */
        .ledger-table-view { display: block; }
        .ledger-stmt-view  { display: none; }

        /* ── Bank Statement styles ───────────── */
        .stmt-container { padding: var(--space-2) 0; overflow: hidden; }
        .stmt-row {
          display: flex; align-items: flex-start; gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          border-bottom: 1px solid var(--border-primary);
          transition: background 0.12s;
        }
        .stmt-row:last-child { border-bottom: none; }
        .stmt-row:hover { background: var(--bg-hover); }

        .stmt-left { flex: 0 0 44px; text-align: center; }
        .stmt-date { font-size: 0.7rem; font-weight: 700; color: var(--text-secondary); line-height: 1.2; }
        .stmt-time { font-size: 0.6rem; color: var(--text-muted); }

        .stmt-spine {
          flex: 0 0 24px; display: flex; flex-direction: column;
          align-items: center; padding-top: 2px;
        }
        .stmt-dot {
          width: 24px; height: 24px; border-radius: 50%;
          display: flex; align-items: center; justify-content: center;
          flex-shrink: 0;
        }
        .debit-dot  { background: rgba(239,68,68,0.12); color: var(--color-danger); }
        .credit-dot { background: rgba(34,197,94,0.12); color: var(--color-success); }

        .stmt-body { flex: 1; min-width: 0; }
        .stmt-source { display: flex; align-items: center; gap: 6px; font-size: var(--text-sm); font-weight: 600; }
        .stmt-desc { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

        .stmt-amount { flex: 0 0 auto; text-align: left; }
        .stmt-amount-val { font-size: var(--text-sm); font-weight: 700; font-variant-numeric: tabular-nums; }
        .debit-amount  .stmt-amount-val { color: var(--color-danger); }
        .credit-amount .stmt-amount-val { color: var(--color-success); }
        .stmt-amount-label { font-size: 0.65rem; color: var(--text-muted); }
        .debit-amount  .stmt-amount-label { color: rgba(239,68,68,0.7); }
        .credit-amount .stmt-amount-label { color: rgba(34,197,94,0.7); }

        .mobile-pagination { display: flex; align-items: center; justify-content: center; gap: var(--space-4); padding: var(--space-4) 0; border-top: 1px solid var(--border-primary); }

        /* ── Responsive ─────────────────────── */
        @media (max-width: 768px) {
          .ledger-layout { grid-template-columns: 1fr; }
          .mobile-hidden { display: none !important; }
          .ledger-table-view { display: none; }
          .ledger-stmt-view  { display: block; }
          .ledger-back-btn {
            display: block; background: none; border: none; cursor: pointer;
            color: var(--color-primary); font-size: var(--text-sm); font-weight: 600;
            padding: 0 0 var(--space-3) 0; text-align: right;
          }
        }
      `}</style>
    </div>
  )
}
