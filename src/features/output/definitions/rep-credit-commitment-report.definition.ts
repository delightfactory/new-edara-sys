/**
 * rep-credit-commitment-report.definition.ts
 *
 * DocumentDefinition — rep-credit-commitment-report
 *
 * التقرير الرئيسي لمحافظ المندوبين.
 * البيانات صفوف مجمّعة (عدد المندوبين صغير) — الفلاتر تُطبَّق client-side
 * على الـ rows المحمّلة، والـ KPI summary تُحسَب من الـ rows المفلترة.
 *
 * الفلاتر المدعومة (في filters object):
 *   repSearch       — نص بحث في اسم المندوب
 *   includeUnassigned — boolean (افتراضي: true)
 *   overdueOnly     — boolean
 *   portfolioMin/Max
 *   createdDebtMin/Max
 *   collectionsMin/Max
 *   sortBy
 *
 * المخرجات: print / pdf-browser / pdf-download
 * الورق: a4-landscape (افتراضي) | a4-portrait
 */

import { DocumentDefinition } from './document-definition';
import { resolveCompanyBranding } from '../branding/branding-resolver';
import { getRepCreditCommitmentReport, type RepCreditCommitmentRow } from '@/lib/services/rep-credit';
import { formatNumber, formatDateTime } from '@/lib/utils/format';

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

function applyFilters(
  rows: RepCreditCommitmentRow[],
  filters: Record<string, any>
): RepCreditCommitmentRow[] {
  let result = [...rows];

  if (filters.repSearch) {
    const q = (filters.repSearch as string).toLowerCase().trim();
    result = result.filter(r => r.rep_name.toLowerCase().includes(q));
  }

  if (filters.includeUnassigned === false || filters.includeUnassigned === 'false') {
    result = result.filter(r => !r.is_unassigned);
  }

  if (filters.overdueOnly === true || filters.overdueOnly === 'true') {
    result = result.filter(r => r.overdue_customers_count > 0);
  }

  if (filters.portfolioMin !== undefined && filters.portfolioMin !== '') {
    result = result.filter(r => r.portfolio_balance >= Number(filters.portfolioMin));
  }
  if (filters.portfolioMax !== undefined && filters.portfolioMax !== '') {
    result = result.filter(r => r.portfolio_balance <= Number(filters.portfolioMax));
  }
  if (filters.createdDebtMin !== undefined && filters.createdDebtMin !== '') {
    result = result.filter(r => r.created_debt >= Number(filters.createdDebtMin));
  }
  if (filters.createdDebtMax !== undefined && filters.createdDebtMax !== '') {
    result = result.filter(r => r.created_debt <= Number(filters.createdDebtMax));
  }
  if (filters.collectionsMin !== undefined && filters.collectionsMin !== '') {
    result = result.filter(r => r.confirmed_collections >= Number(filters.collectionsMin));
  }
  if (filters.collectionsMax !== undefined && filters.collectionsMax !== '') {
    result = result.filter(r => r.confirmed_collections <= Number(filters.collectionsMax));
  }

  if (filters.sortBy) {
    result.sort((a, b) => {
      switch (filters.sortBy) {
        case 'portfolio_desc':    return b.portfolio_balance - a.portfolio_balance;
        case 'created_debt_desc': return b.created_debt - a.created_debt;
        case 'collections_desc':  return b.confirmed_collections - a.confirmed_collections;
        case 'overdue_desc':      return b.overdue_customers_count - a.overdue_customers_count;
        case 'rep_name_asc':      return a.rep_name.localeCompare(b.rep_name, 'ar');
        default: return 0;
      }
    });
  }

  return result;
}

function buildSummaryFromRows(rows: RepCreditCommitmentRow[]) {
  const realReps = rows.filter(r => !r.is_unassigned);
  return {
    totalReps:                 realReps.length,
    totalPortfolio:            rows.reduce((s, r) => s + r.portfolio_balance, 0),
    totalCreatedDebt:          realReps.reduce((s, r) => s + r.created_debt, 0),
    totalConfirmedCollections: realReps.reduce((s, r) => s + r.confirmed_collections, 0),
    totalOverdue:              rows.reduce((s, r) => s + r.overdue_customers_count, 0),
  };
}

