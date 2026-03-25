import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { Save, ArrowRight, Loader2 } from 'lucide-react'
import { createUser } from '@/lib/services/auth'
import { getUser, getRoles, setUserRoles, updateProfile } from '@/lib/services/users'
import type { Role } from '@/lib/types/auth'

export default function UserFormPage() {
  const navigate = useNavigate()
  const { id } = useParams()
  const isEdit = Boolean(id)

  const [loading, setLoading] = useState(isEdit)
  const [saving, setSaving] = useState(false)
  const [roles, setRoles] = useState<Role[]>([])

  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [phone, setPhone] = useState('')
  const [password, setPassword] = useState('')
  const [selectedRoles, setSelectedRoles] = useState<string[]>([])

  useEffect(() => {
    getRoles().then(setRoles).catch(() => toast.error('فشل تحميل الأدوار'))
    if (isEdit && id) {
      getUser(id).then(user => {
        setFullName(user.full_name)
        setEmail(user.email || '')
        setPhone(user.phone || '')
        setSelectedRoles(user.user_roles?.map(ur => ur.role_id) || [])
        setLoading(false)
      }).catch(() => {
        toast.error('فشل تحميل المستخدم')
        navigate('/settings/users')
      })
    }
  }, [id])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!fullName.trim()) { toast.error('الاسم مطلوب'); return }
    if (!isEdit && !email.trim()) { toast.error('البريد الإلكتروني مطلوب'); return }
    if (!isEdit && password.length < 8) { toast.error('كلمة المرور: 8 أحرف على الأقل'); return }

    setSaving(true)
    try {
      if (isEdit && id) {
        await updateProfile(id, { full_name: fullName, phone: phone || null })
        await setUserRoles(id, selectedRoles)
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
          <ArrowRight size={16} /> رجوع
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
              <input className="form-input" dir="ltr" value={phone} onChange={e => setPhone(e.target.value)}
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
                  onChange={() => toggleRole(role.id)} />
                <div>
                  <span className="badge" style={{ background: `${role.color}18`, color: role.color }}>
                    {role.name_ar}
                  </span>
                  {role.is_system && <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginRight: 'var(--space-2)' }}>نظامي</span>}
                </div>
              </label>
            ))}
          </div>
        </div>

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
