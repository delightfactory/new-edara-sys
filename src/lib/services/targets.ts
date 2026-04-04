// ============================================================
// targets.ts — طبقة خدمة محرك الأهداف الموحد (Phase 22)
// Maps to: 22a_target_schema.sql
//          22b_target_calc.sql
//          22c_target_payouts.sql
//          22d_payroll_sync.sql
//
// ⚠️ ممنوع إنشاء هدف عبر INSERT مباشر — استخدم createTargetWithRewards()
// ⚠️ ممنوع تعديل حقول حساسة مباشرةً — استخدم adjustTarget()
// ============================================================

import { supabase } from '@/lib/supabase/client'
import { getAuthUserId } from '@/lib/services/_get-user-id'
import type {
  // Phase 21 (موجودة)
  Target, TargetInput, TargetProgress, TargetAdjustment,
  AdjustTargetInput, TargetStatusRow,
  // Phase 22 (جديدة)
  TargetRewardTier, TargetCustomer, TargetRewardPayout,
  CreateTargetWithRewardsInput, TierInput, TargetCustomerInput,
  TargetRewardType, TargetRewardPoolBasis, TargetPayoutStatus,
  TargetListItem, TargetDetailView, TargetRewardSummary,
  TargetComputedMetrics, TargetFilters, PayoutFilters,
} from '@/lib/types/activities'

// ============================================================
// Helpers
// ============================================================



function sanitize<T extends Record<string, any>>(input: T): T {
  const cleaned = { ...input } as any
  for (const key of Object.keys(cleaned)) {
    if (cleaned[key] === '') cleaned[key] = null
  }
  return cleaned as T
}

/**
 * PostgREST يُعيد latest_progress من target_progress كـ array دائما،
 * حتى مع .limit(1) على referencedTable.
 * هذا الـ helper يُحوّل [] | [obj] إلى TargetProgress | null.
 *
 * المكان الوحيد لهذا التحويل — لا يجب أن يـ exist في consumers.
 */
function normalizeLatestProgress(raw: unknown): TargetProgress | null {
  if (!raw) return null
  if (Array.isArray(raw)) return raw.length > 0 ? (raw[0] as TargetProgress) : null
  return raw as TargetProgress
}

// ============================================================
// SELECT fragments
// ============================================================

/** الحقول الكاملة للهدف شاملاً حقول Phase 22 */
const TARGET_FULL_SELECT = `
  *,
  target_type:target_types!targets_type_id_fkey(id, name, code, unit, category)
`

/** حقول الشرائح — مرتبة تصاعدياً */
const TIERS_SELECT = `id, target_id, sequence, threshold_pct, reward_pct, label, created_at`

/** حقول العملاء المستهدفين مع بيانات العميل */
const CUSTOMERS_SELECT = `
  id, target_id, customer_id, baseline_value, baseline_category_count,
  baseline_period_start, baseline_period_end, created_at,
  customer:customers(id, name, code, phone)
`

/** حقول الاستحقاقات مع بيانات الفترة والموظف */
const PAYOUT_SELECT = `
  id, target_id, employee_id, period_id,
  achievement_pct, tier_reached, reward_pct, base_amount, payout_amount,
  status, adjustment_id, computed_at, committed_at, notes,
  period:hr_payroll_periods(id, name, year, month),
  employee:hr_employees(id, full_name)
`

// ============================================================
// ★ SECTION 1: التحقق على مستوى الخدمة (Service-Layer Validation)
// ============================================================

export interface RewardValidationError {
  field: string
  message: string
}

import { validateRewardConfig } from '@/lib/utils/rewardRules'

/**
 * تحقق موازٍ للمدخلات قبل إرسالها للـ RPC
 * يُكمِّل قيود DB ولا يُلغيها — يُعطي رسائل خطأ واضحة للمستخدم
 * يُطابق حرفياً is_valid_reward_config() في قاعدة البيانات.
 */
