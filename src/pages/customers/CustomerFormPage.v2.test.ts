import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./CustomerFormPage.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')

describe('CustomerFormPage V2 composition contract', () => {
  it('keeps the shared V2 form grammar around the existing submit flow', () => {
    expect(source).toContain("import PageHeader from '@/components/shared/PageHeader'")
    expect(source).toContain("import FormSection from '@/components/patterns/FormSection'")
    expect(source).toContain("import FormGrid from '@/components/patterns/FormGrid'")
    expect(source).toContain("import FormActions from '@/components/patterns/FormActions'")
    expect(source).toContain('<form onSubmit={handleSubmit}>')
    expect(source).toContain('<FormSection title="المعلومات الأساسية"')
    expect(source).toContain('<FormGrid columns={3}>')
    expect(source).toContain('<FormActions align="between" stickyOnMobile>')
  })

  it('preserves the credit permission and customer-creation side effects', () => {
    expect(source).toContain('permission="finance.credit.manage" mode="disable"')
    expect(source).toContain("can('customers.credit.update')")
    expect(source).toContain('await createCustomer(form)')
    expect(source).toContain('await saveCustomerBranch(created.id')
    expect(source).toContain('await saveCustomerContact(created.id')
    expect(source).toContain('onClick={captureGPS}')
  })

  it('keeps tabs explicit and non-submitting while preserving their permission boundary', () => {
    expect(source).toContain('role="tablist"')
    expect(source).toContain('type="button" role="tab" aria-selected={tab === \'info\'}')
    expect(source).toContain('type="button" role="tab" aria-selected={tab === \'credit\'}')
  })
})
