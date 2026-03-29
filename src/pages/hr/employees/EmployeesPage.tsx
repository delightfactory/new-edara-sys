import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Users, Plus, Eye,
  Briefcase, Building2, Phone,
  CheckCircle, PauseCircle, XCircle, Clock, UserX,
} from 'lucide-react'
import { useHREmployees, useHRDepartments } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { HREmployee, HREmployeeStatus } from '@/lib/types/hr'
import { formatNumber } from '@/lib/utils/format'
import { toast } from 'sonner'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import DataCard from '@/components/ui/DataCard'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import PermissionGuard from '@/components/shared/PermissionGuard'
import EmployeeForm from './EmployeeForm'
import StatCard from '@/components/shared/StatCard'

// ─── Status maps ─────────────────────────────────────────────

const statusLabel: Record<HREmployeeStatus, string> = {
  active:     'نشط',
  on_leave:   'في إجازة',
  suspended:  'موقوف',
  terminated: 'منتهي الخدمة',
}

const statusVariant: Record<HREmployeeStatus, 'success' | 'info' | 'warning' | 'danger'> = {
  active:     'success',
  on_leave:   'info',
  suspended:  'warning',
  terminated: 'danger',
}

const statusIcon: Record<HREmployeeStatus, typeof CheckCircle> = {
  active:     CheckCircle,
  on_leave:   Clock,
  suspended:  PauseCircle,
  terminated: XCircle,
}

// ─── Page ─────────────────────────────────────────────────────