export function validateCreateTargetInput(
  input: CreateTargetWithRewardsInput,
  typeCode: string,
  typeCategory: string
): RewardValidationError[] {
  const errors: RewardValidationError[] = []

  // 1. upgrade_value يتطلب growth_pct
  if (typeCode === 'upgrade_value') {
    const growthPct = input.filter_criteria?.growth_pct
    if (!growthPct || Number(growthPct) <= 0) {
      errors.push({
        field: 'filter_criteria.growth_pct',
        message: 'نسبة النمو المطلوبة (growth_pct) إلزامية ويجب أن تكون أكبر من صفر',
      })
    }
  }

  // 2. التحقق من اتساق reward config — يُطابق is_valid_reward_config() حرفياً
  const rewardConfigError = validateRewardConfig(
    typeCategory,
    typeCode,
    (input.reward_type || null) as any,
    (input.reward_pool_basis || null) as any
  )
  if (rewardConfigError) {
    errors.push({ field: 'reward_pool_basis', message: rewardConfigError })
  }

  // 3. reward_base_value موجب إذا كان reward_type محدداً
  if (input.reward_type && (!input.reward_base_value || input.reward_base_value <= 0)) {
    errors.push({
      field: 'reward_base_value',
      message: 'قيمة المكافأة يجب أن تكون موجبة عند تحديد نوع مكافأة',
    })
  }

  // 4. auto_payout يتطلب شرائح + reward_type
  if (input.auto_payout) {
    if (!input.reward_type) {
      errors.push({ field: 'reward_type', message: 'الصرف التلقائي يتطلب تحديد نوع المكافأة' })
    }
    if (!input.tiers || input.tiers.length === 0) {
      errors.push({ field: 'tiers', message: 'الصرف التلقائي يتطلب شريحة مكافأة واحدة على الأقل' })
    }
  }

  // 5. ترتيب الشرائح: كل شريحة يجب أن تكون أعلى من السابقة
  if (input.tiers && input.tiers.length > 0) {
    const sorted = [...input.tiers].sort((a, b) => a.threshold_pct - b.threshold_pct)
    for (let i = 1; i < sorted.length; i++) {
      if (sorted[i].threshold_pct === sorted[i - 1].threshold_pct) {
        errors.push({
          field: `tiers[${i}].threshold_pct`,
          message: `نسب الإنجاز في الشرائح يجب أن تكون مختلفة`,
        })
        break
      }
    }
  }

  // 6. target_customers مطلوب لـ upgrade_value و category_spread
  if (['upgrade_value', 'category_spread'].includes(typeCode) && (!input.customers || input.customers.length === 0)) {
    errors.push({
      field: 'customers',
      message: `هدف ${typeCode} يتطلب تحديد العملاء المستهدفين مع بيانات الفترة المرجعية`,
    })
  }


  // 9. baseline_value إلزامي لـ upgrade_value
  if (typeCode === 'upgrade_value' && input.customers) {
    const missingBaseline = input.customers.some(c => !c.baseline_value || c.baseline_value <= 0)
    if (missingBaseline) {
      errors.push({
        field: 'customers[].baseline_value',
        message: 'هدف رفع القيمة يتطلب قيمة مرجعية موجبة لكل عميل مستهدف',
      })
    }
  }

  return errors
}

// ============================================================
// ★ SECTION 2: إنشاء الهدف الذري (الطريق الوحيد المسموح)
// ============================================================

/**
 * إنشاء هدف مع شرائح وعملاء في عملية ذرية واحدة
 * يستخدم create_target_with_rewards() RPC
 * ⚠️ هذه الدالة هي الوحيدة المسموح بها لإنشاء الأهداف
 */
