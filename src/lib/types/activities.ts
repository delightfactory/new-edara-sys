// ============================================================
// Activities Module Types — Phase 21 (MVP) — v2 CORRECTED
// Maps to: supabase/migrations/21_activities_module_mvp.sql
//          supabase/migrations/21b_activities_rls_engine.sql
//
// ⚠️ أسماء الأعمدة هنا مطابقة 1:1 للـ schema الفعلي في قاعدة البيانات.
// ============================================================

// ─── Enums / Literals ─────────────────────────────────────────

export type ActivityCategory = 'visit' | 'call' | 'task'

export type ActivityOutcome =
  | 'order_placed'
  | 'agreed_order'
  | 'collection'
  | 'promised_payment'
  | 'followup_scheduled'
  | 'followup_visit'
  | 'refused'
  | 'not_interested'
  | 'closed'
  | 'promotion'
  | 'exploratory'
  | 'info_only'
  | 'no_answer'
  | 'busy'
  | 'callback_scheduled'

export type CallDirection = 'inbound' | 'outbound'

export type CallResult =
  | 'answered'
  | 'no_answer'
  | 'busy'
  | 'callback_scheduled'
  | 'wrong_number'
  | 'rejected'

export type PlanStatus =
  | 'draft'
  | 'confirmed'
  | 'in_progress'
  | 'completed'
  | 'partial'
  | 'cancelled'
  | 'missed'

export type PlanItemStatus =
  | 'pending'
  | 'in_progress'
  | 'completed'
  | 'skipped'
  | 'missed'
  | 'rescheduled'

export type PlanItemPurposeType =
  | 'sales'
  | 'collection'
  | 'activation'
  | 'promotion'
  | 'followup'
  | 'service'

export type PlanPriority = 'high' | 'normal' | 'low'

export type TargetScope = 'company' | 'branch' | 'department' | 'individual'

export type TargetPeriod = 'monthly' | 'quarterly' | 'yearly' | 'custom'

export type TargetUnit = 'currency' | 'count' | 'percent' | 'quantity'

export type TargetTrend = 'on_track' | 'at_risk' | 'behind' | 'achieved' | 'exceeded'

export type AdjustableField =
  | 'target_value'
  | 'min_value'
  | 'stretch_value'
  | 'period_end'
  | 'is_paused'
  | 'is_active'
  | 'filter_criteria'

// ─── Reference Data (Read-Only in current phase) ─────────────
// activity_types, target_types, visit_plan_templates, call_plan_templates
// يُقرأ فقط للـ dropdowns — لا CRUD UI في هذه المرحلة

export interface ActivityType {
  id: string
  name: string
  code: string
  category: ActivityCategory
  icon: string | null
  requires_gps: boolean
  requires_customer: boolean
  requires_outcome: boolean
  default_duration_min: number
  is_active: boolean
  sort_order: number
  created_at: string
}

export interface TargetType {
  id: string
  name: string
  code: string
  unit: TargetUnit
  category: string       // 'financial' | 'activity' | 'customer' | 'product'
  auto_source: string    // 'sales_orders' | 'payment_receipts' | 'activities' | 'customers' | 'manual'
  auto_calc_enabled: boolean
  description: string | null
  is_active: boolean
  created_at: string
}

export interface VisitPlanTemplate {
  id: string
  name: string
  employee_id: string | null
  branch_id: string | null
  recurrence: 'none' | 'daily' | 'weekly' | 'monthly'
  day_of_week: number[] | null
  items: any[]
  is_active: boolean
  created_by: string
  created_at: string
}

export interface CallPlanTemplate {
  id: string
  name: string
  employee_id: string | null
  branch_id: string | null
  recurrence: 'none' | 'daily' | 'weekly' | 'monthly'
  day_of_week: number[] | null
  items: any[]
  is_active: boolean
  created_by: string
  created_at: string
}

