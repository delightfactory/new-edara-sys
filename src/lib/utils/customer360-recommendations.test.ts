import { describe, it, expect } from 'vitest'
import { computeRecommendations } from './customer360-recommendations'
import type { Customer360Kpis, CustomerPaymentBehavior, CustomerArAgingBucket } from '../services/customer360'

describe('Customer 360 Recommendations Engine', () => {
  const baseCustomer = { id: 'test', current_balance: 0, is_active: true }

  it('identifies overdue critical amounts', () => {
    const arAging: CustomerArAgingBucket[] = [
      { bucket: '0-30', amount: 5000, invoice_count: 5, oldest_invoice_date: '2023-01-01' },
      { bucket: '90+', amount: 3000, invoice_count: 2, oldest_invoice_date: '2023-02-01' },
    ]
    const recs = computeRecommendations({ customer: baseCustomer, arAging })
    expect(recs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'overdue_critical', severity: 'critical' })
      ])
    )
  })

  it('identifies credit near limit', () => {
    // Threshold is 0.85
    const customer = { ...baseCustomer, current_balance: 8600 }
    const kpis: Customer360Kpis = {
      credit_limit: 10000,
      credit_utilization_pct: 86,
      net_revenue: 1000, total_collected: 500, outstanding_balance: 8600, order_count: 10,
      monthly_avg_orders: 2, return_rate_pct: 0, latest_order_date: '2023-01-01', customer_since_days: 100
    }
    const recs = computeRecommendations({ customer, kpis })
    expect(recs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'credit_near_limit', severity: 'warning' })
      ])
    )
  })

  it('identifies positive credit balance', () => {
    const customer = { ...baseCustomer, current_balance: -1500 }
    const recs = computeRecommendations({ customer })
    expect(recs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'credit_balance', severity: 'positive' })
      ])
    )
  })

  it('identifies slow payer', () => {
    // Threshold is 45 days
    const paymentBehavior: CustomerPaymentBehavior = {
      avg_payment_delay_days: 50,
      min_delay_days: 5, max_delay_days: 60, payment_samples: 10, payment_methods_breakdown: {}, recent_receipts: []
    }
    const recs = computeRecommendations({ customer: baseCustomer, paymentBehavior })
    expect(recs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'slow_payer', severity: 'warning' })
      ])
    )
  })

  it('identifies high return rate', () => {
    // Threshold is 0.15 (15%)
    const kpis: Customer360Kpis = {
      credit_limit: 10000, credit_utilization_pct: 0, net_revenue: 1000, total_collected: 500, outstanding_balance: 0,
      order_count: 10, monthly_avg_orders: 2, return_rate_pct: 16, latest_order_date: '2023-01-01', customer_since_days: 100
    }
    const recs = computeRecommendations({ customer: baseCustomer, kpis })
    expect(recs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'high_return_rate', severity: 'warning' })
      ])
    )
  })

  it('identifies churned products', () => {
    // Threshold is 2
    const recs = computeRecommendations({ customer: baseCustomer, churned_products_count: 3 })
    expect(recs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'churned_products', severity: 'opportunity' })
      ])
    )
  })

  it('identifies categorical concentration', () => {
    // Threshold is 0.80
    const recs = computeRecommendations({ customer: baseCustomer, category_concentration: 0.85 })
    expect(recs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'category_concentration', severity: 'opportunity' })
      ])
    )
  })

  it('identifies sales decline', () => {
    // Threshold is -0.30
    const recs = computeRecommendations({ customer: baseCustomer, monthly_trend_delta: -0.35 })
    expect(recs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'sales_decline', severity: 'warning' })
      ])
    )
  })

  it('displays lock-state gracefully for profitability', () => {
    const recs = computeRecommendations({ customer: baseCustomer, profitability: null })
    expect(recs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'profitability_locked', severity: 'info' })
      ])
    )
  })

  it('identifies dormant high value customer', () => {
    // recency > 60 and monetary > avg
    const health = { health_status: 'نشط', recency_days: 65, frequency_l90d: 0, monetary_l90d: 5000, risk_label: null, last_snapshot_date: null }
    const recs = computeRecommendations({ customer: baseCustomer, health, avg_monetary_l90d: 2000 })
    expect(recs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'dormant_high_value', severity: 'critical' })
      ])
    )
  })

  it('identifies inactive customer fallback', () => {
    const customer = { ...baseCustomer, is_active: false }
    const recs = computeRecommendations({ customer })
    expect(recs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: 'customer_inactive', severity: 'warning' })
      ])
    )
  })
})