export async function createTargetWithRewards(
  input: CreateTargetWithRewardsInput
): Promise<string> {
  const userId = await getAuthUserId()

  // [P2 FIX] جلب معلومات نوع الهدف للتحقق الموازي
  const { data: typeData, error: typeError } = await supabase
    .from('target_types')
    .select('code, category')
    .eq('id', input.type_id)
    .single()
  if (typeError) throw typeError

  const validationErrors = validateCreateTargetInput(
    input,
    typeData.code,
    typeData.category
  )
  if (validationErrors.length > 0) {
    const messages = validationErrors.map(e => `[${e.field}] ${e.message}`).join('\n')
    throw new Error(`أخطاء في مدخلات الهدف:\n${messages}`)
  }

  const { data, error } = await supabase.rpc('create_target_with_rewards', {
    p_type_id:            input.type_id,
    p_name:               input.name,
    p_description:        input.description ?? null,
    p_scope:              input.scope,
    p_scope_id:           input.scope_id ?? null,
    p_period:             input.period ?? 'monthly',
    p_period_start:       input.period_start ?? null,
    p_period_end:         input.period_end ?? null,
    p_target_value:       input.target_value ?? 0,
    p_min_value:          input.min_value ?? null,
    p_stretch_value:      input.stretch_value ?? null,
    p_product_id:         input.product_id ?? null,
    p_category_id:        input.category_id ?? null,
    p_governorate_id:     input.governorate_id ?? null,
    p_city_id:            input.city_id ?? null,
    p_area_id:            input.area_id ?? null,
    p_dormancy_days:      input.dormancy_days ?? null,
    p_filter_criteria:    input.filter_criteria ?? {},
    p_notes:              input.notes ?? null,
    // حقول المكافأة (Phase 22)
    p_reward_type:        input.reward_type ?? null,
    p_reward_base_value:  input.reward_base_value ?? null,
    p_reward_pool_basis:  input.reward_pool_basis ?? null,
    p_payout_month_offset: input.payout_month_offset ?? 0,
    p_tiers:              input.tiers ?? [],
    p_customers:          input.customers ?? [],
    p_auto_payout:        input.auto_payout ?? false,
    p_user_id:            input.p_user_id ?? userId,
  })

  if (error) throw error
  return data as string  // UUID للهدف المنشأ
}

// ============================================================
// ★ SECTION 3: قراءة الأهداف (مع الحقول الجديدة)
// ============================================================

/** Query builder داخلي للأهداف */
function buildTargetsQuery(filters?: TargetFilters) {
  let selectCols = TARGET_FULL_SELECT + ', latest_progress:target_progress(id, snapshot_date, achieved_value, achievement_pct, trend, last_calc_at, calc_details)'
  if (filters?.include_tiers) {
    selectCols += ', reward_tiers:target_reward_tiers(id, sequence, threshold_pct, reward_pct, label, created_at)'
  }

  let q = supabase
    .from('targets')
    .select(selectCols)

  if (filters?.scope)       q = q.eq('scope', filters.scope)
  if (filters?.scope_id)    q = q.eq('scope_id', filters.scope_id)
  if (filters?.type_code)   q = q.eq('type_code', filters.type_code)
  if (filters?.is_active !== undefined)  q = q.eq('is_active', filters.is_active)
  if (filters?.is_paused !== undefined)  q = q.eq('is_paused', filters.is_paused)
  if (filters?.period)      q = q.eq('period', filters.period)
  if (filters?.has_reward !== undefined) {
    if (filters.has_reward) q = q.not('reward_type', 'is', null)
    else                    q = q.is('reward_type', null)
  }
  if (filters?.auto_payout !== undefined) q = q.eq('auto_payout', filters.auto_payout)
  if (filters?.employee_id) q = q.eq('scope_id', filters.employee_id).eq('scope', 'individual')
  if (filters?.branch_id)   q = q.eq('scope_id', filters.branch_id).eq('scope', 'branch')
  if (filters?.date_from)   q = q.gte('period_start', filters.date_from)
  if (filters?.date_to)     q = q.lte('period_end', filters.date_to)

  return q
}

/**
 * جلب قائمة الأهداف مع أحدث snapshot للتقدم
 * يشمل الحقول الجديدة: reward_type, reward_base_value, auto_payout, payout_month_offset
 *
 * ملاحظة: فلتر payout_status يستلزم جلب target_ids مسبقاً من target_reward_payouts
 * لأن Supabase لا يدعم filter على جدول مُضمَّن في select بدون PostgREST view
 */
