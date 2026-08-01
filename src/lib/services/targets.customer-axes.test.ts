import { describe, expect, it } from 'vitest'
import { buildComputedMetrics, validateCreateTargetInput } from './targets'
import type { CreateTargetWithRewardsInput, Target, TargetProgress, TargetRewardTier } from '@/lib/types/activities'

const base: CreateTargetWithRewardsInput = {
  type_id: '00000000-0000-0000-0000-000000000001',
  name: 'هدف اختبار',
  scope: 'individual',
  scope_id: '00000000-0000-0000-0000-000000000002',
  period: 'monthly',
  period_start: '2026-08-01',
  period_end: '2026-08-31',
  target_value: 1,
  customers: [{ customer_id: '00000000-0000-0000-0000-000000000003' }],
}

describe('customer target axes service validation', () => {
  it('accepts upgrade targets without a manually supplied baseline', () => {
    const errors = validateCreateTargetInput({
      ...base,
      filter_criteria: { growth_pct: 20 },
    }, 'upgrade_value', 'sales')
    expect(errors).toEqual([])
  })

  it('requires dormancy and a positive reactivation value', () => {
    const errors = validateCreateTargetInput({ ...base }, 'reactivation', 'sales')
    expect(errors.map(e => e.field)).toEqual(expect.arrayContaining([
      'dormancy_days', 'filter_criteria.min_reactivation_value',
    ]))
  })

  it('requires an integer category count', () => {
    const errors = validateCreateTargetInput({
      ...base,
      filter_criteria: { required_category_count: 2.5 },
    }, 'category_spread', 'sales')
    expect(errors.some(e => e.field === 'filter_criteria.required_category_count')).toBe(true)
  })

  it('rejects targets larger than the fixed customer list', () => {
    const errors = validateCreateTargetInput({
      ...base,
      target_value: 2,
      filter_criteria: { growth_pct: 20 },
    }, 'upgrade_value', 'sales')
    expect(errors.some(e => e.field === 'target_value')).toBe(true)
  })

  it('rejects a partial calendar month', () => {
    const errors = validateCreateTargetInput({
      ...base,
      period_start: '2026-08-02',
      filter_criteria: { growth_pct: 20 },
    }, 'upgrade_value', 'sales')
    expect(errors.some(e => e.field === 'period_start')).toBe(true)
  })
})

describe('general target type filter validation', () => {
  const simpleBase: CreateTargetWithRewardsInput = {
    ...base,
    customers: undefined,
    scope: 'company',
    scope_id: null,
    target_value: 100,
  }

  it('requires a product or category for a quantity target', () => {
    const errors = validateCreateTargetInput(simpleBase, 'product_qty', 'product')
    expect(errors.some(e => e.field === 'product_id')).toBe(true)
  })

  it('accepts a quantity target for one selected product', () => {
    const errors = validateCreateTargetInput({ ...simpleBase, product_id: 'product-1' }, 'product_qty', 'product')
    expect(errors).toEqual([])
  })

  it('rejects conflicting product and category filters', () => {
    const errors = validateCreateTargetInput({
      ...simpleBase,
      product_id: 'product-1',
      category_id: 'category-1',
    }, 'sales_value', 'financial')
    expect(errors.some(e => e.field === 'category_id')).toBe(true)
  })

  it('rejects geography on a type whose calculation does not use it', () => {
    const errors = validateCreateTargetInput({
      ...simpleBase,
      governorate_id: 'governorate-1',
    }, 'collection', 'financial')
    expect(errors.some(e => e.field === 'governorate_id')).toBe(true)
  })

  it('accepts hierarchical geography for sales value', () => {
    const errors = validateCreateTargetInput({
      ...simpleBase,
      governorate_id: 'governorate-1',
      city_id: 'city-1',
      area_id: 'area-1',
    }, 'sales_value', 'financial')
    expect(errors).toEqual([])
  })

  it('rejects invalid dates and thresholds before calling the database', () => {
    const errors = validateCreateTargetInput({
      ...simpleBase,
      period_start: '2026-09-01',
      period_end: '2026-08-31',
      min_value: 101,
      stretch_value: 99,
    }, 'sales_value', 'financial')
    expect(errors.map(e => e.field)).toEqual(expect.arrayContaining([
      'period_end', 'min_value', 'stretch_value',
    ]))
  })

  it('rejects automatic payout for a non-individual target', () => {
    const errors = validateCreateTargetInput({
      ...simpleBase,
      reward_type: 'fixed',
      reward_base_value: 1000,
      auto_payout: true,
      tiers: [{ sequence: 1, threshold_pct: 100, reward_pct: 100 }],
    }, 'sales_value', 'financial')
    expect(errors.some(e => e.field === 'auto_payout')).toBe(true)
  })

  it.each([
    ['sales_value', 'financial', {}],
    ['collection', 'financial', {}],
    ['product_qty', 'product', { product_id: 'product-1' }],
    ['visits_count', 'activity', {}],
    ['calls_count', 'activity', {}],
    ['new_customers', 'customer', {}],
    ['upgrade_value', 'customer', { customers: base.customers, target_value: 1, filter_criteria: { growth_pct: 20 } }],
    ['reactivation', 'customer', { customers: base.customers, target_value: 1, dormancy_days: 90, filter_criteria: { min_reactivation_value: 5000 } }],
    ['category_spread', 'customer', { customers: base.customers, target_value: 1, filter_criteria: { required_category_count: 4 } }],
  ])('accepts a complete valid payload for %s', (typeCode, typeCategory, overrides) => {
    const errors = validateCreateTargetInput({ ...simpleBase, ...overrides }, typeCode, typeCategory)
    expect(errors).toEqual([])
  })
})

describe('percentage reward display safety', () => {
  it('does not treat achieved customer count as a sales pool for upgrade_value', () => {
    const target = {
      type_code: 'upgrade_value',
      target_value: 2,
      period_start: '2026-08-01',
      period_end: '2026-08-31',
      reward_type: 'percentage',
      reward_base_value: 2,
      reward_pool_basis: 'sales_value',
    } as Target
    const progress = { achieved_value: 2, achievement_pct: 100 } as TargetProgress
    const tiers = [{ id: 'tier-1', sequence: 1, threshold_pct: 100, reward_pct: 100 }] as TargetRewardTier[]

    expect(buildComputedMetrics(target, progress, tiers).current_tier_info?.estimated_reward).toBeNull()
  })
})