export default function EmployeesPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  const [search, setSearch]           = useState('')
  const [deptFilter, setDeptFilter]   = useState('')
  const [statusFilter, setStatusFilter] = useState<HREmployeeStatus | ''>('')
  const [page, setPage]               = useState(1)
  const [formOpen, setFormOpen]       = useState(false)
  const [editEmp, setEditEmp]         = useState<HREmployee | null>(null)

  // ── جلب البيانات ──────────────────────────
  const { data: departments = [] } = useHRDepartments()

  const queryParams = useMemo(() => ({
    search: search || undefined,
    departmentId: deptFilter || undefined,
    status: statusFilter || undefined,
    page,
    pageSize: 25,
  }), [search, deptFilter, statusFilter, page])

  const { data: result, isLoading: loading } = useHREmployees(queryParams)
  const employees   = result?.data       ?? []
  const totalPages  = result?.totalPages ?? 1
  const totalCount  = result?.count      ?? 0

  // GAP-08: جلب الإحصائيات من الإجمالي الحقيقي
  const { data: activeResult, isLoading: statsLoading } =
    useHREmployees({ status: 'active', pageSize: 1 })
  const { data: leaveResult } =
    useHREmployees({ status: 'on_leave', pageSize: 1 })

  const activeCount   = activeResult?.count ?? 0
  const onLeaveCount  = leaveResult?.count  ?? 0
  // الموظفون الميدانيون: نحسبهم من الصفحة الحالية (لا يوجد فلتر API لذلك)
  const fieldEmpCount = employees.filter(e => e.is_field_employee).length

  // ── Action handlers ────────────────────────
  const openAdd  = () => { setEditEmp(null); setFormOpen(true) }
  const openEdit = (emp: HREmployee) => { setEditEmp(emp); setFormOpen(true) }

  // ─── DataTable columns ────────────────────

  const columns = [
    {
      key: 'employee_number',
      label: 'رقم الموظف',
      render: (e: HREmployee) => (
        <span style={{ fontFamily: 'monospace', fontWeight: 600, fontSize: 'var(--text-sm)' }} dir="ltr">
          {e.employee_number}
        </span>
      ),
    },
    {
      key: 'full_name',
      label: 'الموظف',
      render: (e: HREmployee) => (
        <>
          <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{e.full_name}</div>
          {e.personal_phone && (
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 4 }}>
              <Phone size={10} />
              <span dir="ltr">{e.personal_phone}</span>
            </div>
          )}
        </>
      ),
    },
    {
      key: 'department',
      label: 'القسم',
      hideOnMobile: true,
      render: (e: HREmployee) => (
        <>
          <div style={{ fontSize: 'var(--text-sm)' }}>{e.department?.name ?? '—'}</div>
          {e.position && (
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
              {e.position.name}
            </div>
          )}
        </>
      ),
    },
    {
      key: 'status',
      label: 'الحالة',
      render: (e: HREmployee) => (
        <Badge variant={statusVariant[e.status]}>
          {statusLabel[e.status]}
        </Badge>
      ),
    },
    {
      key: 'base_salary',
      label: 'الراتب الأساسي',
      hideOnMobile: true,
      render: (e: HREmployee) => (
        <PermissionGuard permission="hr.payroll.read">
          <span style={{ fontVariantNumeric: 'tabular-nums', fontWeight: 500 }}>
            {formatNumber(e.base_salary)} ج.م
          </span>
        </PermissionGuard>
      ),
    },
    {
      key: 'type',
      label: 'النوع',
      hideOnMobile: true,
      render: (e: HREmployee) => (
        <Badge variant={e.is_field_employee ? 'warning' : 'neutral'}>
          {e.is_field_employee ? 'ميداني' : 'مكتبي'}
        </Badge>
      ),
    },
    {
      key: 'actions',
      label: '',
      width: 90,
      render: (e: HREmployee) => (
        <div style={{ display: 'flex', gap: 'var(--space-1)' }} onClick={ev => ev.stopPropagation()}>
          <Button variant="ghost" size="sm" onClick={() => navigate(`/hr/employees/${e.id}`)}>
            <Eye size={14} />
          </Button>
          <PermissionGuard permission="hr.employees.edit">
            <Button variant="ghost" size="sm" onClick={() => openEdit(e)}>
              <Briefcase size={14} />
            </Button>
          </PermissionGuard>
        </div>
      ),
    },
  ]

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="إدارة الموظفين"
        subtitle={loading ? '...' : `${totalCount} موظف`}
        actions={
          <PermissionGuard permission="hr.employees.create">
            <Button
              icon={<Plus size={16} />}
              onClick={openAdd}
            >
              موظف جديد
            </Button>
          </PermissionGuard>
        }
      />

      {/* ── إحصائيات سريعة ── */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 'var(--space-3)', marginBottom: 'var(--space-4)' }}>
        <StatCard label="نشط"      value={activeCount}   icon={<CheckCircle size={18} />} color="var(--color-success)" loading={statsLoading} />
        <StatCard label="في إجازة" value={onLeaveCount}  icon={<Clock size={18} />}       color="var(--color-info)"    loading={statsLoading} />
        <StatCard label="ميداني"   value={fieldEmpCount} icon={<UserX size={18} />}       color="var(--color-warning)" loading={statsLoading} />
        <StatCard label="الإجمالي" value={totalCount}    icon={<Users size={18} />}       color="var(--color-primary)" />
      </div>

      {/* ── Filters ── */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="hr-filter-row">
          <div style={{ flex: 2, minWidth: 180 }}>
            <SearchInput
              value={search}
              onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث بالاسم أو رقم الموظف..."
            />
          </div>
          <select
            className="form-select filter-select"
            value={deptFilter}
            onChange={e => { setDeptFilter(e.target.value); setPage(1) }}
          >
            <option value="">كل الأقسام</option>
            {departments.map(d => (
              <option key={d.id} value={d.id}>{d.name}</option>
            ))}
          </select>
          <select
            className="form-select filter-select"
            value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value as HREmployeeStatus | ''); setPage(1) }}
          >
            <option value="">كل الحالات</option>
            <option value="active">نشط</option>
            <option value="on_leave">في إجازة</option>
            <option value="suspended">موقوف</option>
            <option value="terminated">منتهي الخدمة</option>
          </select>
        </div>
      </div>

      {/* ── Desktop: DataTable ── */}
      <div className="hr-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<HREmployee>
          columns={columns}
          data={employees}
          loading={loading}
          onRowClick={e => navigate(`/hr/employees/${e.id}`)}
          emptyIcon={<Users size={48} />}
          emptyTitle="لا يوجد موظفون"
          emptyText="ابدأ بإضافة أول موظف في المنظومة"
          emptyAction={
            can('hr.employees.create') ? (
              <Button icon={<Plus size={16} />} onClick={openAdd}>موظف جديد</Button>
            ) : undefined
          }
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>

      {/* ── Mobile: DataCard list ── */}
      <div className="hr-card-view">
        {loading ? (
          <div className="mobile-card-list">
            {[1, 2, 3].map(i => (
              <div key={i} className="edara-card" style={{ padding: 'var(--space-4)' }}>
                <div className="skeleton" style={{ height: 16, width: '50%', marginBottom: 8 }} />
                <div className="skeleton" style={{ height: 12, width: '35%', marginBottom: 12 }} />
                <div className="skeleton" style={{ height: 12, width: '70%' }} />
              </div>
            ))}
          </div>
        ) : employees.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
            <Users size={40} className="empty-state-icon" />
            <p className="empty-state-title">لا يوجد موظفون</p>
            <p className="empty-state-text">ابدأ بإضافة أول موظف</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {employees.map(emp => {
              const StatusIcon = statusIcon[emp.status]
              return (
                <DataCard
                  key={emp.id}
                  title={emp.full_name}
                  subtitle={
                    <span dir="ltr" style={{ fontFamily: 'monospace', fontSize: '0.7rem' }}>
                      {emp.employee_number}
                    </span>
                  }
                  badge={
                    <Badge variant={statusVariant[emp.status]}>
                      {statusLabel[emp.status]}
                    </Badge>
                  }
                  leading={
                    <div style={{
                      width: 40, height: 40,
                      borderRadius: 'var(--radius-md)',
                      background: 'var(--bg-accent)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                    }}>
                      <StatusIcon size={18} style={{ color: 'var(--color-primary)' }} />
                    </div>
                  }
                  metadata={[
                    { label: 'القسم',  value: emp.department?.name ?? '—' },
                    { label: 'المسمى', value: emp.position?.name  ?? '—' },
                    ...(can('hr.payroll.read') ? [{
                      label: 'الراتب',
                      value: `${formatNumber(emp.base_salary)} ج.م`,
                      highlight: true,
                    }] : []),
                  ]}
                  actions={
                    <Button
                      variant="secondary"
                      size="sm"
                      style={{ width: '100%', justifyContent: 'center' }}
                      onClick={() => navigate(`/hr/employees/${emp.id}`)}
                    >
                      <Eye size={14} /> عرض الملف
                    </Button>
                  }
                  onClick={() => navigate(`/hr/employees/${emp.id}`)}
                />
              )
            })}
          </div>
        )}

        {totalPages > 1 && (
          <div className="mobile-pagination">
            <Button variant="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>السابق</Button>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>{page} / {totalPages}</span>
            <Button variant="ghost" size="sm" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>التالي</Button>
          </div>
        )}
      </div>

      {/* FAB للموبايل */}
      {/* نموذج الإضافة / التعديل */}
      <EmployeeForm
        open={formOpen}
        onClose={() => setFormOpen(false)}
        employee={editEmp}
        onToast={(msg, type = 'success') => {
          if (type === 'success') toast.success(msg)
          else if (type === 'warning') toast.warning(msg)
          else toast.error(msg)
        }}
      />

      <style>{`
        /* ── Filters ── */
        .hr-filter-row {
          display: flex; gap: var(--space-3); flex-wrap: wrap; align-items: flex-end;
        }
        .filter-select { min-width: 110px; flex: 1; }

        /* ── Responsive table/card switch ── */
        .hr-table-view { display: block; }
        .hr-card-view  { display: none; }
        @media (max-width: 768px) {
          .hr-table-view       { display: none; }
          .hr-card-view        { display: block; }
          .filter-select       { font-size: var(--text-xs); }
        }

        .mobile-card-list {
          display: flex; flex-direction: column; gap: var(--space-3);
          padding: 0 0 var(--space-2);
        }
        .mobile-pagination {
          display: flex; align-items: center; justify-content: center;
          gap: var(--space-4); padding: var(--space-4) 0;
        }
      `}</style>
    </div>
  )
}
