import { useState } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { LogIn, Eye, EyeOff, Loader2, Shield } from 'lucide-react'
import { toast } from 'sonner'
import { signIn, loadSession } from '@/lib/services/auth'

const loginSchema = z.object({
  email: z.string().email('بريد إلكتروني غير صالح'),
  password: z.string().min(6, 'كلمة المرور يجب أن تكون 6 أحرف على الأقل'),
})

type LoginForm = z.infer<typeof loginSchema>

export default function LoginPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const [showPassword, setShowPassword] = useState(false)
  const from = (location.state as { from?: { pathname: string } })?.from?.pathname || '/'

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<LoginForm>({ resolver: zodResolver(loginSchema) })

  const onSubmit = async (data: LoginForm) => {
    try {
      await signIn(data.email, data.password)
      await loadSession()
      toast.success('تم تسجيل الدخول بنجاح')
      navigate(from, { replace: true })
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'حدث خطأ أثناء تسجيل الدخول'
      toast.error(msg === 'Invalid login credentials'
        ? 'بريد إلكتروني أو كلمة مرور غير صحيحة'
        : msg
      )
    }
  }

  return (
    <div className="lp-root">
      {/* Animated background blobs */}
      <div className="lp-blob lp-blob-1" />
      <div className="lp-blob lp-blob-2" />

      <div className="lp-card edara-card">
        {/* Brand header */}
        <div className="lp-brand">
          <div className="lp-brand-icon">
            <Shield size={30} strokeWidth={1.5} />
          </div>
          <h1 className="lp-brand-name">EDARA</h1>
          <p className="lp-brand-tagline">نظام إدارة التوزيع المتكامل</p>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit(onSubmit)} className="lp-form" noValidate>
          {/* Email */}
          <div className="form-group">
            <label className="form-label required">البريد الإلكتروني</label>
            <input
              {...register('email')}
              type="email"
              inputMode="email"
              dir="ltr"
              className={`form-input lp-input ${errors.email ? 'error' : ''}`}
              placeholder="user@company.com"
              autoComplete="username email"
              autoFocus
            />
            {errors.email && <span className="form-error">{errors.email.message}</span>}
          </div>

          {/* Password */}
          <div className="form-group">
            <label className="form-label required">كلمة المرور</label>
            <div style={{ position: 'relative' }}>
              <input
                {...register('password')}
                type={showPassword ? 'text' : 'password'}
                dir="ltr"
                className={`form-input lp-input ${errors.password ? 'error' : ''}`}
                placeholder="••••••••"
                autoComplete="current-password"
              />
              <button
                type="button"
                onClick={() => setShowPassword(s => !s)}
                className="lp-eye-btn"
                tabIndex={-1}
                aria-label={showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور'}
              >
                {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
            {errors.password && <span className="form-error">{errors.password.message}</span>}
          </div>

          {/* Submit */}
          <button
            type="submit"
            className="lp-submit-btn"
            disabled={isSubmitting}
          >
            {isSubmitting ? (
              <><Loader2 size={20} className="animate-spin" /> جاري تسجيل الدخول...</>
            ) : (
              <><LogIn size={20} /> تسجيل الدخول</>
            )}
          </button>

          <p className="lp-hint">نسيت كلمة المرور؟ تواصل مع مسؤول النظام</p>
        </form>
      </div>

      <style>{`
        /* ── Root layout ── */
        .lp-root {
          min-height: 100dvh;
          display: flex; align-items: center; justify-content: center;
          background: var(--bg-app);
          padding: var(--space-4);
          position: relative; overflow: hidden;
        }

        /* ── Animated background blobs ── */
        .lp-blob {
          position: absolute; border-radius: 50%;
          filter: blur(80px); opacity: 0.12; pointer-events: none;
          animation: lp-float 8s ease-in-out infinite alternate;
        }
        .lp-blob-1 {
          width: 500px; height: 500px;
          background: var(--color-primary);
          top: -150px; right: -150px;
        }
        .lp-blob-2 {
          width: 400px; height: 400px;
          background: var(--color-info);
          bottom: -100px; left: -100px;
          animation-delay: -4s;
        }
        @keyframes lp-float {
          from { transform: translate(0, 0) scale(1); }
          to   { transform: translate(30px, -30px) scale(1.05); }
        }

        /* ── Card ── */
        .lp-card {
          position: relative; z-index: 1;
          width: 100%; max-width: 420px;
          border: 1px solid var(--border-primary);
          box-shadow: 0 24px 64px -12px rgba(0,0,0,0.25);
          overflow: hidden;
          border-radius: var(--radius-xl, 16px);
        }

        /* ── Brand header ── */
        .lp-brand {
          background: linear-gradient(135deg, var(--color-primary) 0%, color-mix(in srgb, var(--color-primary) 70%, #000) 100%);
          padding: 40px 32px 36px;
          text-align: center; color: #fff;
        }
        .lp-brand-icon {
          width: 60px; height: 60px;
          background: rgba(255,255,255,0.18);
          border: 1px solid rgba(255,255,255,0.25);
          border-radius: 16px;
          display: flex; align-items: center; justify-content: center;
          margin: 0 auto 16px;
          backdrop-filter: blur(8px);
          box-shadow: 0 8px 24px rgba(0,0,0,0.12);
        }
        .lp-brand-name {
          font-size: 28px; font-weight: 800; letter-spacing: 3px;
          margin: 0 0 6px; color: #fff;
        }
        .lp-brand-tagline {
          font-size: 13px; opacity: 0.82; margin: 0; color: rgba(255,255,255,0.9);
        }

        /* ── Form ── */
        .lp-form {
          padding: 32px;
          display: flex; flex-direction: column; gap: 20px;
          background: var(--bg-surface);
        }
        .lp-input {
          height: 48px; font-size: 15px;
        }
        .lp-eye-btn {
          position: absolute; top: 50%; left: 14px;
          transform: translateY(-50%);
          background: none; border: none; cursor: pointer;
          color: var(--text-muted); padding: 6px;
          display: flex; align-items: center;
          transition: color 0.15s;
        }
        .lp-eye-btn:hover { color: var(--text-primary); }

        /* ── Submit ── */
        .lp-submit-btn {
          width: 100%; height: 52px;
          background: var(--color-primary);
          color: #fff; border: none;
          border-radius: var(--radius-md, 10px);
          font-size: 16px; font-weight: 700;
          cursor: pointer; display: flex; align-items: center;
          justify-content: center; gap: 10px;
          transition: background 0.18s, transform 0.12s, box-shadow 0.18s;
          box-shadow: 0 4px 16px color-mix(in srgb, var(--color-primary) 40%, transparent);
        }
        .lp-submit-btn:hover:not(:disabled) {
          background: color-mix(in srgb, var(--color-primary) 85%, #000);
          box-shadow: 0 6px 24px color-mix(in srgb, var(--color-primary) 50%, transparent);
          transform: translateY(-1px);
        }
        .lp-submit-btn:active:not(:disabled) { transform: translateY(0); }
        .lp-submit-btn:disabled { opacity: 0.7; cursor: not-allowed; }

        .lp-hint {
          text-align: center; font-size: 12px;
          color: var(--text-muted); margin: 0;
        }

        /* ── Mobile ── */
        @media (max-width: 480px) {
          .lp-root { padding: 0; align-items: flex-end; }
          .lp-card { max-width: 100%; border-radius: 20px 20px 0 0; }
          .lp-brand { padding: 28px 24px 24px; }
          .lp-form { padding: 24px; }
          .lp-blob { display: none; }
        }
      `}</style>
    </div>
  )
}