export async function getTargets(
  filters?: TargetFilters,
  pagination?: { page?: number; pageSize?: number }
): Promise<{ data: Target[]; count: number; page: number; pageSize: number; totalPages: number }> {
  const page     = pagination?.page ?? 1
  const pageSize = pagination?.pageSize ?? 20
  const from     = (page - 1) * pageSize

  // payout_status: يستلزم pre-fetch لأن Supabase لا يدعم
  //   filter على جدول مُضمَّن (target_reward_payouts) مباشرة
  let targetIdFilter: string[] | null = null
  if (filters?.payout_status) {
    const { data: payoutRows, error: payoutErr } = await supabase
      .from('target_reward_payouts')
      .select('target_id')
      .eq('status', filters.payout_status)
    if (payoutErr) throw payoutErr
    // إذا لم توجد نتائج → لا أهداف تطابق الفلتر
    targetIdFilter = (payoutRows ?? []).map(r => r.target_id)
    if (targetIdFilter.length === 0) {
      return { data: [], count: 0, page, pageSize, totalPages: 0 }
    }
  }

  let q = buildTargetsQuery(filters)
    .order('created_at', { ascending: false })
    .range(from, from + pageSize - 1)
    .limit(1, { referencedTable: 'target_progress' })

  // تطبيق فلتر payout_status عبر .in() على الـ IDs المُجلَبة
  if (targetIdFilter !== null) {
    q = q.in('id', targetIdFilter)
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error, count } = await q.returns<any[]>()

  if (error) throw error

  // تطبيع latest_progress: PostgREST يُعيد array دائماً حتى مع .limit(1) على referencedTable
  // نحوّلها إلى TargetProgress | null في طبقة الخدمة قبل تسليم البيانات للواجهة
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const normalized: Target[] = ((data ?? []) as any[]).map((t: any) => ({
    ...t,
    latest_progress: normalizeLatestProgress(t.latest_progress),
  })) as unknown as Target[]

  return {
    data: normalized,
    count: count ?? 0,
    page,
    pageSize,
    totalPages: Math.ceil((count ?? 0) / pageSize),
  }
}

/**
 * جلب هدف واحد كامل مع كل بياناته
 * يُعيد TargetDetailView الجاهز للواجهة
 */
export async function getTargetDetail(id: string): Promise<TargetDetailView> {
  const [targetRes, progressRes, tiersRes, customersRes, adjustmentsRes, payoutsRes] =
    await Promise.all([
      supabase
        .from('targets')
        .select(TARGET_FULL_SELECT)
        .eq('id', id)
        .single(),
      supabase
        .from('target_progress')
        .select('*')
        .eq('target_id', id)
        .order('snapshot_date', { ascending: false })
        .limit(1)
        .single(),
      // ★ شرائح المكافأة (Phase 22)
      supabase
        .from('target_reward_tiers')
        .select(TIERS_SELECT)
        .eq('target_id', id)
        .order('sequence', { ascending: true }),
      // ★ العملاء المستهدفون (Phase 22)
      supabase
        .from('target_customers')
        .select(CUSTOMERS_SELECT)
        .eq('target_id', id)
        .order('created_at'),
      // تاريخ التعديلات
      supabase
        .from('target_adjustments')
        .select('*, adjusted_by_profile:profiles!target_adjustments_adjusted_by_fkey(id, full_name)')
        .eq('target_id', id)
        .order('adjusted_at', { ascending: false }),
      // ★ سجل الاستحقاقات (Phase 22)
      supabase
        .from('target_reward_payouts')
        .select(PAYOUT_SELECT)
        .eq('target_id', id)
        .order('computed_at', { ascending: false }),
    ])

  if (targetRes.error) throw targetRes.error

  const target  = targetRes.data as Target
  const progress = progressRes.error ? null : progressRes.data as TargetProgress
  const tiers    = (tiersRes.data ?? []) as TargetRewardTier[]
  const customers = (customersRes.data ?? []) as unknown as TargetCustomer[]
  const adjustments = (adjustmentsRes.data ?? []) as TargetAdjustment[]
  const payouts  = (payoutsRes.data ?? []) as unknown as TargetRewardPayout[]

  return {
    target,
    progress,
    reward_tiers: tiers,
    target_customers: customers,
    adjustments,
    payouts,
    computed: buildComputedMetrics(target, progress, tiers),
  }
}

// ============================================================
// ★ SECTION 4: قراءة الشرائح — target_reward_tiers
// ============================================================

/**
 * جلب شرائح مكافأة هدف محدد
 * مرتبة تصاعدياً بـ sequence
 */
export async function getTargetTiers(targetId: string): Promise<TargetRewardTier[]> {
  const { data, error } = await supabase
    .from('target_reward_tiers')
    .select(TIERS_SELECT)
    .eq('target_id', targetId)
    .order('sequence', { ascending: true })
  if (error) throw error
  return (data ?? []) as TargetRewardTier[]
}

// ============================================================
// ★ SECTION 5: قراءة العملاء المستهدفين — target_customers
// ============================================================

/**
 * جلب العملاء المستهدفين في هدف
 * مع بيانات كل عميل من جدول customers
 */
