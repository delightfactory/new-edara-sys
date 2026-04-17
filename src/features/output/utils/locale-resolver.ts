export const DEFAULT_LOCALE = 'ar-EG';
export const DEFAULT_DIRECTION = 'rtl';

export function resolveEnvironmentLocale(): { locale: string; direction: 'rtl' | 'ltr' } {
  if (typeof navigator !== 'undefined' && navigator.language) {
    const isArabic = navigator.language.startsWith('ar');
    return {
      locale: isArabic ? DEFAULT_LOCALE : 'en-US',
      direction: isArabic ? 'rtl' : 'ltr'
    };
  }
  
  return {
    locale: DEFAULT_LOCALE,
    direction: DEFAULT_DIRECTION
  };
}
