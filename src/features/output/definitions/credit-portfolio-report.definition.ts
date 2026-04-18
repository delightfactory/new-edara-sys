import { DocumentDefinition } from './document-definition';
import { resolveCompanyBranding } from '../branding/branding-resolver';
import { getCreditCustomers, getCreditPortfolioKPIs, getOverdueBatch, type CreditCustomerRow } from '@/lib/services/credit';
import { supabase } from '@/lib/supabase/client';
import { formatNumber, formatDateTime } from '@/lib/utils/format';
import { computeCreditState } from '@/components/shared/CustomerCreditChip';

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

const TERMS_LABELS: Record<string, string> = {
  credit: 'آجل',
  mixed: 'مختلط',
  cash: 'نقدي',
};

function termsLabel(v: string) {
  return TERMS_LABELS[v] ?? v;
}

function buildFilterSummary(filters: Record<string, any>): string {
  const parts: string[] = [];
  if (filters.search)       parts.push(`بحث: "${filters.search}"`);
  if (filters.paymentTerms) parts.push(`طريقة الدفع: ${termsLabel(filters.paymentTerms)}`);
  if (filters.repId)        parts.push('مندوب محدد');
  if (filters.balanceState && filters.balanceState !== 'all') {
    const BSL: Record<string, string> = {
      'with-balance-only': 'لديهم رصيد > 0',
      'near-limit': 'قريبون من الحد',
      'exceeded': 'تجاوزوا الحد',
      'no-limit': 'بلا حد ائتماني',
    };
    parts.push(BSL[filters.balanceState] ?? filters.balanceState);
  }
  if (filters.sortBy) {
    const SBL: Record<string, string> = {
      name: 'الاسم',
      current_balance_desc: 'الرصيد (تنازلياً)',
      available_asc: 'المتاح (تصاعدياً)',
      utilization_desc: 'الاستخدام % (تنازلياً)',
      overdue_count_desc: 'عدد المتأخرين (تنازلياً)',
    };
    parts.push(`ترتيب: ${SBL[filters.sortBy] ?? filters.sortBy}`);
  }
  return parts.length ? parts.join(' | ') : 'جميع العملاء الائتمانيين';
}

/**
 * جلب جميع النتائج للفلاتر الحالية عبر استدعاء مقسّم (Batched) بخادم Supabase.
 * لتفادي أي truncation صامت، نطلب البيانات على دفعات (مثلاً كل 1000 عميل)
 * حتى نجمع كل النتائج المتاحة.
 */
async function fetchAllFilteredCustomers(
  filters: Record<string, any>
): Promise<CreditCustomerRow[]> {
  const PAGE_SIZE = 1000;
  let allData: CreditCustomerRow[] = [];
  let page = 1;
  let totalPages = 1; // سيتم تحديثه في أول استدعاء

  do {
    const result = await getCreditCustomers({
      search:            filters.search            || undefined,
      paymentTerms:      filters.paymentTerms      || undefined,
      repId:             filters.repId             || undefined,
      balanceState:      filters.balanceState !== 'all' ? filters.balanceState : undefined,
      currentBalanceMin: filters.currentBalanceMin ? parseFloat(filters.currentBalanceMin) : undefined,
      currentBalanceMax: filters.currentBalanceMax ? parseFloat(filters.currentBalanceMax) : undefined,
      creditLimitMin:    filters.creditLimitMin    ? parseFloat(filters.creditLimitMin)    : undefined,
      creditLimitMax:    filters.creditLimitMax    ? parseFloat(filters.creditLimitMax)    : undefined,
      sortBy:            filters.sortBy !== 'name' ? filters.sortBy : undefined,
      page:              page,
      pageSize:          PAGE_SIZE,
    });

    allData = allData.concat(result.data);
    totalPages = result.totalPages || 1;
    page++;
    
    // Safety break in case of an extreme number to prevent infinitely blocking the browser
    if (page > 100) {
      throw new Error('حجم التقرير كبير جدًا للتوليد المباشر. يرجى تضييق الفلاتر أو استخدام مسار إخراج مخصص.')
    }
  } while (page <= totalPages);

  return allData;
}

// ─────────────────────────────────────────────────────────────
// Definition
// ─────────────────────────────────────────────────────────────

