import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./VaultsPage.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')

describe('VaultsPage V2 overview composition contract', () => {
  it('uses one responsive collection boundary with deliberate Desktop, Tablet and Mobile renderers', () => {
    expect(source).toContain("import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'")
    expect(source).toContain('<ResponsiveCollection<Vault>')
    expect(source).toContain('renderDesktop={items => (')
    expect(source).toContain("renderTablet={items => renderVaultCards(items, 'tablet')}")
    expect(source).toContain("renderMobile={items => renderVaultCards(items, 'mobile')}")
    expect(source).toContain('ds-responsive-card-grid--${mode}')
    expect(source).not.toContain('vault-table-view')
    expect(source).not.toContain('vault-card-view')
    expect(source).not.toContain('vault-mobile-card')
    expect(source).not.toContain('mobile-card-list')
  })

  it('projects the existing page-owned totals into shared summary grammar without inventing active-count tone', () => {
    expect(source).toContain('const totalBalance = vaults.reduce((s, v) => s + v.current_balance, 0)')
    expect(source).toContain('const activeCount = vaults.filter(v => v.is_active).length')
    expect(source).toContain('<VaultSummary')
    expect(source).toContain("totalBalanceTone: totalBalance >= 0 ? 'success' : 'danger'")
    expect(source).toContain('activeCount,')
    expect(source).toContain('totalCount: vaults.length')
    expect(source).not.toContain('activeCountTone:')
    expect(source).not.toContain('edara-stats-row')
  })

  it('preserves permission and opening-balance predicates while declaring card actions through AppAction', () => {
    expect(source).toContain('const vaultActions = (v: Vault): AppAction[] => {')
    expect(source).toContain("if (can('finance.vaults.transact'))")
    expect(source).toContain('if (v.current_balance === 0)')
    expect(source).toContain("if (can('finance.vaults.update'))")
    expect(source).toContain("id: 'statement'")
    expect(source).toContain("id: 'opening'")
    expect(source).toContain("id: 'deposit'")
    expect(source).toContain("id: 'withdrawal'")
    expect(source).toContain("id: 'edit'")
    expect(source).toContain("onSelect: () => openStatement(v)")
    expect(source).toContain("onSelect: () => openTx(v, 'opening')")
    expect(source).toContain("onSelect: () => openTx(v, 'deposit')")
    expect(source).toContain("onSelect: () => openTx(v, 'withdrawal')")
    expect(source).toContain('onSelect: () => openEdit(v)')
  })

  it('keeps categorical vault type neutral and active/inactive as semantic operational status', () => {
    expect(source).toContain("<Badge variant=\"neutral\">{vaultTypeLabel(v.type)}</Badge>")
    expect(source).toContain("<StatusBadge label={v.is_active ? 'نشطة' : 'معطلة'} tone={v.is_active ? 'success' : 'neutral'} />")
    expect(source).toContain("typeLabel: vaultTypeLabel(v.type)")
    expect(source).toContain("statusTone: v.is_active ? 'success' : 'neutral'")
    expect(source).not.toContain('vaultTypeBadge')
  })

  it('preserves empty/create permission behavior and all statement paging semantics', () => {
    expect(source).toContain('const emptyVaultsState = (')
    expect(source).toContain('title="لا توجد خزائن"')
    expect(source).toContain('description="قم بإنشاء أول خزنة لبدء العمل"')
    expect(source).toContain("action={can('finance.vaults.create') ? (")
    expect(source).toContain('loading={loading}')
    expect(source).toContain('emptyState={emptyVaultsState}')
    expect(source).toContain('getVaultTransactions(vault.id, { page: 1, pageSize: 25 })')
    expect(source).toContain('getVaultTransactions(stmtVault.id, { page: p, pageSize: 25 })')
  })

  it('keeps existing create/transfer header predicates and finance mutation services untouched', () => {
    expect(source).toContain("can('finance.vaults.transact') && vaults.filter(v => v.is_active).length >= 2")
    expect(source).toContain("can('finance.vaults.create')")
    expect(source).toContain('await createVault(form)')
    expect(source).toContain('await updateVault(editingVault.id, form)')
    expect(source).toContain('await postManualVaultAdjustment(')
    expect(source).toContain('await transferBetweenVaults(transferFrom, transferTo, amt, transferDesc)')
  })
})
