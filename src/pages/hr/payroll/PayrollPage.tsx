import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Plus, FileSpreadsheet, ChevronDown, CheckCircle, Clock, AlertCircle } from 'lucide-react'
import {
  useHRPayrollRuns,
  useHRPayrollPeriods,
} from '@/hooks/useQueryHooks'
import type { HRPayrollRun, HRPayrollRunStatus } from '@/lib/types/hr'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import PermissionGuard from '@/components/shared/PermissionGuard'
import PayrollRunForm from './PayrollRunForm'
import PayrollPeriodModal from './PayrollPeriodModal'

// ─── حالات المسير ─────────────────────────────────────
const STATUS_LABEL: Record<HRPayrollRunStatus, string> = {
  draft:       'مسودة',
  calculating: 'قيد الحساب',
  review:      'مراجعة',
  approved:    'مُعتمد',
  paid:        'مدفوع',
  cancelled:   'ملغي',
}

const STATUS_VARIANT: Record<HRPayrollRunStatus, 'neutral' | 'warning' | 'info' | 'success' | 'danger'> = {
  draft:       'neutral',
  calculating: 'warning',
  review:      'info',
  approved:    'success',
  paid:        'success',
  cancelled:   'danger',
}

const STATUS_ICON: Record<HRPayrollRunStatus, React.ReactNode> = {
  draft:       <Clock size={12} />,
  calculating: <Clock size={12} />,
  review:      <AlertCircle size={12} />,
  approved:    <CheckCircle size={12} />,
  paid:        <CheckCircle size={12} />,
  cancelled:   <AlertCircle size={12} />,
}

