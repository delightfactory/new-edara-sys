/**
 * ScrollToTop — زر العودة للأعلى
 *
 * أفضل الممارسات المطبّقة:
 * ──────────────────────────────────────────────────────────────────────────
 * 1. يظهر فقط بعد التمرير ≥ 300px  (Progressive Disclosure)
 * 2. RTL-native: inset-inline-start = يسار في العربية (بعيداً عن FAB)
 * 3. فوق Bottom Nav بمسافة صحيحة (CSS custom properties)
 * 4. انيميشن GPU: transform + opacity (لا يُسبّب Reflow)
 * 5. will-change: transform, opacity (يُخبر المتصفح مسبقاً)
 * 6. prefers-reduced-motion: يُقلّل الحركة عند الحاجة
 * 7. Throttle بـ requestAnimationFrame (لا overhead على الـ scroll)
 * 8. 48px touch target (WCAG 2.5.5 — حجم لمس موصى به)
 * 9. aria-label + role للإمكانية الوصولية
 * 10. تنظيف الـ listener عند unmount (لا memory leaks)
 */

import { useState, useEffect, useCallback, useRef } from 'react'
import { ChevronUp } from 'lucide-react'

const SCROLL_THRESHOLD = 300  // px — بعد كم نُظهر الزر

export default function ScrollToTopButton() {
  const [visible, setVisible] = useState(false)
  const rafRef    = useRef<number | null>(null)
  const lastScroll = useRef(0)

  const handleScroll = useCallback(() => {
    // Throttle via requestAnimationFrame — ~60fps بدون overhead
    if (rafRef.current) return
    rafRef.current = requestAnimationFrame(() => {
      const scrollY = window.scrollY
      // hysteresis: 20px فرق لمنع التذبذب عند الحافة
      if (scrollY > SCROLL_THRESHOLD && !visible) setVisible(true)
      if (scrollY < SCROLL_THRESHOLD - 20  && visible) setVisible(false)
      lastScroll.current = scrollY
      rafRef.current = null
    })
  }, [visible])

  useEffect(() => {
    window.addEventListener('scroll', handleScroll, { passive: true })
    return () => {
      window.removeEventListener('scroll', handleScroll)
      if (rafRef.current) cancelAnimationFrame(rafRef.current)
    }
  }, [handleScroll])

  const scrollToTop = () => {
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  return (
    <>
      <button
        type="button"
        aria-label="العودة إلى أعلى الصفحة"
        onClick={scrollToTop}
        className={`stt-btn${visible ? ' stt-visible' : ''}`}
        tabIndex={visible ? 0 : -1}
      >
        <ChevronUp size={20} strokeWidth={2.5} />
      </button>

      <style>{`
        /* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ SCROLL TO TOP */
        .stt-btn {
          /* الموضع: ثابت، يسار الشاشة (RTL = بعيداً عن FAB اليمين) */
          position: fixed;
          inset-inline-start: var(--space-4, 1rem);

          /* فوق Bottom Nav، تحت FAB مباشرةً */
          /* --bottom-nav-height = 64px (من design rules) */
          bottom: calc(var(--bottom-nav-height, 64px) + var(--space-4, 1rem));

          /* الحجم — 44px minimum (WCAG) + مساحة بصرية */
          width:  48px;
          height: 48px;
          border-radius: 50%;

          /* التصميم — glassmorphism خفيف */
          background: var(--bg-surface, #fff);
          color: var(--color-primary, #2563eb);
          border: 1.5px solid var(--border-default, #e2e8f0);
          box-shadow:
            0 4px 12px rgba(0,0,0,0.12),
            0 1px 3px  rgba(0,0,0,0.08);
          backdrop-filter: blur(8px);
          -webkit-backdrop-filter: blur(8px);

          /* Layout */
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          outline: none;

          /* انيميشن: مخفي بشكل افتراضي */
          opacity: 0;
          transform: translateY(12px) scale(0.85);
          pointer-events: none;
          will-change: transform, opacity;
          transition:
            opacity      0.22s cubic-bezier(0.4, 0, 0.2, 1),
            transform    0.22s cubic-bezier(0.4, 0, 0.2, 1),
            box-shadow   0.15s ease,
            background   0.15s ease;

          /* Z-index: بين FAB وBottom Nav */
          z-index: calc(var(--z-fab, 160) - 10);
        }

        /* حالة الظهور */
        .stt-btn.stt-visible {
          opacity: 1;
          transform: translateY(0) scale(1);
          pointer-events: auto;
        }

        /* Hover */
        .stt-btn:hover {
          background: var(--color-primary-light, rgba(37,99,235,0.08));
          border-color: var(--color-primary, #2563eb);
          box-shadow:
            0 6px 20px rgba(37,99,235,0.18),
            0 2px 6px  rgba(37,99,235,0.12);
          transform: translateY(-2px) scale(1.05);
        }

        /* Active / Press */
        .stt-btn:active {
          transform: scale(0.94);
          box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }

        /* Focus ring (keyboard nav) */
        .stt-btn:focus-visible {
          box-shadow:
            0 0 0 3px var(--color-primary-light, rgba(37,99,235,0.2)),
            0 4px 12px rgba(0,0,0,0.12);
          border-color: var(--color-primary, #2563eb);
        }

        /* على الديسكتوب: لا Bottom Nav، ارفعه قليلاً */
        @media (min-width: 769px) {
          .stt-btn {
            bottom: var(--space-8, 2rem);
            width:  42px;
            height: 42px;
          }
        }

        /* prefers-reduced-motion: انيميشن فوري بدون حركة */
        @media (prefers-reduced-motion: reduce) {
          .stt-btn {
            transition:
              opacity   0.1s linear,
              transform 0.1s linear;
          }
        }
        /* ═══ HIDE IN PRINT + PREVIEW ROUTE ═══════════════════════ */
        /* Never shown when printing any page */
        @media print {
          .stt-btn { display: none !important; }
        }
        /* Never shown inside the document preview page */
        .is-preview-route .stt-btn {
          display: none !important;
        }
      `}</style>
    </>
  )
}
