import { supabase } from '@/lib/supabase/client';
import { CompanyBranding } from '../models/canonical-document';

let _cachedBranding: CompanyBranding | null = null;
let _lastFetchTime = 0;
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

export async function resolveCompanyBranding(forceRefresh = false): Promise<CompanyBranding> {
  const now = Date.now();
  
  if (!forceRefresh && _cachedBranding && (now - _lastFetchTime < CACHE_TTL_MS)) {
    return _cachedBranding;
  }

  const { data, error } = await supabase
    .from('company_settings')
    .select('key, value');
    
  if (error) {
    console.error('Error fetching company branding:', error);
    return getFallbackBranding();
  }

  if (!data || data.length === 0) {
    return getFallbackBranding();
  }

  const map = new Map(data.map(d => [d.key, d.value]));

  const branding: CompanyBranding = {
    name: map.get('company.name') || 'الشركة مجهولة',
    nameEn: map.get('company.name_en') || null,
    logoUrl: map.get('company.logo_url') || null,
    phone: map.get('company.phone') || null,
    address: map.get('company.address') || null,
    taxNumber: map.get('company.tax_number') || null,
    email: map.get('company.email') || null,
    website: map.get('company.website') || null,
    footerNote: map.get('company.footer_note') || null,
    currencyCode: map.get('finance.default_currency') || 'EGP',
    currencySymbol: map.get('finance.currency_symbol') || 'ج.م',
  };

  _cachedBranding = branding;
  _lastFetchTime = now;

  return branding;
}

function getFallbackBranding(): CompanyBranding {
  return {
    name: 'النظام المستندي',
    currencyCode: 'EGP',
    currencySymbol: 'ج.م',
  };
}

export function getCachedBrandingSafely(): CompanyBranding | null {
  return _cachedBranding;
}
