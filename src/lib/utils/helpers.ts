/**
 * دوال مساعدة عامة — EDARA v2
 */

/**
 * دمج أسماء CSS classes مع تجاهل القيم الفارغة
 * @example cn('btn', isActive && 'btn-primary', undefined) → "btn btn-primary"
 */
export function cn(...classes: (string | false | undefined | null)[]): string {
  return classes.filter(Boolean).join(' ')
}

/**
 * تأخير تنفيذ الدالة (للبحث مثلاً)
 * @example const debouncedSearch = debounce(search, 300)
 */
export function debounce<T extends (...args: any[]) => void>(
  fn: T,
  ms: number
): T & { cancel: () => void } {
  let timer: ReturnType<typeof setTimeout> | null = null

  const debounced = (...args: any[]) => {
    if (timer) clearTimeout(timer)
    timer = setTimeout(() => fn(...args), ms)
  }

  debounced.cancel = () => {
    if (timer) clearTimeout(timer)
    timer = null
  }

  return debounced as T & { cancel: () => void }
}

/**
 * اقتطاع نص طويل
 * @example truncate("نص طويل جداً", 10) → "نص طويل..."
 */
export function truncate(text: string | null | undefined, maxLength: number): string {
  if (!text) return ''
  if (text.length <= maxLength) return text
  return text.slice(0, maxLength) + '...'
}

/**
 * توليد ID مؤقت فريد (للعناصر الجديدة قبل الحفظ)
 */
export function tempId(): string {
  return `temp_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`
}

/**
 * التحقق من أن القيمة ليست فارغة (null, undefined, '')
 */
export function isNotEmpty(value: unknown): boolean {
  if (value == null) return false
  if (typeof value === 'string') return value.trim().length > 0
  return true
}
