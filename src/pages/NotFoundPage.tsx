import { useNavigate } from 'react-router-dom'
import { Home, ArrowRight, Compass } from 'lucide-react'

/**
 * NotFoundPage — صفحة 404
 */
export default function NotFoundPage() {
  const navigate = useNavigate()

  return (
    <div className="ep-root">
      <div className="ep-card">
        {/* Icon */}
        <div className="ep-icon-wrap ep-icon-warning">
          <Compass size={44} strokeWidth={1.5} />
        </div>

        {/* Code badge */}
        <div className="ep-code">404</div>

        <h1 className="ep-title">الصفحة غير موجودة</h1>
        <p className="ep-desc">
          الرابط الذي تبحث عنه غير موجود أو تم نقله.
          <br />
          تأكد من صحة الرابط أو عُد إلى الرئيسية.
        </p>

        <div className="ep-actions">
          <button className="ep-btn-primary" onClick={() => navigate('/')}>
            <Home size={16} /> الصفحة الرئيسية
          </button>
          <button className="ep-btn-ghost" onClick={() => navigate(-1)}>
            <ArrowRight size={16} /> رجوع
          </button>
        </div>
      </div>

      <style>{`
        .ep-root {
          min-height: 100dvh;
          display: flex; align-items: center; justify-content: center;
          background: var(--bg-app); padding: var(--space-6);
        }
        .ep-card {
          max-width: 420px; width: 100%;
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: 20px;
          padding: 48px 36px;
          text-align: center;
          box-shadow: 0 16px 48px rgba(0,0,0,0.12);
          animation: ep-in 0.4s cubic-bezier(.22,.68,0,1.2) both;
        }
        @keyframes ep-in {
          from { opacity: 0; transform: scale(0.92) translateY(16px); }
          to   { opacity: 1; transform: none; }
        }
        .ep-icon-wrap {
          width: 88px; height: 88px; border-radius: 50%;
          display: flex; align-items: center; justify-content: center;
          margin: 0 auto 20px;
        }
        .ep-icon-warning {
          background: color-mix(in srgb, var(--color-warning) 10%, transparent);
          border: 2px solid color-mix(in srgb, var(--color-warning) 20%, transparent);
          color: var(--color-warning);
        }
        .ep-code {
          font-size: 13px; font-weight: 700; letter-spacing: 2px;
          color: var(--text-muted); margin-bottom: 8px;
          font-family: monospace;
        }
        .ep-title {
          font-size: 22px; font-weight: 800;
          color: var(--text-primary); margin: 0 0 12px;
        }
        .ep-desc {
          font-size: 14px; color: var(--text-secondary);
          line-height: 1.7; margin: 0 0 32px;
        }
        .ep-actions {
          display: flex; flex-direction: column; gap: 10px;
        }
        .ep-btn-primary {
          height: 48px; border-radius: 10px;
          background: var(--color-primary); color: #fff;
          border: none; font-size: 15px; font-weight: 700;
          cursor: pointer; display: flex; align-items: center;
          justify-content: center; gap: 8px;
          transition: background 0.18s, transform 0.12s;
        }
        .ep-btn-primary:hover { background: color-mix(in srgb, var(--color-primary) 85%, #000); transform: translateY(-1px); }
        .ep-btn-ghost {
          height: 44px; border-radius: 10px;
          background: var(--bg-surface-2);
          border: 1px solid var(--border-primary);
          color: var(--text-secondary); font-size: 14px; font-weight: 500;
          cursor: pointer; display: flex; align-items: center;
          justify-content: center; gap: 8px;
          transition: background 0.15s;
        }
        .ep-btn-ghost:hover { background: var(--bg-hover); }
      `}</style>
    </div>
  )
}
