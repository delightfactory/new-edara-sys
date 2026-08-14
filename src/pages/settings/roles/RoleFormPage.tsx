import { useEffect, useState, type CSSProperties, type FormEvent, type KeyboardEvent } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { Save, ArrowRight, Loader2, CheckSquare, Square, Shield, ChevronDown, ChevronUp } from 'lucide-react'
import { getRole, createRole, updateRole } from '@/lib/services/users'
import { PERMISSION_GROUPS } from '@/lib/permissions/constants'
import { WORK_PERMISSION_GROUP } from '@/lib/permissions/work'

const ROLE_PERMISSION_GROUPS = [...PERMISSION_GROUPS, WORK_PERMISSION_GROUP] as const

type PermissionGroup = (typeof ROLE_PERMISSION_GROUPS)[number]

export default function RoleFormPage() {
  const navigate = useNavigate()
  const { id } = useParams()
  const isEdit = Boolean(id)

  const [loading, setLoading] = useState(isEdit)
  const [saving, setSaving] = useState(false)
  const [name, setName] = useState('')
  const [nameAr, setNameAr] = useState('')
  const [description, setDescription] = useState('')
  const [color, setColor] = useState('#6b7280')
  const [isSystem, setIsSystem] = useState(false)
  const [selectedPerms, setSelectedPerms] = useState<Set<string>>(new Set())
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(new Set())

  useEffect(() => {
    setExpandedGroups(new Set(ROLE_PERMISSION_GROUPS.map(group => group.id)))
  }, [])

  useEffect(() => {
    if (!isEdit || !id) return

    getRole(id).then(role => {
      setName(role.name)
      setNameAr(role.name_ar)
      setDescription(role.description || '')
      setColor(role.color || '#6b7280')
      setIsSystem(role.is_system)
      const perms = role.role_permissions?.map(rp => rp.permission) || []
      if (perms.includes('*')) {
        const allPerms = ROLE_PERMISSION_GROUPS.flatMap(group => group.permissions.map(permission => permission.key))
        setSelectedPerms(new Set(allPerms))
      } else {
        setSelectedPerms(new Set(perms))
      }
      setLoading(false)
    }).catch(() => {
      toast.error('فشل تحميل الدور')
      navigate('/settings/roles')
    })
  }, [id, isEdit, navigate])

  const togglePerm = (perm: string) => {
    setSelectedPerms(previous => {
      const next = new Set(previous)
      next.has(perm) ? next.delete(perm) : next.add(perm)
      return next
    })
  }

  const toggleGroup = (group: PermissionGroup) => {
    const allSelected = group.permissions.every(permission => selectedPerms.has(permission.key))
    setSelectedPerms(previous => {
      const next = new Set(previous)
      for (const permission of group.permissions) {
        allSelected ? next.delete(permission.key) : next.add(permission.key)
      }
      return next
    })
  }

  const toggleExpandGroup = (groupId: string) => {
    setExpandedGroups(previous => {
      const next = new Set(previous)
      next.has(groupId) ? next.delete(groupId) : next.add(groupId)
      return next
    })
  }

  const handleGroupKeyDown = (event: KeyboardEvent<HTMLDivElement>, groupId: string) => {
    if (event.key !== 'Enter' && event.key !== ' ') return
    event.preventDefault()
    toggleExpandGroup(groupId)
  }

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault()
    if (!nameAr.trim()) { toast.error('اسم الدور بالعربية مطلوب'); return }
    if (!isEdit && !name.trim()) { toast.error('الاسم البرمجي مطلوب'); return }
    if (selectedPerms.size === 0) { toast.error('يرجى تحديد صلاحية واحدة على الأقل'); return }

    setSaving(true)
    try {
      const allPermsKeys = ROLE_PERMISSION_GROUPS.flatMap(group => group.permissions.map(permission => permission.key))
      const allSelected = allPermsKeys.every(key => selectedPerms.has(key))
      const perms = allSelected ? ['*'] : Array.from(selectedPerms)

      if (isEdit && id) {
        await updateRole(id, { name_ar: nameAr, description, color }, perms)
        toast.success('تم تحديث الدور بنجاح')
      } else {
        await createRole({ name, name_ar: nameAr, description, color }, perms)
        toast.success('تم إنشاء الدور بنجاح')
      }
      navigate('/settings/roles')
    } catch (error: unknown) {
      toast.error(error instanceof Error ? error.message : 'فشلت العملية')
    } finally {
      setSaving(false)
    }
  }

  const totalPerms = ROLE_PERMISSION_GROUPS.reduce((sum, group) => sum + group.permissions.length, 0)

  if (loading) {
    return (
      <div className="page-container">
        <div className="skeleton" style={{ height: 32, width: 200, marginBottom: 24 }} />
        <div className="skeleton" style={{ height: 160, marginBottom: 16 }} />
        {[1, 2, 3].map(item => <div key={item} className="skeleton" style={{ height: 100, marginBottom: 12 }} />)}
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">
      <div className="page-header">
        <div className="page-header-info">
          <h1 className="page-title">
            {isEdit ? (
              <span className="flex items-center gap-3">
                <span
                  aria-hidden="true"
                  style={{ width: 12, height: 12, borderRadius: '50%', background: color, display: 'inline-block' }}
                />
                تعديل: {nameAr}
              </span>
            ) : 'إنشاء دور جديد'}
          </h1>
          <p className="page-subtitle">{isEdit ? 'تعديل بيانات الدور وصلاحياته' : 'حدد اسم الدور والصلاحيات المسموحة'}</p>
        </div>
        <button className="btn btn-secondary" onClick={() => navigate('/settings/roles')}>
          <ArrowRight size={16} /> رجوع
        </button>
      </div>

      <form onSubmit={handleSubmit}>
        <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-5)' }}>
          <div className="flex items-center gap-3" style={{ marginBottom: 'var(--space-5)' }}>
            <div style={{
              width: 40,
              height: 40,
              borderRadius: 'var(--radius-md)',
              background: `${color}18`,
              color,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}>
              <Shield size={20} />
            </div>
            <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>بيانات الدور</h3>
            {isSystem && <span className="badge badge-info">دور نظامي</span>}
          </div>

          <div className="grid grid-2 gap-4">
            <div className="form-group">
              <label className="form-label required" htmlFor="role-name-ar">الاسم بالعربية</label>
              <input id="role-name-ar" className="form-input" value={nameAr} onChange={event => setNameAr(event.target.value)} placeholder="مثال: مدير فرع" autoFocus />
            </div>
            <div className="form-group">
              <label className="form-label required" htmlFor="role-slug">الاسم البرمجي (slug)</label>
              <input
                id="role-slug"
                className="form-input"
                dir="ltr"
                value={name}
                onChange={event => setName(event.target.value.toLowerCase().replace(/[^a-z0-9_]/g, '_'))}
                placeholder="branch_manager"
                disabled={isEdit}
                style={{ fontFamily: 'monospace' }}
              />
              {isEdit && <span className="form-hint">لا يمكن تعديل الاسم البرمجي بعد الإنشاء</span>}
            </div>
            <div className="form-group">
              <label className="form-label" htmlFor="role-description">الوصف</label>
              <input id="role-description" className="form-input" value={description} onChange={event => setDescription(event.target.value)} placeholder="وصف مختصر (اختياري)" />
            </div>
            <div className="form-group">
              <label className="form-label" htmlFor="role-color">لون الدور</label>
              <div className="flex items-center gap-3">
                <input id="role-color" type="color" value={color} onChange={event => setColor(event.target.value)} style={{ width: 40, height: 36, border: 'none', cursor: 'pointer', borderRadius: 'var(--radius-sm)', padding: 0 }} />
                <input className="form-input" dir="ltr" value={color} onChange={event => setColor(event.target.value)} aria-label="قيمة لون الدور" style={{ flex: 1, fontFamily: 'monospace' }} />
                <span className="badge" style={{ background: `${color}18`, color }}>معاينة</span>
              </div>
            </div>
          </div>
        </div>

        <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-5)' }}>
          <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-5)' }}>
            <div>
              <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>مصفوفة الصلاحيات</h3>
              <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 2 }} aria-live="polite">
                {selectedPerms.size} صلاحية محددة من أصل {totalPerms}
              </p>
            </div>
            <div className="flex gap-2">
              <button type="button" className="btn btn-ghost btn-sm" onClick={() => setSelectedPerms(new Set(ROLE_PERMISSION_GROUPS.flatMap(group => group.permissions.map(permission => permission.key))))}>
                تحديد الكل
              </button>
              <button type="button" className="btn btn-ghost btn-sm" onClick={() => setSelectedPerms(new Set())}>
                إزالة الكل
              </button>
            </div>
          </div>

          <div style={{ height: 6, background: 'var(--bg-surface-2)', borderRadius: 99, marginBottom: 'var(--space-5)', overflow: 'hidden' }} aria-hidden="true">
            <div style={{
              height: '100%',
              borderRadius: 99,
              transition: 'width 0.3s ease',
              background: `linear-gradient(90deg, ${color}, var(--color-primary))`,
              width: `${totalPerms ? (selectedPerms.size / totalPerms) * 100 : 0}%`,
            }} />
          </div>

          <div className="flex flex-col" style={{ gap: 2 }}>
            {ROLE_PERMISSION_GROUPS.map(group => {
              const groupSelected = group.permissions.filter(permission => selectedPerms.has(permission.key)).length
              const allSelected = groupSelected === group.permissions.length
              const noneSelected = groupSelected === 0
              const isExpanded = expandedGroups.has(group.id)
              const panelId = `permission-group-${group.id}`

              return (
                <div key={group.id} style={{
                  borderRadius: 'var(--radius-md)',
                  overflow: 'hidden',
                  border: `1px solid ${allSelected ? `${color}40` : 'var(--divider)'}`,
                  background: allSelected ? `${color}05` : 'transparent',
                  transition: 'all 0.2s ease',
                }}>
                  <div
                    className="flex items-center permission-group-header"
                    role="button"
                    tabIndex={0}
                    aria-expanded={isExpanded}
                    aria-controls={panelId}
                    onClick={() => toggleExpandGroup(group.id)}
                    onKeyDown={event => handleGroupKeyDown(event, group.id)}
                    style={{ padding: 'var(--space-3) var(--space-4)', cursor: 'pointer', userSelect: 'none' }}
                  >
                    <button
                      type="button"
                      aria-label={allSelected ? `إلغاء تحديد كل صلاحيات ${group.label}` : `تحديد كل صلاحيات ${group.label}`}
                      style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 2, marginLeft: 'var(--space-3)', color: allSelected ? color : noneSelected ? 'var(--text-muted)' : 'var(--color-warning)' }}
                      onClick={event => { event.stopPropagation(); toggleGroup(group) }}
                    >
                      {allSelected ? <CheckSquare size={18} /> : <Square size={18} />}
                    </button>

                    <span style={{ fontWeight: 700, fontSize: 'var(--text-sm)', flex: 1 }}>{group.label}</span>
                    <span className="badge" style={{ background: allSelected ? `${color}18` : 'var(--bg-surface-2)', color: allSelected ? color : 'var(--text-muted)', fontSize: 10, marginLeft: 'var(--space-2)' }}>
                      {groupSelected}/{group.permissions.length}
                    </span>
                    {isExpanded ? <ChevronUp size={14} style={{ color: 'var(--text-muted)' }} /> : <ChevronDown size={14} style={{ color: 'var(--text-muted)' }} />}
                  </div>

                  {isExpanded && (
                    <div
                      id={panelId}
                      className="perm-grid"
                      style={{ padding: '0 var(--space-4) var(--space-4)', '--perm-active-color': color } as CSSProperties}
                    >
                      {group.permissions.map(permission => {
                        const isSelected = selectedPerms.has(permission.key)
                        return (
                          <label
                            key={permission.key}
                            className="perm-checkbox-label"
                            style={{
                              border: `1px solid ${isSelected ? `${color}30` : 'transparent'}`,
                              background: isSelected ? `${color}08` : 'var(--bg-surface-2)',
                              fontWeight: isSelected ? 600 : 400,
                              color: isSelected ? 'var(--text-primary)' : 'var(--text-secondary)',
                            }}
                          >
                            <input type="checkbox" checked={isSelected} onChange={() => togglePerm(permission.key)} style={{ accentColor: color }} />
                            <span>{permission.label}</span>
                          </label>
                        )
                      })}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        </div>

        <div className="flex gap-3" style={{ justifyContent: 'flex-end', position: 'sticky', bottom: 0, padding: 'var(--space-4) 0', background: 'var(--bg-app)', borderTop: '1px solid var(--border-primary)', flexWrap: 'wrap' }}>
          <button type="button" className="btn btn-secondary" onClick={() => navigate('/settings/roles')}>إلغاء</button>
          <button type="submit" className="btn btn-primary btn-lg" disabled={saving}>
            {saving ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />}
            {isEdit ? 'حفظ التعديلات' : 'إنشاء الدور'}
            {selectedPerms.size > 0 && <span style={{ fontSize: 'var(--text-xs)', opacity: 0.8, marginRight: 'var(--space-1)' }}>({selectedPerms.size} صلاحية)</span>}
          </button>
        </div>
      </form>

      <style>{`
        .permission-group-header:focus-visible {
          outline: 2px solid var(--color-primary);
          outline-offset: -2px;
        }
        .perm-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
          gap: var(--space-2);
        }
        .perm-checkbox-label {
          display: flex;
          align-items: center;
          gap: 8px;
          cursor: pointer;
          font-size: var(--text-xs);
          padding: var(--space-2) var(--space-3);
          border-radius: var(--radius-sm);
          transition: all 0.15s ease;
        }
        @media (prefers-reduced-motion: reduce) {
          .perm-checkbox-label,
          .perm-checkbox-label input[type="checkbox"],
          .perm-checkbox-label input[type="checkbox"]::after {
            transition: none !important;
          }
        }
        @media (max-width: 768px) {
          .form-group .grid-2 { grid-template-columns: 1fr; }
          .perm-grid {
            display: flex;
            flex-direction: column;
            gap: 0;
          }
          .perm-checkbox-label {
            justify-content: space-between;
            flex-direction: row-reverse;
            padding: 11px var(--space-4);
            border-radius: 0;
            border-bottom: 1px solid var(--border-primary);
            font-size: var(--text-sm);
            font-weight: 500;
          }
          .perm-checkbox-label:last-child { border-bottom: none; }
          .perm-checkbox-label input[type="checkbox"] {
            appearance: none;
            -webkit-appearance: none;
            width: 42px;
            height: 24px;
            border-radius: 12px;
            background: var(--bg-surface-2);
            border: 1.5px solid var(--border-primary);
            cursor: pointer;
            position: relative;
            flex-shrink: 0;
            transition: background 0.2s ease, border-color 0.2s ease;
          }
          .perm-checkbox-label input[type="checkbox"]::after {
            content: '';
            position: absolute;
            top: 2px;
            right: 2px;
            width: 18px;
            height: 18px;
            border-radius: 50%;
            background: white;
            box-shadow: 0 1px 3px rgba(0,0,0,0.2);
            transition: transform 0.22s cubic-bezier(0.34, 1.56, 0.64, 1);
          }
          .perm-checkbox-label input[type="checkbox"]:checked {
            background: var(--perm-active-color, var(--color-primary));
            border-color: transparent;
          }
          .perm-checkbox-label input[type="checkbox"]:checked::after {
            transform: translateX(-18px);
          }
        }
      `}</style>
    </div>
  )
}
