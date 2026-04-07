import { type ReactNode } from 'react'
import { useAnalyticsAvailability } from '@/hooks/useAnalyticsAvailability'
import { AlertTriangle, Lock, Database, RefreshCw } from 'lucide-react'
import SkeletonCard from './SkeletonCard'

interface Props {
  children: ReactNode
}

/**
 * AnalyticsGate
 *
 * Wraps any report page. Fires ONE probe (analytics_ping) and:
 *  - 'checking'     → loading skeletons, no data requests
 *  - 'not_deployed' → honest message: migration not applied (not "check permissions")
 *  - 'unauthorized' → permission message
 *  - 'error'        → transient error with retry option
 *  - 'available'    → renders children (data hooks may fire)
 *
 * This prevents a flood of 404/error requests when analytics is not deployed.
 */
export default function AnalyticsGate({ children }: Props) {
  const { status, errorReason } = useAnalyticsAvailability()

  if (status === 'checking') {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)', padding: 'var(--space-2)' }}>
        <SkeletonCard height={56} />
        <div className="report-grid">
          {[1, 2, 3, 4].map(i => <SkeletonCard key={i} height={160} />)}
        </div>
        <SkeletonCard height={280} />
      </div>
    )
  }

  if (status === 'not_deployed') {
    return (
      <div style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: '400px',
        padding: 'var(--space-8)',
      }}>
        <div style={{
          background: 'var(--bg-surface)',
          border: '1px solid var(--border-primary)',
          borderRadius: 'var(--radius-xl)',
          padding: 'var(--space-8) var(--space-10)',
          maxWidth: '520px',
          textAlign: 'center',
          boxShadow: 'var(--shadow-md)',
        }}>
          <div style={{
            width: '56px', height: '56px',
            borderRadius: '16px',
            background: 'rgba(37,99,235,0.08)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            margin: '0 auto var(--space-5)',
          }}>
            <Database size={26} color="var(--color-primary)" />
          </div>
          <h2 style={{ fontSize: 'var(--text-xl)', fontWeight: 800, color: 'var(--text-primary)', margin: '0 0 var(--space-3)' }}>
            محرك التقارير لم يُنشَّر بعد
          </h2>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 var(--space-5)' }}>
            طبقة analytics غير موجودة في قاعدة البيانات الحالية.
            يجب تطبيق migrations التالية بالترتيب:
          </p>
          <div style={{
            background: 'var(--bg-surface-2)',
            borderRadius: 'var(--radius-md)',
            padding: 'var(--space-4)',
            fontFamily: 'monospace',
            fontSize: '12px',
            color: 'var(--text-secondary)',
            textAlign: 'right',
            direction: 'ltr',
            lineHeight: 2,
          }}>
            75_analytics_schema_wave1.sql<br />
            76_analytics_incremental_jobs.sql<br />
            77_analytics_public_rpc_layer.sql
          </div>
          {errorReason && (
            <div style={{ marginTop: 'var(--space-4)', fontSize: '11px', color: 'var(--text-muted)', fontFamily: 'monospace' }}>
              {errorReason}
            </div>
          )}
        </div>
      </div>
    )
  }

  if (status === 'unauthorized') {
    return (
      <div style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: '400px',
        padding: 'var(--space-8)',
      }}>
        <div style={{
          background: 'var(--bg-surface)',
          border: '1px solid var(--border-primary)',
          borderRadius: 'var(--radius-xl)',
          padding: 'var(--space-8) var(--space-10)',
          maxWidth: '420px',
          textAlign: 'center',
          boxShadow: 'var(--shadow-md)',
        }}>
          <div style={{
            width: '56px', height: '56px',
            borderRadius: '16px',
            background: 'rgba(220,38,38,0.08)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            margin: '0 auto var(--space-5)',
          }}>
            <Lock size={26} color="var(--color-danger)" />
          </div>
          <h2 style={{ fontSize: 'var(--text-xl)', fontWeight: 800, color: 'var(--text-primary)', margin: '0 0 var(--space-3)' }}>
            غير مصرح بالوصول
          </h2>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', lineHeight: 1.7 }}>
            لا تملك صلاحية التقارير المطلوبة لعرض هذا القسم.
            تواصل مع مدير النظام لمنح الصلاحية المناسبة لدورك
            (<code>reports.sales</code> / <code>reports.financial</code> / <code>reports.targets</code>).
          </p>
        </div>
      </div>
    )
  }

  if (status === 'error') {
    return (
      <div style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: '400px',
        padding: 'var(--space-8)',
      }}>
        <div style={{
          background: 'var(--bg-surface)',
          border: '1px solid rgba(220,38,38,0.2)',
          borderRadius: 'var(--radius-xl)',
          padding: 'var(--space-8) var(--space-10)',
          maxWidth: '420px',
          textAlign: 'center',
          boxShadow: 'var(--shadow-md)',
        }}>
          <div style={{
            width: '56px', height: '56px',
            borderRadius: '16px',
            background: 'rgba(220,38,38,0.08)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            margin: '0 auto var(--space-5)',
          }}>
            <AlertTriangle size={26} color="var(--color-danger)" />
          </div>
          <h2 style={{ fontSize: 'var(--text-xl)', fontWeight: 800, color: 'var(--text-primary)', margin: '0 0 var(--space-3)' }}>
            خطأ في الاتصال
          </h2>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 var(--space-4)' }}>
            تعذّر الاتصال بمحرك التقارير. تحقق من الاتصال بالإنترنت وأعد المحاولة.
          </p>
          <button
            onClick={() => window.location.reload()}
            style={{
              display: 'inline-flex', alignItems: 'center', gap: '8px',
              padding: '8px 20px',
              borderRadius: 'var(--radius-md)',
              background: 'var(--color-primary)',
              color: '#fff',
              border: 'none',
              fontSize: 'var(--text-sm)',
              fontWeight: 600,
              cursor: 'pointer',
              fontFamily: 'var(--font-sans)',
            }}
          >
            <RefreshCw size={14} />
            إعادة المحاولة
          </button>
          {errorReason && (
            <div style={{ marginTop: 'var(--space-4)', fontSize: '11px', color: 'var(--text-muted)', fontFamily: 'monospace' }}>
              {errorReason}
            </div>
          )}
        </div>
      </div>
    )
  }

  // status === 'available'
  return <>{children}</>
}
