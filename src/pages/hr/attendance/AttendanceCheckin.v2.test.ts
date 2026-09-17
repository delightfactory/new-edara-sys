import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const source = readFileSync(
  fileURLToPath(new URL('./AttendanceCheckin.tsx', import.meta.url)),
  'utf8',
)

describe('AttendanceCheckin Design System V2 task controls', () => {
  it('composes the live task-control band from shared V2 patterns', () => {
    expect(source).toContain("import AlertPanel from '@/components/patterns/AlertPanel'")
    expect(source).toContain("import ProcessProgress, { type ProcessProgressStep } from '@/components/patterns/ProcessProgress'")
    expect(source).toContain("import PrimaryTaskAction from '@/components/patterns/PrimaryTaskAction'")

    expect(source).toContain('<ProcessProgress')
    expect(source).toContain('ariaLabel="تقدم تسجيل الحضور"')
    expect(source).toContain('<PrimaryTaskAction')
    expect(source).toContain('className="ci-task-control"')

    expect(source).toContain('tone="success"')
    expect(source).toContain('tone="danger"')
    expect(source.match(/\bannounce\b/g)?.length ?? 0).toBeGreaterThanOrEqual(2)
  })

  it('keeps attendance action identity, labels, callback ownership, and success reset unchanged', () => {
    expect(source).toContain('const SUCCESS_RESET_MS = 2500')
    expect(source).toContain("const primaryActionType: ActionType = isCheckInAction ? 'check_in' : 'check_out'")
    expect(source).toContain("const primaryActionLabel = isCheckInAction ? 'بدء الدوام' : 'إنهاء الدوام'")
    expect(source).toContain("id={isCheckInAction ? 'btn-check-in' : 'btn-check-out'}")
    expect(source).toContain('onClick={() => handleAction(primaryActionType)}')
    expect(source).toContain('setTimeout(() => {')
    expect(source).toContain('}, SUCCESS_RESET_MS)')
  })

  it('preserves offline and GPS permission gating at the page boundary', () => {
    expect(source).toContain('if (!navigator.onLine)')
    expect(source).toContain("toast.warning('أنت غير متصل — لا يمكن التسجيل الآن')")
    expect(source).toContain("if (geo.status === 'denied')")
    expect(source).toContain("if (geo.status === 'prompt')")
    expect(source).toContain('setShowGeoDialog(true)')
    expect(source).toContain('<GeoPermissionDialog')
    expect(source).toContain('onAllow={handleGeoDialogAllow}')
    expect(source).toContain('onDismiss={handleGeoDialogDismiss}')
    expect(source).toContain('<GeoPermissionBanner')
  })

  it('keeps attendance services, query boundaries, and tracking operations intact', () => {
    expect(source).toContain('recordAttendanceGPS')
    expect(source).toContain('recordAttendanceLocationPing')
    expect(source).toContain('getAttendanceDays')
    expect(source).toContain('useGeoPermission')
    expect(source).toContain("queryKey: ['hr-attendance-today', employee?.id, today]")
    expect(source).toContain("queryKey: ['settings', 'hr', 'tracking']")
    expect(source).toContain("sendTrackingPing('interval')")
    expect(source).toContain("sendTrackingPing('focus')")
    expect(source).toContain("sendTrackingPing('resume')")
    expect(source).toContain("sendTrackingPing('reconnect')")
  })

  it('removes the superseded page-local task-control mini-system without adding forbidden action patterns', () => {
    expect(source).not.toContain('function SmartActionButton')
    expect(source).not.toContain('function ProgressSteps')
    expect(source).not.toContain('ci-action-btn')
    expect(source).not.toContain('ci-progress')
    expect(source).not.toContain('ci-feedback-card')
    expect(source).not.toContain('ci-step')
    expect(source).not.toContain('AppAction')
    expect(source).not.toContain('resolveActionSet')
    expect(source).not.toMatch(/position\s*:\s*(?:fixed|sticky)/)
  })
})
