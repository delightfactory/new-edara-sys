import { useState, useRef, useCallback, Fragment } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import {
  ArrowRight, UserCog, User, FileText, Calendar,
  Shield, Phone, MapPin, Briefcase, Building2,
  AlertCircle, TrendingUp, TrendingDown, Minus,
  Clock,
} from 'lucide-react'
import {
  useHREmployee,
  useHRLeaveBalances,
} from '@/hooks/useQueryHooks'
import { getEmployeeLiveStatement, getContracts, createContract, getEmployeeSalaryHistory, updateSalaryDirectly, uploadEmployeeDocument, getDelegations, createDelegation, cancelDelegation, getEmployees } from '@/lib/services/hr'
import { getAdvances, getAdvanceInstallments, deferInstallment } from '@/lib/services/hr'
import { getAttendanceDays } from '@/lib/services/hr'
import { getCommissionTargets, getCommissionRecords } from '@/lib/services/hr'
import { getPenaltyInstances, overridePenalty } from '@/lib/services/hr'
import { supabase } from '@/lib/supabase/client'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useAuthStore } from '@/stores/auth-store'
import type {
  HREmployee, HREmployeeStatus, HRLeaveBalance, HREmployeeDocument,
  EmployeeLiveStatement, HRContractType, HRAttendanceStatus,
  HRDocumentType, HRDelegation, HRDelegationInput, HRDelegationScopeType,
  HRAdvanceInstallment, HRContractInput,
} from '@/lib/types/hr'
import { formatNumber } from '@/lib/utils/format'
import DataTable from '@/components/shared/DataTable'
import DataCard from '@/components/ui/DataCard'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Spinner from '@/components/ui/Spinner'
import PermissionGuard from '@/components/shared/PermissionGuard'
import EmployeeForm from './EmployeeForm'
import OffboardingModal from './OffboardingModal'
import { toast } from 'sonner'
import Input from '@/components/ui/Input'
import Select from '@/components/ui/Select'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import AsyncCombobox from '@/components/ui/AsyncCombobox'
import type { ComboboxOption } from '@/components/ui/AsyncCombobox'

// ─── Status maps ─────────────────────────────
const statusLabel: Record<HREmployeeStatus, string> = {
  active: 'نشط', on_leave: 'في إجازة', suspended: 'موقوف', terminated: 'منتهي الخدمة',
}
const statusVariant: Record<HREmployeeStatus, 'success' | 'info' | 'warning' | 'danger'> = {
  active: 'success', on_leave: 'info', suspended: 'warning', terminated: 'danger',
}

// ─── دالة مساعدة لتنسيق التاريخ ──────────────
const fmtDate = (d?: string | null) =>
  d ? new Date(d).toLocaleDateString('ar-EG-u-nu-latn') : '—'

// ─── Avatar بالحرف الأول ───────────────────────
function Avatar({ name, status }: { name: string; status: HREmployeeStatus }) {
  const initial = name.trim().charAt(0)
  const color = status === 'active' ? 'var(--color-primary)' : 'var(--text-muted)'
  return (
    <div style={{
      width: 64, height: 64,
      borderRadius: 'var(--radius-full)',
      background: `color-mix(in srgb, ${color} 14%, transparent)`,
      border: `2px solid color-mix(in srgb, ${color} 30%, transparent)`,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontSize: '1.6rem', fontWeight: 700, color,
      flexShrink: 0,
    }}>
      {initial}
    </div>
  )
}

// ─── حقل readonly ─────────────────────────────
function InfoField({ label, value, icon, dir }: {
  label: string; value?: string | null; icon?: React.ReactNode; dir?: 'ltr' | 'rtl'
}) {
  return (
    <div className="prof-field">
      <span className="prof-field-label">
        {icon && <span style={{ opacity: 0.6 }}>{icon}</span>}
        {label}
      </span>
      <span className="prof-field-value" dir={dir}>
        {value || <span style={{ color: 'var(--text-muted)' }}>—</span>}
      </span>
    </div>
  )
}

// ─── Tab types ────────────────────────────────
type Tab = 'info' | 'documents' | 'leaves' | 'statement' | 'contracts' | 'advances' | 'attendance' | 'targets' | 'penalties' | 'delegations'

// ═════════════════════════════════════════════
// MAIN COMPONENT
// ═════════════════════════════════════════════

