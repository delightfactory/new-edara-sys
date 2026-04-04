/**
 * file-picking-guard
 *
 * مشكلة: على Android/iOS، عند إغلاق منتقي الملفات الأصلي (كاميرا/معرض)،
 * يُولّد النظام أحداثاً وهمية تُغلق المودال الرئيسي:
 *   - Android: زر Back يُطلق Escape keydown في المتصفح
 *   - iOS: touch events وهمية عند العودة من الكاميرا
 *
 * الحل: نُشغّل هذه الحماية قبل فتح أي file input برمجياً،
 * ونوقفها بعد اكتمال الاختيار (أو بعد 600ms للاستيعاب الكامل للأحداث الوهمية).
 */

let _active = false
let _clearTimer: ReturnType<typeof setTimeout> | null = null

/** شغّل الحماية قبل استدعاء input.click() */
export function startFilePicking(): void {
  _active = true
  if (_clearTimer) clearTimeout(_clearTimer)
  // أمان: إلغاء تلقائي بعد 30 ثانية لو لم يُستدعَ endFilePicking
  _clearTimer = setTimeout(() => { _active = false; _clearTimer = null }, 30_000)
}

/**
 * أوقف الحماية بعد اكتمال الاختيار أو الإلغاء.
 * تبقى فعّالة 600ms إضافية لاستيعاب الأحداث الوهمية.
 */
export function endFilePicking(): void {
  if (_clearTimer) { clearTimeout(_clearTimer); _clearTimer = null }
  _clearTimer = setTimeout(() => { _active = false; _clearTimer = null }, 600)
}

/** true أثناء عمل منتقي الملفات أو خلال فترة الحماية بعد إغلاقه */
export function isFilePicking(): boolean {
  return _active
}
