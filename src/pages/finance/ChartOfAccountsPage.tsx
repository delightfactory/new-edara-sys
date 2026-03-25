import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { GitBranchPlus, ChevronDown, ChevronLeft } from 'lucide-react'
import { getChartOfAccounts, buildAccountTree } from '@/lib/services/finance'
import type { ChartOfAccount } from '@/lib/types/master-data'
import PageHeader from '@/components/shared/PageHeader'
import Badge from '@/components/ui/Badge'

const typeLabel: Record<string, string> = {
  asset: 'أصول', liability: 'التزامات', equity: 'حقوق ملكية', revenue: 'إيرادات', expense: 'مصروفات',
}
const typeBadge: Record<string, 'primary' | 'danger' | 'success' | 'info' | 'warning'> = {
  asset: 'primary', liability: 'danger', equity: 'info', revenue: 'success', expense: 'warning',
}

function AccountNode({ account, depth = 0 }: { account: ChartOfAccount; depth?: number }) {
  const [expanded, setExpanded] = useState(depth < 2)
  const hasChildren = account.children && account.children.length > 0

  return (
    <div>
      <div
        className="tree-item"
        style={{ paddingRight: `calc(var(--space-4) + ${depth * 24}px)` }}
        onClick={() => hasChildren && setExpanded(!expanded)}
        data-clickable={hasChildren ? 'true' : undefined}
      >
        <span className="tree-chevron">
          {hasChildren ? (expanded ? <ChevronDown size={14} /> : <ChevronLeft size={14} />) : null}
        </span>
        <span className="tree-code">{account.code}</span>
        <span className="tree-name" style={{ fontWeight: hasChildren ? 600 : 400 }}>{account.name}</span>
        {account.name_en && <span className="tree-name-en">{account.name_en}</span>}
        <Badge variant={typeBadge[account.type] || 'neutral'}>{typeLabel[account.type] || account.type}</Badge>
      </div>
      {hasChildren && expanded && (
        <div className="tree-children">
          {account.children!.map(child => (
            <AccountNode key={child.id} account={child} depth={depth + 1} />
          ))}
        </div>
      )}
    </div>
  )
}

export default function ChartOfAccountsPage() {
  const [accounts, setAccounts] = useState<ChartOfAccount[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const load = async () => {
      try {
        const flat = await getChartOfAccounts()
        setAccounts(buildAccountTree(flat))
      } catch { toast.error('فشل تحميل شجرة الحسابات') }
      finally { setLoading(false) }
    }
    load()
  }, [])

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="شجرة الحسابات"
        subtitle="الدليل المحاسبي لكل حسابات النظام"
      />

      <div className="edara-card" style={{ overflow: 'hidden' }}>
        {loading ? (
          <div style={{ padding: 'var(--space-6)' }}>
            {[1,2,3,4,5].map(i => <div key={i} className="skeleton skeleton-row" />)}
          </div>
        ) : accounts.length === 0 ? (
          <div className="empty-state">
            <GitBranchPlus size={48} />
            <p className="empty-state-title">لا توجد حسابات</p>
          </div>
        ) : (
          accounts.map(a => <AccountNode key={a.id} account={a} />)
        )}
      </div>

      <style>{`
        .tree-item {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          border-bottom: 1px solid var(--border-primary);
          transition: background var(--transition-fast);
          font-size: var(--text-sm);
        }
        .tree-item[data-clickable] { cursor: pointer; }
        .tree-item:hover { background: var(--bg-hover); }
        .tree-chevron {
          width: 16px;
          flex-shrink: 0;
          color: var(--text-muted);
          display: flex;
          align-items: center;
        }
        .tree-code {
          font-family: monospace;
          font-size: var(--text-sm);
          color: var(--text-muted);
          min-width: 60px;
          flex-shrink: 0;
        }
        .tree-name {
          flex: 1;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .tree-name-en {
          font-size: var(--text-xs);
          color: var(--text-muted);
          direction: ltr;
          max-width: 200px;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .tree-children {
          animation: fade-in 0.2s ease;
        }
        @keyframes fade-in {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        @media (max-width: 768px) {
          .tree-name-en { display: none; }
          .tree-item { padding: var(--space-2) var(--space-3); gap: var(--space-2); }
        }
      `}</style>
    </div>
  )
}
