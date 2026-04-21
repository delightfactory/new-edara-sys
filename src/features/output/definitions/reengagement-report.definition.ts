/**
 * reengagement-report.definition.ts
 *
 * تعريف تقرير إعادة الاستهداف (Customer Reengagement Report).
 *
 * المعمارية:
 *   - يُمرَّر الفلاتر + إعدادات 360 عبر URL params فقط (لا rows).
 *   - يجلب fetchAndBuild القائمة والملخص مرة واحدة بنفس فلاتر الصفحة.
 *   - بيانات 360 تُجلب بشكل تسلسلي لكل عميل داخل صفحة المعاينة.
 *   - إذا فشل جلب 360 لعميل، يُسجَّل خطأ لذلك العميل فقط ولا يُوقف التقرير.
 *   - الحد الأقصى لـ 360: 30 عميل.
 *   - كل RPC لكل عميل يُجلب مرة واحدة فقط ويُعاد استخدامه داخل التوصيات.
 *
 * params المقبولة من URL:
 *   dateFrom, dateTo, repId, governorateId, cityId,
 *   priority, customerType, activeOnly,
 *   include360       → '1' | '0'
 *   sections360      → 'kpis,products,payment,recommendations,aging' (comma separated)
 *   limit360         → number string (default '30', max 30)
 */

import { DocumentDefinition } from './document-definition';
import { resolveCompanyBranding } from '../branding/branding-resolver';
import { formatDateTime } from '@/lib/utils/format';
import {
  getReengagementList,
  getReengagementSummary,
  type ReengagementRow,
  type PriorityLabel,
} from '@/lib/services/customerReengagement';
import {
  getCustomer360Kpis,
  getCustomer360TopProducts,
  getCustomer360PaymentBehavior,
  getCustomer360ArAging,
  type Customer360Kpis,
  type CustomerPaymentBehavior,
  type CustomerArAgingBucket,
  type CustomerTopProduct,
} from '@/lib/services/customer360';
import { computeRecommendations } from '@/lib/utils/customer360-recommendations';
import type {
  CustomerCardEntry,
  CustomerCardKpis,
  CustomerCardProduct,
  CustomerCardPaymentBehavior,
  CustomerCardRecommendation,
  CustomerCardAgingBucket,
} from '../models/canonical-document';

// ─── Priority Config ──────────────────────────────────────────────────────────

const PRIORITY_CFG: Record<PriorityLabel, { display: string; accent: string }> = {
  CHAMPION_LOST:  { display: '🔴 Champion Lost', accent: '#dc2626' },
  DECLINING_HIGH: { display: '🟠 تراجع عالي',    accent: '#d97706' },
  MID_LOST:       { display: '🟡 متوسط خامد',    accent: '#92400e' },
  MID_AT_RISK:    { display: '🟤 متوسط معرض',    accent: '#78350f' },
  OTHER:          { display: '⚫ أخرى',           accent: '#64748b' },
};

const PRIORITY_LABELS: Record<PriorityLabel, string> = {
  CHAMPION_LOST:  'Champion Lost',
  DECLINING_HIGH: 'تراجع عالي',
  MID_LOST:       'متوسط خامد',
  MID_AT_RISK:    'متوسط معرض',
  OTHER:          'أخرى',
};

// ─── Formatters ───────────────────────────────────────────────────────────────

const FMT = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });
const fmtCur = (n: number | null | undefined) => n != null ? `${FMT.format(n)} ج.م` : '—';

function fmtRecency(days: number | null): string {
  if (days === null) return 'لا طلبات';
  if (days === 0) return 'اليوم';
  if (days === 1) return 'أمس';
  return `${days} يوم`;
}

function fmtDate(d: string | null): string {
  if (!d) return '—';
  return new Date(d).toLocaleDateString('en-GB');
}

function buildFilterSummary(filters: Record<string, any>): string {
  const parts: string[] = [];
  if (filters.priority)      parts.push(PRIORITY_LABELS[filters.priority as PriorityLabel] ?? filters.priority);
  if (filters.customerType) {
    const T: Record<string, string> = { retail: 'تجزئة', wholesale: 'جملة', distributor: 'موزع' };
    parts.push(T[filters.customerType] ?? filters.customerType);
  }
  if (filters.dateFrom || filters.dateTo) {
    parts.push(`الفترة: ${filters.dateFrom || '...'} → ${filters.dateTo || '...'}`);
  }
  if (filters.activeOnly !== false && filters.activeOnly !== 'false') parts.push('النشطون فقط');
  return parts.length ? parts.join(' | ') : 'جميع العملاء';
}

