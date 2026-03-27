import { AlertTriangle, Trash2, Info } from 'lucide-react'
import ResponsiveModal from './ResponsiveModal'
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
  danger:  <Trash2 size={22} style={{ color: 'var(--color-danger)' }} />,
  warning: <AlertTriangle size={22} style={{ color: 'var(--color-warning)' }} />,
  info:    <Info size={22} style={{ color: 'var(--color-info)' }} />,
}

const iconBg = {
  danger:  'color-mix(in srgb, var(--color-danger) 12%, transparent)',
  warning: 'color-mix(in srgb, var(--color-warning) 12%, transparent)',
  info:    'color-mix(in srgb, var(--color-info) 12%, transparent)',
}

/**
 * ConfirmDialog — مربع تأكيد للعمليات الخطرة
 * يُعرض كـ Bottom Sheet على الموبايل (ResponsiveModal)
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
    <ResponsiveModal open={open} onClose={onCancel} title="">
      <div style={{ textAlign: 'center', paddingBottom: 8 }}>
        {/* Icon badge */}
        <div style={{
          width: 52, height: 52, borderRadius: '50%',
          background: iconBg[variant],
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          margin: '0 auto 14px',
        }}>
          {icons[variant]}
        </div>

        <h3 style={{ fontSize: 17, fontWeight: 700, marginBottom: 8, margin: '0 0 8px' }}>
          {title}
        </h3>
        <p style={{
          fontSize: 13, color: 'var(--text-secondary)', lineHeight: 1.65,
          margin: '0 0 20px', whiteSpace: 'pre-line',
        }}>
          {message}
        </p>

        {/* Action buttons — full-width stacked on mobile */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <Button
            variant={variant === 'info' ? 'primary' : 'danger'}
            onClick={onConfirm}
            loading={loading}
            style={{ width: '100%', justifyContent: 'center', padding: '12px 16px', fontSize: 15 }}
          >
            {confirmText}
          </Button>
          <Button
            variant="ghost"
            onClick={onCancel}
            disabled={loading}
            style={{ width: '100%', justifyContent: 'center', padding: '11px 16px', fontSize: 14 }}
          >
            {cancelText}
          </Button>
        </div>
      </div>
    </ResponsiveModal>
  )
}
