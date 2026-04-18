import { DocumentDefinition } from './document-definition';
import { resolveCompanyBranding } from '../branding/branding-resolver';
import { getPurchaseInvoice } from '@/lib/services/purchases';
import { formatDate, formatNumber } from '@/lib/utils/format';
import { PurchaseInvoiceStatus } from '@/lib/types/master-data';

const statusLabels: Record<PurchaseInvoiceStatus, string> = {
  draft: 'مسودة',
  received: 'مستلمة',
  billed: 'معتمدة',
  paid: 'مدفوعة',
  cancelled: 'ملغاة',
};

const paymentMethodMap: Record<string, string> = {
  cash: 'نقدي',
  bank_transfer: 'تحويل بنكي',
  instapay: 'إنستاباي',
  cheque: 'شيك',
  mobile_wallet: 'محفظة إلكترونية',
  deferred: 'آجل'
};

export const purchaseInvoiceDefinition: DocumentDefinition = {
  kind: 'purchase-invoice',
  title: 'فاتورة شراء',
  defaultPaper: 'a4-portrait',
  supportedOutputs: ['print', 'pdf-browser', 'pdf-download'],
  supportedPapers: ['a4-portrait', 'a4-landscape', 'thermal-80mm'],
  isArchivable: true,
  maxSyncPages: 10,

  fetchAndBuild: async ({ entityId, locale, direction, paperProfileId }) => {
    if (!entityId) throw new Error('entityId is required for purchase-invoice');

    const [branding, invoice] = await Promise.all([
      resolveCompanyBranding(),
      getPurchaseInvoice(entityId)
    ]);

    if (!invoice) throw new Error('لم يتم العثور على الفاتورة');

    let totalOrderedQty = 0;
    let totalReceivedQty = 0;
    const rows = (invoice.items || []).map((item: any) => {
      totalOrderedQty += item.ordered_quantity;
      totalReceivedQty += item.received_quantity || 0;
      const netLine = (item.ordered_quantity * item.unit_price * (1 - (item.discount_rate || 0) / 100)) * (1 + (item.tax_rate || 0) / 100);
      return {
        product: item.product?.name || '—',
        sku: item.product?.sku || '',
        unit: item.unit?.symbol || item.unit?.name || '—',
        ordered_qty: formatNumber(item.ordered_quantity),
        received_qty: formatNumber(item.received_quantity || 0),
        price: `${formatNumber(item.unit_price)} ${branding.currencySymbol}`,
        discount: item.discount_rate ? `%${item.discount_rate}` : '—',
        tax: item.tax_rate ? `%${item.tax_rate}` : '—',
        total: `${formatNumber(netLine)} ${branding.currencySymbol}`
      };
    });

    const kvRows = [];
    if (invoice.supplier?.name) kvRows.push({ label: 'اسم المورد', value: invoice.supplier.name });
    if (invoice.supplier?.code) kvRows.push({ label: 'كود المورد', value: invoice.supplier.code, dir: 'ltr' as const });
    if (invoice.warehouse?.name) kvRows.push({ label: 'المخزن المستلم', value: invoice.warehouse.name });
    if (invoice.supplier_invoice_ref) kvRows.push({ label: 'مرجع المورد', value: invoice.supplier_invoice_ref, dir: 'ltr' as const });
    if (invoice.due_date) kvRows.push({ label: 'تاريخ الاستحقاق', value: formatDate(invoice.due_date) });
    
    if (invoice.payment_method) kvRows.push({ label: 'طريقة السداد', value: paymentMethodMap[invoice.payment_method] || invoice.payment_method });

    const sections: any[] = [];
    if (kvRows.length > 0) {
      sections.push({
        type: 'kv',
        title: 'بيانات المورد والفاتورة',
        rows: kvRows
      });
    }

    sections.push({
      type: 'table',
      title: 'البنود',
      columns: [
        { key: 'product', label: 'المنتج', align: 'start' },
        { key: 'sku', label: 'SKU', align: 'start' },
        { key: 'unit', label: 'الوحدة', align: 'center' },
        { key: 'ordered_qty', label: 'الكمية', align: 'center' },
        { key: 'received_qty', label: 'المستلم', align: 'center' },
        { key: 'price', label: 'السعر', align: 'center' },
        { key: 'discount', label: 'خصم', align: 'center' },
        { key: 'tax', label: 'ضريبة', align: 'center' },
        { key: 'total', label: 'الإجمالي', align: 'end' },
      ],
      rows
    });

    if (rows.length > 0) {
      sections.push({
        type: 'summary',
        items: [
          { label: 'عدد البنود', value: formatNumber(rows.length) },
          { label: 'إجمالي الكمية المطلوبة', value: formatNumber(totalOrderedQty) },
          { label: 'إجمالي الكمية المستلمة', value: formatNumber(totalReceivedQty) }
        ]
      });
    }

    const metaItems = [
      { label: 'رقم الفاتورة', value: invoice.number, dir: 'ltr' as const },
      { label: 'تاريخ الفاتورة', value: formatDate(invoice.invoice_date) }
    ];

    if (invoice.landed_costs && invoice.landed_costs > 0) {
      metaItems.push({ label: 'مصاريف الشحن/الجمارك', value: `${formatNumber(invoice.landed_costs)} ${branding.currencySymbol}` });
    }

    // ── Thermal compact variant ────────────────────────────────────
    if (paperProfileId?.startsWith('thermal')) {
      const compactItems = (invoice.items || []).map((item: any) => {
        const netLine = (item.ordered_quantity * item.unit_price * (1 - (item.discount_rate || 0) / 100)) * (1 + (item.tax_rate || 0) / 100);
        const unitLabel = item.unit?.symbol || item.unit?.name || '';
        const parts: string[] = [];
        if (item.discount_rate) parts.push(`خصم %${item.discount_rate}`);
        if (item.tax_rate) parts.push(`ضريبة %${item.tax_rate}`);
        if (unitLabel) parts.push(unitLabel);
        return {
          name: item.product?.name || '—',
          qtyPrice: `${formatNumber(item.ordered_quantity)} × ${formatNumber(item.unit_price)} ${branding.currencySymbol}`,
          details: parts.length > 0 ? parts.join(' | ') : null,
          lineTotal: `${formatNumber(netLine)} ${branding.currencySymbol}`,
        };
      });

      const thermalKvRows: { label: string; value: string; dir?: 'rtl' | 'ltr' }[] = [];
      if (invoice.supplier?.name) thermalKvRows.push({ label: 'المورد', value: invoice.supplier.name });
      // Always show supplier code if available (operational reference)
      if (invoice.supplier?.code) thermalKvRows.push({ label: 'كود المورد', value: invoice.supplier.code, dir: 'ltr' });
      if (invoice.warehouse?.name) thermalKvRows.push({ label: 'المخزن', value: invoice.warehouse.name });
      if (invoice.supplier_invoice_ref) thermalKvRows.push({ label: 'مرجع', value: invoice.supplier_invoice_ref, dir: 'ltr' });
      if (invoice.due_date) thermalKvRows.push({ label: 'استحقاق', value: formatDate(invoice.due_date) });
      // Payment method — using same map as A4 for consistent Arabic labels
      if (invoice.payment_method) thermalKvRows.push({ label: 'طريقة السداد', value: paymentMethodMap[invoice.payment_method] || invoice.payment_method });
      // Landed costs — only if non-zero (meaningful operational cost)
      if (invoice.landed_costs && invoice.landed_costs > 0) {
        thermalKvRows.push({ label: 'مصاريف شحن/جمارك', value: `${formatNumber(invoice.landed_costs)} ${branding.currencySymbol}` });
      }

      return {
        kind: 'purchase-invoice' as const,
        title: 'فاتورة شراء',
        number: invoice.number,
        status: invoice.status ? statusLabels[invoice.status as PurchaseInvoiceStatus] : undefined,
        issuedAt: formatDate(invoice.invoice_date),
        direction,
        locale,
        company: branding,
        // Canonical parties preserved — matching A4 model.
        parties: invoice.supplier
          ? [{ role: 'المورد', name: invoice.supplier.name || '—', code: invoice.supplier.code }]
          : [],
        meta: [
          { label: 'رقم الفاتورة', value: invoice.number, dir: 'ltr' as const },
          { label: 'التاريخ', value: formatDate(invoice.invoice_date) },
        ],
        sections: [
          ...(thermalKvRows.length > 0 ? [{ type: 'kv' as const, title: 'بيانات', rows: thermalKvRows }] : []),
          { type: 'compact-items' as const, title: 'البنود', items: compactItems },
        ],
        totals: {
          subtotal: `${formatNumber(invoice.subtotal)} ${branding.currencySymbol}`,
          discount: invoice.discount_amount > 0 ? `${formatNumber(invoice.discount_amount)} ${branding.currencySymbol}` : undefined,
          tax: invoice.tax_amount > 0 ? `${formatNumber(invoice.tax_amount)} ${branding.currencySymbol}` : undefined,
          total: `${formatNumber(invoice.total_amount)} ${branding.currencySymbol}`,
          paid: invoice.paid_amount > 0 ? `${formatNumber(invoice.paid_amount)} ${branding.currencySymbol}` : undefined,
          remaining: (invoice.total_amount - (invoice.paid_amount || 0)) > 0
            ? `${formatNumber(invoice.total_amount - (invoice.paid_amount || 0))} ${branding.currencySymbol}`
            : undefined,
        },
        notes: invoice.notes ? [invoice.notes] : undefined,
      };
    }

    return {
      kind: 'purchase-invoice',
      title: 'فاتورة شراء',
      number: invoice.number,
      status: invoice.status ? statusLabels[invoice.status as PurchaseInvoiceStatus] : undefined,
      issuedAt: formatDate(invoice.invoice_date),
      direction,
      locale,
      company: branding,
      parties: [
        {
          role: 'المورد',
          name: invoice.supplier?.name || '—',
          code: invoice.supplier?.code
        }
      ],
      meta: metaItems,
      sections,
      totals: {
        subtotal: `${formatNumber(invoice.subtotal)} ${branding.currencySymbol}`,
        discount: invoice.discount_amount > 0 ? `${formatNumber(invoice.discount_amount)} ${branding.currencySymbol}` : undefined,
        tax: invoice.tax_amount > 0 ? `${formatNumber(invoice.tax_amount)} ${branding.currencySymbol}` : undefined,
        total: `${formatNumber(invoice.total_amount)} ${branding.currencySymbol}`,
        paid: invoice.paid_amount > 0 ? `${formatNumber(invoice.paid_amount)} ${branding.currencySymbol}` : undefined,
        remaining: (invoice.total_amount - (invoice.paid_amount || 0)) > 0 ? `${formatNumber(invoice.total_amount - (invoice.paid_amount || 0))} ${branding.currencySymbol}` : undefined,
      },
      notes: invoice.notes ? [invoice.notes] : undefined
    };
  }
};
