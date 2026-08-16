import { useMemo, useRef, useState, type FormEvent } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { CheckCircle2, Clock3, Inbox, Send } from 'lucide-react'
import { toast } from 'sonner'
import Button from '@/components/ui/Button'
import PageHeader from '@/components/shared/PageHeader'
import {
  listAvailableRequestTypes,
  submitWorkRequest,
  type WorkRequestIntakeField,
} from '@/features/work/runtime-api'
import { workKeys } from '@/features/work/query-keys'
import './work.css'

type IntakeValue = string | boolean

function formatDuration(minutes: number | null) {
  if (minutes === null) return null
  if (minutes < 60) return `${minutes} دقيقة`
  if (minutes % (24 * 60) === 0) return `${minutes / (24 * 60)} يوم`
  if (minutes % 60 === 0) return `${minutes / 60} ساعة`
  return `${Math.floor(minutes / 60)} ساعة و${minutes % 60} دقيقة`
}

function buildPayload(
  fields: WorkRequestIntakeField[],
  values: Record<string, IntakeValue>,
) {
  const payload: Record<string, unknown> = {}
  const errors: Record<string, string> = {}

  for (const field of fields) {
    const raw = values[field.key]

    if (field.type === 'boolean') {
      payload[field.key] = raw === true
      continue
    }

    const text = typeof raw === 'string' ? raw.trim() : ''
    if (!text) {
      if (field.required) errors[field.key] = 'هذا الحقل مطلوب'
      continue
    }

    if (field.type === 'string') {
      payload[field.key] = text
      continue
    }

    if (field.type === 'number') {
      const numberValue = Number(text)
      if (!Number.isFinite(numberValue)) {
        errors[field.key] = 'أدخل رقمًا صحيحًا'
      } else {
        payload[field.key] = numberValue
      }
      continue
    }

    try {
      const parsed = JSON.parse(text) as unknown
      if (field.type === 'array' && !Array.isArray(parsed)) {
        errors[field.key] = 'أدخل قائمة JSON صحيحة، مثال: ["عنصر 1", "عنصر 2"]'
      } else if (
        field.type === 'object'
        && (parsed === null || Array.isArray(parsed) || typeof parsed !== 'object')
      ) {
        errors[field.key] = 'أدخل كائن JSON صحيح، مثال: {"المفتاح":"القيمة"}'
      } else {
        payload[field.key] = parsed
      }
    } catch {
      errors[field.key] = field.type === 'array'
        ? 'صيغة القائمة غير صحيحة'
        : 'صيغة كائن البيانات غير صحيحة'
    }
  }

  return { payload, errors }
}