export const creditPortfolioReportDefinition: DocumentDefinition = {
  kind: 'credit-portfolio-report',
  title: 'تقرير المحفظة الائتمانية',
  defaultPaper: 'a4-landscape',
  supportedOutputs: ['print', 'pdf-browser', 'pdf-download'],
  supportedPapers:  ['a4-landscape', 'a4-portrait'],
  isArchivable:     false,
  maxSyncPages:     200,

  fetchAndBuild: async ({ filters = {}, locale, direction }) => {
    // 1. جلب البيانات والإحصائيات دَفعة واحدة
    const [branding, customers, kpisData] = await Promise.all([
      resolveCompanyBranding(),
      fetchAllFilteredCustomers(filters),
      getCreditPortfolioKPIs(filters)
    ]);

    // جلب بيانات التأخر لكل العملاء (دفعات من 100)
    let overdueMap: Record<string, { hasOverdue: boolean; overdueCount: number }> = {};
    for (let i = 0; i < customers.length; i += 100) {
      const slice = customers.slice(i, i + 100).map(c => c.id);
      const batch = await getOverdueBatch(slice);
      Object.assign(overdueMap, batch);
    }

    const kpis = {
      totalLimit: kpisData.totalLimit,
      totalUsed: kpisData.totalUsed,
      totalAvailable: kpisData.totalAvailable,
      countExceeded: kpisData.countExceeded,
      countNearLimit: kpisData.countNearLimit,
      total: customers.length,
    };

    const filterSummary = buildFilterSummary(filters);

    // جلب اسم المندوب إذا وُجد repId
    let repName = '';
    if (filters.repId) {
      const { data } = await supabase
        .from('profiles')
        .select('full_name')
        .eq('id', filters.repId)
        .single();
      repName = data?.full_name ?? '';
    }

    const tableRows = customers.map(c => {
      const st = computeCreditState({
        payment_terms:   c.payment_terms,
        credit_limit:    c.credit_limit,
        current_balance: c.current_balance,
      });
      const pct       = st.type === 'credit' ? Math.round(st.usedPct * 100) : 0;
      const available = st.type === 'credit' ? st.available : null;
      const stateLabel= st.type === 'credit'  ? st.label        :
                        st.type === 'cash'     ? 'نقدي'          :
                        st.type === 'no_limit' ? 'غير محدود'    : '—';
      const overdue   = overdueMap[c.id];
      const repFull   = (c.assigned_rep as any)?.full_name || '—';

      return {
        name:       c.name,
        code:       c.code || '—',
        rep:        repFull,
        terms:      termsLabel(c.payment_terms),
        limit:      c.credit_limit ? `${formatNumber(c.credit_limit)} ج.م` : '∞',
        balance:    `${formatNumber(c.current_balance ?? 0)} ج.م`,
        available:  available != null ? `${formatNumber(available)} ج.م` : '—',
        pct:        st.type === 'credit' ? `${pct}%` : '—',
        days:       c.credit_days ? `${c.credit_days} يوم` : '—',
        state:      stateLabel,
        overdue:    overdue?.hasOverdue ? `⚠ ${overdue.overdueCount}` : '—',
      };
    });

    const issuedAt = formatDateTime(new Date().toISOString());

    return {
      kind:      'credit-portfolio-report',
      title:     'تقرير المحفظة الائتمانية',
      issuedAt,
      direction: 'rtl',
      locale,
      company:   branding,
      parties:   repName ? [{ role: 'المندوب', name: repName }] : [],
      meta: [
        { label: 'تاريخ التقرير',  value: issuedAt },
        { label: 'الفلاتر النشطة', value: filterSummary },
        { label: 'إجمالي العملاء', value: String(kpis.total) },
      ],
      sections: [
        {
          type:  'summary',
          title: 'مؤشرات المحفظة المفلترة',
          items: [
            { label: 'إجمالي الحد الائتماني',  value: `${formatNumber(kpis.totalLimit)} ج.م` },
            { label: 'إجمالي الرصيد المستخدم', value: `${formatNumber(kpis.totalUsed)} ج.م` },
            { label: 'إجمالي المتاح',           value: `${formatNumber(kpis.totalAvailable)} ج.م` },
            { label: 'متجاوزون الحد',           value: String(kpis.countExceeded) },
            { label: 'قريبون من الحد (≥80%)',   value: String(kpis.countNearLimit) },
          ],
        },
        {
          type: 'table',
          title: `العملاء الائتمانيون (${customers.length})`,
          columns: [
            { key: 'name',      label: 'العميل',      align: 'start' as const },
            { key: 'code',      label: 'الكود',       align: 'start' as const },
            { key: 'rep',       label: 'المندوب',     align: 'start' as const },
            { key: 'terms',     label: 'الدفع',       align: 'center' as const },
            { key: 'limit',     label: 'الحد',        align: 'end' as const },
            { key: 'balance',   label: 'الرصيد',      align: 'end' as const },
            { key: 'available', label: 'المتاح',      align: 'end' as const },
            { key: 'pct',       label: 'الاستخدام %', align: 'center' as const },
            { key: 'days',      label: 'مدة السداد',  align: 'center' as const },
            { key: 'state',     label: 'الحالة',      align: 'center' as const },
            { key: 'overdue',   label: 'تأخر',        align: 'center' as const },
          ],
          rows: tableRows,
        },
      ],
      totals: null,
      notes: [`الفلاتر: ${filterSummary}`],
    };
  },
};
