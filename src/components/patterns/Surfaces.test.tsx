import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import Card from './Card'
import KeyValueList from './KeyValueList'
import SectionHeader from './SectionHeader'
import StatCard from './StatCard'

describe('Card', () => {
  it('expresses surface and padding without introducing interaction semantics', () => {
    render(<Card surface="elevated" padding="lg">محتوى</Card>)

    const card = screen.getByText('محتوى').closest('.ds-card')
    expect(card?.className).toContain('ds-card--elevated')
    expect(card?.className).toContain('ds-card--padding-lg')
    expect(card?.getAttribute('role')).toBeNull()
    expect(card?.getAttribute('tabindex')).toBeNull()
  })
})

describe('SectionHeader', () => {
  it('uses a real heading level and keeps actions separate', () => {
    render(
      <SectionHeader
        headingLevel={3}
        title="بيانات الطلب"
        description="تفاصيل التشغيل"
        action={<button type="button">تعديل</button>}
      />,
    )

    expect(screen.getByRole('heading', { level: 3, name: 'بيانات الطلب' })).not.toBeNull()
    expect(screen.getByRole('button', { name: 'تعديل' })).not.toBeNull()
  })
})

describe('StatCard', () => {
  it('renders supplied metric meaning without calculating it', () => {
    render(
      <StatCard
        tone="success"
        label="التحصيل اليوم"
        value="12,500 ج.م"
        context="من 8 إيصالات"
        trend="+6%"
      />,
    )

    const value = screen.getByText('12,500 ج.م')
    const card = value.closest('.ds-stat-card')
    expect(card?.getAttribute('data-tone')).toBe('success')
    expect(screen.getByText('+6%')).not.toBeNull()
  })
})

describe('KeyValueList', () => {
  it('uses semantic definition-list markup for summary data', () => {
    const { container } = render(
      <KeyValueList
        columns={3}
        items={[
          { key: 'customer', label: 'العميل', value: 'أحمد' },
          { key: 'total', label: 'الإجمالي', value: '1,200 ج.م', emphasis: 'strong' },
        ]}
      />,
    )

    expect(container.querySelector('dl')).not.toBeNull()
    expect(container.querySelectorAll('dt').length).toBe(2)
    expect(container.querySelectorAll('dd').length).toBe(2)
    expect(container.querySelector('.ds-key-value-list--cols-3')).not.toBeNull()
  })
})
