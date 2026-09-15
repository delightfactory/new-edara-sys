import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import Button from '@/components/ui/Button'
import FormActions from './FormActions'
import FormGrid from './FormGrid'
import FormSection from './FormSection'

describe('Form composition patterns', () => {
  it('renders a form section with shared header/body/footer structure', () => {
    const { container } = render(
      <FormSection
        title="بيانات العميل"
        description="المعلومات الأساسية"
        footer={<span>footer</span>}
      >
        <div>body</div>
      </FormSection>
    )

    expect(screen.getByRole('heading', { name: 'بيانات العميل' })).toBeTruthy()
    expect(screen.getByText('المعلومات الأساسية')).toBeTruthy()
    expect(screen.getByText('body')).toBeTruthy()
    expect(screen.getByText('footer')).toBeTruthy()
    expect(container.querySelector('.ds-form-section__body')).toBeTruthy()
  })

  it('encodes the requested desktop grid density without page-local layout code', () => {
    const { container } = render(
      <FormGrid columns={3} compact>
        <div>one</div>
        <div>two</div>
      </FormGrid>
    )

    const grid = container.firstElementChild
    expect(grid?.classList.contains('ds-form-grid--cols-3')).toBe(true)
    expect(grid?.classList.contains('ds-form-grid--compact')).toBe(true)
  })

  it('makes sticky mobile actions explicit opt-in', () => {
    const { container } = render(
      <FormActions stickyOnMobile align="between">
        <Button variant="secondary">إلغاء</Button>
        <Button>حفظ</Button>
      </FormActions>
    )

    const actions = container.firstElementChild
    expect(actions?.classList.contains('ds-form-actions--sticky-mobile')).toBe(true)
    expect(actions?.classList.contains('ds-form-actions--between')).toBe(true)
  })
})
