import { act, renderHook } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import useGeoPermission from './useGeoPermission'

describe('useGeoPermission safety timeout', () => {
  afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
  })

  it('releases the visit flow when an Android-like geolocation call never invokes either callback', async () => {
    vi.useFakeTimers()
    const getCurrentPosition = vi.fn()
    Object.defineProperty(navigator, 'geolocation', {
      configurable: true,
      value: { getCurrentPosition }
    })
    Object.defineProperty(navigator, 'permissions', {
      configurable: true,
      value: { query: vi.fn().mockResolvedValue({ state: 'granted', onchange: null }) }
    })

    const { result } = renderHook(() => useGeoPermission())
    let locationResult: Awaited<ReturnType<typeof result.current.requestLocation>> | undefined
    let request: Promise<Awaited<ReturnType<typeof result.current.requestLocation>>>

    act(() => {
      request = result.current.requestLocation()
    })
    expect(result.current.isLoading).toBe(true)

    await act(async () => {
      await vi.advanceTimersByTimeAsync(28_000)
      locationResult = await request!
    })

    expect(locationResult).toEqual({
      ok: false,
      reason: 'timeout',
      message: 'انتهت مهلة تحديد الموقع — يمكنك المتابعة وسيظهر الموقع للمراجعة'
    })
    expect(result.current.isLoading).toBe(false)
    expect(getCurrentPosition).toHaveBeenCalledTimes(1)
  })
})
