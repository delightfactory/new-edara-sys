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

  it('adopts the complete shared Tabs composition for edit-mode secondary surfaces', () => {
    expect(source).toContain("import CustomerDetailTabs, { type CustomerDetailTab } from './CustomerDetailTabs'")
    expect(source).toContain("from './CustomerSecondaryPanels'")
    expect(source).toContain("useState<CustomerDetailTab>('info')")
    expect(source).toContain('<CustomerDetailTabs')
    expect(source).toContain('onValueChange={setTab}')
    expect(source).toContain("canViewCredit={can('customers.credit.update')}")
    expect(source).toContain('infoPanel={infoPanel}')
    expect(source).toContain('<CustomerBranchesPanel')
    expect(source).toContain("canUpdate={can('customers.update')}")
    expect(source).toContain('onAdd={openBranchCreate}')
    expect(source).toContain('onEdit={openBranchEdit}')
    expect(source).toContain('onDelete={deleteBranch}')
    expect(source).toContain('<CustomerContactsPanel')
    expect(source).toContain('onAdd={openContactCreate}')
    expect(source).toContain('onEdit={openContactEdit}')
    expect(source).toContain('onDelete={deleteContact}')
    expect(source).toContain('creditPanel={<CustomerCreditHistoryPanel history={creditHistory} />}')
  })

  it('removes the duplicate legacy tab switcher and secondary panel markup', () => {
    expect(source).not.toContain('className="tabs"')
    expect(source).not.toContain('className={`tab ${tab ===')
    expect(source).not.toContain('TAB: BRANCHES')
    expect(source).not.toContain('TAB: CONTACTS')
    expect(source).not.toContain('TAB: CREDIT HISTORY')
  })
})
