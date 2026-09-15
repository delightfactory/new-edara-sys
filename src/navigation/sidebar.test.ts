import { describe, expect, it } from 'vitest'
import { NAVIGATION_DESTINATIONS } from './registry'
import { getVisibleSidebarSections, SIDEBAR_SECTIONS } from './sidebar'

const allowAll = {
  can: () => true,
  canAny: () => true,
}

const denyAll = {
  can: () => false,
  canAny: () => false,
}

describe('sidebar information architecture', () => {
  it('references only known navigation destinations', () => {
    const knownIds = new Set(NAVIGATION_DESTINATIONS.map(item => item.id))
    const referencedIds = SIDEBAR_SECTIONS.flatMap(section =>
      section.entries.flatMap(entry =>
        entry.kind === 'leaf' ? [entry.destinationId] : entry.destinationIds
      )
    )

    const unknownIds = referencedIds.filter(id => !knownIds.has(id))
    expect(unknownIds).toEqual([])
  })

  it('does not duplicate a destination across sidebar groups', () => {
    const referencedIds = SIDEBAR_SECTIONS.flatMap(section =>
      section.entries.flatMap(entry =>
        entry.kind === 'leaf' ? [entry.destinationId] : entry.destinationIds
      )
    )

    expect(new Set(referencedIds).size).toBe(referencedIds.length)
  })

  it('keeps the high-level section order stable', () => {
    expect(SIDEBAR_SECTIONS.map(section => section.id)).toEqual([
      'home',
      'operations',
      'inventory',
      'finance',
      'field',
      'tools',
    ])
  })

  it('removes unauthorized groups while preserving public destinations', () => {
    const sections = getVisibleSidebarSections(denyAll)

    expect(sections.map(section => section.id)).toEqual(['home', 'tools'])
    expect(sections[0].entries.map(entry => entry.id)).toEqual(['dashboard', 'notifications'])
    expect(sections[1].entries.map(entry => entry.id)).toEqual(['hr-self'])
  })

  it('projects all configured groups when fully authorized', () => {
    const sections = getVisibleSidebarSections(allowAll)
    expect(sections.map(section => section.id)).toEqual([
      'home',
      'operations',
      'inventory',
      'finance',
      'field',
      'tools',
    ])
    expect(sections.find(section => section.id === 'operations')?.entries.map(entry => entry.id)).toEqual([
      'work',
      'sales',
      'purchases',
      'customers',
      'suppliers',
    ])
  })
})
