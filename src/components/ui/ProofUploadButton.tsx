/**
 * ProofUploadButton — مكوّن رفع الإثبات الاحترافي
 *
 * يعالج مشكلة phantom click على الجوال التي تتسبب في إغلاق المودال
 * عند استخدام input[type=file] مخفي داخل Bottom Sheet.
 *
 * الحل:
 * 1. استخدام onPointerDown بدلاً من onClick لتجنب الـ phantom click
 * 2. تقديم واجهة اختيار المصدر (كاميرا / معرض / ملف) على الجوال
 * 3. معالجة حالة الاختيار والإلغاء مع إعادة ضبط الـ input
 *
 * الاستخدام:
 * ```tsx
 * <ProofUploadButton
 *   file={proofFile}
 *   onChange={setProofFile}
 *   required
 * />
 * ```
 */

import { useRef, useState, useCallback } from 'react'
import { Upload, Camera, Image, FileText, X, CheckCircle2, AlertCircle } from 'lucide-react'

interface ProofUploadButtonProps {
  /** الملف المُختار حالياً */
  file: File | null
  /** callback عند تغيير الملف */
  onChange: (file: File | null) => void
  /** هل الإثبات إجباري؟ */
  required?: boolean
  /** النص الذي يظهر على الزر */
  label?: string
  /** أنواع الملفات المقبولة */
  accept?: string
  /** أقصى حجم بالميجابايت */
  maxSizeMB?: number
  /** هل المكوّن معطّل؟ */
  disabled?: boolean
}

// كشف جهاز الجوال عبر touch support
const isMobileDevice = () =>
  typeof window !== 'undefined' &&
  ('ontouchstart' in window || navigator.maxTouchPoints > 0)

