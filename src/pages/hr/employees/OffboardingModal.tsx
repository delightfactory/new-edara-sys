import { useState } from 'react'
import { AlertTriangle, Calendar, FileText } from 'lucide-react'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'
import Input from '@/components/ui/Input'
import { useQueryClient } from '@tanstack/react-query'
import { useUpdateEmployee } from '@/hooks/useQueryHooks'
import { toast } from 'sonner'

interface OffboardingModalProps {
  open: boolean
  onClose: () => void
  employeeId: string
  employeeName: string
}

export default function OffboardingModal({ open, onClose, employeeId, employeeName }: OffboardingModalProps) {
  const [terminationDate, setTerminationDate] = useState(new Date().toISOString().split('T')[0])
  const [terminationReason, setTerminationReason] = useState('')

  const updateMut = useUpdateEmployee()
  const qc = useQueryClient()

  const handleTerminate = async () => {
    if (!terminationDate || !terminationReason.trim()) {
      toast.error('تاريخ الإنهاء وسبب الإنهاء مطلوبان')
      return
    }

    try {
      await updateMut.mutateAsync({
        id: employeeId,
        input: {
          status: 'terminated',
          termination_date: terminationDate,
          termination_reason: terminationReason
        }
      })
      toast.success('تم إنهاء خدمة الموظف بنجاح')
      qc.invalidateQueries({ queryKey: ['hr-employee', employeeId] })
      onClose()
    } catch (e: any) {
      toast.error(e.message || 'فشل إنهاء الخدمة')
    }
  }

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      title="إنهاء الخدمة (Offboarding)"
      size="sm"
      disableOverlayClose={updateMut.isPending}
      footer={
        <div style={{ display: 'flex', gap: 'var(--space-2)', width: '100%' }}>
          <Button variant="secondary" onClick={onClose} disabled={updateMut.isPending} style={{ flex: 1 }}>تراجع</Button>
          <Button 
            variant="danger" 
            onClick={handleTerminate} 
            loading={updateMut.isPending} 
            disabled={!terminationDate || !terminationReason}
            style={{ flex: 2 }}
          >
            تأكيد إنهاء الخدمة
          </Button>
        </div>
      }
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        
        {/* Warning Context */}
        <div style={{ 
          background: 'var(--bg-danger-light)', 
          color: 'var(--color-danger)', 
          padding: 'var(--space-4)', 
          borderRadius: 'var(--radius-md)', 
          display: 'flex', 
          gap: 'var(--space-3)',
          alignItems: 'flex-start'
        }}>
          <AlertTriangle size={20} style={{ flexShrink: 0, marginTop: 2 }} />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
            <strong style={{ fontSize: 'var(--text-md)' }}>تحذير إنهاء الخدمة</strong>
            <span style={{ fontSize: 'var(--text-sm)', opacity: 0.9, lineHeight: 1.5 }}>
              هل أنت متأكد من رغبتك في إنهاء خدمة <strong style={{color: 'var(--color-danger-dark)'}}>{employeeName}</strong>؟
              هذا الإجراء سيقوم بإلغاء ربط حساب النظام فوراً (إن وُجد) وسينقل الموظف إلى حالة "منتهي الخدمة" مع الحفاظ التام على كامل سجلاته المالية والحضورية السابقة.
            </span>
          </div>
        </div>

        {/* Inputs */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <div>
            <label style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', fontSize: 'var(--text-sm)', fontWeight: 600, marginBottom: 'var(--space-1)', color: 'var(--text-secondary)' }}>
              <Calendar size={14} /> آخر يوم عمل (تاريخ الإنهاء)
            </label>
            <Input 
              type="date" 
              required 
              value={terminationDate} 
              onChange={e => setTerminationDate(e.target.value)} 
              disabled={updateMut.isPending}
            />
          </div>

          <div>
            <label style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', fontSize: 'var(--text-sm)', fontWeight: 600, marginBottom: 'var(--space-1)', color: 'var(--text-secondary)' }}>
              <FileText size={14} /> سبب إنهاء الخدمة
            </label>
            <Input 
              required 
              value={terminationReason} 
              onChange={e => setTerminationReason(e.target.value)} 
              placeholder="استقالة، نهاية عقد، إقالة، ظروف خاصة..."
              disabled={updateMut.isPending}
            />
          </div>
        </div>

      </div>
    </ResponsiveModal>
  )
}