const fmt = (n: number) =>
  n.toLocaleString('ar-EG-u-nu-latn', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' ج.م'

const fmtDate = (d?: string | null) =>
  d ? new Date(d).toLocaleDateString('ar-EG-u-nu-latn', { day: 'numeric', month: 'short', year: 'numeric' }) : '—'

// ═════════════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════════════

export default function PayrollPage() {
  const navigate = useNavigate()

  // فلاتر
  const [statusFilter, setStatusFilter] = useState<string>('')
  const [periodFilter, setPeriodFilter] = useState<string>('')

  // بيانات
  const { data: runs = [],    isLoading } = useHRPayrollRuns({
    periodId: periodFilter || undefined,
  })
  const { data: periods = [] }            = useHRPayrollPeriods()

  // فلترة الحالة (local لأن الـ API لا يدعمها مباشرة)
  const filtered = statusFilter
    ? runs.filter(r => r.status === statusFilter)
    : runs

  // حالة نافذة الإنشاء
  const [formOpen, setFormOpen] = useState(false)
  const [periodOpen, setPeriodOpen] = useState(false)

  // ─── أعمدة الجدول ─────────────────────────────────
  const columns = [
    {
      key: 'number',
      label: 'رقم المسير',
      render: (r: HRPayrollRun) => (
        <span style={{ fontFamily: 'monospace', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
          {r.number ?? '—'}
        </span>
      ),
    },
    {
      key: 'period',
      label: 'الفترة',
      render: (r: HRPayrollRun) => (
        <div>
          <div style={{ fontWeight: 600 }}>{r.period?.name ?? '—'}</div>
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
            {fmtDate(r.period?.start_date)} — {fmtDate(r.period?.end_date)}
          </div>
        </div>
      ),
    },
    {
      key: 'total_employees',
      label: 'موظفون',
      align: 'center' as const,
      hideOnMobile: true,
      render: (r: HRPayrollRun) => (
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>{r.total_employees}</span>
      ),
    },
    {
      key: 'total_gross',
      label: 'الإجمالي',
      align: 'end' as const,
      hideOnMobile: true,
      render: (r: HRPayrollRun) => (
        <span style={{ fontVariantNumeric: 'tabular-nums', color: 'var(--color-success)' }}>
          {fmt(r.total_gross)}
        </span>
      ),
    },
    {
      key: 'total_net',
      label: 'الصافي',
      align: 'end' as const,
      render: (r: HRPayrollRun) => (
        <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: 'var(--color-primary)' }}>
          {fmt(r.total_net)}
        </span>
      ),
    },
    {
      key: 'status',
      label: 'الحالة',
      render: (r: HRPayrollRun) => (
        <Badge variant={STATUS_VARIANT[r.status]}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-1)' }}>
            {STATUS_ICON[r.status]}
            {STATUS_LABEL[r.status]}
          </span>
        </Badge>
      ),
    },
    {
      key: 'approved_at',
      label: 'تاريخ الاعتماد',
      hideOnMobile: true,
      render: (r: HRPayrollRun) => (
        <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
          {r.approved_at ? fmtDate(r.approved_at) : '—'}
        </span>
      ),
    },
  ]

  return (
    <div className="page-container animate-enter">

      <PageHeader
        title="مسير الرواتب"
        subtitle="إدارة دورات صرف الرواتب الشهرية"
        breadcrumbs={[
          { label: 'الموارد البشرية' },
          { label: 'مسير الرواتب' },
        ]}
        actions={
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap' }}>

            {/* زر الفترة الجديدة */}
            <PermissionGuard permission="hr.payroll.calculate">
              <Button
                id="btn-new-payroll-period"
                variant="secondary"
                icon={<Plus size={14} />}
                onClick={() => setPeriodOpen(true)}
              >
                فترة جديدة
              </Button>
            </PermissionGuard>

            {/* فلتر الفترة */}
            <div style={{ position: 'relative' }}>
              <select
                id="payroll-period-filter"
                className="form-input"
                value={periodFilter}
                onChange={e => setPeriodFilter(e.target.value)}
                style={{ paddingLeft: 'var(--space-6)', width: 'auto', minWidth: 160 }}
              >
                <option value="">كل الفترات</option>
                {periods.map(p => (
                  <option key={p.id} value={p.id}>{p.name}</option>
                ))}
              </select>
              <ChevronDown size={13} style={{
                position: 'absolute', left: 'var(--space-2)', top: '50%',
                transform: 'translateY(-50%)', pointerEvents: 'none', color: 'var(--text-muted)',
              }} />
            </div>

            {/* فلتر الحالة */}
            <div style={{ position: 'relative' }}>
              <select
                id="payroll-status-filter"
                className="form-input"
                value={statusFilter}
                onChange={e => setStatusFilter(e.target.value)}
                style={{ paddingLeft: 'var(--space-6)', width: 'auto', minWidth: 140 }}
              >
                <option value="">كل الحالات</option>
                {Object.entries(STATUS_LABEL).map(([k, v]) => (
                  <option key={k} value={k}>{v}</option>
                ))}
              </select>
              <ChevronDown size={13} style={{
                position: 'absolute', left: 'var(--space-2)', top: '50%',
                transform: 'translateY(-50%)', pointerEvents: 'none', color: 'var(--text-muted)',
              }} />
            </div>

            <PermissionGuard permission="hr.payroll.calculate">
              <Button
                id="btn-new-payroll-run"
                icon={<Plus size={14} />}
                onClick={() => setFormOpen(true)}
              >
                مسير جديد
              </Button>
            </PermissionGuard>
          </div>
        }
      />

      {/* ── الجدول الرئيسي ── */}
      <div className="edara-card" style={{ padding: 0, overflow: 'hidden' }}>
        <DataTable
          columns={columns}
          data={filtered}
          loading={isLoading}
          keyField="id"
          onRowClick={r => navigate(`/hr/payroll/${r.id}`)}
          emptyIcon={<FileSpreadsheet size={40} />}
          emptyTitle="لا توجد مسيرات رواتب"
          emptyText="أنشئ مسيرك الأول لبدء دورة الرواتب"
          emptyAction={
            <PermissionGuard permission="hr.payroll.calculate">
              <Button size="sm" icon={<Plus size={13} />} onClick={() => setFormOpen(true)}>
                مسير جديد
              </Button>
            </PermissionGuard>
          }
          rowClassName={r => r.status === 'review' ? 'tr-pending-review' : undefined}
        />
      </div>

      {/* ── نافذة الإنشاء والحساب ── */}
      <PayrollRunForm
        open={formOpen}
        onClose={() => setFormOpen(false)}
        onSuccess={run => navigate(`/hr/payroll/${run.id}`)}
      />

      {/* ── نافذة إنشاء فترة ── */}
      <PayrollPeriodModal
        open={periodOpen}
        onClose={() => setPeriodOpen(false)}
      />

      <style>{`
        .tr-pending-review { background: color-mix(in srgb, var(--color-info) 4%, transparent); }
        .tr-pending-review:hover { background: color-mix(in srgb, var(--color-info) 8%, transparent) !important; }
      `}</style>
    </div>
  )
}
