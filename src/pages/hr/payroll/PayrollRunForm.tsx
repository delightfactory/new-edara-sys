import { useState, useEffect } from 'react'
import { Calculator, ChevronDown, AlertCircle } from 'lucide-react'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'
import {
  useHRPayrollPeriods,
  useCreatePayrollRun,
  useCalculatePayrollRun,
} from '@/hooks/useQueryHooks'
import { useBranches } from '@/hooks/useQueryHooks'
import type { HRPayrollRun } from '@/lib/types/hr'
import { toast } from 'sonner'

interface Props {
  open:    boolean
  onClose: () => void
  /** يُستدعى عند اكتمال الحساب لعرض تفاصيل المسير */
  onSuccess?: (run: HRPayrollRun) => void
}

// ─── مراحل النموذج ────────────────────────────────────
type Step = 'setup' | 'calculating'

export default function PayrollRunForm({ open, onClose, onSuccess }: Props) {
  const [step, setStep]       = useState<Step>('setup')
  const [periodId, setPeriodId] = useState('')
  const [branchId, setBranchId] = useState('')
  const [notes,    setNotes]    = useState('')
  const [progress, setProgress] = useState({ done: 0, total: 0 })
  // UX-07: تتبع الموظفين الذين فشل حساب رواتبهم
  const [failedEmps, setFailedEmps] = useState<{ name: string; error: string }[]>([])

  // البيانات
  const { data: periods = [] } = useHRPayrollPeriods()
  const { data: branches = [] } = useBranches()

  // Mutations
  const createRun    = useCreatePayrollRun()
  const calculateRun = useCalculatePayrollRun()
  const isWorking    = createRun.isPending || calculateRun.isPending

  // إعادة ضبط عند الإغلاق
  useEffect(() => {
    if (!open) {
      setStep('setup'); setPeriodId(''); setBranchId(''); setNotes('')
      setProgress({ done: 0, total: 0 })
      setFailedEmps([])
    }
  }, [open])

  const handleSubmit = async () => {
    if (!periodId) { toast.error('يرجى اختيار فترة الراتب'); return }

    try {
      // 1. إنشاء سجل المسير (draft)
      const run = await createRun.mutateAsync({
        period_id: periodId,
        branch_id: branchId || null,
        notes:     notes.trim() || null,
      })

      // 2. الانتقال لمرحلة الحساب
      setStep('calculating')
      setProgress({ done: 0, total: 0 })
      setFailedEmps([])

      // 3. حساب الرواتب لكل الموظفين
      const result = await calculateRun.mutateAsync({
        runId: run.id,
        onProgress: (done, total) => setProgress({ done, total }),
      })

      toast.success(
        `✅ تم حساب ${result.calculated} موظف بنجاح` +
        (result.skipped > 0 ? ` (${result.skipped} تم تخطيهم)` : '')
      )
      onSuccess?.(run)
      onClose()
    } catch (err) {
      setStep('setup')
      toast.error(`فشل الحساب: ${err instanceof Error ? err.message : String(err)}`)
    }
  }

  const progressPct = progress.total > 0
    ? Math.round((progress.done / progress.total) * 100)
    : 0

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      title="مسير رواتب جديد"
      size="sm"
      disableOverlayClose={isWorking}
      footer={
        step === 'setup' ? (
          <div style={{ display: 'flex', gap: 'var(--space-2)', width: '100%' }}>
            <Button variant="secondary" onClick={onClose} style={{ flex: 1 }} disabled={isWorking}>
              إلغاء
            </Button>
            <Button
              onClick={handleSubmit}
              loading={isWorking}
              disabled={!periodId}
              icon={<Calculator size={14} />}
              style={{ flex: 1 }}
            >
              إنشاء وحساب
            </Button>
          </div>
        ) : null
      }
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>

        {step === 'setup' && (
          <>
            {/* فترة الراتب */}
            <div className="form-group">
              <label className="form-label" htmlFor="payroll-period">
                فترة الراتب <span style={{ color: 'var(--color-danger)' }}>*</span>
              </label>
              <div style={{ position: 'relative' }}>
                <select
                  id="payroll-period"
                  className="form-input"
                  value={periodId}
                  onChange={e => setPeriodId(e.target.value)}
                  disabled={isWorking}
                  style={{ paddingLeft: 'var(--space-6)' }}
                >
                  <option value="">اختر الفترة...</option>
                  {periods.map(p => (
                    <option key={p.id} value={p.id}>
                      {p.name} ({p.year}/{String(p.month).padStart(2, '0')})
                    </option>
                  ))}
                </select>
                <ChevronDown size={13} style={{
                  position: 'absolute', left: 'var(--space-2)', top: '50%',
                  transform: 'translateY(-50%)', pointerEvents: 'none',
                  color: 'var(--text-muted)',
                }} />
              </div>
            </div>

            {/* الفرع (اختياري) */}
            <div className="form-group">
              <label className="form-label" htmlFor="payroll-branch">
                الفرع <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>(اختياري — اتركه فارغاً لكل الفروع)</span>
              </label>
              <div style={{ position: 'relative' }}>
                <select
                  id="payroll-branch"
                  className="form-input"
                  value={branchId}
                  onChange={e => setBranchId(e.target.value)}
                  disabled={isWorking}
                  style={{ paddingLeft: 'var(--space-6)' }}
                >
                  <option value="">كل الفروع</option>
                  {branches.map(b => (
                    <option key={b.id} value={b.id}>{b.name}</option>
                  ))}
                </select>
                <ChevronDown size={13} style={{
                  position: 'absolute', left: 'var(--space-2)', top: '50%',
                  transform: 'translateY(-50%)', pointerEvents: 'none',
                  color: 'var(--text-muted)',
                }} />
              </div>
            </div>

            {/* ملاحظات */}
            <div className="form-group">
              <label className="form-label" htmlFor="payroll-notes">ملاحظات</label>
              <textarea
                id="payroll-notes"
                className="form-input"
                rows={2}
                placeholder="أي ملاحظات اختيارية..."
                value={notes}
                onChange={e => setNotes(e.target.value)}
                disabled={isWorking}
                style={{ resize: 'vertical' }}
              />
            </div>

            {/* تنبيه */}
            <div style={{
              display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-start',
              padding: 'var(--space-3)',
              background: 'color-mix(in srgb, var(--color-warning) 6%, transparent)',
              border: '1px solid color-mix(in srgb, var(--color-warning) 20%, transparent)',
              borderRadius: 'var(--radius-md)',
              fontSize: 'var(--text-xs)', color: 'var(--text-secondary)',
            }}>
              <AlertCircle size={12} style={{ color: 'var(--color-warning)', flexShrink: 0, marginTop: 1 }} />
              سيتم جمع بيانات الحضور، الغياب، الجزاءات، السلف، وعمولات المبيعات لكل موظف تلقائياً.
              عملية الحساب قد تستغرق بضع ثوانٍ.
            </div>
          </>
        )}

        {/* ─── مرحلة الحساب ─── */}
        {step === 'calculating' && (
          <div style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center',
            gap: 'var(--space-5)', padding: 'var(--space-6) var(--space-4)',
            textAlign: 'center',
          }}>
            {/* أيقونة دوارة */}
            <div style={{
              width: 60, height: 60,
              borderRadius: '50%',
              border: '3px solid color-mix(in srgb, var(--color-primary) 20%, transparent)',
              borderTop: '3px solid var(--color-primary)',
              animation: 'spin 1s linear infinite',
            }} />

            <div>
              <div style={{ fontWeight: 700, fontSize: 'var(--text-base)', marginBottom: 'var(--space-1)' }}>
                جاري تجميع بيانات الحضور، السلف، والعمولات...
              </div>
              {progress.total > 0 && (
                <div style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)' }}>
                  {progress.done} من {progress.total} موظف
                </div>
              )}
            </div>

            {/* شريط التقدم */}
            <div style={{
              width: '100%', height: 6,
              background: 'var(--bg-surface-2)',
              borderRadius: 99,
              overflow: 'hidden',
            }}>
              <div style={{
                height: '100%',
                width: progress.total > 0 ? `${progressPct}%` : '30%',
                background: 'var(--color-primary)',
                borderRadius: 99,
                transition: 'width 0.3s ease',
                animation: progress.total === 0 ? 'indeterminate 1.5s ease infinite' : 'none',
              }} />
            </div>

            {progress.total > 0 && (
              <div style={{
                fontWeight: 700, fontSize: 'var(--text-lg)',
                color: 'var(--color-primary)',
              }}>
                {progressPct}%
              </div>
            )}

            {/* UX-07: قائمة الموظفين الذين فشل حسابهم */}
            {failedEmps.length > 0 && (
              <div style={{
                width: '100%', textAlign: 'right',
                background: 'color-mix(in srgb, var(--color-danger) 6%, transparent)',
                border: '1px solid color-mix(in srgb, var(--color-danger) 20%, transparent)',
                borderRadius: 'var(--radius-md)',
                padding: 'var(--space-3)',
              }}>
                <div style={{ fontWeight: 600, fontSize: 'var(--text-xs)', color: 'var(--color-danger)', marginBottom: 'var(--space-2)' }}>
                  ⚠ فشل حساب رواتب {failedEmps.length} موظف:
                </div>
                {failedEmps.map((f, i) => (
                  <div key={i} style={{
                    display: 'flex', justifyContent: 'space-between',
                    fontSize: 'var(--text-xs)', padding: '2px 0',
                    borderBottom: '1px solid color-mix(in srgb, var(--color-danger) 15%, transparent)',
                  }}>
                    <span style={{ fontWeight: 600 }}>{f.name}</span>
                    <span style={{ color: 'var(--text-muted)', maxWidth: '60%', overflow: 'hidden', textOverflow: 'ellipsis' }}>{f.error}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>

      <style>{`
        @keyframes spin { to { transform: rotate(360deg); } }
        @keyframes indeterminate {
          0%   { transform: translateX(-100%); width: 40%; }
          100% { transform: translateX(300%);  width: 40%; }
        }
      `}</style>
    </ResponsiveModal>
  )
}