export default function EmployeeProfile() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const qc = useQueryClient()

  const [activeTab, setActiveTab] = useState<Tab>('info')
  const [editOpen, setEditOpen] = useState(false)
  // GAP-03: ربط حساب المستخدم
  const [linkAccountOpen, setLinkAccountOpen] = useState(false)
  const [linkEmail, setLinkEmail] = useState('')
  const [linking, setLinking] = useState(false)
  // GAP-06: طلب سلفة سريعة من ملف الموظف
  const [quickAdvOpen, setQuickAdvOpen] = useState(false)
  const [advAmount, setAdvAmount] = useState('')
  const [advReason, setAdvReason] = useState('')
  const [advType, setAdvType] = useState<'instant'|'scheduled'>('instant')
  const [submittingAdv, setSubmittingAdv] = useState(false)

  // Wave 2B: Offboarding flow
  const [offboardOpen, setOffboardOpen] = useState(false)

  // ── جلب بيانات الموظف ─────────────────────
  const { data: emp, isLoading, error } = useHREmployee(id)

  // ── Loading / Error state ──────────────────
  if (isLoading) return (
    <div style={{ display: 'flex', justifyContent: 'center', padding: 'var(--space-12)' }}>
      <Spinner />
    </div>
  )

  if (error || !emp) return (
    <div className="page-container">
      <div className="empty-state" style={{ padding: 'var(--space-12)' }}>
        <AlertCircle size={48} className="empty-state-icon" style={{ color: 'var(--color-danger)' }} />
        <p className="empty-state-title">لم يُعثر على الموظف</p>
        <Button variant="secondary" onClick={() => navigate('/hr/employees')}>
          <ArrowRight size={14} /> العودة للقائمة
        </Button>
      </div>
    </div>
  )

  // تعريف التابات مع صلاحيات الوصول
  type TabDef = { id: Tab; label: string; icon: typeof User; permission?: string | string[] }
  const tabs: TabDef[] = [
    { id: 'info',        label: 'البيانات الأساسية', icon: User },
    { id: 'documents',   label: 'الوثائق',           icon: FileText },
    { id: 'contracts',   label: 'العقود والراتب',    icon: TrendingUp,    permission: 'hr.employees.edit' },
    { id: 'leaves',      label: 'الإجازات',          icon: Calendar,       permission: ['hr.leaves.read', 'hr.leaves.approve'] },
    { id: 'advances',    label: 'السلف',             icon: TrendingDown,   permission: ['hr.advances.read', 'hr.advances.approve', 'hr.advances.create'] },
    { id: 'attendance',  label: 'الحضور',            icon: Clock,          permission: ['hr.attendance.read', 'hr.employees.read'] },
    { id: 'penalties',   label: 'الجزاءات',          icon: AlertCircle,    permission: ['hr.attendance.edit', 'hr.attendance.approve'] },
    { id: 'delegations', label: 'التفويضات',         icon: Shield,         permission: ['hr.leaves.approve', 'hr.advances.approve', 'hr.attendance.approve', 'hr.permissions.approve'] },
    ...(emp.is_field_employee ? [{ id: 'targets' as Tab, label: 'الأهداف', icon: TrendingUp }] : []),
    { id: 'statement',   label: 'كشف الحساب',       icon: Shield,         permission: 'hr.payroll.read' },
  ]

  return (
    <div className="page-container animate-enter">

      {/* ══ HERO CARD — تصميم متجاوب جديد ══ */}
      <div className="prof-hero-card edara-card">

        {/* الشريط العلوي: رقم الموظف + أزرار */}
        <div className="prof-hero-topbar">
          <div className="prof-hero-breadcrumb">
            <button
              type="button"
              className="prof-back-btn"
              onClick={() => navigate('/hr/employees')}
              title="العودة للقائمة"
            >
              <ArrowRight size={16} />
            </button>
            <span className="prof-emp-number">{emp.employee_number}</span>
          </div>
          <div className="prof-hero-actions">
            <PermissionGuard permission="hr.advances.create">
              <Button variant="secondary" size="sm" onClick={() => setQuickAdvOpen(true)}>
                طلب سلفة
              </Button>
            </PermissionGuard>
            <PermissionGuard permission="hr.employees.edit">
              {!emp.user_id && emp.status !== 'terminated' && (
                <Button variant="secondary" size="sm" onClick={() => setLinkAccountOpen(true)}>
                  ربط حساب
                </Button>
              )}
            </PermissionGuard>
            {emp.status !== 'terminated' && (
              <PermissionGuard permission="hr.employees.edit">
                <Button variant="danger" size="sm" onClick={() => setOffboardOpen(true)} icon={<AlertCircle size={14} />}>
                  إنهاء الخدمة
                </Button>
              </PermissionGuard>
            )}
            <PermissionGuard permission="hr.employees.edit">
              <Button icon={<UserCog size={14} />} size="sm" onClick={() => setEditOpen(true)}>
                تعديل
              </Button>
            </PermissionGuard>
          </div>
        </div>

        {/* جسم البطاقة */}
        <div className="prof-hero-body">
          {/* أفاتار */}
          <div className="prof-avatar-wrap">
            <div
              className="prof-avatar"
              style={{
                '--avatar-color': emp.status === 'active'
                  ? 'var(--color-primary)'
                  : emp.status === 'on_leave'
                  ? 'var(--color-info)'
                  : 'var(--text-muted)',
              } as React.CSSProperties}
            >
              {emp.full_name.trim().charAt(0)}
            </div>
            <span
              className="prof-avatar-status"
              style={{
                background: statusVariant[emp.status] === 'success' ? 'var(--color-success)'
                  : statusVariant[emp.status] === 'info' ? 'var(--color-info)'
                  : statusVariant[emp.status] === 'warning' ? 'var(--color-warning)'
                  : 'var(--color-danger)',
              }}
            />
          </div>

          {/* المعلومات */}
          <div className="prof-hero-info">
            <div className="prof-hero-name">
              {emp.full_name}
              {emp.full_name_en && (
                <span className="prof-hero-name-en">{emp.full_name_en}</span>
              )}
            </div>

            {/* التاجات */}
            <div className="prof-hero-tags">
              <Badge variant={statusVariant[emp.status]}>{statusLabel[emp.status]}</Badge>
              {emp.status === 'terminated' && emp.termination_date && (
                <Badge variant="danger">
                  <span style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
                    <Calendar size={11} />
                    أُنهيت في: {fmtDate(emp.termination_date)}
                    {emp.termination_reason && ` - ${emp.termination_reason}`}
                  </span>
                </Badge>
              )}
              {emp.position?.name && (
                <span className="prof-tag">
                  <Briefcase size={11} /> {emp.position.name}
                </span>
              )}
              {emp.department?.name && (
                <span className="prof-tag">
                  <Building2 size={11} /> {emp.department.name}
                </span>
              )}
              {emp.is_field_employee && (
                <span className="prof-tag prof-tag--accent">مندوب ميداني</span>
              )}
            </div>

            {/* Stats row */}
            <div className="prof-stats-row">
              <div className="prof-stat">
                <span className="prof-stat-label">تاريخ التعيين</span>
                <span className="prof-stat-value">{fmtDate(emp.hire_date)}</span>
              </div>
              {can('hr.payroll.read') && emp.gross_salary > 0 && (
                <div className="prof-stat">
                  <span className="prof-stat-label">الراتب الإجمالي</span>
                  <span className="prof-stat-value prof-stat-value--primary">
                    {formatNumber(emp.gross_salary)} ج.م
                  </span>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* ══ TABS ══ */}
      <div className="prof-tabs-wrap">
        <div className="prof-tabs" role="tablist">
          {tabs.map(t => {
            if (t.permission) {
              const hasAccess = Array.isArray(t.permission)
                ? t.permission.some(p => can(p))
                : can(t.permission)
              if (!hasAccess) return null
            }
            const Icon = t.icon
            return (
              <button
                key={t.id}
                type="button"
                role="tab"
                id={`emp-profile-tab-${t.id}`}
                aria-selected={activeTab === t.id}
                className={`prof-tab ${activeTab === t.id ? 'prof-tab--active' : ''}`}
                onClick={() => setActiveTab(t.id)}
              >
                <span className="prof-tab-icon"><Icon size={14} /></span>
                <span className="prof-tab-label">{t.label}</span>
              </button>
            )
          })}
        </div>
      </div>

      {/* ══ TAB CONTENT ══ */}
      <div className="prof-panel">
        {activeTab === 'info'        && <InfoTab      emp={emp} />}
        {activeTab === 'documents'   && <DocumentsTab emp={emp} />}
        {activeTab === 'leaves'      && <LeavesTab    employeeId={emp.id} />}
        {activeTab === 'contracts'   && <ContractsTab employeeId={emp.id} />}
        {activeTab === 'advances'    && <AdvancesTab  employeeId={emp.id} />}
        {activeTab === 'attendance'  && <AttendanceCalendarTab employeeId={emp.id} />}
        {activeTab === 'penalties'   && <PenaltiesTab employeeId={emp.id} />}
        {activeTab === 'delegations' && <DelegationsTab employee={emp} />}
        {activeTab === 'targets'     && emp.is_field_employee && <TargetsTab employeeId={emp.id} />}
        {activeTab === 'statement'   && (
          <PermissionGuard permission="hr.payroll.read">
            <StatementTab employeeId={emp.id} />
          </PermissionGuard>
        )}
      </div>

      {/* Form تعديل الموظف */}
      <EmployeeForm
        open={editOpen}
        onClose={() => setEditOpen(false)}
        employee={emp}
        onToast={(msg, type = 'success') => {
          if (type === 'success') toast.success(msg)
          else if (type === 'warning') toast.warning(msg)
          else toast.error(msg)
        }}
      />

      <OffboardingModal
        open={offboardOpen}
        onClose={() => setOffboardOpen(false)}
        employeeId={emp.id}
        employeeName={emp.full_name}
      />

      <style>{`
        /* ══════════════════════════════════════════════════
           HERO CARD
        ══════════════════════════════════════════════════ */
        .prof-hero-card {
          padding: 0;
          overflow: hidden;
          margin-bottom: var(--space-4);
        }

        /* Topbar: رقم + أزرار */
        .prof-hero-topbar {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: var(--space-3) var(--space-5);
          border-bottom: 1px solid var(--border-primary);
          background: var(--bg-surface-2);
          flex-wrap: wrap;
          gap: var(--space-2);
        }
        .prof-hero-breadcrumb {
          display: flex; align-items: center; gap: var(--space-2);
        }
        .prof-back-btn {
          width: 32px; height: 32px;
          border-radius: var(--radius-md);
          border: 1px solid var(--border-primary);
          background: var(--bg-surface);
          color: var(--text-secondary);
          cursor: pointer;
          display: flex; align-items: center; justify-content: center;
          transition: all 0.15s;
          flex-shrink: 0;
        }
        .prof-back-btn:hover { background: var(--bg-hover); color: var(--text-primary); }
        .prof-emp-number {
          font-size: var(--text-xs); font-weight: 700;
          color: var(--text-muted); font-family: monospace; letter-spacing: 0.05em;
          background: var(--bg-surface); border: 1px solid var(--border-primary);
          border-radius: var(--radius-full); padding: 2px 10px;
        }
        .prof-hero-actions { display: flex; gap: var(--space-2); flex-wrap: wrap; }

        /* Body: أفاتار + معلومات */
        .prof-hero-body {
          display: flex; align-items: flex-start;
          gap: var(--space-5); padding: var(--space-5) var(--space-6);
        }

        /* أفاتار */
        .prof-avatar-wrap { position: relative; flex-shrink: 0; }
        .prof-avatar {
          width: 72px; height: 72px; border-radius: 50%;
          background: color-mix(in srgb, var(--avatar-color, var(--color-primary)) 12%, var(--bg-surface-2));
          border: 3px solid color-mix(in srgb, var(--avatar-color, var(--color-primary)) 25%, transparent);
          display: flex; align-items: center; justify-content: center;
          font-size: 1.8rem; font-weight: 800;
          color: var(--avatar-color, var(--color-primary)); line-height: 1;
        }
        .prof-avatar-status {
          position: absolute; bottom: 3px; inset-inline-end: 3px;
          width: 14px; height: 14px; border-radius: 50%;
          border: 2px solid var(--bg-surface);
        }

        /* معلومات */
        .prof-hero-info { flex: 1; min-width: 0; }
        .prof-hero-name {
          font-size: var(--text-xl); font-weight: 800; color: var(--text-primary);
          margin-bottom: var(--space-2); display: flex; align-items: baseline;
          gap: var(--space-2); flex-wrap: wrap; line-height: 1.3;
        }
        .prof-hero-name-en { font-size: var(--text-sm); color: var(--text-muted); font-weight: 400; }

        /* Tags */
        .prof-hero-tags {
          display: flex; flex-wrap: wrap; gap: var(--space-2);
          align-items: center; margin-bottom: var(--space-3);
        }
        .prof-tag {
          display: inline-flex; align-items: center; gap: 4px;
          font-size: var(--text-xs); color: var(--text-secondary);
          background: var(--bg-surface-2); border: 1px solid var(--border-primary);
          border-radius: var(--radius-full); padding: 3px 10px; white-space: nowrap;
        }
        .prof-tag--accent {
          color: var(--color-primary); background: var(--color-primary-light);
          border-color: color-mix(in srgb, var(--color-primary) 25%, transparent); font-weight: 600;
        }

        /* Stats row */
        .prof-stats-row { display: flex; flex-wrap: wrap; gap: var(--space-4); }
        .prof-stat { display: flex; flex-direction: column; gap: 2px; }
        .prof-stat-label { font-size: var(--text-xs); color: var(--text-muted); font-weight: 500; }
        .prof-stat-value { font-size: var(--text-sm); font-weight: 700; color: var(--text-primary); }
        .prof-stat-value--primary { color: var(--color-primary); }

        /* ══════════════════════════════════════════════════
           TABS
        ══════════════════════════════════════════════════ */
        .prof-tabs-wrap {
          position: sticky;
          top: var(--app-bar-height, 56px);
          z-index: 10;
          background: var(--bg-app);
          margin-bottom: var(--space-4);
        }
        .prof-tabs {
          display: flex; gap: 0;
          border-bottom: 2px solid var(--border-primary);
          overflow-x: auto; scrollbar-width: none;
          -webkit-mask-image: linear-gradient(to left, transparent 0px, black 40px);
          mask-image: linear-gradient(to left, transparent 0px, black 40px);
        }
        .prof-tabs::-webkit-scrollbar { display: none; }
        .prof-tab {
          display: inline-flex; align-items: center; gap: 6px;
          padding: var(--space-3) var(--space-4);
          font-size: var(--text-sm); font-weight: 500;
          color: var(--text-muted); background: transparent; border: none;
          cursor: pointer; border-bottom: 2px solid transparent;
          margin-bottom: -2px; white-space: nowrap;
          transition: color 0.15s, border-color 0.15s, background 0.15s;
          font-family: var(--font-sans);
          border-radius: var(--radius-md) var(--radius-md) 0 0;
        }
        .prof-tab:hover { color: var(--text-primary); background: var(--bg-hover); }
        .prof-tab--active {
          color: var(--color-primary); border-bottom-color: var(--color-primary);
          background: color-mix(in srgb, var(--color-primary) 5%, transparent); font-weight: 600;
        }
        .prof-tab-icon { display: flex; align-items: center; }

        /* ══════════════════════════════════════════════════
           CONTENT PANEL
        ══════════════════════════════════════════════════ */
        .prof-panel { animation: fade-in-up 0.2s ease; }
        @keyframes fade-in-up {
          from { opacity: 0; transform: translateY(6px); }
          to   { opacity: 1; transform: translateY(0); }
        }

        /* ── InfoField ── */
        .prof-fields-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
          gap: 0;
        }
        .prof-field {
          display: flex; flex-direction: column; gap: var(--space-1);
          padding: var(--space-3) var(--space-4); border-radius: var(--radius-md);
          transition: background 0.15s;
        }
        .prof-field:hover { background: var(--bg-hover); }
        .prof-field-label {
          display: flex; align-items: center; gap: var(--space-1);
          font-size: var(--text-xs); color: var(--text-muted); font-weight: 600;
          text-transform: uppercase; letter-spacing: 0.04em;
        }
        .prof-field-value { font-size: var(--text-sm); color: var(--text-primary); font-weight: 500; }

        /* ── Section heading ── */
        .prof-section-title {
          font-size: var(--text-xs); font-weight: 700;
          text-transform: uppercase; letter-spacing: 0.06em; color: var(--text-muted);
          padding: var(--space-4) var(--space-4) var(--space-2);
          border-bottom: 1px solid var(--border-primary); margin-bottom: var(--space-1);
        }

        /* ── Leave balance cards ── */
        .leave-balance-grid {
          display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: var(--space-3);
        }
        .leave-balance-card {
          padding: var(--space-4); border-radius: var(--radius-lg);
          border: 1px solid var(--border-primary); background: var(--bg-surface);
          display: flex; flex-direction: column; gap: var(--space-2);
          transition: box-shadow 0.2s, transform 0.2s;
        }
        .leave-balance-card:hover { box-shadow: var(--shadow-md); transform: translateY(-1px); }
        .leave-balance-name { font-size: var(--text-sm); font-weight: 600; color: var(--text-primary); }
        .leave-balance-row { display: flex; justify-content: space-between; font-size: var(--text-xs); color: var(--text-secondary); }
        .leave-balance-remaining {
          font-size: var(--text-3xl); font-weight: 800; color: var(--color-primary);
          font-variant-numeric: tabular-nums; line-height: 1;
        }
        .leave-balance-unit { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }

        /* ── Statement ── */
        .statement-grid { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-4); }
        .statement-section { border: 1px solid var(--border-primary); border-radius: var(--radius-lg); overflow: hidden; }
        .statement-section-header {
          display: flex; align-items: center; gap: var(--space-2);
          padding: var(--space-3) var(--space-4); font-size: var(--text-sm);
          font-weight: 700; border-bottom: 1px solid var(--border-primary);
        }
        .statement-section-header--debit { background: color-mix(in srgb, var(--color-success) 6%, transparent); color: var(--color-success); }
        .statement-section-header--credit { background: color-mix(in srgb, var(--color-danger) 6%, transparent); color: var(--color-danger); }
        .statement-line {
          display: flex; justify-content: space-between; align-items: center;
          padding: var(--space-2) var(--space-4); font-size: var(--text-sm);
          border-bottom: 1px solid var(--border-primary);
        }
        .statement-line:last-child { border-bottom: none; }
        .statement-line-label { color: var(--text-secondary); }
        .statement-line-value { font-weight: 600; font-variant-numeric: tabular-nums; }
        .statement-net {
          display: flex; align-items: center; justify-content: space-between;
          padding: var(--space-4) var(--space-5);
          background: color-mix(in srgb, var(--color-primary) 6%, transparent);
        }
        .statement-net-label { font-size: var(--text-sm); color: var(--text-secondary); font-weight: 600; }
        .statement-net-value { font-size: var(--text-2xl); font-weight: 800; color: var(--color-primary); font-variant-numeric: tabular-nums; }

        /* ── Documents ── */
        .doc-list { display: flex; flex-direction: column; gap: var(--space-2); }
        .doc-item {
          display: flex; align-items: center; gap: var(--space-3);
          padding: var(--space-3) var(--space-4); border: 1px solid var(--border-primary);
          border-radius: var(--radius-md); background: var(--bg-surface); transition: all 0.15s;
        }
        .doc-item:hover { background: var(--bg-hover); box-shadow: var(--shadow-sm); }
        .doc-icon {
          width: 36px; height: 36px; border-radius: var(--radius-md);
          background: color-mix(in srgb, var(--color-primary) 10%, transparent);
          display: flex; align-items: center; justify-content: center;
          color: var(--color-primary); flex-shrink: 0;
        }
        .doc-info { flex: 1; min-width: 0; }
        .doc-type { font-size: var(--text-sm); font-weight: 600; color: var(--text-primary); }
        .doc-meta { font-size: var(--text-xs); color: var(--text-muted); }

        /* ══════════════════════════════════════════════════
           RESPONSIVE — MOBILE
        ══════════════════════════════════════════════════ */
        @media (max-width: 640px) {
          .prof-hero-body {
            flex-direction: column; align-items: center;
            text-align: center; padding: var(--space-5) var(--space-4); gap: var(--space-4);
          }
          .prof-hero-name { justify-content: center; }
          .prof-hero-tags { justify-content: center; }
          .prof-stats-row { justify-content: center; }
          .prof-hero-topbar { padding: var(--space-2) var(--space-3); }
          .prof-hero-actions { flex-wrap: wrap; }
          .prof-tab { padding: var(--space-2) var(--space-3); font-size: var(--text-xs); }
          .prof-tab-label { display: none; }
          .prof-tab--active .prof-tab-label { display: inline; }
          .prof-avatar { width: 60px; height: 60px; font-size: 1.5rem; }
          .statement-grid { grid-template-columns: 1fr; }
          .leave-balance-grid { grid-template-columns: 1fr 1fr; }
          .prof-fields-grid { grid-template-columns: 1fr; }
        }
        @media (max-width: 400px) {
          .leave-balance-grid { grid-template-columns: 1fr; }
        }
      `}</style>

      {/* GAP-03: Modal ربط حساب المستخدم */}
      <ResponsiveModal
        open={linkAccountOpen}
        onClose={() => { setLinkAccountOpen(false); setLinkEmail('') }}
        title="ربط حساب مستخدم"
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => setLinkAccountOpen(false)} style={{ flex: 1 }}>إلغاء</Button>
            <Button
              loading={linking}
              disabled={!linkEmail.trim()}
              style={{ flex: 2 }}
              onClick={async () => {
                if (!linkEmail.trim()) return
                setLinking(true)
                try {
                  const sb = supabase
                  const { data: users, error } = await sb
                    .from('profiles')
                    .select('id, email')
                    .ilike('email', linkEmail.trim())
                    .limit(1)
                  if (error || !users?.length) { toast.error('لم يُعثر على مستخدم بهذا الإيميل'); setLinking(false); return }
                  const { error: updateErr } = await sb
                    .from('hr_employees')
                    .update({ user_id: users[0].id })
                    .eq('id', emp.id)
                  if (updateErr) throw updateErr
                  toast.success('تم ربط الحساب بنجاح')
                  qc.invalidateQueries({ queryKey: ['hr-employee', emp.id] })
                  setLinkAccountOpen(false)
                  setLinkEmail('')
                } catch (e: any) {
                  toast.error(e.message ?? 'فشل الربط')
                } finally {
                  setLinking(false)
                }
              }}
            >تأكيد الربط</Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)' }}>
            سيتم ربط الموظف <strong>{emp.full_name}</strong> بحساب المستخدم المربوط بالإيميل التالي.
          </p>
          <Input
            label="إيميل المستخدم"
            required
            type="email"
            value={linkEmail}
            onChange={e => setLinkEmail(e.target.value)}
            placeholder="user@example.com"
          />
        </div>
      </ResponsiveModal>

      {/* GAP-06: Modal طلب السلفة السريعة */}
      <ResponsiveModal
        open={quickAdvOpen}
        onClose={() => { setQuickAdvOpen(false); setAdvAmount(''); setAdvReason('') }}
        title={`طلب سلفة — ${emp.full_name}`}
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => setQuickAdvOpen(false)} style={{ flex: 1 }}>إلغاء</Button>
            <Button
              loading={submittingAdv}
              disabled={!advAmount || parseFloat(advAmount) <= 0 || !advReason.trim()}
              style={{ flex: 2 }}
              onClick={async () => {
                setSubmittingAdv(true)
                try {
                  const { requestAdvance } = await import('@/lib/services/hr')
                  await requestAdvance({
                    employee_id:        emp.id,
                    amount:             parseFloat(advAmount),
                    reason:             advReason.trim(),
                    advance_type:       advType,
                    installments_count: advType === 'scheduled' ? 3 : 1,
                  })
                  toast.success('تم تقديم طلب السلفة بنجاح')
                  setQuickAdvOpen(false)
                  setAdvAmount('')
                  setAdvReason('')
                  qc.invalidateQueries({ queryKey: ['hr-advances-employee', emp.id] })
                } catch (e: any) {
                  toast.error(e.message ?? 'فشل الطلب')
                } finally {
                  setSubmittingAdv(false)
                }
              }}
            >تقديم الطلب</Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <Input label="مبلغ السلفة" required type="number" value={advAmount}
            onChange={e => setAdvAmount(e.target.value)} placeholder="0.00" />
          <Select
            label="نوع السلفة"
            value={advType}
            onChange={e => setAdvType(e.target.value as 'instant'|'scheduled')}
            options={[
              { value: 'instant',   label: 'دفع فوري' },
              { value: 'scheduled', label: 'أقساط شهرية' },
            ]}
          />
          <Input label="السبب" required value={advReason}
            onChange={e => setAdvReason(e.target.value)} placeholder="سبب طلب السلفة..." />
        </div>
      </ResponsiveModal>
    </div>
  )
}