export default function ProofUploadButton({
  file,
  onChange,
  required = false,
  label = 'اختر إثباتاً',
  accept = 'image/*,.pdf',
  maxSizeMB = 5,
  disabled = false,
}: ProofUploadButtonProps) {
  // المدخلات المنفصلة: معرض / كاميرا / ملف عام
  const galleryRef = useRef<HTMLInputElement>(null)
  const cameraRef  = useRef<HTMLInputElement>(null)
  const fileRef    = useRef<HTMLInputElement>(null)

  // حالة الـ source picker على الجوال
  const [showPicker, setShowPicker] = useState(false)

  // مؤشر انتظار لمنع الضغط المزدوج
  const pickingRef = useRef(false)

  // تنظيف قيمة الـ input بعد الاستخدام (ضروري لإتاحة اختيار نفس الملف مرة أخرى)
  const clearInputs = useCallback(() => {
    ;[galleryRef, cameraRef, fileRef].forEach(ref => {
      if (ref.current) ref.current.value = ''
    })
  }, [])

  // معالجة الملف المُختار
  const handleFile = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0]
    if (!f) { clearInputs(); return }

    // التحقق من الحجم
    if (f.size > maxSizeMB * 1024 * 1024) {
      alert(`حجم الملف يتجاوز ${maxSizeMB}MB — يرجى اختيار ملف أصغر`)
      clearInputs()
      return
    }
    onChange(f)
    clearInputs()
    // إعادة ضبط مؤشر الانتظار
    setTimeout(() => { pickingRef.current = false }, 300)
  }, [maxSizeMB, onChange, clearInputs])

  // ── فتح منتقي الملف (يدعم الجوال والديسكتوب) ──
  const triggerPick = useCallback((e: React.PointerEvent | React.MouseEvent) => {
    // منع انبثاق الحدث حتى لا يصل للـ overlay
    e.stopPropagation()
    if (disabled || pickingRef.current) return
    pickingRef.current = true

    if (isMobileDevice()) {
      // على الجوال: نعرض bottom picker
      setShowPicker(true)
      setTimeout(() => { pickingRef.current = false }, 500)
    } else {
      // على الديسكتوب: نفتح منتقي الملف مباشرة
      fileRef.current?.click()
    }
  }, [disabled])

  // فتح الكاميرا على الجوال
  const triggerCamera = useCallback((e: React.PointerEvent) => {
    e.stopPropagation()
    setShowPicker(false)
    pickingRef.current = true
    setTimeout(() => {
      cameraRef.current?.click()
    }, 50)
  }, [])

  // فتح المعرض على الجوال
  const triggerGallery = useCallback((e: React.PointerEvent) => {
    e.stopPropagation()
    setShowPicker(false)
    pickingRef.current = true
    setTimeout(() => {
      galleryRef.current?.click()
    }, 50)
  }, [])

  // فتح منتقي الملفات العام (PDF...) على الجوال
  const triggerAnyFile = useCallback((e: React.PointerEvent) => {
    e.stopPropagation()
    setShowPicker(false)
    pickingRef.current = true
    setTimeout(() => {
      fileRef.current?.click()
    }, 50)
  }, [])

  // حذف الملف
  const removeFile = useCallback((e: React.PointerEvent | React.MouseEvent) => {
    e.stopPropagation()
    onChange(null)
    clearInputs()
  }, [onChange, clearInputs])

  // ── حالة التصميم ──
  const hasError  = required && !file
  const hasFile   = !!file
  const isImage   = hasFile && file!.type.startsWith('image/')
  const preview   = isImage ? URL.createObjectURL(file!) : null

  const borderColor = hasFile
    ? 'var(--color-success)'
    : hasError
    ? 'var(--color-danger)'
    : 'var(--border-primary)'

  const bgColor = hasFile
    ? 'color-mix(in srgb, var(--color-success) 6%, transparent)'
    : hasError
    ? 'color-mix(in srgb, var(--color-danger) 5%, transparent)'
    : 'var(--bg-surface-2)'

  return (
    <>
      {/* ── hidden inputs ── */}
      {/* معرض الصور */}
      <input
        ref={galleryRef}
        type="file"
        accept="image/*"
        style={{ display: 'none' }}
        onChange={handleFile}
      />
      {/* الكاميرا */}
      <input
        ref={cameraRef}
        type="file"
        accept="image/*"
        capture="environment"
        style={{ display: 'none' }}
        onChange={handleFile}
      />
      {/* ملفات عامة */}
      <input
        ref={fileRef}
        type="file"
        accept={accept}
        style={{ display: 'none' }}
        onChange={handleFile}
      />

      {/* ── واجهة الرفع ── */}
      <div
        style={{
          borderRadius: 10,
          border: `1px solid ${borderColor}`,
          background: bgColor,
          padding: '10px 12px',
          transition: 'border-color 0.2s, background 0.2s',
        }}
      >
        {/* رأس القسم */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
          <span style={{
            fontSize: 12, fontWeight: 700,
            color: hasFile ? 'var(--color-success)' : hasError ? 'var(--color-danger)' : 'var(--text-secondary)',
            display: 'flex', alignItems: 'center', gap: 5,
          }}>
            {hasFile
              ? <CheckCircle2 size={13} />
              : hasError
              ? <AlertCircle size={13} />
              : <Upload size={13} />}
            {label}
            {required && !hasFile && (
              <span style={{ fontWeight: 400, fontSize: 10, color: 'var(--color-danger)' }}>(إجباري)</span>
            )}
          </span>
          {hasFile && (
            <button
              type="button"
              onPointerDown={removeFile}
              style={{
                background: 'none', border: 'none', cursor: 'pointer',
                color: 'var(--text-muted)', padding: 2, borderRadius: 4,
                lineHeight: 1,
              }}
              title="إزالة الملف"
            >
              <X size={14} />
            </button>
          )}
        </div>

        {/* معاينة أو زر الاختيار */}
        {hasFile ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            {preview ? (
              <img
                src={preview}
                alt="معاينة"
                style={{ width: 44, height: 44, objectFit: 'cover', borderRadius: 6, border: '1px solid var(--border-primary)' }}
                onLoad={() => { if (preview) URL.revokeObjectURL(preview) }}
              />
            ) : (
              <div style={{
                width: 44, height: 44, borderRadius: 6, border: '1px solid var(--border-primary)',
                background: 'var(--bg-hover)', display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <FileText size={20} style={{ color: 'var(--color-primary)' }} />
              </div>
            )}
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 11, fontWeight: 600, color: 'var(--color-success)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {file!.name}
              </div>
              <div style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 2 }}>
                {(file!.size / 1024).toFixed(0)} KB
              </div>
            </div>
            {/* زر تغيير الملف */}
            <button
              type="button"
              onPointerDown={triggerPick}
              style={{
                fontSize: 10, fontWeight: 600, color: 'var(--color-primary)',
                background: 'none', border: '1px solid var(--color-primary)',
                borderRadius: 6, padding: '3px 8px', cursor: 'pointer',
                flexShrink: 0,
              }}
            >
              تغيير
            </button>
          </div>
        ) : (
          <button
            type="button"
            onPointerDown={triggerPick}
            disabled={disabled}
            style={{
              display: 'flex', alignItems: 'center', gap: 6,
              fontSize: 12, fontWeight: 600,
              color: hasError ? 'var(--color-danger)' : 'var(--color-primary)',
              background: 'none', border: 'none', cursor: disabled ? 'not-allowed' : 'pointer',
              padding: 0, opacity: disabled ? 0.5 : 1,
            }}
          >
            <Upload size={14} />
            {isMobileDevice() ? 'صوّر أو اختر من المعرض' : 'اختر صورة أو PDF'}
          </button>
        )}

        <div style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 5 }}>
          صور (JPG/PNG) أو PDF — بحد أقصى {maxSizeMB}MB
        </div>
      </div>

      {/* ── Mobile Source Picker (Bottom Sheet بداخل المودال) ── */}
      {showPicker && (
        <>
          {/* Backdrop — يمنع إغلاق المودال الرئيسي */}
          <div
            style={{
              position: 'fixed', inset: 0,
              background: 'rgba(0,0,0,0.5)',
              zIndex: 9000,
            }}
            onPointerDown={e => { e.stopPropagation(); setShowPicker(false) }}
          />
          {/* Sheet */}
          <div
            style={{
              position: 'fixed',
              bottom: 0, left: 0, right: 0,
              background: 'var(--bg-surface)',
              borderRadius: '20px 20px 0 0',
              padding: '16px 0 calc(16px + env(safe-area-inset-bottom, 0px))',
              zIndex: 9001,
              boxShadow: '0 -4px 30px rgba(0,0,0,0.2)',
            }}
            onPointerDown={e => e.stopPropagation()}
          >
            {/* Drag handle */}
            <div style={{
              width: 36, height: 4,
              background: 'var(--neutral-300, #cbd5e1)',
              borderRadius: 99,
              margin: '0 auto 16px',
            }} />

            <div style={{
              fontSize: 13, fontWeight: 700,
              color: 'var(--text-primary)',
              padding: '0 20px 12px',
              borderBottom: '1px solid var(--border-primary)',
              marginBottom: 4,
            }}>
              رفع إثبات الدفع
            </div>

            {/* خيار الكاميرا */}
            <button
              type="button"
              onPointerDown={triggerCamera}
              style={pickerBtnStyle}
            >
              <span style={pickerIconStyle('#2563eb')}>
                <Camera size={22} />
              </span>
              <div>
                <div style={{ fontSize: 14, fontWeight: 600 }}>التقاط صورة</div>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>فتح الكاميرا</div>
              </div>
            </button>

            {/* خيار المعرض */}
            <button
              type="button"
              onPointerDown={triggerGallery}
              style={pickerBtnStyle}
            >
              <span style={pickerIconStyle('#16a34a')}>
                <Image size={22} />
              </span>
              <div>
                <div style={{ fontSize: 14, fontWeight: 600 }}>اختيار من المعرض</div>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>صور الجهاز</div>
              </div>
            </button>

            {/* خيار ملف PDF */}
            <button
              type="button"
              onPointerDown={triggerAnyFile}
              style={pickerBtnStyle}
            >
              <span style={pickerIconStyle('#d97706')}>
                <FileText size={22} />
              </span>
              <div>
                <div style={{ fontSize: 14, fontWeight: 600 }}>ملف PDF</div>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>مستند أو فاتورة</div>
              </div>
            </button>

            {/* إلغاء */}
            <button
              type="button"
              onPointerDown={e => { e.stopPropagation(); setShowPicker(false) }}
              style={{
                width: 'calc(100% - 32px)',
                margin: '8px 16px 0',
                padding: '12px',
                borderRadius: 12,
                border: '1px solid var(--border-primary)',
                background: 'var(--bg-hover)',
                fontSize: 14, fontWeight: 600,
                color: 'var(--text-secondary)',
                cursor: 'pointer',
                textAlign: 'center' as const,
              }}
            >
              إلغاء
            </button>
          </div>
        </>
      )}
    </>
  )
}

// ── Styles ─────────────────────────────────────────────────────
const pickerBtnStyle: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 14,
  width: '100%',
  background: 'none',
  border: 'none',
  padding: '12px 20px',
  cursor: 'pointer',
  textAlign: 'start',
  transition: 'background 0.1s',
  color: 'var(--text-primary)',
}

const pickerIconStyle = (color: string): React.CSSProperties => ({
  width: 44,
  height: 44,
  borderRadius: 12,
  background: `color-mix(in srgb, ${color} 12%, transparent)`,
  color,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  flexShrink: 0,
})
