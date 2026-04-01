// ============================================================
// Activities Module Types — Phase 21 + Phase 22 (Unified Target Engine)
// Maps to: supabase/migrations/21_activities_module_mvp.sql
//          supabase/migrations/21b_activities_rls_engine.sql
//          supabase/migrations/22a_target_schema.sql      ← NEW
//          supabase/migrations/22b_target_calc.sql        ← NEW
//          supabase/migrations/22c_target_payouts.sql     ← NEW
//          supabase/migrations/22d_payroll_sync.sql       ← NEW
//
// ⚠️ أسماء الأعمدة هنا مطابقة 1:1 للـ schema الفعلي في قاعدة البيانات.
// ============================================================

// ─── Enums / Literals ─────────────────────────────────────────

export type ActivityCategory = 'visit' | 'call' | 'task'

export type ActivityOutcome =
  | 'visited'
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

// ─── Phase 22: أنواع محرك المكافآت ────────────────────────────
// مطابق لـ 22a_target_schema.sql SECTION 1

/** نوع المكافأة — reward_type في جدول targets */
export type TargetRewardType = 'fixed' | 'percentage'

/** وعاء حساب المكافأة النسبية — reward_pool_basis */
export type TargetRewardPoolBasis = 'sales_value' | 'collection_value'

/** حالة استحقاق الصرف — target_reward_payouts.status */
export type TargetPayoutStatus = 'pending' | 'committed' | 'cancelled'

/** حقول التعديل المسموح بها عبر adjust_target() — مُحدَّثة بـ Phase 22 */
export type AdjustableField =
  // حقول Phase 21
  | 'target_value'
  | 'min_value'
  | 'stretch_value'
  | 'period_end'
  | 'is_paused'
  | 'is_active'
  | 'filter_criteria'
  // حقول Phase 22 — طبقة أ (قابلة للتعديل دائماً)
  | 'reward_base_value'
  | 'auto_payout'
  | 'payout_month_offset'
  // حقول Phase 22 — طبقة ب (مقيَّدة بعد أول committed)
  | 'reward_type'
  | 'reward_pool_basis'

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
  gps_lat: number | null
  gps_lng: number | null
  end_gps_lat: number | null
  end_gps_lng: number | null
  metadata: Record<string, unknown> | null
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

/** قراءة فقط — يُحسب بواسطة recalculate_target_progress()
 *  أعمدة table: id, target_id, snapshot_date, achieved_value,
 *    achievement_pct, trend, last_calc_at, calc_details
 *  لا يوجد عمود created_at في هذا الجدول.
 */
export interface TargetProgress {
  id: string
  target_id: string
  snapshot_date: string
  achieved_value: number
  achievement_pct: number
  trend: TargetTrend | null               // nullable في DB
  last_calc_at: string | null
  calc_details: Record<string, any>       // JSONB — يشمل تفاصيل الحساب
}

/** قراءة فقط — يُكتب حصراً بواسطة adjust_target() RPC
 *  أعمدة table: target_adjustments
 */
export interface TargetAdjustment {
  id: string
  target_id: string
  field_changed: AdjustableField          // ✅ field_changed (لا field, لا type)
  old_value: string | null                // TEXT في DB
  new_value: string | null                // TEXT في DB
  reason: string | null
  adjusted_by: string | null
  adjusted_at: string                     // ✅ adjusted_at (لا created_at)
  // joined
  adjusted_by_profile?: { id: string; full_name: string } | null
}


export interface Target {
  id: string
  type_id: string                          // → target_types(id)
  type_code: string                        // مُزامَن من trigger sync_target_type_code
  name: string
  description: string | null
  scope: TargetScope
  scope_id: string | null
  period: TargetPeriod
  period_start: string                     // DATE
  period_end: string                       // DATE
  target_value: number
  min_value: number | null
  stretch_value: number | null
  product_id: string | null
  category_id: string | null
  governorate_id: string | null
  city_id: string | null
  area_id: string | null
  dormancy_days: number | null             // أيام الخمول للفلتر
  filter_criteria: Record<string, any>     // JSONB — يشمل growth_pct لـ upgrade_value
  parent_target_id: string | null
  auto_split: boolean
  split_basis: TargetSplitBasis | null
  is_paused: boolean
  paused_at: string | null
  paused_reason: string | null
  assigned_by: string
  is_active: boolean
  notes: string | null
  // ★ Phase 22: حقول محرك المكافآت (22a_target_schema.sql SECTION 1)
  reward_type: TargetRewardType | null     // NULL = بدون مكافأة
  reward_base_value: number | null         // fixed: مبلغ ثابت | percentage: نسبة %
  reward_pool_basis: TargetRewardPoolBasis | null  // وعاء الحساب (للنسبية فقط)
  auto_payout: boolean                     // تفعيل الصرف الآلي عبر مسير الرواتب
  payout_month_offset: number              // إزاحة شهر الصرف (0=نفس شهر الهدف)
  created_at: string
  updated_at: string
  // joined
  target_type?: Pick<TargetType, 'id' | 'name' | 'code' | 'unit' | 'category'>
  latest_progress?: TargetProgress | null
  // ★ Phase 22: بيانات المكافأة المُدمجة (للواجهة التفصيلية)
  reward_tiers?: TargetRewardTier[]
  target_customers?: TargetCustomer[]
  reward_payouts?: TargetRewardPayout[]
}