// ═════════════════════════════════════════════
// TAB 1: INFO
// ═════════════════════════════════════════════

function InfoTab({ emp }: { emp: HREmployee }) {
  const genderLabel: Record<string, string> = { male: 'ذكر', female: 'أنثى' }
  const maritalLabel: Record<string, string> = {
    single: 'أعزب/عزباء', married: 'متزوج/متزوجة', divorced: 'مطلق/مطلقة', widowed: 'أرمل/أرملة',
  }
  const dayLabel: Record<string, string> = {
    friday: 'الجمعة', saturday: 'السبت', sunday: 'الأحد',
    thursday: 'الخميس', monday: 'الإثنين',
  }

  return (
    <div className="edara-card" style={{ padding: 0 }}>
      {/* البيانات الشخصية */}
      <div className="prof-section-title">البيانات الشخصية</div>
      <div className="prof-fields-grid">
        <InfoField label="الاسم الكامل"      value={emp.full_name}            icon={<User size={12} />} />
        <InfoField label="الاسم بالإنجليزية" value={emp.full_name_en} />
        <InfoField label="الرقم القومي"       value={emp.national_id}          icon={<Shield size={12} />} />
        <InfoField label="تاريخ الميلاد"      value={fmtDate(emp.birth_date)}  icon={<Calendar size={12} />} />
        <InfoField label="الجنس"              value={emp.gender ? genderLabel[emp.gender] : null} />
        <InfoField label="الحالة الاجتماعية"  value={emp.marital_status ? maritalLabel[emp.marital_status] : null} />
        <InfoField label="هاتف شخصي"          value={emp.personal_phone}       icon={<Phone size={12} />} dir="ltr" />
        <InfoField label="هاتف طوارئ"         value={emp.emergency_phone}      icon={<Phone size={12} />} dir="ltr" />
        <InfoField label="جهة اتصال طارئ"     value={emp.emergency_contact} />
        <InfoField label="العنوان"             value={emp.address}              icon={<MapPin size={12} />} />
      </div>

      {/* بيانات التوظيف */}
      <div className="prof-section-title" style={{ marginTop: 'var(--space-2)' }}>بيانات التوظيف</div>
      <div className="prof-fields-grid">
        <InfoField label="رقم الموظف"         value={emp.employee_number}      icon={<Briefcase size={12} />} dir="ltr" />
        <InfoField label="القسم"              value={emp.department?.name}     icon={<Building2 size={12} />} />
        <InfoField label="المسمى الوظيفي"     value={emp.position?.name}       icon={<Briefcase size={12} />} />
        <InfoField label="المدير المباشر"     value={(emp as any).direct_manager?.full_name} />
        <InfoField label="تاريخ التعيين"      value={fmtDate(emp.hire_date)}   icon={<Calendar size={12} />} />
        <InfoField label="نهاية فترة التجربة" value={fmtDate(emp.probation_end_date)} />
        <InfoField label="يوم الراحة الأسبوعي" value={emp.weekly_off_day ? dayLabel[emp.weekly_off_day] : 'يتبع الشركة'} />
        <InfoField label="نوع الموظف"         value={emp.is_field_employee ? 'ميداني' : 'مكتبي'} />
        {emp.work_location?.name && (
          <InfoField label="موقع الحضور"      value={emp.work_location.name}   icon={<MapPin size={12} />} />
        )}
        {emp.status === 'terminated' && (
          <>
            <InfoField label="تاريخ الإنهاء"  value={fmtDate(emp.termination_date)} />
            <InfoField label="سبب الإنهاء"    value={emp.termination_reason} />
          </>
        )}
      </div>

      {emp.notes && (
        <>
          <div className="prof-section-title" style={{ marginTop: 'var(--space-2)' }}>ملاحظات</div>
          <div style={{ padding: 'var(--space-3) var(--space-4)', fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>
            {emp.notes}
          </div>
        </>
      )}
    </div>
  )
}

// ═════════════════════════════════════════════
// TAB 2: DOCUMENTS
// ═════════════════════════════════════════════

const docTypeLabel: Record<string, string> = {
  national_id:              'بطاقة رقم قومي',
  passport:                 'جواز سفر',
  driving_license:          'رخصة قيادة',
  employment_contract:      'عقد عمل',
  educational_certificate:  'شهادة علمية',
  social_insurance:         'تأمين اجتماعي',
  medical_certificate:      'شهادة طبية',
  other:                    'مستند آخر',
}

function DocumentsTab({ emp }: { emp: HREmployee & { documents?: HREmployeeDocument[] } }) {
  const qc = useQueryClient()
  const [docs, setDocs] = useState<HREmployeeDocument[]>(emp.documents ?? [])
  const [uploadOpen, setUploadOpen] = useState(false)
  const [uploading, setUploading] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  // form state
  const [docType,    setDocType]    = useState<HRDocumentType>('national_id')
  const [docNumber,  setDocNumber]  = useState('')
  const [issueDate,  setIssueDate]  = useState('')
  const [expiryDate, setExpiryDate] = useState('')
  const [docNotes,   setDocNotes]   = useState('')
  const [file,       setFile]       = useState<File | null>(null)

  const resetForm = () => {
    setDocType('national_id'); setDocNumber(''); setIssueDate('')
    setExpiryDate(''); setDocNotes(''); setFile(null)
    if (fileRef.current) fileRef.current.value = ''
  }

  const handleUpload = async () => {
    if (!file) return
    setUploading(true)
    try {
      const newDoc = await uploadEmployeeDocument({
        employeeId:     emp.id,
        documentType:   docType,
        documentNumber: docNumber  || null,
        issueDate:      issueDate  || null,
        expiryDate:     expiryDate || null,
        notes:          docNotes   || null,
        file,
      })
      setDocs(prev => [newDoc, ...prev])
      qc.invalidateQueries({ queryKey: ['hr-employee', emp.id] })
      toast.success('تم رفع الوثيقة بنجاح')
      setUploadOpen(false)
      resetForm()
    } catch (e: any) {
      toast.error(e.message ?? 'فشل رفع الوثيقة')
    } finally {
      setUploading(false)
    }
  }

  return (
    <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-4)' }}>
        <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)' }}>
          {docs.length} وثيقة
        </span>
        <PermissionGuard permission="hr.employees.edit">
          <Button size="sm" variant="secondary" icon={<FileText size={14} />} onClick={() => setUploadOpen(true)}>
            رفع وثيقة
          </Button>
        </PermissionGuard>
      </div>

      {docs.length === 0 ? (
        <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
          <FileText size={36} className="empty-state-icon" />
          <p className="empty-state-title">لا توجد وثائق</p>
          <p className="empty-state-text">أضف وثائق الموظف كعقد العمل والهوية</p>
        </div>
      ) : (
        <div className="doc-list">
          {docs.map(doc => (
            <div key={doc.id} className="doc-item">
              <div className="doc-icon"><FileText size={16} /></div>
              <div className="doc-info">
                <div className="doc-type">{docTypeLabel[doc.document_type] ?? doc.document_type}</div>
                <div className="doc-meta">
                  {doc.document_number && <span>رقم: {doc.document_number} · </span>}
                  {doc.expiry_date && <span>ينتهي: {fmtDate(doc.expiry_date)}</span>}
                </div>
              </div>
              {doc.file_url && (
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={async () => {
                    try {
                      // SEC-03: Signed URL مؤقتة (60 دقيقة) بدلاً من Public URL مباشرة
                      const sb = supabase
                      // استخراج path من URL الكامل
                      const urlPath = doc.file_url!.split('/object/public/')[1] ?? doc.file_url!
                      // تجربة توليد signed URL
                      const { data, error } = await sb.storage
                        .from(urlPath.split('/')[0])
                        .createSignedUrl(urlPath.slice(urlPath.indexOf('/') + 1), 3600)
                      if (data?.signedUrl) {
                        window.open(data.signedUrl, '_blank', 'noopener,noreferrer')
                      } else {
                        // fallback لـ public URL إذا فشل (للـ buckets العامة)
                        window.open(doc.file_url!, '_blank', 'noopener,noreferrer')
                      }
                    } catch {
                      window.open(doc.file_url!, '_blank', 'noopener,noreferrer')
                    }
                  }}
                >
                  عرض
                </Button>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Upload Modal */}
      <ResponsiveModal
        open={uploadOpen}
        onClose={() => { setUploadOpen(false); resetForm() }}
        title="رفع وثيقة جديدة"
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => { setUploadOpen(false); resetForm() }} style={{ flex: 1 }}>إلغاء</Button>
            <Button
              onClick={handleUpload}
              loading={uploading}
              disabled={!file}
              style={{ flex: 2 }}
            >
              {uploading ? 'جارٍ الرفع...' : 'رفع الوثيقة'}
            </Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <Select
            label="نوع الوثيقة"
            required
            value={docType}
            onChange={e => setDocType(e.target.value as HRDocumentType)}
            options={Object.entries(docTypeLabel).map(([k, v]) => ({ value: k, label: v }))}
          />
          <Input label="رقم الوثيقة" value={docNumber} onChange={e => setDocNumber(e.target.value)} placeholder="اختياري" />
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
            <Input label="تاريخ الإصدار" type="date" value={issueDate}  onChange={e => setIssueDate(e.target.value)} />
            <Input label="تاريخ الانتهاء" type="date" value={expiryDate} onChange={e => setExpiryDate(e.target.value)} />
          </div>
          <Input label="ملاحظات" value={docNotes} onChange={e => setDocNotes(e.target.value)} />
          {/* File picker */}
          <div>
            <label style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', display: 'block', marginBottom: 4 }}>
              الملف <span style={{ color: 'var(--color-danger)' }}>*</span>
            </label>
            <input
              ref={fileRef}
              type="file"
              accept=".pdf,.jpg,.jpeg,.png,.webp"
              onChange={e => setFile(e.target.files?.[0] ?? null)}
              style={{
                width: '100%', padding: 'var(--space-2)', borderRadius: 'var(--radius-md)',
                border: '1px solid var(--border-color)', background: 'var(--bg-input)',
                color: 'var(--text-primary)', fontSize: 'var(--text-sm)',
                cursor: 'pointer',
              }}
            />
            {file && (
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--color-success)', marginTop: 4 }}>
                ✓ {file.name} ({(file.size / 1024).toFixed(0)} KB)
              </div>
            )}
          </div>
        </div>
      </ResponsiveModal>
    </div>
  )
}


// ═════════════════════════════════════════════
// TAB 3: LEAVES
// ═════════════════════════════════════════════

function LeavesTab({ employeeId }: { employeeId: string }) {
  const currentYear = new Date().getFullYear()
  const { data: balances = [], isLoading } = useHRLeaveBalances(employeeId, currentYear)

  // GAP-05: جلب سجل طلبات الإجازة للموظف
  const { data: leaveRequestsResult, isLoading: reqLoading } = useQuery({
    queryKey: ['hr-leave-requests-employee', employeeId],
    queryFn: () => import('@/lib/services/hr').then(m =>
      m.getLeaveRequests({ employeeId, pageSize: 20 })
    ),
  })
  const leaveRequests = leaveRequestsResult?.data ?? []

  const LEAVE_STATUS: Record<string, { label: string; variant: 'warning'|'success'|'danger'|'info'|'neutral' }> = {
    pending_supervisor: { label: 'بانتظار المشرف', variant: 'warning' },
    approved_supervisor: { label: 'موافقة مشرف', variant: 'info' },
    pending_hr: { label: 'بانتظار HR', variant: 'warning' },
    approved: { label: 'معتمد', variant: 'success' },
    rejected: { label: 'مرفوض', variant: 'danger' },
    cancelled: { label: 'ملغي', variant: 'neutral' },
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
      {/* ─ أرصدة الإجازات ─ */}
      <div>
        <div style={{ marginBottom: 'var(--space-3)', fontSize: 'var(--text-sm)', color: 'var(--text-muted)', fontWeight: 600 }}>
          أرصدة عام {currentYear}
        </div>
        {isLoading ? (
          <div style={{ padding: 'var(--space-4)', display: 'flex', justifyContent: 'center' }}><Spinner /></div>
        ) : balances.length === 0 ? (
          <div className="edara-card" style={{ padding: 'var(--space-6)', textAlign: 'center' }}>
            <Calendar size={28} style={{ display: 'block', margin: '0 auto var(--space-2)', opacity: 0.3 }} />
            <p style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)', margin: 0 }}>لم تُحدَّد أنواع إجازات لهذا الموظف</p>
          </div>
        ) : (
          <div className="leave-balance-grid">
            {balances.map(bal => <LeaveBalanceCard key={bal.id} balance={bal} />)}
          </div>
        )}
      </div>

      {/* ─ GAP-05: سجل طلبات الإجازة ─ */}
      <div className="edara-card" style={{ padding: 0, overflow: 'hidden' }}>
        <div style={{ padding: 'var(--space-3) var(--space-4)', fontWeight: 700, fontSize: 'var(--text-sm)', borderBottom: '1px solid var(--border-color)', color: 'var(--color-primary)' }}>
          سجل طلبات الإجازة
        </div>
        {reqLoading ? (
          <div style={{ padding: 'var(--space-4)', textAlign: 'center', color: 'var(--text-muted)' }}>جارِ التحميل...</div>
        ) : leaveRequests.length === 0 ? (
          <div style={{ padding: 'var(--space-6)', textAlign: 'center', color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>لا توجد طلبات سابقة</div>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <DataTable
              columns={[
                { key: 'type', label: 'نوع الإجازة', render: (r: any) => r.leave_type?.name ?? '—' },
                { key: 'start', label: 'من تاريخ', render: (r: any) => fmtDate(r.start_date) },
                { key: 'end', label: 'إلى تاريخ', render: (r: any) => fmtDate(r.end_date) },
                { key: 'days', label: 'الأيام', align: 'center', render: (r: any) => r.days_count.toString() },
                { key: 'status', label: 'الحالة', render: (r: any) => {
                  const st = LEAVE_STATUS[r.status] ?? { label: r.status, variant: 'neutral' }
                  return <Badge variant={st.variant}>{st.label}</Badge>
                } }
              ]}
              data={leaveRequests}
              keyField="id"
              dataCardMapping={(r: any) => ({
                title: r.leave_type?.name ?? '—',
                subtitle: `${fmtDate(r.start_date)} — ${fmtDate(r.end_date)}`,
                badge: <Badge variant={LEAVE_STATUS[r.status]?.variant ?? 'neutral'}>{LEAVE_STATUS[r.status]?.label ?? r.status}</Badge>,
                metadata: [{ label: 'المدة', value: `${r.days_count} يوم` }]
              })}
            />
          </div>
        )}
      </div>
    </div>
  )
}

function LeaveBalanceCard({ balance: b }: { balance: HRLeaveBalance }) {
  const usedRatio = b.total_days > 0 ? b.used_days / b.total_days : 0
  const color = b.remaining_days <= 0
    ? 'var(--color-danger)'
    : usedRatio > 0.7
    ? 'var(--color-warning)'
    : 'var(--color-primary)'

  return (
    <div className="leave-balance-card">
      <div className="leave-balance-name">{b.leave_type?.name ?? '—'}</div>
      <div className="leave-balance-remaining" style={{ color }}>{b.remaining_days}</div>
      <div className="leave-balance-unit">يوم متبقي</div>
      <div style={{ height: 4, borderRadius: 'var(--radius-full)', background: 'var(--bg-surface-2)', overflow: 'hidden' }}>
        <div style={{
          height: '100%',
          width: `${Math.min(100, usedRatio * 100)}%`,
          background: color,
          borderRadius: 'var(--radius-full)',
          transition: 'width 0.4s ease',
        }} />
      </div>
      <div className="leave-balance-row">
        <span>المستحق: {b.total_days}</span>
        <span>المستهلك: {b.used_days}</span>
      </div>
      {b.pending_days > 0 && (
        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--color-warning)' }}>
          في الانتظار: {b.pending_days} يوم
        </div>
      )}
    </div>
  )
}

// ═════════════════════════════════════════════
// TAB 4: LIVE STATEMENT — محمي بـ PermissionGuard في الأعلى
// ═════════════════════════════════════════════

function StatementTab({ employeeId }: { employeeId: string }) {
  const now = new Date()
  // UX-02: جعل الشهر/السنة قابلين للتغيير
  const [year,  setYear]  = useState(now.getFullYear())
  const [month, setMonth] = useState(now.getMonth() + 1)

  const MONTHS = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر']

  const { data: statement, isLoading, error } = useQuery({
    queryKey: ['hr-live-statement', employeeId, year, month],
    queryFn: () => getEmployeeLiveStatement(employeeId, year, month),
    staleTime: 60_000, // 1 دقيقة — البيانات تتغير مع الحضور
  })

  return (
    <div>
      {/* UX-02: سيلكتور الشهر والسنة */}
      <div style={{ display: 'flex', gap: 'var(--space-3)', marginBottom: 'var(--space-4)', alignItems: 'center', flexWrap: 'wrap' }}>
        <Select
          value={String(month)}
          onChange={e => setMonth(Number(e.target.value))}
          options={MONTHS.map((m, i) => ({ value: String(i + 1), label: m }))}
          style={{ minWidth: 130 }}
        />
        <Select
          value={String(year)}
          onChange={e => setYear(Number(e.target.value))}
          options={[now.getFullYear() - 1, now.getFullYear()].map(y => ({ value: String(y), label: String(y) }))}
          style={{ minWidth: 100 }}
        />
        <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>— كشف تقديري</span>
      </div>

      {isLoading ? (
        <div style={{ padding: 'var(--space-6)', display: 'flex', justifyContent: 'center' }}><Spinner /></div>
      ) : error || !statement ? (
        <div className="edara-card" style={{ padding: 'var(--space-6)', textAlign: 'center' }}>
          <AlertCircle size={32} style={{ color: 'var(--color-warning)', margin: '0 auto var(--space-3)' }} />
          <p style={{ color: 'var(--text-secondary)', fontSize: 'var(--text-sm)' }}>
            لا تتوفر بيانات لهذا الشهر
          </p>
        </div>
      ) : <StatementContent statement={statement as EmployeeLiveStatement} year={year} month={month} />}
    </div>
  )
}

function StatementContent({ statement, year, month }: { statement: EmployeeLiveStatement; year: number; month: number }) {
  const { earnings, attendance, advances, period, is_partial_month } = statement

  // حساب إجمالي أقساط السلف النشطة (تقديري)
  const totalAdvanceInstallments = advances.reduce(
    (sum, adv) => sum + (adv.monthly_installment ?? 0), 0
  )

  const monthLabel = period?.month_name
    ?? new Date(year, month - 1).toLocaleString('ar-EG', { month: 'long', year: 'numeric' })

  return (
    <div>
      <div style={{ marginBottom: 'var(--space-4)', fontSize: 'var(--text-sm)', color: 'var(--text-muted)' }}>
        كشف حساب — {monthLabel}
      </div>

      <div className="statement-grid">

        {/* ══ قسم المستحقات — يقرأ من statement.earnings ══ */}
        <div className="statement-section">
          <div className="statement-section-header statement-section-header--debit">
            <TrendingUp size={14} /> المستحقات
          </div>

          {earnings.base_salary > 0 && (
            <div className="statement-line">
              <span className="statement-line-label">الراتب الأساسي</span>
              <span className="statement-line-value" style={{ color: 'var(--color-success)' }}>
                + {formatNumber(earnings.base_salary)} ج.م
              </span>
            </div>
          )}
          {earnings.transport_allowance > 0 && (
            <div className="statement-line">
              <span className="statement-line-label">بدل المواصلات</span>
              <span className="statement-line-value" style={{ color: 'var(--color-success)' }}>
                + {formatNumber(earnings.transport_allowance)} ج.م
              </span>
            </div>
          )}
          {earnings.housing_allowance > 0 && (
            <div className="statement-line">
              <span className="statement-line-label">بدل السكن</span>
              <span className="statement-line-value" style={{ color: 'var(--color-success)' }}>
                + {formatNumber(earnings.housing_allowance)} ج.م
              </span>
            </div>
          )}
          {earnings.other_allowances > 0 && (
            <div className="statement-line">
              <span className="statement-line-label">بدلات أخرى</span>
              <span className="statement-line-value" style={{ color: 'var(--color-success)' }}>
                + {formatNumber(earnings.other_allowances)} ج.م
              </span>
            </div>
          )}
          {earnings.commission_amount > 0 && (
            <div className="statement-line">
              <span className="statement-line-label">عمولات محققة</span>
              <span className="statement-line-value" style={{ color: 'var(--color-success)' }}>
                + {formatNumber(earnings.commission_amount)} ج.م
              </span>
            </div>
          )}

          <div className="statement-line" style={{ fontWeight: 700 }}>
            <span>الإجمالي المستحق</span>
            <span style={{ color: 'var(--color-success)' }}>{formatNumber(earnings.gross_salary)} ج.م</span>
          </div>
        </div>

        {/* ══ مؤشرات الحضور والخصومات (تقديري) — يقرأ من statement.attendance ══ */}
        <div className="statement-section">
          <div className="statement-section-header" style={{
            background: 'color-mix(in srgb, var(--color-warning) 8%, transparent)',
            color: 'var(--color-warning)',
          }}>
            <Clock size={14} /> مؤشرات الحضور والخصومات (تقديري)
          </div>

          <div className="statement-line">
            <span className="statement-line-label">أيام العمل</span>
            <span className="statement-line-value">
              {attendance.present_days} / {attendance.working_days} يوم
            </span>
          </div>

          <div className="statement-line">
            <span className="statement-line-label">أيام الغياب غير المبرر</span>
            <span className="statement-line-value" style={{
              color: attendance.absent_unauthorized > 0 ? 'var(--color-danger)' : 'var(--text-primary)',
            }}>
              {attendance.absent_unauthorized} يوم
            </span>
          </div>

          <div className="statement-line">
            <span className="statement-line-label">إجمالي دقائق التأخير</span>
            <span className="statement-line-value" style={{
              color: attendance.total_late_minutes > 0 ? 'var(--color-warning)' : 'var(--text-primary)',
            }}>
              {attendance.total_late_minutes} دقيقة
            </span>
          </div>

          <div className="statement-line">
            <span className="statement-line-label">أيام الجزاءات (تقديري)</span>
            <span className="statement-line-value" style={{
              color: attendance.penalty_deduction_days > 0 ? 'var(--color-danger)' : 'var(--text-primary)',
            }}>
              {attendance.penalty_deduction_days} يوم
            </span>
          </div>

          {attendance.total_overtime_minutes > 0 && (
            <div className="statement-line">
              <span className="statement-line-label">دقائق الوقت الإضافي</span>
              <span className="statement-line-value" style={{ color: 'var(--color-success)' }}>
                {attendance.total_overtime_minutes} دقيقة
              </span>
            </div>
          )}

          <div className="statement-line" style={{
            fontSize: 'var(--text-xs)', color: 'var(--text-muted)',
            justifyContent: 'center', gap: 'var(--space-1)',
          }}>
            <AlertCircle size={11} />
            الخصومات المالية الموثقة تُحسب عند اعتماد المسير فقط
          </div>
        </div>
      </div>

      {/* ══ السلف النشطة — يقرأ من statement.advances ══ */}
      {advances.length > 0 && (
        <div style={{ marginTop: 'var(--space-4)' }}>
          <div className="statement-section">
            <div className="statement-section-header" style={{
              background: 'color-mix(in srgb, var(--color-primary) 6%, transparent)',
              color: 'var(--color-primary)',
            }}>
              <TrendingDown size={14} /> السلف النشطة والأقساط
            </div>

            {advances.map(adv => (
              <div key={adv.id} className="statement-line" style={{ flexDirection: 'column', alignItems: 'flex-start', gap: 'var(--space-1)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', width: '100%' }}>
                  <span className="statement-line-label">{adv.number ?? 'سلفة'} — {adv.reason}</span>
                  <span className="statement-line-value" style={{ color: 'var(--color-primary)' }}>
                    متبقي: {formatNumber(adv.remaining_amount)} ج.م
                  </span>
                </div>
                {adv.monthly_installment != null && adv.monthly_installment > 0 && (
                  <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    القسط الشهري: {formatNumber(adv.monthly_installment)} ج.م
                  </span>
                )}
              </div>
            ))}

            {totalAdvanceInstallments > 0 && (
              <div className="statement-line" style={{ fontWeight: 700 }}>
                <span>إجمالي الأقساط الشهرية</span>
                <span style={{ color: 'var(--color-primary)' }}>− {formatNumber(totalAdvanceInstallments)} ج.م</span>
              </div>
            )}
          </div>
        </div>
      )}

      {/* إشارة شهر جزئي */}
      {is_partial_month && (
        <div style={{
          marginTop: 'var(--space-3)',
          display: 'flex', alignItems: 'center', gap: 'var(--space-2)',
          fontSize: 'var(--text-xs)', color: 'var(--color-warning)',
          background: 'color-mix(in srgb, var(--color-warning) 8%, transparent)',
          padding: 'var(--space-2) var(--space-3)', borderRadius: 'var(--radius-md)',
        }}>
          <AlertCircle size={13} />
          <span>شهر جزئي — الموظف انضم أو غادر في منتصف الشهر</span>
        </div>
      )}
    </div>
  )
}

// ════════════════════════════════════════════
// CONTRACTS TAB — عقود وتاريخ الراتب (F-D: تعديل مباشر)

function ContractsTab({ employeeId }: { employeeId: string }) {
  const qc = useQueryClient()
  const can = useAuthStore(s => s.can)
  const [salaryModalOpen, setSalaryModalOpen] = useState(false)
  const [salaryForm, setSalaryForm] = useState({
    base_salary: '', transport_allowance: '', housing_allowance: '',
    other_allowances: '', reason: ''
  })
  const [saving, setSaving] = useState(false)

  const [contractModalOpen, setContractModalOpen] = useState(false)
  const [contractSaving, setContractSaving] = useState(false)
  const [contractForm, setContractForm] = useState<Partial<HRContractInput>>({
    contract_type: 'permanent',
    base_salary: 0,
    transport_allowance: 0,
    housing_allowance: 0,
    other_allowances: 0,
    start_date: new Date().toISOString().split('T')[0],
    end_date: ''
  })

  const { data: contracts = [], isLoading: cLoading } = useQuery({
    queryKey: ['hr-employee-contracts', employeeId],
    queryFn: () => getContracts(employeeId),
  })
  const { data: salaryHistory = [], refetch: refetchHistory } = useQuery({
    queryKey: ['hr-employee-salary-history', employeeId],
    queryFn: () => getEmployeeSalaryHistory(employeeId),
  })

  const CONTRACT_TYPE_LABEL: Record<HRContractType, string> = {
    permanent: 'دائم', fixed_term: 'محدد المدة', part_time: 'دوام جزئي',
    freelance: 'عمل حر', probation: 'تجريبي',
  }

  const handleSalaryUpdate = async () => {
    const base = parseFloat(salaryForm.base_salary)
    if (!base || base <= 0 || !salaryForm.reason.trim()) {
      toast.error('يرجى إدخال الراتب الأساسي وسبب التعديل')
      return
    }
    setSaving(true)
    try {
      await updateSalaryDirectly({
        employeeId,
        baseSalary:          base,
        transportAllowance:  salaryForm.transport_allowance ? parseFloat(salaryForm.transport_allowance) : undefined,
        housingAllowance:    salaryForm.housing_allowance   ? parseFloat(salaryForm.housing_allowance)   : undefined,
        otherAllowances:     salaryForm.other_allowances    ? parseFloat(salaryForm.other_allowances)    : undefined,
        reason: salaryForm.reason,
      })
      toast.success('تم تحديث الراتب بنجاح')
      setSalaryModalOpen(false)
      setSalaryForm({ base_salary: '', transport_allowance: '', housing_allowance: '', other_allowances: '', reason: '' })
      qc.invalidateQueries({ queryKey: ['hr-employee', employeeId] })
      refetchHistory()
    } catch (e: any) {
      toast.error(e.message ?? 'فشل تحديث الراتب')
    } finally {
      setSaving(false)
    }
  }

  const handleCreateContract = async () => {
    const bs = Number(contractForm.base_salary)
    const startDate = contractForm.start_date
    if (!bs || bs <= 0 || !startDate) {
      toast.error('يرجى التأكد من الراتب الأساسي وتاريخ البداية')
      return
    }
    setContractSaving(true)
    try {
      const payload: HRContractInput = {
        employee_id: employeeId,
        contract_type: contractForm.contract_type ?? 'permanent',
        start_date: startDate,
        end_date: contractForm.end_date || undefined,
        base_salary: bs,
        transport_allowance: contractForm.transport_allowance ? Number(contractForm.transport_allowance) : 0,
        housing_allowance: contractForm.housing_allowance ? Number(contractForm.housing_allowance) : 0,
        other_allowances: contractForm.other_allowances ? Number(contractForm.other_allowances) : 0,
      }
      // 1. إنشاء العقد (الـ Trigger الحديث بـ Backend سيتكفل بمزامنة الراتب والتاريخ)
      await createContract(payload)
      
      toast.success('تم إنشاء العقد وتحديث الراتب بنجاح')
      setContractModalOpen(false)
      setContractForm({ contract_type: 'permanent', base_salary: 0, transport_allowance: 0, housing_allowance: 0, other_allowances: 0, start_date: new Date().toISOString().split('T')[0], end_date: '' })
      qc.invalidateQueries({ queryKey: ['hr-employee-contracts', employeeId] })
      refetchHistory()
      qc.invalidateQueries({ queryKey: ['hr-employee', employeeId] })
    } catch (e: any) {
      toast.error(e.message ?? 'فشل إنشاء العقد')
    } finally {
      setContractSaving(false)
    }
  }

  return (
    <div>
      <div className="edara-card" style={{ marginBottom: 'var(--space-4)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-4)' }}>
          <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--color-primary)' }}>العقود</div>
          {can('hr.employees.edit') && (
            <Button size="sm" onClick={() => setContractModalOpen(true)}>إنشاء عقد</Button>
          )}
        </div>
        {cLoading ? (
          <div style={{ color: 'var(--text-muted)', textAlign: 'center', padding: 'var(--space-4)' }}>جارِ التحميل...</div>
        ) : contracts.length === 0 ? (
          <div style={{ color: 'var(--text-muted)', textAlign: 'center', padding: 'var(--space-4)' }}>لا توجد عقود مسجلة</div>
        ) : (
          <DataTable
            columns={[
              { key: 'type', label: 'نوع العقد', render: (c: any) => <Badge variant="info">{CONTRACT_TYPE_LABEL[c.contract_type as HRContractType]}</Badge> },
              { key: 'start', label: 'تاريخ البداية', render: (c: any) => new Date(c.start_date).toLocaleDateString('ar-EG') },
              { key: 'end', label: 'تاريخ النهاية', render: (c: any) => c.end_date ? new Date(c.end_date).toLocaleDateString('ar-EG') : 'مفتوح' },
              { key: 'salary', label: 'الراتب الأساسي', render: (c: any) => <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{formatNumber(c.base_salary)} ج.م</span> }
            ]}
            data={contracts}
            keyField="id"
            dataCardMapping={(c: any) => ({
              title: CONTRACT_TYPE_LABEL[c.contract_type as HRContractType],
              subtitle: `${new Date(c.start_date).toLocaleDateString('ar-EG')} — ${c.end_date ? new Date(c.end_date).toLocaleDateString('ar-EG') : 'مفتوح'}`,
              badge: <Badge variant="info">{CONTRACT_TYPE_LABEL[c.contract_type as HRContractType]}</Badge>,
              metadata: [{ label: 'الراتب', value: `${formatNumber(c.base_salary)} ج.م`, highlight: true }]
            })}
          />
        )}
      </div>

      <div className="edara-card">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-4)' }}>
          <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--color-primary)' }}>تاريخ الراتب</div>
          {can('hr.employees.edit') && (
            <Button size="sm" variant="secondary" onClick={() => setSalaryModalOpen(true)}>
              تعديل الراتب
            </Button>
          )}
        </div>
        {salaryHistory.length === 0 ? (
          <div style={{ color: 'var(--text-muted)', textAlign: 'center', padding: 'var(--space-4)' }}>لا يوجد تاريخ</div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            {salaryHistory.map(s => (
              <div key={s.id} style={{
                padding: 'var(--space-3)', borderRadius: 'var(--radius-md)',
                background: 'var(--bg-surface-2)', border: '1px solid var(--border-color)',
              }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 'var(--space-2)' }}>
                  <div>
                    <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)' }}>
                      {new Date(s.effective_date).toLocaleDateString('ar-EG', { month: 'long', year: 'numeric' })}
                    </span>
                    {s.change_reason && (
                      <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontStyle: 'italic', marginTop: 2 }}>{s.change_reason}</div>
                    )}
                  </div>
                  <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: 'var(--color-primary)' }}>{formatNumber(s.gross_salary)} ج.م</span>
                </div>
                {/* UX-06: تفاصيل البدلات */}
                <div style={{ display: 'flex', gap: 'var(--space-3)', flexWrap: 'wrap', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                  <span>أساسي: {formatNumber(s.base_salary)}</span>
                  {(s.transport_allowance ?? 0) > 0 && <span>مواصلات: {formatNumber(s.transport_allowance ?? 0)}</span>}
                  {(s.housing_allowance ?? 0) > 0  && <span>سكن: {formatNumber(s.housing_allowance ?? 0)}</span>}
                  {(s.other_allowances ?? 0) > 0   && <span>بدلات: {formatNumber(s.other_allowances ?? 0)}</span>}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Salary Update Modal */}
      <ResponsiveModal
        open={salaryModalOpen}
        onClose={() => setSalaryModalOpen(false)}
        title="تعديل الراتب المباشر"
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => setSalaryModalOpen(false)} style={{ flex: 1 }}>إلغاء</Button>
            <Button onClick={handleSalaryUpdate} loading={saving} disabled={!salaryForm.base_salary || !salaryForm.reason} style={{ flex: 2 }}>حفظ التعديل</Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <Input label="الراتب الأساسي" required type="number" value={salaryForm.base_salary}
            onChange={e => setSalaryForm(p => ({ ...p, base_salary: e.target.value }))} placeholder="0.00" />
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-2)' }}>
            <Input label="بدل المواصلات" type="number" value={salaryForm.transport_allowance}
              onChange={e => setSalaryForm(p => ({ ...p, transport_allowance: e.target.value }))} />
            <Input label="بدل السكن" type="number" value={salaryForm.housing_allowance}
              onChange={e => setSalaryForm(p => ({ ...p, housing_allowance: e.target.value }))} />
          </div>
          <Input label="بدلات أخرى" type="number" value={salaryForm.other_allowances}
            onChange={e => setSalaryForm(p => ({ ...p, other_allowances: e.target.value }))} />
          <Input label="سبب التعديل" required value={salaryForm.reason}
            onChange={e => setSalaryForm(p => ({ ...p, reason: e.target.value }))} placeholder="علاوة سنوية، ترقية..." />
        </div>
      </ResponsiveModal>

      {/* Contract Create Modal */}
      <ResponsiveModal
        open={contractModalOpen}
        onClose={() => setContractModalOpen(false)}
        title="إنشاء عقد جديد"
        size="md"
        disableOverlayClose={contractSaving}
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => setContractModalOpen(false)} style={{ flex: 1 }}>إلغاء</Button>
            <Button onClick={handleCreateContract} loading={contractSaving} disabled={!contractForm.base_salary || !contractForm.start_date} style={{ flex: 2 }}>إنشاء العقد وتوثيق الراتب</Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <Select label="نوع العقد" required value={contractForm.contract_type} onChange={e => setContractForm(p => ({ ...p, contract_type: e.target.value as HRContractType }))} options={Object.entries(CONTRACT_TYPE_LABEL).map(([k, v]) => ({ label: v, value: k }))} />
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-2)' }}>
            <Input label="تاريخ البداية" required type="date" value={String(contractForm.start_date)} onChange={e => setContractForm(p => ({ ...p, start_date: e.target.value }))} />
            <Input label="تاريخ النهاية" type="date" placeholder="مفتوح" value={contractForm.end_date || ''} onChange={e => setContractForm(p => ({ ...p, end_date: e.target.value }))} />
          </div>
          <hr style={{ borderColor: 'var(--border-color)', margin: 'var(--space-2) 0' }} />
          <Input label="الراتب الأساسي" required type="number" value={String(contractForm.base_salary || '')} onChange={e => setContractForm(p => ({ ...p, base_salary: Number(e.target.value) }))} placeholder="0.00" />
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-2)' }}>
            <Input label="بدل المواصلات" type="number" value={String(contractForm.transport_allowance || '')} onChange={e => setContractForm(p => ({ ...p, transport_allowance: Number(e.target.value) }))} />
            <Input label="بدل السكن" type="number" value={String(contractForm.housing_allowance || '')} onChange={e => setContractForm(p => ({ ...p, housing_allowance: Number(e.target.value) }))} />
          </div>
          <Input label="بدلات أخرى" type="number" value={String(contractForm.other_allowances || '')} onChange={e => setContractForm(p => ({ ...p, other_allowances: Number(e.target.value) }))} />
          
          <div style={{ 
            fontSize: 'var(--text-xs)', color: 'var(--text-muted)', 
            display: 'flex', gap: 'var(--space-2)', alignItems: 'center',
            background: 'var(--bg-surface-2)', padding: 'var(--space-2)', borderRadius: 'var(--radius-sm)'
          }}>
            <AlertCircle size={14} /> بناءً على هذه البيانات سيتم تحديث راتب الموظف الحالي تلقائيًا لتجنب التضارب.
          </div>
        </div>
      </ResponsiveModal>
    </div>
  )
}


