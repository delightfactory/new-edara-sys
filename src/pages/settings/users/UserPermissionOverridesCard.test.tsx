import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { UserPermissionOverridesCard } from './UserPermissionOverridesCard'
import type { UserPermissionContext } from '@/lib/types/auth'

const baseContext: UserPermissionContext = {
  inherited_permissions: [],
  has_wildcard: false,
  role_permissions_by_role: {
    'sales-role': ['sales.orders.read'],
    'admin-role': ['*'],
  },
  overrides: [],
}

function permissionRow(permission: string): HTMLElement {
  const code = screen.getByText(permission)
  const row = code.closest('.user-permission-row')
  if (!row) throw new Error(`Permission row not found: ${permission}`)
  return row as HTMLElement
}

describe('UserPermissionOverridesCard', () => {
  it('previews permissions inherited from the roles currently selected in the form', () => {
    render(
      <UserPermissionOverridesCard
        context={baseContext}
        selectedRoleIds={['sales-role']}
        value={[]}
        onChange={vi.fn()}
      />,
    )

    expect(within(permissionRow('sales.orders.read')).getByText('مسموح فعليًا')).toBeTruthy()
    expect(within(permissionRow('sales.orders.create')).getByText('غير مسموح')).toBeTruthy()
  })

  it('shows an explicit revoke as denied even when the selected role has wildcard', () => {
    render(
      <UserPermissionOverridesCard
        context={baseContext}
        selectedRoleIds={['admin-role']}
        value={[{
          permission: 'finance.view_costs',
          granted: false,
          reason: null,
          expires_at: null,
        }]}
        onChange={vi.fn()}
      />,
    )

    const row = permissionRow('finance.view_costs')
    expect(within(row).getByText('غير مسموح')).toBeTruthy()
    expect((within(row).getByRole('combobox') as HTMLSelectElement).value).toBe('revoke')
  })

  it('emits a new explicit grant without mutating the inherited context', async () => {
    const onChange = vi.fn()
    const user = userEvent.setup()
    render(
      <UserPermissionOverridesCard
        context={baseContext}
        selectedRoleIds={[]}
        value={[]}
        onChange={onChange}
      />,
    )

    await user.selectOptions(
      within(permissionRow('finance.view_costs')).getByRole('combobox'),
      'grant',
    )

    expect(onChange).toHaveBeenCalledWith([{
      permission: 'finance.view_costs',
      granted: true,
      reason: null,
      expires_at: null,
    }])
  })
})