// ─── 360° Fetcher (per customer, graceful, no duplicate RPCs) ────────────────

type Sections360 = Set<string>;

/**
 * Fetches all required 360° data for a single customer.
 * Each RPC is called at most once — shared between sections and recommendations.
 * Failures are isolated per-data-type; one failure never blocks others.
 */
async function fetch360ForCustomer(
  row: ReengagementRow,
  sections: Sections360
): Promise<Partial<CustomerCardEntry>> {
  const result: Partial<CustomerCardEntry> = {};

  // ── Determine what needs to be fetched ──────────────────────────────────
  // recommendations needs everything that's available, so we expand the fetch
  // scope when it's requested — without calling any RPC twice.
  const needsKpis    = sections.has('kpis')    || sections.has('recommendations');
  const needsAging   = sections.has('aging')   || sections.has('recommendations');
  const needsPayment = sections.has('payment') || sections.has('recommendations');
  const needsProducts = sections.has('products') || sections.has('recommendations');

  // ── Parallel fetch — allSettled so one failure never blocks others ────────
  const [kpisResult, agingResult, paymentResult, productsResult] = await Promise.allSettled([
    needsKpis     ? getCustomer360Kpis(row.customer_id)           : Promise.resolve(null as Customer360Kpis | null),
    needsAging    ? getCustomer360ArAging(row.customer_id)         : Promise.resolve([] as CustomerArAgingBucket[]),
    needsPayment  ? getCustomer360PaymentBehavior(row.customer_id) : Promise.resolve(null as CustomerPaymentBehavior | null),
    needsProducts ? getCustomer360TopProducts(row.customer_id, 8)  : Promise.resolve([] as CustomerTopProduct[]),
  ]);

  const rawKpis     = kpisResult.status     === 'fulfilled' ? kpisResult.value     : null;
  const rawAging    = agingResult.status    === 'fulfilled' ? agingResult.value    : [];
  const rawPayment  = paymentResult.status  === 'fulfilled' ? paymentResult.value  : null;
  const rawProducts = productsResult.status === 'fulfilled' ? productsResult.value : [];

  const kpisFailed     = kpisResult.status     === 'rejected';
  const agingFailed    = agingResult.status    === 'rejected';
  const paymentFailed  = paymentResult.status  === 'rejected';
  const productsFailed = productsResult.status === 'rejected';

  // ── Map to card types ────────────────────────────────────────────────────

  // KPIs
  if (sections.has('kpis')) {
    if (kpisFailed) {
      result.kpis360 = 'error';
    } else {
      result.kpis360 = rawKpis ? {
        netRevenue:           rawKpis.net_revenue,
        totalCollected:       rawKpis.total_collected,
        orderCount:           rawKpis.order_count,
        returnRatePct:        rawKpis.return_rate_pct,
        creditUtilizationPct: rawKpis.credit_utilization_pct,
        customerSinceDays:    rawKpis.customer_since_days,
        outstandingBalance:   rawKpis.outstanding_balance,
      } as CustomerCardKpis : null;
    }
  }

  // Products
  if (sections.has('products')) {
    if (productsFailed) {
      result.products360 = 'error';
    } else {
      result.products360 = rawProducts.slice(0, 8).map(p => ({
        name:         p.product_name,
        category:     p.category_name,
        totalValue:   fmtCur(Number(p.total_value)),
        orderCount:   Number(p.order_count ?? 0),
        lastPurchase: fmtDate(p.last_purchase_date),
        status:       p.status,
      } as CustomerCardProduct));
    }
  }

  // Payment Behavior
  if (sections.has('payment')) {
    if (paymentFailed) {
      result.paymentBehavior360 = 'error';
    } else if (rawPayment) {
      const breakdown = rawPayment.payment_methods_breakdown || {};
      const cash     = breakdown['cash']          ?? 0;
      const cheque   = breakdown['cheque']        ?? 0;
      const transfer = breakdown['bank_transfer'] ?? 0;
      const total    = Object.values(breakdown).reduce((s: number, v: any) => s + Number(v), 0);
      const pct = (v: number) => total > 0 ? Math.round((v / total) * 100) : 0;

      result.paymentBehavior360 = {
        avgDelayDays: rawPayment.avg_payment_delay_days,
        cashPct:      pct(cash),
        chequePct:    pct(cheque),
        transferPct:  pct(transfer),
      } as CustomerCardPaymentBehavior;
    } else {
      result.paymentBehavior360 = null;
    }
  }

  // AR Aging
  if (sections.has('aging')) {
    if (agingFailed) {
      result.arAging360 = 'error';
    } else {
      result.arAging360 = rawAging.map(b => ({
        bucket: b.bucket,
        amount: Number(b.amount),
      } as CustomerCardAgingBucket));
    }
  }

  // Recommendations — powered by all available raw data (no repeat RPCs)
  if (sections.has('recommendations')) {
    try {
      const agingForRec = agingFailed ? null : rawAging;
      const kpisForRec  = kpisFailed  ? null : rawKpis;
      const pbForRec    = paymentFailed ? null : rawPayment;

      const churnedCount = productsFailed ? 0 : rawProducts.filter(p => p.status === 'خامد').length;

      const recs = computeRecommendations({
        customer: {
          id:              row.customer_id,
          current_balance: row.outstanding_balance,
          is_active:       row.is_active,
        },
        kpis:            kpisForRec as any,
        arAging:         agingForRec,
        paymentBehavior: pbForRec as any,
        churned_products_count: churnedCount || undefined,
      });

      result.recommendations360 = recs.slice(0, 5).map(r => ({
        severity: r.severity,
        title:    r.title,
        reason:   r.reason,
      } as CustomerCardRecommendation));
    } catch {
      result.recommendations360 = 'error';
    }
  }

  return result;
}

