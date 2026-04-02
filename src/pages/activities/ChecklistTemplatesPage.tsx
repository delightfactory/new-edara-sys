/**
 * ChecklistTemplatesPage — Wave A Final Fix
 * - Admin mode: sees active + inactive templates (includeInactive)
 * - Question authoring: options textarea for single/multi_choice, min/max for rating/number
 * - Edit question: same modal reused for editing
 * - Restricted to fully authorable question types only — no misleading UI
 */
import { useState } from 'react'
import { toast } from 'sonner'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import {
  useChecklistTemplates,
  useCreateChecklistTemplate,
  useUpdateChecklistTemplate,
  useDeleteChecklistTemplate,
  useCreateChecklistQuestion,
  useUpdateChecklistQuestion,
  useDeleteChecklistQuestion,
} from '@/hooks/useQueryHooks'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import { Plus, Trash2, ChevronDown, ChevronUp, Edit2, HelpCircle, Eye, EyeOff } from 'lucide-react'
import type {
  ChecklistTemplate,
  ChecklistQuestion,
  ChecklistTemplateInput,
  ChecklistQuestionInput,
  ChecklistQuestionType,
  ActivityCategory,
  PlanItemPurposeType,
} from '@/lib/types/activities'

const CATEGORY_OPTIONS: { value: ActivityCategory; label: string }[] = [
  { value: 'visit', label: 'زيارة ميدانية' },
]

/**
 * Wave A Final Fix: Only include question types we can fully author here.
 * - text, yes_no: no extra fields needed ✓
 * - number: supports min/max ✓
 * - rating: supports min/max ✓
 * - single_choice, multi_choice: support options list ✓
 * - photo: not authorable here (needs server config) — excluded
 */
const QUESTION_TYPE_OPTIONS: { value: ChecklistQuestionType; label: string; needsOptions?: boolean; needsRange?: boolean }[] = [
  { value: 'text',          label: 'نص حر' },
  { value: 'yes_no',        label: 'نعم / لا' },
  { value: 'number',        label: 'رقم',                 needsRange: true },
  { value: 'rating',        label: 'تقييم (نطاق رقمي)',   needsRange: true },
  { value: 'single_choice', label: 'اختيار واحد',         needsOptions: true },
  { value: 'multi_choice',  label: 'اختيار متعدد',        needsOptions: true },
]

const PURPOSE_OPTIONS: { value: PlanItemPurposeType; label: string }[] = [
  { value: 'sales',      label: 'مبيعات' },
  { value: 'collection', label: 'تحصيل' },
  { value: 'activation', label: 'تنشيط' },
  { value: 'promotion',  label: 'ترويج' },
  { value: 'followup',   label: 'متابعة' },
  { value: 'service',    label: 'خدمة' },
]

const CATEGORY_COLOR: Record<string, string> = {
  visit: 'var(--color-primary)',
  call:  'var(--text-muted)',
  task:  'var(--text-muted)',
}

const EMPTY_TEMPLATE: ChecklistTemplateInput = {
  name: '', description: null, category: 'visit',
  purpose_type: null, is_mandatory: false, is_active: true,
}

interface QFormState extends ChecklistQuestionInput {
  // authoring extras (stored in question_options / metadata)
  optionsText: string   // one option per line → parsed to array
  rangeMin: string
  rangeMax: string
}

const EMPTY_QFORM: QFormState = {
  question_text: '', question_type: 'yes_no', is_required: false,
  hint_text: null, optionsText: '', rangeMin: '', rangeMax: '',
}

function renderOptionSummary(q: ChecklistQuestion): string {
  const opts = (q as any).options
  if (Array.isArray(opts) && opts.length > 0) return opts.slice(0, 3).join(' / ') + (opts.length > 3 ? '...' : '')
  if (q.min_value != null || q.max_value != null) return `${q.min_value ?? '?'} — ${q.max_value ?? '?'}`
  return ''
}

