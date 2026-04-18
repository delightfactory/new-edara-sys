import { describe, it, expect, vi } from 'vitest'
import { getCustomer360Timeline, getCustomer360Ledger, getCustomer360Profitability } from './customer360'
import { supabase } from '@/lib/supabase/client'

vi.mock('@/lib/supabase/client', () => ({
  supabase: {
    rpc: vi.fn(),
  }
}))

describe('Customer 360 Service logic', () => {
  it('gracefully degrades profitability unauthorized to null (lock state)', async () => {
    // mock the RPC to return unauthorized error matching analytics framework
    vi.mocked(supabase.rpc).mockResolvedValueOnce({
      error: { message: 'analytics_unauthorized:domain=profitability', details: '', hint: '', code: '', name: 'PostgrestError' },
      data: null as any, count: null, status: 401, statusText: 'error'
    })
    
    // profitabilityClient maps this to AnalyticsUnauthorizedError, which customer360 Profitability catches.
    // wait, getCustomerProfitability is not mocked directly, it calls supabase.rpc('analytics_gross_profit_by_customer')
    const result = await getCustomer360Profitability({ customer_id: '1', date_from: '2023-01-01', date_to: '2023-12-31' })
    expect(result).toBeNull()
  })

  it('passes timeline cursor pagination parameters correctly', async () => {
    vi.mocked(supabase.rpc).mockResolvedValueOnce({ error: null, data: [] as any, count: null, status: 200, statusText: 'OK' })
    
    await getCustomer360Timeline('cust-1', { limit: 15, before_ts: '2023-01-01', before_id: 'event-1' })
    
    expect(supabase.rpc).toHaveBeenCalledWith('get_customer_unified_timeline', {
      p_customer_id: 'cust-1',
      p_limit: 15,
      p_before_ts: '2023-01-01',
      p_before_id: 'event-1'
    })
  })

  it('fetches ledger using get_customer_ledger_with_balance with deterministic cursor', async () => {
    vi.mocked(supabase.rpc).mockResolvedValueOnce({ error: null, data: [] as any, count: null, status: 200, statusText: 'OK' })
    
    await getCustomer360Ledger('cust-1', { limit: 10, before_ts: '2023-01-01', before_id: 'entry-abc' })
    
    expect(supabase.rpc).toHaveBeenCalledWith('get_customer_ledger_with_balance', {
      p_customer_id: 'cust-1',
      p_limit: 10,
      p_before_ts: '2023-01-01',
      p_before_id: 'entry-abc'   // deterministic cursor second dimension
    })
  })
})