// ─── Build Customer Card Entries ─────────────────────────────────────────────

async function buildCustomerCards(
  rows: ReengagementRow[],
  include360: boolean,
  sections360: Sections360,
  limit360: number
): Promise<CustomerCardEntry[]> {
  const cards: CustomerCardEntry[] = [];

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const cfg = PRIORITY_CFG[row.priority_label];

    const baseEntry: CustomerCardEntry = {
      customerId:        row.customer_id,
      customerName:      row.customer_name,
      customerCode:      row.customer_code,
      customerType:      row.customer_type === 'retail'      ? 'تجزئة'
                         : row.customer_type === 'wholesale' ? 'جملة'
                         : row.customer_type === 'distributor' ? 'موزع'
                         : row.customer_type,
      priorityLabel:    row.priority_label,
      priorityDisplay:  cfg?.display ?? row.priority_label,
      priorityAccent:   cfg?.accent  ?? '#64748b',
      repName:          row.rep_name || 'بدون مندوب',
      governorate:      row.governorate_name || '—',
      city:             row.city_name || '—',
      historicalRevenue: row.historical_revenue,
      revenueL90d:      row.revenue_last_90d,
      recencyDays:      row.recency_days,
      lastOrderDate:    row.last_order_date,
      outstandingBalance: row.outstanding_balance,
      orderCount:       row.order_count,
      valueTier:        row.value_tier,
    };

    // 360° للأوائل فقط
    if (include360 && i < limit360 && sections360.size > 0) {
      const data360 = await fetch360ForCustomer(row, sections360);
      cards.push({ ...baseEntry, ...data360 });
    } else {
      cards.push(baseEntry);
    }
  }

  return cards;
}

// ─── Definition ───────────────────────────────────────────────────────────────

