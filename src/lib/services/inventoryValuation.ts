/**
 * Inventory Valuation & Analytics Service — EDARA v2
 * Calls the RPCs defined in 94/95_inventory_*_rpc.sql
 */

import { supabase } from '@/lib/supabase/client'
import type {
  InventoryValuationSummary,
  WarehouseInventory,
  CategoryInventory,
  InventoryMovementAnalysis,
  DeadStockSummary,
  ABCProduct,
} from '@/lib/types/inventoryValuation'

/**
 * Get inventory valuation summary (total value, quantity, health indicators)
 */
export async function getInventoryValuationSummary(): Promise<InventoryValuationSummary> {
  const { data, error } = await supabase.rpc('get_inventory_valuation_summary')
  if (error) throw new Error(`فشل تحميل ملخص تقييم المخزون: ${error.message}`)
  return data as InventoryValuationSummary
}

/**
 * Get inventory breakdown by warehouse
 */
export async function getInventoryByWarehouse(): Promise<WarehouseInventory[]> {
  const { data, error } = await supabase.rpc('get_inventory_by_warehouse')
  if (error) throw new Error(`فشل تحميل توزيع المخزون حسب المخازن: ${error.message}`)
  return (data ?? []) as WarehouseInventory[]
}

/**
 * Get inventory breakdown by category
 */
export async function getInventoryByCategory(): Promise<CategoryInventory[]> {
  const { data, error } = await supabase.rpc('get_inventory_by_category')
  if (error) throw new Error(`فشل تحميل توزيع المخزون حسب التصنيفات: ${error.message}`)
  return (data ?? []) as CategoryInventory[]
}

// ── 95_inventory_analytics_rpcs.sql ──────────────────────────

/**
 * Get per-product movement analysis (velocity, coverage, dead stock)
 */
export async function getInventoryMovementAnalysis(): Promise<InventoryMovementAnalysis[]> {
  const { data, error } = await supabase.rpc('get_inventory_movement_analysis')
  if (error) throw new Error(`فشل تحميل تحليل حركة المخزون: ${error.message}`)
  return (data ?? []) as InventoryMovementAnalysis[]
}

/**
 * Get dead stock summary (counts and values by aging bucket)
 */
export async function getInventoryDeadStockSummary(): Promise<DeadStockSummary> {
  const { data, error } = await supabase.rpc('get_inventory_dead_stock_summary')
  if (error) throw new Error(`فشل تحميل ملخص المخزون الراكد: ${error.message}`)
  return data as DeadStockSummary
}

/**
 * Get ABC classification for all products with stock
 */
export async function getInventoryABCAnalysis(): Promise<ABCProduct[]> {
  const { data, error } = await supabase.rpc('get_inventory_abc_analysis')
  if (error) throw new Error(`فشل تحميل تصنيف ABC: ${error.message}`)
  return (data ?? []) as ABCProduct[]
}
