# خطة إصلاح نظام الأذونات — Permissions Fix Plan
**المشروع:** new-edara-sys  
**تاريخ الخطة:** 2026-04-05  
**المراجع بعد التنفيذ:** Claude (المحادثة الرئيسية)

---

## نظرة عامة على المشاكل المكتشفة

بعد دراسة شاملة للكود تم تحديد **4 مشاكل حقيقية** مرتبة حسب الخطورة:

| # | المشكلة | الخطورة | الملف |
|---|---------|--------|-------|
| P1 | Race condition: `executeWithGPS` يقرأ `geo.error`/`geo.status` stale من closure | 🔴 حرج | `AttendanceCheckin.tsx` + `useGeoPermission.ts` |
| P2 | `maximumAge: Infinity` في `useGeoOnboarding` يسبب طلب إذن بدون تفعيل GPS حقيقي | 🔴 حرج | `useGeoOnboarding.ts` |
| P3 | Safari القديم يعرض Dialog توضيحي حتى لو الإذن ممنوح (لعدم دعم `permissions.query`) | 🟠 تحذير | `useGeoOnboarding.ts` |
| P4 | رسالة "جرّب Chrome أو Edge أو Firefox" مضللة لمستخدمي iOS (لا أحد منهم يدعم Push) | 🟡 ملاحظة | `NotificationPreferences.tsx` |

**ملاحظات مهمة قبل البدء:**
- ✅ Tracking timer cleanup موجود بالفعل (لا حاجة لإصلاحه)
- ✅ PushPermissionDialog موجود ومربوط بالفعل (لا حاجة لإضافته)
- ✅ "Explain before Ask" للـ GPS موجود بالفعل
- ✅ `onchange` listener cleanup موجود بالفعل

---

## Sprint 1 — إصلاح سريع (Quick Wins)
**الهدف:** إصلاح P2 + P4 — تغييرات منخفضة المخاطر وسريعة  
**عدد الملفات:** 2  
**المتوقع:** تعديلات صغيرة جداً

---

### S1-T1: إصلاح `maximumAge: Infinity` في useGeoOnboarding

**الملف:** `src/hooks/useGeoOnboarding.ts`

**المشكلة:**  
السطر 118 يستخدم `maximumAge: Infinity` عند طلب الإذن في `handleAllow`. هذا يعني أن المتصفح قد يُجيب بموقع مخزن من أيام مضت دون تفعيل GPS الفعلي. على بعض الأجهزة هذا يمنح الإذن بدون اختبار GPS حقيقي، فعندما يحاول الموظف تسجيل الحضور لاحقاً يجد `POSITION_UNAVAILABLE`.

**التعديل المطلوب:**  
اقرأ الملف أولاً ثم ابحث عن السطر الذي يحتوي على:
```
{ enableHighAccuracy: false, timeout: 10_000, maximumAge: Infinity }
```
غيّره إلى:
```
{ enableHighAccuracy: false, timeout: 10_000, maximumAge: 60_000 }
```

**لا تغيّر أي شيء آخر في هذا الملف.**

---

### S1-T2: تحسين رسالة Push للمستخدمين على iOS

**الملف:** `src/components/notifications/NotificationPreferences.tsx`

**المشكلة:**  
عند حالة `pushNotif.permission === 'unsupported'` الرسالة الحالية هي:
```
⚠️ متصفحك لا يدعم Push Notifications — جرّب Chrome أو Edge أو Firefox
```
هذا مضلل لمستخدمي iPhone/iPad لأن Chrome وEdge وFirefox على iOS لا تدعم Push أيضاً. الحل الوحيد لهم هو تثبيت التطبيق كـ PWA (Add to Home Screen) على iOS 16.4+.

**التعديل المطلوب:**  
اقرأ الملف. ابحث عن الـ JSX الذي يحتوي على:
```
⚠️ متصفحك لا يدعم Push Notifications — جرّب Chrome أو Edge أو Firefox
```

استبدل نص الرسالة كاملاً (فقط النص، لا تغيّر className أو structure) بما يلي:

للكشف عن iOS استخدم منطقاً بسيطاً داخل الـ JSX:
```tsx
{pushNotif.permission === 'unsupported' && (
  <div className="pref-push-info pref-push-warning">
    {/iphone|ipad|ipod/i.test(navigator.userAgent)
      ? '⚠️ Push Notifications على iPhone/iPad تتطلب تثبيت التطبيق من Safari: اضغط "مشاركة" ← "إضافة للشاشة الرئيسية" ثم افتح التطبيق من أيقونته'
      : '⚠️ متصفحك لا يدعم Push Notifications — جرّب Chrome أو Edge أو Firefox'}
  </div>
)}
```

