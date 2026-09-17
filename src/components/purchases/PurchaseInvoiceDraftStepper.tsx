import { Building2, CheckCircle, DollarSign, Package } from 'lucide-react'
import Stepper, { type StepperStep } from '@/components/ui/Stepper'

export interface PurchaseInvoiceDraftStepperProps {
  currentStep: number
  canProceedFromBasics: boolean
  canProceedFromItems: boolean
  onStepChange: (step: number) => void
}

const STEP_DEFINITIONS = [
  { label: 'المورد واللوجستيات', icon: <Building2 size={14} /> },
  { label: 'المنتجات المستلمة', icon: <Package size={14} /> },
  { label: 'التكاليف والضرائب', icon: <DollarSign size={14} /> },
  { label: 'مراجعة وحفظ', icon: <CheckCircle size={14} /> },
] as const

function isStepReachable(
  index: number,
  currentStep: number,
  canProceedFromBasics: boolean,
  canProceedFromItems: boolean,
) {
  return (
    index < currentStep ||
    index === 0 ||
    (index === 1 && canProceedFromBasics) ||
    (index === 2 && canProceedFromBasics && canProceedFromItems)
  )
}

/**
 * Presentation adapter for the editable Purchase Invoice workflow.
 * PurchaseInvoiceForm remains authoritative for validation and progression truth;
 * this component only projects that truth into the shared V2 Stepper.
 */
export default function PurchaseInvoiceDraftStepper({
  currentStep,
  canProceedFromBasics,
  canProceedFromItems,
  onStepChange,
}: PurchaseInvoiceDraftStepperProps) {
  const steps: StepperStep[] = STEP_DEFINITIONS.map((stepDefinition, index) => ({
    ...stepDefinition,
    // Keep the active step operable for correct current-step semantics even when
    // legacy direct-jump rules would otherwise reject the same-index no-op.
    disabled:
      index !== currentStep &&
      !isStepReachable(index, currentStep, canProceedFromBasics, canProceedFromItems),
  }))

  return (
    <Stepper
      steps={steps}
      currentStep={currentStep}
      mobileLayout="wrap"
      ariaLabel="مراحل فاتورة المشتريات"
      onStepClick={index => {
        if (
          isStepReachable(
            index,
            currentStep,
            canProceedFromBasics,
            canProceedFromItems,
          )
        ) {
          onStepChange(index)
        }
      }}
    />
  )
}
