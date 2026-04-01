/**
 * PlanTemplatesPage — Wave A Final Fix
 *
 * الحل المعتمد: "Save as Template"
 * - PlanTemplatesPage = إدارة metadata فقط (اسم / تكرار / تفعيل / حذف)
 * - لا يُسمح بإنشاء template فارغة من هنا
 * - الإنشاء الحقيقي يكون من VisitPlanDetail / CallPlanDetail عبر زر "حفظ كقالب"
 * - Admin mode: يرى active + inactive
 */
import { useState } from 'react'
import { toast } from 'sonner'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import {
  useVisitPlanTemplatesAll,
  useCallPlanTemplatesAll,
  useUpdateVisitPlanTemplateMutation,
  useDeleteVisitPlanTemplateMutation,
  useUpdateCallPlanTemplateMutation,
  useDeleteCallPlanTemplateMutation,
} from '@/hooks/useQueryHooks'
import { useNavigate } from 'react-router-dom'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import { Trash2, Edit2, MapPin, Phone, LayoutTemplate, ArrowLeft, EyeOff } from 'lucide-react'
import type { VisitPlanTemplate, CallPlanTemplate } from '@/lib/types/activities'
import type { PlanTemplateInput } from '@/lib/services/activities'

type PlanKind = 'visit' | 'call'

const RECURRENCE_OPTIONS = [
  { value: 'none',    label: 'بدون تكرار' },
  { value: 'daily',   label: 'يومي' },
  { value: 'weekly',  label: 'أسبوعي' },
  { value: 'monthly', label: 'شهري' },
]

