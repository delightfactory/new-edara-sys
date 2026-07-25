/**
 * CancelGuardModal — نافذة تأكيد الخروج من معالج إنشاء الخطة.
 *
 * تُعرض عند وجود بيانات غير محفوظة والضغط على «إلغاء».
 * تستخدم ResponsiveModal (Bottom Sheet على الموبايل).
 * لا window.confirm.
 */
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'

interface CancelGuardModalProps {
  open: boolean
  isSaving: boolean
  onCancel: () => void
  onConfirmLeave: () => void
}

export default function CancelGuardModal({
  open,
  isSaving,
  onCancel,
  onConfirmLeave,
}: CancelGuardModalProps) {
  return (
    <ResponsiveModal
      open={open}
      onClose={isSaving ? () => undefined : onCancel}
      title="إلغاء إنشاء الخطة"
      size="sm"
      disableOverlayClose={isSaving}
      footer={
        <div className="cgm-footer">
          <Button
            type="button"
            variant="secondary"
            onClick={onCancel}
            disabled={isSaving}
          >
            متابعة التعديل
          </Button>
          <Button
            type="button"
            onClick={onConfirmLeave}
            disabled={isSaving}
            style={{ background: 'var(--color-danger)', borderColor: 'var(--color-danger)' }}
          >
            نعم، إلغاء ورجوع
          </Button>
        </div>
      }
    >
      <div className="cgm-body">
        <p className="cgm-message">
          لديك بيانات غير محفوظة. هل تريد الإلغاء والعودة إلى قائمة خطط الزيارات؟
        </p>
        <p className="cgm-note">
          سيتم فقدان جميع البيانات المدخلة.
        </p>
      </div>

      <style>{`
        .cgm-body {
          display: flex;
          flex-direction: column;
          gap: var(--space-2);
        }
        .cgm-message {
          margin: 0;
          font-size: var(--text-base, 15px);
          line-height: 1.7;
          color: var(--text-primary);
          font-weight: 600;
        }
        .cgm-note {
          margin: 0;
          font-size: var(--text-sm);
          line-height: 1.7;
          color: var(--text-muted);
        }
        .cgm-footer {
          display: flex;
          gap: var(--space-3);
          justify-content: flex-end;
          flex-wrap: wrap;
        }
      `}</style>
    </ResponsiveModal>
  )
}