export interface TargetInput {
  type_id: string
  name: string
  description?: string | null
  scope: TargetScope
  scope_id?: string | null
  period: TargetPeriod
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

// ─── Phase 22: شريحة مكافأة — target_reward_tiers ────────────
// مطابق لـ 22a_target_schema.sql SECTION 2

export interface TargetRewardTier {
  id: string
  target_id: string
  sequence: number                         // ترتيب الشريحة (1، 2، 3...)
  threshold_pct: number                    // نسبة الإنجاز المطلوبة (0–200)
  reward_pct: number                       // نسبة ما يُصرف من المكافأة (0–200)
  label: string | null                     // مثال: 'ممتاز'، 'جيد جداً'
  created_at: string
}

/** مدخلات شريحة عند الإنشاء عبر create_target_with_rewards() */
export interface TierInput {
  sequence?: number                        // اختياري — يُحسب تلقائياً
  threshold_pct: number                    // إلزامي: 0 < threshold_pct ≤ 200
  reward_pct: number                       // إلزامي: 0 < reward_pct ≤ 200
  label?: string                           // اسم الشريحة
}

// ─── Phase 22: عميل مستهدف — target_customers ─────────────────
// مطابق لـ 22a_target_schema.sql SECTION 3

export interface TargetCustomer {
  id: string
  target_id: string
  customer_id: string                      // → customers(id)
  baseline_value: number | null            // للـ upgrade_value: متوسط مشتريات المرجع
  baseline_category_count: number | null   // للـ category_spread: عدد التصنيفات المرجعي
  baseline_period_start: string | null     // DATE — بداية الفترة المرجعية
  baseline_period_end: string | null       // DATE — نهاية الفترة المرجعية
  created_at: string
  // joined
  customer?: {
    id: string
    name: string
    code: string
    phone: string | null
  }
}

/** مدخلات عميل مستهدف عند الإنشاء */
export interface TargetCustomerInput {
  customer_id: string
  baseline_value?: number                  // للـ upgrade_value
  baseline_category_count?: number         // للـ category_spread
  baseline_period_start?: string           // DATE
  baseline_period_end?: string             // DATE
}

// ─── Phase 22: استحقاق صرف مكافأة — target_reward_payouts ────
// مطابق لـ 22a_target_schema.sql SECTION 4

export interface TargetRewardPayout {
  id: string
  target_id: string
  employee_id: string                      // → hr_employees(id)
  period_id: string                        // → hr_payroll_periods(id)
  achievement_pct: number                  // نسبة الإنجاز عند التثبيت
  tier_reached: number | null              // رقم الشريحة المُحققة
  reward_pct: number | null                // نسبة المكافأة المُصرَّفة
  base_amount: number | null               // قيمة الـ pool المحسوبة
  payout_amount: number                    // المبلغ النهائي للمكافأة
  status: TargetPayoutStatus               // 'pending' | 'committed' | 'cancelled'
  adjustment_id: string | null             // → hr_payroll_adjustments(id)
  computed_at: string                      // TIMESTAMPTZ
  committed_at: string | null              // TIMESTAMPTZ
  notes: string | null
  // joined
  target?: Pick<Target, 'id' | 'name' | 'type_code'>
  period?: { id: string; name: string; year: number; month: number }
  employee?: { id: string; full_name: string }
}

// ─── Phase 22: مدخلات إنشاء الهدف الذري ──────────────────────
// مطابق لتوقيع create_target_with_rewards() في 22d_payroll_sync.sql
// الدالة الوحيدة المسموح بها لإنشاء الأهداف

export interface CreateTargetWithRewardsInput {
  // حقول الهدف الأساسية
  type_id: string
  name: string
  description?: string | null
  scope: TargetScope
  scope_id?: string | null
  period?: TargetPeriod
  period_start?: string                    // DATE — افتراضي: أول الشهر الحالي
  period_end?: string                      // DATE — افتراضي: آخر الشهر الحالي
  target_value?: number
  min_value?: number | null
  stretch_value?: number | null
  // فلاتر الهدف
  product_id?: string | null
  category_id?: string | null
  governorate_id?: string | null
  city_id?: string | null
  area_id?: string | null
  dormancy_days?: number | null
  /** JSONB — يشمل growth_pct (إلزامي لـ upgrade_value) */
  filter_criteria?: Record<string, any>
  notes?: string | null
  // ★ حقول المكافأة (Phase 22)
  reward_type?: TargetRewardType | null
  reward_base_value?: number | null
  reward_pool_basis?: TargetRewardPoolBasis | null
  /** إزاحة شهر الصرف: 0=شهر انتهاء الهدف، 1=الشهر التالي */
  payout_month_offset?: number
  /** شرائح المكافأة — إلزامية عند auto_payout=true */
  tiers?: TierInput[]
  /** العملاء المستهدفون — للأهداف upgrade_value/category_spread */
  customers?: TargetCustomerInput[]
  /** تفعيل الصرف الآلي — يتطلب شرائح وreward_type */
  auto_payout?: boolean
  p_user_id?: string                       // اختياري — للـ SECURITY DEFINER
}

// ─── Phase 22: مدخلات تعديل الهدف (محدَّثة) ─────────────────
// توقيع adjust_target() في 22c_target_payouts.sql

export interface AdjustTargetInput {
  p_target_id: string
  p_field: AdjustableField                 // الحقل المراد تعديله
  p_new_value: string                      // TEXT — RPC يحوّله حسب p_field
  p_reason: string                         // سبب التعديل (إلزامي)
  p_user_id: string                        // UUID للمستخدم المعتمِد
}

// ─── Phase 22: نماذج العرض للواجهة (View Layer) ───────────────

/**
 * بطاقة الهدف المختصرة — للقوائم وbreadcrumbs
 * مُشتَقة من: targets + target_progress (latest)
 */
export interface TargetListItem {
  id: string
  name: string
  type_code: string
  type_name: string
  scope: TargetScope
  scope_id: string | null
  scope_label: string | null               // اسم الموظف/الفرع/القسم
  period: TargetPeriod
  period_start: string
  period_end: string
  target_value: number
  achieved_value: number
  achievement_pct: number
  trend: TargetTrend | null
  is_active: boolean
  is_paused: boolean
  has_reward: boolean                      // reward_type IS NOT NULL
  reward_type?: TargetRewardType | null    // ★ Phase 22: نوع المكافأة للـ fallback
  auto_payout: boolean
  unit: TargetUnit
  estimated_reward?: number                // ★ Phase 22: للموظف
  // ★ Phase 22: معلومات الشريحة الحالية — تُحسب عند include_tiers
  current_tier_info?: TargetComputedMetrics['current_tier_info']
}

/**
 * تفاصيل الهدف الكاملة — للصفحة التفصيلية والمراجعة
 * يشمل كل حقول Target + المكافآت + التقدم
 */
export interface TargetDetailView {
  // بيانات الهدف الكاملة
  target: Target
  // بيانات التقدم (أحدث snapshot)
  progress: TargetProgress | null
  // ★ Phase 22: بيانات المكافأة
  reward_tiers: TargetRewardTier[]         // مرتبة تصاعدياً بـ sequence
  target_customers: TargetCustomer[]       // العملاء المستهدفون مع baselines
  // تاريخ التعديلات
  adjustments: TargetAdjustment[]
  // سجل الاستحقاقات (إذا كانت موجودة)
  payouts: TargetRewardPayout[]
  // بيانات محسوبة للواجهة
  computed: TargetComputedMetrics
}

/**
 * مقاييس محسوبة للواجهة — لا تُخزَّن في DB
 * تُحسب في طبقة الخدمة من calc_details JSONB
 */
export interface TargetComputedMetrics {
  remaining_value: number                  // target_value - achieved_value
  days_remaining: number                   // أيام متبقية لانتهاء الهدف
  daily_pace_required: number              // المطلوب يومياً لتحقيق الهدف
  forecasted_achievement: number           // تقدير الإنجاز بنهاية الفترة
  is_on_track: boolean
  current_tier_info: {
    reached_tier: number | null            // رقم الشريحة المحققة حالياً
    reached_label: string | null           // اسم الشريحة
    next_tier: number | null               // رقم الشريحة التالية
    next_threshold_pct: number | null      // نسبة الإنجاز المطلوبة للشريحة التالية
    estimated_reward: number | null        // تقدير قيمة المكافأة عند الإنجاز الحالي
  } | null
}

/**
 * ملخص مكافأة الهدف — لبطاقة المكافأة في الواجهة
 * يجمع كل ما يتعلق بالمكافأة في كائن واحد
 */
export interface TargetRewardSummary {
  target_id: string
  reward_type: TargetRewardType | null
  reward_base_value: number | null
  reward_pool_basis: TargetRewardPoolBasis | null
  auto_payout: boolean
  payout_month_offset: number
  tiers: TargetRewardTier[]
  // آخر استحقاق مُثبَّت
  latest_payout: TargetRewardPayout | null
  // تاريخ الاستحقاقات كاملاً
  payout_history: TargetRewardPayout[]
  // ★ تقدير المكافأة المتوقعة بناءً على الإنجاز الحالي
  estimated_payout: number | null
  is_payout_locked: boolean                // صحيح عند وجود committed payout
}

// ─── Phase 22: فلاتر الاستعلام ───────────────────────────────

export interface TargetFilters {
  scope?: TargetScope
  scope_id?: string
  type_code?: string
  is_active?: boolean
  is_paused?: boolean
  period?: TargetPeriod
  has_reward?: boolean                     // هل لديه مكافأة مُعرَّفة
  auto_payout?: boolean
  payout_status?: TargetPayoutStatus       // فلتر على استحقاقات الصرف
  employee_id?: string                     // للتصفية على الموظف (فردي)
  branch_id?: string
  date_from?: string
  date_to?: string
  include_tiers?: boolean                  // ★ Phase 22: لجلب الشرائح وحساب المكافأة المتوقعة
}

export interface PayoutFilters {
  period_id?: string
  employee_id?: string
  target_id?: string
  status?: TargetPayoutStatus
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

// ─── Visit Checklists — استبيانات الزيارات والمكالمات ──────────
// Maps to: supabase/migrations/21d_visit_checklists.sql

export type ChecklistQuestionType =
  | 'text'           // حقل نص حر
  | 'number'         // رقم (كمية، سعر، إلخ)
  | 'yes_no'         // نعم أو لا (toggle)
  | 'single_choice'  // اختيار واحد من قائمة
  | 'multi_choice'   // اختيار متعدد من قائمة
  | 'rating'         // تقييم (1-5 نجوم)
  | 'photo'          // التقاط صورة

export interface ChecklistTemplate {
  id: string
  name: string
  description: string | null
  category: ActivityCategory            // 'visit' | 'call' | 'task'
  purpose_type: PlanItemPurposeType | null  // null = كل الأغراض
  is_mandatory: boolean
  is_active: boolean
  sort_order: number
  created_by: string
  created_at: string
  updated_at: string
  // joined
  questions?: ChecklistQuestion[]
}

export interface ChecklistQuestion {
  id: string
  template_id: string
  question_text: string
  question_type: ChecklistQuestionType
  options: string[] | { label: string; value: string }[]
  default_value: string | null
  hint_text: string | null
  min_value: number | null
  max_value: number | null
  is_required: boolean
  sort_order: number
  created_at: string
}

export interface ChecklistResponse {
  id: string
  activity_id: string
  template_id: string
  question_id: string
  answer_value: string | null
  answer_json: any | null
  created_at: string
  // joined
  question?: Pick<ChecklistQuestion, 'id' | 'question_text' | 'question_type'>
}

export interface ChecklistTemplateInput {
  name: string
  description?: string | null
  category: ActivityCategory
  purpose_type?: PlanItemPurposeType | null
  is_mandatory?: boolean
  is_active?: boolean
  sort_order?: number
}

export interface ChecklistQuestionInput {
  template_id?: string          // يُمرر عند الإنشاء المستقل
  question_text: string
  question_type: ChecklistQuestionType
  options?: any[]
  default_value?: string | null
  hint_text?: string | null
  min_value?: number | null
  max_value?: number | null
  is_required?: boolean
  sort_order?: number
}

export interface ChecklistResponseInput {
  activity_id: string
  template_id: string
  question_id: string
  answer_value?: string | null
  answer_json?: any | null
}