export default function ChecklistTemplatesPage() {
  const can = useAuthStore(s => s.can)
  const canManage = can(PERMISSIONS.CHECKLISTS_MANAGE)

  // Admin mode: show active + inactive
  const { data: templates = [], isLoading } = useChecklistTemplates({ includeInactive: true })

  const createTemplate = useCreateChecklistTemplate()
  const updateTemplate = useUpdateChecklistTemplate()
  const deleteTemplate = useDeleteChecklistTemplate()
  const createQuestion = useCreateChecklistQuestion()
  const updateQuestion = useUpdateChecklistQuestion()
  const deleteQuestion = useDeleteChecklistQuestion()

  // Template modal
  const [showModal, setShowModal]             = useState(false)
  const [editingTemplate, setEditingTemplate] = useState<ChecklistTemplate | null>(null)
  const [form, setForm]                       = useState<ChecklistTemplateInput>(EMPTY_TEMPLATE)
  const [saving, setSaving]                   = useState(false)

  // Expanded template
  const [expandedId, setExpandedId] = useState<string | null>(null)

  // Question modal (shared for add + edit)
  const [showQModal, setShowQModal]   = useState(false)
  const [qTemplateId, setQTemplateId] = useState('')
  const [editingQ, setEditingQ]       = useState<ChecklistQuestion | null>(null)
  const [qForm, setQForm]             = useState<QFormState>(EMPTY_QFORM)
  const [qSaving, setQSaving]         = useState(false)

  // ── Template handlers ────────────────────────────────────────
  function openCreate() {
    setEditingTemplate(null)
    setForm(EMPTY_TEMPLATE)
    setShowModal(true)
  }
  function openEdit(t: ChecklistTemplate) {
    setEditingTemplate(t)
    setForm({
      name: t.name, description: t.description, category: t.category,
      purpose_type: t.purpose_type, is_mandatory: t.is_mandatory, is_active: t.is_active,
    })
    setShowModal(true)
  }
  async function handleSaveTemplate() {
    if (!form.name.trim()) { toast.error('اسم القالب مطلوب'); return }
    setSaving(true)
    try {
      if (editingTemplate) {
        await updateTemplate.mutateAsync({ id: editingTemplate.id, input: form })
        toast.success('تم تحديث القالب')
      } else {
        await createTemplate.mutateAsync(form)
        toast.success('تم إنشاء القالب')
      }
      setShowModal(false)
    } catch (e: any) {
      toast.error(e?.message || 'فشل الحفظ')
    } finally {
      setSaving(false)
    }
  }
  async function handleDeleteTemplate(id: string, name: string) {
    if (!confirm(`حذف قالب "${name}"؟ سيتم حذف كل أسئلته.`)) return
    try {
      await deleteTemplate.mutateAsync(id)
      toast.success('تم حذف القالب')
    } catch (e: any) {
      toast.error(e?.message || 'فشل الحذف')
    }
  }

  // ── Question handlers ────────────────────────────────────────
  function openAddQuestion(templateId: string) {
    setQTemplateId(templateId)
    setEditingQ(null)
    setQForm(EMPTY_QFORM)
    setShowQModal(true)
  }
  function openEditQuestion(templateId: string, q: ChecklistQuestion) {
    setQTemplateId(templateId)
    setEditingQ(q)
    const opts = (q as any).options
    setQForm({
      question_text: q.question_text,
      question_type: q.question_type,
      is_required: q.is_required,
      hint_text: (q as any).hint_text ?? null,
      optionsText: Array.isArray(opts) ? opts.join('\n') : '',
      rangeMin: q.min_value != null ? String(q.min_value) : '',
      rangeMax: q.max_value != null ? String(q.max_value) : '',
    })
    setShowQModal(true)
  }

  function buildQuestionPayload(): ChecklistQuestionInput {
    const typeMeta = QUESTION_TYPE_OPTIONS.find(o => o.value === qForm.question_type)
    const base: ChecklistQuestionInput = {
      question_text: qForm.question_text.trim(),
      question_type: qForm.question_type,
      is_required: qForm.is_required,
      hint_text: qForm.hint_text || null,
    }
    if (typeMeta?.needsOptions) {
      const opts = qForm.optionsText
        .split('\n')
        .map(s => s.trim())
        .filter(Boolean)
      ;(base as any).options = opts
    }
    if (typeMeta?.needsRange) {
      base.min_value = qForm.rangeMin !== '' ? Number(qForm.rangeMin) : null
      base.max_value = qForm.rangeMax !== '' ? Number(qForm.rangeMax) : null
    }
    return base
  }

  async function handleSaveQuestion() {
    if (!qForm.question_text.trim()) { toast.error('نص السؤال مطلوب'); return }
    const typeMeta = QUESTION_TYPE_OPTIONS.find(o => o.value === qForm.question_type)
    if (typeMeta?.needsOptions) {
      const opts = qForm.optionsText.split('\n').map(s => s.trim()).filter(Boolean)
      if (opts.length < 2) { toast.error('أضف خيارَين على الأقل (سطر لكل خيار)'); return }
    }
    setQSaving(true)
    try {
      const payload = buildQuestionPayload()
      if (editingQ) {
        await updateQuestion.mutateAsync({ id: editingQ.id, input: payload })
        toast.success('تم تحديث السؤال')
      } else {
        await createQuestion.mutateAsync({ templateId: qTemplateId, input: payload })
        toast.success('تمت إضافة السؤال')
      }
      setShowQModal(false)
    } catch (e: any) {
      toast.error(e?.message || 'فشل الحفظ')
    } finally {
      setQSaving(false)
    }
  }

  async function handleDeleteQuestion(id: string) {
    if (!confirm('حذف هذا السؤال؟')) return
    try {
      await deleteQuestion.mutateAsync(id)
      toast.success('تم حذف السؤال')
    } catch (e: any) {
      toast.error(e?.message || 'فشل الحذف')
    }
  }

  const selectedQTypeMeta = QUESTION_TYPE_OPTIONS.find(o => o.value === qForm.question_type)

  if (!canManage) {
    return (
      <div className="page-container animate-enter">
        <div className="empty-state p-8">
          <p className="empty-state-title">ليس لديك صلاحية الوصول لهذه الصفحة</p>
        </div>
      </div>
    )
  }

  const active   = templates.filter(t => t.is_active)
  const inactive = templates.filter(t => !t.is_active)

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="استبيانات الزيارات"
        subtitle={`${active.length} مفعّل · ${inactive.length} معطّل`}
        breadcrumbs={[
          { label: 'الأنشطة', path: '/activities' },
          { label: 'الاستبيانات' },
        ]}
        actions={
          <Button icon={<Plus size={16} />} onClick={openCreate}>
            قالب جديد
          </Button>
        }
      />

      {isLoading ? (
        <div className="edara-card p-6">
          {[1,2,3].map(i => <div key={i} className="skeleton h-14 mb-3 rounded-lg" />)}
        </div>
      ) : templates.length === 0 ? (
        <div className="empty-state p-10">
          <HelpCircle size={40} className="text-muted mx-auto mb-3" />
          <p className="empty-state-title">لا توجد قوالب استبيانات بعد</p>
          <p className="empty-state-desc">أنشئ قالباً وأضف أسئلة ليستخدمها المندوب أثناء الزيارة</p>
          <Button icon={<Plus size={16} />} onClick={openCreate} className="mt-4">إنشاء أول قالب</Button>
        </div>
      ) : (
        <div className="chk-list">
          {templates.map(t => {
            const isExpanded = expandedId === t.id
            const questions  = t.questions ?? []
            return (
              <div key={t.id} className={`edara-card chk-card${!t.is_active ? ' chk-card--inactive' : ''}`}>
                {/* Header */}
                <div className="chk-card-header">
                  <div className="chk-card-main">
                    <span
                      className="chk-category-badge"
                      style={{ background: CATEGORY_COLOR[t.category] + '22', color: CATEGORY_COLOR[t.category], opacity: t.is_active ? 1 : 0.5 }}
                    >
                      {CATEGORY_OPTIONS.find(c => c.value === t.category)?.label || 'غير مدعوم (' + t.category + ')'}
                    </span>
                    <div>
                      <div className="chk-card-name" style={!t.is_active ? { opacity: 0.6 } : undefined}>{t.name}</div>
                      {t.description && <div className="chk-card-desc">{t.description}</div>}
                    </div>
                    <div className="chk-card-meta">
                      <span className="chk-meta-chip">{questions.length} سؤال</span>
                      {t.is_mandatory && <span className="chk-meta-chip chk-meta-chip--warn">إلزامي</span>}
                      {!t.is_active && (
                        <span className="chk-meta-chip chk-meta-chip--muted" title="معطّل — لن يظهر للمندوبين">
                          <EyeOff size={10} style={{ display: 'inline', verticalAlign: 'middle' }} /> معطّل
                        </span>
                      )}
                    </div>
                  </div>
                  <div className="chk-card-actions">
                    <Button variant="ghost" size="sm" icon={<Edit2 size={14} />} onClick={() => openEdit(t)} />
                    <Button
                      variant="ghost" size="sm"
                      icon={isExpanded ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                      onClick={() => setExpandedId(isExpanded ? null : t.id)}
                    />
                    <Button
                      variant="ghost" size="sm" icon={<Trash2 size={14} />}
                      className="text-danger"
                      onClick={() => handleDeleteTemplate(t.id, t.name)}
                    />
                  </div>
                </div>

                {/* Expanded questions */}
                {isExpanded && (
                  <div className="chk-questions animate-enter">
                    {questions.length === 0 ? (
                      <div className="chk-q-empty">لا توجد أسئلة — أضف سؤالاً أولاً</div>
                    ) : (
                      questions.map((q, idx) => {
                        const summary = renderOptionSummary(q)
                        return (
                          <div key={q.id} className="chk-q-row">
                            <span className="chk-q-num">{idx + 1}</span>
                            <div className="chk-q-body">
                              <span className="chk-q-text">{q.question_text}</span>
                              <span className="chk-q-type">
                                {QUESTION_TYPE_OPTIONS.find(o => o.value === q.question_type)?.label}
                                {q.is_required && ' · مطلوب'}
                                {summary && ` · ${summary}`}
                              </span>
                            </div>
                            <div className="flex gap-1">
                              <Button
                                variant="ghost" size="sm" icon={<Edit2 size={13} />}
                                onClick={() => openEditQuestion(t.id, q)}
                              />
                              <Button
                                variant="ghost" size="sm" icon={<Trash2 size={13} />}
                                className="text-danger"
                                onClick={() => handleDeleteQuestion(q.id)}
                              />
                            </div>
                          </div>
                        )
                      })
                    )}
                    <Button
                      variant="secondary" size="sm"
                      icon={<Plus size={14} />}
                      onClick={() => openAddQuestion(t.id)}
                      className="mt-3"
                    >
                      إضافة سؤال
                    </Button>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}

      {/* ── Template Modal ──────────────────────────────────── */}
      <ResponsiveModal
        open={showModal}
        onClose={() => setShowModal(false)}
        title={editingTemplate ? 'تعديل القالب' : 'قالب جديد'}
      >
        <div className="flex flex-col gap-4">
          <div className="form-group">
            <label className="form-label">اسم القالب <span className="form-required">*</span></label>
            <input
              className="form-input"
              value={form.name}
              onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
              placeholder="مثال: استبيان زيارة عميل جديد"
              autoFocus
            />
          </div>
          <div className="form-group">
            <label className="form-label">الوصف</label>
            <textarea
              className="form-textarea"
              rows={2}
              value={form.description ?? ''}
              onChange={e => setForm(f => ({ ...f, description: e.target.value || null }))}
              placeholder="وصف اختياري..."
            />
          </div>
          <div className="form-group">
            <label className="form-label">الفئة <span className="form-required">*</span></label>
            <select
              className="form-select"
              value={form.category}
              onChange={e => setForm(f => ({ ...f, category: e.target.value as ActivityCategory }))}
            >
              {CATEGORY_OPTIONS.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
          </div>
          <div className="form-group">
            <label className="form-label">غرض الخطة (اختياري)</label>
            <select
              className="form-select"
              value={form.purpose_type ?? ''}
              onChange={e => setForm(f => ({ ...f, purpose_type: e.target.value as PlanItemPurposeType || null }))}
            >
              <option value="">— كل الأغراض —</option>
              {PURPOSE_OPTIONS.map(p => <option key={p.value} value={p.value}>{p.label}</option>)}
            </select>
          </div>
          <div className="flex gap-4 items-center">
            <label className="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" checked={form.is_mandatory ?? false}
                onChange={e => setForm(f => ({ ...f, is_mandatory: e.target.checked }))} />
              <span className="text-sm">إلزامي (يجب ملؤه قبل إغلاق النشاط)</span>
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" checked={form.is_active ?? true}
                onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} />
              <span className="text-sm">مفعّل</span>
            </label>
          </div>
          <div className="flex gap-3 justify-end mt-2">
            <Button variant="secondary" onClick={() => setShowModal(false)}>إلغاء</Button>
            <Button onClick={handleSaveTemplate} disabled={saving}>
              {saving ? 'جاري الحفظ...' : 'حفظ'}
            </Button>
          </div>
        </div>
      </ResponsiveModal>

      {/* ── Question Modal (Add + Edit) ─────────────────────── */}
      <ResponsiveModal
        open={showQModal}
        onClose={() => setShowQModal(false)}
        title={editingQ ? 'تعديل السؤال' : 'إضافة سؤال'}
      >
        <div className="flex flex-col gap-4">
          <div className="form-group">
            <label className="form-label">نص السؤال <span className="form-required">*</span></label>
            <input
              className="form-input"
              value={qForm.question_text}
              onChange={e => setQForm(q => ({ ...q, question_text: e.target.value }))}
              placeholder="مثال: هل وجدت المخزون كافياً؟"
              autoFocus
            />
          </div>
          <div className="form-group">
            <label className="form-label">نوع السؤال</label>
            <select
              className="form-select"
              value={qForm.question_type}
              onChange={e => setQForm(q => ({ ...q, question_type: e.target.value as ChecklistQuestionType, optionsText: '', rangeMin: '', rangeMax: '' }))}
            >
              {QUESTION_TYPE_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          </div>

          {/* Conditional: options list for choice types */}
          {selectedQTypeMeta?.needsOptions && (
            <div className="form-group">
              <label className="form-label">الخيارات <span className="form-required">*</span></label>
              <textarea
                className="form-textarea"
                rows={4}
                value={qForm.optionsText}
                onChange={e => setQForm(q => ({ ...q, optionsText: e.target.value }))}
                placeholder={`خيار 1\nخيار 2\nخيار 3\n(سطر لكل خيار)`}
                dir="rtl"
              />
              <div className="text-xs text-muted mt-1">
                {qForm.optionsText.split('\n').filter(s => s.trim()).length} خيار حتى الآن
              </div>
            </div>
          )}

          {/* Conditional: range for number/rating */}
          {selectedQTypeMeta?.needsRange && (
            <div className="flex gap-3">
              <div className="form-group flex-1">
                <label className="form-label">أدنى قيمة</label>
                <input
                  className="form-input"
                  type="number"
                  value={qForm.rangeMin}
                  onChange={e => setQForm(q => ({ ...q, rangeMin: e.target.value }))}
                  placeholder={qForm.question_type === 'rating' ? '1' : '0'}
                />
              </div>
              <div className="form-group flex-1">
                <label className="form-label">أعلى قيمة</label>
                <input
                  className="form-input"
                  type="number"
                  value={qForm.rangeMax}
                  onChange={e => setQForm(q => ({ ...q, rangeMax: e.target.value }))}
                  placeholder={qForm.question_type === 'rating' ? '5' : '100'}
                />
              </div>
            </div>
          )}

          <div className="form-group">
            <label className="form-label">تلميح (اختياري)</label>
            <input
              className="form-input"
              value={qForm.hint_text ?? ''}
              onChange={e => setQForm(q => ({ ...q, hint_text: e.target.value || null }))}
              placeholder="توضيح للمستخدم..."
            />
          </div>
          <label className="flex items-center gap-2 cursor-pointer text-sm">
            <input
              type="checkbox"
              checked={qForm.is_required ?? false}
              onChange={e => setQForm(q => ({ ...q, is_required: e.target.checked }))}
            />
            هذا السؤال إلزامي
          </label>
          <div className="flex gap-3 justify-end mt-2">
            <Button variant="secondary" onClick={() => setShowQModal(false)}>إلغاء</Button>
            <Button onClick={handleSaveQuestion} disabled={qSaving}>
              {qSaving ? 'جاري الحفظ...' : editingQ ? 'تحديث' : 'إضافة'}
            </Button>
          </div>
        </div>
      </ResponsiveModal>

      <style>{`
        .chk-list { display: flex; flex-direction: column; gap: var(--space-3); }
        .chk-card { padding: var(--space-4) var(--space-5); }
        .chk-card--inactive { opacity: 0.75; border-style: dashed; }
        .chk-card-header { display: flex; align-items: flex-start; gap: var(--space-3); }
        .chk-card-main { display: flex; align-items: flex-start; gap: var(--space-3); flex: 1; flex-wrap: wrap; }
        .chk-category-badge { padding: 3px 10px; border-radius: var(--radius-full); font-size: var(--text-xs); font-weight: 700; white-space: nowrap; flex-shrink: 0; }
        .chk-card-name { font-weight: 600; font-size: var(--text-sm); color: var(--text-primary); }
        .chk-card-desc { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }
        .chk-card-meta { display: flex; gap: var(--space-1); flex-wrap: wrap; margin-inline-start: auto; }
        .chk-meta-chip { font-size: 11px; padding: 2px 8px; border-radius: var(--radius-full); background: var(--bg-surface-2, var(--bg-surface)); border: 1px solid var(--border-primary); color: var(--text-secondary); font-weight: 500; }
        .chk-meta-chip--warn { color: var(--color-warning); border-color: var(--color-warning); }
        .chk-meta-chip--muted { opacity: .7; }
        .chk-card-actions { display: flex; gap: var(--space-1); flex-shrink: 0; }
        .chk-questions { margin-top: var(--space-4); padding-top: var(--space-4); border-top: 1px solid var(--border-primary); }
        .chk-q-empty { font-size: var(--text-sm); color: var(--text-muted); text-align: center; padding: var(--space-3); }
        .chk-q-row { display: flex; align-items: center; gap: var(--space-2); padding: var(--space-2) 0; border-bottom: 1px solid var(--border-primary); }
        .chk-q-row:last-of-type { border-bottom: none; }
        .chk-q-num { width: 22px; height: 22px; display: flex; align-items: center; justify-content: center; background: var(--color-primary-light); color: var(--color-primary); border-radius: var(--radius-full); font-size: 11px; font-weight: 700; flex-shrink: 0; }
        .chk-q-body { flex: 1; }
        .chk-q-text { font-size: var(--text-sm); color: var(--text-primary); display: block; }
        .chk-q-type { font-size: var(--text-xs); color: var(--text-muted); }
      `}</style>
    </div>
  )
}
