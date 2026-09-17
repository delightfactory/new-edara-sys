import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Briefcase, Eye, Phone, Plus, Users } from 'lucide-react'
import { toast } from 'sonner'
import { useHREmployees, useHRDepartments } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { HREmployee, HREmployeeStatus } from '@/lib/types/hr'
import { formatNumber } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import PermissionGuard from '@/components/shared/PermissionGuard'
import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'
import Pagination from '@/components/patterns/Pagination'
import StatePanel from '@/components/patterns/StatePanel'
import StatusBadge, { type SemanticTone } from '@/components/patterns/StatusBadge'
import Card from '@/components/patterns/Card'
import type { AppAction } from '@/components/patterns/ActionRegistry'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import { EmployeeCard, EmployeeSummary } from '@/components/hr/EmployeeOverviewPresentation'
import EmployeeForm from './EmployeeForm'

const statusLabel: Record<HREmployeeStatus, string> = {
  active: 'نشط',
  on_leave: 'في إجازة',
  suspended: 'موقوف',
  terminated: 'منتهي الخدمة',
}

const statusTone: Record<HREmployeeStatus, SemanticTone> = {
  active: 'success',
  on_leave: 'info',
  suspended: 'warning',
  terminated: 'danger',
}

export default function EmployeesPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  const [search, setSearch] = useState('')
  const [deptFilter, setDeptFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState<HREmployeeStatus | ''>('')
  const [page, setPage] = useState(1)
  const [formOpen, setFormOpen] = useState(false)
  const [editEmp, setEditEmp] = useState<HREmployee | null>(null)

  const { data: departments = [] } = useHRDepartments()

  const queryParams = useMemo(() => ({
    search: search || undefined,
    departmentId: deptFilter || undefined,
    status: statusFilter || undefined,
    page,
    pageSize: 25,
  }), [search, deptFilter, statusFilter, page])

  const { data: result, isLoading: loading } = useHREmployees(queryParams)
  const employees = result?.data ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count ?? 0

  // GAP-08: جلب الإحصائيات من الإجمالي الحقيقي
  const { data: activeResult, isLoading: statsLoading } =
    useHREmployees({ status: 'active', pageSize: 1 })
  const { data: leaveResult } =
    useHREmployees({ status: 'on_leave', pageSize: 1 })

  const activeCount = activeResult?.count ?? 0
  const onLeaveCount = leaveResult?.count ?? 0
  // الموظفون الميدانيون: نحسبهم من الصفحة الحالية (لا يوجد فلتر API لذلك)
  const fieldEmpCount = employees.filter(e => e.is_field_employee).length

  const openAdd = () => { setEditEmp(null); setFormOpen(true) }
  const openEdit = (emp: HREmployee) => { setEditEmp(emp); setFormOpen(true) }
  const openProfile = (emp: HREmployee) => navigate(`/hr/employees/${emp.id}`)

  const columns = [
    {
      key: 'employee_number',
      label: 'رقم الموظف',
      render: (employee: HREmployee) => (
        <span style={{ fontFamily: 'monospace', fontWeight: 600, fontSize: 'var(--text-sm)' }} dir="ltr">
          {employee.employee_number}
        </span>
      ),
    },
    {
      key: 'full_name',
      label: 'الموظف',
      render: (employee: HREmployee) => (
        <>
          <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{employee.full_name}</div>
          {employee.personal_phone && (
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 4 }}>
              <Phone size={10} />
              <span dir="ltr">{employee.personal_phone}</span>
            </div>
          )}
        </>
      ),
    },
    {
      key: 'department',
      label: 'القسم',
      hideOnMobile: true,
      render: (employee: HREmployee) => (
        <>
          <div style={{ fontSize: 'var(--text-sm)' }}>{employee.department?.name ?? '—'}</div>
          {employee.position && (
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
              {employee.position.name}
            </div>
          )}
        </>
      ),
    },
    {
      key: 'status',
      label: 'الحالة',
      render: (employee: HREmployee) => (
        <StatusBadge label={statusLabel[employee.status]} tone={statusTone[employee.status]} />
      ),
    },
    {
      key: 'base_salary',
      label: 'الراتب الأساسي',
      hideOnMobile: true,
      render: (employee: HREmployee) => (
        <PermissionGuard permission="hr.payroll.read">
          <span style={{ fontVariantNumeric: 'tabular-nums', fontWeight: 500 }}>
            {formatNumber(employee.base_salary)} ج.م
          </span>
        </PermissionGuard>
      ),
    },
    {
      key: 'type',
      label: 'النوع',
      hideOnMobile: true,
      render: (employee: HREmployee) => (
        <Badge variant="neutral">
          {employee.is_field_employee ? 'ميداني' : 'مكتبي'}
        </Badge>
      ),
    },
    {
      key: 'actions',
      label: '',
      width: 90,
      render: (employee: HREmployee) => (
        <div style={{ display: 'flex', gap: 'var(--space-1)' }} onClick={event => event.stopPropagation()}>
          <Button
            variant="ghost"
            size="sm"
            aria-label={`عرض ملف ${employee.full_name}`}
            onClick={() => openProfile(employee)}
          >
            <Eye size={14} />
          </Button>
          <PermissionGuard permission="hr.employees.edit">
            <Button
              variant="ghost"
              size="sm"
              aria-label={`تعديل ${employee.full_name}`}
              onClick={() => openEdit(employee)}
            >
              <Briefcase size={14} />
            </Button>
          </PermissionGuard>
        </div>
      ),
    },
  ]

  const employeeCardActions = (employee: HREmployee): AppAction[] => {
    const actions: AppAction[] = [
      {
        id: 'view',
        label: 'عرض الملف',
        ariaLabel: `عرض ملف ${employee.full_name}`,
        icon: <Eye size={14} />,
        importance: 'primary',
        tone: 'secondary',
        onSelect: () => openProfile(employee),
      },
    ]

    if (can('hr.employees.edit')) {
      actions.push({
        id: 'edit',
        label: 'تعديل',
        ariaLabel: `تعديل ${employee.full_name}`,
        icon: <Briefcase size={14} />,
        tone: 'ghost',
        availableOn: ['tablet', 'desktop'],
        onSelect: () => openEdit(employee),
      })
    }

    return actions
  }

  const renderEmployeeCards = (items: HREmployee[], mode: 'mobile' | 'tablet') => (
    <>
      <div className={`ds-responsive-card-grid ds-responsive-card-grid--${mode}`}>
        {items.map(employee => (
          <EmployeeCard
            key={employee.id}
            mode={mode}
            summary={{
              name: employee.full_name,
              employeeNumber: employee.employee_number,
              department: employee.department?.name ?? '—',
              position: employee.position?.name,
              phone: employee.personal_phone ? <span dir="ltr">{employee.personal_phone}</span> : undefined,
              salary: can('hr.payroll.read') ? `${formatNumber(employee.base_salary)} ج.م` : undefined,
              fieldLabel: employee.is_field_employee ? 'ميداني' : 'مكتبي',
              isFieldEmployee: employee.is_field_employee,
              statusLabel: statusLabel[employee.status],
              statusTone: statusTone[employee.status],
            }}
            actions={employeeCardActions(employee)}
            onOpen={() => openProfile(employee)}
          />
        ))}
      </div>

      <Pagination
        page={page}
        totalPages={totalPages}
        totalCount={totalCount}
        onPageChange={setPage}
        ariaLabel="ترقيم صفحات الموظفين"
      />
    </>
  )

  const hasActiveFilters = Boolean(search || deptFilter || statusFilter)
  const emptyState = (
    <StatePanel
      kind="empty"
      icon={<Users size={40} />}
      title={hasActiveFilters ? 'لا توجد نتائج مطابقة' : 'لا يوجد موظفون'}
      description={
        hasActiveFilters
          ? 'جرّب تعديل البحث أو فلاتر القسم والحالة.'
          : 'ابدأ بإضافة أول موظف في المنظومة.'
      }
      action={
        !hasActiveFilters && can('hr.employees.create') ? (
          <Button icon={<Plus size={16} />} onClick={openAdd}>موظف جديد</Button>
        ) : undefined
      }
    />
  )

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="إدارة الموظفين"
        subtitle={loading ? '...' : `${totalCount} موظف`}
        actions={
          <PermissionGuard permission="hr.employees.create">
            <Button icon={<Plus size={16} />} onClick={openAdd}>
              موظف جديد
            </Button>
          </PermissionGuard>
        }
      />

      <div className="ds-hr-employee-summary">
        <EmployeeSummary
          metrics={{
            active: statsLoading ? '...' : activeCount,
            onLeave: statsLoading ? '...' : onLeaveCount,
            field: statsLoading ? '...' : fieldEmpCount,
            total: totalCount,
          }}
        />
      </div>

      <Card padding="md" className="ds-hr-filter-surface">
        <div className="ds-hr-filter-row">
          <div className="ds-hr-filter-search">
            <SearchInput
              value={search}
              onChange={value => { setSearch(value); setPage(1) }}
              placeholder="بحث بالاسم أو رقم الموظف..."
            />
          </div>
          <select
            className="form-select ds-hr-filter-select"
            value={deptFilter}
            aria-label="القسم"
            onChange={event => { setDeptFilter(event.target.value); setPage(1) }}
          >
            <option value="">كل الأقسام</option>
            {departments.map(department => (
              <option key={department.id} value={department.id}>{department.name}</option>
            ))}
          </select>
          <select
            className="form-select ds-hr-filter-select"
            value={statusFilter}
            aria-label="الحالة"
            onChange={event => { setStatusFilter(event.target.value as HREmployeeStatus | ''); setPage(1) }}
          >
            <option value="">كل الحالات</option>
            <option value="active">نشط</option>
            <option value="on_leave">في إجازة</option>
            <option value="suspended">موقوف</option>
            <option value="terminated">منتهي الخدمة</option>
          </select>
        </div>
      </Card>

      <ResponsiveCollection<HREmployee>
        items={employees}
        loading={loading}
        emptyState={emptyState}
        renderDesktop={items => (
          <div className="edara-card" style={{ overflow: 'auto' }}>
            <DataTable<HREmployee>
              columns={columns}
              data={items}
              onRowClick={openProfile}
              page={page}
              totalPages={totalPages}
              totalCount={totalCount}
              onPageChange={setPage}
            />
          </div>
        )}
        renderTablet={items => renderEmployeeCards(items, 'tablet')}
        renderMobile={items => renderEmployeeCards(items, 'mobile')}
      />

      <EmployeeForm
        open={formOpen}
        onClose={() => setFormOpen(false)}
        employee={editEmp}
        onToast={(message, type = 'success') => {
          if (type === 'success') toast.success(message)
          else if (type === 'warning') toast.warning(message)
          else toast.error(message)
        }}
      />
    </div>
  )
}