**لا تغيّر أي شيء آخر في هذا الملف.**

---

## Sprint 2 — إصلاح Race Condition (المشكلة الأساسية)
**الهدف:** إصلاح P1 — إعادة هيكلة `requestLocation` لتُرجع نتيجة مع سبب الفشل  
**عدد الملفات:** 2  
**المتوقع:** تعديل متوسط الحجم — اتبع التعليمات بدقة

**⚠️ تحذير:** هذا Sprint يُغيّر واجهة `requestLocation()`. اتبع الخطوات بالترتيب تماماً.

---

### S2-T1: تعديل `useGeoPermission.ts` — إضافة نوع نتيجة جديد

**الملف:** `src/hooks/useGeoPermission.ts`

**المشكلة:**  
`requestLocation()` حالياً ترجع `Promise<GeoCoords | null>`. عندما ترجع `null` لا نعرف السبب — هل رُفض الإذن؟ هل انتهت المهلة؟ الكود في `AttendanceCheckin.tsx` يحاول قراءة `geo.status` و`geo.error` بعد الـ `await`، لكن هذه قيم React state لن تكون محدثة في نفس cycle.

**التعديلات المطلوبة:**

**الخطوة 1:** في قسم Types في أعلى الملف (بعد `UseGeoPermissionReturn` interface)، أضف النوع الجديد:

```typescript
/** نتيجة طلب الموقع — إما إحداثيات أو خطأ مفصّل */
export type GeoRequestResult =
  | { ok: true;  coords: GeoCoords }
  | { ok: false; reason: 'denied' | 'unavailable' | 'timeout' | 'unknown'; message: string }
```

**الخطوة 2:** في `UseGeoPermissionReturn` interface، غيّر نوع `requestLocation`:
```typescript
// من:
requestLocation: () => Promise<GeoCoords | null>
// إلى:
requestLocation: () => Promise<GeoRequestResult>
```

**الخطوة 3:** في دالة `requestLocation` (داخل `useCallback`)، غيّر جسم الدالة كاملاً:

```typescript
const requestLocation = useCallback(async (): Promise<GeoRequestResult> => {
  if (!navigator.geolocation) {
    setStatus('unavailable')
    setError('جهازك لا يدعم خدمات تحديد الموقع')
    return { ok: false, reason: 'unavailable', message: 'جهازك لا يدعم خدمات تحديد الموقع' }
  }

  setIsLoading(true)
  setError(null)

  return new Promise<GeoRequestResult>((resolve) => {

    const tryGetPosition = (highAccuracy: boolean) => {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          const result: GeoCoords = {
            lat:      position.coords.latitude,
            lng:      position.coords.longitude,
            accuracy: position.coords.accuracy,
          }
          setCoords(result)
          setStatus('granted')
          setError(null)
          setIsLoading(false)
          resolve({ ok: true, coords: result })
        },
        (err) => {
          if (err.code === err.PERMISSION_DENIED) {
            const msg = getBlockedMessage(browserType.current)
            setStatus('denied')
            setError(msg)
            setIsLoading(false)
            resolve({ ok: false, reason: 'denied', message: msg })

          } else if (err.code === err.TIMEOUT && highAccuracy) {
            tryGetPosition(false)

          } else if (err.code === err.POSITION_UNAVAILABLE) {
            const msg = 'تعذّر تحديد الموقع — تأكد من تفعيل GPS في الجهاز ووجودك في مكان مفتوح'
            setError(msg)
            setIsLoading(false)
            resolve({ ok: false, reason: 'unavailable', message: msg })

          } else {
            const msg = err.code === err.TIMEOUT
              ? 'انتهت مهلة تحديد الموقع — تأكد من تفعيل GPS وحاول مرة أخرى'
              : 'حدث خطأ أثناء تحديد الموقع — حاول مرة أخرى'
            setError(msg)
            setIsLoading(false)
            resolve({ ok: false, reason: 'timeout', message: msg })
          }
        },
        {
          enableHighAccuracy: highAccuracy,
          timeout:            highAccuracy ? 15_000 : 10_000,
          maximumAge:         0,
        }
      )
    }

    tryGetPosition(true)
  })
}, [])
```

**الخطوة 4:** في الـ `return` statement في نهاية الـ hook، تأكد أن `requestLocation` لا يزال مُصدَّراً (لا تغيير هنا، فقط تأكد).

---

### S2-T2: تحديث `AttendanceCheckin.tsx` لاستخدام النوع الجديد

**الملف:** `src/pages/hr/attendance/AttendanceCheckin.tsx`