// ─── Core Activity ─────────────────────────────────────────────
// جدول activities — الأعمدة مطابقة للـ schema (line 355)

export interface Activity {
  id: string
  type_id: string                          // ✅ type_id (لا activity_type_id)
  employee_id: string                      // UUID → hr_employees(id)
  customer_id: string | null
  visit_plan_item_id: string | null
  call_plan_item_id: string | null
  subject: string | null
  subject_type: string | null
  outcome_type: ActivityOutcome
  outcome_notes: string | null
  refuse_reason: string | null
  closed_reason: string | null
  gps_lat: number | null
  gps_lng: number | null
  gps_verified: boolean
  distance_meters: number | null
  start_time: string | null                // TIMESTAMPTZ
  end_time: string | null
  duration_minutes: number | null          // GENERATED — قراءة فقط
  activity_date: string                    // DATE
  order_id: string | null                  // ✅ order_id (لا sales_order_id)
  collection_id: string | null             // ✅ collection_id (لا payment_receipt_id)
  followup_activity_id: string | null
  attachments: any[]
  metadata: Record<string, any>
  is_offline_sync: boolean
  synced_at: string | null
  device_id: string | null
  created_by: string                       // UUID → profiles(id)
  created_at: string
  updated_at: string
  deleted_at: string | null
  // joined
  type?: Pick<ActivityType, 'id' | 'name' | 'code' | 'category' | 'icon' | 'requires_gps' | 'requires_customer'>
  customer?: {
    id: string
    name: string
    code: string
    phone: string | null
    latitude: number | null
    longitude: number | null
  }
  call_detail?: CallDetail | null
}

export interface ActivityInput {
  type_id: string                          // ✅ type_id
  employee_id: string
  customer_id?: string | null
  visit_plan_item_id?: string | null
  call_plan_item_id?: string | null
  subject?: string | null
  subject_type?: string | null
  outcome_type: ActivityOutcome
  outcome_notes?: string | null
  refuse_reason?: string | null
  closed_reason?: string | null
  gps_lat?: number | null
  gps_lng?: number | null
  gps_verified?: boolean
  distance_meters?: number | null
  start_time?: string | null
  end_time?: string | null
  activity_date: string
  order_id?: string | null                 // ✅ order_id
  collection_id?: string | null            // ✅ collection_id
  followup_activity_id?: string | null
  metadata?: Record<string, any>
}

// ─── Call Details ──────────────────────────────────────────────
// أعمدة call_details الفعلية في DB:
// direction, call_result, phone_number, attempt_count, callback_at, call_recording_url

export interface CallDetail {
  id: string
  activity_id: string
  direction: CallDirection
  call_result: CallResult | null
  attempt_count: number
  phone_number: string | null        // ✅ اسم العمود الفعلي في DB
  callback_at: string | null
  call_recording_url: string | null  // ✅ اسم العمود الفعلي في DB
  created_at: string
}

export interface CallDetailInput {
  direction: CallDirection
  call_result?: CallResult | null
  attempt_count?: number
  phone_number?: string | null       // ✅ مطابق للـ DB
  callback_at?: string | null
  call_recording_url?: string | null // ✅ مطابق للـ DB
}

// ─── Visit Plans ───────────────────────────────────────────────
// جدول visit_plans — الأعمدة مطابقة (line 167)

export interface VisitPlan {
  id: string
  employee_id: string                      // UUID → hr_employees(id)
  plan_date: string                        // DATE
  plan_type: 'daily' | 'weekly' | 'campaign' | 'recurring'
  status: PlanStatus
  template_id: string | null
  total_customers: number                  // ✅ total_customers (لا total_planned)
  completed_count: number                  // ✅ completed_count
  skipped_count: number                    // ✅ skipped_count
  missed_count: number                     // ✅ missed_count
  completion_pct: number                   // GENERATED
  notes: string | null
  cancellation_reason: string | null       // ✅ cancellation_reason
  confirmed_at: string | null
  confirmed_by: string | null
  started_at: string | null
  completed_at: string | null
  created_by: string
  created_at: string
  updated_at: string
  // joined
  employee?: { id: string; full_name: string; branch_id: string | null }
  template?: Pick<VisitPlanTemplate, 'id' | 'name'> | null
  items?: VisitPlanItem[]
}

