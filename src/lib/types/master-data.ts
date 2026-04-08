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
  cost_price?: number | null
  last_purchase_price?: number | null
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

export interface WarehouseCostBreakdown {
  warehouse_id: string
  warehouse_name: string
  quantity: number
  total_cost_value: number
  wac: number
}

export interface ProductCostMetrics {
  product_id: string
  global_quantity: number
  global_total_cost_value: number
  global_wac: number | null  // NULL when product has no stock
  warehouse_breakdown: WarehouseCostBreakdown[]
  cost_price: number | null
  last_purchase_price: number | null
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

// ============================================================
// Phase 3 — Financial Infrastructure
// Maps to: supabase/migrations/03_financial_infrastructure.sql
// ============================================================

// ----- CHART OF ACCOUNTS -----

export type AccountType = 'asset' | 'liability' | 'equity' | 'revenue' | 'expense'

export interface ChartOfAccount {
  id: string
  code: string
  name: string
  name_en: string | null
  type: AccountType
  parent_id: string | null
  is_active: boolean
  sort_order: number
  created_at: string
  // client-side tree
  children?: ChartOfAccount[]
}

// ----- CUSTOMER LEDGER -----

export type LedgerEntryType = 'debit' | 'credit'
export type CustomerLedgerSource = 'sales_order' | 'sales_return' | 'payment' | 'opening_balance' | 'adjustment'
export type SupplierLedgerSource = 'purchase_order' | 'purchase_return' | 'payment' | 'opening_balance' | 'adjustment'

export interface CustomerLedgerEntry {
  id: string
  customer_id: string
  type: LedgerEntryType
  amount: number
  source_type: CustomerLedgerSource
  source_id: string | null
  description: string | null
  created_by: string | null
  created_at: string
  // joined
  customer?: Pick<Customer, 'id' | 'name' | 'code'>
  created_by_profile?: { id: string; full_name: string }
}

export interface CustomerBalance {
  customer_id: string
  balance: number
  transaction_count: number
  last_transaction_at: string | null
}

// ----- SUPPLIER LEDGER -----

export interface SupplierLedgerEntry {
  id: string
  supplier_id: string
  type: LedgerEntryType
  amount: number
  source_type: SupplierLedgerSource
  source_id: string | null
  description: string | null
  created_by: string | null
  created_at: string
  // joined
  supplier?: Pick<Supplier, 'id' | 'name' | 'code'>
  created_by_profile?: { id: string; full_name: string }
}

export interface SupplierBalance {
  supplier_id: string
  balance: number
  transaction_count: number
  last_transaction_at: string | null
}

// ----- VAULTS -----

export type VaultType = 'cash' | 'bank' | 'mobile_wallet'

export interface Vault {
  id: string
  name: string
  type: VaultType
  account_number: string | null
  bank_name: string | null
  responsible_id: string | null
  branch_id: string | null
  current_balance: number
  is_active: boolean
  created_at: string
  updated_at: string
  // joined
  responsible?: { id: string; full_name: string }
  branch?: Pick<Branch, 'id' | 'name'>
}

export interface VaultInput {
  name: string
  type: VaultType
  account_number?: string | null
  bank_name?: string | null
  responsible_id?: string | null
  branch_id?: string | null
  is_active?: boolean
}

export type VaultTransactionType =
  | 'deposit' | 'withdrawal'
  | 'transfer_in' | 'transfer_out'
  | 'collection' | 'expense'
  | 'custody_load' | 'custody_return'
  | 'opening_balance' | 'vendor_payment'

export interface VaultTransaction {
  id: string
  vault_id: string
  type: VaultTransactionType
  amount: number
  balance_after: number
  reference_type: string | null
  reference_id: string | null
  description: string | null
  created_by: string | null
  created_at: string
  // joined
  created_by_profile?: { id: string; full_name: string }
}

// ----- CUSTODY ACCOUNTS -----

export interface CustodyAccount {
  id: string
  employee_id: string
  max_balance: number
  current_balance: number
  is_active: boolean
  created_at: string
  updated_at: string
  // joined
  employee?: { id: string; full_name: string }
}

export interface CustodyAccountInput {
  employee_id: string
  max_balance?: number
  is_active?: boolean
}

export type CustodyTransactionType = 'load' | 'collection' | 'expense' | 'settlement' | 'return'

export interface CustodyTransaction {
  id: string
  custody_id: string
  type: CustodyTransactionType
  amount: number
  balance_after: number
  vault_id: string | null
  reference_type: string | null
  reference_id: string | null
  description: string | null
  created_by: string | null
  created_at: string
  // joined
  vault?: Pick<Vault, 'id' | 'name' | 'type'>
  created_by_profile?: { id: string; full_name: string }
}

// ----- PAYMENT RECEIPTS -----

export type PaymentMethod = 'cash' | 'bank_transfer' | 'instapay' | 'cheque' | 'mobile_wallet'
export type PaymentReceiptStatus = 'pending' | 'confirmed' | 'rejected'

export interface PaymentReceipt {
  id: string
  number: string
  customer_id: string
  amount: number
  payment_method: PaymentMethod
  status: PaymentReceiptStatus
  vault_id: string | null
  custody_id: string | null
  branch_id: string | null
  proof_url: string | null
  bank_reference: string | null
  check_number: string | null
  check_date: string | null
  notes: string | null
  collected_by: string | null
  reviewed_by: string | null
  reviewed_at: string | null
  rejection_reason: string | null
  sales_order_id: string | null
  created_by: string | null
  created_at: string
  updated_at: string
  // joined
  customer?: Pick<Customer, 'id' | 'name' | 'code'>
  vault?: Pick<Vault, 'id' | 'name' | 'type'>
  custody?: CustodyAccount
  branch?: Pick<Branch, 'id' | 'name'>
  sales_order?: Pick<SalesOrder, 'id' | 'order_number'> | null
  collected_by_profile?: { id: string; full_name: string }
  reviewed_by_profile?: { id: string; full_name: string }
  created_by_profile?: { id: string; full_name: string }
}

export interface PaymentReceiptInput {
  customer_id: string
  amount: number
  payment_method: PaymentMethod
  custody_id?: string | null
  branch_id?: string | null
  proof_url?: string | null
  bank_reference?: string | null
  check_number?: string | null
  check_date?: string | null
  notes?: string | null
  collected_by?: string | null
  sales_order_id?: string | null
}

// ----- EXPENSES -----

export interface ExpenseCategory {
  id: string
  name: string
  parent_id: string | null
  is_active: boolean
  created_at: string
  // client-side tree
  children?: ExpenseCategory[]
}

export type ExpenseStatus = 'draft' | 'pending_approval' | 'approved' | 'rejected'
export type PaymentSource = 'vault' | 'custody'

export interface Expense {
  id: string
  number: string
  category_id: string | null
  amount: number
  description: string
  expense_date: string
  status: ExpenseStatus
  payment_source: PaymentSource | null
  vault_id: string | null
  custody_id: string | null
  receipt_url: string | null
  branch_id: string | null
  approved_by: string | null
  approved_at: string | null
  rejection_reason: string | null
  created_by: string | null
  created_at: string
  updated_at: string
  // joined
  category?: Pick<ExpenseCategory, 'id' | 'name'>
  vault?: Pick<Vault, 'id' | 'name' | 'type'>
  custody?: CustodyAccount
  branch?: Pick<Branch, 'id' | 'name'>
  approved_by_profile?: { id: string; full_name: string }
  created_by_profile?: { id: string; full_name: string }
}

export interface ExpenseInput {
  category_id?: string | null
  amount: number
  description: string
  expense_date?: string
  payment_source: PaymentSource
  vault_id?: string | null
  custody_id?: string | null
  receipt_url?: string | null
  branch_id?: string | null
}

// ----- APPROVAL RULES -----

export type ApprovalType = 'expense' | 'purchase_order' | 'sales_discount'

export interface ApprovalRule {
  id: string
  type: ApprovalType
  role_id: string
  max_amount: number
  sort_order: number
  is_active: boolean
  created_at: string
  // joined
  role?: { id: string; name: string; name_ar: string; color: string }
}

// ----- JOURNAL ENTRIES -----

export type JournalSourceType =
  | 'sales_order' | 'sales_return' | 'payment'
  | 'purchase_order' | 'purchase_return'
  | 'expense' | 'custody' | 'transfer' | 'manual'
export type JournalStatus = 'draft' | 'posted'

export interface JournalEntry {
  id: string
  number: string
  entry_date: string
  source_type: JournalSourceType
  source_id: string | null
  description: string | null
  is_auto: boolean
  status: JournalStatus
  total_debit: number
  total_credit: number
  created_by: string | null
  created_at: string
  // joined
  lines?: JournalEntryLine[]
  created_by_profile?: { id: string; full_name: string }
}

export interface JournalEntryLine {
  id: string
  entry_id: string
  account_id: string
  debit: number
  credit: number
  description: string | null
  // joined
  account?: Pick<ChartOfAccount, 'id' | 'code' | 'name'>
}

export interface JournalEntryInput {
  entry_date?: string
  source_type: JournalSourceType
  source_id?: string | null
  description: string
}

export interface JournalEntryLineInput {
  account_code: string
  debit: number
  credit: number
  description?: string | null
}

// ============================================================
// Phase 4 — Sales System
// Maps to: supabase/migrations/04_sales_system.sql
// ============================================================

// ----- SHIPPING COMPANIES -----

export interface ShippingCompany {
  id: string
  name: string
  phone: string | null
  email: string | null
  notes: string | null
  is_active: boolean
  created_by: string | null
  created_at: string
  updated_at: string
}

export interface ShippingCompanyInput {
  name: string
  phone?: string | null
  email?: string | null
  notes?: string | null
  is_active?: boolean
}

// ----- SALES ORDERS -----

export type SalesOrderStatus =
  | 'draft' | 'confirmed' | 'partially_delivered'
  | 'delivered' | 'completed' | 'cancelled'

export type SalesReturnStatus = 'draft' | 'confirmed' | 'cancelled'

export type DeliveryMethod = 'direct' | 'shipping' | 'pickup'

export interface SalesOrder {
  id: string
  order_number: string

