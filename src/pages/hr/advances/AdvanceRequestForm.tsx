import { useState, useEffect } from 'react'
import { Banknote, Calendar, AlertCircle, TrendingDown, CheckCircle2 } from 'lucide-react'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'
import { useRequestAdvance, useCurrentEmployee } from '@/hooks/useQueryHooks'
import type { HRAdvanceInput, HRAdvanceType } from '@/lib/types/hr'
import { toast } from 'sonner'

interface Props {
  open:         boolean
  onClose:      () => void
  employeeId?:  string
}

const fmt = (n: number) =>
  n.toLocaleString('ar-EG-u-nu-latn', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

// ══════════════════════════════════════════════
// MAIN COMPONENT
// ══════════════════════════════════════════════
export default function AdvanceRequestForm({ open, onClose, employeeId: externalEmpId }: Props) {
  const { data: currentEmployee } = useCurrentEmployee()
  const resolvedEmpId = externalEmpId ?? currentEmployee?.id ?? ''

  const [advanceType,       setAdvanceType]       = useState<HRAdvanceType>('scheduled')
  const [amount,            setAmount]            = useState('')
  const [installmentsCount, setInstallmentsCount] = useState(3)
  const [reason,            setReason]            = useState('')

  useEffect(() => {
    if (!open) {
      setAdvanceType('scheduled')
      setAmount('')
      setInstallmentsCount(3)
      setReason('')
    }
  }, [open])

  useEffect(() => {
    if (advanceType === 'instant') setInstallmentsCount(1)
    else if (installmentsCount < 2) setInstallmentsCount(3)
  }, [advanceType])

  const parsedAmount       = parseFloat(amount.replace(/,/g, '')) || 0
  const monthlyInstallment = advanceType === 'scheduled' && installmentsCount > 1
    ? parsedAmount / installmentsCount
    : parsedAmount

  const requestMutation = useRequestAdvance()
  const isSubmitting    = requestMutation.isPending
  const canSubmit       = !!resolvedEmpId && parsedAmount > 0 && reason.trim().length > 0
    && (advanceType === 'instant' || installmentsCount >= 2)

  const handleSubmit = async () => {
    if (!resolvedEmpId) { toast.error('تعذر تحديد الموظف — يرجى التواصل مع مدير الموارد البشرية'); return }
    if (!parsedAmount || parsedAmount <= 0) { toast.error('يرجى إدخال مبلغ صحيح'); return }
    if (!reason.trim()) { toast.error('يرجى كتابة سبب طلب السلفة'); return }
    if (advanceType === 'scheduled' && installmentsCount < 2) {
      toast.error('السلفة المجدولة تحتاج قسطين على الأقل'); return
    }
    const input: HRAdvanceInput = {
      employee_id:        resolvedEmpId,
      advance_type:       advanceType,
      amount:             parsedAmount,
      installments_count: advanceType === 'instant' ? 1 : installmentsCount,
      reason:             reason.trim(),
    }
    try {
      const result = await requestMutation.mutateAsync(input)
      toast.success(result.message || `✅ تم تقديم طلب السلفة بنجاح`)
      onClose()
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err)
      if (msg.includes('active advance') || msg.includes('سلفة نشطة'))
        toast.error('لا يمكن طلب سلفة جديدة قبل سداد السلفة النشطة الحالية')
      else if (msg.includes('exceeded') || msg.includes('نسبة') || msg.includes('limit'))
        toast.error('مبلغ السلفة يتجاوز الحد الأقصى المسموح به من الراتب')
      else
        toast.error(`فشل تقديم الطلب: ${msg}`)
    }
  }

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      title="طلب سلفة جديدة"
      size="sm"
      disableOverlayClose={isSubmitting}
      footer={
        <div style={{ display: 'flex', gap: 'var(--space-2)', width: '100%' }}>
          <Button
            variant="secondary"
            onClick={onClose}
            disabled={isSubmitting}
            style={{ flex: 1 }}
          >
            إلغاء
          </Button>
          <Button
            onClick={handleSubmit}
            loading={isSubmitting}
            disabled={!canSubmit}
            icon={<CheckCircle2 size={15} />}
            style={{ flex: 2 }}
          >
            تقديم الطلب
          </Button>
        </div>
      }
    >
      <div className="adv-form-body">

        {/* ── اختيار النوع ── */}
        <div className="adv-section">
          <div className="adv-section-label">نوع السلفة</div>
          <div className="adv-type-grid">
            {([
              {
                value: 'scheduled',
                icon: <Calendar size={20} />,
                label: 'مجدولة',
                desc: 'تُسدَّد على أقساط شهرية',
                color: 'var(--color-primary)',
              },
              {
                value: 'instant',
                icon: <Banknote size={20} />,
                label: 'فورية',
                desc: 'قسط واحد من الراتب التالي',
                color: 'var(--color-success)',
              },
            ] as { value: HRAdvanceType; icon: React.ReactNode; label: string; desc: string; color: string }[]).map(opt => {
              const active = advanceType === opt.value
              return (
                <button
                  key={opt.value}
                  type="button"
                  onClick={() => setAdvanceType(opt.value)}
                  disabled={isSubmitting}
                  className={`adv-type-card ${active ? 'adv-type-card--active' : ''}`}
                  style={{ '--type-color': opt.color } as React.CSSProperties}
                >
                  <div className="adv-type-icon">{opt.icon}</div>
                  <div className="adv-type-text">
                    <span className="adv-type-name">{opt.label}</span>
                    <span className="adv-type-desc">{opt.desc}</span>
                  </div>
                  {active && <CheckCircle2 size={14} className="adv-type-check" />}
                </button>
              )
            })}
          </div>
        </div>

        {/* ── المبلغ ── */}
        <div className="adv-section">
          <div className="adv-section-label">
            مبلغ السلفة <span className="adv-required">*</span>
          </div>
          <div className="adv-amount-wrapper">
            <input
              id="advance-amount"
              type="number"
              className="form-input adv-amount-input"
              placeholder="0.00"
              min={1}
              step="0.01"
              value={amount}
              onChange={e => setAmount(e.target.value)}
              disabled={isSubmitting}
              dir="ltr"
            />
            <span className="adv-amount-unit">ج.م</span>
          </div>
        </div>

        {/* ── عدد الأقساط (مجدولة فقط) ── */}
        {advanceType === 'scheduled' && (
          <div className="adv-section">
            <div className="adv-section-label">
              عدد الأقساط الشهرية <span className="adv-required">*</span>
            </div>
            <div className="adv-installments-row">
              {[2, 3, 4, 6, 9, 12].map(n => (
                <button
                  key={n}
                  type="button"
                  onClick={() => setInstallmentsCount(n)}
                  disabled={isSubmitting}
                  className={`adv-inst-chip ${installmentsCount === n ? 'adv-inst-chip--active' : ''}`}
                >
                  {n}
                </button>
              ))}
              <input
                type="number"
                className="form-input adv-inst-custom"
                min={2}
                max={24}
                value={installmentsCount}
                onChange={e => setInstallmentsCount(Math.min(24, Math.max(2, parseInt(e.target.value) || 2)))}
                disabled={isSubmitting}
                title="أدخل عدداً مخصصاً (2-24)"
                dir="ltr"
              />
            </div>
            <p className="adv-hint">من 2 إلى 24 قسطاً — اضغط على الأرقام أو أدخل قيمة مخصصة</p>
          </div>
        )}

        {/* ── ملخص مرئي ── */}
        {parsedAmount > 0 && (
          <div className="adv-summary-card">
            <div className="adv-summary-icon">
              <TrendingDown size={18} />
            </div>
            <div className="adv-summary-body">
              <div className="adv-summary-title">
                {advanceType === 'instant' ? 'المبلغ الإجمالي' : 'القسط الشهري التقديري'}
              </div>
              <div className="adv-summary-amount">
                {fmt(monthlyInstallment)} ج.م
              </div>
            </div>
            {advanceType === 'scheduled' && installmentsCount > 1 && (
              <div className="adv-summary-meta">
                <span>{installmentsCount} أقساط</span>
                <span>·</span>
                <span>{fmt(parsedAmount)} إجمالي</span>
              </div>
            )}
          </div>
        )}

        {/* ── السبب ── */}
        <div className="adv-section">
          <div className="adv-section-label">
            سبب طلب السلفة <span className="adv-required">*</span>
          </div>
          <textarea
            id="advance-reason"
            className="form-input"
            rows={3}
            placeholder="اكتب سبب طلب السلفة بإيجاز..."
            value={reason}
            onChange={e => setReason(e.target.value)}
            disabled={isSubmitting}
            style={{ resize: 'vertical', minHeight: 80 }}
          />
          {reason.length > 0 && (
            <div style={{ textAlign: 'end', fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 4 }}>
              {reason.length} حرف
            </div>
          )}
        </div>

        {/* ── تنبيه ── */}
        <div className="adv-notice">
          <AlertCircle size={13} style={{ flexShrink: 0, marginTop: 1 }} />
          <span>لا يمكن تقديم طلب جديد وهناك سلفة نشطة لم تُسدَّد. المبلغ المسموح به رهن بسياسة الشركة.</span>
        </div>
      </div>

      <style>{`
        .adv-form-body {
          display: flex;
          flex-direction: column;
          gap: var(--space-5);
        }

        /* ── Section heading ── */
        .adv-section { display: flex; flex-direction: column; gap: var(--space-2); }
        .adv-section-label {
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
        }
        .adv-required { color: var(--color-danger); margin-inline-start: 2px; }
        .adv-hint { font-size: var(--text-xs); color: var(--text-muted); margin: var(--space-1) 0 0; }

        /* ── Type selector cards ── */
        .adv-type-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-2);
        }
        .adv-type-card {
          position: relative;
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          border-radius: var(--radius-lg);
          border: 2px solid var(--border-primary);
          background: var(--bg-surface);
          cursor: pointer;
          transition: all 0.15s ease;
          font-family: var(--font-sans);
          text-align: start;
        }
        .adv-type-card:hover:not(:disabled) {
          border-color: var(--type-color, var(--color-primary));
          background: color-mix(in srgb, var(--type-color, var(--color-primary)) 5%, transparent);
        }
        .adv-type-card--active {
          border-color: var(--type-color, var(--color-primary)) !important;
          background: color-mix(in srgb, var(--type-color, var(--color-primary)) 8%, transparent) !important;
          box-shadow: 0 0 0 3px color-mix(in srgb, var(--type-color, var(--color-primary)) 15%, transparent);
        }
        .adv-type-icon {
          width: 40px; height: 40px;
          border-radius: var(--radius-md);
          background: color-mix(in srgb, var(--type-color, var(--color-primary)) 12%, transparent);
          color: var(--type-color, var(--color-primary));
          display: flex; align-items: center; justify-content: center;
          flex-shrink: 0;
        }
        .adv-type-text {
          display: flex; flex-direction: column; gap: 2px; flex: 1; min-width: 0;
        }
        .adv-type-name {
          font-size: var(--text-sm); font-weight: 700;
          color: var(--text-primary);
        }
        .adv-type-desc {
          font-size: 11px; color: var(--text-muted); line-height: 1.4;
        }
        .adv-type-check {
          color: var(--type-color, var(--color-primary));
          flex-shrink: 0;
        }

        /* ── Amount input ── */
        .adv-amount-wrapper {
          position: relative;
        }
        .adv-amount-input {
          font-size: var(--text-lg) !important;
          font-weight: 700 !important;
          padding-inline-end: var(--space-10) !important;
          text-align: start;
        }
        .adv-amount-unit {
          position: absolute;
          inset-inline-end: var(--space-3);
          top: 50%;
          transform: translateY(-50%);
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-muted);
          pointer-events: none;
        }

        /* ── Installment chips ── */
        .adv-installments-row {
          display: flex;
          flex-wrap: wrap;
          gap: var(--space-2);
          align-items: center;
        }
        .adv-inst-chip {
          min-width: 44px; height: 36px;
          padding: 0 var(--space-3);
          border-radius: var(--radius-full);
          border: 1.5px solid var(--border-primary);
          background: var(--bg-surface);
          color: var(--text-secondary);
          font-family: var(--font-sans);
          font-size: var(--text-sm);
          font-weight: 600;
          cursor: pointer;
          transition: all 0.15s;
          white-space: nowrap;
        }
        .adv-inst-chip:hover:not(:disabled) {
          border-color: var(--color-primary);
          color: var(--color-primary);
          background: var(--color-primary-light);
        }
        .adv-inst-chip--active {
          border-color: var(--color-primary) !important;
          background: var(--color-primary) !important;
          color: #fff !important;
        }
        .adv-inst-custom {
          width: 70px !important;
          height: 36px !important;
          padding: 0 var(--space-2) !important;
          font-size: var(--text-sm) !important;
          text-align: center;
        }

        /* ── Summary card ── */
        .adv-summary-card {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-4);
          background: color-mix(in srgb, var(--color-primary) 6%, var(--bg-surface));
          border: 1px solid color-mix(in srgb, var(--color-primary) 20%, transparent);
          border-radius: var(--radius-lg);
          position: relative;
        }
        .adv-summary-icon {
          width: 40px; height: 40px;
          border-radius: var(--radius-md);
          background: color-mix(in srgb, var(--color-primary) 12%, transparent);
          color: var(--color-primary);
          display: flex; align-items: center; justify-content: center;
          flex-shrink: 0;
        }
        .adv-summary-body { flex: 1; }
        .adv-summary-title {
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-bottom: 2px;
        }
        .adv-summary-amount {
          font-size: var(--text-xl);
          font-weight: 800;
          color: var(--color-primary);
          font-variant-numeric: tabular-nums;
        }
        .adv-summary-meta {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: 2px;
          font-size: var(--text-xs);
          color: var(--text-muted);
        }

        /* ── Notice ── */
        .adv-notice {
          display: flex;
          gap: var(--space-2);
          align-items: flex-start;
          padding: var(--space-3);
          background: var(--bg-surface-2);
          border-radius: var(--radius-md);
          border: 1px solid var(--border-primary);
          font-size: var(--text-xs);
          color: var(--text-muted);
          line-height: 1.6;
        }

        @media (max-width: 480px) {
          .adv-type-grid { grid-template-columns: 1fr; }
          .adv-type-card { padding: var(--space-3); }
        }
      `}</style>
    </ResponsiveModal>
  )
}
