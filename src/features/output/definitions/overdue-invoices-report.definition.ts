import { DocumentDefinition } from './document-definition';
import { resolveCompanyBranding } from '../branding/branding-resolver';
import {
  getOverdueSalesInvoices,
  type OverdueInvoiceSortBy,
  type OverdueSalesInvoiceRow,
} from '@/lib/services/credit';
import { supabase } from '@/lib/supabase/client';
import { formatCurrency, formatDate, formatDateTime, formatNumber } from '@/lib/utils/format';

const PAGE_SIZE = 1000;

const SORT_LABELS: Record<OverdueInvoiceSortBy, string> = {
  days_overdue_desc: 'الأكثر تأخيرا',
  due_date_asc: 'الأقدم استحقاقا',
  remaining_desc: 'الأعلى مبلغا',
  customer_name: 'اسم العميل',
};

const TERMS_LABELS: Record<string, string> = {
  cash: 'نقدي',
  credit: 'آجل',
  mixed: 'مختلط',
};

const BUCKET_LABELS: Record<OverdueSalesInvoiceRow['overdue_bucket'], string> = {
  new: 'حديث',
  medium: 'متوسط',
  high: 'مرتفع',
  critical: 'حرج',
};

async function fetchAllOverdueInvoices(filters: Record<string, any>) {
  let page = 1;
  let totalPages = 1;
  let firstPage:
    | Awaited<ReturnType<typeof getOverdueSalesInvoices>>
    | null = null;
  const rows: OverdueSalesInvoiceRow[] = [];

  do {
    const result = await getOverdueSalesInvoices({
      search: filters.search || undefined,
      repId: filters.repId || undefined,
      minDaysOverdue: filters.minDaysOverdue ? Number(filters.minDaysOverdue) : undefined,
      sortBy: (filters.sortBy as OverdueInvoiceSortBy) || 'days_overdue_desc',
      page,
      pageSize: PAGE_SIZE,
    });

    if (!firstPage) firstPage = result;
    rows.push(...result.data);
    totalPages = result.totalPages || 1;
    page++;

    if (page > 100) {
      throw new Error('حجم تقرير الفواتير المتأخرة كبير جدا للتوليد المباشر. يرجى تضييق الفلاتر قبل الطباعة.');
    }
  } while (page <= totalPages);

  return {
    rows,
    summary: {
      count: firstPage?.count ?? rows.length,
      totalOverdueAmount: firstPage?.totalOverdueAmount ?? rows.reduce((sum, row) => sum + row.net_remaining, 0),
      overdueCustomersCount: firstPage?.overdueCustomersCount ?? new Set(rows.map(row => row.customer_id)).size,
      maxDaysOverdue: firstPage?.maxDaysOverdue ?? rows.reduce((max, row) => Math.max(max, row.days_overdue), 0),
    },
  };
}

async function getRepName(repId?: string) {
  if (!repId) return '';

  const { data } = await supabase
    .from('profiles')
    .select('full_name')
    .eq('id', repId)
    .maybeSingle();

  return data?.full_name ?? '';
}

function buildFilterSummary(filters: Record<string, any>, repName: string): string {
  const parts: string[] = [];
  if (filters.search) parts.push(`بحث: "${filters.search}"`);
  if (repName) parts.push(`المندوب: ${repName}`);
  if (filters.minDaysOverdue) parts.push(`تأخير ${filters.minDaysOverdue} يوم فأكثر`);
  if (filters.sortBy) {
    parts.push(`ترتيب: ${SORT_LABELS[filters.sortBy as OverdueInvoiceSortBy] ?? filters.sortBy}`);
  }
  return parts.length ? parts.join(' | ') : 'كل الفواتير المتأخرة';
}

export const overdueInvoicesReportDefinition: DocumentDefinition = {
  kind: 'overdue-invoices-report',
  title: 'تقرير الفواتير المتأخرة',
  defaultPaper: 'a4-landscape',
  supportedOutputs: ['print', 'pdf-browser', 'pdf-download'],
  supportedPapers: ['a4-landscape', 'a4-portrait'],
  isArchivable: false,
  maxSyncPages: 200,

  fetchAndBuild: async ({ filters = {}, locale }) => {
    const [branding, invoiceData, repName] = await Promise.all([
      resolveCompanyBranding(),
      fetchAllOverdueInvoices(filters),
      getRepName(filters.repId),
    ]);

    const issuedAt = formatDateTime(new Date().toISOString());
    const filterSummary = buildFilterSummary(filters, repName);

    const tableRows = invoiceData.rows.map(row => ({
      invoice: row.order_number,
      customer: row.customer_code ? `${row.customer_name} (${row.customer_code})` : row.customer_name,
      rep: row.assigned_rep_name || row.order_rep_name || 'غير مسند',
      dueDate: formatDate(row.due_date),
      overdueDays: `${formatNumber(row.days_overdue)} يوم`,
      remaining: `${formatCurrency(row.net_remaining)} ج.م`,
      terms: TERMS_LABELS[row.payment_terms] ?? row.payment_terms,
      bucket: BUCKET_LABELS[row.overdue_bucket] ?? row.overdue_bucket,
      changed: row.last_due_date_changed_at ? 'معدل' : '',
    }));

    return {
      kind: 'overdue-invoices-report',
      title: 'تقرير الفواتير المتأخرة',
      issuedAt,
      direction: 'rtl',
      locale,
      company: branding,
      parties: repName ? [{ role: 'المندوب', name: repName }] : [],
      meta: [
        { label: 'تاريخ التقرير', value: issuedAt },
        { label: 'الفلاتر النشطة', value: filterSummary },
        { label: 'عدد الفواتير', value: String(invoiceData.summary.count) },
      ],
      sections: [
        {
          type: 'summary',
          title: 'ملخص الفواتير المتأخرة',
          items: [
            { label: 'عدد الفواتير', value: formatNumber(invoiceData.summary.count) },
            { label: 'الصافي المتأخر', value: `${formatCurrency(invoiceData.summary.totalOverdueAmount)} ج.م` },
            { label: 'العملاء المتأثرون', value: formatNumber(invoiceData.summary.overdueCustomersCount) },
            { label: 'أكبر تأخير', value: `${formatNumber(invoiceData.summary.maxDaysOverdue)} يوم` },
          ],
        },
        {
          type: 'table',
          title: `الفواتير المتأخرة (${invoiceData.rows.length})`,
          columns: [
            { key: 'invoice', label: 'الفاتورة', align: 'start', dir: 'ltr' },
            { key: 'customer', label: 'العميل', align: 'start' },
            { key: 'rep', label: 'المندوب', align: 'start' },
            { key: 'dueDate', label: 'الاستحقاق', align: 'center' },
            { key: 'overdueDays', label: 'التأخير', align: 'center' },
            { key: 'remaining', label: 'الصافي المتبقي', align: 'end' },
            { key: 'terms', label: 'الدفع', align: 'center' },
            { key: 'bucket', label: 'درجة الخطر', align: 'center' },
            { key: 'changed', label: 'ملاحظة', align: 'center' },
          ],
          rows: tableRows,
        },
      ],
      totals: {
        total: `${formatCurrency(invoiceData.summary.totalOverdueAmount)} ج.م`,
      },
      notes: [
        `الفلاتر: ${filterSummary}`,
        'يعتمد التقرير على الفواتير الآجلة المسلمة ذات صافي متبق أكبر من صفر وبعد تاريخ الاستحقاق.',
      ],
    };
  },
};