export interface VisitPlanInput {
  employee_id: string
  plan_date: string
  plan_type?: 'daily' | 'weekly' | 'campaign' | 'recurring'
  template_id?: string | null
  notes?: string | null
}

export interface VisitPlanItem {
  id: string
  plan_id: string
  customer_id: string                      // NOT NULL في visit_plan_items
  sequence: number                         // ✅ sequence (لا sequence_order)
  planned_time: string | null              // TIME
  estimated_duration_min: number           // ✅ estimated_duration_min
  priority: PlanPriority
  purpose: string | null
  purpose_type: PlanItemPurposeType | null
  status: PlanItemStatus
  actual_arrival_time: string | null
  actual_start_time: string | null
  actual_end_time: string | null
  activity_id: string | null
  skip_reason: string | null
  reschedule_to: string | null
  created_at: string
  updated_at: string
  // joined
  customer?: {
    id: string
    name: string
    code: string
    phone: string | null
    latitude: number | null
    longitude: number | null
  }
  activity?: Pick<Activity, 'id' | 'outcome_type' | 'created_at'> | null
}

export interface VisitPlanItemInput {
  customer_id: string
  sequence: number                         // ✅ sequence
  planned_time?: string | null
  estimated_duration_min?: number          // ✅ estimated_duration_min
  priority?: PlanPriority
  purpose?: string | null
  purpose_type?: PlanItemPurposeType | null
}

// ─── Call Plans ────────────────────────────────────────────────
// جدول call_plans — الأعمدة مطابقة (line 270)

export interface CallPlan {
  id: string
  employee_id: string                      // UUID → hr_employees(id)
  plan_date: string                        // DATE
  plan_type: 'daily' | 'weekly' | 'campaign' | 'recurring'
  status: PlanStatus
  template_id: string | null
  total_calls: number                      // ✅ total_calls (لا total_planned)
  completed_count: number
  skipped_count: number
  missed_count: number
  completion_pct: number                   // GENERATED
  notes: string | null
  cancellation_reason: string | null       // ✅ cancellation_reason
  confirmed_at: string | null
  confirmed_by: string | null
  started_at: string | null
  completed_at: string | null
  created_by: string
  created_at: string
  updated_at: string
  // joined
  employee?: { id: string; full_name: string; branch_id: string | null }
  template?: Pick<CallPlanTemplate, 'id' | 'name'> | null
  items?: CallPlanItem[]
}

export interface CallPlanInput {
  employee_id: string
  plan_date: string
  plan_type?: 'daily' | 'weekly' | 'campaign' | 'recurring'
  template_id?: string | null
  notes?: string | null
}

export interface CallPlanItem {
  id: string
  plan_id: string
  customer_id: string | null               // ✅ nullable (call_plan_items.customer_id REFERENCES customers(id)) — لأن المكالمة قد تكون لجهة غير مسجلة
  contact_name: string | null              // ✅ contact_name
  phone_number: string | null              // ✅ phone_number
  sequence: number                         // ✅ sequence
  planned_time: string | null              // TIME
  estimated_duration_min: number           // ✅ estimated_duration_min
  priority: PlanPriority
  purpose: string | null
  purpose_type: PlanItemPurposeType | null
  status: PlanItemStatus
  callback_at: string | null
  actual_start_time: string | null
  actual_end_time: string | null
  activity_id: string | null
  skip_reason: string | null
  created_at: string
  updated_at: string
  // joined
  customer?: { id: string; name: string; code: string; phone: string | null } | null
  activity?: Pick<Activity, 'id' | 'outcome_type' | 'created_at'> | null
}

