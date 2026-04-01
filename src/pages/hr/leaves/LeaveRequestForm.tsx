import { useState, useEffect, useRef } from 'react'
import {
  CalendarDays, FileText, AlertCircle, Upload, X,
  CheckCircle2, Clock, Info,
} from 'lucide-react'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'
import {
  useHRLeaveTypes,
  useCreateLeaveRequest,
  useCurrentEmployee,
  useHREmployee,
  useHRLeaveBalances,
} from '@/hooks/useQueryHooks'
import type { HRLeaveRequestInput } from '@/lib/types/hr'
import { supabase } from '@/lib/supabase/client'
import { toast } from 'sonner'

interface Props {
  open: boolean
  onClose: () => void
  employeeId?: string
}

function calcDays(from: string, to: string): number {
  if (!from || !to) return 0
  const diff = Math.round(
    (new Date(to).getTime() - new Date(from).getTime()) / (1000 * 60 * 60 * 24)
  )
  return diff >= 0 ? diff + 1 : 0
}

function fmtDays(n: number): string {
  if (n === 0) return '—'
  if (n === 1) return 'يوم واحد'
  if (n === 2) return 'يومان'
  if (n <= 10) return `${n} أيام`
  return `${n} يوماً`
}

// ── مؤشر الرصيد ────────────────────────────────────────────
function BalanceBar({ employeeId, leaveTypeId, daysRequested }: {
  employeeId: string; leaveTypeId: string; daysRequested: number
}) {
  const { data: balances = [] } = useHRLeaveBalances(employeeId || null, new Date().getFullYear())
  const bal = balances.find(b => b.leave_type_id === leaveTypeId)
  if (!bal) return null

  const pct = Math.min(100, Math.round(((bal.total_days - bal.remaining_days) / bal.total_days) * 100))
  const isOk = bal.remaining_days >= daysRequested
  const barColor = !isOk ? 'var(--color-danger)' : daysRequested > 0 ? 'var(--color-success)' : 'var(--color-primary)'

  return (
    <div className="lf-balance-card">
      <div className="lf-balance-header">
        <span className="lf-balance-label">رصيد الإجازات المتبقي</span>
        <span className="lf-balance-value" style={{ color: barColor }}>
          {bal.remaining_days} يوم
          {daysRequested > 0 && ` (تطلب ${daysRequested})`}
          {daysRequested > 0 && !isOk && ' ⚠ غير كافٍ'}
        </span>
      </div>
      <div className="lf-balance-bar-bg">
        <div
          className="lf-balance-bar-fill"
          style={{ width: `${pct}%`, background: isOk ? 'var(--color-primary)' : 'var(--color-danger)' }}
        />
        {daysRequested > 0 && (
          <div
            className="lf-balance-bar-req"
            style={{
              width: `${Math.min(100, Math.round((daysRequested / bal.total_days) * 100))}%`,
              background: barColor,
            }}
          />
        )}
      </div>
      <div className="lf-balance-legend">
        <span>{bal.used_days} مستخدم</span>
        <span>{bal.total_days} إجمالي</span>
      </div>
    </div>
  )
}

