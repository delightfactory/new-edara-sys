import { useState, useMemo, useCallback, useEffect, useRef } from 'react'
import type { ChecklistQuestion, ChecklistResponseInput } from '@/lib/types/activities'
import { Star, Camera, HelpCircle } from 'lucide-react'
import { toast } from 'sonner'
import { compressImage } from '@/lib/utils/imageCompressor'
import { buildChecklistAnswersByCode, evaluateChecklistVisibility } from '@/lib/utils/checklistVisibility'

interface ChecklistFormProps {
  /** أسئلة الاستبيان */
  questions: ChecklistQuestion[]
  /** معرف النشاط */
  activityId: string
  /** معرف القالب */
  templateId: string
  /** عند اكتمال الإجابات (كل الإجبارية مُجابة) */
  onComplete?: (responses: ChecklistResponseInput[]) => void
  /** عند تغيير أي إجابة */
  onChange?: (responses: ChecklistResponseInput[], isComplete: boolean) => void
  /** إجابات سابقة (للتعديل) */
  initialValues?: Record<string, unknown>
  /** Answers from the other templates, keyed by question_code, for cross-template conditions. */
  contextValues?: Record<string, unknown>
  /** وضع القراءة فقط */
  readOnly?: boolean
  /** وضع الصور */
  photoMode?: 'local-blob'
  /** عند التقاط وحفظ صورة محلياً */
  onPhotoCapture?: (
    questionId: string,
    blob: Blob,
    meta: { mimeType: string; extension: string; size: number; checksum: string }
  ) => Promise<{ local_blob_id: string }>
  /** دالة تحميل الصورة للمعاينة */
  loadLocalPhoto?: (localBlobId: string) => Promise<Blob | null>
}

interface LocalImagePreviewProps {
  localBlobId: string
  loadLocalPhoto?: (localBlobId: string) => Promise<Blob | null>
}

const EMPTY_CONTEXT_VALUES: Record<string, unknown> = {}

export function LocalImagePreview({ localBlobId, loadLocalPhoto }: LocalImagePreviewProps) {
  const [objectUrl, setObjectUrl] = useState<string | null>(null)
  const [error, setError] = useState<boolean>(false)

  useEffect(() => {
    let active = true
    let url: string | null = null

    async function load() {
      if (!loadLocalPhoto) {
        setError(true)
        return
      }
      try {
        const blob = await loadLocalPhoto(localBlobId)
        if (blob && active) {
          url = URL.createObjectURL(blob)
          setObjectUrl(url)
        } else if (active) {
          setError(true)
        }
      } catch (err) {
        if (active) setError(true)
      }
    }

    load()

    return () => {
      active = false
      if (url) {
        URL.revokeObjectURL(url)
      }
    }
  }, [localBlobId, loadLocalPhoto])

  if (error) {
    return <div className="chk-photo-error">فشل تحميل المعاينة</div>
  }

  if (!objectUrl) {
    return <div className="chk-photo-loading">جاري التحميل...</div>
  }

  return <img src={objectUrl} alt="صورة ملتقطة" className="chk-photo-preview" />
}

