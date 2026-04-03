import '@testing-library/react'
import { afterAll, beforeAll } from 'vitest'

// Suppress noisy console.error from React in test output
const originalConsoleError = console.error
beforeAll(() => {
  console.error = (...args: unknown[]) => {
    // Suppress React's act() warnings in tests that don't need them
    if (typeof args[0] === 'string' && args[0].includes('act(')) return
    originalConsoleError(...args)
  }
})
afterAll(() => {
  console.error = originalConsoleError
})
