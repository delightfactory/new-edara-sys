import { useState, useEffect, useRef } from 'react'
import { CalendarDays, FileText, AlertCircle, Upload, X } from 'lucide-react'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'
import {
  useHRLeaveTypes,
  useCreateLeaveRequest,
  useCurrentEmployee,
  useHRLeaveBalances,
} from '@/hooks/useQueryHooks'
import type { HRLeaveRequestInput } from '@/lib/types/hr'
import { supabase } from '@/lib/supabase/client'
import { toast } from 'sonner'

interface Props {
  open: boolean
  onClose: () => void
  /** إذا مُرِّر employeeId من خارج (مدير ينوب عن موظف) يتجاوز useCurrentEmployee */
  employeeId?: string
}

// ─── حساب عدد الأيام بين تاريخين ─────────────────────────
function calcDays(from: string, to: string): number {
  if (!from || !to) return 0
  const d1 = new Date(from)
  const d2 = new Date(to)
  const diff = Math.round((d2.getTime() - d1.getTime()) / (1000 * 60 * 60 * 24))
  return diff >= 0 ? diff + 1 : 0
}

// ─── تنسيق الأيام بالعربية ────────────────────────────────
function fmtDays(n: number): string {
  if (n === 0) return '—'
  if (n === 1) return 'يوم واحد'
  if (n === 2) return 'يومان'
  if (n <= 10) return `${n} أيام`
  return `${n} يوماً`
}

// ─── UX-03: مؤشر الرصيد المتبقي ───────────────────────────────
function LeaveBalanceIndicator({
  employeeId, leaveTypeId, daysRequested,
}: { employeeId: string; leaveTypeId: string; daysRequested: number }) {
  const currentYear = new Date().getFullYear()
  const { data: balances = [] } = useHRLeaveBalances(employeeId || null, currentYear)
  if (!leaveTypeId || !employeeId) return null
  const bal = balances.find(b => b.leave_type_id === leaveTypeId)
  if (!bal) return null

  const isEnough = bal.remaining_days >= daysRequested
  const color = daysRequested > 0 && !isEnough
    ? 'var(--color-danger)'
    : daysRequested > 0
    ? 'var(--color-success)'
    : 'var(--color-info)'

  return (
    <div style={{
      marginTop: 'var(--space-2)',
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      padding: 'var(--space-2) var(--space-3)',
      background: `color-mix(in srgb, ${color} 8%, transparent)`,
      border: `1px solid color-mix(in srgb, ${color} 25%, transparent)`,
      borderRadius: 'var(--radius-md)',
      fontSize: 'var(--text-xs)',
    }}>
      <span style={{ color: 'var(--text-secondary)' }}>الرصيد المتبقي:</span>
      <span style={{ fontWeight: 700, color }}>
        {bal.remaining_days} يوم
        {daysRequested > 0 && ` (تطلب ${daysRequested})`}
        {daysRequested > 0 && !isEnough && ' ⚠ غير كافٍ'}
      </span>
    </div>
  )
}

// ═════════════════════════════════════════════════════════
// MAIN COMPONENT
// ═════════════════════════════════════════════════════════


