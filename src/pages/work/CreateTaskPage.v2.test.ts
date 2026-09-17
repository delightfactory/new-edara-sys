import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./CreateTaskPage.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')
const formsCssPath = fileURLToPath(new URL('../../styles/design-system-v2-forms.css', import.meta.url))
const formsCss = readFileSync(formsCssPath, 'utf8')

describe('CreateTaskPage V2 source contract', () => {
  it('adopts the shared V2 form grammar and retires local Create Task shells', () => {
    expect(source).toContain("import Field from '@/components/ui/Field'")
    expect(source).toContain("import FormSection from '@/components/patterns/FormSection'")
    expect(source).toContain("import FormGrid from '@/components/patterns/FormGrid'")
    expect(source).toContain("import FormActions from '@/components/patterns/FormActions'")

    const sectionTitles = [
      'ما المطلوب بالضبط؟',
      'من المسؤول ومن يمسك الكرة الآن؟',
      'ما الخطوة التالية ومتى؟',
      'أولوية وخصوصية الإجراء',
    ]
    const positions = sectionTitles.map(title => source.indexOf(`<FormSection title="${title}">`))

    expect(positions.every(position => position >= 0)).toBe(true)
    expect(positions).toEqual([...positions].sort((a, b) => a - b))
    expect(source.match(/<FormGrid columns=\{2\}>/g)).toHaveLength(3)
    expect(source).toContain('<FormActions>')
    expect(source).not.toContain('stickyOnMobile')
    expect(source).not.toContain('className="work-form-card"')
    expect(source).not.toContain('className="work-form-grid"')
    expect(source).not.toContain('className="work-form-actions"')
    expect(source).not.toContain('className="work-field"')
  })

  it('keeps shared native form controls on the canonical touch-safe height contract', () => {
    expect(source).toContain('className="form-input"')
    expect(source).toContain('className="form-select"')
    expect(source).toContain('className="form-textarea"')
    expect(formsCss).toContain('.form-input,\n.form-select {\n  min-height: var(--control-height-md);\n}')
    expect(formsCss).toContain('.form-textarea {\n  min-height: max(80px, var(--control-height-md));\n}')
  })

  it('keeps required controls under manual noValidate semantics while exposing Field accessibility', () => {
    expect(source).toContain('<form className="work-form" onSubmit={handleSubmit} noValidate>')
    expect(source).toContain('id="work-title" label="عنوان المهمة" required error={errors.title}')
    expect(source).toContain('id="work-outcome"')
    expect(source).toContain('error={errors.expectedOutcome}')
    expect(source).toContain('id="work-next-action" label="الإجراء التالي" required error={errors.nextActionText}')
    expect(source).toContain('error={errors.ownerUserId}')
    expect(source).toContain('error={errors.assigneeUserId}')
    expect(source).toContain('aria-describedby={describedBy}')
    expect(source).toContain('aria-invalid={invalid || undefined}')
    expect(source).toContain('aria-required="true"')
  })

  it('preserves assignment, acknowledgement and responsibility ownership semantics', () => {
    expect(source).toContain("useAssignmentCandidates('')")
    expect(source).toContain('const self = candidates.find(candidate => candidate.is_self) ?? candidates[0]')
    expect(source).toContain('setOwnerUserId(current => current || self.user_id)')
    expect(source).toContain('setAssigneeUserId(current => current || self.user_id)')
    expect(source).toContain('if (assigneeIsSelf) setAcknowledgementRequired(false)')
    expect(source).toContain('disabled={!assigneeUserId || assigneeIsSelf}')
    expect(source).toContain('acknowledgementRequired: acknowledgementRequired && !assigneeIsSelf')
    expect(source).toContain('className="work-info-grid"')
    expect(source).toContain('className="work-inline-check"')
  })

  it('preserves validation wording and next-action versus due-date semantics exactly', () => {
    expect(source).toContain("if (!title.trim()) next.title = 'عنوان المهمة مطلوب'")
    expect(source).toContain("if (!expectedOutcome.trim()) next.expectedOutcome = 'حدد النتيجة التي تعتبر المهمة مكتملة عند تحقيقها'")
    expect(source).toContain("if (!nextActionText.trim()) next.nextActionText = 'حدد أول إجراء عملي بعد إنشاء المهمة'")
    expect(source).toContain("if (!ownerUserId) next.ownerUserId = 'حدد المسؤول النهائي عن النتيجة'")
    expect(source).toContain("if (!assigneeUserId) next.assigneeUserId = 'حدد الشخص الذي تقع عنده الكرة الآن'")
    expect(source).toContain('new Date(nextActionAt).getTime() > new Date(dueAt).getTime()')
    expect(source).toContain("next.nextActionAt = 'موعد الإجراء التالي لا يفضل أن يتجاوز الموعد النهائي للمهمة'")
  })

  it('preserves create payload, activation, toast and navigation truth', () => {
    expect(source).toContain('const createTask = useCreateTask()')
    expect(source).toContain('description: description.trim() || null')
    expect(source).toContain('expectedOutcome: expectedOutcome.trim()')
    expect(source).toContain('nextActionText: nextActionText.trim()')
    expect(source).toContain('dueAt: toIso(dueAt)')
    expect(source).toContain('nextActionAt: toIso(nextActionAt)')
    expect(source).toContain('priority,')
    expect(source).toContain('visibility,')
    expect(source).toContain('ownerUserId,')
    expect(source).toContain('assigneeUserId,')
    expect(source).toContain('completionMode,')
    expect(source).toContain('activate: true')
    expect(source).toContain("toast.success('تم إنشاء المهمة وتفعيلها')")
    expect(source).toContain('navigate(`/work/${result.work_item_id}`)')
    expect(source).toContain("toast.error(error instanceof Error ? error.message : 'تعذر إنشاء المهمة')")
  })

  it('keeps actions non-sticky, touch-safe and callback-compatible', () => {
    expect(source).toContain('<FormActions>')
    expect(source).toContain('variant="secondary" touchTarget onClick={() => navigate(\'/work\')}')
    expect(source).toContain('type="submit" touchTarget loading={createTask.isPending}')
    expect(source).toContain('إنشاء وتفعيل المهمة')
    expect(source).not.toContain('stickyOnMobile')
  })
})
