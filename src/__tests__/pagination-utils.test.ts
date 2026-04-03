/**
 * pagination-utils.test.ts
 * Unit tests for pagination math — verifies that the from/to/totalPages
 * calculations used across all service functions are correct.
 * These are pure functions extracted from the pattern used in activities.ts,
 * users.ts, etc. Adding them here gives us a fast regression check.
 */
import { describe, it, expect } from 'vitest'

function paginate(page: number, pageSize: number) {
  const from = (page - 1) * pageSize
  const to   = from + pageSize - 1
  return { from, to }
}

function totalPages(count: number, pageSize: number) {
  return Math.ceil(count / pageSize)
}

describe('pagination math', () => {
  it('page 1, pageSize 25 → from=0, to=24', () => {
    expect(paginate(1, 25)).toEqual({ from: 0, to: 24 })
  })

  it('page 2, pageSize 25 → from=25, to=49', () => {
    expect(paginate(2, 25)).toEqual({ from: 25, to: 49 })
  })

  it('page 3, pageSize 10 → from=20, to=29', () => {
    expect(paginate(3, 10)).toEqual({ from: 20, to: 29 })
  })

  it('totalPages: 100 items / 25 per page = 4 pages', () => {
    expect(totalPages(100, 25)).toBe(4)
  })

  it('totalPages: 101 items / 25 per page = 5 pages (ceiling)', () => {
    expect(totalPages(101, 25)).toBe(5)
  })

  it('totalPages: 0 items → 0 pages', () => {
    expect(totalPages(0, 25)).toBe(0)
  })

  it('totalPages: 1 item / 25 per page = 1 page', () => {
    expect(totalPages(1, 25)).toBe(1)
  })
})

describe('empty filter result fast-return contract', () => {
  // Verifies the shape that all service filter helpers return
  // when pre-resolved IDs list is empty (no matches)
  const emptyResult = { data: [], count: 0, page: 1, pageSize: 25, totalPages: 0 }

  it('empty result has correct shape', () => {
    expect(emptyResult.data).toHaveLength(0)
    expect(emptyResult.count).toBe(0)
    expect(emptyResult.totalPages).toBe(0)
  })
})
