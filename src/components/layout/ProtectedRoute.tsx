import { Navigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth-store'
import { loadSession } from '@/lib/services/auth'

interface Props {
  children: React.ReactNode
  permission?: string | string[]
}

/**
 * ProtectedRoute — حارس المسارات
 * إذا لم يكن مسجلاً → Login
 * إذا لا يملك الصلاحية → Unauthorized
 * يدعم صلاحية واحدة (string) أو مصفوفة (string[]) بتقييم OR
 */
export function ProtectedRoute({ children, permission }: Props) {
  const profile = useAuthStore(s => s.profile)
  const isInitialized = useAuthStore(s => s.isInitialized)
  const hasSession = useAuthStore(s => s.hasSession)
  const profileLoadError = useAuthStore(s => s.profileLoadError)
  const can = useAuthStore(s => s.can)
  const canAny = useAuthStore(s => s.canAny)
  const location = useLocation()

  // انتظار التهيئة الأولى فقط — إذا عندنا profile من الـ cache لا نُظهر spinner
  // isLoading في الخلفية (إعادة تحقق) لا يوقف عرض المحتوى
  if (!isInitialized && !profile) {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        minHeight: '100vh', background: 'var(--bg-app)',
      }}>
        <div className="spinner-lg spinner" />
      </div>
    )
  }

  if (hasSession && !profile && profileLoadError) {
    return (
      <div style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: '12px',
        minHeight: '100vh',
        padding: '24px',
        background: 'var(--bg-app)',
        textAlign: 'center',
      }}>
        <div style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>
          تعذر تحميل بيانات المستخدم مؤقتاً
        </div>
        <div style={{ color: 'var(--text-muted)', maxWidth: '420px' }}>
          الجلسة ما زالت موجودة، لكن تعذر جلب الملف الشخصي أو الصلاحيات الآن. حاول مرة أخرى.
        </div>
        <button
          type="button"
          className="btn btn-primary"
          onClick={() => { void loadSession() }}
        >
          إعادة المحاولة
        </button>
      </div>
    )
  }

  // غير مسجل
  if (!profile) {
    return <Navigate to="/login" state={{ from: location }} replace />
  }

  // مسجل لكن بدون صلاحية
  if (permission) {
    const hasAccess = Array.isArray(permission) ? canAny(permission) : can(permission)
    if (!hasAccess) return <Navigate to="/unauthorized" replace />
  }

  return <>{children}</>
}