export async function getTargetCustomers(targetId: string): Promise<TargetCustomer[]> {
  const { data, error } = await supabase
    .from('target_customers')
    .select(CUSTOMERS_SELECT)
    .eq('target_id', targetId)
    .order('created_at')
  if (error) throw error
  return (data ?? []) as unknown as TargetCustomer[]
}

// ============================================================
// ★ SECTION 6: قراءة استحقاقات الصرف — target_reward_payouts
// ============================================================

/**
 * جلب استحقاقات صرف المكافآت مع فلاتر متعددة
 * يشمل: target_id، employee_id، period_id، status
 */
export async function getTargetPayouts(filters?: PayoutFilters): Promise<TargetRewardPayout[]> {
  let q = supabase
    .from('target_reward_payouts')
    .select(PAYOUT_SELECT)
    .order('computed_at', { ascending: false })

  if (filters?.period_id)   q = q.eq('period_id', filters.period_id)
  if (filters?.employee_id) q = q.eq('employee_id', filters.employee_id)
  if (filters?.target_id)   q = q.eq('target_id', filters.target_id)
  if (filters?.status)      q = q.eq('status', filters.status)

  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as unknown as TargetRewardPayout[]
}

/**
 * جلب ملخص مكافأة هدف محدد
 * يجمع الشرائح + الاستحقاقات + حالة القفل
 */
export async function getTargetRewardSummary(targetId: string): Promise<TargetRewardSummary> {
  const [targetRes, tiersRes, payoutsRes, progressRes] = await Promise.all([
    supabase.from('targets').select('reward_type, reward_base_value, reward_pool_basis, auto_payout, payout_month_offset').eq('id', targetId).single(),
    supabase.from('target_reward_tiers').select(TIERS_SELECT).eq('target_id', targetId).order('sequence'),
    supabase.from('target_reward_payouts').select(PAYOUT_SELECT).eq('target_id', targetId).order('computed_at', { ascending: false }),
    // [P1 FIX] جلب achieved_value أيضاً لتمريره كـ poolValue للمكافآت النسبية
    supabase.from('target_progress').select('achievement_pct, achieved_value').eq('target_id', targetId).order('snapshot_date', { ascending: false }).limit(1).single(),
  ])

  if (targetRes.error) throw targetRes.error

  const t = targetRes.data as Pick<Target, 'reward_type' | 'reward_base_value' | 'reward_pool_basis' | 'auto_payout' | 'payout_month_offset'>
  const tiers   = (tiersRes.data ?? []) as TargetRewardTier[]
  const payouts = (payoutsRes.data ?? []) as unknown as TargetRewardPayout[]
  const latestPayout = payouts[0] ?? null
  const isLocked = payouts.some(p => p.status === 'committed')

  // [P1 FIX] تقدير المكافأة بناءً على الإنجاز الحالي
  // achieved_value = pool للنسبية (sales_value أو collection_value حسب reward_pool_basis)
  const currentPct    = progressRes.error ? 0 : (progressRes.data?.achievement_pct ?? 0)
  const achievedValue = progressRes.error ? 0 : (progressRes.data?.achieved_value ?? 0)
  const estimated = estimateReward(t, tiers, currentPct, achievedValue)

  return {
    target_id:          targetId,
    reward_type:        t.reward_type,
    reward_base_value:  t.reward_base_value,
    reward_pool_basis:  t.reward_pool_basis,
    auto_payout:        t.auto_payout,
    payout_month_offset: t.payout_month_offset,
    tiers,
    latest_payout:      latestPayout,
    payout_history:     payouts,
    estimated_payout:   estimated,
    is_payout_locked:   isLocked,
  }
}

// ============================================================
// ★ SECTION 7: تعديل الهدف عبر المسار الرسمي
// ============================================================

/**
 * تعديل حقل في الهدف عبر adjust_target() RPC
 * يدعم الحقول الجديدة: reward_type, reward_base_value, auto_payout, payout_month_offset
 * ⚠️ الحقول المقيَّدة (طبقة ب) لا يمكن تعديلها بعد أول committed payout
 */
export async function adjustTarget(input: AdjustTargetInput): Promise<void> {
  const { error } = await supabase.rpc('adjust_target', {
    p_target_id: input.p_target_id,
    p_field:     input.p_field,
    p_new_value: input.p_new_value,      // TEXT — RPC يحوِّل للنوع المناسب
    p_reason:    input.p_reason,
    p_user_id:   input.p_user_id,
  })
  if (error) throw error
}

