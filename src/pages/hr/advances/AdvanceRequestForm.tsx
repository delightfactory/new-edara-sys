import { useState, useEffect } from 'react'
import { Banknote, Calendar, AlertCircle } from 'lucide-react'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'
import { useRequestAdvance, useCurrentEmployee } from '@/hooks/useQueryHooks'
import type { HRAdvanceInput, HRAdvanceType } from '@/lib/types/hr'
import { toast } from 'sonner'

interface Props {
  open:         boolean
  onClose:      () => void
  /** employeeId خارجي — يُستخدم عندما يتقدم مدير نيابةً عن موظف */
  employeeId?:  string
}

const fmt = (n: number) =>
  n.toLocaleString('ar-EG-u-nu-latn', { maximumFractionDigits: 2 })

// ═════════════════════════════════════════════════════════
// MAIN COMPONENT
// ═════════════════════════════════════════════════════════

export default function AdvanceRequestForm({ open, onClose, employeeId: externalEmpId }: Props) {
  const { data: currentEmployee } = useCurrentEmployee()
  const resolvedEmpId = externalEmpId ?? currentEmployee?.id ?? ''

  // ── حقول الفورم ─────────────────────────────────────
  const [advanceType,        setAdvanceType]        = useState<HRAdvanceType>('scheduled')
  const [amount,             setAmount]             = useState('')
  const [installmentsCount,  setInstallmentsCount]  = useState(1)
  const [reason,             setReason]             = useState('')

  // إعادة ضبط عند الإغلاق
  useEffect(() => {
    if (!open) {
      setAdvanceType('scheduled')
      setAmount('')
      setInstallmentsCount(1)
      setReason('')
    }
  }, [open])

  // القسط الشهري التقديري
  const parsedAmount = parseFloat(amount.replace(/,/g, '')) || 0
  const monthlyInstallment = advanceType === 'scheduled' && installmentsCount > 1
    ? parsedAmount / installmentsCount
    : parsedAmount

  // instant → دائماً قسط واحد
  useEffect(() => {
    if (advanceType === 'instant') setInstallmentsCount(1)
  }, [advanceType])

  const requestMutation = useRequestAdvance()
  const isSubmitting    = requestMutation.isPending

  // ── إرسال الطلب عبر RPC request_advance ────────────
  const handleSubmit = async () => {
    if (!resolvedEmpId) {
      toast.error('تعذر تحديد الموظف — يرجى التواصل مع مدير الموارد البشرية')
      return
    }
    if (!parsedAmount || parsedAmount <= 0) {
      toast.error('يرجى إدخال مبلغ صحيح')
      return
    }
    if (!reason.trim()) {
      toast.error('يرجى كتابة سبب طلب السلفة')
      return
    }
    if (advanceType === 'scheduled' && installmentsCount < 2) {
      toast.error('السلفة المجدولة تحتاج قسطين على الأقل — اختر "فورية" إذا أردت قسطاً واحداً')
      return
    }

    const input: HRAdvanceInput = {
      employee_id:       resolvedEmpId,
      advance_type:      advanceType,
      amount:            parsedAmount,
      installments_count: advanceType === 'instant' ? 1 : installmentsCount,
      reason:            reason.trim(),
    }

    try {
      const result = await requestMutation.mutateAsync(input)
      toast.success(
        result.message ||
        `✅ تم تقديم طلب السلفة بنجاح${result.installments_created > 1 ? ` — ${result.installments_created} أقساط` : ''}`
      )
      onClose()
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err)

      // رسائل الـ DB triggers المعروفة
      if (msg.includes('active advance') || msg.includes('سلفة نشطة')) {
        toast.error('لا يمكن طلب سلفة جديدة قبل سداد السلفة النشطة الحالية')
      } else if (msg.includes('exceeded') || msg.includes('نسبة') || msg.includes('limit')) {
        toast.error('مبلغ السلفة يتجاوز الحد الأقصى المسموح به من الراتب')
      } else {
        toast.error(`فشل تقديم الطلب: ${msg}`)
      }
    }
  }

  const canSubmit = !!resolvedEmpId && parsedAmount > 0 && reason.trim().length > 0
    && (advanceType === 'instant' || installmentsCount >= 2)

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      title="طلب سلفة"
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
            disabled={!canSubmit}
            style={{ flex: 1 }}
          >
            تقديم الطلب
          </Button>
        </div>
      }
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>

        {/* نوع السلفة */}
        <div className="form-group">
          <label className="form-label">نوع السلفة <span style={{ color: 'var(--color-danger)' }}>*</span></label>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-2)' }}>
            {([
              { value: 'scheduled', label: 'مجدولة (أقساط)', icon: <Calendar size={14} /> },
              { value: 'instant',   label: 'فورية (قسط واحد)', icon: <Banknote size={14} /> },
            ] as { value: HRAdvanceType; label: string; icon: React.ReactNode }[]).map(opt => (
              <button
                key={opt.value}
                type="button"
                onClick={() => setAdvanceType(opt.value)}
                disabled={isSubmitting}
                style={{
                  display: 'flex', alignItems: 'center', gap: 'var(--space-2)',
                  padding: 'var(--space-3) var(--space-3)',
                  borderRadius: 'var(--radius-md)',
                  border: `2px solid ${advanceType === opt.value ? 'var(--color-primary)' : 'var(--border-primary)'}`,
                  background: advanceType === opt.value
                    ? 'color-mix(in srgb, var(--color-primary) 8%, transparent)'
                    : 'var(--bg-card)',
                  color: advanceType === opt.value ? 'var(--color-primary)' : 'var(--text-secondary)',
                  fontFamily: 'var(--font-sans)', fontWeight: 600, fontSize: 'var(--text-sm)',
                  cursor: 'pointer', transition: 'all 0.15s',
                  justifyContent: 'center',
                }}
              >
                {opt.icon} {opt.label}
              </button>
            ))}
          </div>
        </div>

        {/* المبلغ */}
        <div className="form-group">
          <label className="form-label" htmlFor="advance-amount">
            مبلغ السلفة <span style={{ color: 'var(--color-danger)' }}>*</span>
          </label>
          <div style={{ position: 'relative' }}>
            <input
              id="advance-amount"
              type="number"
              className="form-input"
              placeholder="0.00"
              min={1}
              step="0.01"
              value={amount}
              onChange={e => setAmount(e.target.value)}
              disabled={isSubmitting}
              style={{ paddingLeft: 'var(--space-12)' }}
            />
            <span style={{
              position: 'absolute', left: 'var(--space-3)', top: '50%', transform: 'translateY(-50%)',
              fontSize: 'var(--text-sm)', color: 'var(--text-muted)', pointerEvents: 'none',
            }}>
              ج.م
            </span>
          </div>
        </div>

        {/* عدد الأقساط (للمجدولة فقط) */}
        {advanceType === 'scheduled' && (
          <div className="form-group">
            <label className="form-label" htmlFor="advance-installments">
              عدد الأقساط الشهرية <span style={{ color: 'var(--color-danger)' }}>*</span>
            </label>
            <input
              id="advance-installments"
              type="number"
              className="form-input"
              min={2}
              max={24}
              value={installmentsCount}
              onChange={e => setInstallmentsCount(Math.max(2, parseInt(e.target.value) || 2))}
              disabled={isSubmitting}
            />
            <p style={{ margin: 'var(--space-1) 0 0', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
              من 2 إلى 24 قسطاً
            </p>
          </div>
        )}

        {/* ملخص القسط */}
        {parsedAmount > 0 && (
          <div style={{
            display: 'flex', justifyContent: 'space-between', alignItems: 'center',
            padding: 'var(--space-3) var(--space-4)',
            background: 'color-mix(in srgb, var(--color-primary) 6%, transparent)',
            border: '1px solid color-mix(in srgb, var(--color-primary) 20%, transparent)',
            borderRadius: 'var(--radius-md)',
          }}>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>
              {advanceType === 'instant' ? 'المبلغ الفوري' : 'القسط الشهري التقديري'}
            </span>
            <span style={{ fontWeight: 700, color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>
              {fmt(monthlyInstallment)} ج.م
            </span>
          </div>
        )}

        {/* السبب */}
        <div className="form-group">
          <label className="form-label" htmlFor="advance-reason">
            سبب طلب السلفة <span style={{ color: 'var(--color-danger)' }}>*</span>
          </label>
          <textarea
            id="advance-reason"
            className="form-input"
            rows={3}
            placeholder="اكتب سبب طلب السلفة..."
            value={reason}
            onChange={e => setReason(e.target.value)}
            disabled={isSubmitting}
            style={{ resize: 'vertical', minHeight: 80 }}
          />
        </div>

        {/* تنبيه مهم */}
        <div style={{
          display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-start',
          fontSize: 'var(--text-xs)', color: 'var(--text-muted)',
          background: 'var(--bg-surface-2)',
          padding: 'var(--space-2) var(--space-3)',
          borderRadius: 'var(--radius-md)',
        }}>
          <AlertCircle size={12} style={{ flexShrink: 0, marginTop: 1 }} />
          لا يمكن تقديم طلب جديد وهناك سلفة نشطة لم تُسدَّد بالكامل. المبلغ المسموح به رهن بسياسة الشركة.
        </div>
      </div>
    </ResponsiveModal>
  )
}