export default function ChecklistForm({
  questions,
  activityId,
  templateId,
  onComplete,
  onChange,
  initialValues = {},
  contextValues = EMPTY_CONTEXT_VALUES,
  readOnly = false,
  photoMode = 'local-blob',
  onPhotoCapture,
  loadLocalPhoto
}: ChecklistFormProps) {
  const [answers, setAnswers] = useState<Record<string, unknown>>(() => {
    const init: Record<string, unknown> = {}
    const vals = initialValues || {}
    for (const q of questions) {
      init[q.id] = vals[q.id] ?? (q.default_value ?? '')
    }
    return init
  })

  useEffect(() => {
    const vals = initialValues || {}
    setAnswers(prev => {
      let changed = false
      const updated = { ...prev }
      for (const q of questions) {
        if (vals[q.id] !== undefined && prev[q.id] !== vals[q.id]) {
          updated[q.id] = vals[q.id]
          changed = true
        }
      }
      return changed ? updated : prev
    })
  }, [initialValues, questions])

  const [processingQuestions, setProcessingQuestions] = useState<Record<string, boolean>>({})

  const answersByCode = useMemo(
    () => buildChecklistAnswersByCode(questions, answers, contextValues),
    [questions, answers, contextValues]
  )

  const visibleQuestions = useMemo(
    () => questions.filter(q => evaluateChecklistVisibility(q.visibility_rule, answersByCode)),
    [questions, answersByCode]
  )

  // حساب الاكتمال — only questions that are both visible and required can block completion.
  const requiredQuestions = useMemo(
    () => visibleQuestions.filter(q => q.is_required),
    [visibleQuestions]
  )

  const isComplete = useMemo(() => {
    return requiredQuestions.every(q => {
      const val = answers[q.id]
      if (val === undefined || val === null || val === '') return false
      if (Array.isArray(val) && val.length === 0) return false
      return true
    })
  }, [requiredQuestions, answers])

  const answeredCount = useMemo(() => {
    return visibleQuestions.filter(q => {
      const val = answers[q.id]
      return val !== undefined && val !== null && val !== '' && !(Array.isArray(val) && val.length === 0)
    }).length
  }, [visibleQuestions, answers])

  const requiredAnsweredCount = useMemo(() => requiredQuestions.filter(q => {
    const val = answers[q.id]
    return val !== undefined && val !== null && val !== '' && !(Array.isArray(val) && val.length === 0)
  }).length, [requiredQuestions, answers])

  // التحقق من صحة إعداد الـ photoMode والـ handler لمرة واحدة في وضع التحرير فقط
  const hasPhotoQuestion = questions.some(q => q.question_type === 'photo')
  const isPhotoSetupInvalid = hasPhotoQuestion && !readOnly && photoMode === 'local-blob' && !onPhotoCapture
  const loggedRef = useRef(false)

  useEffect(() => {
    if (isPhotoSetupInvalid && !loggedRef.current) {
      console.error('onPhotoCapture handler is required when photoMode is local-blob')
      loggedRef.current = true
    }
  }, [isPhotoSetupInvalid])

  // بناء الردود
  const getTypedResponses = useCallback((): ChecklistResponseInput[] => {
    const list: ChecklistResponseInput[] = []
    for (const q of visibleQuestions) {
      const val = answers[q.id]
      if (val !== undefined && val !== null && val !== '') {
        if (typeof val === 'string') {
          list.push({
            activity_id: activityId,
            template_id: templateId,
            question_id: q.id,
            answer_value: val,
            answer_json: null
          })
        } else {
          list.push({
            activity_id: activityId,
            template_id: templateId,
            question_id: q.id,
            answer_value: null,
            answer_json: val as Record<string, unknown> | string[]
          })
        }
      }
    }
    return list
  }, [visibleQuestions, activityId, templateId, answers])

  const buildResponses = useCallback((): ChecklistResponseInput[] => {
    return getTypedResponses()
  }, [getTypedResponses])

  const handleChange = useCallback((questionId: string, value: unknown) => {
    setAnswers(prev => {
      if (prev[questionId] === value) return prev
      return { ...prev, [questionId]: value }
    })
  }, [])

  const onChangeRef = useRef(onChange)
  useEffect(() => {
    onChangeRef.current = onChange
  }, [onChange])

  // إبلاغ الـ parent بالتغيير
  useEffect(() => {
    if (!onChangeRef.current) return
    const responses = getTypedResponses()

    const allRequired = requiredQuestions.every(q => {
      const val = answers[q.id]
      return val !== undefined && val !== null && val !== '' && !(Array.isArray(val) && val.length === 0)
    })

    onChangeRef.current(responses, allRequired)
  }, [answers, getTypedResponses, requiredQuestions])

  // معالجة التقاط صورة
  const handlePhotoCaptureClick = async (questionId: string) => {
    if (processingQuestions[questionId]) return
    if (!onPhotoCapture) return

    const input = document.createElement('input')
    input.type = 'file'
    input.accept = 'image/jpeg,image/png'
    input.capture = 'environment'

    input.onchange = async (e: Event) => {
      const target = e.target as HTMLInputElement
      const file = target.files?.[0]
      if (!file) return

      setProcessingQuestions(prev => ({ ...prev, [questionId]: true }))
      try {
        const result = await compressImage(file)
        const captureRes = await onPhotoCapture(questionId, result.blob, {
          mimeType: result.mimeType,
          extension: result.extension,
          size: result.sizeBytes,
          checksum: result.checksum
        })
        handleChange(questionId, { local_blob_id: captureRes.local_blob_id })
      } catch (err: unknown) {
        const errMsg = err instanceof Error ? err.message : 'فشل معالجة وحفظ الصورة'
        console.error('Photo capture error:', err)
        toast.error(errMsg)
      } finally {
        setProcessingQuestions(prev => ({ ...prev, [questionId]: false }))
      }
    }

    input.click()
  }

  // دالة المساعدة لرسم المدخلات
  const renderInput = (q: ChecklistQuestion, value: unknown) => {
    switch (q.question_type) {
      case 'text':
        return (
          <textarea
            className="chk-textarea"
            value={(value as string) ?? ''}
            onChange={e => handleChange(q.id, e.target.value)}
            placeholder="اكتب إجابتك..."
            rows={2}
            readOnly={readOnly}
          />
        )

      case 'number':
        return (
          <input
            className="chk-input"
            type="number"
            value={(value as string) ?? ''}
            onChange={e => handleChange(q.id, e.target.value)}
            placeholder={q.hint_text || 'أدخل رقماً'}
            min={q.min_value ?? undefined}
            max={q.max_value ?? undefined}
            readOnly={readOnly}
          />
        )

      case 'date':
        return (
          <input
            className="chk-input"
            type="date"
            value={(value as string) ?? ''}
            onChange={e => handleChange(q.id, e.target.value)}
            readOnly={readOnly}
          />
        )

      case 'yes_no':
        return (
          <div className="chk-toggle-group">
            <button
              type="button"
              className={`chk-toggle ${value === 'yes' ? 'chk-toggle--active chk-toggle--yes' : ''}`}
              onClick={() => !readOnly && handleChange(q.id, value === 'yes' ? '' : 'yes')}
            >
              نعم ✓
            </button>
            <button
              type="button"
              className={`chk-toggle ${value === 'no' ? 'chk-toggle--active chk-toggle--no' : ''}`}
              onClick={() => !readOnly && handleChange(q.id, value === 'no' ? '' : 'no')}
            >
              لا ✗
            </button>
          </div>
        )

      case 'single_choice': {
        const options = parseOptions(q.options)
        return (
          <div className="chk-choices">
            {options.map(opt => (
              <button
                key={opt}
                type="button"
                className={`chk-choice ${value === opt ? 'chk-choice--selected' : ''}`}
                onClick={() => !readOnly && handleChange(q.id, value === opt ? '' : opt)}
              >
                {value === opt && '● '}{opt}
              </button>
            ))}
          </div>
        )
      }

      case 'multi_choice': {
        const options = parseOptions(q.options)
        const selected = Array.isArray(value) ? (value as string[]) : []
        return (
          <div className="chk-choices">
            {options.map(opt => (
              <button
                key={opt}
                type="button"
                className={`chk-choice ${selected.includes(opt) ? 'chk-choice--selected' : ''}`}
                onClick={() => {
                  if (readOnly) return
                  const next = selected.includes(opt)
                    ? selected.filter((s: string) => s !== opt)
                    : [...selected, opt]
                  handleChange(q.id, next)
                }}
              >
                {selected.includes(opt) ? '☑ ' : '☐ '}{opt}
              </button>
            ))}
          </div>
        )
      }

      case 'rating': {
        const rating = parseInt(String(value)) || 0
        return (
          <div className="chk-rating">
            {[1, 2, 3, 4, 5].map(star => (
              <button
                key={star}
                type="button"
                className={`chk-star ${star <= rating ? 'chk-star--filled' : ''}`}
                onClick={() => !readOnly && handleChange(q.id, star === rating ? '' : String(star))}
              >
                <Star size={24} fill={star <= rating ? 'currentColor' : 'none'} />
              </button>
            ))}
            {rating > 0 && <span className="chk-rating-text">{rating}/5</span>}
          </div>
        )
      }

      case 'photo': {
        const isBlobObj = (val: unknown): val is { local_blob_id: string } => {
          return !!val && typeof val === 'object' && 'local_blob_id' in val && typeof (val as Record<string, unknown>).local_blob_id === 'string'
        }
        const hasBlob = isBlobObj(value)
        const isProcessing = !!processingQuestions[q.id]

        if (isPhotoSetupInvalid) {
          return (
            <div className="chk-photo">
              <button type="button" className="chk-photo-btn chk-photo-btn--disabled" disabled>
                <Camera size={20} />
                التقاط الصور معطل حالياً بسبب خطأ في الإعداد
              </button>
            </div>
          )
        }

        return (
          <div className="chk-photo">
            <button
              type="button"
              className={`chk-photo-btn ${isProcessing ? 'chk-photo-btn--processing' : ''}`}
              onClick={() => !readOnly && handlePhotoCaptureClick(q.id)}
              disabled={readOnly || isProcessing}
              aria-busy={isProcessing}
            >
              <Camera size={20} />
              {isProcessing ? 'جاري معالجة وحفظ الصورة...' : hasBlob ? 'تغيير الصورة' : 'التقاط صورة'}
            </button>
            {hasBlob && (
              <LocalImagePreview
                key={value.local_blob_id}
                localBlobId={value.local_blob_id}
                loadLocalPhoto={loadLocalPhoto}
              />
            )}
          </div>
        )
      }

      default:
        return null
    }
  }

  return (
    <div className="chk-form">
      {/* شريط التقدم */}
      <div className="chk-progress">
        <div className="chk-progress-bar">
          <div
            className="chk-progress-fill"
            style={{ width: `${visibleQuestions.length > 0 ? (answeredCount / visibleQuestions.length) * 100 : 100}%` }}
          />
        </div>
        <span className="chk-progress-text">
          {answeredCount}/{visibleQuestions.length} سؤال ظاهر
        </span>
      </div>

      {/* الأسئلة */}
      {visibleQuestions.map((q, idx) => (
        <div key={q.id} className={`chk-q ${q.is_required ? 'chk-q--required' : ''}`}>
          <label className="chk-q-label">
            <span className="chk-q-num">{idx + 1}</span>
            <span className="chk-q-text">{q.question_text}</span>
            {q.is_required
              ? <span className="chk-q-required">* مطلوب الآن</span>
              : <span className="chk-q-optional">اختياري</span>}
          </label>

          {q.hint_text && (
            <p className="chk-q-hint">
              <HelpCircle size={12} /> {q.hint_text}
            </p>
          )}

          <div className="chk-q-input">
            {renderInput(q, answers[q.id])}
          </div>
        </div>
      ))}

      {/* زر الإرسال (اختياري) */}
      {onComplete && (
        <button
          className={`chk-submit ${isComplete ? 'chk-submit--ready' : 'chk-submit--disabled'}`}
          onClick={() => isComplete && onComplete(buildResponses())}
          disabled={!isComplete}
          type="button"
        >
          {isComplete ? '✓ مكتمل — يمكنك إنهاء الزيارة' : `${requiredQuestions.length - requiredAnsweredCount} سؤال ظاهر مطلوب`}
        </button>
      )}

      <style>{styles}</style>
    </div>
  )
}

