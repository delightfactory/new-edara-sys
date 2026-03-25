import { AlertTriangle, Trash2, Info } from 'lucide-react'
import Modal from './Modal'
import Button from './Button'

interface ConfirmDialogProps {
  open: boolean
  onConfirm: () => void
  onCancel: () => void
  title?: string
  message?: string
  confirmText?: string
  cancelText?: string
  variant?: 'danger' | 'warning' | 'info'
  loading?: boolean
}

const icons = {
  danger: <Trash2 size={24} style={{ color: 'var(--color-danger)' }} />,
  warning: <AlertTriangle size={24} style={{ color: 'var(--color-warning)' }} />,
  info: <Info size={24} style={{ color: 'var(--color-info)' }} />,
}

/**
 * ConfirmDialog — مربع تأكيد للعمليات الخطرة
 * بديل لـ window.confirm() مع تصميم احترافي
 */
export default function ConfirmDialog({
  open,
  onConfirm,
  onCancel,
  title = 'تأكيد',
  message = 'هل أنت متأكد من هذا الإجراء؟',
  confirmText = 'تأكيد',
  cancelText = 'إلغاء',
  variant = 'danger',
  loading = false,
}: ConfirmDialogProps) {
  return (
    <Modal open={open} onClose={onCancel} size="sm">
      <div style={{ textAlign: 'center', padding: 'var(--space-4) 0' }}>
        <div style={{
          width: 56, height: 56, borderRadius: 'var(--radius-full)',
          background: variant === 'danger' ? 'var(--color-danger-light)' :
                      variant === 'warning' ? 'var(--color-warning-light)' : 'var(--color-info-light)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          margin: '0 auto var(--space-4)',
        }}>
          {icons[variant]}
        </div>
        <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-2)' }}>
          {title}
        </h3>
        <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', lineHeight: 1.6 }}>
          {message}
        </p>
      </div>
      <div style={{
        display: 'flex', gap: 'var(--space-3)', justifyContent: 'center',
        paddingTop: 'var(--space-4)', borderTop: '1px solid var(--border-primary)',
      }}>
        <Button variant="secondary" onClick={onCancel} disabled={loading}>
          {cancelText}
        </Button>
        <Button variant={variant === 'info' ? 'primary' : 'danger'} onClick={onConfirm} loading={loading}>
          {confirmText}
        </Button>
      </div>
    </Modal>
  )
}
