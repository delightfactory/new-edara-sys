import { type ReactNode, useCallback, useId, useRef } from 'react'
import { X } from 'lucide-react'
import { cn } from '@/lib/utils/helpers'
import { useDialogLifecycle } from '@/hooks/useDialogLifecycle'

interface ModalProps {
  open: boolean
  onClose: () => void
  title?: string
  size?: 'sm' | 'md' | 'lg'
  children: ReactNode
  footer?: ReactNode
  /** منع الإغلاق عند الضغط على الخلفية (للنماذج المعقدة) */
  disableOverlayClose?: boolean
  ariaLabelledBy?: string
  ariaLabel?: string
}

/**
 * Modal — مكون نافذة منبثقة موحد
 * يغلف modal-overlay + modal-box + modal-header + modal-body + modal-footer
 * يغلق بـ Escape أو الضغط على الخلفية
 */
export default function Modal({ open, onClose, title, size = 'md', children, footer, disableOverlayClose = false, ariaLabelledBy, ariaLabel }: ModalProps) {
  const contentRef = useRef<HTMLDivElement>(null)
  const titleId = useId()
  const onFocusCapture = useDialogLifecycle(open, contentRef, onClose)
  const requestClose = useCallback(() => {
    onClose()
  }, [onClose])

  if (!open) return null

  return (
    <div
      className="modal-overlay"
      onClick={disableOverlayClose ? undefined : requestClose}
    >
      <div
        ref={contentRef}
        className={cn('modal-box', `modal-${size}`)}
        onClick={e => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby={ariaLabelledBy ?? (title ? titleId : undefined)}
        aria-label={ariaLabel}
        tabIndex={-1}
        onFocusCapture={onFocusCapture}
      >
        {title && (
          <div className="modal-header">
            <span id={titleId} className="modal-title">{title}</span>
            <button type="button" className="btn btn-ghost btn-icon" onClick={onClose} aria-label="إغلاق">
              <X size={18} />
            </button>
          </div>
        )}
        <div className="modal-body">
          {children}
        </div>
        {footer && (
          <div className="modal-footer">
            {footer}
          </div>
        )}
      </div>
    </div>
  )
}
