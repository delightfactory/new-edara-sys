import { useState, useMemo, useCallback, useEffect } from 'react'
import type { ChecklistQuestion, ChecklistResponseInput } from '@/lib/types/activities'
import { Star, Camera, HelpCircle } from 'lucide-react'

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
  initialValues?: Record<string, string | any>
  /** وضع القراءة فقط */
  readOnly?: boolean
}

/**
 * ChecklistForm — نموذج أسئلة الاستبيان
 *
 * يدعم 7 أنواع أسئلة:
 * text, number, yes_no, single_choice, multi_choice, rating, photo
 *
 * الأسئلة الإجبارية تمنع زر "الإنهاء" حتى الإجابة عليها.
 */
export default function ChecklistForm({
  questions,
  activityId,
  templateId,
  onComplete,
  onChange,
  initialValues = {},
  readOnly = false,
}: ChecklistFormProps) {
  const [answers, setAnswers] = useState<Record<string, string | any>>(() => {
    const init: Record<string, string | any> = {}
    for (const q of questions) {
      init[q.id] = initialValues[q.id] ?? (q.default_value ?? '')
    }
    return init
  })

  // حساب الاكتمال
  const requiredQuestions = useMemo(
    () => questions.filter(q => q.is_required),
    [questions]
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
    return questions.filter(q => {
      const val = answers[q.id]
      return val !== undefined && val !== null && val !== '' && !(Array.isArray(val) && val.length === 0)
    }).length
  }, [questions, answers])

  // بناء الردود
  const buildResponses = useCallback((): ChecklistResponseInput[] => {
    return questions.map(q => ({
      activity_id: activityId,
      template_id: templateId,
      question_id: q.id,
      answer_value: typeof answers[q.id] === 'string' ? answers[q.id] : null,
      answer_json: typeof answers[q.id] !== 'string' ? answers[q.id] : null,
    })).filter(r => r.answer_value || r.answer_json)
  }, [questions, activityId, templateId, answers])

  const handleChange = useCallback((questionId: string, value: any) => {
    setAnswers(prev => ({ ...prev, [questionId]: value }))
  }, [])

  // إبلاغ الـ parent بالتغيير — خارج setAnswers لتجنب setState أثناء render
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!onChange) return
    const responses = questions.map(q => ({
      activity_id: activityId,
      template_id: templateId,
      question_id: q.id,
      answer_value: typeof answers[q.id] === 'string' ? answers[q.id] : null,
      answer_json: typeof answers[q.id] !== 'string' ? answers[q.id] : null,
    })).filter(r => r.answer_value || r.answer_json)

    const allRequired = requiredQuestions.every(q => {
      const val = answers[q.id]
      return val !== undefined && val !== null && val !== '' && !(Array.isArray(val) && val.length === 0)
    })

    onChange(responses, allRequired)
  }, [answers])

  return (
    <div className="chk-form">
      {/* شريط التقدم */}
      <div className="chk-progress">
        <div className="chk-progress-bar">
          <div
            className="chk-progress-fill"
            style={{ width: `${questions.length > 0 ? (answeredCount / questions.length) * 100 : 0}%` }}
          />
        </div>
        <span className="chk-progress-text">
          {answeredCount}/{questions.length} سؤال
        </span>
      </div>

      {/* الأسئلة */}
      {questions.map((q, idx) => (
        <div key={q.id} className={`chk-q ${q.is_required ? 'chk-q--required' : ''}`}>
          <label className="chk-q-label">
            <span className="chk-q-num">{idx + 1}</span>
            <span className="chk-q-text">{q.question_text}</span>
            {q.is_required && <span className="chk-q-required">*</span>}
          </label>

          {q.hint_text && (
            <p className="chk-q-hint">
              <HelpCircle size={12} /> {q.hint_text}
            </p>
          )}

          <div className="chk-q-input">
            {renderInput(q, answers[q.id], handleChange, readOnly)}
          </div>
        </div>
      ))}

      {/* زر الإرسال (اختياري — يتحكم الـ parent عادةً) */}
      {onComplete && (
        <button
          className={`chk-submit ${isComplete ? 'chk-submit--ready' : 'chk-submit--disabled'}`}
          onClick={() => isComplete && onComplete(buildResponses())}
          disabled={!isComplete}
          type="button"
        >
          {isComplete ? '✓ الاستبيان مكتمل — جاهز للإنهاء' : `${requiredQuestions.length - answeredCount} سؤال إجباري متبقٍ`}
        </button>
      )}

      <style>{styles}</style>
    </div>
  )
}

// ── Render helpers ────────────────────────────────────────────