// ════════════════════════════════════════════
// ADVANCES TAB — سجل السلف (F-C: تأجيل القسط)
// ════════════════════════════════════════════
function AdvancesTab({ employeeId }: { employeeId: string }) {
  const can = useAuthStore(s => s.can)
  const [expandedAdv, setExpandedAdv] = useState<string | null>(null)
  const [deferTarget, setDeferTarget] = useState<HRAdvanceInstallment | null>(null)
  const [deferReason, setDeferReason]   = useState('')
  const [deferMonth,  setDeferMonth]    = useState(new Date().getMonth() + 2 > 12 ? 1 : new Date().getMonth() + 2)
  const [deferYear,   setDeferYear]     = useState(new Date().getMonth() + 2 > 12 ? new Date().getFullYear() + 1 : new Date().getFullYear())
  const [deferLoading, setDeferLoading] = useState(false)

  const { data: advancesResult, isLoading } = useQuery({
    queryKey: ['hr-advances-employee', employeeId],
    queryFn: () => getAdvances({ employeeId }),
  })

  const advances = advancesResult?.data ?? []

  const { data: installments = [], refetch: refetchInst } = useQuery({
    queryKey: ['hr-advance-installments', expandedAdv],
    queryFn:  () => expandedAdv ? getAdvanceInstallments(expandedAdv) : Promise.resolve([]),
    enabled:  !!expandedAdv,
  })

  const ADV_STATUS: Record<string, string> = {
    pending: 'قيد المراجعة', approved: 'مُعتمد', rejected: 'مرفوض',
    disbursed: 'مصروف', fully_deducted: 'مكتمل', cancelled: 'ملغي',
  }
  const ADV_VARIANT: Record<string, 'warning'|'success'|'danger'|'info'|'neutral'> = {
    pending: 'warning', approved: 'info', rejected: 'danger',
    disbursed: 'info', fully_deducted: 'success', cancelled: 'neutral',
  }
  const INST_STATUS: Record<string, string> = {
    pending: 'قادم', deducted: 'مخصوم', deferred: 'مؤجل', cancelled: 'ملغي',
  }
  const INST_VARIANT: Record<string, 'warning'|'success'|'neutral'|'info'> = {
    pending: 'warning', deducted: 'success', deferred: 'info', cancelled: 'neutral',
  }
  const ARB_MONTHS = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر']

  const totalRemaining = advances
    .filter(a => ['disbursed', 'approved'].includes(a.status))
    .reduce((s, a) => s + (a.remaining_amount ?? 0), 0)

  const handleDefer = async () => {
    if (!deferTarget || !deferReason.trim()) return
    setDeferLoading(true)
    try {
      await deferInstallment(deferTarget.id, deferReason, deferMonth, deferYear)
      toast.success('تم تأجيل القسط')
      setDeferTarget(null)
      setDeferReason('')
      refetchInst()
    } catch (e: any) {
      toast.error(e.message ?? 'فشل التأجيل')
    } finally {
      setDeferLoading(false)
    }
  }

  return (
    <div>
      {totalRemaining > 0 && (
        <div style={{
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          padding: 'var(--space-3) var(--space-4)', marginBottom: 'var(--space-4)',
          background: 'color-mix(in srgb, var(--color-warning) 8%, transparent)',
          borderRadius: 'var(--radius-md)', border: '1px solid color-mix(in srgb, var(--color-warning) 25%, transparent)',
          fontSize: 'var(--text-sm)',
        }}>
          <span>إجمالي المديونية الحالية</span>
          <strong style={{ color: 'var(--color-warning)', fontVariantNumeric: 'tabular-nums' }}>{formatNumber(totalRemaining)} ج.م</strong>
        </div>
      )}

      <div className="edara-card" style={{ padding: 0, overflow: 'hidden' }}>
        {isLoading ? (
          <div style={{ textAlign: 'center', padding: 'var(--space-6)', color: 'var(--text-muted)' }}>جارِ التحميل...</div>
        ) : advances.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 'var(--space-6)', color: 'var(--text-muted)' }}>لا توجد سلف</div>
        ) : (
          <>
            <DataTable
              columns={[
                { key: 'num', label: 'رقم السلفة', render: (a: any) => <div><div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{a.number}</div><div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{new Date(a.created_at).toLocaleDateString('ar-EG')}</div></div> },
                { key: 'amount', label: 'المبلغ', render: (a: any) => <span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatNumber(a.amount)}</span> },
                { key: 'rem', label: 'المتبقي', render: (a: any) => <span style={{ fontVariantNumeric: 'tabular-nums', color: (a.remaining_amount ?? 0) > 0 ? 'var(--color-warning)' : 'var(--color-success)' }}>{formatNumber(a.remaining_amount ?? 0)}</span> },
                { key: 'inst', label: 'القسط/شهر', render: (a: any) => <span style={{ fontVariantNumeric: 'tabular-nums' }}>{a.monthly_installment ? formatNumber(a.monthly_installment) : '—'}</span> },
                { key: 'status', label: 'الحالة', render: (a: any) => <Badge variant={ADV_VARIANT[a.status] ?? 'neutral'}>{ADV_STATUS[a.status] ?? a.status}</Badge> },
                { key: 'actions', label: '', align: 'end', render: (a: any) => ['approved', 'disbursed'].includes(a.status) ? <Button size="sm" variant="ghost" onClick={() => setExpandedAdv(a.id)}>الأقساط</Button> : null }
              ]}
              data={advances}
              keyField="id"
              dataCardMapping={(a: any) => ({
                title: `سلفة ${a.number}`,
                subtitle: new Date(a.created_at).toLocaleDateString('ar-EG'),
                badge: <Badge variant={ADV_VARIANT[a.status] ?? 'neutral'}>{ADV_STATUS[a.status] ?? a.status}</Badge>,
                metadata: [
                  { label: 'المبلغ', value: formatNumber(a.amount) },
                  { label: 'المتبقي', value: formatNumber(a.remaining_amount ?? 0), highlight: (a.remaining_amount ?? 0) > 0 }
                ],
                actions: ['approved', 'disbursed'].includes(a.status) ? <Button size="sm" variant="secondary" onClick={() => setExpandedAdv(a.id)} style={{ width: '100%', justifyContent: 'center' }}>تفاصيل الأقساط</Button> : undefined
              })}
            />

            <ResponsiveModal
              open={!!expandedAdv}
              onClose={() => setExpandedAdv(null)}
              title="جدول الأقساط"
            >
              <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
                {installments.length === 0 ? (
                  <div style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-4)' }}>لا توجد أقساط متاحة</div>
                ) : installments.map((inst: any) => (
                  <div key={inst.id} style={{
                    display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                    padding: 'var(--space-2) var(--space-3)', borderRadius: 'var(--radius-sm)',
                    background: 'var(--bg-surface-2)', border: '1px solid var(--border-color)',
                    fontSize: 'var(--text-sm)',
                  }}>
                    <div>
                      <div style={{ fontWeight: 600 }}>قسط {inst.installment_number}</div>
                      <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{ARB_MONTHS[inst.due_month - 1]} {inst.due_year}</div>
                      {inst.status === 'deferred' && inst.deferred_reason && (
                        <div style={{ color: 'var(--color-info)', fontSize: 10 }}>{inst.deferred_reason}</div>
                      )}
                    </div>
                    <div style={{ textAlign: 'left' }}>
                      <div style={{ fontVariantNumeric: 'tabular-nums', fontWeight: 700, marginBottom: 4 }}>{formatNumber(inst.amount)} ج.م</div>
                      <div style={{ transform: 'scale(0.85)', transformOrigin: 'left center' }}>
                        <Badge variant={INST_VARIANT[inst.status] ?? 'neutral'}>{INST_STATUS[inst.status] ?? inst.status}</Badge>
                      </div>
                      {inst.status === 'pending' && can('hr.advances.approve') && (
                        <Button size="sm" variant="ghost" style={{ marginTop: 4, display: 'block', fontSize: 11 }} onClick={() => {
                          setDeferTarget(inst); setDeferReason(''); setExpandedAdv(null);
                        }}>تأجيل</Button>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            </ResponsiveModal>
          </>
        )}
      </div>

      {/* Defer Modal */}
      <ResponsiveModal
        open={!!deferTarget}
        onClose={() => setDeferTarget(null)}
        title="تأجيل قسط"
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => setDeferTarget(null)} style={{ flex: 1 }}>إلغاء</Button>
            <Button onClick={handleDefer} loading={deferLoading} disabled={!deferReason.trim()} style={{ flex: 2 }}>تأكيد التأجيل</Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <div style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)' }}>
            تأجيل القسط رقم {deferTarget?.installment_number} ، المبلغ: {formatNumber(deferTarget?.amount ?? 0)} ج.م
          </div>
          <Input label="سبب التأجيل" required value={deferReason} onChange={e => setDeferReason(e.target.value)} placeholder="إجازة بدون راتب، قرار إداري..." />
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-2)' }}>
            <Select label="شهر إعادة الجدولة" value={String(deferMonth)} onChange={e => setDeferMonth(Number(e.target.value))}
              options={ARB_MONTHS.map((m, i) => ({ value: String(i + 1), label: m }))} />
            <Select label="السنة" value={String(deferYear)} onChange={e => setDeferYear(Number(e.target.value))}
              options={[0, 1].map(d => ({ value: String(new Date().getFullYear() + d), label: String(new Date().getFullYear() + d) }))} />
          </div>
        </div>
      </ResponsiveModal>
    </div>
  )
}



