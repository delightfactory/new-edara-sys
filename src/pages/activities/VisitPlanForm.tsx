/**
 * VisitPlanForm — إنشاء خطة زيارات يومية
 * يُستدعى من /activities/visit-plans/new
 */
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { useCreateVisitPlan, useCurrentEmployee } from '@/hooks/useQueryHooks'
import type { VisitPlanInput } from '@/lib/types/activities'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'

export default function VisitPlanForm() {
  const navigate    = useNavigate()
  const createPlan  = useCreateVisitPlan()
  const { data: employee } = useCurrentEmployee()

  const [planDate,  setPlanDate]  = useState(() => new Date().toISOString().slice(0, 10))
  const [notes,     setNotes]     = useState('')
  const [saving,    setSaving]    = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!planDate) { toast.error('اختر تاريخ الخطة'); return }
    if (!employee?.id) { toast.error('لا يوجد سجل موظف مرتبط بهذا الحساب'); return }
    setSaving(true)

    const payload: VisitPlanInput = {
      employee_id: employee.id,
      plan_date: planDate,
      notes:     notes || null,
    }

    createPlan.mutate(payload, {
      onSuccess: (plan) => {
        toast.success('تم إنشاء خطة الزيارات')
        navigate(`/activities/visit-plans/${plan.id}`)
      },
      onError: (e: any) => {
        toast.error(e?.message || 'فشل إنشاء الخطة')
        setSaving(false)
      },
    })
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="خطة زيارات جديدة"
        subtitle="إنشاء خطة زيارات يومية"
        breadcrumbs={[
          { label: 'خطط الزيارات', path: '/activities/visit-plans' },
          { label: 'جديد' },
        ]}
      />

      <form className="edara-card plan-form" onSubmit={handleSubmit}>
        <div className="form-group">
          <label className="form-label">تاريخ الخطة <span className="form-required">*</span></label>
          <input
            type="date"
            className="form-input"
            value={planDate}
            onChange={e => setPlanDate(e.target.value)}
            required
          />
        </div>

        <div className="form-group">
          <label className="form-label">ملاحظات</label>
          <textarea
            className="form-textarea"
            rows={3}
            value={notes}
            onChange={e => setNotes(e.target.value)}
            placeholder="ملاحظات على خطة الزيارات..."
          />
        </div>

        <p className="plan-form-hint">
          💡 بعد الإنشاء ستتمكن من إضافة العملاء والبنود التفصيلية من صفحة الخطة
        </p>

        <div className="plan-form-actions">
          <Button type="button" variant="secondary" onClick={() => navigate('/activities/visit-plans')} disabled={saving}>
            إلغاء
          </Button>
          <Button type="submit" disabled={saving}>
            {saving ? 'جاري الإنشاء...' : 'إنشاء الخطة'}
          </Button>
        </div>
      </form>

      <style>{`
        .plan-form {
          max-width: 540px;
          margin: 0 auto;
          padding: var(--space-6);
          display: flex;
          flex-direction: column;
          gap: var(--space-4);
        }
        .plan-form-hint {
          margin: 0;
          padding: var(--space-3);
          background: var(--bg-surface-2);
          border-radius: var(--radius-md);
          font-size: var(--text-sm);
          color: var(--text-muted);
          line-height: 1.6;
        }
        .plan-form-actions {
          display: flex;
          gap: var(--space-3);
          justify-content: flex-end;
          padding-top: var(--space-2);
          border-top: 1px solid var(--border-primary);
        }
        @media (max-width: 480px) {
          .plan-form { padding: var(--space-4); }
        }
      `}</style>
    </div>
  )
}
