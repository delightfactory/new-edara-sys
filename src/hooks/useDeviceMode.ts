import { useEffect, useState } from 'react'

export type DeviceMode = 'mobile' | 'tablet' | 'desktop'

export const MOBILE_MAX_WIDTH = 768
export const TABLET_MAX_WIDTH = 1024

export function getDeviceMode(width: number): DeviceMode {
  if (width <= MOBILE_MAX_WIDTH) return 'mobile'
  if (width <= TABLET_MAX_WIDTH) return 'tablet'
  return 'desktop'
}

/**
 * Canonical Design System V2 device-mode hook.
 *
 * Edara is a client-rendered application, so a viewport-based mode is safe here.
 * Centralizing the thresholds prevents every feature from inventing its own
 * mobile/tablet/desktop split.
 */
export function useDeviceMode(): DeviceMode {
  const [mode, setMode] = useState<DeviceMode>(() =>
    typeof window === 'undefined' ? 'desktop' : getDeviceMode(window.innerWidth)
  )

  useEffect(() => {
    if (typeof window === 'undefined') return

    const update = () => setMode(getDeviceMode(window.innerWidth))
    update()
    window.addEventListener('resize', update, { passive: true })
    return () => window.removeEventListener('resize', update)
  }, [])

  return mode
}
