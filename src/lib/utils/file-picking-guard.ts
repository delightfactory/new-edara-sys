/**
 * file-picking-guard — v2
 *
 * المشكلة على Android / iOS:
 *   عند إغلاق منتقي الملفات الأصلي (كاميرا/معرض)، يُطلق النظام:
 *   - Android: أحداث pointer وهمية على إحداثيات زر "OK" في الكاميرا
 *   - Android: أحياناً Escape keydown يُغلق المودال
 *   - iOS: touch events متأخرة بعد العودة من الكاميرا
 *
 * سلوك التسلسل الزمني على Android:
 *   1. onChange fires (نختار ملف)  ← الحماية نشطة هنا ✅
 *   2. phantom pointerdown (~0ms)  ← الحماية تحجبه ✅
 *   3. phantom pointerup (~50-400ms) ← يجب أن تظل الحماية نشطة هنا
 *
 * المشكلة كانت: endFilePicking يبدأ العدّ التنازلي من 600ms
 * بمجرد استلام onChange، لكن phantom pointerup قد يصل بعد 400ms
 * مما يُقلّص هامش الأمان.
 *
 * الحل: نرفع المهلة إلى 1200ms لاستيعاب كل الأحداث الوهمية بأمان.
 * هذه المهلة لا تؤثر على UX لأن المستخدم لا يلاحظ 1.2 ثانية بعد رجوعه من الكاميرا.
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
 *
 * 1200ms بدلاً من 600ms:
 * - Android يُطلق phantom events على مدى 50-400ms بعد إغلاق الكاميرا
 * - 1200ms هامش أمان مريح يستوعب أبطأ الأجهزة
 * - لا تأثير على UX: المستخدم لا يلاحظ هذه الفترة
 */
export function endFilePicking(): void {
  if (_clearTimer) { clearTimeout(_clearTimer); _clearTimer = null }
  _clearTimer = setTimeout(() => { _active = false; _clearTimer = null }, 1200)
}

/** true أثناء عمل منتقي الملفات أو خلال فترة الحماية بعد إغلاقه */
export function isFilePicking(): boolean {
  return _active
}
