// ============================================================
// Master Data Types — Phase 2
// Maps to: supabase/migrations/02_master_data.sql (30 tables)
// ============================================================

// ----- GEOGRAPHY -----

export interface Governorate {
  id: string
  name: string
  name_en: string | null
  code: string
  sort_order: number
  created_at: string
  updated_at: string
}

export interface City {
  id: string
  governorate_id: string
  name: string
  name_en: string | null
  sort_order: number
  created_at: string
  updated_at: string
  // joined
  governorate?: Pick<Governorate, 'id' | 'name' | 'name_en'>
}

export interface Area {
  id: string
  city_id: string
  name: string
  created_at: string
  updated_at: string
}

// ----- BRANCHES -----

export type BranchType = 'distribution' | 'retail' | 'warehouse'

export interface Branch {
  id: string
  name: string
  type: BranchType
  city_id: string | null
  address: string | null
  phone: string | null
  manager_id: string | null
  is_active: boolean
  created_at: string
  updated_at: string
  // joined
  city?: Pick<City, 'id' | 'name'> & { governorate?: Pick<Governorate, 'id' | 'name'> }
  manager?: { id: string; full_name: string }
}

export interface BranchInput {
  name: string
  type: BranchType
  city_id?: string | null
  address?: string | null
  phone?: string | null
  manager_id?: string | null
  is_active?: boolean
}

// ----- PRODUCTS -----

export interface ProductCategory {
  id: string
  name: string
  parent_id: string | null
  icon: string | null
  sort_order: number
  is_active: boolean
  created_at: string
  updated_at: string
  // client-side tree
  children?: ProductCategory[]
}

export interface Brand {
  id: string
  name: string
  logo_url: string | null
  is_active: boolean
  created_at: string
  updated_at: string
}

export interface Unit {
  id: string
  name: string
  symbol: string
  is_base: boolean
  created_at: string
  updated_at: string
}

export interface Product {
  id: string
  sku: string
  name: string
  barcode: string | null
  category_id: string | null
  brand_id: string | null
  base_unit_id: string
  selling_price: number
  cost_price: number
  tax_rate: number
  description: string | null
  image_url: string | null
  is_active: boolean
  min_stock_level: number
  created_at: string
  updated_at: string
  // joined
  category?: Pick<ProductCategory, 'id' | 'name'>
  brand?: Pick<Brand, 'id' | 'name'>
  base_unit?: Pick<Unit, 'id' | 'name' | 'symbol'>
  product_units?: ProductUnit[]
}

export interface ProductInput {
  sku: string
  name: string
  barcode?: string | null
  category_id?: string | null
  brand_id?: string | null
  base_unit_id: string
  selling_price: number
  cost_price: number
  tax_rate?: number
  description?: string | null
  image_url?: string | null
  is_active?: boolean
  min_stock_level?: number
}

export interface ProductUnit {
  id: string
  product_id: string
  unit_id: string
  conversion_factor: number
  selling_price: number | null
  is_purchase_unit: boolean
  is_sales_unit: boolean
  created_at: string
  // joined
  unit?: Pick<Unit, 'id' | 'name' | 'symbol'>
}

export interface ProductUnitInput {
  unit_id: string
  conversion_factor: number
  selling_price?: number | null
  is_purchase_unit?: boolean
  is_sales_unit?: boolean
}

export interface ProductBundle {
  id: string
  name: string
  sku: string | null
  price: number
  is_active: boolean
  created_at: string
  updated_at: string
  items?: ProductBundleItem[]
}

export interface ProductBundleItem {
  id: string
  bundle_id: string
  product_id: string
  unit_id: string
  quantity: number
  // joined
  product?: Pick<Product, 'id' | 'name' | 'sku'>
  unit?: Pick<Unit, 'id' | 'name' | 'symbol'>
}

// ----- PRICE LISTS -----

export interface PriceList {
  id: string
  name: string
  description: string | null
  is_default: boolean
  is_active: boolean
  valid_from: string | null
  valid_to: string | null
  created_at: string
  updated_at: string
}

export interface PriceListItem {
  id: string
  price_list_id: string
  product_id: string
  unit_id: string
  price: number
  min_qty: number
  max_qty: number | null
  created_at: string
  // joined
  product?: Pick<Product, 'id' | 'name' | 'sku'>
  unit?: Pick<Unit, 'id' | 'name' | 'symbol'>
}

