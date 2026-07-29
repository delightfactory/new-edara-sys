import { describe, expect, it } from 'vitest'
import { evaluateChecklistVisibility } from './checklistVisibility'

describe('evaluateChecklistVisibility', () => {
  it('keeps legacy questions visible', () => {
    expect(evaluateChecklistVisibility(null, {})).toBe(true)
  })

  it('does not reveal dependent questions before the controller is answered', () => {
    expect(evaluateChecklistVisibility({
      question_code: 'sales.order_outcome',
      operator: 'not_equals',
      value: 'تم إنشاء طلب',
    }, {})).toBe(false)
  })

  it('supports grouped and multi-choice conditions', () => {
    const rule = {
      all: [
        { question_code: 'contact.result', operator: 'in' as const, value: ['تمت مقابلة المسؤول', 'تمت مقابلة موظف'] },
        { question_code: 'activation.action', operator: 'contains' as const, value: 'لم يتم التنشيط' },
      ],
    }

    expect(evaluateChecklistVisibility(rule, {
      'contact.result': 'تمت مقابلة المسؤول',
      'activation.action': ['لم يتم التنشيط'],
    })).toBe(true)
    expect(evaluateChecklistVisibility(rule, {
      'contact.result': 'المكان مغلق',
      'activation.action': ['لم يتم التنشيط'],
    })).toBe(false)
  })
})
