import { type ReactNode, useCallback, useEffect } from 'react'
import { X } from 'lucide-react'
import { cn } from '@/lib/utils/helpers'
import { isFilePicking } from '@/lib/utils/file-picking-guard'

interface ModalProps {
  open: boolean
  onClose: () => void
  title?: string
  size?: 'sm' | 'md' | 'lg'
  children: ReactNode
  footer?: ReactNode
  /** منع الإغلاق عند الضغط على الخلفية (للنماذج المعقدة) */
  disableOverlayClose?: boolean
}

/**
 * Modal — مكون نافذة منبثقة موحد
 * يغلف modal-overlay + modal-box + modal-header + modal-body + modal-footer
 * يغلق بـ Escape أو الضغط على الخلفية
 */
export default function Modal({ open, onClose, title, size = 'md', children, footer, disableOverlayClose = false }: ModalProps) {
  const requestClose = useCallback(() => {
    if (isFilePicking()) return
    onClose()
  }, [onClose])

  // إغلاق بمفتاح Escape
  useEffect(() => {
    if (!open) return
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') requestClose()
    }
    document.addEventListener('keydown', handler)
    return () => document.removeEventListener('keydown', handler)
  }, [open, requestClose])

  // منع scroll الصفحة خلف الـ modal
  useEffect(() => {
    if (open) {
      document.body.style.overflow = 'hidden'
    }
    return () => { document.body.style.overflow = '' }
  }, [open])

  if (!open) return null

  return (
    <div
      className="modal-overlay"
      onClickCapture={e => {
        if (isFilePicking()) { e.stopPropagation(); e.preventDefault() }
      }}
      onClick={disableOverlayClose ? undefined : requestClose}
    >
      <div
        className={cn('modal-box', `modal-${size}`)}
        onClick={e => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
      >
        {title && (
          <div className="modal-header">
            <span className="modal-title">{title}</span>
            <button className="btn btn-ghost btn-icon" onClick={onClose} aria-label="إغلاق">
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