  // الأطراف
  customer_id: string
  rep_id: string | null
  created_by_id: string
  branch_id: string | null

  // الحالة
  status: SalesOrderStatus
  order_date: string
  expected_delivery: string | null

  // التسليم
  delivery_method: DeliveryMethod
  warehouse_id: string | null
  shipping_company_id: string | null
  tracking_number: string | null
  shipping_cost: number
  shipping_on_customer: boolean
  delivery_address_id: string | null

  // الدفع
  payment_terms: PaymentTerms | null
  payment_method: PaymentMethod | null
  vault_id: string | null
  custody_id: string | null
  cash_amount: number
  credit_amount: number

  // الإجماليات
  subtotal: number
  discount_amount: number
  tax_amount: number
  total_amount: number
  paid_amount: number
  returned_amount: number

  // فحص الائتمان
  credit_check_passed: boolean | null
  credit_override: boolean
  credit_override_by: string | null

  // التدقيق
  confirmed_by: string | null
  confirmed_at: string | null
  delivered_by: string | null
  delivered_at: string | null
  cancelled_by: string | null
  cancelled_at: string | null
  cancel_reason: string | null

  due_date: string | null
  notes: string | null
  created_at: string
  updated_at: string

  // joined
  customer?: Pick<Customer, 'id' | 'name' | 'code' | 'phone' | 'payment_terms' | 'credit_limit' | 'credit_days'>
  rep?: { id: string; full_name: string }
  created_by_profile?: { id: string; full_name: string }
  branch?: Pick<Branch, 'id' | 'name'>
  warehouse?: Pick<Warehouse, 'id' | 'name'>
  shipping_company?: Pick<ShippingCompany, 'id' | 'name'>
  delivery_address?: Pick<CustomerBranch, 'id' | 'name' | 'address'>
  vault?: Pick<Vault, 'id' | 'name' | 'type'>
  custody?: Pick<CustodyAccount, 'id' | 'current_balance'> & { employee?: { id: string; full_name: string } }
  items?: SalesOrderItem[]
  returns?: SalesReturn[]
}

export interface SalesOrderInput {
  customer_id: string
  rep_id?: string | null
  branch_id?: string | null
  order_date?: string
  expected_delivery?: string | null
  delivery_method?: DeliveryMethod
  warehouse_id?: string | null
  shipping_company_id?: string | null
  tracking_number?: string | null
  shipping_cost?: number
  shipping_on_customer?: boolean
  delivery_address_id?: string | null
  notes?: string | null
}

// ----- SALES ORDER ITEMS -----

export interface SalesOrderItem {
  id: string
  order_id: string
  product_id: string
  unit_id: string
  conversion_factor: number
  quantity: number
  base_quantity: number
  delivered_quantity: number
  returned_quantity: number
  unit_price: number
  discount_percent: number
  discount_amount: number
  tax_rate: number
  tax_amount: number
  line_total: number
  unit_cost_at_sale: number
  // joined
  product?: Pick<Product, 'id' | 'name' | 'sku' | 'selling_price' | 'tax_rate'> & {
    base_unit?: Pick<Unit, 'id' | 'name' | 'symbol'>
  }
  unit?: Pick<Unit, 'id' | 'name' | 'symbol'>
}

export interface SalesOrderItemInput {
  product_id: string
  unit_id: string
  conversion_factor?: number
  quantity: number
  base_quantity: number
  unit_price: number
  discount_percent?: number
  discount_amount?: number
  tax_rate?: number
  tax_amount?: number
  line_total?: number
}

// ----- SALES RETURNS -----

export interface SalesReturn {
  id: string
  return_number: string
  order_id: string
  customer_id: string
  warehouse_id: string | null
  status: SalesReturnStatus
  return_date: string
  total_amount: number
  reason: string | null
  notes: string | null
  confirmed_by: string | null
  confirmed_at: string | null
  cancelled_by: string | null
  cancelled_at: string | null
  created_by: string
  created_at: string
  updated_at: string
  // joined
  order?: Pick<SalesOrder, 'id' | 'order_number' | 'payment_terms' | 'total_amount'>
  customer?: Pick<Customer, 'id' | 'name' | 'code'>
  warehouse?: Pick<Warehouse, 'id' | 'name'>
  confirmed_by_profile?: { id: string; full_name: string }
  created_by_profile?: { id: string; full_name: string }
  items?: SalesReturnItem[]
}

export interface SalesReturnInput {
  order_id: string
  customer_id: string
  warehouse_id?: string | null
  return_date?: string
  reason?: string | null
  notes?: string | null
}

export interface SalesReturnItem {
  id: string
  return_id: string
  order_item_id: string
  product_id: string
  unit_id: string
  conversion_factor: number
  quantity: number
  base_quantity: number
  unit_price: number
  line_total: number
  unit_cost_at_sale: number
  // joined
  product?: Pick<Product, 'id' | 'name' | 'sku'>
  unit?: Pick<Unit, 'id' | 'name' | 'symbol'>
  order_item?: Pick<SalesOrderItem, 'id' | 'delivered_quantity' | 'returned_quantity'>
}

export interface SalesReturnItemInput {
  order_item_id: string
  product_id: string
  unit_id: string
  conversion_factor?: number
  quantity: number
  base_quantity: number
  unit_price: number
  line_total?: number
}

// ----- SALES SETTINGS -----

export interface SalesSettings {
  maxDiscountPercent: number
  minOrderAmount: number
  taxEnabled: boolean
  defaultTaxRate: number
}

// ============================================================
// Phase 5 — Procurement Module
// Maps to: supabase/migrations/14_procurement_schema_and_coa.sql
// ============================================================

export type PurchaseInvoiceStatus = 'draft' | 'received' | 'billed' | 'paid' | 'cancelled'
export type PurchasePaymentMethod = 'cash' | 'bank_transfer' | 'cheque' | 'instapay' | 'mobile_wallet'

export interface PurchaseInvoiceItem {
  id: string
  invoice_id: string
  product_id: string
  unit_id: string | null
  ordered_quantity: number
  received_quantity: number
  unit_price: number
  discount_rate: number   // 0–100 percent
  tax_rate: number        // 0–100 percent
  // computed by receive_purchase_invoice RPC
  net_cost: number
  landed_cost_share: number
  true_net_cost: number
  created_at: string
  // joined
  product?: Pick<Product, 'id' | 'name' | 'sku'> & {
    base_unit?: Pick<Unit, 'id' | 'name' | 'symbol'>
  }
  unit?: Pick<Unit, 'id' | 'name' | 'symbol'>
}

export interface PurchaseInvoice {
  id: string
  number: string          // Auto-generated: PIN-YYYYMMDD-XXXX
  supplier_id: string
  warehouse_id: string
  status: PurchaseInvoiceStatus
  invoice_date: string
  supplier_invoice_ref: string | null
  due_date: string | null
  // financials
  subtotal: number
  discount_amount: number
  tax_amount: number
  landed_costs: number
  total_amount: number
  paid_amount: number
  // payment (immediate only)
  vault_id: string | null
  payment_method: PurchasePaymentMethod | null
  bank_reference: string | null
  check_number: string | null
  check_date: string | null
  notes: string | null
  // audit
  received_by: string | null
  received_at: string | null
  billed_by: string | null
  billed_at: string | null
  created_by: string | null
  created_at: string
  updated_at: string
  // joined
  supplier?: Pick<Supplier, 'id' | 'name' | 'code'>
  warehouse?: Pick<Warehouse, 'id' | 'name'>
  vault?: Pick<Vault, 'id' | 'name' | 'type'>
  items?: PurchaseInvoiceItem[]
}

// ----- INPUT TYPES -----

export interface PurchaseInvoiceItemInput {
  product_id: string
  unit_id?: string | null
  ordered_quantity: number
  received_quantity?: number
  unit_price: number
  discount_rate?: number
  tax_rate?: number
}

export interface PurchaseInvoiceInput {
  supplier_id: string
  warehouse_id: string
  invoice_date?: string
  supplier_invoice_ref?: string | null
  due_date?: string | null
  landed_costs?: number
  notes?: string | null
}


// ============================================================
// Phase 6 — Procurement Returns & Cancellations
// ============================================================

export type PurchaseReturnStatus = 'draft' | 'confirmed'

export interface PurchaseReturnItem {
  id: string
  return_id: string
  product_id: string
  unit_id: string | null
  quantity: number
  unit_price: number
  discount_rate: number
  tax_rate: number
  ap_line_gross: number
  ap_line_discount: number
  ap_line_net: number
  ap_line_tax: number
  ap_line_total: number
  cogs_value: number
  wac_variance: number
  line_total: number
  created_at: string
  product?: Pick<Product, 'id' | 'name' | 'sku'> & { base_unit?: Pick<Unit, 'id' | 'name' | 'symbol'> }
  unit?: Pick<Unit, 'id' | 'name' | 'symbol'>
}

export interface PurchaseReturn {
  id: string
  number: string
  supplier_id: string
  warehouse_id: string
  original_invoice_id: string | null
  status: PurchaseReturnStatus
  return_date: string
  notes: string | null
  subtotal: number
  discount_amount: number
  tax_amount: number
  total_amount: number
  refunded_amount: number
  confirmed_by: string | null
  confirmed_at: string | null
  created_by: string | null
  created_at: string
  updated_at: string
  supplier?: Pick<Supplier, 'id' | 'name' | 'code'>
  warehouse?: Pick<Warehouse, 'id' | 'name'>
  original_invoice?: Pick<PurchaseInvoice, 'id' | 'number'> | null
  confirmed_by_profile?: { id: string; full_name: string }
  items?: PurchaseReturnItem[]
}

export interface PurchaseReturnItemInput {
  product_id: string
  unit_id?: string | null
  quantity: number
  unit_price: number
  discount_rate?: number
  tax_rate?: number
}

export interface PurchaseReturnInput {
  supplier_id: string
  warehouse_id: string
  original_invoice_id?: string | null
  return_date?: string
  notes?: string | null
}
