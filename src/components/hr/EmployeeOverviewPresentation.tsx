import type { ReactNode } from 'react'
import { Briefcase, Clock, MoreHorizontal, UserRound, Users } from 'lucide-react'
import Card from '@/components/patterns/Card'
import KeyValueList, { type KeyValueItem } from '@/components/patterns/KeyValueList'
import MetricGrid from '@/components/patterns/MetricGrid'
import StatCard from '@/components/patterns/StatCard'
import StatusBadge, { type SemanticTone } from '@/components/patterns/StatusBadge'
import { resolveActionSet, type AppAction } from '@/components/patterns/ActionRegistry'
import Badge from '@/components/ui/Badge'
import Button, { type ButtonProps } from '@/components/ui/Button'
import '@/styles/hr-admin-v2.css'

export interface EmployeeSummaryMetrics {
  active: ReactNode
  onLeave: ReactNode
  field: ReactNode
  total: ReactNode
}

export interface EmployeeCardSummary {
  name: string
  employeeNumber: ReactNode
  department: ReactNode
  position?: ReactNode
  phone?: ReactNode
  salary?: ReactNode
  fieldLabel: ReactNode
  statusLabel: ReactNode
  statusTone: SemanticTone
}

export interface EmployeeCardProps {
  summary: EmployeeCardSummary
  mode: 'mobile' | 'tablet'
  actions: AppAction[]
  onOpen: () => void
}

function actionVariant(action: AppAction): NonNullable<ButtonProps['variant']> {
  if (action.tone) return action.tone
  return action.importance === 'primary' ? 'primary' : 'secondary'
}

function EmployeeAction({ action }: { action: AppAction }) {
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

export function EmployeeSummary({ metrics }: { metrics: EmployeeSummaryMetrics }) {
  return (
    <MetricGrid columns={4} aria-label="ملخص الموظفين">
      <StatCard label="نشط" value={metrics.active} tone="success" icon={<Users size={18} />} />
      <StatCard label="في إجازة" value={metrics.onLeave} tone="info" icon={<Clock size={18} />} />
      <StatCard label="ميداني" value={metrics.field} icon={<Briefcase size={18} />} />
      <StatCard label="الإجمالي" value={metrics.total} icon={<UserRound size={18} />} />
    </MetricGrid>
  )
}

/**
 * EmployeeCard — HR-domain projection over shared V2 card/status/action grammar.
 * Permission and action eligibility remain caller-owned; this component owns
 * only hierarchy and device-aware placement.
 */
export function EmployeeCard({ summary, mode, actions, onOpen }: EmployeeCardProps) {
  const resolvedActions = resolveActionSet(actions, mode)
  const metadata: KeyValueItem[] = [
    { key: 'department', label: 'القسم', value: summary.department },
  ]

  if (summary.position != null) {
    metadata.push({ key: 'position', label: 'المسمى', value: summary.position })
  }
  if (summary.phone != null) {
    metadata.push({ key: 'phone', label: 'الهاتف', value: summary.phone })
  }
  if (summary.salary != null) {
    metadata.push({ key: 'salary', label: 'الراتب الأساسي', value: summary.salary, emphasis: 'strong' })
  }

  return (
    <Card
      surface="default"
      padding={mode === 'tablet' ? 'md' : 'sm'}
      className="ds-employee-card"
      data-employee-card
      data-mode={mode}
    >
      <div className="ds-employee-card__header">
        <button
          type="button"
          className="ds-employee-card__identity"
          onClick={onOpen}
          aria-label={`فتح ملف ${summary.name}`}
        >
          <span className="ds-employee-card__avatar" aria-hidden="true">
            <UserRound size={18} />
          </span>
          <span className="ds-employee-card__copy">
            <span className="ds-employee-card__name">{summary.name}</span>
            <span className="ds-employee-card__number" dir="ltr">{summary.employeeNumber}</span>
          </span>
        </button>

        <div className="ds-employee-card__badges">
          <StatusBadge label={summary.statusLabel} tone={summary.statusTone} />
          <Badge variant="neutral">{summary.fieldLabel}</Badge>
        </div>
      </div>

      <div className="ds-employee-card__metadata">
        <KeyValueList items={metadata} columns={mode === 'tablet' ? 2 : 1} compact />
      </div>

      {(resolvedActions.visible.length > 0 || resolvedActions.overflow.length > 0) && (
        <div className="ds-action-set" role="group" aria-label="إجراءات الموظف" data-device={mode}>
          {resolvedActions.visible.length > 0 && (
            <div className="ds-action-set__visible">
              {resolvedActions.visible.map(action => (
                <EmployeeAction key={action.id} action={action} />
              ))}
            </div>
          )}

          {resolvedActions.overflow.length > 0 && (
            <details className="ds-action-set__overflow">
              <summary className="ds-action-set__overflow-trigger" aria-label="المزيد من إجراءات الموظف">
                <MoreHorizontal size={16} aria-hidden="true" />
                <span>المزيد</span>
              </summary>
              <div className="ds-action-set__overflow-actions">
                {resolvedActions.overflow.map(action => (
                  <EmployeeAction key={action.id} action={action} />
                ))}
              </div>
            </details>
          )}
        </div>
      )}
    </Card>
  )
}
