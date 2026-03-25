import { useNavigate } from 'react-router-dom'
import { Home, AlertTriangle } from 'lucide-react'

/**
 * NotFoundPage — صفحة 404
 */
export default function NotFoundPage() {
  const navigate = useNavigate()

  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
      minHeight: '60vh', padding: 'var(--space-6)', textAlign: 'center',
    }}>
      <div style={{
        width: 80, height: 80, borderRadius: 'var(--radius-full)',
        background: 'var(--color-warning-light)', display: 'flex',
        alignItems: 'center', justifyContent: 'center', marginBottom: 'var(--space-5)',
      }}>
        <AlertTriangle size={40} style={{ color: 'var(--color-warning)' }} />
      </div>
      <h1 style={{ fontSize: 'var(--text-3xl)', fontWeight: 800, marginBottom: 'var(--space-2)' }}>
        ٤٠٤
      </h1>
      <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 600, marginBottom: 'var(--space-2)', color: 'var(--text-secondary)' }}>
        الصفحة غير موجودة
      </h2>
      <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)', marginBottom: 'var(--space-6)', maxWidth: 400 }}>
        الصفحة التي تبحث عنها غير متوفرة. تأكد من صحة الرابط أو عُد إلى الصفحة الرئيسية.
      </p>
      <button className="btn btn-primary btn-lg" onClick={() => navigate('/')}>
        <Home size={18} />
        العودة للرئيسية
      </button>
    </div>
  )
}
