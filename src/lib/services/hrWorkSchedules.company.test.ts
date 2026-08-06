import { beforeEach, describe, expect, it, vi } from 'vitest'
import { supabase } from '@/lib/supabase/client'
import { getCompanyWorkScheduleForDate } from './hrWorkSchedules'

vi.mock('@/lib/supabase/client', () => ({
  supabase: {
    rpc: vi.fn(),
  },
}))

describe('date-effective company work schedule service', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('requests the company version for the selected employee schedule date', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        id: 'company-version-2',
        effective_from: '2026-09-01',
        effective_to: null,
        status: 'active',
        start_time: '1000',
        end_time: '16:00:00',
        work_hours_per_day: 6,
        scheduled_minutes: 360,
        weekly_off_day: 'friday',
        notes: null,
        is_system_baseline: false,
      },
      error: null,
    } as never)

    const result = await getCompanyWorkScheduleForDate('2026-09-15')

    expect(supabase.rpc).toHaveBeenCalledWith('get_company_work_schedule_for_date', {
      p_target_date: '2026-09-15',
    })
    expect(result).toMatchObject({
      id: 'company-version-2',
      effective_from: '2026-09-01',
      start_time: '10:00',
      end_time: '16:00',
      scheduled_minutes: 360,
      work_hours_per_day: 6,
    })
  })

  it('fails closed when the date-effective company version is unavailable', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: null,
      error: { message: 'لا يوجد جدول شركة يغطي التاريخ المحدد' },
    } as never)

    await expect(getCompanyWorkScheduleForDate('2026-10-01'))
      .rejects.toMatchObject({ message: 'لا يوجد جدول شركة يغطي التاريخ المحدد' })
  })
})