// ══════════════════════════════════════════════
// MAIN COMPONENT
// ══════════════════════════════════════════════
export default function LeaveRequestForm({ open, onClose, employeeId: externalEmpId }: Props) {
  const { data: currentEmployee } = useCurrentEmployee()
  const resolvedEmpId = externalEmpId ?? currentEmployee?.id ?? ''

  // X2: Fetch Context
  const { data: targetEmployee } = useHREmployee(resolvedEmpId || null)
  const employeeGender = targetEmployee?.gender

  const [leaveTypeId, setLeaveTypeId] = useState('')
  const [startDate,   setStartDate]   = useState('')
  const [endDate,     setEndDate]     = useState('')
  const [reason,      setReason]      = useState('')
  const [docFile,     setDocFile]     = useState<File | null>(null)
  const [uploading,   setUploading]   = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const daysCount = calcDays(startDate, endDate)

  useEffect(() => {
    if (endDate && startDate && endDate < startDate) setEndDate(startDate)
  }, [startDate, endDate])

  useEffect(() => {
    if (!open) {
      setLeaveTypeId(''); setStartDate(''); setEndDate(''); setReason(''); setDocFile(null)
    }
  }, [open])

  const { data: leaveTypes = [], isLoading: typesLoading } = useHRLeaveTypes()
  
  // X2: Context-Aware Filtering Model
  const applicableLeaveTypes = leaveTypes.filter(t => {
    // 1- Always allow universal rules
    if (!t.eligible_gender || t.eligible_gender === 'all') return true
    
    // 2- If context is missing, be graceful and do NOT show targeted types
    if (!employeeGender) return false
    
    // 3- Matching rules
    return t.eligible_gender === employeeGender
  })

  const createMutation = useCreateLeaveRequest()

  const selectedType = applicableLeaveTypes.find(t => t.id === leaveTypeId)
  const requiresDoc  = selectedType?.requires_document ?? false

  const handleSubmit = async () => {
    if (!resolvedEmpId) { toast.error('تعذر تحديد الموظف — تأكد من ربط حسابك بسجل موظف'); return }
    if (!leaveTypeId)   { toast.error('يرجى اختيار نوع الإجازة'); return }
    if (!startDate || !endDate) { toast.error('يرجى تحديد تاريخ البداية والنهاية'); return }
    if (daysCount <= 0) { toast.error('تاريخ النهاية يجب أن يكون بعد تاريخ البداية'); return }
    if (!reason.trim()) { toast.error('يرجى كتابة سبب الإجازة'); return }
    if (requiresDoc && !docFile) { toast.error('هذا النوع من الإجازة يتطلب رفع وثيقة داعمة'); return }

    let document_url: string | undefined
    if (docFile) {
      setUploading(true)
      try {
        const ext  = docFile.name.split('.').pop()
        const path = `leave-docs/${resolvedEmpId}/${Date.now()}.${ext}`
        const { error: upErr } = await supabase.storage.from('hr-documents').upload(path, docFile)
        if (upErr) throw upErr
        const { data: urlData } = supabase.storage.from('hr-documents').getPublicUrl(path)
        document_url = urlData.publicUrl
      } catch (e: any) {
        toast.error('فشل رفع الوثيقة: ' + (e.message ?? ''))
        setUploading(false); return
      }
      setUploading(false)
    }

    const input: HRLeaveRequestInput = {
      employee_id:   resolvedEmpId,
      leave_type_id: leaveTypeId,
      start_date:    startDate,
      end_date:      endDate,
      days_count:    daysCount,
      reason:        reason.trim(),
      ...(document_url ? { document_url } : {}),
    }

    try {
      await createMutation.mutateAsync(input)
      toast.success('تم تقديم طلب الإجازة بنجاح')
      onClose()
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err)
      if (msg.includes('insufficient') || msg.includes('رصيد') || msg.includes('balance'))
        toast.error('رصيد الإجازة غير كافٍ للمدة المطلوبة')
      else
        toast.error(`فشل تقديم الطلب: ${msg}`)
    }
  }

  const isSubmitting = createMutation.isPending || uploading
  const isDisabled   = !leaveTypeId || !startDate || !endDate || daysCount <= 0 || !reason.trim()
                     || (requiresDoc && !docFile)

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      title="طلب إجازة جديدة"
      size="sm"
      disableOverlayClose={isSubmitting}
      footer={
        <div style={{ display: 'flex', gap: 'var(--space-2)', width: '100%' }}>
          <Button variant="secondary" onClick={onClose} disabled={isSubmitting} style={{ flex: 1 }}>
            إلغاء
          </Button>
          <Button
            onClick={handleSubmit}
            loading={isSubmitting}
            disabled={isDisabled}
            icon={<CheckCircle2 size={15} />}
            style={{ flex: 2 }}
          >
            تقديم الطلب
          </Button>
        </div>
      }
    >
      <div className="lf-body">

        {/* ── نوع الإجازة ── */}
        <div className="lf-section">
          <label className="lf-label" htmlFor="leave-type-select">
            نوع الإجازة <span className="lf-required">*</span>
          </label>
          <select
            id="leave-type-select"
            className="form-input"
            value={leaveTypeId}
            onChange={e => setLeaveTypeId(e.target.value)}
            disabled={typesLoading || isSubmitting}
          >
            <option value="">اختر نوع الإجازة...</option>
            {applicableLeaveTypes.map(t => (
              <option key={t.id} value={t.id}>
                {t.name}
                {!t.is_paid ? ' (بدون أجر)' : ''}
                {t.max_days_per_year ? ` — حد أقصى ${t.max_days_per_year} يوم/سنة` : ''}
              </option>
            ))}
          </select>

          {!employeeGender && resolvedEmpId && (
            <div className="lf-notice" style={{ marginTop: 'var(--space-2)' }}>
              <AlertCircle size={13} style={{ flexShrink: 0, marginTop: 1, color: 'var(--color-warning)' }} />
              <span><strong>تنبيه: </strong>بيانات الموظف غير مكتملة (الجنس غير محدد). تُعرض الإجازات المتاحة للجميع فقط. لتوسيع الخيارات، يجب تحديد الجنس في ملف الموظف.</span>
            </div>
          )}

          {/* نوع الإجازة chips */}
          {selectedType && (
            <div className="lf-type-chips">
              <span
                className="lf-type-chip"
                style={{ color: selectedType.is_paid ? 'var(--color-success)' : 'var(--color-warning)' }}
              >
                {selectedType.is_paid ? '✓ بأجر' : '✗ بدون أجر'}
              </span>
              {selectedType.affects_salary && (
                <span className="lf-type-chip" style={{ color: 'var(--color-danger)' }}>
                  · يؤثر على الراتب
                </span>
              )}
              {selectedType.requires_document && (
                <span className="lf-type-chip" style={{ color: 'var(--color-warning)' }}>
                  · يستلزم وثيقة
                </span>
              )}
            </div>
          )}

          {/* مؤشر الرصيد */}
          {leaveTypeId && resolvedEmpId && (
            <BalanceBar
              employeeId={resolvedEmpId}
              leaveTypeId={leaveTypeId}
              daysRequested={daysCount}
            />
          )}
        </div>

        {/* ── التواريخ ── */}
        <div className="lf-section">
          <div className="lf-label">الفترة الزمنية <span className="lf-required">*</span></div>
          <div className="lf-dates-grid">
            <div className="lf-date-field">
              <label className="lf-date-label" htmlFor="leave-start">
                <CalendarDays size={12} /> من تاريخ
              </label>
              <input
                id="leave-start"
                type="date"
                className="form-input"
                value={startDate}
                min={new Date().toISOString().split('T')[0]}
                onChange={e => setStartDate(e.target.value)}
                disabled={isSubmitting}
              />
            </div>
            <div className="lf-date-field">
              <label className="lf-date-label" htmlFor="leave-end">
                <CalendarDays size={12} /> إلى تاريخ
              </label>
              <input
                id="leave-end"
                type="date"
                className="form-input"
                value={endDate}
                min={startDate || new Date().toISOString().split('T')[0]}
                onChange={e => setEndDate(e.target.value)}
                disabled={isSubmitting}
              />
            </div>
          </div>

          {/* مؤشر عدد الأيام */}
          {daysCount > 0 && (
            <div className="lf-days-badge">
              <Clock size={13} />
              <span>مدة الإجازة:</span>
              <strong>{fmtDays(daysCount)}</strong>
            </div>
          )}
        </div>

        {/* ── سبب الإجازة ── */}
        <div className="lf-section">
          <label className="lf-label" htmlFor="leave-reason">
            <FileText size={12} /> سبب الإجازة <span className="lf-required">*</span>
          </label>
          <textarea
            id="leave-reason"
            className="form-input"
            rows={3}
            placeholder="اكتب سبب طلب الإجازة بإيجاز..."
            value={reason}
            onChange={e => setReason(e.target.value)}
            disabled={isSubmitting}
            style={{ resize: 'vertical', minHeight: 80 }}
          />
        </div>

        {/* ── رفع وثيقة ── */}
        {selectedType && (
          <div className="lf-section">
            <div className="lf-label">
              <Upload size={12} /> الوثيقة الداعمة
              {requiresDoc
                ? <span className="lf-required"> *</span>
                : <span className="lf-optional"> (اختياري)</span>
              }
            </div>

            {docFile ? (
              <div className="lf-file-preview">
                <FileText size={14} style={{ color: 'var(--color-success)', flexShrink: 0 }} />
                <span className="lf-file-name">{docFile.name}</span>
                <button
                  type="button"
                  className="lf-file-remove"
                  onClick={() => setDocFile(null)}
                  title="إزالة الملف"
                >
                  <X size={13} />
                </button>
              </div>
            ) : (
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                disabled={isSubmitting}
                className={`lf-upload-zone ${requiresDoc ? 'lf-upload-zone--required' : ''}`}
              >
                <Upload size={20} style={{ color: 'var(--text-muted)' }} />
                <span className="lf-upload-main">
                  {requiresDoc ? 'مطلوب — اضغط لرفع الوثيقة' : 'اضغط لرفع وثيقة داعمة'}
                </span>
                <span className="lf-upload-hint">PDF أو صورة · حجم أقصى 5 MB</span>
              </button>
            )}

            <input
              ref={fileInputRef}
              type="file"
              accept=".pdf,.jpg,.jpeg,.png"
              style={{ display: 'none' }}
              onChange={e => {
                const f = e.target.files?.[0]
                if (!f) return
                if (f.size > 5 * 1024 * 1024) { toast.error('حجم الملف يتجاوز 5MB'); return }
                setDocFile(f)
                e.target.value = ''
              }}
            />
          </div>
        )}

        {/* ── تنبيه الرصيد ── */}
        {selectedType?.has_balance && (
          <div className="lf-notice">
            <Info size={13} style={{ flexShrink: 0, marginTop: 1 }} />
            <span>سيُخصم من رصيد إجازاتك. الطلب سيُرفض تلقائياً إذا كان الرصيد غير كافٍ.</span>
          </div>
        )}
      </div>

      <style>{`
        .lf-body {
          display: flex; flex-direction: column; gap: var(--space-5);
        }
        .lf-section { display: flex; flex-direction: column; gap: var(--space-2); }
        .lf-label {
          display: flex; align-items: center; gap: var(--space-1);
          font-size: var(--text-sm); font-weight: 600; color: var(--text-primary);
        }
        .lf-required { color: var(--color-danger); margin-inline-start: 2px; }
        .lf-optional { font-size: var(--text-xs); color: var(--text-muted); font-weight: 400; margin-inline-start: 4px; }

        /* ── Type chips ── */
        .lf-type-chips {
          display: flex; flex-wrap: wrap; gap: var(--space-2);
          margin-top: var(--space-1);
        }
        .lf-type-chip {
          font-size: var(--text-xs); font-weight: 600;
        }

        /* ── Balance bar ── */
        .lf-balance-card {
          padding: var(--space-3);
          background: var(--bg-surface-2);
          border-radius: var(--radius-md);
          border: 1px solid var(--border-primary);
          display: flex; flex-direction: column; gap: var(--space-2);
        }
        .lf-balance-header {
          display: flex; justify-content: space-between; align-items: center;
          font-size: var(--text-xs);
        }
        .lf-balance-label { color: var(--text-muted); }
        .lf-balance-value { font-weight: 700; }
        .lf-balance-bar-bg {
          height: 6px; border-radius: 99px;
          background: var(--border-primary);
          position: relative; overflow: hidden;
        }
        .lf-balance-bar-fill {
          position: absolute; inset-block: 0; inset-inline-start: 0;
          border-radius: 99px; transition: width 0.3s;
          opacity: 0.3;
        }
        .lf-balance-bar-req {
          position: absolute; inset-block: 0; inset-inline-start: 0;
          border-radius: 99px; transition: width 0.3s;
        }
        .lf-balance-legend {
          display: flex; justify-content: space-between;
          font-size: 11px; color: var(--text-muted);
        }

        /* ── Dates grid ── */
        .lf-dates-grid {
          display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-3);
        }
        .lf-date-field { display: flex; flex-direction: column; gap: var(--space-1); }
        .lf-date-label {
          display: flex; align-items: center; gap: 4px;
          font-size: var(--text-xs); color: var(--text-muted); font-weight: 500;
        }

        /* ── Days badge ── */
        .lf-days-badge {
          display: inline-flex; align-items: center; gap: var(--space-2);
          padding: var(--space-2) var(--space-3);
          background: color-mix(in srgb, var(--color-primary) 8%, transparent);
          border: 1px solid color-mix(in srgb, var(--color-primary) 20%, transparent);
          border-radius: var(--radius-full);
          font-size: var(--text-sm); color: var(--color-primary);
          align-self: flex-start;
        }
        .lf-days-badge strong { font-weight: 800; }

        /* ── File preview ── */
        .lf-file-preview {
          display: flex; align-items: center; gap: var(--space-2);
          padding: var(--space-2) var(--space-3);
          background: color-mix(in srgb, var(--color-success) 7%, transparent);
          border: 1px solid color-mix(in srgb, var(--color-success) 25%, transparent);
          border-radius: var(--radius-md);
          font-size: var(--text-xs);
        }
        .lf-file-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .lf-file-remove {
          background: none; border: none; cursor: pointer;
          color: var(--text-muted); padding: 2px;
          border-radius: 4px; transition: color 0.15s;
          display: flex; align-items: center;
        }
        .lf-file-remove:hover { color: var(--color-danger); }

        /* ── Upload zone ── */
        .lf-upload-zone {
          width: 100%; padding: var(--space-5);
          border: 2px dashed var(--border-primary);
          border-radius: var(--radius-lg);
          background: var(--bg-surface-2);
          cursor: pointer; font-family: var(--font-sans);
          display: flex; flex-direction: column; align-items: center;
          gap: var(--space-1); transition: all 0.15s;
        }
        .lf-upload-zone:hover:not(:disabled) {
          border-color: var(--color-primary);
          background: color-mix(in srgb, var(--color-primary) 4%, transparent);
        }
        .lf-upload-zone--required { border-color: color-mix(in srgb, var(--color-warning) 60%, transparent); }
        .lf-upload-main { font-size: var(--text-sm); color: var(--text-secondary); font-weight: 600; }
        .lf-upload-hint { font-size: var(--text-xs); color: var(--text-muted); }

        /* ── Notice ── */
        .lf-notice {
          display: flex; gap: var(--space-2); align-items: flex-start;
          padding: var(--space-3); border-radius: var(--radius-md);
          background: var(--bg-surface-2); border: 1px solid var(--border-primary);
          font-size: var(--text-xs); color: var(--text-muted); line-height: 1.6;
        }

        @media (max-width: 480px) {
          .lf-dates-grid { grid-template-columns: 1fr; }
        }
      `}</style>
    </ResponsiveModal>
  )
}
