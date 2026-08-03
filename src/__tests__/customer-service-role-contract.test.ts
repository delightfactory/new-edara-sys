import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { PERMISSIONS } from '@/lib/permissions/constants'

const migration = readFileSync(
  resolve(
    process.cwd(),
    'supabase/migrations/20260803193059_add_customer_service_role.sql',
  ),
  'utf8',
)

describe('customer service role contract', () => {
  it('creates an editable, low-grade role with a stable slug', () => {
    expect(migration).toContain("'customer_service'")
    expect(migration).toContain("'خدمة العملاء'")
    expect(migration).toMatch(/'#[0-9a-f]{6}',\s*5\s*\)/i)
    expect(migration).toContain('is_system = false')
    expect(migration).not.toContain('is_system = true')
  })

  it('only seeds permissions known to the frontend permission matrix', () => {
    const seededBlock = migration.match(
      /CROSS JOIN \(VALUES([\s\S]*?)\) AS p\(permission\)/,
    )
    expect(seededBlock, 'customer-service permission seed is missing').not.toBeNull()

    const seededPermissions = [
      ...seededBlock![1].matchAll(/\('([^']+)'\)/g),
    ].map(match => match[1])
    const knownPermissions = new Set<string>(Object.values(PERMISSIONS))

    expect(seededPermissions.length).toBeGreaterThan(0)
    for (const permission of seededPermissions) {
      expect(knownPermissions.has(permission), permission).toBe(true)
    }
  })

  it('does not seed approval, override, finance, or cost privileges', () => {
    const forbiddenPermissions = [
      PERMISSIONS.SALES_ORDERS_CONFIRM,
      PERMISSIONS.SALES_ORDERS_DELIVER,
      PERMISSIONS.SALES_ORDERS_CANCEL,
      PERMISSIONS.SALES_DISCOUNTS_OVERRIDE,
      PERMISSIONS.SALES_ORDERS_OVERRIDE_CREDIT,
      PERMISSIONS.CUSTOMERS_CREDIT_UPDATE,
      PERMISSIONS.FINANCE_VIEW_COSTS,
      PERMISSIONS.FINANCE_READ,
    ]

    for (const permission of forbiddenPermissions) {
      expect(migration).not.toContain(`('${permission}')`)
    }
  })

  it('includes the HR permissions required for employee self-service', () => {
    const requiredSelfServicePermissions = [
      PERMISSIONS.HR_ATTENDANCE_CHECKIN,
      PERMISSIONS.HR_LEAVES_REQUEST,
      PERMISSIONS.HR_ADVANCES_CREATE,
    ]

    for (const permission of requiredSelfServicePermissions) {
      expect(migration).toContain(`('${permission}')`)
    }
  })

  it('does not grant HR administration or access to other employees data', () => {
    const forbiddenHRPermissions = [
      PERMISSIONS.HR_EMPLOYEES_READ,
      PERMISSIONS.HR_ATTENDANCE_READ,
      PERMISSIONS.HR_ATTENDANCE_CREATE,
      PERMISSIONS.HR_ATTENDANCE_EDIT,
      PERMISSIONS.HR_ATTENDANCE_UPDATE,
      PERMISSIONS.HR_ATTENDANCE_APPROVE,
      PERMISSIONS.HR_LEAVES_READ,
      PERMISSIONS.HR_LEAVES_CREATE,
      PERMISSIONS.HR_LEAVES_APPROVE,
      PERMISSIONS.HR_ADVANCES_READ,
      PERMISSIONS.HR_ADVANCES_APPROVE,
      PERMISSIONS.HR_PERMISSIONS_APPROVE,
      PERMISSIONS.HR_PAYROLL_READ,
      PERMISSIONS.HR_PAYROLL_CALCULATE,
      PERMISSIONS.HR_PAYROLL_APPROVE,
      PERMISSIONS.HR_PAYROLL_DISBURSE,
    ]

    for (const permission of forbiddenHRPermissions) {
      expect(migration).not.toContain(`('${permission}')`)
    }
  })

  it('does not alter sales workflow schema, policies, or functions', () => {
    expect(migration).not.toMatch(/\b(?:CREATE|DROP)\s+POLICY\b/i)
    expect(migration).not.toMatch(/\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\b/i)
    expect(migration).not.toMatch(/\bALTER\s+TABLE\b/i)
  })
})