export default function SubmitRequestPanel({ initialTypeKey }: { initialTypeKey?: string | null }) {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const operationIdRef = useRef<string | null>(null)

  const requestTypes = useQuery({
    queryKey: ['work', 'request-types', 'available'],
    queryFn: listAvailableRequestTypes,
    staleTime: 5 * 60_000,
  })

  const submitRequest = useMutation({
    mutationFn: submitWorkRequest,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: workKeys.all }),
  })

  const availableTypes = requestTypes.data ?? []
  const initialTypeId = useMemo(() => {
    if (!initialTypeKey) return ''
    return availableTypes.find(type => type.id === initialTypeKey || type.code === initialTypeKey)?.id ?? ''
  }, [availableTypes, initialTypeKey])

  const [selectedTypeId, setSelectedTypeId] = useState('')
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [values, setValues] = useState<Record<string, IntakeValue>>({})
  const [errors, setErrors] = useState<Record<string, string>>({})

  const effectiveTypeId = selectedTypeId || initialTypeId
  const selectedType = availableTypes.find(type => type.id === effectiveTypeId) ?? null

  const markDirty = () => {
    operationIdRef.current = null
  }

  const changeType = (value: string) => {
    markDirty()
    setSelectedTypeId(value)
    setValues({})
    setErrors({})
  }

  const changeValue = (key: string, value: IntakeValue) => {
    markDirty()
    setValues(current => ({ ...current, [key]: value }))
    setErrors(current => {
      if (!current[key]) return current
      const next = { ...current }
      delete next[key]
      return next
    })
  }

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault()

    const nextErrors: Record<string, string> = {}
    if (!selectedType) nextErrors.requestType = 'اختر نوع الطلب'
    if (!title.trim()) nextErrors.title = 'عنوان الطلب مطلوب'

    const intake = buildPayload(selectedType?.intake_schema.fields ?? [], values)
    Object.assign(nextErrors, intake.errors)
    setErrors(nextErrors)
    if (Object.keys(nextErrors).length > 0 || !selectedType) return

    const operationId = operationIdRef.current ?? crypto.randomUUID()
    operationIdRef.current = operationId

    try {
      const result = await submitRequest.mutateAsync({
        operationId,
        requestTypeId: selectedType.id,
        title: title.trim(),
        description: description.trim() || null,
        intakePayload: intake.payload,
      })
      operationIdRef.current = null
      toast.success('تم إرسال الطلب لجهة الاستقبال')
      navigate(`/work/${result.work_item_id}`)
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر إرسال الطلب')
    }
  }

  const triageDuration = formatDuration(selectedType?.triage_sla_minutes ?? null)
  const resolutionDuration = formatDuration(selectedType?.default_resolution_sla_minutes ?? null)

  return (
    <div className="work-page">
      <PageHeader
        title="إرسال طلب"
        subtitle="اختر الخدمة المطلوبة وأدخل البيانات؛ النظام سيوجه الطلب تلقائيًا للجهة المسؤولة ويتابع زمن الاستجابة."
        backPath="/work"
      />

      {requestTypes.isLoading ? (
        <div className="work-form">
          <div className="skeleton skeleton-row" />
          <div className="skeleton skeleton-row" />
        </div>
      ) : requestTypes.isError ? (
        <div className="work-empty">
          <div className="work-empty-icon"><Inbox size={22} /></div>
          <strong>تعذر تحميل أنواع الطلبات</strong>
          <span>أعد المحاولة، وإذا استمرت المشكلة راجع صلاحية إرسال الطلبات.</span>
          <Button variant="secondary" onClick={() => void requestTypes.refetch()}>إعادة المحاولة</Button>
        </div>
      ) : availableTypes.length === 0 ? (
        <div className="work-empty">
          <div className="work-empty-icon"><Inbox size={22} /></div>
          <strong>لا توجد أنواع طلبات متاحة حاليًا</strong>
          <span>يجب تفعيل نوع طلب وربطه بجهة استقبال نشطة قبل الإرسال.</span>
          <Button variant="secondary" onClick={() => navigate('/work')}>العودة إلى مركز العمل</Button>
        </div>
      ) : (
        <form className="work-form" onSubmit={handleSubmit} noValidate>
          <section className="work-form-card">
            <h2 className="work-form-section-title">ما الخدمة التي تحتاجها؟</h2>
            <div className="work-field">
              <label htmlFor="work-request-type">نوع الطلب *</label>
              <select
                id="work-request-type"
                value={effectiveTypeId}
                onChange={event => changeType(event.target.value)}
                autoFocus
              >
                <option value="">اختر نوع الطلب</option>
                {availableTypes.map(type => (
                  <option key={type.id} value={type.id}>{type.name}</option>
                ))}
              </select>
              {errors.requestType && <span className="form-error">{errors.requestType}</span>}
            </div>

            {selectedType && (
              <div className="work-info-grid" style={{ marginTop: 'var(--space-4)' }}>
                <div className="work-info-cell">
                  <div className="work-info-label">جهة الاستقبال</div>
                  <div className="work-info-value">{selectedType.target_queue_name}</div>
                </div>
                <div className="work-info-cell">
                  <div className="work-info-label">زمن الفرز المستهدف</div>
                  <div className="work-info-value">{triageDuration ?? 'حسب سياسة الجهة'}</div>
                </div>
                <div className="work-info-cell">
                  <div className="work-info-label">زمن الإنجاز المستهدف</div>
                  <div className="work-info-value">{resolutionDuration ?? 'يحدد بعد الفرز'}</div>
                </div>
              </div>
            )}

            {selectedType?.description && (
              <p className="work-field-hint" style={{ marginTop: 'var(--space-3)' }}>{selectedType.description}</p>
            )}
          </section>

          {selectedType && (
            <>
              <section className="work-form-card">
                <h2 className="work-form-section-title">صف طلبك بوضوح</h2>
                <div className="work-form">
                  <div className="work-field">
                    <label htmlFor="work-request-title">عنوان الطلب *</label>
                    <input
                      id="work-request-title"
                      value={title}
                      maxLength={250}
                      onChange={event => {
                        markDirty()
                        setTitle(event.target.value)
                      }}
                      placeholder="اكتب عنوانًا مختصرًا يوضح المطلوب"
                    />
                    {errors.title && <span className="form-error">{errors.title}</span>}
                  </div>

                  <div className="work-field">
                    <label htmlFor="work-request-description">تفاصيل إضافية</label>
                    <textarea
                      id="work-request-description"
                      value={description}
                      onChange={event => {
                        markDirty()
                        setDescription(event.target.value)
                      }}
                      placeholder="أضف أي سياق يساعد جهة الاستقبال على فهم الطلب من أول مرة."
                    />
                  </div>

                  {selectedType.expected_outcome_template && (
                    <div className="work-info-cell">
                      <div className="work-info-label"><CheckCircle2 size={14} /> معيار اكتمال الطلب</div>
                      <div className="work-info-value">{selectedType.expected_outcome_template}</div>
                    </div>
                  )}
                </div>
              </section>

              {selectedType.intake_schema.fields.length > 0 && (
                <section className="work-form-card">
                  <h2 className="work-form-section-title">بيانات الطلب</h2>
                  <div className="work-form-grid">
                    {selectedType.intake_schema.fields.map(field => (
                      <div className="work-field" key={field.key}>
                        {field.type === 'boolean' ? (
                          <label className="work-inline-check">
                            <input
                              type="checkbox"
                              checked={values[field.key] === true}
                              onChange={event => changeValue(field.key, event.target.checked)}
                            />
                            <span>{field.label}{field.required ? ' *' : ''}</span>
                          </label>
                        ) : field.type === 'array' || field.type === 'object' ? (
                          <>
                            <label htmlFor={`work-request-${field.key}`}>{field.label}{field.required ? ' *' : ''}</label>
                            <textarea
                              id={`work-request-${field.key}`}
                              dir="ltr"
                              value={typeof values[field.key] === 'string' ? values[field.key] as string : ''}
                              onChange={event => changeValue(field.key, event.target.value)}
                              placeholder={field.type === 'array' ? '["عنصر 1", "عنصر 2"]' : '{"المفتاح":"القيمة"}'}
                            />
                          </>
                        ) : (
                          <>
                            <label htmlFor={`work-request-${field.key}`}>{field.label}{field.required ? ' *' : ''}</label>
                            <input
                              id={`work-request-${field.key}`}
                              type={field.type === 'number' ? 'number' : 'text'}
                              value={typeof values[field.key] === 'string' ? values[field.key] as string : ''}
                              onChange={event => changeValue(field.key, event.target.value)}
                            />
                          </>
                        )}
                        {field.help && <span className="work-field-hint">{field.help}</span>}
                        {errors[field.key] && <span className="form-error">{errors[field.key]}</span>}
                      </div>
                    ))}
                  </div>
                </section>
              )}

              <section className="work-form-card">
                <div className="work-info-value" style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
                  <Clock3 size={16} /> بعد الإرسال سيظهر الطلب في مركز العمل ويمكن متابعة حالته ومن تقع عنده الكرة.
                </div>
              </section>
            </>
          )}

          <div className="work-form-actions">
            <Button type="button" variant="secondary" onClick={() => navigate('/work')}>إلغاء</Button>
            <Button type="submit" loading={submitRequest.isPending} disabled={!selectedType} icon={<Send size={17} />}>
              إرسال الطلب
            </Button>
          </div>
        </form>
      )}
    </div>
  )
}
