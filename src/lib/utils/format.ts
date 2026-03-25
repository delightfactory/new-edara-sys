/**
 * دوال تنسيق مشتركة — EDARA v2
 * تُستخدم في كل الصفحات لعرض العملة والتواريخ والأرقام بشكل موحد
 */

/**
 * تنسيق العملة المصرية
 * @example formatCurrency(1500) → "١٬٥٠٠٫٠٠"
 */
export function formatCurrency(value: number | null | undefined): string {
  if (value == null) return '—'
  return value.toLocaleString('ar-EG', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}

/**
 * تنسيق رقم بدون كسور عشرية
 * @example formatNumber(1500) → "١٬٥٠٠"
 */
export function formatNumber(value: number | null | undefined): string {
  if (value == null) return '—'
  return value.toLocaleString('ar-EG')
}

/**
 * تنسيق التاريخ (يوم شهر سنة)
 * @example formatDate("2026-03-24") → "٢٤ مارس ٢٠٢٦"
 */
export function formatDate(date: string | null | undefined): string {
  if (!date) return '—'
  try {
    return new Date(date).toLocaleDateString('ar-EG', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    })
  } catch {
    return '—'
  }
}

/**
 * تنسيق التاريخ والوقت
 * @example formatDateTime("2026-03-24T15:30:00") → "٢٤ مارس ٢٠٢٦ ٠٣:٣٠ م"
 */
export function formatDateTime(date: string | null | undefined): string {
  if (!date) return '—'
  try {
    return new Date(date).toLocaleDateString('ar-EG', {
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
 * تنسيق النسبة المئوية
 * @example formatPercent(15) → "١٥٪"
 */
export function formatPercent(value: number | null | undefined): string {
  if (value == null) return '—'
  return `${value.toLocaleString('ar-EG')}٪`
}

/**
 * تنسيق التاريخ بصيغة مختصرة
 * @example formatDateShort("2026-03-24") → "٢٤/٠٣/٢٠٢٦"
 */
export function formatDateShort(date: string | null | undefined): string {
  if (!date) return '—'
  try {
    return new Date(date).toLocaleDateString('ar-EG')
  } catch {
    return '—'
  }
}
