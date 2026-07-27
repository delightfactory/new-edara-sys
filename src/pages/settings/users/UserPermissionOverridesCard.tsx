import { useMemo, useState } from 'react'
import { ChevronDown, ChevronUp, Search, ShieldCheck } from 'lucide-react'
import { PERMISSION_GROUPS } from '@/lib/permissions/constants'
import type { UserPermissionContext, UserPermissionOverrideInput } from '@/lib/types/auth'

type OverrideMode = 'inherit' | 'grant' | 'revoke'

interface UserPermissionOverridesCardProps {
  context: UserPermissionContext
  selectedRoleIds: string[]
  value: UserPermissionOverrideInput[]
  onChange: (value: UserPermissionOverrideInput[]) => void
  disabled?: boolean
}

function toLocalDateTime(value: string | null): string {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  const offset = date.getTimezoneOffset() * 60_000
  return new Date(date.getTime() - offset).toISOString().slice(0, 16)
}

function toIsoDateTime(value: string): string | null {
  if (!value) return null
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? null : date.toISOString()
}

export function UserPermissionOverridesCard({
  context,
  selectedRoleIds,
  value,
  onChange,
  disabled = false,
}: UserPermissionOverridesCardProps) {
  const [search, setSearch] = useState('')
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(
    () => new Set(PERMISSION_GROUPS.map(group => group.id)),
  )

  const inheritedPermissions = useMemo(() => {
    const permissions = new Set<string>()
    for (const roleId of selectedRoleIds) {
      for (const permission of context.role_permissions_by_role[roleId] ?? []) {
        permissions.add(permission)
      }
    }
    return permissions
  }, [context.role_permissions_by_role, selectedRoleIds])

  const hasWildcard = inheritedPermissions.has('*')
  const overridesByPermission = useMemo(
    () => new Map(value.map(override => [override.permission, override])),
    [value],
  )

  const normalizedSearch = search.trim().toLocaleLowerCase('ar')
  const visibleGroups = useMemo(() => {
    if (!normalizedSearch) return PERMISSION_GROUPS
    return PERMISSION_GROUPS
      .map(group => ({
        ...group,
        permissions: group.permissions.filter(permission =>
          permission.label.toLocaleLowerCase('ar').includes(normalizedSearch)
          || permission.key.toLowerCase().includes(normalizedSearch),
        ),
      }))
      .filter(group => group.permissions.length > 0)
  }, [normalizedSearch])

  const grantedCount = value.filter(override => override.granted).length
  const revokedCount = value.length - grantedCount

  const setMode = (permission: string, mode: OverrideMode) => {
    const existing = overridesByPermission.get(permission)
    const remaining = value.filter(item => item.permission !== permission)
    if (mode === 'inherit') {
      onChange(remaining)
      return
    }

    onChange([
      ...remaining,
      {
        permission,
        granted: mode === 'grant',
        reason: existing?.reason ?? null,
        expires_at: existing?.expires_at ?? null,
      },
    ])
  }

  const updateOverride = (
    permission: string,
    updates: Partial<Pick<UserPermissionOverrideInput, 'reason' | 'expires_at'>>,
  ) => {
    onChange(value.map(item => item.permission === permission ? { ...item, ...updates } : item))
  }

  const toggleGroup = (groupId: string) => {
    setExpandedGroups(previous => {
      const next = new Set(previous)
      if (next.has(groupId)) next.delete(groupId)
      else next.add(groupId)
      return next
    })
  }

  return (
    <section className="edara-card user-permissions-card">
      <div className="user-permissions-header">
        <div className="user-permissions-title">
          <span className="user-permissions-icon"><ShieldCheck size={20} /></span>
          <div>
            <h3>الصلاحيات الفردية</h3>
            <p>الاستثناء الفردي يتقدم على صلاحيات الأدوار المحددة أعلاه.</p>
          </div>
        </div>
        <div className="user-permissions-summary" aria-label="ملخص الاستثناءات">
          <span className="badge badge-success">منح: {grantedCount}</span>
          <span className="badge badge-danger">سحب: {revokedCount}</span>
          {hasWildcard && <span className="badge badge-warning">الدور يمنح كل الصلاحيات</span>}
        </div>
      </div>

      <div className="user-permissions-help">
        «حسب الدور» لا يحفظ استثناءً. ويمكن استخدام «سحب» لمنع صلاحية حتى لو أُضيفت إلى دور المستخدم لاحقًا.
      </div>

      <label className="user-permissions-search">
        <span className="sr-only">البحث في الصلاحيات</span>
        <Search size={16} aria-hidden="true" />
        <input
          className="form-input"
          value={search}
          onChange={event => setSearch(event.target.value)}
          placeholder="ابحث باسم الصلاحية أو رمزها"
          disabled={disabled}
        />
      </label>

      <div className="user-permissions-groups">
        {visibleGroups.map(group => {
          const isExpanded = normalizedSearch.length > 0 || expandedGroups.has(group.id)
          const groupOverrideCount = group.permissions.filter(permission =>
            overridesByPermission.has(permission.key),
          ).length

          return (
            <div className="user-permissions-group" key={group.id}>
              <button
                className="user-permissions-group-toggle"
                type="button"
                onClick={() => toggleGroup(group.id)}
                aria-expanded={isExpanded}
              >
                <span>{group.label}</span>
                <span className="user-permissions-group-meta">
                  {groupOverrideCount > 0 && <span className="badge badge-primary">{groupOverrideCount} استثناء</span>}
                  {isExpanded ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
                </span>
              </button>

              {isExpanded && (
                <div className="user-permissions-list">
                  {group.permissions.map(permission => {
                    const override = overridesByPermission.get(permission.key)
                    const inherited = hasWildcard || inheritedPermissions.has(permission.key)
                    const mode: OverrideMode = override
                      ? (override.granted ? 'grant' : 'revoke')
                      : 'inherit'
                    const effective = override?.granted ?? inherited

                    return (
                      <div className="user-permission-row" key={permission.key}>
                        <div className="user-permission-main">
                          <div className="user-permission-name">
                            <span>{permission.label}</span>
                            <code dir="ltr">{permission.key}</code>
                          </div>
                          <div className="user-permission-state">
                            <span className={`badge ${effective ? 'badge-success' : 'badge-neutral'}`}>
                              {effective ? 'مسموح فعليًا' : 'غير مسموح'}
                            </span>
                            {inherited && <span className="badge badge-info">موروثة</span>}
                          </div>
                          <label>
                            <span className="sr-only">تخصيص صلاحية {permission.label}</span>
                            <select
                              className="form-input user-permission-mode"
                              value={mode}
                              onChange={event => setMode(permission.key, event.target.value as OverrideMode)}
                              disabled={disabled}
                            >
                              <option value="inherit">حسب الدور</option>
                              <option value="grant">منح استثنائي</option>
                              <option value="revoke">سحب استثنائي</option>
                            </select>
                          </label>
                        </div>

                        {override && (
                          <div className="user-permission-details">
                            <label className="form-group">
                              <span className="form-label">سبب الاستثناء</span>
                              <input
                                className="form-input"
                                value={override.reason ?? ''}
                                onChange={event => updateOverride(permission.key, {
                                  reason: event.target.value || null,
                                })}
                                maxLength={500}
                                placeholder="اختياري"
                                disabled={disabled}
                              />
                            </label>
                            <label className="form-group">
                              <span className="form-label">ينتهي في</span>
                              <input
                                className="form-input"
                                type="datetime-local"
                                dir="ltr"
                                value={toLocalDateTime(override.expires_at)}
                                min={toLocalDateTime(new Date().toISOString())}
                                onChange={event => updateOverride(permission.key, {
                                  expires_at: toIsoDateTime(event.target.value),
                                })}
                                disabled={disabled}
                              />
                              <span className="form-hint">اتركه فارغًا لاستثناء دائم.</span>
                            </label>
                          </div>
                        )}
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          )
        })}

        {visibleGroups.length === 0 && (
          <div className="user-permissions-empty">لا توجد صلاحيات مطابقة للبحث.</div>
        )}
      </div>

      <style>{`
        .user-permissions-card { padding: var(--space-6); margin-bottom: var(--space-4); }
        .user-permissions-card .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0; }
        .user-permissions-header { display: flex; align-items: flex-start; justify-content: space-between; gap: var(--space-4); }
        .user-permissions-title { display: flex; align-items: flex-start; gap: var(--space-3); }
        .user-permissions-title h3 { font-size: var(--text-lg); font-weight: 700; line-height: 1.3; }
        .user-permissions-title p { color: var(--text-secondary); font-size: var(--text-sm); line-height: 1.7; margin-top: 2px; }
        .user-permissions-icon { display: grid; place-items: center; width: 40px; height: 40px; border-radius: var(--radius-md); background: var(--color-primary-light); color: var(--color-primary); flex-shrink: 0; }
        .user-permissions-summary { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: var(--space-2); }
        .user-permissions-help { margin-block: var(--space-4); padding: var(--space-3) var(--space-4); border-inline-start: 3px solid var(--color-info); border-radius: var(--radius-sm); background: var(--bg-surface-2); color: var(--text-secondary); font-size: var(--text-sm); line-height: 1.7; }
        .user-permissions-search { position: relative; display: block; margin-bottom: var(--space-4); }
        .user-permissions-search > svg { position: absolute; inset-inline-start: 13px; top: 50%; transform: translateY(-50%); color: var(--text-muted); pointer-events: none; }
        .user-permissions-search .form-input { padding-inline-start: 38px; min-height: var(--touch-target); }
        .user-permissions-groups { display: flex; flex-direction: column; gap: var(--space-2); }
        .user-permissions-group { border: 1px solid var(--border-primary); border-radius: var(--radius-md); overflow: hidden; }
        .user-permissions-group-toggle { width: 100%; min-height: var(--touch-target); display: flex; align-items: center; justify-content: space-between; gap: var(--space-3); padding: var(--space-3) var(--space-4); border: 0; background: var(--bg-surface-2); color: var(--text-primary); font: inherit; font-weight: 700; cursor: pointer; text-align: start; }
        .user-permissions-group-meta, .user-permission-state { display: flex; align-items: center; flex-wrap: wrap; gap: var(--space-2); }
        .user-permissions-list { display: flex; flex-direction: column; }
        .user-permission-row { padding: var(--space-3) var(--space-4); border-top: 1px solid var(--border-primary); }
        .user-permission-main { display: grid; grid-template-columns: minmax(220px, 1fr) minmax(170px, auto) minmax(160px, 210px); align-items: center; gap: var(--space-3); }
        .user-permission-name { min-width: 0; }
        .user-permission-name > span { display: block; font-size: var(--text-sm); font-weight: 600; line-height: 1.7; }
        .user-permission-name code { display: block; color: var(--text-muted); font-size: var(--text-xs); overflow-wrap: anywhere; text-align: start; }
        .user-permission-mode { min-height: var(--touch-target); }
        .user-permission-details { display: grid; grid-template-columns: minmax(220px, 1fr) minmax(220px, 1fr); gap: var(--space-3); margin-top: var(--space-3); padding: var(--space-3); border-radius: var(--radius-sm); background: var(--bg-surface-2); }
        .user-permission-details .form-group { margin: 0; }
        .user-permissions-empty { padding: var(--space-6); text-align: center; color: var(--text-muted); }
        @media (max-width: 768px) {
          .user-permissions-card { padding: var(--space-4); }
          .user-permissions-header { flex-direction: column; }
          .user-permissions-summary { justify-content: flex-start; }
          .user-permission-main { grid-template-columns: 1fr; }
          .user-permission-details { grid-template-columns: 1fr; }
          .user-permission-row { padding: var(--space-4); }
        }
      `}</style>
    </section>
  )
}
