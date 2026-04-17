import { DocumentDefinition } from './document-definition';
import { resolveCompanyBranding } from '../branding/branding-resolver';
import { getSupplierPaymentVoucher } from '@/lib/services/supplier-payments';
import { formatDate, formatNumber } from '@/lib/utils/format';

const paymentMethodMap: Record<string, string> = {
  cash: 'نقدي',
  bank_transfer: 'تحويل بنكي',
  cheque: 'شيك',
  mobile_wallet: 'محفظة إلكترونية'
};

const statusMap: Record<string, string> = {
  posted: 'مُرحَّل',
  reversed: 'مُعكوس'
};

export const paymentVoucherDefinition: DocumentDefinition = {
  kind: 'payment-voucher',
  title: 'سند صرف مورد',
  defaultPaper: 'a4-portrait',
  supportedOutputs: ['print', 'pdf-browser', 'pdf-download'],
  supportedPapers: ['a4-portrait', 'thermal-80mm'],
  isArchivable: true,
  maxSyncPages: 10,

  fetchAndBuild: async ({ entityId, locale, direction }) => {
    if (!entityId) throw new Error('entityId is required for payment-voucher');

    const [branding, voucher] = await Promise.all([
      resolveCompanyBranding(),
      getSupplierPaymentVoucher(entityId)
    ]);

    if (!voucher) throw new Error('لم يتم العثور على سند الصرف');

    const kvRows = [];
    if (voucher.supplier?.name) kvRows.push({ label: 'المورد', value: voucher.supplier.name });
    if (voucher.supplier?.code) kvRows.push({ label: 'كود المورد', value: voucher.supplier.code, dir: 'ltr' as const });
    if (voucher.payment_method) kvRows.push({ label: 'طريقة الدفع', value: paymentMethodMap[voucher.payment_method] || voucher.payment_method });
    if (voucher.vault?.name) kvRows.push({ label: 'الخزينة / البنك', value: voucher.vault.name });

    const metaItems: any[] = [
      { label: 'رقم السند', value: voucher.number, dir: 'ltr' as const },
      { label: 'تاريخ السداد', value: formatDate(voucher.payment_date) }
    ];
    if (voucher.payment_method) metaItems.push({ label: 'طريقة الدفع', value: paymentMethodMap[voucher.payment_method] || voucher.payment_method });
    if (voucher.supplier?.name) metaItems.push({ label: 'اسم المورد', value: voucher.supplier.name });
    if (voucher.supplier?.code) metaItems.push({ label: 'كود المورد', value: voucher.supplier.code, dir: 'ltr' as const });
    if (voucher.vault?.name) metaItems.push({ label: 'الخزينة / البنك', value: voucher.vault.name });
    if (voucher.status) metaItems.push({ label: 'الحالة', value: statusMap[voucher.status] || voucher.status });

    return {
      kind: 'payment-voucher',
      title: 'سند صرف مورد',
      number: voucher.number,
      status: voucher.status ? statusMap[voucher.status] || voucher.status : undefined,
      issuedAt: formatDate(voucher.payment_date),
      direction,
      locale,
      company: branding,
      parties: [
        {
          role: 'المورد',
          name: voucher.supplier?.name || '—',
          code: voucher.supplier?.code
        }
      ],
      meta: metaItems,
      sections: [
        {
          type: 'kv',
          title: 'بيانات السداد',
          rows: kvRows
        }
      ],
      totals: {
        total: `${formatNumber(voucher.amount)} ${branding.currencySymbol}`
      },
      notes: voucher.notes ? [voucher.notes] : undefined,
      approvals: voucher.created_by_profile?.full_name ? [
        { label: 'أنشئ بواسطة', value: voucher.created_by_profile.full_name }
      ] : undefined
    };
  }
};
