import { Component, type ReactNode, type ErrorInfo } from 'react'
import { AlertTriangle } from 'lucide-react'
import { captureError } from '@/lib/monitoring/sentry'

interface Props {
  children: ReactNode
  fallback?: ReactNode
}

interface State {
  hasError: boolean
  error?: Error
}

/**
 * ErrorBoundary — يلتقط أخطاء React ويعرض رسالة بدلاً من كسر التطبيق
 */
export default class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props)
    this.state = { hasError: false }
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('[ErrorBoundary] Caught error:', error, errorInfo)
    captureError(error, { componentStack: errorInfo.componentStack ?? undefined })
  }

  handleReset = () => {
    this.setState({ hasError: false, error: undefined })
  }

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) return this.props.fallback

      return (
        <div style={{
          display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
          minHeight: '50vh', padding: 'var(--space-6)', textAlign: 'center',
        }}>
          <div style={{
            width: 64, height: 64, borderRadius: 'var(--radius-full)',
            background: 'var(--color-danger-light)', display: 'flex',
            alignItems: 'center', justifyContent: 'center', marginBottom: 'var(--space-4)',
          }}>
            <AlertTriangle size={32} style={{ color: 'var(--color-danger)' }} />
          </div>
          <h2 style={{ fontSize: 'var(--text-xl)', fontWeight: 700, marginBottom: 'var(--space-2)' }}>
            حدث خطأ غير متوقع
          </h2>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', marginBottom: 'var(--space-4)', maxWidth: 400 }}>
            نعتذر عن هذا الخطأ. يرجى المحاولة مرة أخرى أو التواصل مع الدعم الفني.
          </p>
          {this.state.error && (
            <pre style={{
              fontSize: 'var(--text-xs)', color: 'var(--text-muted)', background: 'var(--bg-surface-2)',
              padding: 'var(--space-3)', borderRadius: 'var(--radius-md)', marginBottom: 'var(--space-4)',
              maxWidth: '100%', overflow: 'auto', direction: 'ltr', textAlign: 'left',
            }}>
              {this.state.error.message}
            </pre>
          )}
          <div style={{ display: 'flex', gap: 'var(--space-3)' }}>
            <button className="btn btn-primary" onClick={this.handleReset}>
              إعادة المحاولة
            </button>
            <button className="btn btn-secondary" onClick={() => window.location.href = '/'}>
              العودة للرئيسية
            </button>
          </div>
        </div>
      )
    }

    return this.props.children
  }
}
