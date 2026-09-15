import type { ReactNode } from 'react'
import type { DeviceMode } from '@/hooks/useDeviceMode'

export type ActionImportance = 'primary' | 'secondary' | 'tertiary'
export type ActionTone = 'primary' | 'secondary' | 'success' | 'danger' | 'ghost'

export interface AppAction {
  id: string
  label: string
  icon?: ReactNode
  onSelect: () => void
  importance?: ActionImportance
  tone?: ActionTone
  disabled?: boolean
  loading?: boolean
  hidden?: boolean
  order?: number
  availableOn?: DeviceMode[]
  ariaLabel?: string
}

export interface ResolvedActionSet {
  visible: AppAction[]
  overflow: AppAction[]
}

const importanceRank: Record<ActionImportance, number> = {
  primary: 0,
  secondary: 1,
  tertiary: 2,
}

const visibleLimit: Record<DeviceMode, number> = {
  mobile: 1,
  tablet: 2,
  desktop: 4,
}

/**
 * resolveActionSet — deterministic, device-aware action prioritization.
 *
 * Pages declare action meaning and importance. Presentation surfaces decide
 * later whether the resolved visible action becomes a header button, sticky
 * action, or FAB. This keeps domain pages from owning placement rules.
 */
export function resolveActionSet(actions: AppAction[], device: DeviceMode): ResolvedActionSet {
  const eligible = actions
    .map((action, index) => ({ action, index }))
    .filter(({ action }) => {
      if (action.hidden) return false
      if (action.availableOn && !action.availableOn.includes(device)) return false
      return true
    })
    .sort((a, b) => {
      const aImportance = importanceRank[a.action.importance ?? 'secondary']
      const bImportance = importanceRank[b.action.importance ?? 'secondary']
      if (aImportance !== bImportance) return aImportance - bImportance

      const aOrder = a.action.order ?? 0
      const bOrder = b.action.order ?? 0
      if (aOrder !== bOrder) return aOrder - bOrder

      return a.index - b.index
    })
    .map(({ action }) => action)

  const limit = visibleLimit[device]
  return {
    visible: eligible.slice(0, limit),
    overflow: eligible.slice(limit),
  }
}

export function getPrimaryResolvedAction(actions: AppAction[], device: DeviceMode): AppAction | undefined {
  return resolveActionSet(actions, device).visible[0]
}
