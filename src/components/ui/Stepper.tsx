import { type ReactNode } from 'react'
import { Check } from 'lucide-react'

interface Step {
  label: string
  description?: string
}

interface StepperProps {
  steps: Step[] | string[]
  currentStep: number  // 0-indexed
  /** Show step numbers inside the circles */
  showNumbers?: boolean
  className?: string
}

/**
 * Stepper — Visual step indicator for multi-step forms / wizards.
 *
 * Usage:
 * ```tsx
 * <Stepper
 *   steps={['بيانات العميل', 'المنتجات', 'الدفع', 'المراجعة']}
 *   currentStep={1}
 * />
 * ```
 *
 * Or with descriptions:
 * ```tsx
 * <Stepper
 *   steps={[
 *     { label: 'العميل', description: 'بيانات العميل والفرع' },
 *     { label: 'المنتجات', description: 'اختر المنتجات والكميات' },
 *     { label: 'المراجعة', description: 'راجع الطلب قبل الإرسال' },
 *   ]}
 *   currentStep={0}
 * />
 * ```
 */
export default function Stepper({ steps, currentStep, showNumbers = true, className = '' }: StepperProps) {
  const normalized: Step[] = steps.map(s =>
    typeof s === 'string' ? { label: s } : s
  )

  return (
    <nav
      className={`stepper ${className}`}
      aria-label="خطوات النموذج"
    >
      {normalized.map((step, index) => {
        const isDone = index < currentStep
        const isActive = index === currentStep
        const state = isDone ? 'done' : isActive ? 'active' : 'pending'

        return (
          <div key={index} className={`stepper-step stepper-step--${state}`}>
            {/* Connector line before (not for first step) */}
            {index > 0 && (
              <div
                className={`stepper-connector ${isDone ? 'stepper-connector--done' : ''}`}
                aria-hidden="true"
              />
            )}

            {/* Circle indicator */}
            <div
              className="stepper-circle"
              aria-current={isActive ? 'step' : undefined}
              aria-label={`${isActive ? 'الخطوة الحالية: ' : isDone ? 'مكتملة: ' : 'قادمة: '}${step.label}`}
            >
              {isDone ? (
                <Check size={14} strokeWidth={3} />
              ) : showNumbers ? (
                <span className="stepper-number">{index + 1}</span>
              ) : null}
            </div>

            {/* Labels */}
            <div className="stepper-labels">
              <span className="stepper-label">{step.label}</span>
              {step.description && (
                <span className="stepper-desc">{step.description}</span>
              )}
            </div>
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

        /* ── Single Step ── */
        .stepper-step {
          display: flex;
          flex-direction: column;
          align-items: center;
          flex: 1;
          min-width: 0;
          position: relative;
        }

        /* ── Connector line ── */
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

        /* ── Circle ── */
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

        .stepper-number {
          line-height: 1;
        }

        /* ── Labels ── */
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

        .stepper-step--done .stepper-label {
          color: var(--text-secondary);
        }

        .stepper-desc {
          font-size: 0.65rem;
          color: var(--text-muted);
          margin-top: 2px;
          display: none;
        }

        /* Show description on desktop where there's space */
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
