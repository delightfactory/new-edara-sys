import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./PurchaseInvoiceForm.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')
const shellStylesPath = fileURLToPath(new URL('../../styles/purchase-invoice-v2.css', import.meta.url))
const shellStyles = readFileSync(shellStylesPath, 'utf8')
const mainStylesPath = fileURLToPath(new URL('../../styles/main.css', import.meta.url))
const mainStyles = readFileSync(mainStylesPath, 'utf8')

describe('PurchaseInvoiceForm V2 shell contract', () => {
  it('wires the shared purchase stepper only into the editable new/draft wizard', () => {
    expect(source).toContain("from '@/components/purchases/PurchaseInvoiceDraftStepper'")
    expect(source).toContain('<PurchaseInvoiceDraftStepper')
    expect(source).toContain('currentStep={step}')
    expect(source).toContain('canProceedFromBasics={canProceedStep0}')
    expect(source).toContain('canProceedFromItems={canProceedStep1}')
    expect(source).toContain('onStepChange={setStep}')
    expect(source).toContain("mode === 'new' || (mode === 'draft' && !showReceivePanel)")
    expect(source).not.toContain('className="stepper-label"')
    expect(source).not.toContain('.stepper-label    { display: none; }')
  })

  it('uses shared form composition for basic invoice data with 3/2/1 responsive density', () => {
    expect(source).toContain("from '@/components/patterns/FormSection'")
    expect(source).toContain("from '@/components/patterns/FormGrid'")
    expect(source).toContain('<FormSection title="بيانات الفاتورة" icon={<FileText size={16} />}>')
    expect(source).toContain('<FormGrid columns={3}>')
    expect(source.match(/gridColumn: '1 \/ -1'/g)?.length ?? 0).toBeGreaterThanOrEqual(2)
    expect(source).toContain("disabled={readOnly || mode === 'bill' || (mode === 'draft' && showReceivePanel)}")
    expect(source).toContain("disabled={mode !== 'draft'}")
  })

  it('owns the migrated basic-section separation at the Purchase Invoice shell boundary', () => {
    expect(source).toContain('className="purch-action-bar"')
    expect(mainStyles).toContain("@import './purchase-invoice-v2.css';")
    expect(shellStyles).toContain('.page-container:has(> .purch-action-bar) > .ds-form-section {')
    expect(shellStyles).toContain('margin-block-end: var(--space-4);')
    expect(shellStyles).not.toMatch(/^\s*\.ds-form-section\s*\{/m)
  })

  it('keeps forward validation and save truth page-owned while using shared FormActions', () => {
    expect(source).toContain("from '@/components/patterns/FormActions'")
    expect(source).toContain('<FormActions align="between"')
    expect(source).toContain("if (step === 0 && !canProceedStep0) { toast.error('يرجى اختيار المورد والمخزن أولاً'); return }")
    expect(source).toContain("if (step === 1 && !canProceedStep1) { toast.error('يرجى إضافة منتج واحد على الأقل'); return }")
    expect(source).toContain('onClick={goNext}')
    expect(source).toContain("onClick={step === 0 ? () => navigate('/purchases/invoices') : () => setStep(s => s - 1)}")
    expect(source).toContain('disabled={saving || !supplierId || !warehouseId || validDraftLines.length === 0}')
    expect(source).toContain('onClick={handleSaveDraft}')
    expect(source).toContain('<ChevronRight size={16} aria-hidden="true" />')
    expect(source).toContain('<ChevronLeft size={16} aria-hidden="true" />')
  })

  it('maps Purchase Invoice workflow states into the shared semantic StatusBadge', () => {
    expect(source).toContain("from '@/components/patterns/StatusBadge'")
    expect(source).toContain("draft:     'neutral'")
    expect(source).toContain("received:  'info'")
    expect(source).toContain("billed:    'warning'")
    expect(source).toContain("paid:      'success'")
    expect(source).toContain("cancelled: 'danger'")
    expect(source).toContain('<StatusBadge label={STATUS_LABELS[invoice.status]} tone={STATUS_TONES[invoice.status]} />')
    expect(source).not.toContain("color: '#92400e'")
    expect(source).not.toContain("bg: '#fef3c7'")
  })

  it('preserves purchase/accounting service and workflow boundaries', () => {
    expect(source).toContain('await createPurchaseInvoice(header, items)')
    expect(source).toContain('await updatePurchaseInvoice(id!, header, items)')
    expect(source).toContain('receiveLines.map(l => updateItemReceivedQty(l.item_id, l.received_quantity))')
    expect(source).toContain('await updateLandedCosts(id, landedCosts)')
    expect(source).toContain('await receivePurchaseInvoice(id)')
    expect(source).toContain('await billPurchaseInvoice(id, {')
    expect(source).toContain('await cancelPurchaseInvoice(invoice.id)')
    expect(source).toContain("can('procurement.invoices.receive')")
    expect(source).toContain("can('procurement.invoices.bill')")
    expect(source).toContain("can('procurement.invoices.cancel')")
    expect(source).toContain('<ResponsiveModal')
    expect(source).toContain('<DocumentActions kind="purchase-invoice" entityId={invoice.id} />')
  })
})
