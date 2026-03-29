import { useState, useEffect, useRef } from 'react'
import { Download, X, Smartphone } from 'lucide-react'

interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

const DISMISS_KEY = 'edara-install-dismissed'
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) && !(window as unknown as { MSStream?: unknown }).MSStream

/**
 * InstallBanner — دعوة تثبيت التطبيق على الهاتف
 * يظهر فقط بعد أن يكون المستخدم قد تنقّل لصفحة ثانية (engagement حقيقي)
 * لا يعرض إذا رفض المستخدم من قبل (localStorage)
 * يوفر تعليمات خاصة لمستخدمي أجهزة آبل
 */
export default function InstallBanner() {
  const [show, setShow] = useState(false)
  const [isInstalled, setIsInstalled] = useState(false)
  const deferredPrompt = useRef<BeforeInstallPromptEvent | null>(null)
  const pageVisits = useRef(0)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)

  // لا تعرض إذا سبق الرفض أو التثبيت
  useEffect(() => {
    if (localStorage.getItem(DISMISS_KEY)) return
    if (window.matchMedia('(display-mode: standalone)').matches) {
      setIsInstalled(true)
      return
    }

    // التقاط حدث التثبيت من المتصفح
    const handlePrompt = (e: Event) => {
      e.preventDefault()
      deferredPrompt.current = e as BeforeInstallPromptEvent
    }

    const handleInstalled = () => setIsInstalled(true)

    window.addEventListener('beforeinstallprompt', handlePrompt)
    window.addEventListener('appinstalled', handleInstalled)

    return () => {
      window.removeEventListener('beforeinstallprompt', handlePrompt)
      window.removeEventListener('appinstalled', handleInstalled)
    }
  }, [])

  // نظهر الدعوة فقط بعد engagement حقيقي (صفحة ثانية + 30 ثانية)
  useEffect(() => {
    if (isInstalled || localStorage.getItem(DISMISS_KEY)) return

    pageVisits.current += 1

    // نبدأ العداد فقط من الصفحة الثانية
    if (pageVisits.current < 2) return

    // iOS — لا يوجد beforeinstallprompt، نعرض تعليمات يدوية
    if (isIOS) {
      timer.current = setTimeout(() => setShow(true), 30_000)
      return
    }

    // Android/Desktop — ننتظر حتى يصبح الـ prompt متاحاً
    const checkAndShow = () => {
      if (deferredPrompt.current) {
        timer.current = setTimeout(() => setShow(true), 30_000)
      }
    }
    checkAndShow()

    return () => {
      if (timer.current) clearTimeout(timer.current)
    }
  }, [isInstalled])  // FIX-AUDIT-05: dependency array — يمنع تشغيل الأثر بعد كل render

  const handleInstall = async () => {
    if (!deferredPrompt.current) return
    await deferredPrompt.current.prompt()
    const { outcome } = await deferredPrompt.current.userChoice
    if (outcome === 'accepted') {
      setIsInstalled(true)
    }
    deferredPrompt.current = null
    setShow(false)
  }

  const handleDismiss = () => {
    setShow(false)
    localStorage.setItem(DISMISS_KEY, '1')
  }

  if (!show || isInstalled) return null

  return (
    <>
      {/* تعليمات آبل */}
      {isIOS ? (
        <div style={bannerStyle}>
          <div style={{ display: 'flex', gap: '12px', alignItems: 'flex-start', flex: 1 }}>
            <Smartphone size={20} style={{ flexShrink: 0, marginTop: 2 }} />
            <div>
              <p style={titleStyle}>تثبيت تطبيق إدارة</p>
              <p style={subStyle}>اضغط على زر المشاركة ← ثم "إضافة إلى الشاشة الرئيسية"</p>
            </div>
          </div>
          <button onClick={handleDismiss} style={closeStyle} aria-label="إغلاق">
            <X size={16} />
          </button>
        </div>
      ) : (
        /* دعوة التثبيت العادية */
        <div style={bannerStyle}>
          <div style={{ display: 'flex', gap: '12px', alignItems: 'center', flex: 1 }}>
            <Download size={20} style={{ flexShrink: 0 }} />
            <div>
              <p style={titleStyle}>ثبّت التطبيق على هاتفك</p>
              <p style={subStyle}>تجربة أسرع وأسهل بدون متصفح</p>
            </div>
          </div>
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <button onClick={handleDismiss} style={laterStyle}>لاحقاً</button>
            <button onClick={handleInstall} style={installStyle}>تثبيت</button>
          </div>
        </div>
      )}
    </>
  )
}

// ── الأنماط ──
const bannerStyle: React.CSSProperties = {
  position: 'fixed',
  bottom: 'calc(var(--bottom-nav-height, 64px) + 12px)',
  left: '12px',
  right: '12px',
  zIndex: 8000,
  background: 'var(--bg-surface, #fff)',
  border: '1px solid var(--border-primary, #e5e7eb)',
  borderRadius: '14px',
  padding: '14px 16px',
  display: 'flex',
  alignItems: 'center',
  gap: '12px',
  boxShadow: '0 8px 32px rgba(0,0,0,0.12), 0 2px 8px rgba(0,0,0,0.08)',
  fontFamily: 'var(--font-sans, inherit)',
  animation: 'ib-slide-up 0.3s cubic-bezier(0.34,1.56,0.64,1)',
}
const titleStyle: React.CSSProperties = {
  fontSize: '13.5px', fontWeight: 700,
  color: 'var(--text-primary, #111827)', margin: 0,
}
const subStyle: React.CSSProperties = {
  fontSize: '12px', color: 'var(--text-secondary, #6b7280)',
  margin: '3px 0 0',
}
const closeStyle: React.CSSProperties = {
  display: 'flex', alignItems: 'center', justifyContent: 'center',
  width: 30, height: 30, borderRadius: 8,
  border: 'none', background: 'var(--bg-hover, rgba(0,0,0,0.05))',
  color: 'var(--text-muted, #9ca3af)',
  cursor: 'pointer', flexShrink: 0,
}
const laterStyle: React.CSSProperties = {
  padding: '7px 12px', borderRadius: 8, border: 'none',
  background: 'none', fontSize: '13px', fontWeight: 500,
  color: 'var(--text-secondary, #6b7280)', cursor: 'pointer',
  fontFamily: 'var(--font-sans, inherit)',
}
const installStyle: React.CSSProperties = {
  padding: '7px 16px', borderRadius: 8, border: 'none',
  background: '#2563eb', color: '#fff',
  fontSize: '13px', fontWeight: 600, cursor: 'pointer',
  fontFamily: 'var(--font-sans, inherit)',
  boxShadow: '0 2px 8px rgba(37,99,235,0.35)',
}
