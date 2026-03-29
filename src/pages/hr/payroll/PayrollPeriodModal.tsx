import { useState } from 'react'
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

function getMonthDates(year: number, month: number) {
  const start = new Date(year, month - 1, 1)
  const end   = new Date(year, month, 0)   // last day of month
  return {
    start_date: start.toISOString().split('T')[0],
    end_date:   end.toISOString().split('T')[0],
  }
}

export default function PayrollPeriodModal({ open, onClose }: Props) {
  const qc = useQueryClient()
  const [year,  setYear]  = useState(currentYear)
  const [month, setMonth] = useState(currentMonth)

  const dates = getMonthDates(year, month)
  const name  = `${MONTH_NAMES[month - 1]} ${year}`

  const form: HRPayrollPeriodInput = {
    year,
    month,
    name,
    start_date: dates.start_date,
    end_date:   dates.end_date,
  }

  const createMut = useMutation({
    mutationFn: () => createPayrollPeriod(form),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['hr-payroll-periods'] })
      toast.success(`تم إنشاء فترة ${name}`)
      onClose()
    },
    onError: (e: Error) => toast.error(e.message),
  })

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
          <span>حدد الشهر والسنة لتوليد الفترة الزمنية للمسير. يمكنك إنشاء مسيرات متعددة لنفس الفترة.</span>
        </div>

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

        {/* معاينة الفترة */}
        <div style={{
          padding: 'var(--space-3)',
          background: 'var(--bg-surface-2)',
          borderRadius: 'var(--radius-md)',
          border: '1px solid var(--border-color)',
          fontSize: 'var(--text-sm)',
        }}>
          <div style={{ fontWeight: 700, marginBottom: 8, color: 'var(--color-primary)' }}>{name}</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-2)' }}>
            <div>
              <span style={{ color: 'var(--text-muted)' }}>من: </span>
              <Input type="date" value={form.start_date} onChange={() => {}} readOnly />
            </div>
            <div>
              <span style={{ color: 'var(--text-muted)' }}>إلى: </span>
              <Input type="date" value={form.end_date} onChange={() => {}} readOnly />
            </div>
          </div>
        </div>
      </div>
    </ResponsiveModal>
  )
}
