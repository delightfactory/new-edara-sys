import { DocumentDefinition } from './document-definition';
import { resolveCompanyBranding } from '../branding/branding-resolver';
import { getSalesOrder } from '@/lib/services/sales';
import { formatDate, formatNumber } from '@/lib/utils/format';
import { SalesOrderStatus } from '@/lib/types/master-data';

// [ENGINEERING NOTE]: These labels are intentionally synced with the local ones in SalesOrderDetail.tsx.
// If you update one, you MUST update the other to maintain UI/Print consistency.
// We keep them co-located to avoid polluting global shared types with domain-specific UI labels.
const statusLabels: Record<SalesOrderStatus, string> = {
  draft: 'مسودة',
  confirmed: 'مؤكد',
  partially_delivered: 'مسلّم جزئياً',
  delivered: 'مُسلّم',
  completed: 'مكتمل',
  cancelled: 'ملغي',
};

const termLabels: Record<string, string> = {
  cash: 'نقدي',
  credit: 'آجل',
  mixed: 'مختلط'
};

const deliveryMethodLabels: Record<string, string> = {
  direct: 'مباشر (توصيل مندوب)',
  shipping: 'شحن شركات',
  pickup: 'استلام من الفرع',
};

export const salesOrderDefinition: DocumentDefinition = {
  kind: 'sales-order',
  title: 'أمر بيع',
  defaultPaper: 'a4-portrait',
  supportedOutputs: ['print', 'pdf-browser', 'pdf-download'],
  supportedPapers: ['a4-portrait', 'a4-landscape', 'thermal-80mm'],
  isArchivable: true,
  maxSyncPages: 10,

  fetchAndBuild: async ({ entityId, locale, direction, paperProfileId }) => {
    if (!entityId) throw new Error('entityId is required for sales-order');

    const [order, branding] = await Promise.all([
      getSalesOrder(entityId),
      resolveCompanyBranding()
    ]);

    const remaining = Math.max(order.total_amount - (order.paid_amount || 0) - (order.returned_amount || 0), 0);

    const parties = [
      {
        role: 'العميل',
        name: order.customer?.name || '—',
        code: order.customer?.code,
        phone: order.customer?.phone
      }
    ];

    if (order.rep) {
      parties.push({ role: 'المندوب', name: order.rep.full_name, code: undefined, phone: undefined });
    }
    if (order.branch) {
      parties.push({ role: 'الفرع', name: order.branch.name, code: undefined, phone: undefined });
    }

    const meta = [
      { label: 'رقم الطلب', value: order.order_number || '—', dir: 'ltr' as const },
      { label: 'تاريخ الطلب', value: formatDate(order.order_date) },
      { label: 'حالة الطلب', value: order.status ? (statusLabels[order.status] || order.status) : '—' },
      { label: 'شروط الدفع', value: order.payment_terms ? (termLabels[order.payment_terms] || order.payment_terms) : '—' },
    ];

    if (order.due_date) meta.push({ label: 'تاريخ الاستحقاق', value: formatDate(order.due_date) });
    if (order.expected_delivery) meta.push({ label: 'تاريخ التسليم المتوقع', value: formatDate(order.expected_delivery) });
    if (order.delivery_method) meta.push({ label: 'وسيلة التسليم', value: deliveryMethodLabels[order.delivery_method] || order.delivery_method });
    if (order.warehouse) meta.push({ label: 'المخزن', value: order.warehouse.name });
    if (order.shipping_company) meta.push({ label: 'شركة الشحن', value: order.shipping_company.name });
    if (order.tracking_number) meta.push({ label: 'رقم التتبع', value: order.tracking_number, dir: 'ltr' as const });

    // ── Shared item rows for A4 full table ────────────────────────
    const rows = (order.items || []).map(item => {
      const unitLabel = item.unit?.symbol || item.unit?.name || '';
      return {
        product: item.product?.name || '—',
        sku: item.product?.sku || '—',
        qty: `${item.quantity} ${unitLabel}`,
        delivered: item.delivered_quantity > 0 ? `${item.delivered_quantity}` : '0',
        returned: item.returned_quantity > 0 ? `${item.returned_quantity}` : '0',
        price: formatNumber(item.unit_price),
        discount: item.discount_amount > 0 ? `${formatNumber(item.discount_amount)}` : '0',
        tax: item.tax_amount > 0 ? `${formatNumber(item.tax_amount)}` : '0',
        total: formatNumber(item.line_total),
      };
    });

    // ── Thermal compact variant ──────────────────────────────────────
    const isThermal = paperProfileId?.startsWith('thermal');

    if (isThermal) {
      const compactItems = (order.items || []).map(item => {
        const unitLabel = item.unit?.symbol || item.unit?.name || '';
        const parts: string[] = [];
        if (item.discount_amount > 0) parts.push(`خصم ${formatNumber(item.discount_amount)} ${branding.currencySymbol}`);
        if (item.tax_amount > 0) parts.push(`ضريبة ${formatNumber(item.tax_amount)} ${branding.currencySymbol}`);
        if (unitLabel) parts.push(unitLabel);
        return {
          name: item.product?.name || '—',
          qtyPrice: `${formatNumber(item.quantity)} × ${formatNumber(item.unit_price)} ${branding.currencySymbol}`,
          details: parts.length > 0 ? parts.join(' | ') : null,
          lineTotal: `${formatNumber(item.line_total)} ${branding.currencySymbol}`,
        };
      });

      const thermalKvRows: { label: string; value: string; dir?: 'rtl' | 'ltr' }[] = [];
      if (order.customer?.name) thermalKvRows.push({ label: 'العميل', value: order.customer.name });
      // Show code even if phone is absent
      if (order.customer?.code) thermalKvRows.push({ label: 'الكود', value: order.customer.code, dir: 'ltr' });
      if (order.customer?.phone) thermalKvRows.push({ label: 'هاتف', value: order.customer.phone, dir: 'ltr' });
      if (order.rep) thermalKvRows.push({ label: 'المندوب', value: order.rep.full_name });
      if (order.branch) thermalKvRows.push({ label: 'الفرع', value: order.branch.name });
      if (order.warehouse) thermalKvRows.push({ label: 'المخزن', value: order.warehouse.name });
      if (order.payment_terms) thermalKvRows.push({ label: 'الدفع', value: termLabels[order.payment_terms] || order.payment_terms });
      if (order.delivery_method) thermalKvRows.push({ label: 'التسليم', value: deliveryMethodLabels[order.delivery_method] || order.delivery_method });
      if (order.tracking_number) thermalKvRows.push({ label: 'رقم التتبع', value: order.tracking_number, dir: 'ltr' });

      return {
        kind: 'sales-order' as const,
        title: 'أمر بيع',
        number: order.order_number,
        status: order.status ? (statusLabels[order.status] || order.status) : '—',
        issuedAt: formatDate(order.order_date),
        direction,
        locale,
        company: branding,
        // Parties are preserved in the canonical model for consistency with A4.
        // ThermalLayout renders them only if present; KV rows handle the detailed display.
        parties,
        meta: [
          { label: 'رقم الطلب', value: order.order_number || '—', dir: 'ltr' as const },
          { label: 'التاريخ', value: formatDate(order.order_date) },
        ],
        sections: [
          ...(thermalKvRows.length > 0 ? [{ type: 'kv' as const, title: 'بيانات الطلب', rows: thermalKvRows }] : []),
          { type: 'compact-items' as const, title: 'البنود', items: compactItems },
        ],
        totals: {
          subtotal: `${formatNumber(order.subtotal)} ${branding.currencySymbol}`,
          discount: order.discount_amount > 0 ? `${formatNumber(order.discount_amount)} ${branding.currencySymbol}` : undefined,
          tax: order.tax_amount > 0 ? `${formatNumber(order.tax_amount)} ${branding.currencySymbol}` : undefined,
          total: `${formatNumber(order.total_amount)} ${branding.currencySymbol}`,
          paid: order.paid_amount > 0 ? `${formatNumber(order.paid_amount)} ${branding.currencySymbol}` : undefined,
          remaining: remaining > 0 ? `${formatNumber(remaining)} ${branding.currencySymbol}` : undefined,
        },
        notes: order.notes ? [order.notes] : undefined,
      };
    }

    const approvals = [];
    if (order.created_by_profile) approvals.push({ label: 'أنشئ بواسطة', value: order.created_by_profile.full_name });
    // If we had confirmed_by, we would add it here. For now we just put fixed signature fields
    approvals.push({ label: 'اعتماد العميل / المستلم', value: '' });

    let totalQty = 0;
    let totalDelivered = 0;
    let totalReturned = 0;
    (order.items || []).forEach(item => {
      totalQty += item.quantity;
      totalDelivered += item.delivered_quantity;
      totalReturned += item.returned_quantity;
    });

    const summaryItems = [];
    summaryItems.push({ label: 'إجمالي عدد البنود', value: `${rows.length}` });
    if (totalQty > 0) summaryItems.push({ label: 'إجمالي الكمية المطلوبة', value: `${formatNumber(totalQty)}` });
    if (totalDelivered > 0) summaryItems.push({ label: 'إجمالي المُسلّم', value: `${formatNumber(totalDelivered)}` });
    if (totalReturned > 0) summaryItems.push({ label: 'إجمالي المرتجع', value: `${formatNumber(totalReturned)}` });

    const finalSections: any[] = [
      {
        type: 'kv',
        title: 'بيانات العميل والتسليم',
        rows: [
          { label: 'اسم العميل', value: order.customer?.name || '—' },
          ...(order.customer?.code ? [{ label: 'كود العميل', value: order.customer.code, dir: 'ltr' as const }] : []),
          ...(order.customer?.phone ? [{ label: 'هاتف العميل', value: order.customer.phone, dir: 'ltr' as const }] : []),
          ...(order.rep ? [{ label: 'المندوب', value: order.rep.full_name }] : []),
          ...(order.branch ? [{ label: 'الفرع', value: order.branch.name }] : []),
          ...(order.delivery_address ? [{ label: 'عنوان التسليم', value: order.delivery_address.name || order.delivery_address.address || '—' }] : []),
          ...(order.delivery_method ? [{ label: 'وسيلة التسليم', value: deliveryMethodLabels[order.delivery_method] || order.delivery_method }] : []),
          ...(order.shipping_company ? [{ label: 'شركة الشحن', value: order.shipping_company.name }] : []),
          ...(order.tracking_number ? [{ label: 'رقم التتبع', value: order.tracking_number, dir: 'ltr' as const }] : [])
        ]
      },
      {
        type: 'table',
        title: 'بنود الطلب',
        columns: [
          { key: 'product', label: 'المنتج / الصنف' },
          { key: 'sku', label: 'SKU', dir: 'ltr' },
          { key: 'qty', label: 'الكمية', align: 'center' },
          { key: 'delivered', label: 'مُسلّم', align: 'center' },
          { key: 'returned', label: 'مرتجع', align: 'center' },
          { key: 'price', label: 'سعر الوحدة', align: 'start' },
          { key: 'discount', label: 'خصم', align: 'start' },
          { key: 'tax', label: 'ضريبة', align: 'start' },
          { key: 'total', label: 'الإجمالي', align: 'start' },
        ],
        rows
      }
    ];

    if (summaryItems.length > 0) {
      finalSections.push({
        type: 'summary',
        title: 'ملخص التنفيذ',
        items: summaryItems
      });
    }

    return {
      kind: 'sales-order',
      title: 'أمر بيع',
      number: order.order_number,
      status: order.status ? (statusLabels[order.status] || order.status) : '—',
      issuedAt: formatDate(order.order_date),
      direction,
      locale,
      company: branding,
      parties,
      meta,
      sections: finalSections,
      totals: {
        subtotal: `${formatNumber(order.subtotal)} ${branding.currencySymbol}`,
        discount: order.discount_amount > 0 ? `${formatNumber(order.discount_amount)} ${branding.currencySymbol}` : undefined,
        tax: order.tax_amount > 0 ? `${formatNumber(order.tax_amount)} ${branding.currencySymbol}` : undefined,
        total: `${formatNumber(order.total_amount)} ${branding.currencySymbol}`,
        paid: order.paid_amount > 0 ? `${formatNumber(order.paid_amount)} ${branding.currencySymbol}` : undefined,
        // Only show remaining if it is actually non-zero.
        // Showing "0.00 ج.م" when fully paid is misleading on printed documents.
        remaining: remaining > 0 ? `${formatNumber(remaining)} ${branding.currencySymbol}` : undefined,
      },
      notes: order.notes ? [order.notes] : undefined,
      approvals
    };
  }
};
