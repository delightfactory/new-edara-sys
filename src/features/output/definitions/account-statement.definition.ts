import { DocumentDefinition } from './document-definition';
import { resolveCompanyBranding } from '../branding/branding-resolver';
import { getCustomerLedger, getCustomerBalance, getSupplierLedger, getSupplierBalance } from '@/lib/services/finance';
import { supabase } from '@/lib/supabase/client';
import { formatDateTime, formatNumber } from '@/lib/utils/format';

const sourceLabel: Record<string, string> = {
  sales_order: 'طلب بيع',
  sales_return: 'مرتجع',
  payment: 'دفعة',
  opening_balance: 'رصيد افتتاحي',
  adjustment: 'تسوية',
  purchase_order: 'أمر شراء',
  purchase_return: 'مرتجع شراء',
};

export const accountStatementDefinition: DocumentDefinition = {
  kind: 'account-statement',
  title: 'كشف حساب',
  defaultPaper: 'a4-portrait',
  supportedOutputs: ['print', 'pdf-browser', 'pdf-download'],
  supportedPapers: ['a4-portrait', 'a4-landscape'],
  isArchivable: true,
  maxSyncPages: 50,

  fetchAndBuild: async ({ entityId, filters, locale, direction }) => {
    if (!entityId) throw new Error('entityId is required for account-statement');

    const ledgerType = filters?.type;
    if (ledgerType !== 'customers' && ledgerType !== 'suppliers') {
      throw new Error('نوع كشف الحساب غير صالح');
    }
    const isCustomer = ledgerType === 'customers';

    const [branding, entityRes, balanceData, ledgerRes] = await Promise.all([
      resolveCompanyBranding(),
      supabase.from(isCustomer ? 'customers' : 'suppliers').select('name, code').eq('id', entityId).single(),
      isCustomer ? getCustomerBalance(entityId) : getSupplierBalance(entityId),
      (async () => {
        let allData: any[] = [];
        let page = 1;
        let totalPages = 1;
        let count = 0;
        do {
          const res = isCustomer 
            ? await getCustomerLedger(entityId, { page, pageSize: 1000 })
            : await getSupplierLedger(entityId, { page, pageSize: 1000 });
          allData = allData.concat(res.data);
          totalPages = res.totalPages;
          count = res.count;
          page++;
        } while (page <= totalPages);
        return { data: allData, count };
      })()
    ]);

    if (entityRes.error) throw new Error('فشل جلب بيانات الحساب');

    const entityName = entityRes.data.name;
    const entityCode = entityRes.data.code;

    const balanceValue = balanceData?.balance || 0;
    const isDebt = balanceValue > 0;
    const balanceLabel = isCustomer
      ? (isDebt ? 'مدين لنا' : 'دائن')
      : (isDebt ? 'ندين له' : 'دائن لنا');

    const titleStr = isCustomer ? 'كشف حساب عميل' : 'كشف حساب مورد';

    const sortedLedger = [...(ledgerRes?.data || [])].sort((a, b) => 
      new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
    );

    const rows = sortedLedger.map((entry: any) => {
      const isDebit = entry.type === 'debit';
      return {
        date: formatDateTime(entry.created_at),
        source: sourceLabel[entry.source_type] || entry.source_type,
        desc: entry.description || '—',
        debit: isDebit ? formatNumber(entry.amount) : '',
        credit: !isDebit ? formatNumber(entry.amount) : '',
      };
    });

    let totalDebit = 0;
    let totalCredit = 0;
    sortedLedger.forEach((entry: any) => {
      if (entry.type === 'debit') totalDebit += entry.amount;
      else totalCredit += entry.amount;
    });

    return {
      kind: 'account-statement',
      title: titleStr,
      issuedAt: formatDateTime(new Date().toISOString()),
      direction,
      locale,
      company: branding,
      parties: [
        { role: isCustomer ? 'العميل' : 'المورد', name: entityName, code: entityCode }
      ],
      meta: [
        { label: 'الاسم', value: entityName },
        { label: 'الكود', value: entityCode, dir: 'ltr' as const },
        { label: 'إجمالي الحركات', value: `${balanceData.transaction_count || ledgerRes.count}` }
      ],
      sections: [
        {
          type: 'summary',
          title: 'ملخص الرصيد',
          items: [
            { label: 'الرصيد الحالي', value: `${formatNumber(Math.abs(balanceValue))} ${branding.currencySymbol} (${balanceLabel})` },
            { label: 'إجمالي مدين (الفترة)', value: `${formatNumber(totalDebit)} ${branding.currencySymbol}` },
            { label: 'إجمالي دائن (الفترة)', value: `${formatNumber(totalCredit)} ${branding.currencySymbol}` },
          ]
        },
        {
          type: 'table',
          title: 'حركات الحساب',
          columns: [
            { key: 'date', label: 'التاريخ', align: 'start' },
            { key: 'source', label: 'المصدر', align: 'start' },
            { key: 'desc', label: 'البيان', align: 'start' },
            { key: 'debit', label: 'مدين', align: 'center' },
            { key: 'credit', label: 'دائن', align: 'center' },
          ],
          rows
        }
      ]
    };
  }
};
