import type { CSSProperties, ReactNode } from 'react'
import './OperationalTaskControls.css'

export type ProcessStepState = 'completed' | 'current' | 'pending'

export interface ProcessProgressStep {
  id: string
  label: ReactNode
  state: ProcessStepState
  meta?: ReactNode
}

export interface ProcessProgressProps {
  steps: ProcessProgressStep[]
  ariaLabel?: string
  className?: string
}

const stateLabels: Record<ProcessStepState, string> = {
  completed: 'مكتملة',
  current: 'الخطوة الحالية',
  pending: 'قادمة',
}

/**
 * ProcessProgress — presentation-only progress grammar for short operational tasks.
 *
 * Callers own process truth and provide the state of every step. This component
 * only renders accessible current/completed/pending semantics and never infers
 * workflow transitions.
 */
export default function ProcessProgress({
  steps,
  ariaLabel = 'تقدم العملية',
  className,
}: ProcessProgressProps) {
  const style = {
    '--ds-process-step-count': Math.max(steps.length, 1),
  } as CSSProperties

  return (
    <div
      className={['ds-process-progress', className].filter(Boolean).join(' ')}
      data-process-progress
      style={style}
    >
      <ol className="ds-process-progress__list" aria-label={ariaLabel}>
        {steps.map((step, index) => (
          <li
            key={step.id}
            className="ds-process-progress__step"
            data-state={step.state}
            aria-current={step.state === 'current' ? 'step' : undefined}
          >
            <span className="ds-process-progress__marker" aria-hidden="true">
              {step.state === 'completed' ? '✓' : index + 1}
            </span>
            <span className="ds-process-progress__content">
              <span className="ds-process-progress__label">{step.label}</span>
              <span className="ds-process-progress__state">{stateLabels[step.state]}</span>
              {step.meta != null ? (
                <span className="ds-process-progress__meta">{step.meta}</span>
              ) : null}
            </span>
          </li>
        ))}
      </ol>
    </div>
  )
}
