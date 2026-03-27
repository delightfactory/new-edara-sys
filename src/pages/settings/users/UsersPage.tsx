import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Plus, Search, UserCog, KeyRound, Ban, CheckCircle } from 'lucide-react'
import { toggleUserStatus } from '@/lib/services/users'
import { adminResetPassword } from '@/lib/services/auth'
import { useUsers, useRoles } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { UserWithRoles } from '@/lib/types/auth'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import ConfirmDialog from '@/components/ui/ConfirmDialog'
import Button from '@/components/ui/Button'

export default function UsersPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const queryClient = useQueryClient()

  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [roleFilter, setRoleFilter] = useState('')
  const [page, setPage] = useState(1)
  const [resetModal, setResetModal] = useState<string | null>(null)
  const [newPassword, setNewPassword] = useState('')
  const [resetting, setResetting] = useState(false)
  const [confirmToggle, setConfirmToggle] = useState<UserWithRoles | null>(null)
  const [toggling, setToggling] = useState(false)

  const { data: usersResult, isLoading: loading } = useUsers({ search, status: statusFilter, role: roleFilter, page })
  const users = usersResult?.data || []
  const totalPages = usersResult?.totalPages || 1
  const { data: roles = [] } = useRoles()

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['users'] })

  const handleToggleStatus = async (user: UserWithRoles) => {
    setConfirmToggle(user)
  }

  const executeToggle = async () => {
    if (!confirmToggle) return
    const newStatus = confirmToggle.status === 'active' ? 'inactive' : 'active'
    setToggling(true)
    try {
      await toggleUserStatus(confirmToggle.id, newStatus)
      toast.success(`تم ${newStatus === 'active' ? 'تفعيل' : 'تعطيل'} المستخدم`)
      invalidate()
    } catch { toast.error('فشلت العملية') }
    finally { setToggling(false); setConfirmToggle(null) }
  }

  const handleResetPassword = async () => {
    if (!resetModal || newPassword.length < 8) {
      toast.error('كلمة المرور يجب أن تكون 8 أحرف على الأقل')
      return
    }
    setResetting(true)
    try {
      await adminResetPassword(resetModal, newPassword)
      toast.success('تم إعادة تعيين كلمة المرور')
      setResetModal(null)
      setNewPassword('')
    } catch { toast.error('فشلت العملية') }
    finally { setResetting(false) }
  }

  const statusBadge = (status: string) => {
    const map: Record<string, { cls: string; label: string }> = {
      active: { cls: 'badge-success', label: 'نشط' },
      inactive: { cls: 'badge-danger', label: 'معطل' },
      suspended: { cls: 'badge-warning', label: 'معلق' },
    }
    const s = map[status] || { cls: 'badge-neutral', label: status }
    return <span className={`badge ${s.cls}`}>{s.label}</span>
  }

  return (
    <div className="page-container animate-enter">
      <div className="page-header">
        <div className="page-header-info">
          <h1 className="page-title">إدارة المستخدمين</h1>
          <p className="page-subtitle">{loading ? '...' : `${users.length} مستخدم`}</p>
        </div>
        {can('auth.users.create') && (
          <div className="page-actions">
            <button className="btn btn-primary" onClick={() => navigate('/settings/users/new')}>
              <Plus size={16} /> إضافة مستخدم
            </button>
          </div>
        )}
      </div>

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-4" style={{ flexWrap: 'wrap' }}>
          <div className="search-input-wrapper" style={{ flex: 1, minWidth: 200 }}>
            <Search size={16} className="search-icon" />
            <input
              className="form-input search-input"
              placeholder="بحث بالاسم أو البريد..."
              value={search}
              onChange={e => { setSearch(e.target.value); setPage(1) }}
            />
          </div>
          <select className="form-select" style={{ width: 150 }} value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value); setPage(1) }}>
            <option value="">كل الحالات</option>
            <option value="active">نشط</option>
            <option value="inactive">معطل</option>
            <option value="suspended">معلق</option>
          </select>
          <select className="form-select" style={{ width: 180 }} value={roleFilter}
            onChange={e => { setRoleFilter(e.target.value); setPage(1) }}>
            <option value="">كل الأدوار</option>
            {roles.map(r => <option key={r.id} value={r.name}>{r.name_ar}</option>)}
          </select>
        </div>
      </div>

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        {loading ? (
          <div style={{ padding: 'var(--space-6)' }}>
            {[1,2,3,4,5].map(i => <div key={i} className="skeleton skeleton-row" />)}
          </div>
        ) : users.length === 0 ? (
          <div className="empty-state">
            <UserCog size={48} className="empty-state-icon" />
            <p className="empty-state-title">لا يوجد مستخدمون</p>
            <p className="empty-state-text">لم يتم العثور على مستخدمين مطابقين للبحث</p>
          </div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>المستخدم</th>
                <th className="hide-mobile">البريد</th>
                <th>الدور</th>
                <th>الحالة</th>
                <th className="hide-mobile">آخر دخول</th>
                <th style={{ width: 140 }}>إجراءات</th>
              </tr>
            </thead>
            <tbody>
              {users.map(user => (
                <tr key={user.id}>
                  <td>
                    <div className="flex items-center gap-3">
                      <div className="sidebar-user-avatar" style={{ width: 32, height: 32, fontSize: 'var(--text-xs)' }}>
                        {user.full_name?.charAt(0)}
                      </div>
                      <div>
                        <span style={{ fontWeight: 600 }}>{user.full_name}</span>
                        <div className="show-mobile" style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }} dir="ltr">{user.email}</div>
                      </div>
                    </div>
                  </td>
                  <td className="hide-mobile"><span dir="ltr" style={{ color: 'var(--text-secondary)' }}>{user.email}</span></td>
                  <td>
                    <div className="flex gap-1" style={{ flexWrap: 'wrap' }}>
                      {user.user_roles?.map(ur => (
                        <span key={ur.id} className="badge" style={{
                          background: `${ur.role?.color}18`,
                          color: ur.role?.color,
                        }}>
                          {ur.role?.name_ar}
                        </span>
                      ))}
                      {(!user.user_roles || user.user_roles.length === 0) && (
                        <span className="badge badge-neutral">بدون دور</span>
                      )}
                    </div>
                  </td>
                  <td>{statusBadge(user.status)}</td>
                  <td className="hide-mobile" style={{ color: 'var(--text-muted)', fontSize: 'var(--text-xs)' }}>
                    {user.last_login_at
                      ? new Date(user.last_login_at).toLocaleDateString('ar-EG-u-nu-latn')
                      : 'لم يسجل دخول'}
                  </td>
                  <td>
                    <div className="flex gap-1">
                      {can('auth.users.update') && (
                        <button className="btn btn-ghost btn-sm" title="تعديل"
                          onClick={() => navigate(`/settings/users/${user.id}/edit`)}>
                          <UserCog size={14} />
                        </button>
                      )}
                      {can('auth.users.reset_password') && (
                        <button className="btn btn-ghost btn-sm" title="إعادة تعيين كلمة المرور"
                          onClick={() => setResetModal(user.id)}>
                          <KeyRound size={14} />
                        </button>
                      )}
                      {can('auth.users.deactivate') && (
                        <button
                          className={`btn btn-sm ${user.status === 'active' ? 'btn-danger' : 'btn-success'}`}
                          title={user.status === 'active' ? 'تعطيل' : 'تفعيل'}
                          onClick={() => handleToggleStatus(user)}
                        >
                          {user.status === 'active' ? <Ban size={14} /> : <CheckCircle size={14} />}
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        {/* Pagination */}
        {totalPages > 1 && (
          <div className="pagination" style={{ padding: 'var(--space-4)' }}>
            <span className="pagination-info">صفحة {page} من {totalPages}</span>
            <div className="pagination-buttons">
              <button className="pagination-btn" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>‹</button>
              <button className="pagination-btn" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>›</button>
            </div>
          </div>
        )}
      </div>

      {/* ── Reset Password — ResponsiveModal (bottom-sheet on mobile) ── */}
      <ResponsiveModal
        open={!!resetModal}
        onClose={() => { setResetModal(null); setNewPassword('') }}
        title="إعادة تعيين كلمة المرور"
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div className="form-group">
            <label className="form-label required">كلمة المرور الجديدة</label>
            <input
              type="password" dir="ltr" className="form-input"
              placeholder="8 أحرف على الأقل"
              value={newPassword}
              onChange={e => setNewPassword(e.target.value)}
              autoFocus
            />
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, paddingTop: 4 }}>
            <Button onClick={handleResetPassword} loading={resetting} style={{ width: '100%', justifyContent: 'center' }}>
              <KeyRound size={14} /> تأكيد
            </Button>
            <Button variant="ghost" onClick={() => { setResetModal(null); setNewPassword('') }} style={{ width: '100%', justifyContent: 'center' }}>
              إلغاء
            </Button>
          </div>
        </div>
      </ResponsiveModal>

      {/* ── Toggle Status Confirm ── */}
      <ConfirmDialog
        open={!!confirmToggle}
        title={confirmToggle?.status === 'active' ? 'تعطيل المستخدم' : 'تفعيل المستخدم'}
        message={`هل تريد ${confirmToggle?.status === 'active' ? 'تعطيل' : 'تفعيل'} المستخدم "${confirmToggle?.full_name}"؟`}
        variant={confirmToggle?.status === 'active' ? 'danger' : 'info'}
        confirmText={confirmToggle?.status === 'active' ? 'تعطيل' : 'تفعيل'}
        loading={toggling}
        onConfirm={executeToggle}
        onCancel={() => setConfirmToggle(null)}
      />
    </div>
  )
}
