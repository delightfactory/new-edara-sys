import { useState } from 'react'
import { Target, Plus, CheckCircle, TrendingUp, Award } from 'lucide-react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { getCommissionTargets, createCommissionTarget, getCommissionRecords, getPayrollPeriods } from '@/lib/services/hr'
import { getEmployees } from '@/lib/services/hr'
import type { HRCommissionTargetInput } from '@/lib/types/hr'
import PageHeader from '@/components/shared/PageHeader'
import Input from '@/components/ui/Input'
import Select from '@/components/ui/Select'
import Button from '@/components/ui/Button'
import Badge from '@/components/ui/Badge'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import PermissionGuard from '@/components/shared/PermissionGuard'
import { formatNumber } from '@/lib/utils/format'

const SOURCE_LABEL: Record<string, string> = {
  sales: 'مبيعات', collection: 'تحصيل', delivery: 'توصيل',
}
const SOURCE_VARIANT: Record<string, 'success' | 'info' | 'neutral'> = {
  sales: 'success', collection: 'info', delivery: 'neutral',
}

type ViewTab = 'targets' | 'records'

// ─── Empty form helper ───────────────────────
const EMPTY_TARGET: HRCommissionTargetInput = {
  employee_id: '',
  period_id: '',
  target_amount: 0,
  commission_rate: 5,
  tier_50_rate: null,
  tier_75_rate: null,
  tier_100_rate: null,
  tier_120_rate: null,
  notes: null,
}