// ════════════════════════════════════════════
// ATTENDANCE CALENDAR TAB
// ════════════════════════════════════════════
function AttendanceCalendarTab({ employeeId }: { employeeId: string }) {
  const today = new Date()
  const [selYear,  setSelYear]  = useState(today.getFullYear())
  const [selMonth, setSelMonth] = useState(today.getMonth() + 1)

  const daysInMonth = new Date(selYear, selMonth, 0).getDate()
  const dateFrom = `${selYear}-${String(selMonth).padStart(2, '0')}-01`
  const dateTo   = `${selYear}-${String(selMonth).padStart(2, '0')}-${String(daysInMonth).padStart(2, '0')}`

  const { data: result } = useQuery({
    queryKey: ['hr-attendance-calendar', employeeId, selYear, selMonth],
    queryFn: () => getAttendanceDays({ employeeId, dateFrom, dateTo, pageSize: 31 }),
  })

  const days = result?.data ?? []
  const statusMap = new Map(days.map(d => [d.shift_date, d] as const))

  const STATUS_COLOR: Record<string, { bg: string; text: string }> = {
    present:             { bg: 'color-mix(in srgb, var(--color-success) 15%, transparent)', text: 'var(--color-success)' },
    late:                { bg: 'color-mix(in srgb, var(--color-warning) 15%, transparent)', text: 'var(--color-warning)' },
    half_day:            { bg: 'color-mix(in srgb, var(--color-info)    15%, transparent)', text: 'var(--color-info)' },
    absent_unauthorized: { bg: 'color-mix(in srgb, var(--color-danger)  15%, transparent)', text: 'var(--color-danger)' },
    absent_authorized:   { bg: 'color-mix(in srgb, var(--color-warning) 10%, transparent)', text: 'var(--color-warning)' },
    on_leave:            { bg: 'color-mix(in srgb, var(--color-info)    10%, transparent)', text: 'var(--color-info)' },
    weekly_off:          { bg: 'var(--bg-surface-2)', text: 'var(--text-muted)' },
    public_holiday:      { bg: 'var(--bg-surface-2)', text: 'var(--text-muted)' },
  }

  const STATUS_LABEL2: Record<string, string> = {
    present: 'حضور', late: 'تأخير', half_day: 'نصف', absent_unauthorized: 'غياب',
    absent_authorized: 'غياب م', on_leave: 'إجازة', weekly_off: 'عطلة', public_holiday: 'رسمي',
  }

  const MONTHS = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر']

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-3)', marginBottom: 'var(--space-4)' }}>
        <Select value={String(selMonth)} onChange={e => setSelMonth(Number(e.target.value))}
          options={MONTHS.map((m, i) => ({ value: String(i + 1), label: m }))} style={{ minWidth: 130 }} />
        <Select value={String(selYear)} onChange={e => setSelYear(Number(e.target.value))}
          options={[today.getFullYear()-1, today.getFullYear()].map(y => ({ value: String(y), label: String(y) }))} style={{ minWidth: 100 }} />
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 4 }}>
        {['أحد','اثنين','ثلاث','أربع','خميس','جمعة','سبت'].map(d => (
          <div key={d} style={{ textAlign: 'center', fontSize: 10, color: 'var(--text-muted)', padding: '4px 0', fontWeight: 700 }}>{d}</div>
        ))}

        {Array.from({ length: new Date(selYear, selMonth - 1, 1).getDay() }).map((_, i) => (
          <div key={`empty-${i}`} />
        ))}

        {Array.from({ length: daysInMonth }, (_, i) => i + 1).map(day => {
          const dateKey = `${selYear}-${String(selMonth).padStart(2, '0')}-${String(day).padStart(2, '0')}`
          const record  = statusMap.get(dateKey)
          const colors  = record ? STATUS_COLOR[record.status] : null
          // F-I: تمييز سجلات needs_review بحدود برتقالي
          const needsReview = record?.review_status === 'needs_review'

          return (
            <div key={day} title={record ? `${STATUS_LABEL2[record.status]}${needsReview ? ' — تحتاج مراجعة' : ''}` : undefined} style={{
              padding: '6px 4px', borderRadius: 'var(--radius-sm)',
              background: colors?.bg ?? 'transparent',
              border: needsReview
                ? '2px solid var(--color-warning)'
                : '1px solid var(--border-color)',
              textAlign: 'center', minHeight: 48,
              position: 'relative',
            }}>
              <div style={{ fontSize: 12, fontWeight: 600, color: colors?.text ?? 'var(--text-secondary)' }}>{day}</div>
              {record && <div style={{ fontSize: 9, color: colors?.text ?? 'var(--text-muted)', marginTop: 2 }}>{STATUS_LABEL2[record.status]}</div>}
              {record?.late_minutes && record.late_minutes > 0 && <div style={{ fontSize: 8, color: 'var(--color-warning)' }}>{record.late_minutes}د</div>}
              {needsReview && (
                <div style={{
                  position: 'absolute', top: 2, left: 2,
                  width: 6, height: 6, borderRadius: '50%',
                  background: 'var(--color-warning)',
                }} />
              )}
            </div>
          )
        })}
      </div>

      <div style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap', marginTop: 'var(--space-4)', fontSize: 'var(--text-xs)' }}>
        {['present','late','half_day','absent_unauthorized','on_leave','weekly_off'].map(key => (
          <span key={key} style={{
            display: 'inline-flex', alignItems: 'center', gap: 4, padding: '2px 8px', borderRadius: 999,
            background: STATUS_COLOR[key]?.bg, color: STATUS_COLOR[key]?.text,
            border: '1px solid color-mix(in srgb, currentColor 30%, transparent)',
          }}>
            {STATUS_LABEL2[key]}
          </span>
        ))}
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 4, padding: '2px 8px', borderRadius: 999,
          background: 'color-mix(in srgb, var(--color-warning) 10%, transparent)', color: 'var(--color-warning)',
          border: '2px solid var(--color-warning)',
        }}>
          ● تحتاج مراجعة
        </span>
      </div>
    </div>
  )
}


