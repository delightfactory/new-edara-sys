import { useMemo } from 'react'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Badge from '@/components/ui/Badge'
import { Printer, X } from 'lucide-react'
import Button from '@/components/ui/Button'
import type { EmployeePayslipSummary } from '@/lib/types/hr'

interface PayslipViewerModalProps {
  open: boolean
  onClose: () => void
  payslip: EmployeePayslipSummary | null
  employeeName: string
  employeeNumber?: string
}

const fmtCurrency = (n: number) =>
  Number(n).toLocaleString('ar-EG-u-nu-latn', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' ج.م'

export default function PayslipViewerModal({ open, onClose, payslip, employeeName, employeeNumber }: PayslipViewerModalProps) {
  
  const statusColors = {
    approved: 'var(--color-warning)',
    paid: 'var(--color-success)',
  }
  const statusLabels = {
    approved: 'معتمد (قيد الصرف)',
    paid: 'مدفوع'
  }

  if (!payslip) return null

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      title={`تفاصيل راتب شهر ${payslip.period_name}`}
      size="md"
      footer={
        <div style={{ display: 'flex', gap: 'var(--space-2)', width: '100%', justifyContent: 'space-between' }}>
          <Button variant="secondary" onClick={onClose} icon={<X size={14} />}>
            إغلاق
          </Button>
          <Button variant="secondary" disabled title="سيتم تفعيل الطباعة لاحقاً" icon={<Printer size={14} />}>
            طباعة
          </Button>
        </div>
      }
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-6)', fontFamily: 'var(--font-sans)', padding: 'var(--space-2)' }}>
        
        {/* Header Info */}
        <div style={{ 
          display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start',
          borderBottom: '1px dashed var(--border-color)', paddingBottom: 'var(--space-4)'
        }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
            <h3 style={{ margin: 0, fontSize: 'var(--text-lg)', fontWeight: 800 }}>{employeeName}</h3>
            {employeeNumber && <span style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>الرقم الوظيفي: {employeeNumber}</span>}
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 'var(--space-2)' }}>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)' }}>حالة المسير</span>
            <Badge variant={payslip.run_status === 'paid' ? 'success' : 'warning'}>
              {statusLabels[payslip.run_status]}
            </Badge>
          </div>
        </div>

        {/* Net Salary Highlight */}
        <div style={{
          background: 'var(--bg-surface-2)',
          borderRadius: 'var(--radius-lg)',
          padding: 'var(--space-4)',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          boxShadow: 'var(--shadow-sm)',
          border: '1px solid var(--border-color)'
        }}>
          <span style={{ fontSize: 'var(--text-md)', fontWeight: 700, color: 'var(--text-secondary)' }}>صافي الراتب المستحق</span>
          <span style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--color-primary)' }}>
            {fmtCurrency(payslip.net_salary)}
          </span>
        </div>

        {/* Breakdown Grid */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-5)' }}>
          
          {/* Earnings */}
          <div>
            <h4 style={{ margin: '0 0 var(--space-3)', color: 'var(--color-success)', fontSize: 'var(--text-sm)', fontWeight: 700, borderBottom: '2px solid var(--color-success)', paddingBottom: 'var(--space-2)', display: 'inline-block' }}>
              المستحقات
            </h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              <Row label="الراتب الأساسي" value={payslip.base_salary} />
              
              {payslip.transport_allowance > 0 && <Row label="بدل نقل" value={payslip.transport_allowance} />}
              {payslip.housing_allowance > 0 && <Row label="بدل سكن" value={payslip.housing_allowance} />}
              {payslip.other_allowances > 0 && <Row label="بدلات أخرى" value={payslip.other_allowances} />}
              
              {payslip.overtime_amount > 0 && <Row label="العمل الإضافي" value={payslip.overtime_amount} />}
              {payslip.commission_amount > 0 && <Row label="عمولات" value={payslip.commission_amount} />}
              {payslip.bonus_amount > 0 && <Row label="مكافآت" value={payslip.bonus_amount} />}
              
              <div style={{ borderTop: '1px solid var(--border-color)', margin: 'var(--space-2) 0' }} />
              <Row label="إجمالي المستحقات" value={payslip.base_salary + payslip.total_allowances} bold color="var(--color-success)" />
            </div>
          </div>

          {/* Deductions */}
          <div>
            <h4 style={{ margin: '0 0 var(--space-3)', color: 'var(--color-danger)', fontSize: 'var(--text-sm)', fontWeight: 700, borderBottom: '2px solid var(--color-danger)', paddingBottom: 'var(--space-2)', display: 'inline-block' }}>
              الاستقطاعات
            </h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              {payslip.absence_deduction > 0 && <Row label="خصم الغياب" value={payslip.absence_deduction} />}
              {payslip.penalty_deduction > 0 && <Row label="جزاءات إدارية" value={payslip.penalty_deduction} />}
              {payslip.advance_deduction > 0 && <Row label="أقساط سلف" value={payslip.advance_deduction} />}
              {payslip.social_insurance > 0 && <Row label="تأمينات اجتماعية" value={payslip.social_insurance} />}
              {payslip.health_insurance > 0 && <Row label="تأمين طبي" value={payslip.health_insurance} />}
              {payslip.other_deductions > 0 && <Row label="استقطاعات أخرى" value={payslip.other_deductions} />}
              
              {payslip.total_deductions === 0 && (
                <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)' }}>لا يوجد استقطاعات</span>
              )}

              {payslip.total_deductions > 0 && (
                <>
                  <div style={{ borderTop: '1px solid var(--border-color)', margin: 'var(--space-2) 0' }} />
                  <Row label="إجمالي الاستقطاعات" value={payslip.total_deductions} bold color="var(--color-danger)" />
                </>
              )}
            </div>
          </div>

        </div>

      </div>
    </ResponsiveModal>
  )
}

function Row({ label, value, bold = false, color }: { label: string; value: number; bold?: boolean; color?: string }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: 'var(--text-sm)' }}>
      <span style={{ color: bold ? 'var(--text-primary)' : 'var(--text-secondary)', fontWeight: bold ? 700 : 500 }}>{label}</span>
      <span style={{ fontWeight: bold ? 700 : 600, color: color || 'var(--text-primary)' }}>{fmtCurrency(value)}</span>
    </div>
  )
}
