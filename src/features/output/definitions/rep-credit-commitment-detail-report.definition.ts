/**
 * rep-credit-commitment-detail-report.definition.ts
 *
 * DocumentDefinition — rep-credit-commitment-detail-report
 *
 * تقرير تفاصيل مندوب واحد من الـ Drawer.
 * entityId = repId أو sentinel '__unassigned__'
 *
 * الفلاتر المدعومة (في filters object):
 *   search                — نص بحث في اسم/كود العميل
 *   customersOnlyWithBalance — boolean (افتراضي: true)
 *   customerPaymentTerms  — all | credit | mixed | cash
 *   customerState         — all | exceeded | near-limit | within-limit | no-limit
 *   sections              — all | customers | orders | receipts
 *   repName               — اسم المندوب (لعرضه في التقرير)
 *   isUnassigned          — boolean
 *
 * المخرجات: print / pdf-browser / pdf-download
 * الورق: a4-landscape (افتراضي) | a4-portrait
 */

import { DocumentDefinition } from './document-definition';
import { resolveCompanyBranding } from '../branding/branding-resolver';
import { getRepCreditCommitmentDetail, type RepCreditDetailRow } from '@/lib/services/rep-credit';
import { formatNumber, formatDateTime } from '@/lib/utils/format';
import { computeCreditState } from '@/components/shared/CustomerCreditChip';

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

const PAY_LABELS: Record<string, string> = {
  cash: 'نقدي', credit: 'آجل', mixed: 'مختلط',
};
function payLabel(v: string | null) { return v ? (PAY_LABELS[v] ?? v) : '—'; }

function applyCustomerFilters(
  customers: RepCreditDetailRow[],
  filters: Record<string, any>
): RepCreditDetailRow[] {
  let result = [...customers];

  const onlyWithBalance = filters.customersOnlyWithBalance !== false &&
                          filters.customersOnlyWithBalance !== 'false';
  if (onlyWithBalance) {
    result = result.filter(c => (c.amount_1 ?? 0) > 0);
  }

  if (filters.search) {
    const q = (filters.search as string).toLowerCase().trim();
    result = result.filter(c =>
      c.entity_name.toLowerCase().includes(q) ||
      (c.entity_ref ?? '').toLowerCase().includes(q)
    );
  }

  if (filters.customerPaymentTerms && filters.customerPaymentTerms !== 'all') {
    result = result.filter(c => c.status_text === filters.customerPaymentTerms);
  }

  if (filters.customerState && filters.customerState !== 'all') {
    result = result.filter(c => {
      const st = computeCreditState({
        payment_terms:   c.status_text ?? 'cash',
        credit_limit:    c.amount_2 ?? 0,
        current_balance: c.amount_1 ?? 0,
      });
      switch (filters.customerState) {
        case 'exceeded':
          return st.type === 'credit' && (c.amount_1 ?? 0) > (c.amount_2 ?? 0);
        case 'near-limit':
          return st.type === 'credit' && st.usedPct >= 0.8 && st.usedPct <= 1;
        case 'within-limit':
          return st.type === 'credit' && st.usedPct < 0.8;
        case 'no-limit':
          return st.type === 'no_limit';
        default: return true;
      }
    });
  }

  return result;
}

function applyOrderFilters(
  orders: RepCreditDetailRow[],
  filters: Record<string, any>
): RepCreditDetailRow[] {
  let result = [...orders];
  if (filters.search) {
    const q = (filters.search as string).toLowerCase().trim();
    result = result.filter(o =>
      (o.entity_ref ?? '').toLowerCase().includes(q) ||
      o.entity_name.toLowerCase().includes(q)
    );
  }
  return result;
}

function applyReceiptFilters(
  receipts: RepCreditDetailRow[],
  filters: Record<string, any>
): RepCreditDetailRow[] {
  let result = [...receipts];
  if (filters.search) {
    const q = (filters.search as string).toLowerCase().trim();
    result = result.filter(r =>
      (r.entity_ref ?? '').toLowerCase().includes(q) ||
      r.entity_name.toLowerCase().includes(q)
    );
  }
  return result;
}

