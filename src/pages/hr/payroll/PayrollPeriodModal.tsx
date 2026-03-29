import { useState, useEffect } from 'react'
import { Calendar, Plus } from 'lucide-react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { createPayrollPeriod } from '@/lib/services/hr'
import type { HRPayrollPeriodInput } from '@/lib/types/hr'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'
import Input from '@/components/ui/Input'
import Select from '@/components/ui/Select'

interface Props {
  open: boolean
  onClose: () => void
}

const MONTH_NAMES = [
  'يناير','فبراير','مارس','أبريل','مايو','يونيو',
  'يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'
]

const currentYear = new Date().getFullYear()
const currentMonth = new Date().getMonth() + 1  // 1-indexed

/**
 * حساب تاريخ أول وآخر يوم في الشهر بشكل آمن
 * بدون استخدام toISOString() الذي يحوّل لـ UTC ويسبب خطأ ±1 يوم
 */
function getMonthDates(year: number, month: number) {
  // أول يوم: YYYY-MM-01
  const startDate = `${year}-${String(month).padStart(2, '0')}-01`

  // آخر يوم: نأخذ اليوم 0 من الشهر التالي = آخر يوم من الشهر الحالي
  const lastDay = new Date(year, month, 0).getDate()
  const endDate = `${year}-${String(month).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`

  return { start_date: startDate, end_date: endDate }
}

export default function PayrollPeriodModal({ open, onClose }: Props) {
  const qc = useQueryClient()
  const [year,  setYear]  = useState(currentYear)
  const [month, setMonth] = useState(currentMonth)

  // التواريخ الافتراضية من الشهر المختار
  const defaults = getMonthDates(year, month)

  // حالة التواريخ قابلة للتعديل
  const [startDate, setStartDate] = useState(defaults.start_date)
  const [endDate, setEndDate]     = useState(defaults.end_date)

  // عند تغيير الشهر أو السنة → تحديث التواريخ تلقائياً
  useEffect(() => {
    const d = getMonthDates(year, month)
    setStartDate(d.start_date)
    setEndDate(d.end_date)
  }, [year, month])

  const name = `${MONTH_NAMES[month - 1]} ${year}`

  const form: HRPayrollPeriodInput = {
    year,
    month,
    name,
    start_date: startDate,
    end_date:   endDate,
  }

  // التحقق من صحة التواريخ
  const isValid = startDate && endDate && startDate <= endDate

  const createMut = useMutation({
    mutationFn: () => createPayrollPeriod(form),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['hr-payroll-periods'] })
      toast.success(`تم إنشاء فترة ${name}`)
      onClose()
    },
    onError: (e: Error) => toast.error(e.message),
  })

  // إعادة تعيين الحالة عند فتح/إغلاق
  useEffect(() => {
    if (open) {
      const d = getMonthDates(currentYear, currentMonth)
      setYear(currentYear)
      setMonth(currentMonth)
      setStartDate(d.start_date)
      setEndDate(d.end_date)
    }
  }, [open])

  const yearOptions = [currentYear - 1, currentYear, currentYear + 1].map(y => ({
    value: String(y), label: String(y),
  }))

  const monthOptions = MONTH_NAMES.map((m, i) => ({
    value: String(i + 1), label: m,
  }))

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      title="إنشاء فترة راتب جديدة"
      size="sm"
      footer={
        <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
          <Button variant="secondary" onClick={onClose} style={{ flex: 1 }}>إلغاء</Button>
          <Button
            icon={<Plus size={15} />}
            onClick={() => createMut.mutate()}
            loading={createMut.isPending}
            disabled={!isValid}
            style={{ flex: 2 }}
          >
            إنشاء الفترة
          </Button>
        </div>
      }
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        {/* شرح */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          padding: 'var(--space-3) var(--space-4)',
          background: 'color-mix(in srgb, var(--color-primary) 6%, transparent)',
          borderRadius: 'var(--radius-md)',
          border: '1px solid color-mix(in srgb, var(--color-primary) 20%, transparent)',
          fontSize: 'var(--text-sm)', color: 'var(--text-secondary)',
        }}>
          <Calendar size={16} color="var(--color-primary)" />
          <span>حدد الشهر والسنة — التواريخ تُملأ تلقائياً ويمكنك تعديلها إذا احتجت فترة مختلفة.</span>
        </div>

        {/* الشهر والسنة */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
          <Select
            label="الشهر"
            value={String(month)}
            onChange={e => setMonth(Number(e.target.value))}
            options={monthOptions}
          />
          <Select
            label="السنة"
            value={String(year)}
            onChange={e => setYear(Number(e.target.value))}
            options={yearOptions}
          />
        </div>

        {/* التواريخ — قابلة للتعديل */}
        <div style={{
          padding: 'var(--space-3)',
          background: 'var(--bg-surface-2)',
          borderRadius: 'var(--radius-md)',
          border: '1px solid var(--border-color)',
          fontSize: 'var(--text-sm)',
        }}>
          <div style={{ fontWeight: 700, marginBottom: 8, color: 'var(--color-primary)' }}>{name}</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-2)' }}>
            <Input
              label="بداية الفترة"
              type="date"
              value={startDate}
              onChange={e => setStartDate(e.target.value)}
            />
            <Input
              label="نهاية الفترة"
              type="date"
              value={endDate}
              onChange={e => setEndDate(e.target.value)}
            />
          </div>

          {/* تحذير إذا التواريخ لا تتطابق مع الشهر المختار */}
          {(startDate !== defaults.start_date || endDate !== defaults.end_date) && (
            <div style={{
              marginTop: 'var(--space-2)',
              padding: 'var(--space-2) var(--space-3)',
              background: 'color-mix(in srgb, var(--color-warning) 10%, transparent)',
              borderRadius: 'var(--radius-sm)',
              border: '1px solid color-mix(in srgb, var(--color-warning) 30%, transparent)',
              fontSize: 'var(--text-xs)',
              color: 'var(--color-warning)',
              display: 'flex', alignItems: 'center', gap: 6,
            }}>
              ⚠️ التواريخ مختلفة عن الافتراضية ({defaults.start_date} → {defaults.end_date})
            </div>
          )}

          {/* تحذير إذا التواريخ غير صحيحة */}
          {!isValid && (
            <div style={{
              marginTop: 'var(--space-2)',
              padding: 'var(--space-2) var(--space-3)',
              background: 'color-mix(in srgb, var(--color-danger) 10%, transparent)',
              borderRadius: 'var(--radius-sm)',
              border: '1px solid color-mix(in srgb, var(--color-danger) 30%, transparent)',
              fontSize: 'var(--text-xs)',
              color: 'var(--color-danger)',
            }}>
              ❌ تاريخ البداية يجب أن يسبق تاريخ النهاية
            </div>
          )}
        </div>
      </div>
    </ResponsiveModal>
  )
}
