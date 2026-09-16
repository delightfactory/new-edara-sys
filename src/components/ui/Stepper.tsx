import { type ReactNode } from 'react'
import { Check } from 'lucide-react'

export interface StepperStep {
  label: string
  description?: string
  icon?: ReactNode
  /** Page/domain-owned reachability projected into the shared stepper. */
  disabled?: boolean
}

export interface StepperProps {
  steps: StepperStep[] | string[]
  currentStep: number // 0-indexed
  /** Show step numbers inside the circles when no step icon is supplied. */
  showNumbers?: boolean
  className?: string
  /** Optional interaction callback. When omitted, the stepper remains a read-only indicator. */
  onStepClick?: (index: number) => void
  /** Accessible navigation label for the specific workflow. */
  ariaLabel?: string
  /** Preserve the historical scroll treatment or opt into a generic two-column mobile wrap. */
  mobileLayout?: 'scroll' | 'wrap'
}

/**
 * Stepper — shared visual/interactive step indicator for multi-step forms and wizards.
 *
 * Domain/page code remains authoritative for reachability. Project that truth through
 * `disabled` on each step; the Stepper only owns presentation and interaction semantics.
 */
export default function Stepper({
  steps,
  currentStep,
  showNumbers = true,
  className = '',
  onStepClick,
  ariaLabel = 'خطوات النموذج',
  mobileLayout = 'scroll',
}: StepperProps) {
  const normalized: StepperStep[] = steps.map(step =>
    typeof step === 'string' ? { label: step } : step,
  )

  return (
    <nav
      className={`stepper stepper--mobile-${mobileLayout} ${className}`.trim()}
      aria-label={ariaLabel}
    >
      {normalized.map((step, index) => {
        const isDone = index < currentStep
        const isActive = index === currentStep
        const state = isDone ? 'done' : isActive ? 'active' : 'pending'
        const stateLabel = isActive ? 'الخطوة الحالية: ' : isDone ? 'مكتملة: ' : 'قادمة: '
        const accessibleLabel = `${stateLabel}${step.label}`

        const indicator = (
          <div
            className="stepper-circle"
            aria-current={!onStepClick && isActive ? 'step' : undefined}
            aria-label={!onStepClick ? accessibleLabel : undefined}
            aria-hidden={onStepClick ? 'true' : undefined}
          >
            {isDone ? (
              <Check size={14} strokeWidth={3} />
            ) : step.icon ? (
              step.icon
            ) : showNumbers ? (
              <span className="stepper-number">{index + 1}</span>
            ) : null}
          </div>
        )

        const labels = (
          <div className="stepper-labels" aria-hidden={onStepClick ? 'true' : undefined}>
            <span className="stepper-label">{step.label}</span>
            {step.description && (
              <span className="stepper-desc">{step.description}</span>
            )}
          </div>
        )

        return (
          <div key={`${step.label}-${index}`} className={`stepper-step stepper-step--${state}`}>
            {index > 0 && (
              <div
                className={`stepper-connector ${isDone ? 'stepper-connector--done' : ''}`}
                aria-hidden="true"
              />
            )}

            {onStepClick ? (
              <button
                type="button"
                className="stepper-trigger"
                aria-current={isActive ? 'step' : undefined}
                aria-label={accessibleLabel}
                disabled={step.disabled}
                onClick={() => onStepClick(index)}
              >
                {indicator}
                {labels}
              </button>
            ) : (
              <>
                {indicator}
                {labels}
              </>
            )}
          </div>
        )
      })}

      <style>{`
        .stepper {
          display: flex;
          align-items: flex-start;
          gap: 0;
          width: 100%;
          padding: var(--space-2) 0 var(--space-4);
          overflow-x: auto;
          scrollbar-width: none;
        }
        .stepper::-webkit-scrollbar { display: none; }

        .stepper-step {
          display: flex;
          flex-direction: column;
          align-items: center;
          flex: 1;
          min-width: 0;
          position: relative;
        }

        .stepper-trigger {
          display: flex;
          flex-direction: column;
          align-items: center;
          width: 100%;
          min-width: 0;
          margin: 0;
          padding: 0;
          border: 0;
          border-radius: var(--radius-md);
          background: transparent;
          color: inherit;
          font: inherit;
          cursor: pointer;
        }
        .stepper-trigger:focus-visible {
          outline: 2px solid var(--color-primary);
          outline-offset: 4px;
        }
        .stepper-trigger:disabled {
          cursor: not-allowed;
          opacity: 0.62;
        }

        .stepper-connector {
          position: absolute;
          top: 16px;
          inset-inline-end: 50%;
          width: 100%;
          height: 2px;
          background: var(--border-primary);
          z-index: 0;
          transition: background var(--transition-slow);
        }
        .stepper-connector--done {
          background: var(--color-primary);
        }

        .stepper-circle {
          width: 32px;
          height: 32px;
          border-radius: var(--radius-full);
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
          z-index: 1;
          font-size: var(--text-xs);
          font-weight: 700;
          transition: background var(--transition-base),
                      border-color var(--transition-base),
                      color var(--transition-base),
                      box-shadow var(--transition-base);
          border: 2px solid var(--border-primary);
          background: var(--bg-surface);
          color: var(--text-muted);
          position: relative;
        }

        .stepper-step--done .stepper-circle {
          background: var(--color-primary);
          border-color: var(--color-primary);
          color: white;
        }

        .stepper-step--active .stepper-circle {
          background: var(--bg-surface);
          border-color: var(--color-primary);
          color: var(--color-primary);
          box-shadow: 0 0 0 4px var(--color-primary-light);
        }

        .stepper-number { line-height: 1; }

        .stepper-labels {
          display: flex;
          flex-direction: column;
          align-items: center;
          margin-top: var(--space-2);
          text-align: center;
          padding: 0 var(--space-1);
        }

        .stepper-label {
          font-size: var(--text-xs);
          font-weight: 600;
          color: var(--text-muted);
          white-space: nowrap;
          transition: color var(--transition-base);
        }

        .stepper-step--active .stepper-label {
          color: var(--color-primary);
          font-weight: 700;
        }

        .stepper-step--done .stepper-label { color: var(--text-secondary); }

        .stepper-desc {
          font-size: 0.65rem;
          color: var(--text-muted);
          margin-top: 2px;
          display: none;
        }

        @media (max-width: 639px) {
          .stepper--mobile-wrap {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: var(--space-3);
            overflow-x: visible;
            padding-block-end: var(--space-3);
          }
          .stepper--mobile-wrap .stepper-step,
          .stepper--mobile-wrap .stepper-trigger {
            width: 100%;
          }
          .stepper--mobile-wrap .stepper-connector { display: none; }
          .stepper--mobile-wrap .stepper-label { white-space: normal; }
        }

        @media (min-width: 640px) {
          .stepper-circle { width: 36px; height: 36px; }
          .stepper-connector { top: 18px; }
          .stepper-label { font-size: var(--text-sm); }
          .stepper-desc { display: block; }
        }
      `}</style>
    </nav>
  )
}