// ════════════════════════════════════════════
// TARGETS TAB — أهداف المندوب
// ════════════════════════════════════════════
function TargetsTab({ employeeId }: { employeeId: string }) {
  const { data: targets = [], isLoading: tLoading } = useQuery({
    queryKey: ['hr-commission-targets-employee', employeeId],
    queryFn: () => getCommissionTargets({ employeeId }),
  })
  const { data: records = [], isLoading: rLoading } = useQuery({
    queryKey: ['hr-commission-records-employee', employeeId],
    queryFn: () => getCommissionRecords({ employeeId }),
  })

  const totalCommission = records.reduce((s, r) => s + r.commission_amount, 0)

  return (
    <div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)', marginBottom: 'var(--space-4)' }}>
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 4 }}>إجمالي العمولات</div>
          <div style={{ fontSize: 'var(--text-xl)', fontWeight: 800, color: 'var(--color-success)' }}>{formatNumber(totalCommission)} ج.م</div>
        </div>
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 4 }}>فترات الأهداف</div>
          <div style={{ fontSize: 'var(--text-xl)', fontWeight: 800 }}>{targets.length}</div>
        </div>
      </div>

      <div className="edara-card" style={{ marginBottom: 'var(--space-4)' }}>
        <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', marginBottom: 'var(--space-3)', color: 'var(--color-primary)' }}>الأهداف الشهرية</div>
        {tLoading ? <div style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-4)' }}>جارٍ التحميل...</div>
        : targets.length === 0 ? <div style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-4)' }}>لا توجد أهداف محددة</div>
        : targets.map(t => (
          <div key={t.id} style={{
            display: 'flex', justifyContent: 'space-between', alignItems: 'center',
            padding: 'var(--space-3)', marginBottom: 'var(--space-2)',
            borderRadius: 'var(--radius-md)', border: '1px solid var(--border-color)',
            background: 'var(--bg-surface-2)',
          }}>
            <div>
              <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{t.period?.name ?? '—'}</div>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>نسبة العمولة: {t.commission_rate}%</div>
            </div>
            <div style={{ textAlign: 'end' }}>
              <div style={{ fontWeight: 700 }}>{formatNumber(t.target_amount)} ج.م</div>
            </div>
          </div>
        ))}
      </div>

      <div className="edara-card">
        <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', marginBottom: 'var(--space-3)', color: 'var(--color-primary)' }}>آخر العمولات</div>
        {rLoading ? <div style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-4)' }}>جارٍ التحميل...</div>
        : records.length === 0 ? <div style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-4)' }}>لا توجد سجلات</div>
        : records.slice(0, 10).map(r => (
          <div key={r.id} style={{
            display: 'flex', justifyContent: 'space-between', alignItems: 'center',
            padding: 'var(--space-2) var(--space-3)', borderBottom: '1px solid var(--border-color)',
            fontSize: 'var(--text-sm)',
          }}>
            <span style={{ color: 'var(--text-muted)' }}>{r.period?.name ?? '—'}</span>
            <span style={{ fontWeight: 700, color: 'var(--color-success)' }}>{formatNumber(r.commission_amount)} ج.م</span>
          </div>
        ))}
      </div>
    </div>
  )
}

