import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260801140911_improve_customer_target_axes_safely.sql',
), 'utf8')
const service = readFileSync(resolve(process.cwd(), 'src/lib/services/targets.ts'), 'utf8')
const form = readFileSync(resolve(process.cwd(), 'src/pages/activities/TargetForm.tsx'), 'utf8')

describe('final target-module hardening contract', () => {
  it('deduplicates collection returns and shares them proportionally between collectors', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.target_collection_net_value(')
    expect(migration).toContain('sr.total_amount * scoped.amount / NULLIF(all_r.amount, 0)')
    expect(migration).toContain("v_achieved := public.target_collection_net_value(")
    expect(migration).toContain("WHEN 'collection_value' THEN")
    expect(migration).toContain('v_pool := public.target_collection_net_value(')
  })

  it('updates reward settings atomically and preserves field-level audit records', () => {
    expect(service).toContain("supabase.rpc('adjust_target_fields'")
    expect(service).not.toContain('p_new_value: String(value)')
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.adjust_target_fields(')
    expect(migration).toContain('WHERE id = p_target_id FOR UPDATE')
    expect(migration).toContain('RETURNING * INTO v_updated')
    expect(migration).toContain('INSERT INTO public.target_adjustments(')
    expect(migration).toContain('PERFORM public.recalculate_target_progress(p_target_id, CURRENT_DATE)')
  })

  it('requires an authenticated caller and prevents user-id spoofing', () => {
    const createStart = migration.indexOf('CREATE OR REPLACE FUNCTION public.create_target_with_rewards(')
    const createEnd = migration.indexOf('CREATE OR REPLACE FUNCTION public.adjust_target_fields(', createStart)
    const createFunction = migration.slice(createStart, createEnd)
    expect(createFunction).toContain('v_caller_id := auth.uid()')
    expect(createFunction).not.toContain('COALESCE(p_user_id, auth.uid())')
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.create_target_with_rewards(')
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.adjust_target_fields(')
  })

  it('requires create or assign permission even when read-all is granted', () => {
    const createStart = migration.indexOf('CREATE OR REPLACE FUNCTION public.create_target_with_rewards(')
    const createEnd = migration.indexOf('CREATE OR REPLACE FUNCTION public.adjust_target_fields(', createStart)
    const createFunction = migration.slice(createStart, createEnd)
    const permissionCheck = "IF NOT (check_permission(v_caller_id, 'targets.create') OR check_permission(v_caller_id, 'targets.assign')) THEN"
    expect(createFunction).toContain(permissionCheck)
    expect(createFunction.indexOf(permissionCheck)).toBeLessThan(createFunction.indexOf('IF NOT v_has_read_all THEN'))
  })

  it('bounds every progress snapshot to the target period', () => {
    const recalcStart = migration.indexOf('CREATE OR REPLACE FUNCTION public.recalculate_target_progress(')
    const recalcEnd = migration.indexOf('CREATE OR REPLACE FUNCTION public.create_target_with_rewards(', recalcStart)
    const recalc = migration.slice(recalcStart, recalcEnd)
    expect(recalc).toContain('v_calc_date := LEAST(')
    expect(recalc).toContain('GREATEST(COALESCE(p_snapshot_date, CURRENT_DATE), v_target.period_start)')
    expect(recalc).toContain('VALUES (p_target_id, v_calc_date, v_achieved')
    expect(recalc).not.toMatch(/BETWEEN v_target\.period_start AND p_snapshot_date/)
    expect(recalc).not.toMatch(/WHEN\s+'[^']+'\s*,\s*'[^']+'/)
    expect(recalc).toContain("WHEN 'upgrade_value' THEN")
    expect(recalc).toContain("WHEN 'reactivation' THEN")
    expect(recalc).toContain("WHEN 'category_spread' THEN")
  })

  it('does not expose privileged calculation helpers to public API roles', () => {
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.calc_target_pool_value(UUID, UUID, DATE, DATE) FROM PUBLIC, anon, authenticated')
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.recalculate_target_progress(UUID, DATE, BOOLEAN) FROM PUBLIC, anon')
    expect(migration).toContain('GRANT EXECUTE ON FUNCTION public.recalculate_target_progress(UUID, DATE, BOOLEAN) TO authenticated')
    expect(migration).toContain("IF NOT v_visible THEN RAISE EXCEPTION 'ليس لديك صلاحية إعادة حساب هذا الهدف'")
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.recalculate_all_active_targets(DATE) FROM PUBLIC, anon, authenticated')
    expect(migration).toContain('REVOKE ALL ON FUNCTION public.recalculate_targets_for_employee(UUID, TEXT[], DATE, DATE) FROM PUBLIC, anon, authenticated')
    expect(migration).toContain('RENAME TO prepare_target_reward_payouts_internal')
    expect(migration).toContain("public.check_permission(v_caller, 'hr.payroll.approve')")
  })

  it('enforces the same general invariants in service and database', () => {
    expect(migration).toContain('القيمة المستهدفة يجب أن تكون أكبر من صفر')
    expect(migration).toContain('اختر منتجاً أو تصنيفاً، وليس الاثنين معاً')
    expect(migration).toContain('هدف كمية المنتج يتطلب منتجاً محدداً أو تصنيفاً')
    expect(migration).toContain('اختيار المنطقة يتطلب اختيار المدينة أولاً')
    expect(migration).toContain("p_auto_payout AND p_scope <> 'individual'")
    expect(form).toContain("scope !== 'individual'")
  })

  it('preserves customer-axis invariants during later adjustments', () => {
    const adjustStart = migration.indexOf('CREATE OR REPLACE FUNCTION public.adjust_target_fields(')
    const adjustEnd = migration.indexOf('-- Compatibility path', adjustStart)
    const adjust = migration.slice(adjustStart, adjustEnd)
    expect(adjust).toContain("v_type_code IN ('upgrade_value', 'reactivation', 'category_spread')")
    expect(adjust).toContain('v_new_target > v_customer_count')
    expect(adjust).toContain("v_target.period <> 'monthly'")
    expect(adjust).toContain("v_new_filter->>'growth_pct'")
    expect(adjust).toContain("v_new_filter->>'min_reactivation_value'")
    expect(adjust).toContain("v_new_filter->>'required_category_count'")
  })

  it('clears stale reward state and validates tier limits in the creation UI', () => {
    expect(form).toContain("setRewardBaseValue('')")
    expect(form).toContain('setAutoPayout(false)')
    expect(form).toContain("setPayoutMonthOffset('0')")
    expect(form).toContain('t.threshold_pct <= 200')
    expect(form).toContain('new Set(tiers.map(t => t.threshold_pct)).size === tiers.length')
    expect(service).toContain('لا يمكن إرسال قيمة أو شرائح أو صرف تلقائي بدون نوع مكافأة')
    expect(service).toContain('tier.threshold_pct > 200')
  })

  it('requests an exact count and orders embedded progress before limiting it', () => {
    expect(service).toContain(".select(selectCols, { count: 'exact' })")
    const queryStart = service.indexOf('let q = buildTargetsQuery(filters)')
    const queryEnd = service.indexOf('// تطبيق فلتر payout_status', queryStart)
    const query = service.slice(queryStart, queryEnd)
    expect(query.indexOf(".order('snapshot_date', { ascending: false, referencedTable: 'target_progress' })"))
      .toBeGreaterThanOrEqual(0)
    expect(query.indexOf(".order('snapshot_date'"))
      .toBeLessThan(query.indexOf(".limit(1, { referencedTable: 'target_progress' })"))
  })

  it('loads the newest progress window then restores chronological chart order', () => {
    const historyStart = service.indexOf('export async function getTargetProgressHistory(')
    const history = service.slice(historyStart)
    expect(history).toContain(".order('snapshot_date', { ascending: false })")
    expect(history).toContain('return ((data ?? []) as TargetProgress[]).reverse()')
  })
})