export interface CallPlanItemInput {
  customer_id?: string | null
  contact_name?: string | null
  phone_number?: string | null             // مطلوب إذا لم يكن customer_id (CHECK constraint)
  sequence: number                         // ✅ sequence
  planned_time?: string | null
  estimated_duration_min?: number
  priority?: PlanPriority
  purpose?: string | null
  purpose_type?: PlanItemPurposeType | null
}

// ─── Targets ───────────────────────────────────────────────────
// جدول targets — الأعمدة مطابقة 1:1 للـ schema (line 477-517)

export type TargetSplitBasis = 'historical_sales' | 'equal' | 'manual'

export interface Target {
  id: string
  type_id: string                          // ✅ type_id (لا target_type_id) → target_types(id)
  type_code: string                        // مُزامَن من target_type عبر trigger (sync_target_type_code)
  name: string
  description: string | null              // ✅ مضاف
  scope: TargetScope
  scope_id: string | null
  period: TargetPeriod                    // ✅ period ('monthly'|'quarterly'|'yearly'|'custom')
  period_start: string                    // DATE
  period_end: string                      // DATE
  target_value: number
  min_value: number | null
  stretch_value: number | null
  product_id: string | null              // ✅ فلتر منتج محدد
  category_id: string | null             // ✅ فلتر تصنيف محدد
  governorate_id: string | null          // ✅ فلتر محافظة
  city_id: string | null                 // ✅ فلتر مدينة
  area_id: string | null                 // ✅ فلتر منطقة
  dormancy_days: number | null           // ✅ أيام الخمول للفلتر بالعملاء غير النشطين
  filter_criteria: Record<string, any>   // JSONB NOT NULL DEFAULT '{}'
  parent_target_id: string | null        // ✅ للتسلسل الهرمي في التقسيم
  auto_split: boolean
  split_basis: TargetSplitBasis | null   // ✅ split_basis
  is_paused: boolean
  paused_at: string | null
  paused_reason: string | null           // ✅ مضاف
  assigned_by: string                    // ✅ assigned_by (لا created_by) → profiles(id)
  is_active: boolean
  notes: string | null                   // ✅ مضاف
  created_at: string
  updated_at: string
  // joined — type_id → target_types
  target_type?: Pick<TargetType, 'id' | 'name' | 'code' | 'unit' | 'category'>
  latest_progress?: TargetProgress | null
}

export interface TargetInput {
  type_id: string                          // ✅ type_id (لا target_type_id)
  name: string
  description?: string | null
  scope: TargetScope
  scope_id?: string | null
  period: TargetPeriod                    // ✅ مطلوب NOT NULL في DB
  period_start: string
  period_end: string
  target_value: number
  min_value?: number | null
  stretch_value?: number | null
  product_id?: string | null
  category_id?: string | null
  governorate_id?: string | null
  city_id?: string | null
  area_id?: string | null
  dormancy_days?: number | null
  filter_criteria?: Record<string, any>
  parent_target_id?: string | null
  auto_split?: boolean
  split_basis?: TargetSplitBasis | null
  notes?: string | null
}


/** قراءة فقط — يُحسب بواسطة recalculate_target_progress()
 *  أعمدة table (line 548): id, target_id, snapshot_date, achieved_value,
 *    achievement_pct, trend, last_calc_at, calc_details
 *  لا يوجد عمود created_at في هذا الجدول.
 */
export interface TargetProgress {
  id: string
  target_id: string
  snapshot_date: string
  achieved_value: number
  achievement_pct: number
  trend: TargetTrend | null               // nullable في DB (CHECK constraint بدون NOT NULL)
  last_calc_at: string | null
  calc_details: Record<string, any>      // ✅ calc_details JSONB مضاف
}