// ════════════════════════════════════════════
// PENALTIES TAB — جزاءات الموظف
// ════════════════════════════════════════════
function PenaltiesTab({ employeeId }: { employeeId: string }) {
  const qc = useQueryClient()
  const can = useAuthStore(s => s.can)
  const [overrideId, setOverrideId] = useState<string | null>(null)
  const [overrideReason, setOverrideReason] = useState('')
  const [overrideLoading, setOverrideLoading] = useState(false)

  const { data: penalties = [], isLoading, refetch } = useQuery({
    queryKey: ['hr-penalties-employee', employeeId],
    queryFn: () => getPenaltyInstances({ employeeId }),
  })

  const handleOverride = async () => {
    if (!overrideId || !overrideReason.trim()) return
    setOverrideLoading(true)
    try {
      await overridePenalty(overrideId, overrideReason)
      toast.success('تم الإعفاء من الجزاء')
      setOverrideId(null)
      setOverrideReason('')
      refetch()
    } catch (e: any) {
      toast.error(e.message ?? 'فشل الإعفاء')
    } finally {
      setOverrideLoading(false)
    }
  }

  const totalDeductionDays = penalties
    .filter(p => !p.is_overridden)
    .reduce((s, p) => s + p.deduction_days, 0)

  return (
    <div>
      {totalDeductionDays > 0 && (
        <div style={{
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          padding: 'var(--space-3) var(--space-4)', marginBottom: 'var(--space-4)',
          background: 'color-mix(in srgb, var(--color-danger) 8%, transparent)',
          borderRadius: 'var(--radius-md)', border: '1px solid color-mix(in srgb, var(--color-danger) 25%, transparent)',
          fontSize: 'var(--text-sm)',
        }}>
          <span>إجمالي أيام الخصم المفعّلة</span>
          <strong style={{ color: 'var(--color-danger)' }}>{totalDeductionDays.toFixed(2)} يوم</strong>
        </div>
      )}

      <div className="edara-card" style={{ padding: 0, overflow: 'hidden' }}>
        {isLoading ? (
          <div style={{ textAlign: 'center', padding: 'var(--space-6)', color: 'var(--text-muted)' }}>جارٍ التحميل...</div>
        ) : penalties.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 'var(--space-6)', color: 'var(--text-muted)' }}>
            <AlertCircle size={28} style={{ display: 'block', margin: '0 auto var(--space-2)', opacity: 0.3 }} />
            لا توجد جزاءات مسجلة
          </div>
        ) : (
          <DataTable
            columns={[
              { key: 'rule', label: 'القاعدة / التاريخ', render: (p: any) => <div><div style={{ fontWeight: 600 }}>{p.penalty_rule?.name ?? '—'}</div><div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{p.attendance_day_id ? `مرتبط بيوم حضور` : `تاريخ التسجيل: ${new Date(p.created_at).toLocaleDateString('ar-EG')}`}</div></div> },
              { key: 'date', label: 'التاريخ', render: (p: any) => new Date(p.created_at).toLocaleDateString('ar-EG') },
              { key: 'ded', label: 'الخصم', render: (p: any) => <span style={{ fontVariantNumeric: 'tabular-nums', color: p.is_overridden ? 'var(--text-muted)' : 'var(--color-danger)', textDecoration: p.is_overridden ? 'line-through' : 'none' }}>{p.deduction_days.toFixed(2)} يوم</span> },
              { key: 'status', label: 'الحالة', render: (p: any) => p.is_overridden ? <Badge variant="success">مُعفى</Badge> : <Badge variant="danger">مفعّل</Badge> },
              { key: 'actions', label: '', align: 'end', render: (p: any) => (!p.is_overridden && can('hr.employees.edit')) ? <Button size="sm" variant="ghost" onClick={() => { setOverrideId(p.id); setOverrideReason('') }}>إعفاء</Button> : null }
            ]}
            data={penalties}
            keyField="id"
            rowStyle={(p: any) => ({ opacity: p.is_overridden ? 0.6 : 1 })}
            dataCardMapping={(p: any) => ({
              title: p.penalty_rule?.name ?? 'جزاء مخصص',
              subtitle: new Date(p.created_at).toLocaleDateString('ar-EG'),
              badge: p.is_overridden ? <Badge variant="success">مُعفى</Badge> : <Badge variant="danger">مفعّل</Badge>,
              metadata: [{ label: 'الخصم', value: `${p.deduction_days.toFixed(2)} يوم`, highlight: !p.is_overridden }],
              actions: (!p.is_overridden && can('hr.employees.edit')) ? <Button size="sm" variant="secondary" onClick={() => { setOverrideId(p.id); setOverrideReason('') }} style={{ width: '100%', justifyContent: 'center' }}>إعفاء من الجزاء</Button> : undefined
            })}
          />
        )}
      </div>

      {/* Override Modal */}
      <ResponsiveModal
        open={!!overrideId}
        onClose={() => { setOverrideId(null); setOverrideReason('') }}
        title="إعفاء من الجزاء"
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => setOverrideId(null)} style={{ flex: 1 }}>إلغاء</Button>
            <Button
              onClick={handleOverride}
              loading={overrideLoading}
              disabled={!overrideReason.trim()}
              style={{ flex: 2 }}
            >
              تأكيد الإعفاء
            </Button>
          </div>
        }
      >
        <div>
          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)', marginBottom: 'var(--space-3)' }}>
            يرجى ذكر سبب الإعفاء. سيُحفظ لأغراض التدقيق.
          </p>
          <Input
            label="سبب الإعفاء"
            required
            value={overrideReason}
            onChange={e => setOverrideReason(e.target.value)}
            placeholder="مثال: خطأ في تسجيل الحضور، عذر مقبول..."
          />
        </div>
      </ResponsiveModal>
    </div>
  )
}

