import { type ReactNode, useEffect, useRef, useState } from 'react'
import { X } from 'lucide-react'
import { useModalStack } from '@/hooks/useModalStack'

interface ResponsiveModalProps {
  open: boolean
  onClose: () => void
  title?: string
  size?: 'sm' | 'md' | 'lg'
  children: ReactNode
  footer?: ReactNode
  /**
   * Prevent closing when clicking the backdrop.
   * Useful for forms with unsaved data.
   */
  disableOverlayClose?: boolean
}

/**
 * ResponsiveModal — Smart adaptive modal component.
 *
 * - MOBILE (≤768px): Renders as a Bottom Sheet sliding up from the bottom.
 *   Includes a drag handle, safe-area padding, and swipe-to-close feeling.
 * - DESKTOP (≥769px): Renders as a traditional centered Modal.
 *
 * Both modes:
 * - Dark backdrop with `--z-overlay` (190)
 * - Modal/Sheet itself on `--z-modal` (200)
 * - Keyboard: Escape closes
 * - Body scroll is locked while open
 * - aria-modal="true" + focus management
 *
 * Usage:
 * ```tsx
 * <ResponsiveModal open={open} onClose={close} title="تأكيد الطلب">
 *   <p>هل أنت متأكد؟</p>
 * </ResponsiveModal>
 * ```
 */
export default function ResponsiveModal({
  open,
  onClose,
  title,
  size = 'md',
  children,
  footer,
  disableOverlayClose = false,
}: ResponsiveModalProps) {
  const [isVisible, setIsVisible] = useState(false)
  const contentRef = useRef<HTMLDivElement>(null)
  const { push, pop } = useModalStack()

  // Track modal depth so FAB can auto-hide
  useEffect(() => {
    if (open) { push() } else { pop() }
    return () => { if (open) pop() }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  // Stagger open animation
  useEffect(() => {
    if (open) {
      // Tiny delay for CSS transition to fire
      requestAnimationFrame(() => setIsVisible(true))
    } else {
      setIsVisible(false)
    }
  }, [open])

  // Escape key
  useEffect(() => {
    if (!open) return
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', handler)
    return () => document.removeEventListener('keydown', handler)
  }, [open, onClose])

  // Lock body scroll
  useEffect(() => {
    if (open) document.body.style.overflow = 'hidden'
    return () => { document.body.style.overflow = '' }
  }, [open])

  // Focus the dialog on open
  useEffect(() => {
    if (open && contentRef.current) {
      contentRef.current.focus()
    }
  }, [open])

  if (!open) return null

  const sizeClass = `rmodal-box--${size}`

  return (
    <div
      className={`rmodal-overlay ${isVisible ? 'rmodal-overlay--visible' : ''}`}
      onClick={disableOverlayClose ? undefined : onClose}
      aria-hidden="true"
    >
      <div
        ref={contentRef}
        className={`rmodal-box ${sizeClass} ${isVisible ? 'rmodal-box--visible' : ''}`}
        onClick={e => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby={title ? 'rmodal-title' : undefined}
        tabIndex={-1}
      >
        {/* Drag handle — mobile only visual cue */}
        <div className="rmodal-handle" aria-hidden="true" />

        {title && (
          <div className="rmodal-header">
            <span id="rmodal-title" className="rmodal-title">{title}</span>
            <button
              className="btn btn-ghost btn-icon"
              onClick={onClose}
              aria-label="إغلاق"
              type="button"
            >
              <X size={18} />
            </button>
          </div>
        )}

        <div className="rmodal-body">
          {children}
        </div>

        {footer && (
          <div className="rmodal-footer">
            {footer}
          </div>
        )}
      </div>

      <style>{`
        /* ── Backdrop ──────────────────────────────────── */
        .rmodal-overlay {
          position: fixed;
          inset: 0;
          background: var(--overlay-bg);
          backdrop-filter: blur(4px);
          -webkit-backdrop-filter: blur(4px);
          z-index: var(--z-overlay);
          display: flex;
          align-items: center;
          justify-content: center;
          padding: var(--space-4);
          opacity: 0;
          transition: opacity 0.22s ease;
        }
        .rmodal-overlay--visible {
          opacity: 1;
        }

        /* ── Desktop Modal Box ──────────────────────────── */
        .rmodal-box {
          background: var(--modal-bg);
          border-radius: var(--radius-lg);
          box-shadow: var(--shadow-xl);
          width: 100%;
          max-height: 90vh;
          overflow-y: auto;
          outline: none;
          transform: translateY(12px) scale(0.98);
          transition: transform 0.25s cubic-bezier(0.34, 1.56, 0.64, 1),
                      opacity 0.2s ease;
          opacity: 0;
          z-index: var(--z-modal);
          position: relative;
        }
        .rmodal-box--visible {
          transform: translateY(0) scale(1);
          opacity: 1;
        }
        .rmodal-box--sm { max-width: 420px; }
        .rmodal-box--md { max-width: 560px; }
        .rmodal-box--lg { max-width: 720px; }

        /* Hide drag handle on desktop */
        .rmodal-handle { display: none; }

        /* ── Modal Internals ─────────────────────────────── */
        .rmodal-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: var(--space-5) var(--space-6);
          border-bottom: 1px solid var(--border-primary);
        }
        .rmodal-title {
          font-size: var(--text-lg);
          font-weight: 700;
          color: var(--text-primary);
        }
        .rmodal-body {
          padding: var(--space-6);
        }
        .rmodal-footer {
          display: flex;
          gap: var(--space-3);
          justify-content: flex-end;
          padding: var(--space-4) var(--space-6);
          border-top: 1px solid var(--border-primary);
          background: var(--bg-surface-2);
          border-radius: 0 0 var(--radius-lg) var(--radius-lg);
        }

        /* ── Mobile — Bottom Sheet ──────────────────────── */
        @media (max-width: 768px) {
          .rmodal-overlay {
            align-items: flex-end;
            padding: 0;
          }

          .rmodal-box {
            border-radius: var(--sheet-radius);
            max-width: 100%;
            max-height: 92dvh;
            width: 100%;
            transform: translateY(100%);
            transition: transform 0.35s cubic-bezier(0.32, 0.72, 0, 1);
            opacity: 1; /* Opacity always 1 on mobile — slide handles reveal */
          }

          .rmodal-box--visible {
            transform: translateY(0);
            opacity: 1;
          }

          /* Drag handle pill */
          .rmodal-handle {
            display: block;
            width: 36px;
            height: 4px;
            background: var(--sheet-handle-color);
            border-radius: var(--radius-full);
            margin: var(--space-3) auto var(--space-1);
            flex-shrink: 0;
          }

          .rmodal-header {
            padding: var(--space-3) var(--space-4);
          }
          .rmodal-body {
            padding: var(--space-4);
          }
          .rmodal-footer {
            padding: var(--space-3) var(--space-4);
            padding-bottom: calc(var(--space-4) + env(safe-area-inset-bottom, 0px));
          }

          /* Mobile sheet sizes ignored — always full width */
          .rmodal-box--sm,
          .rmodal-box--md,
          .rmodal-box--lg {
            max-width: 100%;
          }
        }
      `}</style>
    </div>
  )
}
