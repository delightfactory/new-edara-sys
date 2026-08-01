import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const source = readFileSync(resolve(
  process.cwd(),
  'src/pages/activities/TargetForm.tsx',
), 'utf8')

describe('target creation review flow contract', () => {
  it('never creates a target through implicit form submission', () => {
    expect(source).toContain('onSubmit={e => e.preventDefault()}')
    expect(source).not.toMatch(/onSubmit=\{[^}]*handleSubmit/)
    expect(source).toContain('key="wizard-create" type="button" onClick={handleSubmit}')
  })

  it('keeps next navigation separate from the create action', () => {
    expect(source).toContain('key="wizard-next" type="button"')
    expect(source).toContain('if (step !== REVIEW_STEP || !reviewReady || !allRequiredStepsValid || saving) return')
  })

  it('shows and validates the review step before enabling creation', () => {
    expect(source).toContain('reviewHeadingRef.current?.scrollIntoView')
    expect(source).toContain('window.setTimeout(() => setReviewReady(true), 500)')
    expect(source).toContain('disabled={saving || !reviewReady || !allRequiredStepsValid}')
    expect(source).toContain('.filter(s => s !== REVIEW_STEP)')
    expect(source).toContain('.every(stepValid)')
  })
})
