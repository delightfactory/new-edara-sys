import { describe, expect, it, vi } from 'vitest'
import { getPrimaryResolvedAction, resolveActionSet, type AppAction } from './ActionRegistry'

function action(id: string, overrides: Partial<AppAction> = {}): AppAction {
  return {
    id,
    label: id,
    onSelect: vi.fn(),
    ...overrides,
  }
}

describe('ActionRegistry', () => {
  it('shows one visible action on mobile and moves the rest to overflow', () => {
    const actions = [
      action('secondary'),
      action('primary', { importance: 'primary' }),
      action('tertiary', { importance: 'tertiary' }),
    ]

    const resolved = resolveActionSet(actions, 'mobile')

    expect(resolved.visible.map(a => a.id)).toEqual(['primary'])
    expect(resolved.overflow.map(a => a.id)).toEqual(['secondary', 'tertiary'])
  })

  it('allows two visible actions on tablet and four on desktop', () => {
    const actions = [
      action('a', { importance: 'primary' }),
      action('b'),
      action('c'),
      action('d', { importance: 'tertiary' }),
      action('e', { importance: 'tertiary' }),
    ]

    expect(resolveActionSet(actions, 'tablet').visible.map(a => a.id)).toEqual(['a', 'b'])
    expect(resolveActionSet(actions, 'desktop').visible.map(a => a.id)).toEqual(['a', 'b', 'c', 'd'])
  })

  it('filters hidden and device-ineligible actions before resolving placement', () => {
    const actions = [
      action('hidden', { hidden: true, importance: 'primary' }),
      action('desktop-only', { availableOn: ['desktop'], importance: 'primary' }),
      action('mobile-ok'),
    ]

    expect(resolveActionSet(actions, 'mobile').visible.map(a => a.id)).toEqual(['mobile-ok'])
    expect(resolveActionSet(actions, 'desktop').visible.map(a => a.id)).toEqual(['desktop-only', 'mobile-ok'])
  })

  it('keeps ordering deterministic inside the same importance level', () => {
    const actions = [
      action('later', { order: 20 }),
      action('first', { order: -10 }),
      action('middle', { order: 0 }),
    ]

    expect(resolveActionSet(actions, 'desktop').visible.map(a => a.id)).toEqual(['first', 'middle', 'later'])
  })

  it('returns the first resolved visible action as the primary device action', () => {
    const actions = [action('secondary'), action('primary', { importance: 'primary' })]
    expect(getPrimaryResolvedAction(actions, 'mobile')?.id).toBe('primary')
  })
})
