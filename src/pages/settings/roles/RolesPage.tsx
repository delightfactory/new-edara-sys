import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Plus, Shield, Trash2, Users, Edit3, Lock } from 'lucide-react'
import { getRoles, deleteRole, getRoleUserCounts } from '@/lib/services/users'
import { useAuthStore } from '@/stores/auth-store'
import { supabase } from '@/lib/supabase/client'
import type { Role } from '@/lib/types/auth'

export default function RolesPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const [roles, setRoles] = useState<Role[]>([])
  const [counts, setCounts] = useState<Record<string, number>>({})
  const [permCounts, setPermCounts] = useState<Record<string, number>>({})
  const [loading, setLoading] = useState(true)

  const loadData = async () => {
    setLoading(true)
    try {
      const [rolesRes, countsRes] = await Promise.all([getRoles(), getRoleUserCounts()])
      setRoles(rolesRes)
      setCounts(countsRes)

      // جلب عدد صلاحيات كل دور
      const { data: allPerms } = await supabase
        .from('role_permissions')
        .select('role_id')
      const pc: Record<string, number> = {}
      for (const rp of allPerms || []) {
        pc[rp.role_id] = (pc[rp.role_id] || 0) + 1
      }
      setPermCounts(pc)
    } catch { toast.error('فشل تحميل الأدوار') }
    finally { setLoading(false) }
  }

  useEffect(() => { loadData() }, [])

  const handleDelete = async (role: Role) => {
    if (role.is_system) { toast.error('لا يمكن حذف دور نظامي'); return }
    if (counts[role.id] && counts[role.id] > 0) {
      toast.error('لا يمكن حذف دور مُعيّن لمستخدمين نشطين')
      return
    }
    if (!confirm(`هل تريد حذف الدور "${role.name_ar}"؟ هذا الإجراء لا يمكن التراجع عنه.`)) return
    try {
      await deleteRole(role.id)
      toast.success('تم حذف الدور')
      loadData()
    } catch { toast.error('فشل الحذف') }
  }

  return (
    <div className="page-container animate-enter">
      <div className="page-header">
        <div className="page-header-info">
          <h1 className="page-title">الأدوار والصلاحيات</h1>
          <p className="page-subtitle">
            {loading ? '...' : `${roles.length} دور — تحكم في صلاحيات كل دور بالنظام`}
          </p>
        </div>
        {can('auth.roles.create') && (
          <button className="btn btn-primary" onClick={() => navigate('/settings/roles/new')}>
            <Plus size={16} /> إنشاء دور جديد
          </button>
        )}
      </div>

      {loading ? (
        <div className="grid grid-3 gap-4">
          {[1,2,3,4,5,6].map(i => <div key={i} className="skeleton" style={{ height: 160 }} />)}
        </div>
      ) : (
        <div className="grid grid-3 gap-4">
          {roles.map(role => {
            const userCount = counts[role.id] || 0
            const permCount = permCounts[role.id] || 0
            const isWildcard = permCount === 1 && role.name === 'super_admin'

            return (
              <div key={role.id} className="edara-card edara-card-interactive"
                style={{
                  padding: 0, overflow: 'hidden',
                  borderTop: `3px solid ${role.color}`,
                  cursor: 'pointer',
                }}
                onClick={() => can('auth.roles.update') && navigate(`/settings/roles/${role.id}/edit`)}
              >
                <div style={{ padding: 'var(--space-5)' }}>
                  <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-3)' }}>
                    <div className="flex items-center gap-3">
                      <div style={{
                        width: 44, height: 44, borderRadius: 'var(--radius-md)',
                        background: `${role.color}15`, color: role.color,
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                      }}>
                        <Shield size={22} />
                      </div>
                      <div>
                        <h3 style={{ fontWeight: 700, fontSize: 'var(--text-base)', lineHeight: 1.3 }}>{role.name_ar}</h3>
                        <span style={{ fontSize: 11, color: 'var(--text-muted)', fontFamily: 'monospace' }}>{role.name}</span>
                      </div>
                    </div>
                    {role.is_system && (
                      <span className="badge badge-info" style={{ fontSize: 10, gap: 2 }}>
                        <Lock size={10} /> نظامي
                      </span>
                    )}
                  </div>

                  {role.description && (
                    <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 'var(--space-3)' }}>
                      {role.description}
                    </p>
                  )}
                </div>

                {/* Footer Stats */}
                <div className="flex items-center" style={{
                  padding: 'var(--space-3) var(--space-5)',
                  borderTop: '1px solid var(--divider)',
                  background: 'var(--bg-surface-2)',
                  gap: 'var(--space-4)',
                }}>
                  <div className="flex items-center gap-1" style={{ color: 'var(--text-muted)', fontSize: 'var(--text-xs)' }}>
                    <Users size={13} />
                    <span>{userCount} مستخدم</span>
                  </div>
                  <div className="flex items-center gap-1" style={{ color: 'var(--text-muted)', fontSize: 'var(--text-xs)' }}>
                    <Shield size={13} />
                    <span>{isWildcard ? 'كل الصلاحيات ✱' : `${permCount} صلاحية`}</span>
                  </div>

                  <div style={{ marginRight: 'auto', display: 'flex', gap: 'var(--space-1)' }}
                    onClick={e => e.stopPropagation()}>
                    {can('auth.roles.update') && (
                      <button className="btn btn-ghost btn-sm" title="تعديل"
                        onClick={() => navigate(`/settings/roles/${role.id}/edit`)}>
                        <Edit3 size={14} />
                      </button>
                    )}
                    {can('auth.roles.delete') && !role.is_system && (
                      <button className="btn btn-danger btn-sm" title="حذف"
                        onClick={() => handleDelete(role)}>
                        <Trash2 size={14} />
                      </button>
                    )}
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
