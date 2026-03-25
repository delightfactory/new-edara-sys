import { useState } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { LogIn, Eye, EyeOff, Loader2 } from 'lucide-react'
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
  } = useForm<LoginForm>({
    resolver: zodResolver(loginSchema),
  })

  const onSubmit = async (data: LoginForm) => {
    try {
      await signIn(data.email, data.password)
      // تحميل الملف الشخصي والصلاحيات قبل التوجيه
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
    <div className="login-page">
      <div className="login-card edara-card">
        <div className="login-header">
          <div className="login-logo">
            <div className="login-logo-icon">
              <LogIn size={28} />
            </div>
            <h1>EDARA</h1>
            <p>نظام إدارة التوزيع المتكامل</p>
          </div>
        </div>

        <form onSubmit={handleSubmit(onSubmit)} className="login-form">
          <div className="form-group">
            <label className="form-label required">البريد الإلكتروني</label>
            <input
              {...register('email')}
              type="email"
              dir="ltr"
              className={`form-input ${errors.email ? 'error' : ''}`}
              placeholder="user@company.com"
              autoComplete="email"
              autoFocus
            />
            {errors.email && <span className="form-error">{errors.email.message}</span>}
          </div>

          <div className="form-group">
            <label className="form-label required">كلمة المرور</label>
            <div style={{ position: 'relative' }}>
              <input
                {...register('password')}
                type={showPassword ? 'text' : 'password'}
                dir="ltr"
                className={`form-input ${errors.password ? 'error' : ''}`}
                placeholder="••••••••"
                autoComplete="current-password"
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="password-toggle"
                tabIndex={-1}
              >
                {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
            {errors.password && <span className="form-error">{errors.password.message}</span>}
          </div>

          <button
            type="submit"
            className="btn btn-primary btn-lg btn-block"
            disabled={isSubmitting}
          >
            {isSubmitting ? (
              <>
                <Loader2 size={18} className="animate-spin" />
                جاري تسجيل الدخول...
              </>
            ) : (
              <>
                <LogIn size={18} />
                تسجيل الدخول
              </>
            )}
          </button>

          <p className="login-help">
            نسيت كلمة المرور؟ تواصل مع مسؤول النظام
          </p>
        </form>
      </div>

      <style>{`
        .login-page {
          min-height: 100vh;
          display: flex; align-items: center; justify-content: center;
          background: linear-gradient(135deg, #1e3a5f 0%, #0f172a 50%, #1e293b 100%);
          padding: var(--space-4);
        }
        .login-card {
          width: 100%; max-width: 420px;
          border: none; box-shadow: var(--shadow-lg);
          overflow: hidden;
        }
        .login-header {
          background: linear-gradient(135deg, var(--color-primary) 0%, var(--color-primary-dark) 100%);
          padding: var(--space-8) var(--space-6);
          text-align: center; color: white;
        }
        .login-logo-icon {
          width: 56px; height: 56px;
          background: rgba(255,255,255,0.15);
          border-radius: var(--radius-lg);
          display: flex; align-items: center; justify-content: center;
          margin: 0 auto var(--space-3);
          backdrop-filter: blur(8px);
        }
        .login-header h1 {
          font-size: var(--text-2xl); font-weight: 700;
          letter-spacing: 2px; margin-bottom: var(--space-1);
        }
        .login-header p {
          font-size: var(--text-sm); opacity: 0.85;
        }
        .login-form {
          padding: var(--space-6);
          display: flex; flex-direction: column; gap: var(--space-5);
        }
        .password-toggle {
          position: absolute; top: 50%; left: 12px;
          transform: translateY(-50%);
          background: none; border: none; cursor: pointer;
          color: var(--text-muted); padding: 4px;
        }
        [dir="rtl"] .password-toggle { left: 12px; right: auto; }
        .login-help {
          text-align: center; font-size: var(--text-xs);
          color: var(--text-muted);
        }
      `}</style>
    </div>
  )
}