/**
 * تعديل دُفعة من حقول الهدف (طبقة أ فقط — حقول آمنة)
 * كل تعديل يُنفَّذ منفصلاً عبر adjust_target() للحفاظ على سجل التدقيق
 */
export async function adjustTargetBatch(
  targetId: string,
  fields: Partial<Pick<Target, 'reward_type' | 'reward_pool_basis' | 'reward_base_value' | 'auto_payout' | 'payout_month_offset' | 'target_value' | 'min_value' | 'stretch_value' | 'period_end' | 'is_paused' | 'is_active' | 'filter_criteria'>>,
  reason: string,
  userId: string
): Promise<void> {
  const entries = Object.entries(fields).filter(([, v]) => v !== undefined)
  for (const [field, value] of entries) {
    await adjustTarget({
      p_target_id: targetId,
      p_field:     field as any,
      p_new_value: String(value),
      p_reason:    reason,
      p_user_id:   userId,
    })
  }
}

// ============================================================
// ★ SECTION 8: تثبيت المكافآت يدوياً (للإدارة)
// ============================================================

/**
 * طلب تثبيت مكافآت فترة راتب محددة
 * يستدعي prepare_target_reward_payouts() RPC
 * ⚠️ يتطلب صلاحية hr.payroll.read أو targets.read_all
 */
export async function prepareTargetRewardPayouts(periodId: string): Promise<void> {
  const { error } = await supabase.rpc('prepare_target_reward_payouts', {
    p_period_id: periodId,
  })
  if (error) throw error
}

/**
 * إعادة حساب تقدم هدف يدوياً
 * يستدعي recalculate_target_progress() RPC
 */
export async function recalculateTargetProgress(targetId: string, snapshotDate?: string): Promise<void> {
  const { error } = await supabase.rpc('recalculate_target_progress', {
    p_target_id:    targetId,
    p_snapshot_date: snapshotDate ?? new Date().toISOString().split('T')[0],
  })
  if (error) throw error
}

// ============================================================
// ★ SECTION 9: نماذج القراءة للواجهة (View Models)
// ============================================================

/**
 * بناء قائمة بطاقات مختصرة للأهداف
 * تُستخدَم في شاشات القوائم وبطاقات الداشبورد
 */
export function buildTargetListItems(
  targets: Target[],
  scopeLabels?: Record<string, string>  // scope_id → display name
): TargetListItem[] {
  return targets.map(t => {
    // latest_progress مضمون الآن أن يكون TargetProgress | null بعد normalizeLatestProgress في getTargets
    const progress    = (t.latest_progress ?? null) as TargetProgress | null
    const rewardTiers = ((t as any).reward_tiers ?? []) as TargetRewardTier[]
    return {
      id:              t.id,
      name:            t.name,
      type_code:       t.type_code,
      type_name:       t.target_type?.name ?? t.type_code,
      scope:           t.scope,
      scope_id:        t.scope_id,
      scope_label:     scopeLabels?.[t.scope_id ?? ''] ?? null,
      period:          t.period,
      period_start:    t.period_start,
      period_end:      t.period_end,
      target_value:    t.target_value,
      achieved_value:  progress?.achieved_value ?? 0,
      achievement_pct: progress?.achievement_pct ?? 0,
      trend:           progress?.trend ?? null,
      is_active:       t.is_active,
      is_paused:       t.is_paused,
      has_reward:      t.reward_type !== null,            // ★ Phase 22
      reward_type:     t.reward_type,                     // ★ Phase 22 fallback
      auto_payout:     t.auto_payout,                    // ★ Phase 22
      unit:            t.target_type?.unit ?? 'currency',
      estimated_reward: rewardTiers.length > 0
        ? buildCurrentTierInfo(
            progress?.achievement_pct ?? 0,
            t,
            rewardTiers,
            progress?.achieved_value ?? 0
          )?.estimated_reward ?? undefined
        : undefined,
      current_tier_info: rewardTiers.length > 0
        ? buildCurrentTierInfo(
            progress?.achievement_pct ?? 0,
            t,
            rewardTiers,
            progress?.achieved_value ?? 0
          )
        : undefined,
    }
  })
}

