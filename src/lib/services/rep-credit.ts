/**
 * rep-credit.ts — v3
 * خدمة تقرير الالتزام الائتماني للمندوبين
 *
 * التغييرات في v3:
 *   - rep_id أصبح nullable (null = صف "غير مسند")
 *   - إضافة: is_unassigned, sort_order, customers_count
 *   - getRepCreditCommitmentDetail يقبل null rep_id
 *     → null: يُعيد عملاء غير مسندين فقط (orders/receipts فارغان)
 *   - RepCreditCommitmentSummary يضم hasUnassigned، unassignedBalance
 *
 * القيود الصارمة:
 *   - قراءة فقط — لا منطق أعمال، لا تعديل
 *   - لا تجميع كبير في JavaScript — كل التجميع في SQL
 *
 * تعيين حقول العملاء في RepCreditDetailRow:
 *   amount_1    = current_balance
 *   amount_2    = credit_limit
 *   amount_3    = credit_days (INTEGER عبر SQL → NUMERIC)
 *   status_text = payment_terms
 *   date_1      = NULL
 *   extra_int   = NULL
 */

import { supabase } from '@/lib/supabase/client'

// ─────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────

/** سطر واحد لكل مسؤول محفظة في التقرير المجمّع */
export interface RepCreditCommitmentRow {
  rep_id:                  string | null  // null للصف الصناعي "غير مسند"
  rep_name:                string
  is_unassigned:           boolean        // true للصف الصناعي فقط
  sort_order:              number         // 0=مسؤول حقيقي، 1=غير مسند

  // محفظة المتابعة
  portfolio_balance:       number
  customers_count:         number         // إجمالي العملاء المسندين (نشطون)
  customers_with_balance:  number         // منهم: رصيد > 0
  overdue_customers_count: number         // منهم: فواتير متأخرة صافيها > 0

  // المديونية المنشأة (0 للصف الصناعي)
  created_debt:            number

  // التحصيلات المؤكدة (0 للصف الصناعي)
  confirmed_collections:   number
}

/** ملخص إجمالي للتقرير */
export interface RepCreditCommitmentSummary {
  totalReps:                 number   // عدد مسؤولي المحافظ الحقيقيين
  totalPortfolio:            number   // إجمالي المحافظ (مسندة + غير مسندة)
  totalCreatedDebt:          number   // إجمالي المديونية المنشأة (مسؤولون حقيقيون)
  totalConfirmedCollections: number   // إجمالي التحصيلات (مسؤولون حقيقيون)
  hasUnassigned:             boolean  // هل يوجد رصيد غير مسند
  unassignedBalance:         number   // قيمة الرصيد غير المسند
}

/** سطر تفصيلي لمسؤول واحد أو لصف "غير مسند" */
export interface RepCreditDetailRow {
  section_type:  'customer' | 'order' | 'receipt'
  entity_id:     string
  entity_ref:    string | null
  entity_name:   string
  /**
   * تعيين حسب section_type:
   *   customer: current_balance
   *   order:    net_remaining
   *   receipt:  amount
   */
  amount_1:      number
  /**
   *   customer: credit_limit
   *   order:    total_amount
   *   receipt:  NULL
   */
  amount_2:      number | null
  /**
   *   customer: credit_days (NUMBER)
   *   order:    paid_amount
   *   receipt:  NULL
   */
  amount_3:      number | null
  /**
   *   customer: NULL
   *   order:    delivered_at
   *   receipt:  reviewed_at
   */
  date_1:        string | null
  /**
   *   customer: payment_terms (مثل 'credit' | 'cash' | ...)
   *   order:    order status
   *   receipt:  receipt status
   */
  status_text:   string | null
  /**
   *   customer: NULL
   *   order:    days_since_delivery
   *   receipt:  NULL
   */
  extra_int:     number | null
}

export interface RepCreditCommitmentDetail {
  customers: RepCreditDetailRow[]
  orders:    RepCreditDetailRow[]
  receipts:  RepCreditDetailRow[]
}

// ─────────────────────────────────────────────────────────────
// getRepCreditCommitmentReport
// ─────────────────────────────────────────────────────────────

export async function getRepCreditCommitmentReport(): Promise<{
  rows:    RepCreditCommitmentRow[]
  summary: RepCreditCommitmentSummary
}> {
  const { data, error } = await supabase.rpc('get_rep_credit_commitment_report')

  if (error) throw error

  const rows: RepCreditCommitmentRow[] = ((data || []) as any[]).map(r => ({
    rep_id:                  r.rep_id   ?? null,
    rep_name:                r.rep_name ?? '',
    is_unassigned:           Boolean(r.is_unassigned),
    sort_order:              Number(r.sort_order)              || 0,
    portfolio_balance:       Number(r.portfolio_balance)       || 0,
    customers_count:         Number(r.customers_count)         || 0,
    customers_with_balance:  Number(r.customers_with_balance)  || 0,
    overdue_customers_count: Number(r.overdue_customers_count) || 0,
    created_debt:            Number(r.created_debt)            || 0,
    confirmed_collections:   Number(r.confirmed_collections)   || 0,
  }))

  const realReps     = rows.filter(r => !r.is_unassigned)
  const unassignedRow = rows.find(r => r.is_unassigned)

  const summary: RepCreditCommitmentSummary = {
    totalReps:                 realReps.length,
    totalPortfolio:            rows.reduce((s, r) => s + r.portfolio_balance,    0),
    totalCreatedDebt:          realReps.reduce((s, r) => s + r.created_debt,      0),
    totalConfirmedCollections: realReps.reduce((s, r) => s + r.confirmed_collections, 0),
    hasUnassigned:             !!unassignedRow,
    unassignedBalance:         unassignedRow?.portfolio_balance ?? 0,
  }

  return { rows, summary }
}

// ─────────────────────────────────────────────────────────────
// getRepCreditCommitmentDetail
//   repId = null  → تفاصيل "غير مسند" (عملاء فقط)
//   repId = UUID  → تفاصيل مسؤول حقيقي (3 أقسام)
// ─────────────────────────────────────────────────────────────

export async function getRepCreditCommitmentDetail(
  repId: string | null
): Promise<RepCreditCommitmentDetail> {
  const { data, error } = await supabase.rpc('get_rep_credit_commitment_detail', {
    p_rep_id: repId,   // null → SQL يُعيد عملاء غير مسندين فقط
  })

  if (error) throw error

  const all: RepCreditDetailRow[] = ((data || []) as any[]).map(r => ({
    section_type: r.section_type as 'customer' | 'order' | 'receipt',
    entity_id:    r.entity_id,
    entity_ref:   r.entity_ref   ?? null,
    entity_name:  r.entity_name  ?? '',
    amount_1:     Number(r.amount_1) || 0,
    amount_2:     r.amount_2 != null ? Number(r.amount_2) : null,
    amount_3:     r.amount_3 != null ? Number(r.amount_3) : null,
    date_1:       r.date_1      ?? null,
    status_text:  r.status_text ?? null,
    extra_int:    r.extra_int   != null ? Number(r.extra_int) : null,
  }))

  return {
    customers: all.filter(r => r.section_type === 'customer'),
    orders:    all.filter(r => r.section_type === 'order'),
    receipts:  all.filter(r => r.section_type === 'receipt'),
  }
}
