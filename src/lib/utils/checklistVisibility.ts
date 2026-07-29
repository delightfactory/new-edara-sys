import type {
  ChecklistCondition,
  ChecklistQuestion,
  ChecklistVisibilityRule,
} from '@/lib/types/activities'

export type ChecklistAnswersByCode = Record<string, unknown>

function hasValue(value: unknown): boolean {
  if (value === undefined || value === null || value === '') return false
  return !Array.isArray(value) || value.length > 0
}

function asList(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [value]
}

function evaluateCondition(condition: ChecklistCondition, answers: ChecklistAnswersByCode): boolean {
  const actual = answers[condition.question_code]
  if (condition.operator === 'answered') {
    return condition.value === false ? !hasValue(actual) : hasValue(actual)
  }

  // A comparison must never reveal a dependent question before its controller is answered.
  if (!hasValue(actual)) return false

  const expected = condition.value
  switch (condition.operator) {
    case 'equals':
      return actual === expected
    case 'not_equals':
      return actual !== expected
    case 'in':
      return asList(expected).includes(actual)
    case 'not_in':
      return !asList(expected).includes(actual)
    case 'contains':
      return asList(actual).some(value => asList(expected).includes(value))
    case 'not_contains':
      return !asList(actual).some(value => asList(expected).includes(value))
    default:
      return true
  }
}

export function evaluateChecklistVisibility(
  rule: ChecklistVisibilityRule | null | undefined,
  answers: ChecklistAnswersByCode,
): boolean {
  if (!rule) return true
  if ('all' in rule) return rule.all.every(child => evaluateChecklistVisibility(child, answers))
  if ('any' in rule) return rule.any.some(child => evaluateChecklistVisibility(child, answers))
  return evaluateCondition(rule, answers)
}

export function buildChecklistAnswersByCode(
  questions: ChecklistQuestion[],
  answersById: Record<string, unknown>,
  context: ChecklistAnswersByCode = {},
): ChecklistAnswersByCode {
  const result = { ...context }
  for (const question of questions) {
    const value = answersById[question.id]
    if (hasValue(value)) result[question.question_code] = value
  }
  return result
}
