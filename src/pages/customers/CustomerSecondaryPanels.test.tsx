import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import type { CustomerBranch, CustomerContact, CustomerCreditHistory } from '@/lib/types/master-data'
import {
  CustomerBranchesPanel,
  CustomerContactsPanel,
  CustomerCreditHistoryPanel,
} from './CustomerSecondaryPanels'

const branch = {
  id: 'branch-1',
  customer_id: 'customer-1',
  name: 'الفرع الرئيسي',
  address: 'طنطا',
  phone: '01000000000',
  contact_name: 'أحمد',
  latitude: 30.7865,
  longitude: 31.0004,
  is_primary: true,
} as CustomerBranch

const contact = {
  id: 'contact-1',
  customer_id: 'customer-1',
  name: 'محمد علي',
  role: 'مدير المشتريات',
  phone: '01100000000',
  email: 'buyer@example.com',
  is_primary: true,
} as CustomerContact

describe('CustomerBranchesPanel', () => {
  it('keeps update actions explicit and callback-owned', () => {
    const onAdd = vi.fn()
    const onEdit = vi.fn()
    const onDelete = vi.fn()

    render(
      <CustomerBranchesPanel
        branches={[branch]}
        canUpdate
        onAdd={onAdd}
        onEdit={onEdit}
        onDelete={onDelete}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'إضافة فرع' }))
    fireEvent.click(screen.getByRole('button', { name: 'تعديل' }))
    fireEvent.click(screen.getByRole('button', { name: 'حذف فرع الفرع الرئيسي' }))

    expect(onAdd).toHaveBeenCalledTimes(1)
    expect(onEdit).toHaveBeenCalledWith(branch)
    expect(onDelete).toHaveBeenCalledWith('branch-1', 'الفرع الرئيسي')
    expect(screen.getByText('أساسي')).not.toBeNull()
  })

  it('keeps permission-limited presentation free of mutation actions', () => {
    render(
      <CustomerBranchesPanel
        branches={[]}
        canUpdate={false}
        onAdd={vi.fn()}
        onEdit={vi.fn()}
        onDelete={vi.fn()}
      />,
    )

    expect(screen.getByText('لا يوجد فروع لهذا العميل')).not.toBeNull()
    expect(screen.queryByRole('button')).toBeNull()
  })
})

describe('CustomerContactsPanel', () => {
  it('preserves contact detail direction and edit/delete callbacks', () => {
    const onEdit = vi.fn()
    const onDelete = vi.fn()

    render(
      <CustomerContactsPanel
        contacts={[contact]}
        canUpdate
        onAdd={vi.fn()}
        onEdit={onEdit}
        onDelete={onDelete}
      />,
    )

    expect(screen.getByText('01100000000').getAttribute('dir')).toBe('ltr')
    expect(screen.getByText('buyer@example.com').getAttribute('dir')).toBe('ltr')

    fireEvent.click(screen.getByRole('button', { name: 'تعديل' }))
    fireEvent.click(screen.getByRole('button', { name: 'حذف جهة الاتصال محمد علي' }))

    expect(onEdit).toHaveBeenCalledWith(contact)
    expect(onDelete).toHaveBeenCalledWith('contact-1', 'محمد علي')
  })
})

describe('CustomerCreditHistoryPanel', () => {
  it('keeps empty credit history in the shared state grammar', () => {
    render(<CustomerCreditHistoryPanel history={[]} />)

    expect(screen.getByText('لا يوجد تغييرات مسجلة')).not.toBeNull()
    expect(screen.queryByRole('table')).toBeNull()
  })

  it('renders existing history without changing credit arithmetic', () => {
    const entry = {
      id: 'credit-1',
      customer_id: 'customer-1',
      limit_before: 1000,
      limit_after: 1500,
      reason: 'تحديث حد الائتمان',
      created_at: '2026-09-15T12:00:00Z',
      changed_by_profile: { full_name: 'مدير المالية' },
    } as CustomerCreditHistory

    render(<CustomerCreditHistoryPanel history={[entry]} />)

    expect(screen.getByRole('table')).not.toBeNull()
    expect(screen.getByText('+500')).not.toBeNull()
    expect(screen.getByText('مدير المالية')).not.toBeNull()
  })
})
