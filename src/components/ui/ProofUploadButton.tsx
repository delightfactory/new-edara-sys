/**
 * ProofUploadButton — مكوّن رفع الإثبات
 *
 * النهج المعتمد (مطابق للنمط العامل في home-care):
 * ─────────────────────────────────────────────
 * - أزرار inline دائمة في DOM
 * - e.stopPropagation() على الأزرار لمنع الفقاعة للـ overlay
 * - لا file-picking-guard / لا startFilePicking / لا endFilePicking
 * - المودال يُغلق بالضغط على الـ backdrop — والضغط على المحتوى يُوقف الفقاعة
 */

import { useRef, useCallback } from 'react'
import { Camera, Image, FileText, X, CheckCircle2, AlertCircle, Upload } from 'lucide-react'

interface ProofUploadButtonProps {
  file: File | null
  onChange: (file: File | null) => void
  required?: boolean
  label?: string
  accept?: string
  maxSizeMB?: number
  disabled?: boolean
}

const isMobile = () =>
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
  const galleryRef = useRef<HTMLInputElement>(null)
  const cameraRef  = useRef<HTMLInputElement>(null)
  const fileRef    = useRef<HTMLInputElement>(null)

  // تنظيف قيمة الـ input بعد الاستخدام
  const clearInputs = useCallback(() => {
    ;[galleryRef, cameraRef, fileRef].forEach(r => {
      if (r.current) r.current.value = ''
    })
  }, [])

  // معالجة الملف المُختار — مطابق لـ handleFileChange في home-care
  const handleFile = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0]
    if (f) {
      if (f.size > maxSizeMB * 1024 * 1024) {
        alert(`حجم الملف يتجاوز ${maxSizeMB}MB — يرجى اختيار ملف أصغر`)
        clearInputs()
        return
      }
      onChange(f)
    }
    clearInputs()
  }, [maxSizeMB, onChange, clearInputs])

  // فتح الكاميرا — stopPropagation يمنع الفقاعة للـ backdrop
  const openCamera = useCallback((e: React.MouseEvent) => {
    e.stopPropagation()
    if (disabled) return
    cameraRef.current?.click()
  }, [disabled])

  // فتح المعرض
  const openGallery = useCallback((e: React.MouseEvent) => {
    e.stopPropagation()
    if (disabled) return
    galleryRef.current?.click()
  }, [disabled])

  // فتح منتقي الملفات (PDF + الديسكتوب)
  const openFile = useCallback((e: React.MouseEvent) => {
    e.stopPropagation()
    if (disabled) return
    fileRef.current?.click()
  }, [disabled])

  // حذف الملف
  const removeFile = useCallback((e: React.MouseEvent) => {
    e.stopPropagation()
    onChange(null)
    clearInputs()
  }, [onChange, clearInputs])

  // ── التصميم ──
  const hasFile  = !!file
  const hasError = required && !file
  const isImage  = hasFile && file!.type.startsWith('image/')
  const preview  = isImage ? URL.createObjectURL(file!) : null
  const showPdf  = accept.includes('pdf')

  const borderColor = hasFile  ? 'var(--color-success)'
    : hasError ? 'var(--color-danger)'
    : 'var(--border-primary)'
  const bgColor = hasFile  ? 'color-mix(in srgb, var(--color-success) 6%, transparent)'
    : hasError ? 'color-mix(in srgb, var(--color-danger) 5%, transparent)'
    : 'var(--bg-surface-2)'

  return (
    <>
      {/* ── hidden inputs — دائماً في DOM ── */}
      <input ref={galleryRef} type="file" accept="image/*"         style={{ display: 'none' }} onChange={handleFile} />
      <input ref={cameraRef}  type="file" accept="image/*" capture="environment" style={{ display: 'none' }} onChange={handleFile} />
      <input ref={fileRef}    type="file" accept={accept}          style={{ display: 'none' }} onChange={handleFile} />

      {/* ── واجهة الرفع ── */}
      <div style={{
        borderRadius: 10,
        border: `1px solid ${borderColor}`,
        background: bgColor,
        padding: '10px 12px',
        transition: 'border-color 0.2s, background 0.2s',
      }}>
        {/* رأس القسم */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
          <span style={{
            fontSize: 12, fontWeight: 700,
            color: hasFile ? 'var(--color-success)' : hasError ? 'var(--color-danger)' : 'var(--text-secondary)',
            display: 'flex', alignItems: 'center', gap: 5,
          }}>
            {hasFile ? <CheckCircle2 size={13} /> : hasError ? <AlertCircle size={13} /> : <Upload size={13} />}
            {label}
            {required && !hasFile && (
              <span style={{ fontWeight: 400, fontSize: 10, color: 'var(--color-danger)' }}>(إجباري)</span>
            )}
          </span>
          {hasFile && (
            <button type="button" onClick={removeFile}
              style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', padding: 2, borderRadius: 4, lineHeight: 1 }}
              title="إزالة الملف"
            >
              <X size={14} />
            </button>
          )}
        </div>

        {/* معاينة الملف المُختار */}
        {hasFile ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
            {preview ? (
              <img src={preview} alt="معاينة"
                style={{ width: 44, height: 44, objectFit: 'cover', borderRadius: 6, border: '1px solid var(--border-primary)', flexShrink: 0 }}
                onLoad={() => { if (preview) URL.revokeObjectURL(preview) }}
              />
            ) : (
              <div style={{ width: 44, height: 44, borderRadius: 6, border: '1px solid var(--border-primary)', background: 'var(--bg-hover)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
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
          </div>
        ) : null}

        {/* ── أزرار الاختيار — دائماً ظاهرة في DOM ── */}
        {isMobile() ? (
          /* جوال: أزرار كاميرا + معرض inline */
          <div style={{ display: 'flex', gap: 6 }}>
            <button type="button" onClick={openCamera} disabled={disabled} style={mobileBtn('#2563eb')}>
              <Camera size={16} />
              <span>كاميرا</span>
            </button>
            <button type="button" onClick={openGallery} disabled={disabled} style={mobileBtn('#7c3aed')}>
              <Image size={16} />
              <span>معرض</span>
            </button>
            {showPdf && (
              <button type="button" onClick={openFile} disabled={disabled} style={mobileBtn('#d97706')}>
                <FileText size={16} />
                <span>PDF</span>
              </button>
            )}
          </div>
        ) : (
          /* ديسكتوب: زر واحد */
          <button type="button" onClick={openFile} disabled={disabled}
            style={{
              display: 'flex', alignItems: 'center', gap: 6,
              fontSize: 12, fontWeight: 600,
              color: hasError ? 'var(--color-danger)' : 'var(--color-primary)',
              background: 'none', border: 'none',
              cursor: disabled ? 'not-allowed' : 'pointer',
              padding: 0, opacity: disabled ? 0.5 : 1,
            }}
          >
            <Upload size={14} />
            {hasFile ? 'تغيير الملف' : 'اختر صورة أو PDF'}
          </button>
        )}

        <div style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 6 }}>
          صور (JPG/PNG) أو PDF — بحد أقصى {maxSizeMB}MB
        </div>
      </div>
    </>
  )
}

// ── Styles ──────────────────────────────────────────────────────
const mobileBtn = (color: string): React.CSSProperties => ({
  display: 'flex',
  alignItems: 'center',
  gap: 5,
  flex: 1,
  justifyContent: 'center',
  padding: '8px 4px',
  borderRadius: 8,
  border: `1.5px solid color-mix(in srgb, ${color} 35%, transparent)`,
  background: `color-mix(in srgb, ${color} 8%, transparent)`,
  color,
  fontSize: 11,
  fontWeight: 600,
  cursor: 'pointer',
})
