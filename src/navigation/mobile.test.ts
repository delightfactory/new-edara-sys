import { describe, expect, it } from 'vitest'
import { getVisibleMobilePrimaryDestinations } from './mobile'

describe('mobile shell navigation parity', () => {
  it('preserves the established shortcut labels and order when fully authorized', () => {
    const items = getVisibleMobilePrimaryDestinations({
      can: () => true,
      canAny: () => true,
    })

    expect(items.map(item => [item.id, item.mobileLabel])).toEqual([
      ['dashboard', 'الرئيسية'],
      ['work', 'العمل'],
      ['sales-orders', 'المبيعات'],
      ['customers', 'العملاء'],
    ])
  })

  it('keeps the existing mobile shortcuts stricter than route-level create access', () => {
    const evaluator = {
      can: (permission: string) => permission === 'sales.orders.create' || permission === 'customers.create',
      canAny: (permissions: string[]) => permissions.some(permission =>
        permission === 'sales.orders.create' || permission === 'customers.create'
      ),
    }

    const items = getVisibleMobilePrimaryDestinations(evaluator)
    expect(items.map(item => item.id)).toEqual(['dashboard'])
  })
})
