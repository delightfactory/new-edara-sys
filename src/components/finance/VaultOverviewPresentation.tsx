import type { ReactNode } from 'react'
import {
  ArrowDownToLine,
  ArrowUpFromLine,
  Building2,
  Edit,
  Eye,
  Landmark,
  Layers,
  Wallet,
} from 'lucide-react'
import Card from '@/components/patterns/Card'
import KeyValueList, { type KeyValueItem } from '@/components/patterns/KeyValueList'
import MetricGrid from '@/components/patterns/MetricGrid'
import StatCard from '@/components/patterns/StatCard'
import StatusBadge, { type SemanticTone } from '@/components/patterns/StatusBadge'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'

export type VaultKind = 'cash' | 'bank' | 'mobile_wallet'
export type VaultTypeBadgeVariant = 'success' | 'info' | 'primary' | 'neutral'

export interface VaultSummaryMetrics {
  totalBalance: ReactNode
  totalBalanceTone?: SemanticTone
  activeCount: ReactNode
  totalCount: ReactNode
}

export interface VaultCardSummary {
  name: ReactNode
  kind: VaultKind
  typeLabel: ReactNode
  typeVariant?: VaultTypeBadgeVariant
  balance: ReactNode
  balanceTone?: SemanticTone
  branch?: ReactNode
  responsible?: ReactNode
  statusLabel: ReactNode
  statusTone: SemanticTone
}

export interface VaultCardActions {
  onStatement: () => void
  onOpening?: () => void
  onDeposit?: () => void
  onWithdrawal?: () => void
  onEdit?: () => void
}

export interface VaultCardProps {
  summary: VaultCardSummary
  mode: 'mobile' | 'tablet'
  actions: VaultCardActions
}

function toneColor(tone: SemanticTone | undefined) {
  if (tone === 'danger') return 'var(--ds-status-danger-fg)'
  if (tone === 'warning') return 'var(--ds-status-warning-fg)'
  if (tone === 'success') return 'var(--ds-status-success-fg)'
  if (tone === 'info') return 'var(--ds-status-info-fg)'
  return 'var(--ds-text-primary)'
}

function vaultIcon(kind: VaultKind) {
  if (kind === 'cash') return <Wallet size={18} />
  if (kind === 'bank') return <Building2 size={18} />
  return <Landmark size={18} />
}

/**
 * VaultSummary — Finance-domain projection over shared V2 summary primitives.
 * Values and tone decisions remain page-owned; this component owns hierarchy only.
 */
export function VaultSummary({ metrics }: { metrics: VaultSummaryMetrics }) {
  return (
    <MetricGrid columns={3} aria-label="ملخص الخزائن">
      <StatCard
        label="إجمالي الرصيد"
        value={metrics.totalBalance}
        tone={metrics.totalBalanceTone}
        icon={<Landmark size={18} />}
      />
      <StatCard
        label="الخزائن النشطة"
        value={metrics.activeCount}
        tone="success"
        icon={<Wallet size={18} />}
      />
      <StatCard
        label="إجمالي الخزائن"
        value={metrics.totalCount}
        icon={<Building2 size={18} />}
      />
    </MetricGrid>
  )
}

/**
 * VaultCard — Finance-domain adapter over shared V2 card/detail/action grammar.
 *
 * The caller decides every financial/business predicate by choosing which action
 * callbacks exist. This component never decides whether opening balance,
 * deposit, withdrawal or edit is allowed.
 */
export function VaultCard({ summary, mode, actions }: VaultCardProps) {
  const metadata: KeyValueItem[] = []

  if (summary.branch != null) {
    metadata.push({ key: 'branch', label: 'الفرع', value: summary.branch })
  }
  if (summary.responsible != null) {
    metadata.push({ key: 'responsible', label: 'المسؤول', value: summary.responsible })
  }

  return (
    <Card
      surface="default"
      padding={mode === 'tablet' ? 'md' : 'sm'}
      data-vault-card
      data-mode={mode}
    >
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 'var(--space-3)' }}>
        <div
          aria-hidden="true"
          style={{
            width: 40,
            height: 40,
            borderRadius: 'var(--radius-lg)',
            background: 'var(--bg-accent)',
            color: 'var(--color-primary)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
          }}
        >
          {vaultIcon(summary.kind)}
        </div>

        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', gap: 'var(--space-3)', alignItems: 'flex-start', flexWrap: 'wrap' }}>
            <div style={{ minWidth: 0 }}>
              <div style={{ fontWeight: 700, overflowWrap: 'anywhere' }}>{summary.name}</div>
              <div style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap', marginBlockStart: 'var(--space-1)' }}>
                <Badge variant={summary.typeVariant ?? 'neutral'}>{summary.typeLabel}</Badge>
                <StatusBadge label={summary.statusLabel} tone={summary.statusTone} />
              </div>
            </div>

            <div style={{ textAlign: 'end', minWidth: 0 }}>
              <div
                data-vault-balance
                style={{
                  color: toneColor(summary.balanceTone),
                  fontWeight: 800,
                  fontSize: mode === 'tablet' ? 'var(--ds-type-section-title-size)' : 'var(--ds-type-body-size)',
                  fontVariantNumeric: 'tabular-nums',
                  overflowWrap: 'anywhere',
                }}
              >
                {summary.balance}
              </div>
            </div>
          </div>
        </div>
      </div>

      {metadata.length > 0 && (
        <div style={{ marginBlockStart: 'var(--space-3)' }}>
          <KeyValueList
            items={metadata}
            columns={mode === 'tablet' ? 2 : 1}
            compact
          />
        </div>
      )}

      <div
        role="group"
        aria-label="إجراءات الخزنة"
        style={{
          display: 'flex',
          gap: 'var(--space-2)',
          flexWrap: 'wrap',
          marginBlockStart: 'var(--space-3)',
          paddingBlockStart: 'var(--space-3)',
          borderBlockStart: '1px solid var(--ds-border-subtle)',
        }}
      >
        <Button
          variant="ghost"
          size="sm"
          touchTarget
          icon={<Eye size={14} />}
          onClick={actions.onStatement}
        >
          كشف حساب
        </Button>

        {actions.onOpening && (
          <Button
            variant="secondary"
            size="sm"
            touchTarget
            icon={<Layers size={14} />}
            onClick={actions.onOpening}
          >
            افتتاحي
          </Button>
        )}

        {actions.onDeposit && (
          <Button
            variant="success"
            size="sm"
            touchTarget
            icon={<ArrowDownToLine size={14} />}
            onClick={actions.onDeposit}
          >
            إيداع
          </Button>
        )}

        {actions.onWithdrawal && (
          <Button
            variant="danger"
            size="sm"
            touchTarget
            icon={<ArrowUpFromLine size={14} />}
            onClick={actions.onWithdrawal}
          >
            سحب
          </Button>
        )}

        {actions.onEdit && (
          <Button
            variant="ghost"
            size="sm"
            touchTarget
            icon={<Edit size={14} />}
            onClick={actions.onEdit}
          >
            تعديل
          </Button>
        )}
      </div>
    </Card>
  )
}