**المشكلة:**  
`executeWithGPS` يقرأ `geo.status` و`geo.error` بعد `await geo.requestLocation()` وهذه قيم stale. الآن بعد تغيير `requestLocation` لترجع `GeoRequestResult` يجب تحديث الكود.

**الخطوة 1:** ابحث عن `executeWithGPS` function (حوالي السطر 377). ابحث عن الكتلة:

```typescript
const geoCoords = await geo.requestLocation()

if (!geoCoords) {
  // فشل GPS — الخطأ محفوظ في geo.error
  if (geo.status === 'denied') {
    setErrorMsg(geo.blockedMessage)
  } else {
    setErrorMsg(geo.error ?? 'فشل تحديد الموقع — حاول مرة أخرى')
  }
  setFlowState('error')
  return
}

setPosition({ latitude: geoCoords.lat, longitude: geoCoords.lng, accuracy: geoCoords.accuracy })
```

استبدلها بـ:

```typescript
const geoResult = await geo.requestLocation()

if (!geoResult.ok) {
  setErrorMsg(geoResult.message)
  setFlowState('error')
  return
}

setPosition({ latitude: geoResult.coords.lat, longitude: geoResult.coords.lng, accuracy: geoResult.coords.accuracy })
```

**الخطوة 2:** ابحث عن `sendTrackingPing` function (حوالي السطر 466). ابحث عن:

```typescript
const geoCoords = await geo.requestLocation()
if (!geoCoords) {
  setTrackingMessage('تعذر إرسال نقطة تتبع الآن')
  return
}

const nextPos: GeoPos = { latitude: geoCoords.lat, longitude: geoCoords.lng, accuracy: geoCoords.accuracy }
```

استبدلها بـ:

```typescript
const geoResult = await geo.requestLocation()
if (!geoResult.ok) {
  setTrackingMessage('تعذر إرسال نقطة تتبع الآن')
  return
}

const nextPos: GeoPos = { latitude: geoResult.coords.lat, longitude: geoResult.coords.lng, accuracy: geoResult.coords.accuracy }
```

**لا تغيّر أي شيء آخر في هذا الملف.**

---

### S2-T3: التحقق من TypeScript

بعد انتهاء S2-T1 و S2-T2، شغّل:
```bash
npx tsc --noEmit --project tsconfig.json 2>&1 | head -50
```

إذا ظهرت أخطاء تخص `requestLocation` أو `GeoCoords` أو `GeoRequestResult` فقط — أصلحها.  
إذا ظهرت أخطاء في ملفات أخرى غير مرتبطة بهذه التغييرات — تجاهلها.

---

## Sprint 3 — إصلاح Safari القديم
**الهدف:** إصلاح P3 — المتصفحات التي لا تدعم `permissions.query`  
**عدد الملفات:** 1

---

### S3-T1: إصلاح fallback لـ Safari القديم في useGeoOnboarding

**الملف:** `src/hooks/useGeoOnboarding.ts`

**المشكلة:**  
في الـ `else` branch (حوالي السطر 78-88) عندما لا يدعم المتصفح `navigator.permissions?.query`، الكود يعرض dialog بعد 2.5 ثانية دون فحص الحالة الفعلية. على Safari القديم هذا يعني عرض Dialog حتى لو الإذن ممنوح مسبقاً.

**التعديل المطلوب:**  
ابحث عن الـ `else` block التي تحتوي على:
```typescript
} else {
  // Safari القديم لا يدعم permissions.query → نؤخر وعرضه
  timerRef.current = setTimeout(() => {
    setShowDialog(true)
  }, 2500)
}
```

استبدلها بـ:

```typescript
} else {
  // Safari القديم لا يدعم permissions.query
  // نكتشف الحالة بطلب صامت جداً (timeout: 100ms) — إذا كان مسموحاً سيُجيب فوراً
  navigator.geolocation.getCurrentPosition(
    () => {
      // ✅ الإذن ممنوح — نسجّل ذلك ولا نزعج المستخدم
      markAsShown()
    },
    (err) => {
      if (err.code === err.PERMISSION_DENIED) {
        // 🚫 محظور — نسجّل ولا نعرض dialog
        markAsShown()
      } else {
        // ❓ TIMEOUT أو POSITION_UNAVAILABLE = لم يُجب بعد → prompt state
        // نعرض dialog بعد تأخير قصير
        timerRef.current = setTimeout(() => {
          setShowDialog(true)
        }, 2500)
      }
    },
    { enableHighAccuracy: false, timeout: 200, maximumAge: Infinity }
  )
}
```

**لا تغيّر أي شيء آخر في هذا الملف.**

---