export default function PlanTemplatesPage() {
  const can      = useAuthStore(s => s.can)
  const navigate = useNavigate()
  const canManage = can(PERMISSIONS.VISIT_PLANS_CREATE) || can(PERMISSIONS.CALL_PLANS_CREATE)

  const [activeTab, setActiveTab] = useState<PlanKind>('visit')

  // Admin mode — includeInactive via *All hooks
  const { data: visitTemplates = [], isLoading: loadingVisit } = useVisitPlanTemplatesAll()
  const { data: callTemplates  = [], isLoading: loadingCall  } = useCallPlanTemplatesAll()

  const updateVisitTmpl  = useUpdateVisitPlanTemplateMutation()
  const deleteVisitTmpl  = useDeleteVisitPlanTemplateMutation()
  const updateCallTmpl   = useUpdateCallPlanTemplateMutation()
  const deleteCallTmpl   = useDeleteCallPlanTemplateMutation()

  // Edit-metadata modal (no item management — templates are created from plan details)
  const [showModal, setShowModal]   = useState(false)
  const [editingId, setEditingId]   = useState<string | null>(null)
  const [form, setForm]             = useState<Partial<PlanTemplateInput>>({})
  const [saving, setSaving]         = useState(false)

  function openEdit(t: VisitPlanTemplate | CallPlanTemplate) {
    setEditingId(t.id)
    setForm({ name: t.name, recurrence: t.recurrence, is_active: t.is_active })
    setShowModal(true)
  }

  async function handleSave() {
    if (!form.name?.trim()) { toast.error('اسم القالب مطلوب'); return }
    if (!editingId) return
    setSaving(true)
    try {
      if (activeTab === 'visit') {
        await updateVisitTmpl.mutateAsync({ id: editingId, input: form as PlanTemplateInput })
      } else {
        await updateCallTmpl.mutateAsync({ id: editingId, input: form as PlanTemplateInput })
      }
      toast.success('تم تحديث القالب')
      setShowModal(false)
    } catch (e: any) {
      toast.error(e?.message || 'فشل الحفظ')
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(id: string, name: string) {
    if (!confirm(`حذف قالب "${name}"؟`)) return
    try {
      if (activeTab === 'visit') {
        await deleteVisitTmpl.mutateAsync(id)
      } else {
        await deleteCallTmpl.mutateAsync(id)
      }
      toast.success('تم حذف القالب')
    } catch (e: any) {
      toast.error(e?.message || 'فشل الحذف')
    }
  }

  const templates  = activeTab === 'visit' ? visitTemplates : callTemplates
  const isLoading  = activeTab === 'visit' ? loadingVisit : loadingCall
  const planPath   = activeTab === 'visit' ? '/activities/visit-plans' : '/activities/call-plans'
  const planLabel  = activeTab === 'visit' ? 'خطة الزيارات' : 'خطة المكالمات'

  if (!canManage) {
    return (
      <div className="page-container animate-enter">
        <div className="empty-state p-8">
          <p className="empty-state-title">ليس لديك صلاحية</p>
        </div>
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="قوالب الخطط"
        subtitle="إدارة قوالب خطط الزيارات والمكالمات"
        breadcrumbs={[
          { label: 'الأنشطة', path: '/activities' },
          { label: 'القوالب' },
        ]}
      />

      {/* How-to Banner */}
      <div className="pt-howto-banner">
        <LayoutTemplate size={18} style={{ flexShrink: 0 }} />
        <div className="pt-howto-text">
          <strong>كيف تُنشئ قالب جديد؟</strong>
          <span>افتح خطة {planLabel} جاهزة، ثم اضغط زر <strong>"حفظ كقالب"</strong> — يتم حفظ الخطة ببنودها مباشرة.</span>
        </div>
        <Button
          variant="secondary" size="sm"
          icon={<ArrowLeft size={14} />}
          onClick={() => navigate(planPath)}
        >
          الذهاب لـ{planLabel === 'خطة الزيارات' ? 'خطط الزيارات' : 'خطط المكالمات'}
        </Button>
      </div>

      {/* Tab switcher */}
      <div className="pt-tabs">
        <button
          className={`pt-tab${activeTab === 'visit' ? ' pt-tab--active' : ''}`}
          onClick={() => setActiveTab('visit')}
        >
          <MapPin size={15} /> قوالب الزيارات
          <span className="pt-tab-count">{visitTemplates.length}</span>
        </button>
        <button
          className={`pt-tab${activeTab === 'call' ? ' pt-tab--active' : ''}`}
          onClick={() => setActiveTab('call')}
        >
          <Phone size={15} /> قوالب المكالمات
          <span className="pt-tab-count">{callTemplates.length}</span>
        </button>
      </div>

      {isLoading ? (
        <div className="edara-card p-6">
          {[1,2,3].map(i => <div key={i} className="skeleton h-14 mb-3 rounded-lg" />)}
        </div>
      ) : templates.length === 0 ? (
        <div className="empty-state p-10">
          <LayoutTemplate size={40} className="text-muted mx-auto mb-3" />
          <p className="empty-state-title">
            لا توجد قوالب {activeTab === 'visit' ? 'زيارات' : 'مكالمات'} بعد
          </p>
          <p className="empty-state-desc">
            افتح {planLabel} جاهزة واضغط "حفظ كقالب" لإنشاء أول قالب بببنود فعلية
          </p>
          <Button
            variant="secondary"
            icon={<ArrowLeft size={14} />}
            onClick={() => navigate(planPath)}
            className="mt-4"
          >
            الذهاب لـ{planLabel === 'خطة الزيارات' ? 'خطط الزيارات' : 'خطط المكالمات'}
          </Button>
        </div>
      ) : (
        <div className="pt-list">
          {(templates as any[]).map((t) => (
            <div key={t.id} className={`edara-card pt-card${!t.is_active ? ' pt-card--inactive' : ''}`}>
              <div className="pt-card-icon" style={{ opacity: t.is_active ? 1 : 0.4 }}>
                {activeTab === 'visit' ? <MapPin size={15} /> : <Phone size={15} />}
              </div>
              <div className="pt-card-body">
                <div className="pt-card-name" style={!t.is_active ? { opacity: 0.6 } : undefined}>{t.name}</div>
                <div className="pt-card-meta">
                  {RECURRENCE_OPTIONS.find(r => r.value === t.recurrence)?.label ?? 'بدون تكرار'}
                  {t.items?.length > 0 && ` · ${t.items.length} ${activeTab === 'visit' ? 'عميل' : 'مكالمة'}`}
                </div>
              </div>
              {!t.is_active && (
                <span className="pt-badge-inactive" title="معطّل — لن يظهر في نماذج الإنشاء">
                  <EyeOff size={10} style={{ display: 'inline', verticalAlign: 'middle' }} /> معطّل
                </span>
              )}
              <div className="pt-card-actions">
                <Button variant="ghost" size="sm" icon={<Edit2 size={14} />} onClick={() => openEdit(t)} />
                <Button
                  variant="ghost" size="sm" icon={<Trash2 size={14} />}
                  className="text-danger"
                  onClick={() => handleDelete(t.id, t.name)}
                />
              </div>
            </div>
          ))}
        </div>
      )}

      {/* ── Edit Metadata Modal ───────────────────────────── */}
      <ResponsiveModal
        open={showModal}
        onClose={() => setShowModal(false)}
        title="تعديل بيانات القالب"
      >
        <div className="flex flex-col gap-4">
          <div className="form-group">
            <label className="form-label">اسم القالب <span className="form-required">*</span></label>
            <input
              className="form-input"
              value={form.name ?? ''}
              onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
              autoFocus
            />
          </div>
          <div className="form-group">
            <label className="form-label">نوع التكرار</label>
            <select
              className="form-select"
              value={form.recurrence ?? 'none'}
              onChange={e => setForm(f => ({ ...f, recurrence: e.target.value as any }))}
            >
              {RECURRENCE_OPTIONS.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
            </select>
          </div>
          <label className="flex items-center gap-2 cursor-pointer text-sm">
            <input
              type="checkbox"
              checked={form.is_active ?? true}
              onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))}
            />
            القالب مفعّل (يظهر في نموذج إنشاء الخطة)
          </label>
          <div className="flex gap-3 justify-end mt-2">
            <Button variant="secondary" onClick={() => setShowModal(false)}>إلغاء</Button>
            <Button onClick={handleSave} disabled={saving}>
              {saving ? 'جاري الحفظ...' : 'حفظ'}
            </Button>
          </div>
        </div>
      </ResponsiveModal>

      <style>{`
        .pt-howto-banner {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          background: var(--color-primary-light);
          border: 1px solid var(--color-primary);
          border-radius: var(--radius-lg);
          padding: var(--space-3) var(--space-4);
          margin-bottom: var(--space-4);
          color: var(--color-primary-dark, var(--color-primary));
        }
        .pt-howto-text {
          flex: 1;
          font-size: var(--text-sm);
          display: flex;
          flex-direction: column;
          gap: 2px;
        }
        .pt-howto-text strong { font-weight: 700; }
        .pt-howto-text span { opacity: 0.85; }

        .pt-tabs { display: flex; gap: var(--space-2); margin-bottom: var(--space-4); border-bottom: 2px solid var(--border-primary); }
        .pt-tab { display: flex; align-items: center; gap: 6px; padding: var(--space-2) var(--space-4); border: none; background: none; font-size: var(--text-sm); font-weight: 500; color: var(--text-muted); cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -2px; font-family: inherit; transition: all var(--transition-fast); }
        .pt-tab:hover { color: var(--text-primary); }
        .pt-tab--active { color: var(--color-primary); border-bottom-color: var(--color-primary); }
        .pt-tab-count { background: var(--color-primary-light); color: var(--color-primary); border-radius: var(--radius-full); padding: 1px 7px; font-size: 11px; font-weight: 700; }

        .pt-list { display: flex; flex-direction: column; gap: var(--space-2); }
        .pt-card { display: flex; align-items: center; gap: var(--space-3); padding: var(--space-3) var(--space-4); }
        .pt-card--inactive { opacity: 0.8; border-style: dashed; }
        .pt-card-icon { width: 36px; height: 36px; display: flex; align-items: center; justify-content: center; background: var(--color-primary-light); color: var(--color-primary); border-radius: var(--radius-lg); flex-shrink: 0; }
        .pt-card-body { flex: 1; }
        .pt-card-name { font-weight: 600; font-size: var(--text-sm); color: var(--text-primary); }
        .pt-card-meta { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }
        .pt-badge-inactive { font-size: 11px; color: var(--text-muted); background: var(--border-primary); padding: 2px 8px; border-radius: var(--radius-full); display: flex; align-items: center; gap: 4px; }
        .pt-card-actions { display: flex; gap: var(--space-1); }
      `}</style>
    </div>
  )
}