function buildFilterSummary(filters: Record<string, any>): string {
  const parts: string[] = [];
  if (filters.repSearch)       parts.push(`بحث: "${filters.repSearch}"`);
  if (filters.overdueOnly === true || filters.overdueOnly === 'true')
    parts.push('المتأخرون فقط');
  if (filters.includeUnassigned === false || filters.includeUnassigned === 'false')
    parts.push('بدون صف "غير مسند"');
  if (filters.sortBy) {
    const SBL: Record<string, string> = {
      portfolio_desc:    'المحفظة (تنازلياً)',
      created_debt_desc: 'المديونية (تنازلياً)',
      collections_desc:  'التحصيلات (تنازلياً)',
      overdue_desc:      'المتأخرون (تنازلياً)',
      rep_name_asc:      'اسم المندوب (أبجدي)',
    };
    parts.push(`ترتيب: ${SBL[filters.sortBy] ?? filters.sortBy}`);
  }
  return parts.length ? parts.join(' | ') : 'جميع مسؤولي المحافظ';
}

// ─────────────────────────────────────────────────────────────
// Definition
// ─────────────────────────────────────────────────────────────

export const repCreditCommitmentReportDefinition: DocumentDefinition = {
  kind: 'rep-credit-commitment-report',
  title: 'تقرير التزام مسؤولي المحافظ الائتمانية',
  defaultPaper: 'a4-landscape',
  supportedOutputs: ['print', 'pdf-browser', 'pdf-download'],
  supportedPapers:  ['a4-landscape', 'a4-portrait'],
  isArchivable:     false,
  maxSyncPages:     50,

  fetchAndBuild: async ({ filters = {}, locale, direction }) => {
    const [branding, rawData] = await Promise.all([
      resolveCompanyBranding(),
      getRepCreditCommitmentReport(),
    ]);

    const filteredRows = applyFilters(rawData.rows, filters);
    const summary      = buildSummaryFromRows(filteredRows);
    const filterSummary = buildFilterSummary(filters);
    const issuedAt = formatDateTime(new Date().toISOString());

    const tableRows = filteredRows.map(r => ({
      rep:         r.is_unassigned ? '⚠ غير مسند' : r.rep_name,
      customers:   String(r.customers_count),
      withBalance: String(r.customers_with_balance),
      overdue:     r.overdue_customers_count > 0 ? `⚠ ${r.overdue_customers_count}` : '—',
      portfolio:   `${formatNumber(r.portfolio_balance)} ج.م`,
      debt:        r.is_unassigned ? 'لا ينطبق' : `${formatNumber(r.created_debt)} ج.م`,
      collections: r.is_unassigned ? 'لا ينطبق' : `${formatNumber(r.confirmed_collections)} ج.م`,
    }));

    return {
      kind:      'rep-credit-commitment-report',
      title:     'تقرير التزام مسؤولي المحافظ الائتمانية',
      issuedAt,
      direction: 'rtl',
      locale,
      company:   branding,
      parties:   [],
      meta: [
        { label: 'تاريخ التقرير',    value: issuedAt },
        { label: 'الفلاتر النشطة',   value: filterSummary },
        { label: 'عدد المسؤولين',    value: String(summary.totalReps) },
      ],
      sections: [
        {
          type:  'summary',
          title: 'ملخص المحافظ المفلترة',
          items: [
            { label: 'مسؤولو المحافظ',           value: String(summary.totalReps) },
            { label: 'إجمالي محافظ المتابعة',    value: `${formatNumber(summary.totalPortfolio)} ج.م` },
            { label: 'إجمالي المديونية المنشأة', value: `${formatNumber(summary.totalCreatedDebt)} ج.م` },
            { label: 'إجمالي التحصيلات المؤكدة', value: `${formatNumber(summary.totalConfirmedCollections)} ج.م` },
            { label: 'إجمالي العملاء المتأخرين', value: String(summary.totalOverdue) },
          ],
        },
        {
          type: 'table',
          title: `مسؤولو المحافظ (${filteredRows.length})`,
          columns: [
            { key: 'rep',         label: 'المسؤول',            align: 'start' as const },
            { key: 'customers',   label: 'العملاء',            align: 'center' as const },
            { key: 'withBalance', label: 'بأرصدة',             align: 'center' as const },
            { key: 'overdue',     label: 'متأخرون',            align: 'center' as const },
            { key: 'portfolio',   label: 'محفظة المتابعة',     align: 'end' as const },
            { key: 'debt',        label: 'المديونية المنشأة',  align: 'end' as const },
            { key: 'collections', label: 'التحصيلات المؤكدة', align: 'end' as const },
          ],
          rows: tableRows,
        },
      ],
      totals: null,
      notes: [`الفلاتر: ${filterSummary}`],
    };
  },
};
