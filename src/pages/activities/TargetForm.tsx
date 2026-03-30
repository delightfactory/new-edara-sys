/**
 * TargetForm — إنشاء هدف جديد مع دعم كامل لـ scope_id
 * يُستدعى من /activities/targets/new
 *
 * قواعد scope_id (من 21_activities_module_mvp.sql line 513):
 *   company    → scope_id = null      (لا يُحدد فرع/قسم/موظف)
 *   branch     → scope_id = branch_id  (مطلوب)
 *   department → scope_id = department_id (مطلوب)
 *   individual → scope_id = employee_id  (مطلوب)
 */
import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import {
  useCreateTarget,
  useTargetTypes,
  useBranches,
  useHRDepartments,
  useHREmployees,
} from '@/hooks/useQueryHooks'
import type { TargetInput, TargetScope, TargetPeriod } from '@/lib/types/activities'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'

// ── Helpers ─────────────────────────────────────────────────────

const SCOPE_OPTIONS: { value: TargetScope; label: string; needsScopeId: boolean }[] = [
  { value: 'company',    label: 'الشركة كلها',  needsScopeId: false },
  { value: 'branch',     label: 'فرع',           needsScopeId: true  },
  { value: 'department', label: 'قسم',           needsScopeId: true  },
  { value: 'individual', label: 'موظف بعينه',    needsScopeId: true  },
]

const PERIOD_OPTIONS: { value: TargetPeriod; label: string }[] = [
  { value: 'monthly',   label: 'شهري' },
  { value: 'quarterly', label: 'ربع سنوي' },
  { value: 'yearly',    label: 'سنوي' },
  { value: 'custom',    label: 'مخصص' },
]

function getDefaultDates(period: TargetPeriod): { start: string; end: string } {
  const now   = new Date()
  const year  = now.getFullYear()
  const month = now.getMonth()
  switch (period) {
    case 'monthly': {
      const s = new Date(year, month, 1)
      const e = new Date(year, month + 1, 0)
      return { start: s.toISOString().slice(0, 10), end: e.toISOString().slice(0, 10) }
    }
    case 'quarterly': {
      const q = Math.floor(month / 3)
      const s = new Date(year, q * 3, 1)
      const e = new Date(year, q * 3 + 3, 0)
      return { start: s.toISOString().slice(0, 10), end: e.toISOString().slice(0, 10) }
    }
    case 'yearly':
      return { start: `${year}-01-01`, end: `${year}-12-31` }
    default:
      return { start: now.toISOString().slice(0, 10), end: now.toISOString().slice(0, 10) }
  }
}

// ── Component ────────────────────────────────────────────────────

