import { DocumentDefinition } from './document-definition';
import { resolveCompanyBranding } from '../branding/branding-resolver';
import { getPaymentReceipt } from '@/lib/services/payments';
import { formatDate, formatNumber } from '@/lib/utils/format';

export const paymentReceiptDefinition: DocumentDefinition = {
  kind: 'payment-receipt',
  title: 'سند استلام نقدية / تحصيل',
  defaultPaper: 'a4-portrait',
  supportedOutputs: ['print', 'pdf-browser', 'pdf-download'],
  supportedPapers: ['a4-portrait', 'thermal-80mm', 'thermal-58mm'],
  isArchivable: true,
  maxSyncPages: 1,

  fetchAndBuild: async ({ entityId, locale, direction }) => {
    if (!entityId) throw new Error('entityId is required for payment-receipt');

    const [receipt, branding] = await Promise.all([
      getPaymentReceipt(entityId),
      resolveCompanyBranding()
    ]);

    return {
      kind: 'payment-receipt',
      title: 'سند قبض',
      number: receipt.number,
      status: receipt.status === 'confirmed' ? 'مؤكد' : receipt.status === 'rejected' ? 'مرفوض' : 'معلق — بانتظار المراجعة',
      issuedAt: formatDate(receipt.created_at),
      direction,
      locale,
      company: branding,
      parties: [
        {
          role: 'استلمنا من السيد/الشركة',
          name: receipt.customer?.name || 'عميل نقدي',
          code: receipt.customer?.code
        }
      ],
      meta: [
        { label: 'رقم الإيصال', value: receipt.number, dir: 'ltr' as const },
        { label: 'التاريخ', value: formatDate(receipt.created_at) },
        { label: 'طريقة الدفع', value: receipt.payment_method === 'cash' ? 'نقدي' : receipt.payment_method === 'bank_transfer' ? 'تحويل بنكي' : receipt.payment_method },
        { label: 'المبلغ', value: `${formatNumber(receipt.amount)} ${branding.currencySymbol}` },
      ],
      sections: [
        {
          type: 'plain-text',
          title: 'مبلغ وقدره',
          content: `${formatNumber(receipt.amount)} ${branding.currencySymbol}`,
          dir: 'rtl'
        },
        {
          type: 'kv',
          title: 'تفاصيل الاستلام',
          rows: [
            { label: 'طريقة الدفع', value: receipt.payment_method === 'cash' ? 'نقدي' : receipt.payment_method === 'bank_transfer' ? 'تحويل بنكي' : receipt.payment_method },
            { label: 'رقم المرجع', value: receipt.bank_reference || receipt.check_number || '-', dir: 'ltr' },
            { label: 'الخزنة / الحساب', value: receipt.vault?.name || '-' },
            { label: 'رقم المبيعات', value: receipt.sales_order?.order_number || '-', dir: 'ltr' },
            { label: 'ملاحظات', value: receipt.notes || '-' },
          ]
        }
      ],
      totals: {
        total: `${formatNumber(receipt.amount)} ${branding.currencySymbol}`
      },
      approvals: receipt.collected_by_profile?.full_name ? [
        { label: 'المستلم (أمين الخزنة)', value: receipt.collected_by_profile.full_name },
      ] : undefined
    };
  }
};
