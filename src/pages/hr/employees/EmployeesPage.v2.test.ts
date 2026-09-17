import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./EmployeesPage.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')

describe('EmployeesPage V2 administration-list contract', () => {
  it('uses one responsive collection boundary with deliberate Desktop, Tablet and Mobile composition', () => {
    expect(source).toContain("import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'")
    expect(source).toContain('<ResponsiveCollection<HREmployee>')
    expect(source).toContain('renderDesktop={items => (')
    expect(source).toContain("renderTablet={items => renderEmployeeCards(items, 'tablet')}")
    expect(source).toContain("renderMobile={items => renderEmployeeCards(items, 'mobile')}")
    expect(source).toContain('ds-responsive-card-grid--${mode}')
    expect(source).not.toContain('hr-table-view')
    expect(source).not.toContain('hr-card-view')
    expect(source).not.toContain('mobile-card-list')
  })

  it('preserves the existing employee query and page-reset behavior', () => {
    expect(source).toContain('search: search || undefined')
    expect(source).toContain('departmentId: deptFilter || undefined')
    expect(source).toContain('status: statusFilter || undefined')
    expect(source).toContain('pageSize: 25')
    expect(source).toContain('useHREmployees(queryParams)')
    expect(source).toContain('setSearch(value); setPage(1)')
    expect(source).toContain('setDeptFilter(event.target.value); setPage(1)')
    expect(source).toContain("setStatusFilter(event.target.value as HREmployeeStatus | ''); setPage(1)")
  })

  it('keeps salary and mutation/navigation actions behind the existing permission predicates', () => {
    expect(source).toContain('<PermissionGuard permission="hr.payroll.read">')
    expect(source).toContain("salary: can('hr.payroll.read') ?")
    expect(source).toContain('<PermissionGuard permission="hr.employees.create">')
    expect(source).toContain("!hasActiveFilters && can('hr.employees.create')")
    expect(source).toContain("if (can('hr.employees.edit'))")
    expect(source).toContain('<PermissionGuard permission="hr.employees.edit">')
    expect(source).toContain('onSelect: () => openProfile(employee)')
    expect(source).toContain('onSelect: () => openEdit(employee)')
    expect(source).toContain("availableOn: ['tablet', 'desktop']")
  })

  it('maps workflow status semantically while keeping field/office categorical metadata neutral', () => {
    expect(source).toContain("active: 'success'")
    expect(source).toContain("on_leave: 'info'")
    expect(source).toContain("suspended: 'warning'")
    expect(source).toContain("terminated: 'danger'")
    expect(source).toContain('<StatusBadge label={statusLabel[employee.status]} tone={statusTone[employee.status]} />')
    expect(source).toContain('<Badge variant="neutral">')
    expect(source).not.toContain("employee.is_field_employee ? 'warning' : 'neutral'")
  })

  it('distinguishes initial empty from filtered empty without changing creation eligibility', () => {
    expect(source).toContain('const hasActiveFilters = Boolean(search || deptFilter || statusFilter)')
    expect(source).toContain("title={hasActiveFilters ? 'لا توجد نتائج مطابقة' : 'لا يوجد موظفون'}")
    expect(source).toContain("'جرّب تعديل البحث أو فلاتر القسم والحالة.'")
    expect(source).toContain("!hasActiveFilters && can('hr.employees.create')")
  })

  it('keeps EmployeeForm as the existing create/edit boundary and does not absorb form semantics into this concern', () => {
    expect(source).toContain("import EmployeeForm from './EmployeeForm'")
    expect(source).toContain('<EmployeeForm')
    expect(source).toContain('employee={editEmp}')
    expect(source).toContain('setEditEmp(null); setFormOpen(true)')
    expect(source).toContain('setEditEmp(emp); setFormOpen(true)')
  })
})
