/**
 * file-picking-guard — v3
 *
 * يحل مشكلتين:
 * 1. Phantom click من الكاميرا يُغلق المودال
 * 2. المودال مجمّد 30 ثانية عند إلغاء الكاميرا (endFilePicking لا يُستدعى)
 *
 * الحل:
 * - نستمع لـ visibilitychange: حين تعود الصفحة للواجهة بعد الكاميرا،
 *   نبدأ فوراً مؤقت الـ 800ms (سواء اختار المستخدم صورة أم لا).
 * - 800ms كافية لاستيعاب phantom events التي تصل خلال 0-400ms.
 * - isFilePicking() يبقى true فقط 800ms بعد إغلاق الكاميرا.
 */

let _active = false
let _clearTimer: ReturnType<typeof setTimeout> | null = null

function clearTimerIfAny(): void {
  if (_clearTimer) { clearTimeout(_clearTimer); _clearTimer = null }
}

// عند عودة الصفحة للواجهة (كاميرا تُغلق — سواء اختار أم لا)
// نبدأ مؤقت الإنهاء فوراً
function handlePageVisible(): void {
  if (document.visibilityState === 'visible' && _active) {
    endFilePicking()
  }
}

/** شغّل الحماية قبل استدعاء input.click() */
export function startFilePicking(): void {
  _active = true
  clearTimerIfAny()
  // أمان: إلغاء تلقائي بعد 30 ثانية في حالة عدم استدعاء endFilePicking وعدم تغيير الـ visibility
  _clearTimer = setTimeout(() => { _active = false; _clearTimer = null }, 30_000)
  // الحل الرئيسي: حين تعود الصفحة للواجهة نبدأ الإنهاء فوراً
  document.addEventListener('visibilitychange', handlePageVisible)
}

/**
 * أوقف الحماية بعد اكتمال الاختيار.
 * 800ms لاستيعاب phantom events (تصل خلال 0-400ms على Android).
 * يُستدعى تلقائياً من handlePageVisible عند الإلغاء.
 */
export function endFilePicking(): void {
  document.removeEventListener('visibilitychange', handlePageVisible)
  clearTimerIfAny()
  _clearTimer = setTimeout(() => { _active = false; _clearTimer = null }, 800)
}

/** true أثناء عمل منتقي الملفات أو خلال فترة الحماية (800ms) بعد إغلاقه */
export function isFilePicking(): boolean {
  return _active
}
