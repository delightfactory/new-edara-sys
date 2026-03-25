import { useNavigate } from 'react-router-dom'
import { ShieldX, ArrowRight } from 'lucide-react'

export default function UnauthorizedPage() {
  const navigate = useNavigate()

  return (
    <div style={{
      minHeight: '100vh', display: 'flex', alignItems: 'center',
      justifyContent: 'center', background: 'var(--bg-app)',
      padding: 'var(--space-4)',
    }}>
      <div style={{ textAlign: 'center', maxWidth: 400 }}>
        <ShieldX size={64} style={{ color: 'var(--color-danger)', opacity: 0.6, margin: '0 auto var(--space-4)' }} />
        <h1 style={{ fontSize: 'var(--text-2xl)', fontWeight: 700, marginBottom: 'var(--space-2)' }}>
          غير مصرح
        </h1>
        <p style={{ color: 'var(--text-secondary)', marginBottom: 'var(--space-6)', fontSize: 'var(--text-sm)' }}>
          ليس لديك الصلاحية للوصول إلى هذه الصفحة.
          إذا كنت تعتقد أن هذا خطأ، تواصل مع مسؤول النظام.
        </p>
        <button className="btn btn-primary" onClick={() => navigate('/', { replace: true })}>
          <ArrowRight size={16} />
          العودة للرئيسية
        </button>
      </div>
    </div>
  )
}