export interface PriceListAssignment {
  id: string
  price_list_id: string
  entity_type: 'customer' | 'city' | 'governorate'
  entity_id: string
  created_at: string
}

// ----- CUSTOMERS -----

export type CustomerType = 'retail' | 'wholesale' | 'distributor'
export type PaymentTerms = 'cash' | 'credit' | 'mixed'

export interface Customer {
  id: string
  code: string          // Auto-generated: CUS-00001
  name: string
  type: CustomerType
  governorate_id: string | null
  city_id: string | null
  area_id: string | null
  address: string | null
  phone: string | null
  mobile: string | null
  email: string | null
  tax_number: string | null
  payment_terms: PaymentTerms
  credit_limit: number
  credit_days: number
  opening_balance: number
  current_balance: number
  price_list_id: string | null
  assigned_rep_id: string | null
  latitude: number | null
  longitude: number | null
  location_accuracy: number | null
  location_updated_at: string | null
  location_updated_by: string | null
  is_active: boolean
  notes: string | null
  created_by: string | null
  created_at: string
  updated_at: string
  // joined
  governorate?: Pick<Governorate, 'id' | 'name'>
  city?: Pick<City, 'id' | 'name'>
  area?: Pick<Area, 'id' | 'name'>
  assigned_rep?: { id: string; full_name: string }
  price_list?: Pick<PriceList, 'id' | 'name'>
}

export interface CustomerInput {
  name: string
  type?: CustomerType
  governorate_id?: string | null
  city_id?: string | null
  area_id?: string | null
  address?: string | null
  phone?: string | null
  mobile?: string | null
  email?: string | null
  tax_number?: string | null
  payment_terms?: PaymentTerms
  credit_limit?: number
  credit_days?: number
  opening_balance?: number
  price_list_id?: string | null
  assigned_rep_id?: string | null
  is_active?: boolean
  notes?: string | null
}

export interface CustomerBranch {
  id: string
  customer_id: string
  name: string
  address: string | null
  phone: string | null
  contact_name: string | null
  latitude: number | null
  longitude: number | null
  is_primary: boolean
  created_at: string
  updated_at: string
}

export interface CustomerContact {
  id: string
  customer_id: string
  name: string
  role: string | null
  phone: string | null
  email: string | null
  is_primary: boolean
  created_at: string
}

export interface CustomerCreditHistory {
  id: string
  customer_id: string
  limit_before: number
  limit_after: number
  changed_by: string
  reason: string | null
  created_at: string
  // joined
  changed_by_profile?: { id: string; full_name: string }
}

// ----- SUPPLIERS -----

export interface Supplier {
  id: string
  code: string          // Auto-generated: SUP-00001
  name: string
  type: string | null
  governorate_id: string | null
  city_id: string | null
  phone: string | null
  email: string | null
  tax_number: string | null
  payment_terms: string | null
  credit_limit: number
  credit_days: number
  opening_balance: number
  current_balance: number
  bank_account: string | null
  is_active: boolean
  created_at: string
  updated_at: string
  // joined
  governorate?: Pick<Governorate, 'id' | 'name'>
  city?: Pick<City, 'id' | 'name'>
}

export interface SupplierInput {
  name: string
  type?: string | null
  governorate_id?: string | null
  city_id?: string | null
  phone?: string | null
  email?: string | null
  tax_number?: string | null
  payment_terms?: string | null
  credit_limit?: number
  credit_days?: number
  opening_balance?: number
  bank_account?: string | null
  is_active?: boolean
}

export interface SupplierContact {
  id: string
  supplier_id: string
  name: string
  role: string | null
  phone: string | null
  email: string | null
  created_at: string
}

export interface SupplierPaymentReminder {
  id: string
  supplier_id: string
  due_date: string
  amount: number
  invoice_ref: string | null
  status: 'pending' | 'paid' | 'overdue'
  notify_before_days: number
  created_at: string
  updated_at: string
}

// ----- WAREHOUSES & STOCK -----

export type WarehouseType = 'fixed' | 'vehicle' | 'retail'