/**
 * بناء مقاييس محسوبة للواجهة من بيانات الهدف والتقدم والشرائح
 */
export function buildComputedMetrics(
  target: Target,
  progress: TargetProgress | null,
  tiers: TargetRewardTier[]
): TargetComputedMetrics {
  const achieved     = progress?.achieved_value ?? 0
  const remaining    = Math.max(0, target.target_value - achieved)
  const today        = new Date()
  const endDate      = new Date(target.period_end)
  const daysLeft     = Math.max(0, Math.ceil((endDate.getTime() - today.getTime()) / 86_400_000))
  const dailyPace    = daysLeft > 0 ? remaining / daysLeft : 0
  const currentPct   = progress?.achievement_pct ?? 0

  // تقدير الإنجاز بنهاية الفترة
  const startDate    = new Date(target.period_start)
  const totalDays    = Math.ceil((endDate.getTime() - startDate.getTime()) / 86_400_000)
  const elapsedDays  = Math.max(0, totalDays - daysLeft)
  const dailyCurrent = elapsedDays > 0 ? achieved / elapsedDays : 0
  const forecasted   = dailyCurrent * totalDays

  // [P1 FIX] تمرير achieved كـ poolValue لحساب مكافآت النسبية بشكل صحيح
  // achieved_value = إجمالي المبيعات أو التحصيلات (حسب reward_pool_basis) — هو الوعاء الفعلي
  const tierInfo = tiers.length > 0
    ? buildCurrentTierInfo(currentPct, target, tiers, achieved)
    : null

  return {
    remaining_value:        remaining,
    days_remaining:         daysLeft,
    daily_pace_required:    dailyPace,
    forecasted_achievement: forecasted,
    is_on_track:            forecasted >= target.target_value,
    current_tier_info:      tierInfo,
  }
}

/** حساب معلومات الشريحة الحالية */
function buildCurrentTierInfo(
  currentPct: number,
  target: Target,
  tiers: TargetRewardTier[],
  achievedValue?: number  // [P1 FIX] poolValue للمكافآت النسبية
): TargetComputedMetrics['current_tier_info'] {
  const sortedTiers = [...tiers].sort((a, b) => a.threshold_pct - b.threshold_pct)

  // الشريحة المحققة = أعلى شريحة تحقق عتبتها
  const reachedTiers = sortedTiers.filter(t => currentPct >= t.threshold_pct)
  const reached = reachedTiers[reachedTiers.length - 1] ?? null

  // الشريحة التالية
  const nextTierIndex = reached
    ? sortedTiers.findIndex(t => t.id === reached.id) + 1
    : 0
  const nextTier = sortedTiers[nextTierIndex] ?? null

  // [P1 FIX] تقدير قيمة المكافأة مع تمرير achievedValue كـ pool للنسبية
  const estimated = reached ? estimateReward(target, tiers, currentPct, achievedValue) : null

  return {
    reached_tier:        reached?.sequence ?? null,
    reached_label:       reached?.label ?? null,
    next_tier:           nextTier?.sequence ?? null,
    next_threshold_pct:  nextTier?.threshold_pct ?? null,
    estimated_reward:    estimated,
  }
}

/**
 * تقدير قيمة المكافأة بناءً على نسبة الإنجاز الحالية
 * منطق مطابق بالضبط لـ 22c_target_payouts.sql calc_target_pool_value()
 */
export function estimateReward(
  targetOrReward: Pick<Target, 'reward_type' | 'reward_base_value' | 'reward_pool_basis'>,
  tiers: TargetRewardTier[],
  currentPct: number,
  poolValue?: number  // يختياري: لحساب النسبية
): number | null {
  const { reward_type, reward_base_value } = targetOrReward
  if (!reward_type || !reward_base_value || reward_base_value <= 0) return null
  if (tiers.length === 0) return null

  // أعلى شريحة محققة
  const sortedTiers = [...tiers].sort((a, b) => a.threshold_pct - b.threshold_pct)
  const reachedTiers = sortedTiers.filter(t => currentPct >= t.threshold_pct)
  const reached = reachedTiers[reachedTiers.length - 1]
  if (!reached) return null

  if (reward_type === 'fixed') {
    return reward_base_value * (reached.reward_pct / 100)
  } else {
    // percentage: reward_base_value = نسبة % × pool
    const pool = poolValue ?? 0
    return pool * (reward_base_value / 100) * (reached.reward_pct / 100)
  }
}

