import type { ReactNode } from 'react'
import { ChevronLeft, ChevronRight, Save } from 'lucide-react'
import FormActions from '@/components/patterns/FormActions'
import FormGrid, { type FormGridColumns } from '@/components/patterns/FormGrid'
import FormSection, { type FormSectionProps } from '@/components/patterns/FormSection'
import Button from '@/components/ui/Button'
import Stepper, { type StepperStep } from '@/components/ui/Stepper'
import './sales-order-form-v2.css'

export interface SalesOrderFormStep {
  id: string
  label: string
  icon: ReactNode
}

export interface SalesOrderStepNavigatorProps {
  steps: SalesOrderFormStep[]
  activeIndex: number
  canActivate: (index: number) => boolean
  onChange: (index: number) => void
}

/**
 * Thin Sales adapter over the shared Stepper.
 * The page owns all reachability/validation truth through `canActivate`.
 */
export function SalesOrderStepNavigator({
  steps,
  activeIndex,
  canActivate,
  onChange,
}: SalesOrderStepNavigatorProps) {
  const projectedSteps: StepperStep[] = steps.map((step, index) => ({
    label: step.label,
    icon: step.icon,
    disabled: !canActivate(index),
  }))

  return (
    <Stepper
      steps={projectedSteps}
      currentStep={activeIndex}
      showNumbers={false}
      onStepClick={onChange}
      ariaLabel="مراحل أمر البيع"
      mobileLayout="wrap"
      className="sales-order-stepper-v2"
    />
  )
}

export interface SalesOrderFormSectionProps
  extends Omit<FormSectionProps, 'children'> {
  columns?: FormGridColumns
  compact?: boolean
  children: ReactNode
}

/**
 * Sales Order section composition over the shared V2 form patterns.
 * It intentionally owns no sales-domain state, validation or calculations.
 */
export function SalesOrderFormSection({
  columns = 2,
  compact = false,
  children,
  ...sectionProps
}: SalesOrderFormSectionProps) {
  return (
    <FormSection {...sectionProps}>
      <FormGrid columns={columns} compact={compact}>
        {children}
      </FormGrid>
    </FormSection>
  )
}

export interface SalesOrderFormActionsProps {
  activeIndex: number
  lastIndex: number
  saving: boolean
  submitDisabled: boolean
  isEdit: boolean
  onCancel: () => void
  onPrevious: () => void
  onNext: () => void
  onSubmit: () => void
}

/**
 * Shared action hierarchy for the stepped Sales Order form.
 * The page remains authoritative for whether progression/submission is valid.
 */
export function SalesOrderFormActions({
  activeIndex,
  lastIndex,
  saving,
  submitDisabled,
  isEdit,
  onCancel,
  onPrevious,
  onNext,
  onSubmit,
}: SalesOrderFormActionsProps) {
  const isFirst = activeIndex === 0
  const isLast = activeIndex === lastIndex

  return (
    <FormActions align="between" stickyOnMobile className="sales-order-form-actions-v2">
      <Button
        type="button"
        variant="ghost"
        touchTarget
        onClick={isFirst ? onCancel : onPrevious}
      >
        {isFirst ? 'إلغاء' : (
          <>
            <ChevronRight
              size={16}
              aria-hidden="true"
              className="sales-order-form-actions-v2__previous-icon"
            />
            السابق
          </>
        )}
      </Button>

      {isLast ? (
        <Button
          type="button"
          icon={<Save size={15} aria-hidden="true" />}
          loading={saving}
          disabled={submitDisabled}
          touchTarget
          onClick={onSubmit}
        >
          {isEdit ? 'حفظ التعديلات' : 'حفظ المسودة'}
        </Button>
      ) : (
        <Button type="button" touchTarget onClick={onNext}>
          التالي
          <ChevronLeft
            size={16}
            aria-hidden="true"
            className="sales-order-form-actions-v2__next-icon"
          />
        </Button>
      )}
    </FormActions>
  )
}
