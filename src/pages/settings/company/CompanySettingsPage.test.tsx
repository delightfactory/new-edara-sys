import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import CompanySettingsPage from './CompanySettingsPage'

let responses: { status: number; body: unknown }[]
const fetchBoundary = vi.fn(async (input: RequestInfo | URL) => {
  const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url)
  if (url.origin !== 'https://example.supabase.co' || url.pathname !== '/rest/v1/company_settings') {
    throw new Error('Unexpected request in settings test')
  }
  const response = responses.shift()
  if (!response) throw new Error('Unexpected extra settings request')
  return new Response(JSON.stringify(response.body), {
    status: response.status,
    headers: { 'Content-Type': 'application/json' },
  })
})

beforeEach(() => {
  responses = []
  fetchBoundary.mockClear()
  vi.stubGlobal('fetch', fetchBoundary)
})

afterEach(() => { cleanup(); vi.unstubAllGlobals() })

describe('company settings load states through real service and SDK', () => {
  it('explains a genuinely empty settings collection', async () => {
    responses.push({ status: 200, body: [] })
    render(<CompanySettingsPage />)
    expect(await screen.findByText('لا توجد إعدادات للشركة')).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'حفظ التغييرات' })).toBeNull()
  })

  it('ends failed loading and retries the real settings request', async () => {
    responses.push({ status: 403, body: { code: '42501', message: 'permission denied' } })
    render(<CompanySettingsPage />)
    expect(await screen.findByText('تعذر تحميل إعدادات الشركة')).toBeTruthy()
    responses.push({ status: 200, body: [{ key: 'company.name', value: 'شركة اختبار', type: 'text', description: 'اسم الشركة', category: 'company' }] })
    fireEvent.click(screen.getByRole('button', { name: 'إعادة المحاولة' }))
    expect((await screen.findAllByDisplayValue('شركة اختبار')).length).toBeGreaterThan(0)
    expect(fetchBoundary).toHaveBeenCalledTimes(2)
    expect(screen.queryByText('تعذر تحميل إعدادات الشركة')).toBeNull()
  })

  it('opens an available category when the company category is absent', async () => {
    responses.push({ status: 200, body: [{ key: 'general.example', value: 'قيمة اختبار', type: 'text', description: 'إعداد تجريبي', category: 'general' }] })
    render(<CompanySettingsPage />)
    expect((await screen.findAllByDisplayValue('قيمة اختبار')).length).toBeGreaterThan(0)
  })
})