// ============================================================
// ★ SECTION 10: نقطة واحدة للتقدم — تاريخ snapshots
// ============================================================

/**
 * جلب تاريخ التقدم الكامل لهدف
 * للرسوم البيانية وشاشة التتبع
 */
export async function getTargetProgressHistory(
  targetId: string,
  limit: number = 90
): Promise<TargetProgress[]> {
  const { data, error } = await supabase
    .from('target_progress')
    .select('*')
    .eq('target_id', targetId)
    .order('snapshot_date', { ascending: true })
    .limit(limit)
  if (error) throw error
  return (data ?? []) as TargetProgress[]
}

// ============================================================
// ★ SECTION 11: جلب أهداف الموظف الفردي
// ============================================================

/**
 * جلب أهداف موظف محدد مع تقدمها
 * للوحة الموظف الخاصة
 */
export async function getEmployeeTargets(
  employeeId: string,
  filters?: Pick<TargetFilters, 'is_active' | 'date_from' | 'date_to'>
): Promise<TargetDetailView[]> {
  // [P1 FIX] بناء الاستعلام بشكل صحيح بدون conditional مكسور
  let q = supabase
    .from('targets')
    .select(TARGET_FULL_SELECT)
    .eq('scope', 'individual')
    .eq('scope_id', employeeId)
    .order('period_start', { ascending: false })
    .limit(20)

  // تطبيق الفلاتر فقط عند وجودها
  if (filters?.is_active !== undefined) q = q.eq('is_active', filters.is_active)
  if (filters?.date_from) q = q.gte('period_start', filters.date_from)
  if (filters?.date_to)   q = q.lte('period_end',   filters.date_to)

  const { data: targets, error } = await q
  if (error) throw error
  if (!targets || targets.length === 0) return []

  // جلب بيانات المكافأة لكل هدف بشكل موازٍ
  const details = await Promise.all(
    (targets as Target[]).map(t => getTargetDetail(t.id))
  )
  return details
}

// ============================================================
// ★ SECTION 12: v_target_status (من Phase 21 — محدَّثة بـ Phase 22)
// ============================================================

/**
 * جلب حالة الأهداف من view v_target_status
 * ملاحظة: هذه الـ view لا تشمل حقول المكافأة الجديدة
 * استخدم getTargets() للحصول على الحقول الكاملة
 */
export async function getTargetStatus(params?: {
  scope?: string
  scopeId?: string
  isActive?: boolean
  hasReward?: boolean
}): Promise<TargetStatusRow[]> {
  let q = supabase
    .from('v_target_status')
    .select('*')
    .order('achievement_pct', { ascending: false })

  if (params?.scope)   q = q.eq('scope', params.scope)
  if (params?.scopeId) q = q.eq('scope_id', params.scopeId)
  if (params?.isActive !== undefined) q = q.eq('is_active', params.isActive)

  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as TargetStatusRow[]
}

// ============================================================
// ★ SECTION 13: إدارة التعديلات (Adjustments)
// ============================================================

/**
 * جلب سجل تعديلات هدف محدد
 */
export async function getTargetAdjustments(targetId: string): Promise<TargetAdjustment[]> {
  const { data, error } = await supabase
    .from('target_adjustments')
    .select('*, adjusted_by_profile:profiles!target_adjustments_adjusted_by_fkey(id, full_name)')
    .eq('target_id', targetId)
    .order('adjusted_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as TargetAdjustment[]
}

// ============================================================
// ★ Re-export الدوال المشتركة (backward-compat)
// ============================================================
// الدوال التالية تُبقي توافقية مع الكود القائم

/** @deprecated استخدم createTargetWithRewards() بدلاً من الإدخال المباشر */
export const LEGACY_DIRECT_INSERT_BLOCKED = true

export type {
  TargetRewardType,
  TargetRewardPoolBasis,
  TargetPayoutStatus,
  TargetRewardTier,
  TargetCustomer,
  TargetRewardPayout,
  CreateTargetWithRewardsInput,
  TierInput,
  TargetCustomerInput,
  TargetListItem,
  TargetDetailView,
  TargetRewardSummary,
  TargetComputedMetrics,
  TargetFilters,
  PayoutFilters,
}