export const reengagementReportDefinition: DocumentDefinition = {
  kind: 'reengagement-report',
  title: 'تقرير إعادة الاستهداف',
  defaultPaper: 'a4-portrait',
  supportedOutputs: ['print', 'pdf-browser', 'pdf-download'],
  supportedPapers:  ['a4-portrait', 'a4-landscape'],
  isArchivable:     false,
  maxSyncPages:     500,

  fetchAndBuild: async ({ filters = {}, locale }) => {
    // ── Parse params ────────────────────────────────────────────────────────
    const include360  = filters.include360 === '1' || filters.include360 === true;
    const limit360    = Math.min(parseInt(String(filters.limit360 ?? '30'), 10) || 30, 30);
    const sections360 = new Set<string>(
      typeof filters.sections360 === 'string'
        ? filters.sections360.split(',').map((s: string) => s.trim()).filter(Boolean)
        : ['kpis', 'products', 'payment', 'recommendations']
    );

    // ── Build the filters for the RPC ───────────────────────────────────────
    const rpcFilters = {
      dateFrom:      filters.dateFrom      || undefined,
      dateTo:        filters.dateTo        || undefined,
      repId:         filters.repId         || undefined,
      governorateId: filters.governorateId || undefined,
      cityId:        filters.cityId        || undefined,
      priority:      (filters.priority     || undefined) as PriorityLabel | undefined,
      customerType:  filters.customerType  || undefined,
      activeOnly:    filters.activeOnly !== 'false' && filters.activeOnly !== false,
    };

    // ── Fetch in parallel: branding + list + summary ────────────────────────
    const [branding, rows, summary] = await Promise.all([
      resolveCompanyBranding(),
      getReengagementList({ ...rpcFilters, limit: 100 }),
      getReengagementSummary(rpcFilters),
    ]);

    const issuedAt = formatDateTime(new Date().toISOString());
    const filterSummary = buildFilterSummary(filters);

    // ── Build customer cards (with optional 360) ────────────────────────────
    const customerCards = await buildCustomerCards(rows, include360, sections360, limit360);

    // ── Summary table rows ──────────────────────────────────────────────────
    const summaryTableRows = rows.map((row, idx) => ({
      rank:     String(idx + 1),
      name:     row.customer_name,
      code:     row.customer_code || '—',
      priority: PRIORITY_CFG[row.priority_label]?.display ?? row.priority_label,
      revenue:  fmtCur(row.historical_revenue),
      recency:  fmtRecency(row.recency_days),
      balance:  fmtCur(Math.abs(row.outstanding_balance)),
      rep:      row.rep_name || 'بدون مندوب',
      gov:      row.governorate_name || '—',
    }));

    // ── Notes ───────────────────────────────────────────────────────────────
    const notes: string[] = [];

    // حدود التقرير: إذا كان عدد المطابقين أكثر من المعروضين
    const totalMatched = summary.total_customers ?? rows.length;
    if (totalMatched > rows.length) {
      notes.push(
        `• التقرير يعرض أول ${rows.length} عميل حسب ترتيب الأولوية` +
        ` من أصل ${totalMatched} عميل مطابق للفلاتر.`
      );
    }

    // حدود 360°
    if (include360 && rows.length > limit360) {
      notes.push(
        `• بيانات 360° مضمّنة لأول ${limit360} عميل فقط حسب ترتيب الأولوية. ` +
        `باقي العملاء (${rows.length - limit360}) موجودون بالبيانات الأساسية.`
      );
    }
    if (include360 && sections360.size > 0) {
      const sectionNames: Record<string, string> = {
        kpis: 'الملخص التنفيذي',
        products: 'أبرز المنتجات',
        payment: 'سلوك السداد',
        recommendations: 'التوصيات',
        aging: 'أعمار الديون',
      };
      const includedSections = [...sections360].map(s => sectionNames[s] ?? s).join(' · ');
      notes.push(`• الأقسام المضمّنة في 360°: ${includedSections}`);
    }
    notes.push('• سري — للاستخدام الداخلي فقط');

    return {
      kind:      'reengagement-report',
      title:     'تقرير إعادة الاستهداف',
      issuedAt,
      direction: 'rtl',
      locale,
      company:   branding,
      parties:   [],
      meta: [
        { label: 'تاريخ التقرير',            value: issuedAt },
        { label: 'الفلاتر النشطة',            value: filterSummary },
        { label: 'عدد العملاء في التقرير',    value: String(rows.length) },
        ...(totalMatched > rows.length ? [
          { label: 'إجمالي مطابق للفلاتر',   value: String(totalMatched) }
        ] : []),
        { label: 'Champion Lost',             value: String(summary.champion_lost_count) },
        { label: 'تراجع عالي',                value: String(summary.declining_high_count) },
        { label: 'صافي الأرصدة',              value: fmtCur(Math.abs(summary.total_outstanding)) },
      ],
      sections: [
        // ── KPI Summary ──────────────────────────────
        {
          type:  'summary',
          title: 'ملخص إعادة الاستهداف',
          items: [
            { label: '🔴 Champion Lost',  value: String(summary.champion_lost_count) },
            { label: '🟠 تراجع عالي',     value: String(summary.declining_high_count) },
            { label: '🟡 متوسط خامد',     value: String(summary.mid_lost_count) },
            { label: '🟤 متوسط معرض',     value: String(summary.mid_at_risk_count) },
            { label: 'في التقرير',        value: String(rows.length) },
            ...(totalMatched > rows.length ? [
              { label: 'مطابق للفلاتر',   value: String(totalMatched) }
            ] : []),
            { label: 'صافي الأرصدة',      value: fmtCur(Math.abs(summary.total_outstanding)) },
            ...(summary.avg_recency_days != null ? [
              { label: 'متوسط أيام الغياب', value: `${Math.round(summary.avg_recency_days)} يوم` }
            ] : []),
          ],
        },

        // ── Summary Table (للمشرف) ───────────────────
        {
          type: 'table',
          title: `قائمة العملاء المستهدفين (${rows.length}${totalMatched > rows.length ? ` من أصل ${totalMatched}` : ''})`,
          columns: [
            { key: 'rank',     label: '#',               align: 'center' as const, width: '32px'  },
            { key: 'name',     label: 'العميل',          align: 'start'  as const               },
            { key: 'code',     label: 'الكود',           align: 'start'  as const, width: '80px'  },
            { key: 'priority', label: 'الأولوية',        align: 'start'  as const, width: '120px' },
            { key: 'revenue',  label: 'القيمة التاريخية', align: 'end'   as const, width: '110px' },
            { key: 'recency',  label: 'آخر شراء',        align: 'center' as const, width: '90px'  },
            { key: 'balance',  label: 'الرصيد',          align: 'end'    as const, width: '100px' },
            { key: 'rep',      label: 'المندوب',         align: 'start'  as const, width: '100px' },
            { key: 'gov',      label: 'المحافظة',        align: 'start'  as const, width: '90px'  },
          ],
          rows: summaryTableRows,
        },

        // ── Customer Cards ───────────────────────────
        {
          type:      'customer-card',
          customers: customerCards,
        },
      ],
      totals: null,
      notes,
    };
  },

  // ── CSV Export Schema ──────────────────────────────────────────────────────
  exportSchema: {
    columns: [
      { key: 'rank',              header: '#' },
      { key: 'customerName',      header: 'اسم العميل' },
      { key: 'customerCode',      header: 'كود العميل' },
      { key: 'customerType',      header: 'النوع' },
      { key: 'priorityDisplay',   header: 'الأولوية' },
      { key: 'repName',           header: 'المندوب' },
      { key: 'governorate',       header: 'المحافظة' },
      { key: 'city',              header: 'المدينة' },
      { key: 'historicalRevenue', header: 'القيمة التاريخية (ج.م)' },
      { key: 'recency',           header: 'آخر شراء (أيام)' },
      { key: 'lastOrderDate',     header: 'تاريخ آخر طلب' },
      { key: 'outstandingBalance',header: 'الرصيد (ج.م)' },
      { key: 'orderCount',        header: 'عدد الطلبات' },
      { key: 'valueTier',         header: 'شريحة القيمة' },
    ],
    buildRows: (entities: any[]) =>
      entities.map((row, idx) => ({
        rank:               idx + 1,
        customerName:       row.customer_name,
        customerCode:       row.customer_code || '',
        customerType:       row.customer_type === 'retail' ? 'تجزئة'
                            : row.customer_type === 'wholesale' ? 'جملة' : 'موزع',
        priorityDisplay:    PRIORITY_CFG[row.priority_label as PriorityLabel]?.display ?? row.priority_label,
        repName:            row.rep_name || 'بدون مندوب',
        governorate:        row.governorate_name || '',
        city:               row.city_name || '',
        historicalRevenue:  row.historical_revenue,
        recency:            row.recency_days ?? '',
        lastOrderDate:      row.last_order_date || '',
        outstandingBalance: row.outstanding_balance,
        orderCount:         row.order_count,
        valueTier:          row.value_tier,
      })),
  },
};
