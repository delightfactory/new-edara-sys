/**
 * Inventory Valuation Types — EDARA v2
 * Matches the output of 94_inventory_valuation_rpc.sql RPCs
 */

export interface InventoryValuationSummary {
  total_value: number
  total_quantity: number
  unique_products: number
  total_warehouses: number
  out_of_stock_count: number
  low_stock_count: number
  total_retail_value: number
}

export interface WarehouseInventory {
  warehouse_id: string
  warehouse_name: string
  warehouse_type: 'fixed' | 'vehicle' | 'retail'
  product_count: number
  total_quantity: number
  total_value: number
  value_percentage: number
}

export interface CategoryInventory {
  category_id: string | null
  category_name: string
  product_count: number
  total_quantity: number
  total_value: number
  value_percentage: number
}

// ── 95_inventory_analytics_rpcs.sql types ────────────────────

export type CoverageStatus = 'dead' | 'critical' | 'low' | 'ok' | 'surplus'

export interface InventoryMovementAnalysis {
  product_id: string
  product_name: string
  product_sku: string
  category_name: string
  total_quantity: number
  available_qty: number
  total_value: number
  daily_velocity: number
  days_of_cover: number
  last_out_date: string | null
  days_since_last_out: number | null
  coverage_status: CoverageStatus
}

export interface DeadStockBucket {
  count: number
  value: number
}

export interface DeadStockSummary {
  dead_30: DeadStockBucket
  dead_60: DeadStockBucket
  dead_90: DeadStockBucket
  total_dead_value: number
  total_dead_pct: number
  surplus_count: number
  surplus_value: number
  critical_count: number
  low_count: number
}

export type ABCClass = 'A' | 'B' | 'C'

export interface ABCProduct {
  product_id: string
  product_name: string
  product_sku: string
  category_name: string
  total_quantity: number
  total_value: number
  value_pct: number
  cumulative_pct: number
  abc_class: ABCClass
}
