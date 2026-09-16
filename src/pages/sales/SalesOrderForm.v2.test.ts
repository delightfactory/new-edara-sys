import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./SalesOrderForm.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')

describe('SalesOrderForm V2 outer composition contract', () => {
  it('uses the shared V2 stepper, form section and action composition', () => {
    expect(source).toContain("from '@/components/sales/SalesOrderFormPresentation'")
    expect(source).toContain('<SalesOrderStepNavigator')
    expect(source).toContain('<SalesOrderFormSection')
    expect(source).toContain('<SalesOrderFormActions')
    expect(source).not.toContain('stepper-bar edara-card')
    expect(source).not.toContain('stepper-label')
    expect(source).not.toContain("transform: 'rotate(180deg)'")
  })

  it('preserves the shared 3 Desktop -> 2 Tablet -> 1 Mobile density contract for order data', () => {
    expect(source).toContain('<SalesOrderFormSection title="بيانات الطلب" icon={<User size={16} />} columns={3}>')
    expect(source).not.toContain('<SalesOrderFormSection title="بيانات الطلب" icon={<User size={16} />} columns={2}>')
    expect(source.match(/gridColumn: '1 \/ -1'/g)?.length ?? 0).toBeGreaterThanOrEqual(2)
  })

  it('keeps direct step activation page-owned and prevents free access to review', () => {
    expect(source).toContain('const canActivateStep = (index: number) => {')
    expect(source).toContain('if (index === step || index < step) return true')
    expect(source).toContain('if (index === 1) return canProceedStep0')
    expect(source).toContain('if (index === 2) return canProceedStep0 && canProceedStep1')
    expect(source).toContain('return false')
    expect(source).toContain('canActivate={canActivateStep}')
    expect(source).toContain('onChange={setStep}')
  })

  it('preserves forward validation and page-owned submission truth', () => {
    expect(source).toContain("if (step === 0 && !canProceedStep0) { toast.error('يرجى اختيار العميل أولاً'); return }")
    expect(source).toContain("if (step === 1 && !canProceedStep1) { toast.error('يرجى إضافة منتج واحد على الأقل'); return }")
    expect(source).toContain('onNext={goNext}')
    expect(source).toContain('submitDisabled={saving || !form.customer_id || validLines.length === 0 || isUnderMin}')
    expect(source).toContain('onSubmit={handleSave}')
    expect(source).toContain('await updateSalesOrder(id!, form)')
    expect(source).toContain('await createSalesOrder(form)')
    expect(source).toContain('await saveSalesOrderItems(orderId!, itemInputs)')
    expect(source).toContain('await recalcOrderTotals(orderId!)')
  })

  it('keeps pricing, discount permissions, copy/edit and mobile add-product flows page-owned', () => {
    expect(source).toContain("const canEditPrice = can('sales.orders.edit_price')")
    expect(source).toContain("const canOverrideDiscount = can('sales.discounts.override')")
    expect(source).toContain('getProductPrice(productId, effectiveCustomerId, unitId, qty)')
    expect(source).toContain("const copyFromId = searchParams.get('copyFrom')")
    expect(source).toContain("if (order.status !== 'draft')")
    expect(source).toContain('<ResponsiveModal')
    expect(source).toContain('setItemSheet(true)')
  })
})