export interface Warehouse {
  id: string
  name: string
  type: WarehouseType
  branch_id: string | null
  address: string | null
  manager_id: string | null
  is_active: boolean
  created_at: string
  updated_at: string
  // joined
  branch?: Pick<Branch, 'id' | 'name'>
  manager?: { id: string; full_name: string }
}

export interface WarehouseManager {
  id: string
  warehouse_id: string
  profile_id: string
  is_primary: boolean
  can_approve_receipts: boolean
  created_at: string
  // joined
  profile?: { id: string; full_name: string }
}

export interface Stock {
  id: string
  warehouse_id: string
  product_id: string
  quantity: number
  reserved_quantity: number
  available_quantity: number  // GENERATED COLUMN
  wac: number
  total_cost_value: number
  created_at: string
  updated_at: string
  // joined
  warehouse?: Pick<Warehouse, 'id' | 'name' | 'type'>
  product?: Pick<Product, 'id' | 'name' | 'sku'> & { base_unit?: Pick<Unit, 'id' | 'name' | 'symbol'> }
}

export interface StockBatch {
  id: string
  stock_id: string
  batch_number: string
  expiry_date: string | null
  quantity: number
  cost_price: number
  created_at: string
}

export type StockMovementType =
  | 'in' | 'out'
  | 'transfer_in' | 'transfer_out'
  | 'adjustment_add' | 'adjustment_remove'
  | 'return_in' | 'return_out'

export interface StockMovement {
  id: string
  warehouse_id: string
  product_id: string
  unit_id: string | null
  quantity: number
  type: StockMovementType
  unit_cost: number | null
  wac_before: number | null
  wac_after: number | null
  before_qty: number | null
  after_qty: number | null
  reference_type: string | null
  reference_id: string | null
  notes: string | null
  created_by: string | null
  created_at: string
  // joined
  warehouse?: Pick<Warehouse, 'id' | 'name'>
  product?: Pick<Product, 'id' | 'name' | 'sku'>
  created_by_profile?: { id: string; full_name: string }
}

// ----- STOCK TRANSFERS -----

export type TransferStatus = 'pending' | 'approved' | 'in_transit' | 'received' | 'cancelled'

export type TransferDirection = 'push' | 'pull'

export interface StockTransfer {
  id: string
  number: string         // Auto-generated: TRN-000001
  from_warehouse_id: string
  to_warehouse_id: string
  direction: TransferDirection
  status: TransferStatus
  requested_by: string
  approved_by: string | null
  sent_by: string | null
  received_by: string | null
  notes: string | null
  sent_at: string | null
  received_at: string | null
  created_at: string
  updated_at: string
  // joined
  from_warehouse?: Pick<Warehouse, 'id' | 'name'>
  to_warehouse?: Pick<Warehouse, 'id' | 'name'>
  requested_by_profile?: { id: string; full_name: string }
  items?: StockTransferItem[]
}

export interface StockTransferItem {
  id: string
  transfer_id: string
  product_id: string
  unit_id: string
  quantity: number
  received_quantity: number
  unit_cost: number
  // joined
  product?: Pick<Product, 'id' | 'name' | 'sku'>
  unit?: Pick<Unit, 'id' | 'name' | 'symbol'>
}

// ----- STOCK ADJUSTMENTS -----

export type AdjustmentType = 'add' | 'remove' | 'count'
export type AdjustmentStatus = 'draft' | 'pending' | 'approved' | 'rejected'

export interface StockAdjustment {
  id: string
  number: string         // Auto-generated: ADJ-000001
  warehouse_id: string
  type: AdjustmentType
  status: AdjustmentStatus
  reason: string | null
  approved_by: string | null
  created_by: string
  created_at: string
  updated_at: string
  // joined
  warehouse?: Pick<Warehouse, 'id' | 'name'>
  created_by_profile?: { id: string; full_name: string }
  items?: StockAdjustmentItem[]
}

export interface StockAdjustmentItem {
  id: string
  adjustment_id: string
  product_id: string
  system_qty: number
  actual_qty: number
  difference: number     // GENERATED COLUMN
  unit_cost: number
  notes: string | null
  // joined
  product?: Pick<Product, 'id' | 'name' | 'sku'>
}