function buildFilterSummary(filters: Record<string, any>): string {
  const parts: string[] = [];
  if (filters.search)         parts.push(`بحث: "${filters.search}"`);
  const onlyBal = filters.customersOnlyWithBalance !== false &&
                  filters.customersOnlyWithBalance !== 'false';
  if (onlyBal)                parts.push('عملاء برصيد > 0 فقط');
  if (filters.customerPaymentTerms && filters.customerPaymentTerms !== 'all')
    parts.push(`طريقة الدفع: ${payLabel(filters.customerPaymentTerms)}`);
  if (filters.customerState && filters.customerState !== 'all') {
    const SL: Record<string, string> = {
      exceeded: 'متجاوزون الحد',
      'near-limit': 'قريبون من الحد',
      'within-limit': 'ضمن الحد',
      'no-limit': 'بلا حد',
    };
    parts.push(SL[filters.customerState] ?? filters.customerState);
  }
  if (filters.sections && filters.sections !== 'all')
    parts.push(`القسم: ${filters.sections}`);
  return parts.length ? parts.join(' | ') : 'كل البيانات';
}

// ─────────────────────────────────────────────────────────────
// Definition
// ─────────────────────────────────────────────────────────────

export const repCreditCommitmentDetailReportDefinition: DocumentDefinition = {
  kind: 'rep-credit-commitment-detail-report',
  title: 'تقرير تفاصيل مسؤول المحفظة',
  defaultPaper: 'a4-landscape',
  supportedOutputs: ['print', 'pdf-browser', 'pdf-download'],
  supportedPapers:  ['a4-landscape', 'a4-portrait'],
  isArchivable:     false,
  maxSyncPages:     100,

  fetchAndBuild: async ({ entityId, filters = {}, locale, direction }) => {
    const isUnassigned = entityId === '__unassigned__' ||
                         filters.isUnassigned === true ||
                         filters.isUnassigned === 'true';
    const repId = (!isUnassigned && entityId && entityId !== '__unassigned__')
      ? entityId
      : null;

    const repName = (filters.repName as string) || (isUnassigned ? 'غير مسند' : 'مسؤول المحفظة');

    const [branding, rawData] = await Promise.all([
      resolveCompanyBranding(),
      getRepCreditCommitmentDetail(repId),
    ]);

    // تطبيق الفلاتر على كل قسم
    const sections = (filters.sections as string) ?? 'all';
    const showCustomers = sections === 'all' || sections === 'customers';
    const showOrders    = sections === 'all' || sections === 'orders';
    const showReceipts  = sections === 'all' || sections === 'receipts';

    const filteredCustomers = showCustomers
      ? applyCustomerFilters(rawData.customers, filters)
      : [];
    const filteredOrders    = showOrders && !isUnassigned
      ? applyOrderFilters(rawData.orders, filters)
      : [];
    const filteredReceipts  = showReceipts && !isUnassigned
      ? applyReceiptFilters(rawData.receipts, filters)
      : [];

    const filterSummary = buildFilterSummary(filters);
    const issuedAt = formatDateTime(new Date().toISOString());

    // KPIs من الـ filtered data
    const totalCustomerBalance = filteredCustomers.reduce((s, c) => s + (c.amount_1 ?? 0), 0);
    const totalOrderDebt       = filteredOrders.reduce((s, o) => s + (o.amount_1 ?? 0), 0);
    const totalReceiptsAmt     = filteredReceipts.reduce((s, r) => s + (r.amount_1 ?? 0), 0);

    const docSections: any[] = [];

    // ملخص
    docSections.push({
      type:  'summary',
      title: `ملخص: ${repName}`,
      items: [
        ...(showCustomers ? [{ label: `العملاء (${filteredCustomers.length})`, value: `إجمالي الأرصدة: ${formatNumber(totalCustomerBalance)} ج.م` }] : []),
        ...(showOrders && !isUnassigned ? [{ label: `الفواتير (${filteredOrders.length})`, value: `صافي المديونية: ${formatNumber(totalOrderDebt)} ج.م` }] : []),
        ...(showReceipts && !isUnassigned ? [{ label: `التحصيلات (${filteredReceipts.length})`, value: `إجمالي: ${formatNumber(totalReceiptsAmt)} ج.م` }] : []),
      ],
    });

    // جدول العملاء
    if (showCustomers && filteredCustomers.length > 0) {
      docSections.push({
        type: 'table',
        title: `العملاء (${filteredCustomers.length})`,
        columns: [
          { key: 'name',      label: 'الاسم',           align: 'start' as const },
          { key: 'code',      label: 'الكود',           align: 'start' as const },
          { key: 'balance',   label: 'الرصيد الحالي',   align: 'end' as const },
          { key: 'limit',     label: 'الحد الائتماني',  align: 'end' as const },
          { key: 'terms',     label: 'طريقة الدفع',     align: 'center' as const },
          { key: 'days',      label: 'أيام الائتمان',   align: 'center' as const },
        ],
        rows: filteredCustomers.map(c => ({
          name:    c.entity_name,
          code:    c.entity_ref ?? '—',
          balance: `${formatNumber(c.amount_1 ?? 0)} ج.م`,
          limit:   c.amount_2 != null ? `${formatNumber(c.amount_2)} ج.م` : '—',
          terms:   payLabel(c.status_text),
          days:    c.amount_3 != null ? `${Math.round(c.amount_3)} يوم` : '—',
        })),
      });
    }

    // جدول الفواتير
    if (showOrders && !isUnassigned && filteredOrders.length > 0) {
      docSections.push({
        type: 'table',
        title: `الفواتير المنشأة بواسطته — صافي متبقٍ (${filteredOrders.length})`,
        columns: [
          { key: 'ref',       label: 'رقم الطلب',       align: 'start' as const },
          { key: 'customer',  label: 'العميل',           align: 'start' as const },
          { key: 'net',       label: 'الصافي المتبقي',  align: 'end' as const },
          { key: 'total',     label: 'الإجمالي',        align: 'end' as const },
          { key: 'date',      label: 'تاريخ التسليم',   align: 'center' as const },
          { key: 'days',      label: 'الأيام',          align: 'center' as const },
        ],
        rows: filteredOrders.map(o => ({
          ref:      o.entity_ref ?? '—',
          customer: o.entity_name,
          net:      `${formatNumber(o.amount_1 ?? 0)} ج.م`,
          total:    o.amount_2 != null ? `${formatNumber(o.amount_2)} ج.م` : '—',
          date:     o.date_1 ?? '—',
          days:     o.extra_int != null ? String(o.extra_int) : '—',
        })),
      });
    }

    // جدول التحصيلات
    if (showReceipts && !isUnassigned && filteredReceipts.length > 0) {
      docSections.push({
        type: 'table',
        title: `التحصيلات المؤكدة (${filteredReceipts.length})`,
        columns: [
          { key: 'ref',      label: 'رقم الإيصالة',   align: 'start' as const },
          { key: 'customer', label: 'العميل',          align: 'start' as const },
          { key: 'amount',   label: 'المبلغ',          align: 'end' as const },
          { key: 'date',     label: 'تاريخ المراجعة', align: 'center' as const },
        ],
        rows: filteredReceipts.map(r => ({
          ref:      r.entity_ref ?? '—',
          customer: r.entity_name,
          amount:   `${formatNumber(r.amount_1 ?? 0)} ج.م`,
          date:     r.date_1 ?? '—',
        })),
      });
    }

    return {
      kind:      'rep-credit-commitment-detail-report',
      title:     `تقرير تفاصيل: ${repName}`,
      issuedAt,
      direction: 'rtl',
      locale,
      company:   branding,
      parties:   [{ role: isUnassigned ? 'الحالة' : 'مسؤول المحفظة', name: repName }],
      meta: [
        { label: 'تاريخ التقرير',    value: issuedAt },
        { label: 'الفلاتر النشطة',   value: filterSummary },
      ],
      sections: docSections,
      totals:   null,
      notes:    [`الفلاتر: ${filterSummary}`],
    };
  },
};
