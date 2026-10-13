import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import VisitGuidance from './VisitGuidance'
import PlanItemCard from './PlanItemCard'
import type { CallPlanItem, VisitPlanItem } from '@/lib/types/activities'
import styles from './VisitGuidance.css?raw'

const instruction = 'راجع احتياج العميل إلى أربعة أصناف جديدة.\nسجّل النتيجة والخطوة التالية دون اختصار.'

describe('VisitGuidance', () => {
  it('preserves the complete multiline Arabic text and a navigable target', () => {
    render(<VisitGuidance id="plan-guidance" title="توجيهات الخطة" text={instruction} />)
    const section = screen.getByRole('region', { name: 'توجيهات الخطة' })
    expect(section.id).toBe('plan-guidance')
    expect(section.querySelector('p')?.textContent).toBe(instruction)
    expect(section.querySelector('p')?.getAttribute('dir')).toBe('auto')
    expect(section.closest('[hidden]')).toBeNull()
  })

  it.each([null, undefined, '', ' \n\t '])('omits empty guidance %s', text => {
    const { container } = render(<VisitGuidance title="توجيهات الخطة" text={text} />)
    expect(container.innerHTML).toBe('')
  })

  it('renders content as text, never as HTML', () => {
    const { container } = render(<VisitGuidance title="توجيهات الخطة" text={'<img src=x onerror=alert(1)>'} />)
    expect(container.querySelector('img')).toBeNull()
    expect(screen.getByText('<img src=x onerror=alert(1)>')).toBeDefined()
  })

  it('preserves line breaks and wraps long words without line clamps or fixed heights', () => {
    expect(styles).toContain('white-space: pre-wrap')
    expect(styles).toContain('overflow-wrap: anywhere')
    expect(styles).toContain('scroll-margin-block-start')
    expect(styles).not.toMatch(/line-clamp|text-overflow|(?:^|\n)\s*(?:max-)?(?:height|block-size)\s*:/)
  })
})

describe('PlanItemCard visit instructions', () => {
  it.each(['pending', 'in_progress', 'completed'] as const)('shows purpose independently of purpose_type for %s visits', status => {
    const item = {
      id: 'synthetic-item', status, sequence: 1, purpose: instruction,
      purpose_type: null, estimated_duration_min: 20,
      customer: { name: 'عميل تجريبي' },
      metadata: { instructions: 'لا تعرض البيانات التقنية' },
    } as unknown as VisitPlanItem
    render(<PlanItemCard type="visit" item={item} />)
    expect(screen.getByRole('region', { name: 'المطلوب في الزيارة' }).querySelector('p')?.textContent).toBe(instruction)
    expect(screen.queryByText('لا تعرض البيانات التقنية')).toBeNull()
  })

  it('does not add visit instructions to call cards', () => {
    const item = { id: 'call', status: 'pending', sequence: 1, purpose: instruction } as unknown as CallPlanItem
    render(<PlanItemCard type="call" item={item} />)
    expect(screen.queryByRole('region', { name: 'المطلوب في الزيارة' })).toBeNull()
  })
})