// ════════════════════════════════════════════
// DELEGATIONS TAB — تفويضات الموظف
// F-A: permissions[] مصفوفة | F-B: delegate_id الصحيح | F-J: scope_type
// ════════════════════════════════════════════
function DelegationsTab({ employee }: { employee: HREmployee }) {
  const qc = useQueryClient()
  const can = useAuthStore(s => s.can)
  const [createOpen, setCreateOpen] = useState(false)

  type DelegForm = {
    delegate_id: string
    permissions: string[]
    valid_from: string
    valid_until: string
    scope_type: HRDelegationScopeType
    reason: string
  }
  const [form, setForm] = useState<DelegForm>({
    delegate_id: '', permissions: [], valid_from: '', valid_until: '', scope_type: 'all', reason: '',
  })
  const [creating, setCreating] = useState(false)

  // GAP-04: استخدام AsyncCombobox لاختيار الموظف بدلاً من UUID خام
  const loadDelegates = useCallback(async (search: string): Promise<ComboboxOption[]> => {
    const { data } = await getEmployees({ page: 1, pageSize: 30 })
    return (data ?? [])
      .filter(e => e.id !== employee.id) // لا يفوِّض لنفسه
      .filter(e =>
        !search ||
        e.full_name.includes(search) ||
        (e.employee_number ?? '').includes(search)
      )
      .map(e => ({ value: e.id, label: `${e.full_name} (${e.employee_number ?? ''})` }))
  }, [employee.id])

  const { data: myDelegations = [], isLoading, refetch } = useQuery({
    queryKey: ['hr-delegations-tab', employee.id],
    queryFn: () => getDelegations({ delegatorId: employee.id }),
  })

  const { data: delegatedToMe = [] } = useQuery({
    queryKey: ['hr-delegations-to-tab', employee.id],
    queryFn: () => getDelegations({ delegateId: employee.id, activeOnly: true }),
  })

  const DELEGATABLE = [
    { value: 'hr.leaves.approve',      label: 'اعتماد الإجازات' },
    { value: 'hr.advances.approve',    label: 'اعتماد السلف' },
    { value: 'hr.attendance.approve',  label: 'اعتماد الحضور' },
    { value: 'hr.permissions.approve', label: 'اعتماد الأذونات' },
  ]

  const permLabel = (perms: string[]) =>
    perms.map(p => DELEGATABLE.find(x => x.value === p)?.label ?? p).join('، ')

  const fmtD = (d: string) => new Date(d).toLocaleDateString('ar-EG', { day: 'numeric', month: 'short', year: 'numeric' })
  const now = new Date().toISOString()

  const togglePermission = (perm: string) => {
    setForm(p => ({
      ...p,
      permissions: p.permissions.includes(perm)
        ? p.permissions.filter(x => x !== perm)
        : [...p.permissions, perm],
    }))
  }

  const handleCreate = async () => {
    if (!form.delegate_id || form.permissions.length === 0 || !form.valid_from || !form.valid_until) {
      toast.error('يرجى تعبئة الحقول المطلوبة واختيار صلاحية واحدة على الأقل')
      return
    }
    if (form.valid_until <= form.valid_from) {
      toast.error('تاريخ الانتهاء يجب أن يكون بعد تاريخ البداية')
      return
    }
    setCreating(true)
    try {
      await createDelegation({
        delegator_id: employee.id,
        delegate_id:  form.delegate_id,
        permissions:  form.permissions,
        scope_type:   form.scope_type,
        valid_from:   form.valid_from,
        valid_until:  form.valid_until,
        reason:       form.reason || null,
      })
      toast.success('تم إنشاء التفويض')
      setCreateOpen(false)
      setForm({ delegate_id: '', permissions: [], valid_from: '', valid_until: '', scope_type: 'all', reason: '' })
      qc.invalidateQueries({ queryKey: ['hr-delegations-tab', employee.id] })
      refetch()
    } catch (e: any) {
      toast.error(e.message ?? 'فشل إنشاء التفويض')
    } finally {
      setCreating(false)
    }
  }

  const handleCancel = async (id: string) => {
    try {
      await cancelDelegation(id)
      toast.success('تم إلغاء التفويض')
      qc.invalidateQueries({ queryKey: ['hr-delegations-tab', employee.id] })
    } catch (e: any) {
      toast.error(e.message ?? 'فشل الإلغاء')
    }
  }

  return (
    <div>
      {/* تفويضاتي */}
      <div className="edara-card" style={{ marginBottom: 'var(--space-4)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-4)' }}>
          <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--color-primary)' }}>التفويضات التي أعطيتها</div>
          {can('hr.employees.read') && (
            <Button size="sm" icon={<Shield size={13} />} onClick={() => setCreateOpen(true)}>تفويض جديد</Button>
          )}
        </div>

        {isLoading ? (
          <div style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-4)', fontSize: 'var(--text-sm)' }}>جارٍ التحميل...</div>
        ) : myDelegations.length === 0 ? (
          <div style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-4)', fontSize: 'var(--text-sm)' }}>لا توجد تفويضات</div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            {myDelegations.map(d => {
              const isActive = d.is_active && d.valid_from <= now && d.valid_until >= now
              return (
                <div key={d.id} style={{
                  display: 'flex', alignItems: 'flex-start', gap: 'var(--space-2)',
                  padding: 'var(--space-2) var(--space-3)', borderRadius: 'var(--radius-md)',
                  // DSN-05: تمييز بصري واضح للتفويضات المنتهية
                  background: isActive
                    ? 'color-mix(in srgb, var(--color-success) 6%, var(--bg-surface-2))'
                    : 'color-mix(in srgb, var(--text-muted) 4%, var(--bg-surface-2))',
                  border: isActive
                    ? '1px solid color-mix(in srgb, var(--color-success) 20%, transparent)'
                    : '1px solid var(--border-color)',
                  opacity: isActive ? 1 : 0.65,
                  fontSize: 'var(--text-sm)',
                }}>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontWeight: 600, color: isActive ? 'inherit' : 'var(--text-muted)' }}>{d.delegate?.full_name ?? '—'}</div>
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                      {permLabel(d.permissions)}
                    </div>
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                      {fmtD(d.valid_from)} — {fmtD(d.valid_until)}
                      {d.scope_type !== 'all' && ` · نطاق: ${d.scope_type === 'branch' ? 'فرع' : 'فريق'}`}
                    </div>
                  </div>
                  <Badge variant={isActive ? 'success' : 'neutral'}>{isActive ? 'نشط' : 'منتهٍ'}</Badge>
                  {d.is_active && (
                    <Button size="sm" variant="ghost" onClick={() => handleCancel(d.id)}>إلغاء</Button>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </div>

      {/* ممنوحة لي */}
      {delegatedToMe.length > 0 && (
        <div className="edara-card">
          <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', marginBottom: 'var(--space-3)', color: 'var(--color-warning)' }}>التفويضات الممنوحة لي</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            {delegatedToMe.map(d => (
              <div key={d.id} style={{
                display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                padding: 'var(--space-2) var(--space-3)', borderRadius: 'var(--radius-md)',
                background: 'color-mix(in srgb, var(--color-warning) 5%, var(--bg-surface-2))',
                border: '1px solid color-mix(in srgb, var(--color-warning) 20%, transparent)',
                fontSize: 'var(--text-sm)',
              }}>
                <div>
                  <div style={{ fontWeight: 600 }}>من: {d.delegator?.full_name ?? '—'}</div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    {permLabel(d.permissions)} · حتى {fmtD(d.valid_until)}
                  </div>
                </div>
                <Badge variant="warning">نشط</Badge>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Create Modal */}
      <ResponsiveModal
        open={createOpen}
        onClose={() => setCreateOpen(false)}
        title="تفويض جديد"
        size="sm"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => setCreateOpen(false)} style={{ flex: 1 }}>إلغاء</Button>
            <Button onClick={handleCreate} loading={creating} disabled={form.permissions.length === 0} style={{ flex: 2 }}>حفظ</Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <AsyncCombobox
            label="الموظف المُفوَّض إليه"
            required
            placeholder="ابحث باسم الموظف أو رقمه..."
            value={form.delegate_id || null}
            onChange={val => setForm(p => ({ ...p, delegate_id: val ?? '' }))}
            loadOptions={loadDelegates}
          />

          <div>
            <label style={{ fontSize: 'var(--text-xs)', fontWeight: 600, color: 'var(--text-muted)', display: 'block', marginBottom: 'var(--space-2)' }}>
              الصلاحيات المُفوَّضة <span style={{ color: 'var(--color-danger)' }}>*</span>
            </label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
              {DELEGATABLE.map(opt => (
                <label key={opt.value} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 'var(--text-sm)', cursor: 'pointer', padding: 'var(--space-1)' }}>
                  <input
                    type="checkbox"
                    checked={form.permissions.includes(opt.value)}
                    onChange={() => togglePermission(opt.value)}
                  />
                  {opt.label}
                </label>
              ))}
            </div>
          </div>

          <Select
            label="نطاق التفويض"
            value={form.scope_type}
            onChange={e => setForm(p => ({ ...p, scope_type: e.target.value as HRDelegationScopeType }))}
            options={[
              { value: 'all',    label: 'كل الشركة' },
              { value: 'branch', label: 'فرع محدد' },
              { value: 'team',   label: 'فريق محدد' },
            ]}
          />

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-2)' }}>
            <Input label="من تاريخ" type="date" required value={form.valid_from}  onChange={e => setForm(p => ({ ...p, valid_from:  e.target.value }))} />
            <Input label="إلى تاريخ" type="date" required value={form.valid_until} onChange={e => setForm(p => ({ ...p, valid_until: e.target.value }))} />
          </div>
          <Input label="سبب التفويض" value={form.reason} onChange={e => setForm(p => ({ ...p, reason: e.target.value }))} placeholder="سفر، إجازة..." />
        </div>
      </ResponsiveModal>
    </div>
  )
}