function renderInput(
  q: ChecklistQuestion,
  value: any,
  onChange: (id: string, val: any) => void,
  readOnly: boolean
) {
  switch (q.question_type) {
    case 'text':
      return (
        <textarea
          className="chk-textarea"
          value={value ?? ''}
          onChange={e => onChange(q.id, e.target.value)}
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
          value={value ?? ''}
          onChange={e => onChange(q.id, e.target.value)}
          placeholder={q.hint_text || 'أدخل رقماً'}
          min={q.min_value ?? undefined}
          max={q.max_value ?? undefined}
          readOnly={readOnly}
        />
      )

    case 'yes_no':
      return (
        <div className="chk-toggle-group">
          <button
            type="button"
            className={`chk-toggle ${value === 'yes' ? 'chk-toggle--active chk-toggle--yes' : ''}`}
            onClick={() => !readOnly && onChange(q.id, value === 'yes' ? '' : 'yes')}
          >
            نعم ✓
          </button>
          <button
            type="button"
            className={`chk-toggle ${value === 'no' ? 'chk-toggle--active chk-toggle--no' : ''}`}
            onClick={() => !readOnly && onChange(q.id, value === 'no' ? '' : 'no')}
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
              onClick={() => !readOnly && onChange(q.id, value === opt ? '' : opt)}
            >
              {value === opt && '● '}{opt}
            </button>
          ))}
        </div>
      )
    }

    case 'multi_choice': {
      const options = parseOptions(q.options)
      const selected = Array.isArray(value) ? value : []
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
                onChange(q.id, next)
              }}
            >
              {selected.includes(opt) ? '☑ ' : '☐ '}{opt}
            </button>
          ))}
        </div>
      )
    }

    case 'rating': {
      const rating = parseInt(value) || 0
      return (
        <div className="chk-rating">
          {[1, 2, 3, 4, 5].map(star => (
            <button
              key={star}
              type="button"
              className={`chk-star ${star <= rating ? 'chk-star--filled' : ''}`}
              onClick={() => !readOnly && onChange(q.id, star === rating ? '' : String(star))}
            >
              <Star size={24} fill={star <= rating ? 'currentColor' : 'none'} />
            </button>
          ))}
          {rating > 0 && <span className="chk-rating-text">{rating}/5</span>}
        </div>
      )
    }

    case 'photo':
      return (
        <div className="chk-photo">
          <button
            type="button"
            className="chk-photo-btn"
            onClick={() => {
              if (readOnly) return
              // TODO: implement camera capture
              const input = document.createElement('input')
              input.type = 'file'
              input.accept = 'image/*'
              input.capture = 'environment'
              input.onchange = (e: any) => {
                const file = e.target?.files?.[0]
                if (file) {
                  const reader = new FileReader()
                  reader.onload = () => onChange(q.id, reader.result)
                  reader.readAsDataURL(file)
                }
              }
              input.click()
            }}
          >
            <Camera size={20} />
            {value ? 'تغيير الصورة' : 'التقاط صورة'}
          </button>
          {value && typeof value === 'string' && value.startsWith('data:') && (
            <img src={value} alt="صورة ملتقطة" className="chk-photo-preview" />
          )}
        </div>
      )

    default:
      return null
  }
}

function parseOptions(options: any): string[] {
  if (!options) return []
  if (Array.isArray(options)) {
    return options.map(o => (typeof o === 'string' ? o : o.label || o.value || ''))
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
    border-right: 3px solid var(--color-warning, #d97706);
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
  .chk-q-hint {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: var(--text-xs, 12px);
    color: var(--text-muted, #64748b);
    margin: 0;
    padding-right: 30px;
  }
  .chk-q-input {
    padding-right: 30px;
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
    padding: var(--space-2, 8px) var(--space-3, 12px);
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
    padding: var(--space-2, 8px) var(--space-3, 12px);
    border: 1px solid var(--border-light, #e2e8f0);
    border-radius: var(--radius-md, 8px);
    background: var(--bg-surface, white);
    cursor: pointer;
    font-size: var(--text-xs, 12px);
    font-weight: 500;
    transition: all 0.15s ease;
    font-family: inherit;
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
    margin-right: var(--space-2, 8px);
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
    padding: var(--space-3, 12px) var(--space-4, 16px);
    border: 2px dashed var(--border-light, #e2e8f0);
    border-radius: var(--radius-lg, 12px);
    background: var(--neutral-50, #f8fafc);
    cursor: pointer;
    font-size: var(--text-sm, 14px);
    font-weight: 500;
    font-family: inherit;
    color: var(--text-secondary, #334155);
    transition: all 0.15s ease;
  }
  .chk-photo-btn:hover {
    border-color: var(--color-primary, #2563eb);
    color: var(--color-primary, #2563eb);
  }
  .chk-photo-preview {
    max-width: 200px;
    max-height: 150px;
    border-radius: var(--radius-md, 8px);
    object-fit: cover;
    border: 1px solid var(--border-light, #e2e8f0);
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
