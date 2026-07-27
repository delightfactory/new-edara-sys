import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { Save, ArrowRight, Loader2, ShieldAlert } from 'lucide-react'
import { createUser } from '@/lib/services/auth'
import {
  getUser,
  getRoles,
  getUserPermissionContext,
  updateUserWithAccessAtomic,
  updateProfile,
} from '@/lib/services/users'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { useAuthStore } from '@/stores/auth-store'
import { UserPermissionOverridesCard } from './UserPermissionOverridesCard'
import type {
  Role,
  UserPermissionContext,
  UserPermissionOverrideInput,
} from '@/lib/types/auth'

export default function UserFormPage() {
  const navigate = useNavigate()
  const { id } = useParams()
  const isEdit = Boolean(id)
  const currentUserId = useAuthStore(state => state.profile?.id)
  const canManageIndividualPermissions = useAuthStore(state =>
    state.can(PERMISSIONS.AUTH_USER_PERMISSIONS_MANAGE),
  )
  const canEditTargetPermissions = Boolean(
    isEdit && id && canManageIndividualPermissions && currentUserId !== id,
  )

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [roles, setRoles] = useState<Role[]>([])
  const [permissionContext, setPermissionContext] = useState<UserPermissionContext | null>(null)
  const [permissionOverrides, setPermissionOverrides] = useState<UserPermissionOverrideInput[]>([])

  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [phone, setPhone] = useState('')
  const [password, setPassword] = useState('')
  const [selectedRoles, setSelectedRoles] = useState<string[]>([])

  useEffect(() => {
    let cancelled = false

    const loadForm = async () => {
      setLoading(true)
      try {
        if (isEdit && id) {
          const [loadedRoles, user] = await Promise.all([
            getRoles(),
            getUser(id),
          ])
          if (cancelled) return

          setRoles(loadedRoles)
          setFullName(user.full_name)
          setEmail(user.email || '')
          setPhone(user.phone || '')
          setSelectedRoles(user.user_roles?.map(ur => ur.role_id) || [])
          // The established profile/role form must not wait for the optional
          // individual-permission context to finish loading.
          setLoading(false)
        } else {
          const loadedRoles = await getRoles()
          if (!cancelled) setRoles(loadedRoles)
        }
      } catch {
        if (cancelled) return
        toast.error(isEdit ? 'فشل تحميل بيانات المستخدم وصلاحياته' : 'فشل تحميل الأدوار')
        if (isEdit) navigate('/settings/users')
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    void loadForm()
    return () => { cancelled = true }
  }, [id, isEdit, navigate])

  useEffect(() => {
    let cancelled = false

    // Permission state belongs to one target and must never survive a route or
    // authorization change. Keep this independent from the established form
    // load so a background session refresh cannot discard unsaved profile data.
    setPermissionContext(null)
    setPermissionOverrides([])

    if (!canEditTargetPermissions || !isEdit || !id) {
      return () => { cancelled = true }
    }

    const loadPermissionContext = async () => {
      try {
        const accessContext = await getUserPermissionContext(id)
        if (cancelled) return
        setPermissionContext(accessContext)
        setPermissionOverrides(accessContext.overrides.map(override => ({
          permission: override.permission,
          granted: override.granted,
          reason: override.reason,
          expires_at: override.expires_at,
        })))
      } catch {
        if (cancelled) return
        setPermissionContext(null)
        setPermissionOverrides([])
        toast.warning('تعذر تحميل الصلاحيات الفردية؛ يمكنك تعديل البيانات دون تغييرها')
      }
    }

    void loadPermissionContext()
    return () => { cancelled = true }
  }, [canEditTargetPermissions, id, isEdit])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!fullName.trim()) { toast.error('الاسم مطلوب'); return }
    if (!isEdit && !email.trim()) { toast.error('البريد الإلكتروني مطلوب'); return }
    if (!isEdit && password.length < 8) { toast.error('كلمة المرور: 8 أحرف على الأقل'); return }
    if (permissionOverrides.some(override =>
      override.expires_at && new Date(override.expires_at).getTime() <= Date.now()
    )) {
      toast.error('تاريخ انتهاء استثناء الصلاحية يجب أن يكون في المستقبل')
      return
    }

    setSaving(true)
    try {
      if (isEdit && id) {
        if (currentUserId === id) {
          await updateProfile(id, { full_name: fullName, phone: phone || null })
        } else {
          await updateUserWithAccessAtomic(
            id,
            { full_name: fullName, phone: phone || null },
            selectedRoles,
            canEditTargetPermissions && permissionContext ? permissionOverrides : null,
          )
        }
        toast.success('تم تحديث المستخدم')
      } else {
        await createUser({
          full_name: fullName, email, password,
          phone: phone || undefined,
          role_ids: selectedRoles,
        })
        toast.success('تم إنشاء المستخدم بنجاح')
      }
      navigate('/settings/users')
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'فشلت العملية')
    } finally { setSaving(false) }
  }

  const toggleRole = (roleId: string) => {
    setSelectedRoles(prev =>
      prev.includes(roleId) ? prev.filter(r => r !== roleId) : [...prev, roleId]
    )
  }

  if (loading) {
    return (
      <div className="page-container">
        {[1,2,3,4].map(i => <div key={i} className="skeleton" style={{ height: 56, marginBottom: 16 }} />)}
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">
      <div className="page-header">
        <div className="page-header-info">
          <h1 className="page-title">{isEdit ? 'تعديل مستخدم' : 'إضافة مستخدم جديد'}</h1>
          <p className="page-subtitle">{isEdit ? `تعديل بيانات ${fullName}` : 'إنشاء حساب مستخدم جديد في النظام'}</p>
        </div>
        <button className="btn btn-secondary" onClick={() => navigate('/settings/users')}>
          <ArrowRight size={16} style={{ transform: 'scaleX(-1)' }} /> رجوع
        </button>
      </div>

      <form onSubmit={handleSubmit}>
        <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-4)' }}>
          <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-5)' }}>
            البيانات الأساسية
          </h3>
          <div className="grid grid-2 gap-4">
            <div className="form-group">
              <label className="form-label required">الاسم الكامل</label>
              <input className="form-input" value={fullName} onChange={e => setFullName(e.target.value)}
                placeholder="أدخل الاسم الكامل" autoFocus />
            </div>
            <div className="form-group">
              <label className="form-label required">البريد الإلكتروني</label>
              <input className="form-input" dir="ltr" value={email} onChange={e => setEmail(e.target.value)}
                placeholder="user@company.com" type="email" disabled={isEdit} />
              {isEdit && <span className="form-hint">لا يمكن تعديل البريد الإلكتروني</span>}
            </div>
            <div className="form-group">
              <label className="form-label">رقم الهاتف</label>
              <input className="form-input" dir="ltr" type="tel" inputMode="numeric"
                value={phone} onChange={e => setPhone(e.target.value)}
                placeholder="01xxxxxxxxx" />
            </div>
            {!isEdit && (
              <div className="form-group">
                <label className="form-label required">كلمة المرور</label>
                <input className="form-input" dir="ltr" type="password" value={password}
                  onChange={e => setPassword(e.target.value)}
                  placeholder="8 أحرف على الأقل" />
              </div>
            )}
          </div>
        </div>

        <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-4)' }}>
          <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-5)' }}>
            الأدوار
          </h3>
          <div className="grid grid-3 gap-3">
            {roles.map(role => (
              <label key={role.id} className="edara-card" style={{
                padding: 'var(--space-3) var(--space-4)',
                cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 'var(--space-3)',
                borderColor: selectedRoles.includes(role.id) ? role.color : undefined,
                background: selectedRoles.includes(role.id) ? `${role.color}08` : undefined,
              }}>
                <input type="checkbox" checked={selectedRoles.includes(role.id)}
                  disabled={isEdit && currentUserId === id}
                  onChange={() => toggleRole(role.id)} />
                <div>
                  <span className="badge" style={{ background: `${role.color}18`, color: role.color }}>
                    {role.name_ar}
                  </span>
                  {role.is_system && <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginInlineStart: 'var(--space-2)' }}>نظامي</span>}
                </div>
              </label>
            ))}
          </div>
        </div>

        {isEdit && canEditTargetPermissions && permissionContext && (
          <UserPermissionOverridesCard
            context={permissionContext}
            selectedRoleIds={selectedRoles}
            value={permissionOverrides}
            onChange={setPermissionOverrides}
            disabled={saving}
          />
        )}

        {isEdit && canManageIndividualPermissions && currentUserId === id && (
          <div className="edara-card" style={{
            padding: 'var(--space-4)',
            marginBottom: 'var(--space-4)',
            display: 'flex',
            alignItems: 'flex-start',
            gap: 'var(--space-3)',
            color: 'var(--text-secondary)',
          }}>
            <ShieldAlert size={20} style={{ color: 'var(--color-warning)', flexShrink: 0 }} />
            <div>
              <strong style={{ color: 'var(--text-primary)', fontWeight: 700 }}>حماية الحساب الحالي</strong>
              <p style={{ fontSize: 'var(--text-sm)', lineHeight: 1.7, marginTop: 2 }}>
                لا يمكن تعديل أدوار أو استثناءات حسابك أثناء استخدامه، لمنع التصعيد الذاتي أو فقدان صلاحية الإدارة.
              </p>
            </div>
          </div>
        )}

        <div className="flex gap-3" style={{ justifyContent: 'flex-end' }}>
          <button type="button" className="btn btn-secondary" onClick={() => navigate('/settings/users')}>إلغاء</button>
          <button type="submit" className="btn btn-primary btn-lg" disabled={saving}>
            {saving ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />}
            {isEdit ? 'حفظ التعديلات' : 'إنشاء المستخدم'}
          </button>
        </div>
      </form>
    </div>
  )
}