export default function LeaveRequestForm({ open, onClose, employeeId: externalEmpId }: Props) {
  // الموظف الحالي (للخدمة الذاتية)
  const { data: currentEmployee } = useCurrentEmployee()
  const resolvedEmpId = externalEmpId ?? currentEmployee?.id ?? ''

  // بيانات الفورم
  const [leaveTypeId, setLeaveTypeId] = useState('')
  const [startDate,   setStartDate]   = useState('')
  const [endDate,     setEndDate]     = useState('')
  const [reason,      setReason]      = useState('')

  // F-G: رفع الوثيقة
  const [docFile, setDocFile]   = useState<File | null>(null)
  const [uploading, setUploading] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  // حساب عدد الأيام تلقائياً
  const daysCount = calcDays(startDate, endDate)

  // تأكد أن تاريخ النهاية ≥ تاريخ البداية
  useEffect(() => {
    if (endDate && startDate && endDate < startDate) {
      setEndDate(startDate)
    }
  }, [startDate, endDate])

  // إعادة ضبط الفورم عند الإغلاق
  useEffect(() => {
    if (!open) {
      setLeaveTypeId('')
      setStartDate('')
      setEndDate('')
      setReason('')
      setDocFile(null)
    }
  }, [open])

  const { data: leaveTypes = [], isLoading: typesLoading } = useHRLeaveTypes()
  const createMutation = useCreateLeaveRequest()

  const selectedType = leaveTypes.find(t => t.id === leaveTypeId)
  const requiresDoc  = selectedType?.requires_document ?? false

  const handleSubmit = async () => {
    // ── التحقق الأساسي ──
    if (!resolvedEmpId) {
      toast.error('تعذر تحديد الموظف — تأكد من ربط حسابك بسجل موظف')
      return
    }
    if (!leaveTypeId) {
      toast.error('يرجى اختيار نوع الإجازة')
      return
    }
    if (!startDate || !endDate) {
      toast.error('يرجى تحديد تاريخ البداية والنهاية')
      return
    }
    if (daysCount <= 0) {
      toast.error('تاريخ النهاية يجب أن يكون بعد تاريخ البداية')
      return
    }
    if (!reason.trim()) {
      toast.error('يرجى كتابة سبب الإجازة')
      return
    }
    // F-G: وثيقة مطلوبة إذا كان النوع يستلزمها
    if (requiresDoc && !docFile) {
      toast.error('هذا النوع من الإجازة يتطلب رفع وثيقة داعمة')
      return
    }

    let document_url: string | undefined
    // F-G: رفع الوثيقة إلى Storage إذا وجدت
    if (docFile) {
      setUploading(true)
      try {
        const ext  = docFile.name.split('.').pop()
        const path = `leave-docs/${resolvedEmpId}/${Date.now()}.${ext}`
        const { error: upErr } = await supabase.storage
          .from('hr-documents')
          .upload(path, docFile)
        if (upErr) throw upErr
        const { data: urlData } = supabase.storage.from('hr-documents').getPublicUrl(path)
        document_url = urlData.publicUrl
      } catch (e: any) {
        toast.error('فشل رفع الوثيقة: ' + (e.message ?? ''))
        setUploading(false)
        return
      }
      setUploading(false)
    }

    const input: HRLeaveRequestInput = {
      employee_id:    resolvedEmpId,
      leave_type_id:  leaveTypeId,
      start_date:     startDate,
      end_date:       endDate,
      days_count:     daysCount,
      reason:         reason.trim(),
      ...(document_url ? { document_url } : {}),
    }

    try {
      await createMutation.mutateAsync(input)
      toast.success('تم تقديم طلب الإجازة بنجاح')
      onClose()
    } catch (err: unknown) {
      // الـ Trigger handle_leave_submission يُرجع EXCEPTION إذا كان الرصيد لا يكفي
      const msg = err instanceof Error ? err.message : String(err)
      if (msg.includes('insufficient') || msg.includes('رصيد') || msg.includes('balance')) {
        toast.error('رصيد الإجازة غير كافٍ للمدة المطلوبة')
      } else {
        toast.error(`فشل تقديم الطلب: ${msg}`)
      }
    }
  }

  const isSubmitting = createMutation.isPending || uploading
  const isDisabled   = !leaveTypeId || !startDate || !endDate || daysCount <= 0 || !reason.trim()
                     || (requiresDoc && !docFile)

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      title="طلب إجازة"
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
            style={{ flex: 1 }}
          >
            تقديم الطلب
          </Button>
        </div>
      }
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>

        {/* نوع الإجازة */}
        <div className="form-group">
          <label className="form-label" htmlFor="leave-type-select">
            نوع الإجازة <span style={{ color: 'var(--color-danger)' }}>*</span>
          </label>
          <select
            id="leave-type-select"
            className="form-input"
            value={leaveTypeId}
            onChange={e => setLeaveTypeId(e.target.value)}
            disabled={typesLoading || isSubmitting}
          >
            <option value="">اختر نوع الإجازة...</option>
            {leaveTypes.map(t => (
              <option key={t.id} value={t.id}>
                {t.name}
                {!t.is_paid ? ' (بدون أجر)' : ''}
                {t.max_days_per_year ? ` — حد أقصى ${t.max_days_per_year} يوم/سنة` : ''}
              </option>
            ))}
          </select>
        {selectedType && (
            <div style={{
              marginTop: 'var(--space-1)',
              fontSize: 'var(--text-xs)',
              color: selectedType.is_paid ? 'var(--color-success)' : 'var(--color-warning)',
              display: 'flex', alignItems: 'center', gap: 4,
            }}>
              <span>{selectedType.is_paid ? '✓ بأجر' : '✗ بدون أجر'}</span>
              {selectedType.affects_salary && (
                <span style={{ color: 'var(--color-danger)' }}>· يؤثر على الراتب</span>
              )}
            </div>
          )}

          {/* UX-03: عرض الرصيد المتبقي من نوع الإجازة المختار */}
          <LeaveBalanceIndicator
            employeeId={resolvedEmpId}
            leaveTypeId={leaveTypeId}
            daysRequested={daysCount}
          />
        </div>

        {/* تواريخ البداية والنهاية */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
          <div className="form-group">
            <label className="form-label" htmlFor="leave-start">
              <CalendarDays size={12} style={{ marginLeft: 4 }} />
              من تاريخ <span style={{ color: 'var(--color-danger)' }}>*</span>
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

          <div className="form-group">
            <label className="form-label" htmlFor="leave-end">
              إلى تاريخ <span style={{ color: 'var(--color-danger)' }}>*</span>
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
          <div style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            padding: 'var(--space-3) var(--space-4)',
            background: 'color-mix(in srgb, var(--color-primary) 6%, transparent)',
            border: '1px solid color-mix(in srgb, var(--color-primary) 20%, transparent)',
            borderRadius: 'var(--radius-md)',
          }}>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>
              مدة الإجازة
            </span>
            <span style={{ fontWeight: 700, color: 'var(--color-primary)' }}>
              {fmtDays(daysCount)}
            </span>
          </div>
        )}

        {/* السبب */}
        <div className="form-group">
          <label className="form-label" htmlFor="leave-reason">
            <FileText size={12} style={{ marginLeft: 4 }} />
            سبب الإجازة <span style={{ color: 'var(--color-danger)' }}>*</span>
          </label>
          <textarea
            id="leave-reason"
            className="form-input"
            rows={3}
            placeholder="اكتب سبب طلب الإجازة..."
            value={reason}
            onChange={e => setReason(e.target.value)}
            disabled={isSubmitting}
            style={{ resize: 'vertical', minHeight: 80 }}
          />
        </div>

        {/* F-G: رفع الوثيقة عند requires_document */}
        {selectedType && (
          <div className="form-group">
            <label className="form-label">
              <Upload size={12} style={{ marginLeft: 4 }} />
              برفق الوثيقة
              {requiresDoc
                ? <span style={{ color: 'var(--color-danger)', marginRight: 4 }}>*</span>
                : <span style={{ color: 'var(--text-muted)', marginRight: 4, fontSize: 'var(--text-xs)' }}> (اختياري)</span>
              }
            </label>

            {docFile ? (
              <div style={{
                display: 'flex', alignItems: 'center', gap: 'var(--space-2)',
                padding: 'var(--space-2) var(--space-3)',
                background: 'color-mix(in srgb, var(--color-success) 8%, transparent)',
                border: '1px solid color-mix(in srgb, var(--color-success) 25%, transparent)',
                borderRadius: 'var(--radius-md)',
                fontSize: 'var(--text-xs)',
              }}>
                <FileText size={12} style={{ color: 'var(--color-success)', flexShrink: 0 }} />
                <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{docFile.name}</span>
                <button
                  type="button"
                  onClick={() => setDocFile(null)}
                  style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', padding: 2 }}
                >
                  <X size={12} />
                </button>
              </div>
            ) : (
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                disabled={isSubmitting}
                style={{
                  width: '100%', padding: 'var(--space-3)',
                  border: `2px dashed ${requiresDoc ? 'var(--color-danger)' : 'var(--border-color)'}`,
                  borderRadius: 'var(--radius-md)',
                  background: 'var(--bg-surface-2)',
                  cursor: 'pointer',
                  display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 'var(--space-1)',
                  color: 'var(--text-muted)', fontSize: 'var(--text-xs)',
                  transition: 'border-color 0.15s',
                }}
              >
                <Upload size={16} />
                <span>{requiresDoc ? 'مطلوب — اضغط لرفع الوثيقة' : 'اختياري — اضغط لرفع وثيقة'}</span>
                <span style={{ fontSize: 10 }}>PDF, صورة — حجم أقصى 5MB</span>
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
                if (f.size > 5 * 1024 * 1024) {
                  toast.error('حجم الملف يتجاوز 5MB')
                  return
                }
                setDocFile(f)
                e.target.value = ''
              }}
            />
          </div>
        )}

        {/* تنبيه الرصيد */}
        {selectedType?.has_balance && (
          <div style={{
            display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-start',
            fontSize: 'var(--text-xs)', color: 'var(--text-muted)',
            background: 'var(--bg-surface-2)',
            padding: 'var(--space-2) var(--space-3)',
            borderRadius: 'var(--radius-md)',
          }}>
            <AlertCircle size={12} style={{ flexShrink: 0, marginTop: 1 }} />
            سيُخصم من رصيد إجازاتك. الطلب سيُرفض تلقائياً إذا كان الرصيد غير كافـْ.
          </div>
        )}
      </div>
    </ResponsiveModal>
  )
}