## Sprint 4 — مزامنة Push Subscription
**الهدف:** ضمان اتساق حالة Push بين المتصفح وـ Supabase  
**عدد الملفات:** 1

---

### S4-T1: إضافة sync-check عند mount في usePushNotifications

**الملف:** `src/hooks/usePushNotifications.ts`

**المشكلة:**  
إذا نجح `requestAndSubscribe` في طلب الإذن وإنشاء الـ subscription في المتصفح، لكن `savePushSubscription` فشل لانقطاع الشبكة، يصبح المتصفح مشتركاً لكن الـ backend لا يعلم → المستخدم لا يتلقى إشعارات.

**التعديل المطلوب:**  
في `useEffect` الحالي (أسطر 52-72)، في داخل الـ block `if (perm === 'granted')`:

ابحث عن:
```typescript
// If already granted, fetch the existing subscription silently
if (perm === 'granted') {
  navigator.serviceWorker.ready
    .then(reg => reg.pushManager.getSubscription())
    .then(existing => setCurrentSubscription(existing))
    .catch(() => {
      // Non-critical — existing subscription may be null
    })
}
```

استبدلها بـ:

```typescript
// If already granted, fetch the existing subscription and sync with backend
if (perm === 'granted') {
  navigator.serviceWorker.ready
    .then(reg => reg.pushManager.getSubscription())
    .then(async (existing) => {
      setCurrentSubscription(existing)
      // Sync-check: إذا كان هناك subscription في المتصفح ولكن قد تكون غير محفوظة
      // نُعيد الحفظ صامتاً لضمان الاتساق (idempotent — لا تُكرر السجل)
      if (existing) {
        try {
          await NotificationsAPI.savePushSubscription(existing, {
            deviceName: buildDeviceName(),
            deviceType: detectDeviceType(),
            browser: detectBrowser(),
            userAgent: navigator.userAgent,
          })
        } catch {
          // Non-critical — will retry on next mount or manual subscribe
        }
      }
    })
    .catch(() => {
      // Non-critical — existing subscription may be null
    })
}
```

**⚠️ مهم:** تأكد أن `NotificationsAPI.savePushSubscription` يدعم `upsert` (لا `insert` فقط). افتح الملف `src/lib/notifications/api.ts` وابحث عن `savePushSubscription`. إذا كانت تستخدم `.insert()` فقط، غيّرها إلى `.upsert()` مع `onConflict: 'endpoint'`. إذا كانت تستخدم `.upsert()` بالفعل، لا تغيّر شيئاً.

---

## التحقق النهائي بعد كل Sprint

بعد انتهاء كل Sprint شغّل:

```bash
npx tsc --noEmit --project tsconfig.json 2>&1 | grep -E "error TS" | head -20
```

لا يجب أن تظهر أخطاء جديدة متعلقة بالملفات التي تم تعديلها.

---

## ملخص الملفات المُعدَّلة

| Sprint | الملف | نوع التغيير |
|--------|-------|------------|
| S1 | `src/hooks/useGeoOnboarding.ts` | سطر واحد: `Infinity` → `60_000` |
| S1 | `src/components/notifications/NotificationPreferences.tsx` | تحسين رسالة iOS |
| S2 | `src/hooks/useGeoPermission.ts` | إضافة type + تغيير return type لـ `requestLocation` |
| S2 | `src/pages/hr/attendance/AttendanceCheckin.tsx` | تحديث موضعين يستخدمان `requestLocation` |
| S3 | `src/hooks/useGeoOnboarding.ts` | إصلاح Safari fallback |
| S4 | `src/hooks/usePushNotifications.ts` | إضافة sync-check في useEffect |
| S4 | `src/lib/notifications/api.ts` | تحقق فقط: upsert أم insert |

---

## ما لا يجب تغييره

- ❌ لا تُعدّل `useGeoOnboarding.ts` خارج التعليمات المحددة
- ❌ لا تُضف error handling إضافي غير مطلوب
- ❌ لا تُغيّر منطق الـ tracking timer (هو صحيح بالفعل)
- ❌ لا تُغيّر `PushPermissionDialog` (موجود ومكتمل)
- ❌ لا تُعيد هيكلة ملفات غير مذكورة
- ❌ لا تُضف comments جديدة إلا عند الضرورة القصوى

---

## بعد الانتهاء

أرسل للمراجع (Claude) ملخصاً يتضمن:
1. قائمة الملفات المُعدَّلة مع رقم السطر لكل تغيير
2. نتيجة `tsc --noEmit` (صفر أخطاء أم ماذا؟)
3. أي ملاحظات غير متوقعة صادفتها أثناء التنفيذ
