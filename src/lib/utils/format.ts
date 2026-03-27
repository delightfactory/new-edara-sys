/**
 * دوال تنسيق مشتركة — EDARA v2
 * تُستخدم في كل الصفحات لعرض العملة والتواريخ والأرقام بشكل موحد
 *
 * الأرقام: دائماً بالأرقام الإنجليزية (Western Arabic / Latin digits)
 * النصوص/التواريخ: باللغة العربية
 *
 * نستخدم locale مركّب 'ar-EG-u-nu-latn' لضمان:
 *   - فاصل الآلاف المناسب (,)
 *   - الفاصل العشري المناسب (.)
 *   - أرقام لاتينية 0-9 دائماً
 */

const NUM_LOCALE = 'ar-EG-u-nu-latn'  // Arabic locale + Latin (Western) numerals

/**
 * تنسيق العملة المصرية — أرقام إنجليزية
 * @example formatCurrency(1500) → "1,500.00"
 */
export function formatCurrency(value: number | null | undefined): string {
  if (value == null) return '—'
  return value.toLocaleString(NUM_LOCALE, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}

/**
 * تنسيق رقم بدون كسور عشرية — أرقام إنجليزية
 * @example formatNumber(1500) → "1,500"
 */
export function formatNumber(value: number | null | undefined): string {
  if (value == null) return '—'
  return value.toLocaleString(NUM_LOCALE)
}

/**
 * تنسيق التاريخ (يوم شهر سنة) — أرقام إنجليزية
 * @example formatDate("2026-03-24") → "24 مارس 2026"
 */
export function formatDate(date: string | null | undefined): string {
  if (!date) return '—'
  try {
    return new Date(date).toLocaleDateString(NUM_LOCALE, {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    })
  } catch {
    return '—'
  }
}

/**
 * تنسيق التاريخ والوقت — أرقام إنجليزية
 * @example formatDateTime("2026-03-24T15:30:00") → "24 مارس 2026، 03:30 م"
 */
export function formatDateTime(date: string | null | undefined): string {
  if (!date) return '—'
  try {
    return new Date(date).toLocaleDateString(NUM_LOCALE, {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    })
  } catch {
    return '—'
  }
}

/**
 * تنسيق النسبة المئوية — أرقام إنجليزية
 * @example formatPercent(15) → "15%"
 */
export function formatPercent(value: number | null | undefined): string {
  if (value == null) return '—'
  return `${value.toLocaleString(NUM_LOCALE, { maximumFractionDigits: 2 })}%`
}

/**
 * تنسيق التاريخ بصيغة مختصرة — أرقام إنجليزية
 * @example formatDateShort("2026-03-24") → "24/03/2026"
 */
export function formatDateShort(date: string | null | undefined): string {
  if (!date) return '—'
  try {
    return new Date(date).toLocaleDateString(NUM_LOCALE)
  } catch {
    return '—'
  }
}