/** قراءة فقط — يُكتب حصراً بواسطة adjust_target() RPC */
export interface TargetAdjustment {
  id: string
  target_id: string
  field_changed: AdjustableField          // ✅ field_changed (لا field, لا type)
  old_value: string | null                 // TEXT في DB
  new_value: string | null                 // TEXT في DB
  reason: string | null                    // ✅ reason (لا business_reason)
  adjusted_by: string | null
  adjusted_at: string                      // ✅ adjusted_at (لا created_at)
  // joined
  adjusted_by_profile?: { id: string; full_name: string } | null
}

/**
 * مدخلات adjust_target() RPC — التوقيع الحقيقي من 21b (line 581):
 * p_target_id, p_field, p_new_value (TEXT), p_reason, p_user_id
 */
export interface AdjustTargetInput {
  p_target_id: string
  p_field: AdjustableField                 // ✅ p_field مطلوب
  p_new_value: string                      // ✅ TEXT (لا number) — RPC يحوّله حسب p_field
  p_reason: string                         // ✅ p_reason (لا p_business_reason)
  p_user_id: string                        // ✅ p_user_id مطلوب للـ SECURITY DEFINER check
}

// ─── View Row Types — مطابقة 1:1 للـ views الفعلية ────────────

/**
 * v_rep_performance (line 682-699 في 21b_activities_rls_engine.sql)
 * الأعمدة: employee_id, employee_name, branch_id, branch_name,
 *          period (month), visits_count, calls_count,
 *          orders_from_activities, sales_value, collection_value, active_customers
 */
export interface RepPerformanceRow {
  employee_id: string
  employee_name: string                    // ✅ employee_name (لا full_name)
  branch_id: string
  branch_name: string                      // ✅ branch_name
  period: string                           // ✅ period = DATE_TRUNC('month') (لا year/month منفصلتين)
  visits_count: number
  calls_count: number
  orders_from_activities: number           // ✅ orders_from_activities
  sales_value: number                      // ✅ sales_value (لا total_sales_amount)
  collection_value: number                 // ✅ collection_value
  active_customers: number                 // ✅ active_customers
}

/**
 * v_plan_daily_summary (line 707-729 في 21b_activities_rls_engine.sql)
 * الأعمدة: plan_module, id, employee_id, plan_date, plan_type,
 *          plan_status, total_items, completed_count, skipped_count,
 *          missed_count, completion_pct, pending_count, high_priority_pending
 */
export interface PlanDailySummaryRow {
  plan_module: 'visit' | 'call'            // ✅ plan_module
  id: string
  employee_id: string
  plan_date: string
  plan_type: string
  plan_status: PlanStatus
  total_items: number                      // ✅ total_items (total_customers OR total_calls)
  completed_count: number
  skipped_count: number
  missed_count: number
  completion_pct: number
  pending_count: number                    // ✅ pending_count
  high_priority_pending: number            // ✅ high_priority_pending
}

/**
 * v_target_status (line 738-760 في 21b_activities_rls_engine.sql)
 * الأعمدة: id, name, type_code, scope, scope_id,
 *          period_start, period_end, target_value, min_value, stretch_value,
 *          is_active, is_paused, achieved_value, achievement_pct, trend,
 *          last_calc_at, data_as_of, remaining_value, days_remaining, forecasted_value
 */
export interface TargetStatusRow {
  id: string
  name: string
  type_code: string                        // ✅ type_code (لا target_type_name)
  scope: TargetScope
  scope_id: string | null
  period_start: string
  period_end: string
  target_value: number
  min_value: number | null
  stretch_value: number | null
  is_active: boolean
  is_paused: boolean
  achieved_value: number | null
  achievement_pct: number | null
  trend: TargetTrend | null
  last_calc_at: string | null
  data_as_of: string | null                // ✅ data_as_of (= snapshot_date)
  remaining_value: number
  days_remaining: number
  forecasted_value: number | null          // ✅ forecasted_value
}