export default function CommissionsPage() {
  const qc = useQueryClient()
  const [tab, setTab] = useState<ViewTab>('targets')
  const [formOpen, setFormOpen] = useState(false)
  const [form, setForm] = useState<HRCommissionTargetInput>(EMPTY_TARGET)
  const [filterPeriod, setFilterPeriod] = useState('')

  // Queries
  const { data: targets = [], isLoading: targetsLoading } = useQuery({
    queryKey: ['hr-commission-targets', filterPeriod],
    queryFn: () => getCommissionTargets({ periodId: filterPeriod || undefined }),
  })
  const { data: records = [], isLoading: recordsLoading } = useQuery({
    queryKey: ['hr-commission-records', filterPeriod],
    queryFn: () => getCommissionRecords({ periodId: filterPeriod || undefined }),
  })
  const { data: periods = [] } = useQuery({
    queryKey: ['hr-payroll-periods'],
    queryFn: getPayrollPeriods,
  })
  const { data: employees = [] } = useQuery({
    queryKey: ['hr-field-employees'],
    queryFn: () => getEmployees({ page: 1, pageSize: 200 }),
    select: d => d.data.filter(e => e.is_field_employee && e.status === 'active'),
  })

  const createMut = useMutation({
    mutationFn: () => createCommissionTarget(form),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['hr-commission-targets'] })
      toast.success('تم إضافة الهدف')
      setFormOpen(false)
      setForm(EMPTY_TARGET)
    },
    onError: (e: Error) => toast.error(e.message),
  })

  const setF = <K extends keyof HRCommissionTargetInput>(k: K) => (v: HRCommissionTargetInput[K]) =>
    setForm(p => ({ ...p, [k]: v }))

  // احسب الإجماليات من الأهداف
  const totalTargetAmount = targets.reduce((s, t) => s + t.target_amount, 0)
  const totalCommission   = records.reduce((s, r) => s + r.commission_amount, 0)

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="أهداف المبيعات والعمولات"
        subtitle="إدارة أهداف المندوبين وعرض العمولات المحسوبة"
        breadcrumbs={[
          { label: 'الموارد البشرية', path: '/hr' },
          { label: 'العمولات' },
        ]}
        actions={
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
            <Select
              value={filterPeriod}
              onChange={e => setFilterPeriod(e.target.value)}
              options={periods.map(p => ({ value: p.id, label: p.name }))}
              placeholder="كل الفترات"
              style={{ minWidth: 150 }}
            />
            <PermissionGuard permission="hr.commissions.create">
              <Button icon={<Plus size={14} />} onClick={() => setFormOpen(true)}>
                هدف جديد
              </Button>
            </PermissionGuard>
          </div>
        }
      />

      {/* Stats */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 'var(--space-3)', marginBottom: 'var(--space-4)' }}>
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
            <Target size={16} color="var(--color-primary)" />
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>إجمالي الأهداف</span>
          </div>
          <div style={{ fontSize: 'var(--text-xl)', fontWeight: 700 }}>{formatNumber(totalTargetAmount)} ج.م</div>
        </div>
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
            <TrendingUp size={16} color="var(--color-success)" />
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>إجمالي العمولات</span>
          </div>
          <div style={{ fontSize: 'var(--text-xl)', fontWeight: 700, color: 'var(--color-success)' }}>{formatNumber(totalCommission)} ج.م</div>
        </div>
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
            <Award size={16} color="var(--color-warning)" />
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>عدد المندوبين</span>
          </div>
          <div style={{ fontSize: 'var(--text-xl)', fontWeight: 700 }}>{targets.length}</div>
        </div>
      </div>

      {/* Tabs */}
      <div style={{ display: 'flex', gap: 4, borderBottom: '1.5px solid var(--border-color)', marginBottom: 'var(--space-4)' }}>
        {(['targets', 'records'] as ViewTab[]).map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            style={{
              padding: 'var(--space-2) var(--space-4)', border: 'none', background: 'transparent',
              cursor: 'pointer', fontFamily: 'var(--font-sans)', fontSize: 'var(--text-sm)',
              fontWeight: 500, marginBottom: -1.5,
              color: tab === t ? 'var(--color-primary)' : 'var(--text-muted)',
              borderBottom: `2px solid ${tab === t ? 'var(--color-primary)' : 'transparent'}`,
              transition: 'all 0.15s',
            }}
          >
            {t === 'targets' ? `الأهداف (${targets.length})` : `سجل العمولات (${records.length})`}
          </button>
        ))}
      </div>

      {/* Targets Table */}
      {tab === 'targets' && (
        <div className="edara-card" style={{ padding: 0, overflow: 'hidden' }}>
          {targetsLoading ? (
            <div style={{ textAlign: 'center', padding: 'var(--space-8)', color: 'var(--text-muted)' }}>جارٍ التحميل...</div>
          ) : targets.length === 0 ? (
            <div style={{ textAlign: 'center', padding: 'var(--space-8)' }}>
              <Target size={40} style={{ opacity: 0.3, marginBottom: 8 }} />
              <div style={{ color: 'var(--text-muted)' }}>لا توجد أهداف — {filterPeriod ? 'لهذه الفترة' : 'أضف هدفاً أولاً'}</div>
              <Button size="sm" icon={<Plus size={13} />} onClick={() => setFormOpen(true)} style={{ marginTop: 12 }}>هدف جديد</Button>
            </div>
          ) : (
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--text-sm)' }}>
              <thead>
                <tr style={{ background: 'var(--bg-surface-2)' }}>
                  <th style={{ padding: 'var(--space-3)', textAlign: 'right', color: 'var(--text-muted)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-color)' }}>المندوب</th>
                  <th style={{ padding: 'var(--space-3)', textAlign: 'right', color: 'var(--text-muted)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-color)' }}>الفترة</th>
                  <th style={{ padding: 'var(--space-3)', textAlign: 'end',  color: 'var(--text-muted)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-color)' }}>الهدف</th>
                  <th style={{ padding: 'var(--space-3)', textAlign: 'center',color: 'var(--text-muted)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-color)' }}>النسبة الأساسية</th>
                  <th style={{ padding: 'var(--space-3)', textAlign: 'center',color: 'var(--text-muted)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-color)' }}>شريحة 100%</th>
                </tr>
              </thead>
              <tbody>
                {targets.map(t => (
                  <tr key={t.id} style={{ borderBottom: '1px solid var(--border-color)' }}>
                    <td style={{ padding: 'var(--space-3)' }}>
                      <div style={{ fontWeight: 600 }}>{t.employee?.full_name ?? '—'}</div>
                      <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{t.employee?.employee_number}</div>
                    </td>
                    <td style={{ padding: 'var(--space-3)' }}>{t.period?.name ?? '—'}</td>
                    <td style={{ padding: 'var(--space-3)', textAlign: 'end', fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{formatNumber(t.target_amount)} ج.م</td>
                    <td style={{ padding: 'var(--space-3)', textAlign: 'center' }}>{t.commission_rate}%</td>
                    <td style={{ padding: 'var(--space-3)', textAlign: 'center' }}>{t.tier_100_rate != null ? `${t.tier_100_rate}%` : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* Records Table */}
      {tab === 'records' && (
        <div className="edara-card" style={{ padding: 0, overflow: 'hidden' }}>
          {recordsLoading ? (
            <div style={{ textAlign: 'center', padding: 'var(--space-8)', color: 'var(--text-muted)' }}>جارٍ التحميل...</div>
          ) : records.length === 0 ? (
            <div style={{ textAlign: 'center', padding: 'var(--space-8)', color: 'var(--text-muted)' }}>
              لا توجد سجلات عمولات — تُغذَّى تلقائياً من موديول المبيعات والتحصيلات
            </div>
          ) : (
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--text-sm)' }}>
              <thead>
                <tr style={{ background: 'var(--bg-surface-2)' }}>
                  <th style={{ padding: 'var(--space-3)', textAlign: 'right', color: 'var(--text-muted)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-color)' }}>المندوب</th>
                  <th style={{ padding: 'var(--space-3)', textAlign: 'right', color: 'var(--text-muted)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-color)' }}>المصدر</th>
                  <th style={{ padding: 'var(--space-3)', textAlign: 'end',  color: 'var(--text-muted)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-color)' }}>قيمة البيع</th>
                  <th style={{ padding: 'var(--space-3)', textAlign: 'end',  color: 'var(--text-muted)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-color)' }}>المحصَّل</th>
                  <th style={{ padding: 'var(--space-3)', textAlign: 'center',color: 'var(--text-muted)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-color)' }}>النسبة</th>
                  <th style={{ padding: 'var(--space-3)', textAlign: 'end',  color: 'var(--text-muted)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-color)' }}>العمولة</th>
                  <th style={{ padding: 'var(--space-3)', textAlign: 'center',color: 'var(--text-muted)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-color)' }}>مؤهل؟</th>
                </tr>
              </thead>
              <tbody>
                {records.map(r => (
                  <tr key={r.id} style={{ borderBottom: '1px solid var(--border-color)' }}>
                    <td style={{ padding: 'var(--space-3)' }}>
                      <div style={{ fontWeight: 600 }}>{r.employee?.full_name ?? '—'}</div>
                      <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{r.employee?.employee_number}</div>
                    </td>
                    <td style={{ padding: 'var(--space-3)' }}>
                      <Badge variant={SOURCE_VARIANT[r.source_type] ?? 'neutral'}>{SOURCE_LABEL[r.source_type] ?? r.source_type}</Badge>
                    </td>
                    <td style={{ padding: 'var(--space-3)', textAlign: 'end', fontVariantNumeric: 'tabular-nums' }}>{formatNumber(r.gross_amount)}</td>
                    <td style={{ padding: 'var(--space-3)', textAlign: 'end', fontVariantNumeric: 'tabular-nums', color: 'var(--color-success)' }}>{formatNumber(r.collected_amount)}</td>
                    <td style={{ padding: 'var(--space-3)', textAlign: 'center' }}>{r.commission_rate}%</td>
                    <td style={{ padding: 'var(--space-3)', textAlign: 'end', fontWeight: 700, color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>{formatNumber(r.commission_amount)}</td>
                    <td style={{ padding: 'var(--space-3)', textAlign: 'center' }}>
                      {r.is_eligible ? <CheckCircle size={15} color="var(--color-success)" /> : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* Add Target Modal */}
      <ResponsiveModal
        open={formOpen}
        onClose={() => setFormOpen(false)}
        title="إضافة هدف مبيعات"
        size="md"
        footer={
          <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
            <Button variant="secondary" onClick={() => setFormOpen(false)} style={{ flex: 1 }}>إلغاء</Button>
            <Button
              icon={<Target size={15} />}
              onClick={() => createMut.mutate()}
              loading={createMut.isPending}
              disabled={!form.employee_id || !form.period_id || form.target_amount <= 0}
              style={{ flex: 2 }}
            >
              حفظ الهدف
            </Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
            <Select
              label="المندوب"
              required
              value={form.employee_id}
              onChange={e => setF('employee_id')(e.target.value)}
              options={employees.map(e => ({ value: e.id, label: e.full_name }))}
              placeholder="اختر المندوب"
            />
            <Select
              label="فترة الراتب"
              required
              value={form.period_id}
              onChange={e => setF('period_id')(e.target.value)}
              options={periods.map(p => ({ value: p.id, label: p.name }))}
              placeholder="اختر الفترة"
            />
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
            <Input
              label="الهدف البيعي (ج.م)"
              type="number"
              required
              min={0}
              step={1000}
              value={String(form.target_amount)}
              onChange={e => setF('target_amount')(Number(e.target.value))}
            />
            <Input
              label="النسبة الأساسية %"
              type="number"
              required
              min={0}
              max={100}
              step={0.5}
              value={String(form.commission_rate)}
              onChange={e => setF('commission_rate')(Number(e.target.value))}
            />
          </div>

          <details style={{ borderRadius: 'var(--radius-md)', border: '1px solid var(--border-color)', padding: 'var(--space-3)' }}>
            <summary style={{ cursor: 'pointer', fontSize: 'var(--text-sm)', fontWeight: 600 }}>شرائح العمولة المتدرجة (اختياري)</summary>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)', marginTop: 'var(--space-3)' }}>
              <Input label="عند 50% من الهدف %" type="number" step={0.5} value={String(form.tier_50_rate ?? '')} onChange={e => setF('tier_50_rate')(e.target.value ? Number(e.target.value) : null)} />
              <Input label="عند 75% من الهدف %" type="number" step={0.5} value={String(form.tier_75_rate ?? '')} onChange={e => setF('tier_75_rate')(e.target.value ? Number(e.target.value) : null)} />
              <Input label="عند 100% من الهدف %" type="number" step={0.5} value={String(form.tier_100_rate ?? '')} onChange={e => setF('tier_100_rate')(e.target.value ? Number(e.target.value) : null)} />
              <Input label="عند تجاوز 120% %" type="number" step={0.5} value={String(form.tier_120_rate ?? '')} onChange={e => setF('tier_120_rate')(e.target.value ? Number(e.target.value) : null)} />
            </div>
          </details>

          <Input
            label="ملاحظات"
            value={form.notes ?? ''}
            onChange={e => setF('notes')(e.target.value || null)}
          />
        </div>
      </ResponsiveModal>
    </div>
  )
}
