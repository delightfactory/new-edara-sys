import { beforeEach, describe, expect, it, vi } from 'vitest'

const { getProductsMock } = vi.hoisted(() => ({ getProductsMock: vi.fn() }))

vi.mock('@/lib/services/products', () => ({
  getProducts: getProductsMock,
}))

import { loadTargetProductOptions, TARGET_UI_CONFIG } from './TargetForm'

describe('TargetForm supported type flows', () => {
  it('defines an explicit flow for every active target type', () => {
    expect(Object.keys(TARGET_UI_CONFIG).sort()).toEqual([
      'calls_count',
      'category_spread',
      'collection',
      'new_customers',
      'product_qty',
      'reactivation',
      'sales_value',
      'upgrade_value',
      'visits_count',
    ])

    expect(TARGET_UI_CONFIG.sales_value.filters).toEqual(['product', 'category', 'geography'])
    expect(TARGET_UI_CONFIG.product_qty.filters).toEqual(['product', 'category'])
    expect(TARGET_UI_CONFIG.collection.filters).toEqual([])
    expect(TARGET_UI_CONFIG.new_customers.filters).toEqual([])
    expect(TARGET_UI_CONFIG.reactivation).toMatchObject({ needsCustomers: true, monthlyOnly: true })
    expect(TARGET_UI_CONFIG.upgrade_value).toMatchObject({ needsCustomers: true, monthlyOnly: true })
    expect(TARGET_UI_CONFIG.category_spread).toMatchObject({ needsCustomers: true, monthlyOnly: true })
  })

  describe('smart product selector', () => {
    beforeEach(() => getProductsMock.mockReset())

    it('loads every page of active products and exposes identifying details', async () => {
      getProductsMock
        .mockResolvedValueOnce({
          data: [{ id: 'p1', name: 'منتج ألف', sku: 'SKU-1', barcode: '111', category: { name: 'أغذية' } }],
          totalPages: 2,
        })
        .mockResolvedValueOnce({
          data: [{ id: 'p2', name: 'منتج باء', sku: 'SKU-2', barcode: null, category: { name: 'مشروبات' } }],
          totalPages: 2,
        })

      const options = await loadTargetProductOptions(' ألف ')

      expect(getProductsMock).toHaveBeenNthCalledWith(1, {
        search: 'ألف', isActive: true, page: 1, pageSize: 200,
      })
      expect(getProductsMock).toHaveBeenNthCalledWith(2, {
        search: 'ألف', isActive: true, page: 2, pageSize: 200,
      })
      expect(options).toEqual([
        { value: 'p1', label: 'منتج ألف', sublabel: 'SKU-1 • أغذية • 111' },
        { value: 'p2', label: 'منتج باء', sublabel: 'SKU-2 • مشروبات' },
      ])
    })
  })
})
