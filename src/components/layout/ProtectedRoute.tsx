import { Navigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/stores/auth-store'

interface Props {
  children: React.ReactNode
  permission?: string
}

/**
 * ProtectedRoute — حارس المسارات
 * إذا لم يكن مسجلاً → Login
 * إذا لا يملك الصلاحية → Unauthorized
 */
export function ProtectedRoute({ children, permission }: Props) {
  const profile = useAuthStore(s => s.profile)
  const isInitialized = useAuthStore(s => s.isInitialized)
  const can = useAuthStore(s => s.can)
  const location = useLocation()

  // انتظار التهيئة
  if (!isInitialized) {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        minHeight: '100vh', background: 'var(--bg-app)',
      }}>
        <div className="spinner-lg spinner" />
      </div>
    )
  }

  // غير مسجل
  if (!profile) {
    return <Navigate to="/login" state={{ from: location }} replace />
  }

  // مسجل لكن بدون صلاحية
  if (permission && !can(permission)) {
    return <Navigate to="/unauthorized" replace />
  }

  return <>{children}</>
}
