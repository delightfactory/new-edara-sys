import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { Save, ArrowRight, Loader2, CheckSquare, Square, Shield, ChevronDown, ChevronUp } from 'lucide-react'
import { getRole, createRole, updateRole } from '@/lib/services/users'
import { PERMISSION_GROUPS } from '@/lib/permissions/constants'

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

  // Expand all groups by default
  useEffect(() => {
    setExpandedGroups(new Set(PERMISSION_GROUPS.map(g => g.id)))
  }, [])

  useEffect(() => {
    if (isEdit && id) {
      getRole(id).then(role => {
        setName(role.name)
        setNameAr(role.name_ar)
        setDescription(role.description || '')
        setColor(role.color || '#6b7280')
        setIsSystem(role.is_system)
        const perms = role.role_permissions?.map(rp => rp.permission) || []
        // إذا كان الدور يملك wildcard ← نحدد كل الصلاحيات
        if (perms.includes('*')) {
          const allPerms = PERMISSION_GROUPS.flatMap(g => g.permissions.map(p => p.key))
          setSelectedPerms(new Set(allPerms))
        } else {
          setSelectedPerms(new Set(perms))
        }
        setLoading(false)
      }).catch(() => {
        toast.error('فشل تحميل الدور')
        navigate('/settings/roles')
      })
    }
  }, [id])

  const togglePerm = (perm: string) => {
    setSelectedPerms(prev => {
      const next = new Set(prev)
      next.has(perm) ? next.delete(perm) : next.add(perm)
      return next
    })
  }

  const toggleGroup = (group: typeof PERMISSION_GROUPS[number]) => {
    const allSelected = group.permissions.every(p => selectedPerms.has(p.key))
    setSelectedPerms(prev => {
      const next = new Set(prev)
      for (const p of group.permissions) {
        allSelected ? next.delete(p.key) : next.add(p.key)
      }
      return next
    })
  }

  const toggleExpandGroup = (groupId: string) => {
    setExpandedGroups(prev => {
      const next = new Set(prev)
      next.has(groupId) ? next.delete(groupId) : next.add(groupId)
      return next
    })
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!nameAr.trim()) { toast.error('اسم الدور بالعربية مطلوب'); return }
    if (!isEdit && !name.trim()) { toast.error('الاسم البرمجي مطلوب'); return }
    if (selectedPerms.size === 0) { toast.error('يرجى تحديد صلاحية واحدة على الأقل'); return }

    setSaving(true)
    try {
      // إذا كل الصلاحيات محددة ← نحفظ `*` بدلاً من إدخالها واحدة واحدة
      const allPermsKeys = PERMISSION_GROUPS.flatMap(g => g.permissions.map(p => p.key))
      const allSelected = allPermsKeys.every(k => selectedPerms.has(k))
      const perms = allSelected ? ['*'] : Array.from(selectedPerms)

      if (isEdit && id) {
        await updateRole(id, { name_ar: nameAr, description, color }, perms)
        toast.success('تم تحديث الدور بنجاح')
      } else {
        await createRole({ name, name_ar: nameAr, description, color }, perms)
        toast.success('تم إنشاء الدور بنجاح')
      }
      navigate('/settings/roles')
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'فشلت العملية')
    } finally { setSaving(false) }
  }

  const totalPerms = PERMISSION_GROUPS.reduce((sum, g) => sum + g.permissions.length, 0)

  if (loading) {
    return (
      <div className="page-container">
        <div className="skeleton" style={{ height: 32, width: 200, marginBottom: 24 }} />
        <div className="skeleton" style={{ height: 160, marginBottom: 16 }} />
        {[1,2,3].map(i => <div key={i} className="skeleton" style={{ height: 100, marginBottom: 12 }} />)}
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
                <span style={{
                  width: 12, height: 12, borderRadius: '50%',
                  background: color, display: 'inline-block',
                }} />
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
        {/* Basic Info Card */}
        <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-5)' }}>
          <div className="flex items-center gap-3" style={{ marginBottom: 'var(--space-5)' }}>
            <div style={{
              width: 40, height: 40, borderRadius: 'var(--radius-md)',
              background: `${color}18`, color: color,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <Shield size={20} />
            </div>
            <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>بيانات الدور</h3>
            {isSystem && <span className="badge badge-info">دور نظامي</span>}
          </div>

          <div className="grid grid-2 gap-4">
            <div className="form-group">
              <label className="form-label required">الاسم بالعربية</label>
              <input className="form-input" value={nameAr} onChange={e => setNameAr(e.target.value)}
                placeholder="مثال: مدير فرع" autoFocus />
            </div>
            <div className="form-group">
              <label className="form-label required">الاسم البرمجي (slug)</label>
              <input className="form-input" dir="ltr" value={name}
                onChange={e => setName(e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, '_'))}
                placeholder="branch_manager"
                disabled={isEdit}
                style={{ fontFamily: 'monospace' }}
              />
              {isEdit && <span className="form-hint">لا يمكن تعديل الاسم البرمجي بعد الإنشاء</span>}
            </div>
            <div className="form-group">
              <label className="form-label">الوصف</label>
              <input className="form-input" value={description} onChange={e => setDescription(e.target.value)}
                placeholder="وصف مختصر (اختياري)" />
            </div>
            <div className="form-group">
              <label className="form-label">لون الدور</label>
              <div className="flex items-center gap-3">
                <input type="color" value={color} onChange={e => setColor(e.target.value)}
                  style={{ width: 40, height: 36, border: 'none', cursor: 'pointer', borderRadius: 'var(--radius-sm)', padding: 0 }} />
                <input className="form-input" dir="ltr" value={color} onChange={e => setColor(e.target.value)}
                  style={{ flex: 1, fontFamily: 'monospace' }} />
                <span className="badge" style={{ background: `${color}18`, color: color }}>معاينة</span>
              </div>
            </div>
          </div>
        </div>

        {/* Permissions Card */}
        <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-5)' }}>
          <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-5)' }}>
            <div>
              <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>مصفوفة الصلاحيات</h3>
              <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 2 }}>
                {selectedPerms.size} صلاحية محددة من أصل {totalPerms}
              </p>
            </div>
            <div className="flex gap-2">
              <button type="button" className="btn btn-ghost btn-sm"
                onClick={() => setSelectedPerms(new Set(PERMISSION_GROUPS.flatMap(g => g.permissions.map(p => p.key))))}>
                تحديد الكل
              </button>
              <button type="button" className="btn btn-ghost btn-sm"
                onClick={() => setSelectedPerms(new Set())}>
                إزالة الكل
              </button>
            </div>
          </div>

          {/* Progress Bar */}
          <div style={{
            height: 6, background: 'var(--bg-surface-2)', borderRadius: 99,
            marginBottom: 'var(--space-5)', overflow: 'hidden',
          }}>
            <div style={{
              height: '100%', borderRadius: 99, transition: 'width 0.3s ease',
              background: `linear-gradient(90deg, ${color}, var(--color-primary))`,
              width: `${(selectedPerms.size / totalPerms) * 100}%`,
            }} />
          </div>

          {/* Groups */}
          <div className="flex flex-col" style={{ gap: 2 }}>
            {PERMISSION_GROUPS.map(group => {
              const groupSelected = group.permissions.filter(p => selectedPerms.has(p.key)).length
              const allSelected = groupSelected === group.permissions.length
              const noneSelected = groupSelected === 0
              const isExpanded = expandedGroups.has(group.id)

              return (
                <div key={group.id} style={{
                  borderRadius: 'var(--radius-md)', overflow: 'hidden',
                  border: `1px solid ${allSelected ? `${color}40` : 'var(--divider)'}`,
                  background: allSelected ? `${color}05` : 'transparent',
                  transition: 'all 0.2s ease',
                }}>
                  {/* Group Header */}
                  <div className="flex items-center" style={{
                    padding: 'var(--space-3) var(--space-4)',
                    cursor: 'pointer', userSelect: 'none',
                  }}
                    onClick={() => toggleExpandGroup(group.id)}
                  >
                    {/* Select All checkbox */}
                    <button type="button" style={{
                      background: 'none', border: 'none', cursor: 'pointer',
                      padding: 2, marginLeft: 'var(--space-3)',
                      color: allSelected ? color : noneSelected ? 'var(--text-muted)' : 'var(--color-warning)',
                    }} onClick={(e) => { e.stopPropagation(); toggleGroup(group) }}>
                      {allSelected
                        ? <CheckSquare size={18} />
                        : <Square size={18} />
                      }
                    </button>

                    <span style={{ fontWeight: 700, fontSize: 'var(--text-sm)', flex: 1 }}>{group.label}</span>

                    <span className="badge" style={{
                      background: allSelected ? `${color}18` : 'var(--bg-surface-2)',
                      color: allSelected ? color : 'var(--text-muted)',
                      fontSize: 10, marginLeft: 'var(--space-2)',
                    }}>
                      {groupSelected}/{group.permissions.length}
                    </span>

                    {isExpanded ? <ChevronUp size={14} style={{ color: 'var(--text-muted)' }} /> : <ChevronDown size={14} style={{ color: 'var(--text-muted)' }} />}
                  </div>

                  {/* Group Permissions */}
                  {isExpanded && (
                    <div
                      className="perm-grid"
                      style={{
                        padding: '0 var(--space-4) var(--space-4)',
                        '--perm-active-color': color,
                      } as React.CSSProperties}
                    >
                      {group.permissions.map(perm => {
                        const isSelected = selectedPerms.has(perm.key)
                        return (
                          <label key={perm.key}
                            className="perm-checkbox-label"
                            style={{
                              border: `1px solid ${isSelected ? `${color}30` : 'transparent'}`,
                              background: isSelected ? `${color}08` : 'var(--bg-surface-2)',
                              fontWeight: isSelected ? 600 : 400,
                              color: isSelected ? 'var(--text-primary)' : 'var(--text-secondary)',
                            }}
                          >
                            <input type="checkbox" checked={isSelected} onChange={() => togglePerm(perm.key)}
                              style={{ accentColor: color }} />
                            <span>{perm.label}</span>
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

        {/* Action Buttons */}
        <div className="flex gap-3" style={{
          justifyContent: 'flex-end', position: 'sticky',
          bottom: 0, padding: 'var(--space-4) 0',
          background: 'var(--bg-app)',
          borderTop: '1px solid var(--border-primary)',
          flexWrap: 'wrap',
        }}>
          <button type="button" className="btn btn-secondary" onClick={() => navigate('/settings/roles')}>إلغاء</button>
          <button type="submit" className="btn btn-primary btn-lg" disabled={saving}>
            {saving ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />}
            {isEdit ? 'حفظ التعديلات' : 'إنشاء الدور'}
            {selectedPerms.size > 0 && (
              <span style={{ fontSize: 'var(--text-xs)', opacity: 0.8, marginRight: 'var(--space-1)' }}>
                ({selectedPerms.size} صلاحية)
              </span>
            )}
          </button>
        </div>
      </form>

      <style>{`
        /* ── Permission Group Layout ─────────────────────── */

        /* Desktop: current grid approach (unchanged) */
        .perm-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
          gap: var(--space-2);
        }
        .perm-checkbox-label {
          display: flex; align-items: center; gap: 8px;
          cursor: pointer; font-size: var(--text-xs);
          padding: var(--space-2) var(--space-3);
          border-radius: var(--radius-sm);
          transition: all 0.15s ease;
        }

        /* Mobile: Switch to native-feel toggle list */
        @media (max-width: 768px) {
          .form-group .grid-2 { grid-template-columns: 1fr; }

          /* Override grid → vertical list */
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
          .perm-checkbox-label:last-child {
            border-bottom: none;
          }

          /* Hide the checkbox, show a toggle switch */
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
