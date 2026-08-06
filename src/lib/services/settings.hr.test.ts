import { beforeEach, describe, expect, it, vi } from 'vitest'
import { supabase } from '@/lib/supabase/client'
import { updateSettings } from './settings'

vi.mock('@/lib/supabase/client', () => ({
  supabase: {
    rpc: vi.fn(),
    from: vi.fn(),
  },
}))

describe('generic HR settings service', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('rejects the employee schedule activation key before any database call', async () => {
    await expect(updateSettings([
      { key: 'hr.employee_work_schedules_enabled', value: 'true' },
    ])).rejects.toThrow('مفتاح تفعيل جداول الموظفين داخلي')

    expect(supabase.rpc).not.toHaveBeenCalled()
    expect(supabase.from).not.toHaveBeenCalled()
  })
})