export default function TargetForm() {
  const navigate     = useNavigate()
  const createTarget = useCreateTarget()

  // ── Reference Data ──────────────────────────────────────────
  const { data: targetTypes  = [] } = useTargetTypes()
  const { data: branches     = [] } = useBranches()
  const { data: departments  = [] } = useHRDepartments(true)
  // جلب الموظفين بـ pageSize كبير لـ dropdown (يمكن تحسينه لاحقاً بـ search)
  const { data: employeesRes }      = useHREmployees({ pageSize: 200 })
  const employees = useMemo(() => employeesRes?.data ?? [], [employeesRes])

  // ── Form State ──────────────────────────────────────────────
  const [typeId,        setTypeId]        = useState('')
  const [name,          setName]          = useState('')
  const [scope,         setScope]         = useState<TargetScope>('company')
  const [scopeId,       setScopeId]       = useState('')         // "raw" scope_id input
  const [period,        setPeriod]        = useState<TargetPeriod>('monthly')
  const [periodStart,   setPeriodStart]   = useState(() => getDefaultDates('monthly').start)
  const [periodEnd,     setPeriodEnd]     = useState(() => getDefaultDates('monthly').end)
  const [targetValue,   setTargetValue]   = useState('')
  const [minValue,      setMinValue]      = useState('')
  const [stretchValue,  setStretchValue]  = useState('')
  const [description,   setDescription]   = useState('')
  const [notes,         setNotes]         = useState('')
  const [saving,        setSaving]        = useState(false)

  // ── Derived ─────────────────────────────────────────────────
  const selectedScopeOption = SCOPE_OPTIONS.find(o => o.value === scope)!
  const needsScopeId = selectedScopeOption.needsScopeId

  const scopeIdLabel: Record<TargetScope, string> = {
    company:    '',
    branch:     'الفرع',
    department: 'القسم',
    individual: 'الموظف',
  }

  // ── Handlers ────────────────────────────────────────────────
  const handleScopeChange = (s: TargetScope) => {
    setScope(s)
    setScopeId('')   // reset when scope changes
  }

  const handlePeriodChange = (p: TargetPeriod) => {
    setPeriod(p)
    if (p !== 'custom') {
      const { start, end } = getDefaultDates(p)
      setPeriodStart(start)
      setPeriodEnd(end)
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!typeId)        { toast.error('اختر نوع الهدف'); return }
    if (!name.trim())   { toast.error('أدخل اسم الهدف'); return }
    if (!targetValue)   { toast.error('أدخل القيمة المستهدفة'); return }
    if (!periodStart || !periodEnd) { toast.error('اختر فترة الهدف'); return }
    // scopeId مطلوب إذا كان النطاق ليس company
    if (needsScopeId && !scopeId) {
      toast.error(`اختر ${scopeIdLabel[scope]} للهدف`)
      return
    }
    setSaving(true)

    const payload: TargetInput = {
      type_id:       typeId,
      name:          name.trim(),
      scope,
      scope_id:      needsScopeId ? scopeId : null,
      period,
      period_start:  periodStart,
      period_end:    periodEnd,
      target_value:  Number(targetValue),
      min_value:     minValue      ? Number(minValue)      : null,
      stretch_value: stretchValue  ? Number(stretchValue)  : null,
      description:   description   || null,
      notes:         notes         || null,
    }

    createTarget.mutate(payload, {
      onSuccess: (target) => {
        toast.success('تم إنشاء الهدف')
        navigate(`/activities/targets/${target.id}`)
      },
      onError: (err: any) => {
        toast.error(err?.message || 'فشل إنشاء الهدف')
        setSaving(false)
      },
    })
  }

  // ── Scope ID Selector ────────────────────────────────────────
  const renderScopeIdSelector = () => {
    if (!needsScopeId) return null

    if (scope === 'branch') {
      return (
        <div className="form-group">
          <label className="form-label">
            الفرع <span className="form-required">*</span>
          </label>
          <select
            className="form-select"
            value={scopeId}
            onChange={e => setScopeId(e.target.value)}
            required
          >
            <option value="">-- اختر الفرع --</option>
            {branches.map((b: any) => (
              <option key={b.id} value={b.id}>{b.name}</option>
            ))}
          </select>
        </div>
      )
    }

    if (scope === 'department') {
      return (
        <div className="form-group">
          <label className="form-label">
            القسم <span className="form-required">*</span>
          </label>
          <select
            className="form-select"
            value={scopeId}
            onChange={e => setScopeId(e.target.value)}
            required
          >
            <option value="">-- اختر القسم --</option>
            {departments.map((d: any) => (
              <option key={d.id} value={d.id}>{d.name}</option>
            ))}
          </select>
        </div>
      )
    }

    if (scope === 'individual') {
      return (
        <div className="form-group">
          <label className="form-label">
            الموظف <span className="form-required">*</span>
          </label>
          <select
            className="form-select"
            value={scopeId}
            onChange={e => setScopeId(e.target.value)}
            required
          >
            <option value="">-- اختر الموظف --</option>
            {employees.map((emp: any) => (
              <option key={emp.id} value={emp.id}>
                {emp.full_name}
                {emp.employee_number ? ` (${emp.employee_number})` : ''}
              </option>
            ))}
          </select>
        </div>
      )
    }

    return null
  }

  // ── Render ──────────────────────────────────────────────────
  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="هدف جديد"
        subtitle="تعيين هدف جديد للأداء"
        breadcrumbs={[
          { label: 'الأهداف', path: '/activities/targets' },
          { label: 'جديد' },
        ]}
      />

      <form className="edara-card target-form" onSubmit={handleSubmit}>

        {/* ── تصنيف الهدف ── */}
        <div className="target-form-section">
          <div className="target-form-section-title">تفاصيل الهدف</div>

          {/* نوع الهدف */}
          <div className="form-group">
            <label className="form-label">نوع الهدف <span className="form-required">*</span></label>
            <select className="form-select" value={typeId} onChange={e => setTypeId(e.target.value)} required>
              <option value="">-- اختر نوع الهدف --</option>
              {targetTypes.map((t: any) => (
                <option key={t.id} value={t.id}>{t.name}</option>
              ))}
            </select>
          </div>

          {/* اسم الهدف */}
          <div className="form-group">
            <label className="form-label">اسم الهدف <span className="form-required">*</span></label>
            <input
              className="form-input"
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="مثال: هدف مبيعات أبريل 2026"
              required
            />
          </div>
        </div>

        {/* ── النطاق ── */}
        <div className="target-form-section">
          <div className="target-form-section-title">نطاق الهدف</div>
          <div className="form-group">
            <label className="form-label">المستوى <span className="form-required">*</span></label>
            <div className="target-scope-grid">
              {SCOPE_OPTIONS.map(o => (
                <button
                  key={o.value}
                  type="button"
                  className={`target-scope-btn${scope === o.value ? ' target-scope-btn--active' : ''}`}
                  onClick={() => handleScopeChange(o.value)}
                >
                  {o.label}
                </button>
              ))}
            </div>
          </div>

          {/* ── Scope ID Selector يظهر فوراً إذا لزم ── */}
          {renderScopeIdSelector()}
        </div>

        {/* ── الفترة ── */}
        <div className="target-form-section">
          <div className="target-form-section-title">الفترة الزمنية</div>
          <div className="form-group">
            <label className="form-label">نوع الفترة <span className="form-required">*</span></label>
            <select className="form-select" value={period} onChange={e => handlePeriodChange(e.target.value as TargetPeriod)} required>
              {PERIOD_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          </div>

          <div className="target-form-dates">
            <div className="form-group">
              <label className="form-label">من <span className="form-required">*</span></label>
              <input
                type="date"
                className="form-input"
                value={periodStart}
                onChange={e => setPeriodStart(e.target.value)}
                required
              />
            </div>
            <div className="form-group">
              <label className="form-label">إلى <span className="form-required">*</span></label>
              <input
                type="date"
                className="form-input"
                value={periodEnd}
                onChange={e => setPeriodEnd(e.target.value)}
                required
              />
            </div>
          </div>
        </div>

        {/* ── القيم ── */}
        <div className="target-form-section">
          <div className="target-form-section-title">القيم المستهدفة</div>
          <div className="target-form-values">
            <div className="form-group">
              <label className="form-label">القيمة المستهدفة <span className="form-required">*</span></label>
              <input
                type="number"
                className="form-input"
                value={targetValue}
                onChange={e => setTargetValue(e.target.value)}
                placeholder="0"
                min="0"
                step="any"
                required
              />
            </div>
            <div className="form-group">
              <label className="form-label">الحد الأدنى <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>(اختياري)</span></label>
              <input
                type="number"
                className="form-input"
                value={minValue}
                onChange={e => setMinValue(e.target.value)}
                placeholder="—"
                min="0"
                step="any"
              />
            </div>
            <div className="form-group">
              <label className="form-label">هدف التمدد <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>(اختياري)</span></label>
              <input
                type="number"
                className="form-input"
                value={stretchValue}
                onChange={e => setStretchValue(e.target.value)}
                placeholder="—"
                min="0"
                step="any"
              />
            </div>
          </div>
        </div>

        {/* ── ملاحظات ── */}
        <div className="target-form-section">
          <div className="target-form-section-title">تفاصيل إضافية</div>
          <div className="form-group">
            <label className="form-label">الوصف</label>
            <textarea
              className="form-textarea"
              rows={2}
              value={description}
              onChange={e => setDescription(e.target.value)}
              placeholder="وصف مختصر للهدف..."
            />
          </div>
          <div className="form-group">
            <label className="form-label">ملاحظات</label>
            <textarea
              className="form-textarea"
              rows={2}
              value={notes}
              onChange={e => setNotes(e.target.value)}
              placeholder="ملاحظات إضافية..."
            />
          </div>
        </div>

        {/* ── Summary Preview ── */}
        {typeId && name && targetValue && (
          <div className="target-form-preview">
            <span className="target-form-preview-icon">🎯</span>
            <span>
              <strong>{name}</strong>
              {' · '}
              {SCOPE_OPTIONS.find(o => o.value === scope)?.label}
              {needsScopeId && scopeId && ' (محدد)'}
              {' · '}
              {targetValue} وحدة
            </span>
          </div>
        )}

        <div className="target-form-actions">
          <Button
            type="button"
            variant="secondary"
            onClick={() => navigate('/activities/targets')}
            disabled={saving}
          >
            إلغاء
          </Button>
          <Button
            type="submit"
            disabled={saving || (needsScopeId && !scopeId)}
          >
            {saving ? 'جاري الإنشاء...' : 'إنشاء الهدف'}
          </Button>
        </div>
      </form>

      <style>{`
        .target-form {
          max-width: 680px;
          margin: 0 auto;
          padding: var(--space-4);
          display: flex;
          flex-direction: column;
          gap: var(--space-2);
        }
        .target-form-section {
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg);
          padding: var(--space-4);
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
        }
        .target-form-section-title {
          font-size: var(--text-sm);
          font-weight: 700;
          color: var(--text-secondary);
          margin-bottom: var(--space-1);
          padding-bottom: var(--space-2);
          border-bottom: 1px solid var(--border-primary);
          text-transform: uppercase;
          letter-spacing: 0.04em;
        }
        .target-scope-grid {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: var(--space-2);
        }
        .target-scope-btn {
          padding: var(--space-2) var(--space-1);
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-md);
          background: var(--bg-surface);
          color: var(--text-secondary);
          font-size: var(--text-sm);
          cursor: pointer;
          transition: all var(--transition-fast);
          font-family: inherit;
          font-weight: 500;
        }
        .target-scope-btn:hover {
          border-color: var(--color-primary);
          color: var(--color-primary);
          background: var(--color-primary-light);
        }
        .target-scope-btn--active {
          border-color: var(--color-primary);
          background: var(--color-primary);
          color: #fff;
          font-weight: 700;
        }
        .target-form-dates,
        .target-form-values {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
          gap: var(--space-3);
        }
        .target-form-preview {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-3);
          background: var(--color-primary-light);
          border: 1px solid var(--color-primary);
          border-radius: var(--radius-md);
          font-size: var(--text-sm);
          color: var(--color-primary);
          animation: fadeIn 0.2s ease;
        }
        .target-form-preview-icon { font-size: 20px; }
        .target-form-actions {
          display: flex;
          gap: var(--space-3);
          justify-content: flex-end;
          padding-top: var(--space-3);
          border-top: 1px solid var(--border-primary);
        }
        @keyframes fadeIn { from { opacity:0; transform:translateY(4px) } to { opacity:1; transform:translateY(0) } }
        @media (max-width: 600px) {
          .target-form { padding: var(--space-3); }
          .target-scope-grid { grid-template-columns: repeat(2, 1fr); }
          .target-form-dates,
          .target-form-values { grid-template-columns: 1fr; }
        }
      `}</style>
    </div>
  )
}