function parseOptions(options: unknown): string[] {
  if (!options) return []
  if (Array.isArray(options)) {
    return options.map(o => {
      if (typeof o === 'string') return o
      if (o && typeof o === 'object') {
        const record = o as Record<string, unknown>
        const val = record.label ?? record.value
        return typeof val === 'string' ? val : ''
      }
      return ''
    })
  }
  return []
}

const styles = `
  .chk-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4, 16px);
  }
  .chk-progress {
    display: flex;
    align-items: center;
    gap: var(--space-3, 12px);
  }
  .chk-progress-bar {
    flex: 1;
    height: 6px;
    background: var(--neutral-200, #e2e8f0);
    border-radius: 99px;
    overflow: hidden;
  }
  .chk-progress-fill {
    height: 100%;
    background: var(--color-primary, #2563eb);
    border-radius: 99px;
    transition: width 0.3s ease;
  }
  .chk-progress-text {
    font-size: var(--text-xs, 12px);
    color: var(--text-muted, #64748b);
    white-space: nowrap;
    font-weight: 500;
  }
  .chk-q {
    display: flex;
    flex-direction: column;
    gap: var(--space-2, 8px);
    padding: var(--space-3, 12px);
    border: 1px solid var(--border-light, #e2e8f0);
    border-radius: var(--radius-lg, 12px);
    background: var(--bg-surface, white);
  }
  .chk-q--required {
    border-inline-start: 3px solid var(--color-warning, #d97706);
  }
  .chk-q-label {
    display: flex;
    align-items: flex-start;
    gap: var(--space-2, 8px);
    font-size: var(--text-sm, 14px);
    font-weight: 600;
    color: var(--text-primary, #0f172a);
  }
  .chk-q-num {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 22px;
    height: 22px;
    background: var(--color-primary-light, rgba(37,99,235,0.1));
    color: var(--color-primary, #2563eb);
    border-radius: 50%;
    font-size: 11px;
    font-weight: 700;
    flex-shrink: 0;
  }
  .chk-q-text {
    flex: 1;
    line-height: 1.5;
  }
  .chk-q-required {
    color: var(--color-danger, #dc2626);
    font-size: 16px;
    flex-shrink: 0;
  }
  .chk-q-optional {
    color: var(--text-muted, #64748b);
    font-size: var(--text-xs, 12px);
    font-weight: 500;
    margin-inline-start: auto;
  }
  .chk-q-hint {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: var(--text-xs, 12px);
    color: var(--text-muted, #64748b);
    margin: 0;
    padding-inline-start: 30px;
  }
  .chk-q-input {
    padding-inline-start: 30px;
  }
  .chk-textarea, .chk-input {
    width: 100%;
    padding: var(--space-2, 8px) var(--space-3, 12px);
    border: 1px solid var(--border-light, #e2e8f0);
    border-radius: var(--radius-md, 8px);
    font-size: var(--text-sm, 14px);
    font-family: inherit;
    resize: vertical;
    transition: border-color 0.15s ease;
    background: var(--bg-surface, white);
    min-height: 44px;
  }
  .chk-textarea:focus, .chk-input:focus {
    outline: none;
    border-color: var(--color-primary, #2563eb);
    box-shadow: 0 0 0 3px var(--color-primary-light, rgba(37,99,235,0.1));
  }
  .chk-toggle-group {
    display: flex;
    gap: var(--space-2, 8px);
  }
  .chk-toggle {
    flex: 1;
    padding: var(--space-3, 12px) var(--space-3, 12px);
    min-height: 48px;
    border: 2px solid var(--border-light, #e2e8f0);
    border-radius: var(--radius-md, 8px);
    background: var(--bg-surface, white);
    cursor: pointer;
    font-size: var(--text-sm, 14px);
    font-weight: 600;
    transition: all 0.15s ease;
    font-family: inherit;
  }
  .chk-toggle:hover { border-color: var(--neutral-300, #cbd5e1); }
  .chk-toggle--active.chk-toggle--yes {
    border-color: var(--color-success, #16a34a);
    background: var(--color-success-light, rgba(22,163,74,0.1));
    color: var(--color-success, #16a34a);
  }
  .chk-toggle--active.chk-toggle--no {
    border-color: var(--color-danger, #dc2626);
    background: var(--color-danger-light, rgba(220,38,38,0.1));
    color: var(--color-danger, #dc2626);
  }
  .chk-choices {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2, 8px);
  }
  .chk-choice {
    padding: var(--space-2, 10px) var(--space-3, 14px);
    min-height: 40px;
    border: 1px solid var(--border-light, #e2e8f0);
    border-radius: var(--radius-md, 8px);
    background: var(--bg-surface, white);
    cursor: pointer;
    font-size: var(--text-xs, 12px);
    font-weight: 500;
    transition: all 0.15s ease;
    font-family: inherit;
    display: inline-flex;
    align-items: center;
  }
  .chk-choice:hover { border-color: var(--color-primary, #2563eb); }
  .chk-choice--selected {
    border-color: var(--color-primary, #2563eb);
    background: var(--color-primary-light, rgba(37,99,235,0.1));
    color: var(--color-primary, #2563eb);
    font-weight: 600;
  }
  .chk-rating {
    display: flex;
    align-items: center;
    gap: var(--space-1, 4px);
  }
  .chk-star {
    border: none;
    background: none;
    cursor: pointer;
    padding: 4px;
    color: var(--neutral-300, #cbd5e1);
    transition: color 0.1s ease, transform 0.15s ease;
  }
  .chk-star:hover { transform: scale(1.2); }
  .chk-star--filled { color: #f59e0b; }
  .chk-rating-text {
    margin-inline-start: var(--space-2, 8px);
    font-size: var(--text-sm, 14px);
    font-weight: 600;
    color: #f59e0b;
  }
  .chk-photo {
    display: flex;
    flex-direction: column;
    gap: var(--space-2, 8px);
  }
  .chk-photo-btn {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: var(--space-4, 16px) var(--space-4, 16px);
    min-height: 52px;
    border: 2px dashed var(--border-light, #e2e8f0);
    border-radius: var(--radius-lg, 12px);
    background: var(--neutral-50, #f8fafc);
    cursor: pointer;
    font-size: var(--text-sm, 14px);
    font-weight: 500;
    font-family: inherit;
    color: var(--text-secondary, #334155);
    transition: all 0.15s ease;
    width: 100%;
    justify-content: center;
  }
  .chk-photo-btn:hover:not(:disabled) {
    border-color: var(--color-primary, #2563eb);
    color: var(--color-primary, #2563eb);
  }
  .chk-photo-btn:disabled {
    cursor: not-allowed;
    background: var(--neutral-100, #f1f5f9);
    color: var(--text-muted, #94a3b8);
    border-style: solid;
  }
  .chk-photo-preview {
    max-width: 200px;
    max-height: 150px;
    border-radius: var(--radius-md, 8px);
    object-fit: cover;
    border: 1px solid var(--border-light, #e2e8f0);
  }
  .chk-photo-loading {
    font-size: var(--text-xs, 12px);
    color: var(--text-muted, #64748b);
  }
  .chk-photo-error {
    font-size: var(--text-xs, 12px);
    color: var(--color-danger, #dc2626);
  }
  .chk-submit {
    padding: var(--space-3, 12px) var(--space-4, 16px);
    border: none;
    border-radius: var(--radius-lg, 12px);
    font-size: var(--text-sm, 14px);
    font-weight: 600;
    cursor: pointer;
    transition: all 0.15s ease;
    font-family: inherit;
  }
  .chk-submit--ready {
    background: var(--color-success, #16a34a);
    color: white;
  }
  .chk-submit--ready:hover {
    background: #15803d;
  }
  .chk-submit--disabled {
    background: var(--neutral-200, #e2e8f0);
    color: var(--text-muted, #64748b);
    cursor: not-allowed;
  }
`

export type { ChecklistFormProps }
