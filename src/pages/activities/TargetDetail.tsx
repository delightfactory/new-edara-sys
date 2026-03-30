import { useParams, useNavigate } from 'react-router-dom'
import { useTarget, useAdjustTarget } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { toast } from 'sonner'
import { useState } from 'react'
import { Edit2 } from 'lucide-react'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import TargetProgressWidget from '@/components/shared/TargetProgressWidget'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import { supabase } from '@/lib/supabase/client'

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG', { day: 'numeric', month: 'long', year: 'numeric' })
}
function fmtNum(n: number) {
  return n.toLocaleString('ar-EG', { maximumFractionDigits: 2 })
}

const SCOPE_AR: Record<string, string> = {
  company: 'الشركة', branch: 'الفرع', department: 'القسم', individual: 'فرد',
}
const PERIOD_AR: Record<string, string> = {
  monthly: 'شهري', quarterly: 'ربع سنوي', yearly: 'سنوي', custom: 'مخصص',
}

export default function TargetDetail() {
  const { id }     = useParams<{ id: string }>()
  const navigate   = useNavigate()
  const can        = useAuthStore(s => s.can)
  const [adjustOpen, setAdjustOpen] = useState(false)
  const [adjustField, setAdjustField] = useState('target_value')
  const [adjustValue, setAdjustValue] = useState('')
  const [adjustReason, setAdjustReason] = useState('')
  const [processing, setProcessing] = useState(false)

  const { data: target, isLoading: targetLoading } = useTarget(id)

  const adjustTarget = useAdjustTarget()
  const canAdjust    = can(PERMISSIONS.TARGETS_ASSIGN)

  const progress = (target as any)?.progress_history ?? []
  const latestProgress = progress[0] ?? null

  const handleAdjust = async () => {
    if (!id || !adjustValue || !adjustReason.trim()) return
    setProcessing(true)
    try {
      const { data: userData } = await supabase.auth.getUser()
      const userId = userData.user?.id ?? ''
      adjustTarget.mutate(
        {
          p_target_id: id,
          p_field:     adjustField as any,
          p_new_value: adjustValue,
          p_reason:    adjustReason,
          p_user_id:   userId,
        },
        {
          onSuccess: () => { toast.success('تم تعديل الهدف'); setAdjustOpen(false); setAdjustValue(''); setAdjustReason('') },
          onError:   (e: any) => toast.error(e?.message || 'فشل التعديل'),
          onSettled: () => setProcessing(false),
        }
      )
    } catch {
      toast.error('فشل جلب بيانات المستخدم')
      setProcessing(false)
    }
  }

  if (targetLoading) {
    return (
      <div className="page-container animate-enter">
        <div className="edara-card" style={{ padding: 'var(--space-6)' }}>
          {[1, 2, 3, 4].map(i => (
            <div key={i} className="skeleton" style={{ height: 20, marginBottom: 'var(--space-3)', width: `${70 - i * 10}%` }} />
          ))}
        </div>
      </div>
    )
  }

  if (!target) {
    return (
      <div className="page-container animate-enter">
        <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
          <p className="empty-state-title">لم يتم العثور على الهدف</p>
          <Button variant="secondary" onClick={() => navigate('/activities/targets')}>العودة</Button>
        </div>
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title={target.name}
        subtitle={`${target.target_type?.name ?? target.type_code} • ${SCOPE_AR[target.scope] ?? target.scope}`}
        breadcrumbs={[
          { label: 'الأهداف', path: '/activities/targets' },
          { label: target.name },
        ]}
        actions={canAdjust ? (
          <Button icon={<Edit2 size={16} />} variant="secondary" onClick={() => setAdjustOpen(true)}>
            تعديل الهدف
          </Button>
        ) : undefined}
      />

      {/* Progress Widget */}
      <TargetProgressWidget
        target={target}
        progress={latestProgress}
      />

      {/* Details Card */}
      <div className="edara-card td-card">
        <h3 className="td-section-title">معلومات الهدف</h3>
        <div className="td-grid">
          <div className="td-item">
            <div className="td-label">القيمة المستهدفة</div>
            <div className="td-value td-value--primary">{fmtNum(target.target_value)}</div>
          </div>
          {target.min_value != null && (
            <div className="td-item">
              <div className="td-label">الحد الأدنى</div>
              <div className="td-value">{fmtNum(target.min_value)}</div>
            </div>
          )}
          {target.stretch_value != null && (
            <div className="td-item">
              <div className="td-label">الهدف التمدد</div>
              <div className="td-value" style={{ color: 'var(--color-primary)' }}>{fmtNum(target.stretch_value)}</div>
            </div>
          )}
          <div className="td-item">
            <div className="td-label">الفترة</div>
            <div className="td-value">{PERIOD_AR[target.period] ?? target.period}</div>
          </div>
          <div className="td-item">
            <div className="td-label">من</div>
            <div className="td-value">{fmtDate(target.period_start)}</div>
          </div>
          <div className="td-item">
            <div className="td-label">إلى</div>
            <div className="td-value">{fmtDate(target.period_end)}</div>
          </div>
          <div className="td-item">
            <div className="td-label">الحالة</div>
            <div className="td-value">
              {target.is_paused ? (
                <span style={{ color: 'var(--color-warning)', fontWeight: 600 }}>موقوف</span>
              ) : target.is_active ? (
                <span style={{ color: 'var(--color-success)', fontWeight: 600 }}>نشط</span>
              ) : (
                <span style={{ color: 'var(--text-muted)' }}>غير نشط</span>
              )}
            </div>
          </div>
          {latestProgress?.trend && (
            <div className="td-item">
              <div className="td-label">الاتجاه</div>
              <div className="td-value" style={{ fontWeight: 600, color:
                latestProgress.trend === 'achieved' || latestProgress.trend === 'exceeded' ? 'var(--color-success)' :
                latestProgress.trend === 'on_track' ? 'var(--color-primary)' :
                latestProgress.trend === 'at_risk'  ? 'var(--color-warning)' :
                'var(--color-danger)'
              }}>
                {{
                  on_track:  '→ على المسار',
                  at_risk:   '↘ في خطر',
                  behind:    '↓ متأخر',
                  achieved:  '✓ محقق',
                  exceeded:  '↑ تجاوز الهدف',
                }[latestProgress.trend as string] ?? latestProgress.trend}
              </div>
            </div>
          )}
        </div>

        {target.description && (
          <div style={{ marginTop: 'var(--space-4)', paddingTop: 'var(--space-4)', borderTop: '1px solid var(--border-primary)' }}>
            <div className="td-label" style={{ marginBottom: 'var(--space-2)' }}>الوصف</div>
            <p style={{ margin: 0, fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', lineHeight: 1.7 }}>
              {target.description}
            </p>
          </div>
        )}
        {target.notes && (
          <div style={{ marginTop: 'var(--space-3)' }}>
            <div className="td-label" style={{ marginBottom: 'var(--space-2)' }}>ملاحظات</div>
            <p style={{ margin: 0, fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', lineHeight: 1.7 }}>
              {target.notes}
            </p>
          </div>
        )}
      </div>

      {/* Adjust Modal */}
      <ResponsiveModal
        open={adjustOpen}
        onClose={() => setAdjustOpen(false)}
        title="تعديل قيمة الهدف"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => setAdjustOpen(false)} disabled={processing}>إلغاء</Button>
          <Button onClick={handleAdjust} disabled={processing || !adjustValue || !adjustReason.trim()}>
            {processing ? 'جاري الحفظ...' : 'حفظ التعديل'}
          </Button>
        </>}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div className="form-group">
            <label className="form-label">الحقل المراد تعديله</label>
            <select
              className="form-select"
              value={adjustField}
              onChange={e => setAdjustField(e.target.value as typeof adjustField)}
            >
              <option value="target_value">القيمة المستهدفة</option>
              <option value="min_value">الحد الأدنى</option>
              <option value="stretch_value">الهدف التمدد</option>
            </select>
          </div>
          <div className="form-group">
            <label className="form-label">القيمة الجديدة <span className="form-required">*</span></label>
            <input
              type="number"
              className="form-input"
              value={adjustValue}
              onChange={e => setAdjustValue(e.target.value)}
              placeholder="أدخل القيمة..."
            />
          </div>
          <div className="form-group">
            <label className="form-label">سبب التعديل <span className="form-required">*</span></label>
            <textarea
              className="form-textarea"
              rows={2}
              value={adjustReason}
              onChange={e => setAdjustReason(e.target.value)}
              placeholder="اذكر سبب التعديل لأغراض التدقيق..."
            />
          </div>
        </div>
      </ResponsiveModal>

      <style>{`
        .td-card { padding: var(--space-5); margin-top: var(--space-4); }
        .td-section-title {
          font-size: var(--text-base);
          font-weight: 700;
          color: var(--text-primary);
          margin: 0 0 var(--space-4);
          padding-bottom: var(--space-3);
          border-bottom: 1px solid var(--border-primary);
        }
        .td-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
          gap: var(--space-4);
        }
        .td-label {
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-bottom: var(--space-1);
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
        .td-value {
          font-size: var(--text-sm);
          color: var(--text-primary);
          font-weight: 500;
        }
        .td-value--primary {
          font-size: var(--text-lg);
          font-weight: 700;
          color: var(--color-primary);
          font-variant-numeric: tabular-nums;
        }
      `}</style>
    </div>
  )
}
