import { fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter, useLocation } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import FAB from './FAB'

vi.mock('@/stores/auth-store', () => ({
  useAuthStore: (selector: (state: unknown) => unknown) => selector({
    can: (permission: string) => permission === 'targets.assign' || permission === 'activities.create',
  }),
}))

vi.mock('@/hooks/useModalStack', () => ({
  useIsAnyModalOpen: () => false,
}))

function CurrentPath() {
  return <output aria-label="المسار الحالي">{useLocation().pathname}</output>
}

function renderAt(pathname: string) {
  return render(
    <MemoryRouter initialEntries={[pathname]}>
      <FAB />
      <CurrentPath />
    </MemoryRouter>,
  )
}

describe('FAB route actions', () => {
  it('shows goal creation on the targets list instead of the generic activity action', () => {
    renderAt('/activities/targets')

    expect(screen.queryByRole('button', { name: '+ نشاط' })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: '+ هدف' }))
    expect(screen.getByLabelText('المسار الحالي').textContent).toBe('/activities/targets/new')
  })

  it('keeps the established activity action on the activities list', () => {
    renderAt('/activities/list')

    expect(screen.getByRole('button', { name: '+ نشاط' })).not.toBeNull()
    expect(screen.queryByRole('button', { name: '+ هدف' })).toBeNull()
  })

  it('removes the action while the user is already creating a goal', () => {
    renderAt('/activities/targets/new')

    expect(screen.queryByRole('button')).toBeNull()
  })
})
