import type { ReactNode } from 'react'
import { Building2, Landmark, MoreHorizontal, Wallet } from 'lucide-react'
import Card from '@/components/patterns/Card'
import KeyValueList, { type KeyValueItem } from '@/components/patterns/KeyValueList'
import MetricGrid from '@/components/patterns/MetricGrid'
import StatCard from '@/components/patterns/StatCard'
import StatusBadge, { type SemanticTone } from '@/components/patterns/StatusBadge'
import { resolveActionSet, type AppAction } from '@/components/patterns/ActionRegistry'
import Badge from '@/components/ui/Badge'
import Button, { type ButtonProps } from '@/components/ui/Button'

export type VaultKind = 'cash' | 'bank' | 'mobile_wallet'

export interface VaultSummaryMetrics {
  totalBalance: ReactNode
  totalBalanceTone?: SemanticTone
  activeCount: ReactNode
  activeCountTone?: SemanticTone
  totalCount: ReactNode
}

export interface VaultCardSummary {
  name: ReactNode
  kind: VaultKind
  typeLabel: ReactNode
  balance: ReactNode
  balanceTone?: SemanticTone
  branch?: ReactNode
  responsible?: ReactNode
  statusLabel: ReactNode
  statusTone: SemanticTone
}

export interface VaultCardProps {
  summary: VaultCardSummary
  mode: 'mobile' | 'tablet'
  actions: AppAction[]
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

function actionVariant(action: AppAction): NonNullable<ButtonProps['variant']> {
  if (action.tone) return action.tone
  return action.importance === 'primary' ? 'primary' : 'secondary'
}

function VaultAction({ action }: { action: AppAction }) {
  return (
    <Button
      type="button"
      variant={actionVariant(action)}
      size="sm"
      touchTarget
      icon={action.icon}
      onClick={action.onSelect}
      disabled={action.disabled}
      loading={action.loading}
      aria-label={action.ariaLabel ?? action.label}
      data-action-id={action.id}
    >
      {action.label}
    </Button>
  )
}

/**
 * VaultSummary — Finance-domain projection over shared V2 summary primitives.
 * Values and semantic tone decisions remain page-owned; this component owns hierarchy only.
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
        tone={metrics.activeCountTone}
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
 * The caller owns action eligibility and ordering through canonical AppAction declarations.
 * The shared registry owns device-aware visible/overflow placement. This component never
 * decides whether opening balance, deposit, withdrawal, statement or edit is allowed.
 */
export function VaultCard({ summary, mode, actions }: VaultCardProps) {
  const metadata: KeyValueItem[] = []
  const resolvedActions = resolveActionSet(actions, mode)

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
      <div className="ds-vault-card__identity">
        <div className="ds-vault-card__icon" aria-hidden="true">
          {vaultIcon(summary.kind)}
        </div>

        <div className="ds-vault-card__main">
          <div className="ds-vault-card__heading-row">
            <div className="ds-vault-card__heading">
              <div className="ds-vault-card__name">{summary.name}</div>
              <div className="ds-vault-card__badges">
                <Badge variant="neutral">{summary.typeLabel}</Badge>
                <StatusBadge label={summary.statusLabel} tone={summary.statusTone} />
              </div>
            </div>

            <div className="ds-vault-card__balance-wrap">
              <div
                data-vault-balance
                className="ds-vault-card__balance"
                style={{ color: toneColor(summary.balanceTone) }}
              >
                {summary.balance}
              </div>
            </div>
          </div>
        </div>
      </div>

      {metadata.length > 0 && (
        <div className="ds-vault-card__metadata">
          <KeyValueList
            items={metadata}
            columns={mode === 'tablet' ? 2 : 1}
            compact
          />
        </div>
      )}

      {(resolvedActions.visible.length > 0 || resolvedActions.overflow.length > 0) && (
        <div className="ds-action-set" role="group" aria-label="إجراءات الخزنة" data-device={mode}>
          {resolvedActions.visible.length > 0 && (
            <div className="ds-action-set__visible">
              {resolvedActions.visible.map(action => (
                <VaultAction key={action.id} action={action} />
              ))}
            </div>
          )}

          {resolvedActions.overflow.length > 0 && (
            <details className="ds-action-set__overflow">
              <summary className="ds-action-set__overflow-trigger" aria-label="المزيد من إجراءات الخزنة">
                <MoreHorizontal size={16} aria-hidden="true" />
                <span>المزيد</span>
              </summary>
              <div className="ds-action-set__overflow-actions">
                {resolvedActions.overflow.map(action => (
                  <VaultAction key={action.id} action={action} />
                ))}
              </div>
            </details>
          )}
        </div>
      )}
    </Card>
  )
}
