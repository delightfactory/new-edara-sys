import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { BookText, Users, Truck } from 'lucide-react'
import { getCustomerLedger, getCustomerBalance, getSupplierLedger, getSupplierBalance } from '@/lib/services/finance'
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

export default function LedgerPage() {
  const [tab, setTab] = useState<LedgerTab>('customers')
  const [entities, setEntities] = useState<{ id: string; name: string; code: string }[]>([])
  const [search, setSearch] = useState('')
  const [selectedId, setSelectedId] = useState('')
  const [balance, setBalance] = useState<CustomerBalance | SupplierBalance | null>(null)
  const [ledger, setLedger] = useState<(CustomerLedgerEntry | SupplierLedgerEntry)[]>([])
  const [loading, setLoading] = useState(false)
  const [entitiesLoading, setEntitiesLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [totalPages, setTotalPages] = useState(0)
  const [totalCount, setTotalCount] = useState(0)

  // Load entities
  useEffect(() => {
    const loadEntities = async () => {
      setEntitiesLoading(true); setSelectedId(''); setLedger([]); setBalance(null)
      try {
        const { supabase } = await import('@/lib/supabase/client')
        const table = tab === 'customers' ? 'customers' : 'suppliers'
        const { data, error } = await supabase.from(table).select('id, name, code').eq('is_active', true).order('name').limit(500)
        if (error) throw error
        setEntities(data || [])
      } catch { toast.error('فشل تحميل البيانات') }
      finally { setEntitiesLoading(false) }
    }
    loadEntities()
  }, [tab])

  const loadLedger = async (entityId: string, p = 1) => {
    setSelectedId(entityId); setLoading(true); setPage(p)
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

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="دفتر الحسابات"
        subtitle="كشف حساب العملاء والموردين"
      />

      {/* Tab bar */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-2">
          <Button variant={tab === 'customers' ? 'primary' : 'ghost'} icon={<Users size={16} />} onClick={() => setTab('customers')}>العملاء</Button>
          <Button variant={tab === 'suppliers' ? 'primary' : 'ghost'} icon={<Truck size={16} />} onClick={() => setTab('suppliers')}>الموردين</Button>
        </div>
      </div>

      <div className="ledger-layout">
        {/* Entity list */}
        <div className="edara-card ledger-entity-list">
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
              <div style={{ padding: 'var(--space-4)' }}>{[1,2,3,4].map(i => <div key={i} className="skeleton skeleton-row" />)}</div>
            ) : filteredEntities.length === 0 ? (
              <div className="ledger-empty-list">لا توجد نتائج</div>
            ) : (
              filteredEntities.map(e => (
                <div
                  key={e.id}
                  className={`ledger-entity-item ${selectedId === e.id ? 'active' : ''}`}
                  onClick={() => loadLedger(e.id)}
                >
                  <div style={{ fontWeight: 500, fontSize: 'var(--text-sm)' }}>{e.name}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{e.code}</div>
                </div>
              ))
            )}
          </div>
        </div>

        {/* Ledger view */}
        <div className="ledger-content">
          {selectedId && balance ? (
            <>
              {/* Balance card */}
              <div className="edara-card edara-stats-row" style={{ marginBottom: 'var(--space-4)' }}>
                <div className="stat-card">
                  <span className="stat-label">الرصيد</span>
                  <span className="stat-value" style={{ color: (balance.balance || 0) > 0 ? 'var(--color-danger)' : 'var(--color-success)' }}>
                    {formatCurrency(balance.balance || 0)}
                  </span>
                  <span className="stat-sub">
                    {tab === 'customers' ? ((balance.balance || 0) > 0 ? 'مدين لنا' : 'دائن') : ((balance.balance || 0) > 0 ? 'ندين له' : 'دائن لنا')}
                  </span>
                </div>
                <div className="stat-card">
                  <span className="stat-label">عدد الحركات</span>
                  <span className="stat-value">{balance.transaction_count}</span>
                </div>
                <div className="stat-card">
                  <span className="stat-label">آخر حركة</span>
                  <span style={{ fontWeight: 500, fontSize: 'var(--text-sm)' }}>{balance.last_transaction_at ? formatDateTime(balance.last_transaction_at) : '—'}</span>
                </div>
              </div>

              {/* Table */}
              <div className="edara-card" style={{ overflow: 'auto' }}>
                <DataTable
                  columns={[
                    { key: 'created_at', label: 'التاريخ', render: (e: any) => formatDateTime(e.created_at) },
                    { key: 'type', label: 'النوع', render: (e: any) => <Badge variant={e.type === 'debit' ? 'danger' : 'success'}>{e.type === 'debit' ? 'مدين' : 'دائن'}</Badge> },
                    { key: 'amount', label: 'المبلغ', render: (e: any) => <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{formatCurrency(e.amount)}</span> },
                    { key: 'source_type', label: 'المصدر', render: (e: any) => sourceLabel[e.source_type] || e.source_type },
                    { key: 'description', label: 'الوصف', hideOnMobile: true, render: (e: any) => e.description || <span style={{ color: 'var(--text-muted)' }}>—</span> },
                  ]}
                  data={ledger}
                  loading={loading}
                  emptyTitle="لا توجد حركات"
                  page={page}
                  totalPages={totalPages}
                  totalCount={totalCount}
                  onPageChange={(p) => loadLedger(selectedId, p)}
                />
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
        .ledger-layout {
          display: grid;
          grid-template-columns: 300px 1fr;
          gap: var(--space-4);
          min-height: 500px;
        }
        .ledger-entity-list { overflow: hidden; display: flex; flex-direction: column; }
        .ledger-search-box { padding: var(--space-3); border-bottom: 1px solid var(--border-primary); }
        .ledger-entity-scroll { flex: 1; overflow-y: auto; max-height: 550px; }
        .ledger-entity-item {
          padding: var(--space-3) var(--space-4);
          border-bottom: 1px solid var(--border-primary);
          cursor: pointer;
          transition: background var(--transition-fast);
        }
        .ledger-entity-item:hover { background: var(--bg-hover); }
        .ledger-entity-item.active { background: var(--color-primary-light); border-right: 3px solid var(--color-primary); }
        .ledger-empty-list { padding: var(--space-8); text-align: center; color: var(--text-muted); }
        .ledger-placeholder {
          display: flex; flex-direction: column; align-items: center; justify-content: center;
          min-height: 400px; gap: var(--space-3); color: var(--text-muted); text-align: center;
        }
        .ledger-content { min-width: 0; }
        @media (max-width: 768px) {
          .ledger-layout { grid-template-columns: 1fr; }
          .ledger-entity-scroll { max-height: 250px; }
        }
      `}</style>
    </div>
  )
}
