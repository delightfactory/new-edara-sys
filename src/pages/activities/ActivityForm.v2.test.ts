import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./ActivityForm.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')
const stylesheetPath = fileURLToPath(new URL('../../styles/field-activity-form-v2.css', import.meta.url))
const stylesheet = readFileSync(stylesheetPath, 'utf8')

describe('ActivityForm V2 composition contract', () => {
  it('adopts the shared form composition without restoring the local outer mini-system', () => {
    expect(source).toContain("import FormSection from '@/components/patterns/FormSection'")
    expect(source).toContain("import FormGrid from '@/components/patterns/FormGrid'")
    expect(source).toContain("import FormActions from '@/components/patterns/FormActions'")
    expect(source).toContain('<form className="ds-field-activity-form" onSubmit={handleSubmit}>')
    expect(source).toContain('<FormSection title="بيانات النشاط">')
    expect(source).toContain('<FormSection title="النتيجة والربط">')
    expect(source).toContain('<FormSection title="التوقيت والملاحظات">')
    expect(source).toContain('<FormGrid columns={3}>')
    expect(source).toContain('<FormActions>')
    expect(source).not.toContain('className="edara-card act-form"')
    expect(source).not.toContain('act-form-times')
    expect(source).not.toContain('act-form-actions')
    expect(source).not.toContain('<style>{`')
  })

  it('keeps action callbacks, labels and save/GPS suppression page-owned and non-sticky', () => {
    expect(source).toContain('onClick={() => navigate(-1)}')
    expect(source).toContain('disabled={saving}')
    expect(source).toContain('disabled={saving || gpsBlocking}')
    expect(source).toContain("{saving ? 'جاري الحفظ...' : activityId ? 'حفظ التعديلات' : 'تسجيل النشاط'}")
    expect(source).toContain('touchTarget')
    expect(source).not.toContain('stickyOnMobile')
  })

  it('preserves validation, GPS, payload, mutation and query ownership in ActivityForm', () => {
    expect(source).toContain('function validate(): string | null')
    expect(source).toContain("if (gpsBlocking) return 'يتطلب هذا النوع تحديد موقع GPS'")
    expect(source).toContain("if (isCallType && !callResult) return 'اختر نتيجة المكالمة'")
    expect(source).toContain('const payload: ActivityInput = {')
    expect(source).toContain('gps_verified:        !!gpsCoords')
    expect(source).toContain('distance_meters:     distanceMeters')
    expect(source).toContain('updateActivity.mutate(')
    expect(source).toContain('createActivity.mutate(payload')
    expect(source).toContain('saveCallDetail.mutateAsync')
    expect(source).toContain('useActivities({ customerId: customerId || undefined, pageSize: 3 })')
    expect(source).toContain('useTargetStatus({ isActive: true })')
    expect(source).toContain(".from('sales_orders')")
  })

  it('leaves visit-plan routing and link/call-detail behavior in the existing page boundary', () => {
    expect(source).toContain("if (planType === 'visit' && planItemId)")
    expect(source).toContain("navigate(`/activities/visit-plans/${resolvedPlanId}/execute`)")
    expect(source).toContain("navigate('/activities/visit-plans')")
    expect(source).toContain('className="act-link-section"')
    expect(source).toContain('className="act-call-section"')
    expect(source).toContain("navigate(`/sales/orders/new?customerId=${customerId}&returnUrl=${returnUrl}`)")
    expect(source).toContain("navigate(`/finance/payments?customerId=${customerId}`)")
  })

  it('associates the composition-touched Arabic labels with native controls', () => {
    expect(source).toContain('htmlFor="activity-type"')
    expect(source).toContain('id="activity-type"')
    expect(source).toContain('htmlFor="activity-customer"')
    expect(source).toContain('id="activity-customer"')
    expect(source).toContain('htmlFor="activity-outcome"')
    expect(source).toContain('id="activity-outcome"')
    expect(source).toContain('htmlFor="activity-date"')
    expect(source).toContain('id="activity-date"')
    expect(source).toContain('htmlFor="activity-start-time"')
    expect(source).toContain('htmlFor="activity-end-time"')
    expect(source).toContain('htmlFor="activity-outcome-notes"')
  })

  it('keeps the bounded form width and retires only superseded local composition CSS', () => {
    expect(stylesheet).toContain('.ds-field-activity-form')
    expect(stylesheet).toContain('max-width: 640px')
    expect(stylesheet).toContain('margin-inline: auto')
    expect(stylesheet).toContain('.act-call-section')
    expect(stylesheet).toContain('.act-link-section')
    expect(stylesheet).not.toContain('.act-form-times')
    expect(stylesheet).not.toContain('.act-form-actions')
  })
})
