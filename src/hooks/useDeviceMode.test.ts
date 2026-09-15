import { describe, expect, it } from 'vitest'
import { getDeviceMode, MOBILE_MAX_WIDTH, TABLET_MAX_WIDTH } from './useDeviceMode'

describe('canonical device boundaries', () => {
  it('keeps mobile at and below 768px', () => {
    expect(MOBILE_MAX_WIDTH).toBe(768)
    expect(getDeviceMode(390)).toBe('mobile')
    expect(getDeviceMode(768)).toBe('mobile')
  })

  it('treats 769px through 1024px as tablet', () => {
    expect(TABLET_MAX_WIDTH).toBe(1024)
    expect(getDeviceMode(769)).toBe('tablet')
    expect(getDeviceMode(900)).toBe('tablet')
    expect(getDeviceMode(1024)).toBe('tablet')
  })

  it('uses the persistent desktop shell only above 1024px', () => {
    expect(getDeviceMode(1025)).toBe('desktop')
    expect(getDeviceMode(1440)).toBe('desktop')
  })
})
