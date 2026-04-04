/**
 * TargetDetail — عرض تفاصيل الهدف + إدارته بالكامل
 *
 * يعرض: Progress Widget + Forecast Cards + Progress Timeline
 *        + Adjustment History + Child Targets + Pause/Resume
 *        + Phase 22: Reward Configs + Customers List + Payouts Ledger
 */
import { useParams, useNavigate } from 'react-router-dom'
import {
  useTargetDetail, useTargetRewardSummary, useTargetProgressHistory,
  useTargetChildren, useAdjustTarget,
  useTargetStatus, useBranches, useHREmployees, useHRDepartments,
  useActivities, useUpdateTarget,
} from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import { toast } from 'sonner'
import { useState, useMemo } from 'react'
import {
  Edit2, Pause, Play, XCircle, Target, ChevronLeft,
  TrendingUp, Clock, BarChart3, AlertCircle, MapPin, Phone, Eye, Gift, Settings
} from 'lucide-react'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import TargetProgressWidget from '@/components/shared/TargetProgressWidget'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import ActivityStatusBadge from '@/components/shared/ActivityStatusBadge'
import type { TargetProgress, TargetAdjustment, AdjustableField } from '@/lib/types/activities'

import RewardConfigCard from '@/components/targets/RewardConfigCard'
import TierLadderDisplay from '@/components/targets/TierLadderDisplay'
import TargetCustomersSection from '@/components/targets/TargetCustomersSection'
import TargetRewardEditModal from '@/components/targets/TargetRewardEditModal'

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG', { day: 'numeric', month: 'long', year: 'numeric' })
}
function fmtUnit(n: number, unit?: string) {
  if (unit === 'currency') return `${n.toLocaleString('ar-EG', { maximumFractionDigits: 0 })} ج.م`
  if (unit === 'percent') return `${n.toFixed(1)}%`
  return n.toLocaleString('ar-EG', { maximumFractionDigits: 0 })
}

const SCOPE_AR: Record<string, string> = {
  company: 'الشركة', branch: 'الفرع', department: 'القسم', individual: 'فرد',
}
const PERIOD_AR: Record<string, string> = {
  monthly: 'شهري', quarterly: 'ربع سنوي', yearly: 'سنوي', custom: 'مخصص',
}
const FIELD_AR: Record<string, string> = {
  target_value: 'القيمة المستهدفة', min_value: 'الحد الأدنى', stretch_value: 'هدف التمدد',
  period_end: 'نهاية الفترة', is_paused: 'إيقاف مؤقت', is_active: 'الحالة',
  filter_criteria: 'معايير الفلترة',
}

export default function TargetDetail() {
  const { id }     = useParams<{ id: string }>()
  const navigate   = useNavigate()
  const can        = useAuthStore(s => s.can)
  const currentUserId = useAuthStore(s => s.profile?.id) ?? ''

  // ── Modals State
  const [adjustOpen, setAdjustOpen]   = useState(false)
  const [adjustField, setAdjustField] = useState<AdjustableField>('target_value')
  const [adjustValue, setAdjustValue] = useState('')
  const [adjustReason, setAdjustReason] = useState('')
  const [processing, setProcessing]   = useState(false)
  const [pauseOpen, setPauseOpen]     = useState(false)
  const [pauseReason, setPauseReason] = useState('')
  const [rewardEditOpen, setRewardEditOpen] = useState(false)

  // ── Edit Metadata State
  const [metaOpen, setMetaOpen]     = useState(false)
  const [metaName, setMetaName]     = useState('')
  const [metaDesc, setMetaDesc]     = useState('')
  const [metaNotes, setMetaNotes]   = useState('')
  const [metaSaving, setMetaSaving] = useState(false)

  // ── Data Fetching
  const { data: detailData, isLoading: detailLoading } = useTargetDetail(id)
  const { data: summaryData } = useTargetRewardSummary(id)
  const { data: progressHistory = [] } = useTargetProgressHistory(id)
  const { data: children = [] } = useTargetChildren(id)

  const target         = detailData?.target
  const latestProgress = detailData?.progress
  const adjustments    = detailData?.adjustments ?? []
  const payouts        = detailData?.payouts ?? []
  const computed       = detailData?.computed
  const rewardTiers    = detailData?.reward_tiers ?? []
  const targetCustomers = detailData?.target_customers ?? []

  // Derived metrics
  const daysRemaining  = computed?.days_remaining ?? 0
  const remainingValue = computed?.remaining_value ?? 0
  const dailyNeeded    = computed?.daily_pace_required ?? 0
  const unit           = target?.target_type?.unit

  // Keep forecastedValue from v_target_status to avoid regressions
  const { data: statusRows = [] } = useTargetStatus({ isActive: undefined })
  const statusRow       = statusRows.find(r => r.id === id)
  const forecastedValue = statusRow?.forecasted_value ?? null

  const { data: branches = [] }    = useBranches()
  const { data: departments = [] } = useHRDepartments()
  const { data: employeesRes }     = useHREmployees({ pageSize: 200 })
  const employees = useMemo(() => employeesRes?.data ?? [], [employeesRes])

  const adjustTarget    = useAdjustTarget()
  const updateTarget    = useUpdateTarget()
  const canAssign       = can(PERMISSIONS.TARGETS_ASSIGN)
  // [P1 FIX] Payroll status visibility — only hr.payroll.read holders see payout status
  const canReadPayroll  = can(PERMISSIONS.HR_PAYROLL_READ)

  // resolve scope_id name
  const scopeName = useMemo(() => {
    if (!target) return '—'
    if (target.scope === 'company') return 'الشركة كلها'
    if (target.scope === 'branch') return (branches as any[]).find(b => b.id === target.scope_id)?.name ?? target.scope_id
    if (target.scope === 'department') return (departments as any[]).find(d => d.id === target.scope_id)?.name ?? target.scope_id
    if (target.scope === 'individual') return employees.find(e => e.id === target.scope_id)?.full_name ?? target.scope_id
    return target.scope_id ?? '—'
  }, [target, branches, departments, employees])

  // ── Handlers
  const doAdjust = async (field: AdjustableField, value: string, reason: string) => {
    if (!id || !reason.trim()) return
    setProcessing(true)
    try {
      adjustTarget.mutate(
        { p_target_id: id, p_field: field, p_new_value: value, p_reason: reason, p_user_id: currentUserId },
        {
          onSuccess: () => {
            toast.success('تم تعديل الهدف')
            setAdjustOpen(false); setPauseOpen(false)
            setAdjustValue(''); setAdjustReason(''); setPauseReason('')
          },
          onError: (e: any) => toast.error(e?.message || 'فشل التعديل'),
          onSettled: () => setProcessing(false),
        }
      )
    } catch {
      toast.error('فشل جلب بيانات المستخدم')
      setProcessing(false)
    }
  }

  const handleAdjust     = () => doAdjust(adjustField, adjustValue, adjustReason)
  const handlePause      = () => doAdjust('is_paused', 'true', pauseReason || 'إيقاف مؤقت')
  const handleResume     = () => doAdjust('is_paused', 'false', 'استئناف الهدف')
  const handleDeactivate = () => {
    if (confirm('هل أنت متأكد من إلغاء هذا الهدف؟ لا يمكن التراجع.')) {
      doAdjust('is_active', 'false', 'إلغاء الهدف')
    }
  }

  const openMetaEdit = () => {
    setMetaName(target?.name ?? '')
    setMetaDesc(target?.description ?? '')
    setMetaNotes(target?.notes ?? '')
    setMetaOpen(true)
  }

  const handleSaveMeta = async () => {
    if (!id) return
    if (!metaName.trim()) { toast.error('اسم الهدف مطلوب'); return }
    setMetaSaving(true)
    try {
      await updateTarget.mutateAsync({
        id,
        input: {
          name: metaName.trim(),
          description: metaDesc.trim() || null,
          notes: metaNotes.trim() || null,
        }
      })
      toast.success('تم تحديث بيانات الهدف بنجاح')
      setMetaOpen(false)
    } catch (err: any) {
      toast.error(err?.message || 'فشل التحديث')
    } finally {
      setMetaSaving(false)
    }
  }

  // ── Loading / Empty state
  if (detailLoading) {
    return (
      <div className="page-container animate-enter">
        <div className="edara-card" style={{ padding: 'var(--space-6)' }}>
          {[1, 2, 3, 4].map(i => (
            <div key={i} className="skeleton" style={{ height: 20, marginBottom: 'var(--space-3)', width: `${70 - i * 10}%` }} />
          ))}
        </div>
      </div>
    )
  }

  if (!target) {
    return (
      <div className="page-container animate-enter">
        <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
          <p className="empty-state-title">لم يتم العثور على الهدف</p>
          <Button variant="secondary" onClick={() => navigate('/activities/targets')}>العودة</Button>
        </div>
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title={target.name}
        subtitle={`${target.target_type?.name ?? target.type_code} • ${SCOPE_AR[target.scope] ?? target.scope}`}
        breadcrumbs={[
          { label: 'الأهداف', path: '/activities/targets' },
          { label: target.name },
        ]}
        actions={canAssign ? (
          <div className="flex gap-2">
            <Button icon={<Settings size={16} />} variant="secondary" onClick={openMetaEdit}>
              تعديل البيانات
            </Button>
            <Button icon={<Edit2 size={16} />} variant="secondary" onClick={() => setAdjustOpen(true)}>
              تعديل القيمة
            </Button>
            {target.is_active && !target.is_paused && (
              <Button icon={<Pause size={14} />} variant="secondary" onClick={() => setPauseOpen(true)}>
                إيقاف
              </Button>
            )}
            {target.is_paused && (
              <Button icon={<Play size={14} />} variant="success" onClick={handleResume} disabled={processing}>
                استئناف
              </Button>
            )}
            {target.is_active && (
              <Button icon={<XCircle size={14} />} variant="danger" onClick={handleDeactivate} disabled={processing}>
                إلغاء
              </Button>
            )}
          </div>
        ) : undefined}
      />

      {/* Paused / Inactive Alert */}
      {target.is_paused && (
        <div className="td-alert td-alert--warning">
          <Pause size={16} />
          <span>هذا الهدف متوقف مؤقتاً{target.paused_reason ? ` — ${target.paused_reason}` : ''}</span>
        </div>
      )}
      {!target.is_active && (
        <div className="td-alert td-alert--danger">
          <XCircle size={16} />
          <span>هذا الهدف ملغى</span>
        </div>
      )}

      {/* Progress Widget */}
      <TargetProgressWidget target={target} progress={latestProgress} />

      {/* ── KPI Grid ─────────────────────────────────────────── */}
      <div className="td-kpi-grid">
        <div className="td-kpi">
          <div className="td-kpi-icon" style={{ background: 'var(--color-success-light)', color: 'var(--color-success)' }}>
            <BarChart3 size={18} />
          </div>
          <div className="td-kpi-value">{fmtUnit(latestProgress?.achieved_value ?? 0, unit)}</div>
          <div className="td-kpi-label">المحقّق</div>
        </div>
        <div className="td-kpi">
          <div className="td-kpi-icon" style={{ background: 'var(--color-warning-light)', color: 'var(--color-warning)' }}>
            <Target size={18} />
          </div>
          <div className="td-kpi-value">{fmtUnit(remainingValue, unit)}</div>
          <div className="td-kpi-label">المتبقي</div>
        </div>
        <div className="td-kpi">
          <div className="td-kpi-icon" style={{ background: 'var(--color-primary-light)', color: 'var(--color-primary)' }}>
            <Clock size={18} />
          </div>
          <div className="td-kpi-value">{daysRemaining}</div>
          <div className="td-kpi-label">يوم متبقي</div>
        </div>
        <div className="td-kpi">
          <div className="td-kpi-icon" style={{ background: 'rgba(139,92,246,0.1)', color: '#7c3aed' }}>
            <TrendingUp size={18} />
          </div>
          <div className="td-kpi-value">
            {forecastedValue != null ? fmtUnit(forecastedValue, unit) : '—'}
          </div>
          <div className="td-kpi-label">التوقع لنهاية الفترة</div>
        </div>
      </div>

      {/* Daily needed */}
      {daysRemaining > 0 && remainingValue > 0 && (
        <div className="td-daily-needed">
          <AlertCircle size={14} />
          <span>تحتاج إلى <strong>{fmtUnit(dailyNeeded, unit)}</strong> يومياً لتحقيق الهدف</span>
        </div>
      )}

      {/* ── Reward Config Section ────────────────────────────── */}
      {target.reward_type && (
        <div className="edara-card td-card" style={{ padding: 'var(--space-6)', marginTop: 'var(--space-6)' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', borderBottom: '1px solid var(--border-primary)', paddingBottom: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
            <h3 className="td-section-title" style={{ margin: 0, padding: 0, border: 'none', display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Gift size={20} className="text-primary" /> مسار المكافأة
            </h3>
            {canAssign && (
              <Button variant="secondary" onClick={() => setRewardEditOpen(true)} size="sm">
                <Edit2 size={14} style={{ marginRight: '6px' }} />
                إعدادات المكافأة
              </Button>
            )}
          </div>
          <RewardConfigCard summary={summaryData ?? null} />

          <div style={{ marginTop: 'var(--space-6)' }}>
            <TierLadderDisplay
              tiers={rewardTiers}
              currentAchievementPct={latestProgress?.achievement_pct ?? 0}
              rewardType={target.reward_type}
              estimatedReward={summaryData?.estimated_payout ?? null}
              rewardBaseValue={target.reward_base_value}
            />
          </div>
        </div>
      )}

      {/* ── Target Customers List ────────────────────────────── */}
      {targetCustomers.length > 0 && (
        <div className="edara-card td-card">
          <h3 className="td-section-title">👥 العملاء المستهدفون ({targetCustomers.length})</h3>
          <TargetCustomersSection customers={targetCustomers} />
        </div>
      )}

      {/* ── Reward Payouts Ledger ────────────────────────────── */}
      {target.reward_type && (
        <div className="edara-card td-card">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '12px' }}>
            <h3 className="td-section-title" style={{ margin: 0, border: 'none', padding: 0 }}>💸 سجل استحقاقات المكافآت</h3>
            {canReadPayroll && (
              <a
                href={`/hr/payroll/target-payouts?target_id=${id}`}
                style={{
                  fontSize: '12px', fontWeight: 600, color: 'var(--color-primary)',
                  textDecoration: 'none', display: 'flex', alignItems: 'center', gap: '4px',
                  padding: '4px 10px', border: '1px solid var(--color-primary)',
                  borderRadius: '6px', background: 'var(--color-primary-light)',
                  transition: 'all 0.15s',
                }}
                onMouseEnter={e => { (e.currentTarget as HTMLElement).style.background = 'var(--color-primary)'; (e.currentTarget as HTMLElement).style.color = '#fff' }}
                onMouseLeave={e => { (e.currentTarget as HTMLElement).style.background = 'var(--color-primary-light)'; (e.currentTarget as HTMLElement).style.color = 'var(--color-primary)' }}
              >
                ← صفحة HR للمكافآت
              </a>
            )}
          </div>
          {payouts.length === 0 ? (
            <div className="empty-state" style={{ padding: 'var(--space-6) 0' }}>
              <p className="empty-state-title" style={{ marginBottom: '8px' }}>لا توجد سجلات استحقاق حتى الآن</p>
              <p className="empty-state-text">سيتم إدراج الاستحقاقات هنا تلقائياً عند طلب دورة التقييم.</p>
            </div>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table className="edara-table" style={{ width: '100%', fontSize: '13px' }}>
                <thead>
                  <tr>
                    <th style={{ padding: '12px', textAlign: 'right', color: 'var(--text-muted)', borderBottom: '1px solid var(--border-color)' }}>التاريخ والفترة</th>
                    <th style={{ padding: '12px', textAlign: 'center', color: 'var(--text-muted)', borderBottom: '1px solid var(--border-color)' }}>الإنجاز</th>
                    <th style={{ padding: '12px', textAlign: 'center', color: 'var(--text-muted)', borderBottom: '1px solid var(--border-color)' }}>الشريحة المحققة</th>
                    <th style={{ padding: '12px', textAlign: 'center', color: 'var(--text-muted)', borderBottom: '1px solid var(--border-color)' }}>المبلغ المستحق</th>
                    {/* [P1 FIX] عمود الحالة للـ HR فقط */}
                    {canReadPayroll && (
                      <th style={{ padding: '12px', textAlign: 'center', color: 'var(--text-muted)', borderBottom: '1px solid var(--border-color)' }}>حالة الصرف</th>
                    )}
                  </tr>
                </thead>
                <tbody>
                  {payouts.map(p => (
                    <tr key={p.id} style={{ borderBottom: '1px solid var(--border-secondary)' }}>
                      <td style={{ padding: '12px' }}>
                        <div style={{ fontWeight: 600, color: 'var(--color-primary)' }}>
                          {new Date(p.computed_at).toLocaleDateString('ar-EG', { year: 'numeric', month: 'long', day: 'numeric' })}
                        </div>
                        {/* [P2 FIX] عرض اسم الفترة المقروء بدل period_id الخام */}
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                          {p.period?.name ? `فترة: ${p.period.name}` : 'بدون فترة مسير'}
                        </div>
                      </td>
                      <td style={{ padding: '12px', textAlign: 'center', fontWeight: 'bold' }}>
                        {p.achievement_pct.toFixed(1)}%
                      </td>
                      <td style={{ padding: '12px', textAlign: 'center' }}>
                        {p.tier_reached ? (
                          <span className="td-filter-tag" style={{ background: 'var(--color-primary-light)', color: 'var(--color-primary)', borderColor: 'rgba(59,130,246,0.3)' }}>
                            {`شريحة ${p.tier_reached}`}
                          </span>
                        ) : (
                          <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>بدون شريحة</span>
                        )}
                      </td>
                      <td style={{ padding: '12px', textAlign: 'center', fontWeight: 'bold', color: 'var(--color-success)' }}>
                        {fmtUnit(p.payout_amount, 'currency')}
                      </td>
                      {/* [P1 FIX] حالة الصرف — مرئية لـ hr.payroll.read فقط */}
                      {canReadPayroll && (
                        <td style={{ padding: '12px', textAlign: 'center' }}>
                          {p.status === 'pending' ? (
                            <span style={{ fontSize: '11px', fontWeight: 600, padding: '4px 8px', background: 'var(--color-warning-light)', color: 'var(--color-warning)', border: '1px solid rgba(245,158,11,0.3)', borderRadius: '6px' }}>قيد الصرف</span>
                          ) : p.status === 'committed' ? (
                            <span style={{ fontSize: '11px', fontWeight: 600, padding: '4px 8px', background: 'var(--color-success-light)', color: 'var(--color-success)', border: '1px solid rgba(16,185,129,0.3)', borderRadius: '6px' }}>مصروفة ✓</span>
                          ) : (
                            <span style={{ fontSize: '11px', fontWeight: 600, padding: '4px 8px', color: 'var(--color-danger)' }}>ملغية ✗</span>
                          )}
                        </td>
                      )}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* ── Progress Timeline ────────────────────────────────── */}
      {progressHistory.length > 0 && (
        <div className="edara-card td-card">
          <h3 className="td-section-title">📊 تطور الإنجاز</h3>
          <div className="td-progress-timeline">
            {progressHistory.slice(0, 15).reverse().map((p, i) => {
              const pct = Math.min(p.achievement_pct, 120)
              return (
                <div key={p.id || i} className="td-progress-bar-item">
                  <div className="td-progress-bar-date">
                    {new Date(p.snapshot_date).toLocaleDateString('ar-EG', { day: 'numeric', month: 'short' })}
                  </div>
                  <div className="td-progress-bar-track">
                    <div
                      className="td-progress-bar-fill"
                      style={{
                        width: `${Math.min(pct, 100)}%`,
                        background: pct >= 100 ? 'var(--color-success)' : pct >= 80 ? 'var(--color-primary)' : pct >= 60 ? 'var(--color-warning)' : 'var(--color-danger)',
                      }}
                    />
                  </div>
                  <div className="td-progress-bar-pct">{pct.toFixed(0)}%</div>
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* ── Details Card ──────────────────────────────────────── */}
      <div className="edara-card td-card">
        <h3 className="td-section-title">معلومات الهدف</h3>
        <div className="td-grid">
          <div className="td-item">
            <div className="td-label">القيمة المستهدفة</div>
            <div className="td-value td-value--primary">{fmtUnit(target.target_value, unit)}</div>
          </div>
          {target.min_value != null && (
            <div className="td-item">
              <div className="td-label">الحد الأدنى</div>
              <div className="td-value">{fmtUnit(target.min_value, unit)}</div>
            </div>
          )}
          {target.stretch_value != null && (
            <div className="td-item">
              <div className="td-label">هدف التمدد</div>
              <div className="td-value" style={{ color: '#7c3aed' }}>{fmtUnit(target.stretch_value, unit)}</div>
            </div>
          )}
          <div className="td-item">
            <div className="td-label">الفترة</div>
            <div className="td-value">{PERIOD_AR[target.period] ?? target.period}</div>
          </div>
          <div className="td-item">
            <div className="td-label">من</div>
            <div className="td-value">{fmtDate(target.period_start)}</div>
          </div>
          <div className="td-item">
            <div className="td-label">إلى</div>
            <div className="td-value">{fmtDate(target.period_end)}</div>
          </div>
          <div className="td-item">
            <div className="td-label">النطاق</div>
            <div className="td-value">{scopeName}</div>
          </div>
          <div className="td-item">
            <div className="td-label">الحالة</div>
            <div className="td-value">
              {target.is_paused ? (
                <span style={{ color: 'var(--color-warning)', fontWeight: 600 }}>⏸ موقوف</span>
              ) : target.is_active ? (
                <span style={{ color: 'var(--color-success)', fontWeight: 600 }}>● نشط</span>
              ) : (
                <span style={{ color: 'var(--text-muted)' }}>○ ملغى</span>
              )}
            </div>
          </div>
          {latestProgress?.trend && (
            <div className="td-item">
              <div className="td-label">الاتجاه</div>
              <div className="td-value">
                <ActivityStatusBadge trend={latestProgress.trend} size="sm" />
              </div>
            </div>
          )}
        </div>

        {/* Filters info */}
        {(target.product_id || target.category_id || target.governorate_id || target.dormancy_days) && (
          <div className="mt-4 pt-3 border-t border-primary">
            <div className="td-label mb-2">فلاتر تخصصية</div>
            <div className="flex gap-2 flex-wrap">
              {target.product_id && <span className="td-filter-tag">منتج محدد</span>}
              {target.category_id && <span className="td-filter-tag">تصنيف محدد</span>}
              {target.governorate_id && <span className="td-filter-tag">محافظة محددة</span>}
              {target.dormancy_days && <span className="td-filter-tag">خمول: {target.dormancy_days} يوم</span>}
            </div>
          </div>
        )}

        {target.description && (
          <div className="mt-4 pt-4 border-t border-primary">
            <div className="td-label mb-2">الوصف</div>
            <p className="m-0 text-sm text-secondary leading-relaxed">{target.description}</p>
          </div>
        )}
        {target.notes && (
          <div className="mt-3">
            <div className="td-label mb-2">ملاحظات</div>
            <p className="m-0 text-sm text-secondary leading-relaxed">{target.notes}</p>
          </div>
        )}
      </div>

      {/* ── Parent Target Link ────────────────────────────────── */}
      {target.parent_target_id && (
        <div className="edara-card td-parent-link" onClick={() => navigate(`/activities/targets/${target.parent_target_id}`)}>
          <ChevronLeft size={14} />
          <span>هذا الهدف جزء من هدف أعلى — عرض الهدف الأب</span>
        </div>
      )}

      {/* ── Child Targets ────────────────────────────────────── */}
      {children.length > 0 && (
        <div className="edara-card td-card">
          <h3 className="td-section-title">🔀 الأهداف الفرعية ({children.length})</h3>
          <div className="td-children">
            {children.map((child: any) => {
              const childProg = child.latest_progress
              return (
                <div
                  key={child.id}
                  className="td-child-card"
                  onClick={() => navigate(`/activities/targets/${child.id}`)}
                >
                  <div className="td-child-info">
                    <div className="td-child-name">{child.name}</div>
                    <div className="td-child-scope">{SCOPE_AR[child.scope]} — {fmtUnit(child.target_value, unit)}</div>
                  </div>
                  <div className="td-child-progress">
                    {childProg ? (
                      <>
                        <div className="td-child-pct">{childProg.achievement_pct.toFixed(0)}%</div>
                        <ActivityStatusBadge trend={childProg.trend ?? undefined} size="sm" />
                      </>
                    ) : (
                      <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>لم يُحسب</span>
                    )}
                  </div>
                  <ChevronLeft size={14} className="td-child-arrow" />
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* ── Contributing Activities ─────────────────────────── */}
      <ContributingActivities target={target} navigate={navigate} />

      {/* ── Adjustment History ────────────────────────────────── */}
      {adjustments.length > 0 && (
        <div className="edara-card td-card">
          <h3 className="td-section-title">📋 سجل التعديلات ({adjustments.length})</h3>
          <div className="td-adj-list">
            {adjustments.map((adj: TargetAdjustment) => (
              <div key={adj.id} className="td-adj-item">
                <div className="td-adj-dot" />
                <div className="td-adj-body">
                  <div className="td-adj-header">
                    <span className="td-adj-field">{FIELD_AR[adj.field_changed] ?? adj.field_changed}</span>
                    <span className="td-adj-date">
                      {new Date(adj.adjusted_at).toLocaleDateString('ar-EG', {
                        day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit',
                      })}
                    </span>
                  </div>
                  <div className="td-adj-change">
                    <span className="td-adj-old">{adj.old_value ?? '—'}</span>
                    <span className="td-adj-arrow">←</span>
                    <span className="td-adj-new">{adj.new_value ?? '—'}</span>
                  </div>
                  {adj.reason && <div className="td-adj-reason">السبب: {adj.reason}</div>}
                  {adj.adjusted_by_profile && (
                    <div className="td-adj-by">بواسطة: {adj.adjusted_by_profile.full_name}</div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* ─── Modal: Reward Edit ─── */}
      <TargetRewardEditModal
        open={rewardEditOpen}
        onClose={() => setRewardEditOpen(false)}
        targetId={id!}
        summary={summaryData ?? null}
        typeCode={target.type_code ?? ''}
        typeCategory={target.target_type?.category ?? ''}
      />

      {/* ── Edit Metadata Modal ────────────────────────────────────────── */}
      <ResponsiveModal
        open={metaOpen}
        onClose={() => setMetaOpen(false)}
        title="تعديل بيانات الهدف"
        disableOverlayClose={metaSaving}
        footer={<>
          <Button variant="secondary" onClick={() => setMetaOpen(false)} disabled={metaSaving}>إلغاء</Button>
          <Button onClick={handleSaveMeta} disabled={metaSaving || !metaName.trim()}>
            {metaSaving ? 'جاري الحفظ...' : 'حفظ البيانات'}
          </Button>
        </>}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div className="form-group">
            <label className="form-label">اسم الهدف <span className="form-required">*</span></label>
            <input
              className="form-input"
              value={metaName}
              onChange={e => setMetaName(e.target.value)}
              placeholder="مثال: هدف مبيعات القاهرة"
            />
          </div>
          <div className="form-group">
            <label className="form-label">الوصف التفصيلي</label>
            <textarea
              className="form-textarea"
              rows={3}
              value={metaDesc}
              onChange={e => setMetaDesc(e.target.value)}
              placeholder="وصف الهدف الذي يظهر للموظف..."
            />
          </div>
          <div className="form-group">
            <label className="form-label">ملاحظات داخلية (للمديرين فقط)</label>
            <textarea
              className="form-textarea"
              rows={2}
              value={metaNotes}
              onChange={e => setMetaNotes(e.target.value)}
              placeholder="أي ملاحظات لن تظهر للموظف..."
            />
          </div>
          {/* Locked fields warning */}
          <div style={{ marginTop: 'var(--space-2)', padding: 'var(--space-3)', background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-md)', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
            <span style={{ fontWeight: 600, display: 'block', marginBottom: 'var(--space-1)' }}>حقول مقفلة:</span>
            لحماية حسابات التقدم (Progress)، لا يمكن تعديل (القيم، نوع الهدف، المنتجات، الفروع) من هذه الشاشة بعد الإنشاء. لتعديل القيم المؤثرة، استخدم زر "تعديل القيمة" في أعلى الصفحة.
          </div>
        </div>
      </ResponsiveModal>

      {/* ── Adjust Value Modal ───────────────────────────────────────── */}
      <ResponsiveModal
        open={adjustOpen}
        onClose={() => setAdjustOpen(false)}
        title="تعديل قيمة الهدف"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => setAdjustOpen(false)} disabled={processing}>إلغاء</Button>
          <Button onClick={handleAdjust} disabled={processing || !adjustValue || !adjustReason.trim()}>
            {processing ? 'جاري الحفظ...' : 'حفظ التعديل'}
          </Button>
        </>}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div className="form-group">
            <label className="form-label">الحقل المراد تعديله</label>
            <select className="form-select" value={adjustField}
              onChange={e => setAdjustField(e.target.value as AdjustableField)}>
              <option value="target_value">القيمة المستهدفة</option>
              <option value="min_value">الحد الأدنى</option>
              <option value="stretch_value">هدف التمدد</option>
              <option value="period_end">نهاية الفترة</option>
            </select>
          </div>
          <div className="form-group">
            <label className="form-label">
              {adjustField === 'period_end' ? 'التاريخ الجديد' : 'القيمة الجديدة'}
              <span className="form-required"> *</span>
            </label>
            <input
              type={adjustField === 'period_end' ? 'date' : 'number'}
              className="form-input"
              value={adjustValue}
              onChange={e => setAdjustValue(e.target.value)}
              placeholder={adjustField === 'period_end' ? '' : 'أدخل القيمة...'}
            />
          </div>
          <div className="form-group">
            <label className="form-label">سبب التعديل <span className="form-required">*</span></label>
            <textarea className="form-textarea" rows={2} value={adjustReason}
              onChange={e => setAdjustReason(e.target.value)}
              placeholder="اذكر سبب التعديل لأغراض التدقيق..." />
          </div>
        </div>
      </ResponsiveModal>

      {/* ─── Modal: Pause ─── */}
      <ResponsiveModal
        open={pauseOpen}
        onClose={() => setPauseOpen(false)}
        title="إيقاف الهدف مؤقتاً"
        disableOverlayClose={processing}
        footer={<>
          <Button variant="secondary" onClick={() => setPauseOpen(false)} disabled={processing}>إلغاء</Button>
          <Button variant="danger" onClick={handlePause} disabled={processing}>
            {processing ? 'جاري الإيقاف...' : 'إيقاف الهدف'}
          </Button>
        </>}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <p style={{ margin: 0, fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', lineHeight: 1.7 }}>
            سيتم إيقاف حساب الإنجاز مؤقتاً لهذا الهدف.
            يُستخدم في حالات الإجازة أو الظروف الطارئة.
          </p>
          <div className="form-group">
            <label className="form-label">سبب الإيقاف (اختياري)</label>
            <input className="form-input" value={pauseReason}
              onChange={e => setPauseReason(e.target.value)}
              placeholder="مثال: إجازة سنوية..." />
          </div>
        </div>
      </ResponsiveModal>

      <style>{`
        .td-alert { display: flex; align-items: center; gap: var(--space-2); padding: var(--space-3) var(--space-4); border-radius: var(--radius-md); border: 1px solid; font-size: var(--text-sm); font-weight: 600; margin-bottom: var(--space-3); }
        .td-alert--warning { background: var(--color-warning-light); border-color: var(--color-warning); color: var(--color-warning); }
        .td-alert--danger  { background: var(--color-danger-light); border-color: var(--color-danger); color: var(--color-danger); }
        .td-kpi-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: var(--space-3); margin: var(--space-4) 0; }
        .td-kpi { background: var(--bg-surface); border: 1px solid var(--border-primary); border-radius: var(--radius-lg); padding: var(--space-4); text-align: center; }
        .td-kpi-icon { width: 36px; height: 36px; border-radius: var(--radius-md); display: flex; align-items: center; justify-content: center; margin: 0 auto var(--space-2); }
        .td-kpi-value { font-size: var(--text-lg); font-weight: 800; color: var(--text-primary); font-variant-numeric: tabular-nums; }
        .td-kpi-label { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }
        @media (max-width: 600px) { .td-kpi-grid { grid-template-columns: 1fr 1fr; } }
        .td-daily-needed { display: flex; align-items: center; gap: var(--space-2); padding: var(--space-3) var(--space-4); background: var(--color-primary-light); border: 1px solid var(--color-primary); border-radius: var(--radius-md); font-size: var(--text-sm); color: var(--color-primary); margin-bottom: var(--space-4); }
        .td-card { padding: var(--space-5); margin-top: var(--space-4); }
        .td-section-title { font-size: var(--text-base); font-weight: 700; color: var(--text-primary); margin: 0 0 var(--space-4); padding-bottom: var(--space-3); border-bottom: 1px solid var(--border-primary); }
        .td-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: var(--space-4); }
        .td-label { font-size: var(--text-xs); color: var(--text-muted); margin-bottom: var(--space-1); font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; }
        .td-value { font-size: var(--text-sm); color: var(--text-primary); font-weight: 500; }
        .td-value--primary { font-size: var(--text-lg); font-weight: 700; color: var(--color-primary); font-variant-numeric: tabular-nums; }
        .td-filter-tag { font-size: 11px; padding: 2px 8px; border-radius: 99px; background: var(--bg-surface-2); color: var(--text-secondary); border: 1px solid var(--border-primary); }
        .td-parent-link { display: flex; align-items: center; gap: var(--space-2); padding: var(--space-3) var(--space-4); margin-top: var(--space-3); cursor: pointer; font-size: var(--text-sm); color: var(--color-primary); font-weight: 600; transition: background var(--transition-fast); }
        .td-parent-link:hover { background: var(--color-primary-light); }
        .td-children { display: flex; flex-direction: column; gap: var(--space-2); }
        .td-child-card { display: flex; align-items: center; gap: var(--space-3); padding: var(--space-3) var(--space-4); background: var(--bg-surface-2); border: 1px solid var(--border-primary); border-radius: var(--radius-md); cursor: pointer; transition: background var(--transition-fast); position: relative; }
        .td-child-card:hover { background: var(--bg-hover); }
        .td-child-info { flex: 1; }
        .td-child-name { font-weight: 600; font-size: var(--text-sm); color: var(--text-primary); }
        .td-child-scope { font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }
        .td-child-progress { display: flex; align-items: center; gap: var(--space-2); }
        .td-child-pct { font-size: var(--text-sm); font-weight: 700; color: var(--text-primary); }
        .td-child-arrow { position: absolute; left: var(--space-3); top: 50%; transform: translateY(-50%); color: var(--text-muted); opacity: 0.5; }
        .td-progress-timeline { display: flex; flex-direction: column; gap: var(--space-2); }
        .td-progress-bar-item { display: grid; grid-template-columns: 60px 1fr 40px; align-items: center; gap: var(--space-2); }
        .td-progress-bar-date { font-size: 11px; color: var(--text-muted); text-align: right; }
        .td-progress-bar-track { height: 8px; background: var(--bg-surface-2); border-radius: 99px; overflow: hidden; }
        .td-progress-bar-fill { height: 100%; border-radius: 99px; transition: width 0.4s ease; }
        .td-progress-bar-pct { font-size: 11px; font-weight: 700; color: var(--text-secondary); text-align: right; }
        .td-adj-list { display: flex; flex-direction: column; gap: 0; position: relative; }
        .td-adj-list::before { content: ''; position: absolute; right: 7px; top: 8px; bottom: 8px; width: 2px; background: var(--border-primary); }
        .td-adj-item { display: flex; gap: var(--space-3); padding: var(--space-3) 0; position: relative; }
        .td-adj-dot { width: 16px; height: 16px; border-radius: 50%; flex-shrink: 0; background: var(--color-primary); border: 3px solid var(--bg-surface); position: relative; z-index: 1; }
        .td-adj-body { flex: 1; }
        .td-adj-header { display: flex; justify-content: space-between; align-items: center; }
        .td-adj-field { font-weight: 700; font-size: var(--text-sm); color: var(--text-primary); }
        .td-adj-date { font-size: 11px; color: var(--text-muted); }
        .td-adj-change { display: flex; align-items: center; gap: var(--space-2); margin-top: var(--space-1); font-size: var(--text-sm); }
        .td-adj-old { color: var(--color-danger); text-decoration: line-through; }
        .td-adj-arrow { color: var(--text-muted); }
        .td-adj-new { color: var(--color-success); font-weight: 600; }
        .td-adj-reason { font-size: var(--text-xs); color: var(--text-muted); margin-top: var(--space-1); font-style: italic; }
        .td-adj-by { font-size: 11px; color: var(--text-muted); margin-top: 2px; }
      `}</style>
    </div>
  )
}

// ── Contributing Activities ─────────────────────────────────
const TYPE_CAT_MAP: Record<string, string> = {
  visits_count: 'visit',
  calls_count: 'call',
}
const CAT_ICON_MAP: Record<string, React.ReactNode> = {
  visit: <MapPin size={14} />,
  call: <Phone size={14} />,
}
const OUTCOME_LABELS: Record<string, string> = {
  order_placed: 'طلب مبيعات', agreed_order: 'اتفاق على طلب', collection: 'تحصيل',
  promised_payment: 'وعد بالدفع', followup_visit: 'زيارة متابعة', followup_scheduled: 'متابعة مجدولة',
  refused: 'رفض', not_interested: 'غير مهتم', closed: 'مغلق', promotion: 'ترويج',
  exploratory: 'استكشافية', info_only: 'معلومات فقط', no_answer: 'لا يرد', busy: 'مشغول',
}

function ContributingActivities({ target, navigate }: { target: any; navigate: (path: string) => void }) {
  const typeCategory = TYPE_CAT_MAP[target.type_code] ?? undefined
  const employeeId   = target.scope === 'individual' ? target.scope_id : undefined

  const { data: result, isLoading } = useActivities({
    typeCategory,
    employeeId,
    dateFrom: target.period_start,
    dateTo:   target.period_end,
    pageSize: 5,
  })
  const activities = result?.data ?? []

  if (isLoading) {
    return (
      <div className="edara-card td-card">
        <h3 className="td-section-title">📊 آخر الأنشطة المساهمة</h3>
        {[1, 2, 3].map(i => (
          <div key={i} className="skeleton" style={{ height: 40, borderRadius: 'var(--radius-md)', marginBottom: 'var(--space-2)' }} />
        ))}
      </div>
    )
  }

  if (activities.length === 0) return null

  return (
    <div className="edara-card td-card">
      <h3 className="td-section-title">📊 آخر الأنشطة المساهمة</h3>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
        {activities.map((act, idx) => {
          const cat     = (act as any).type?.category ?? ''
          const icon    = CAT_ICON_MAP[cat] ?? <Clock size={14} />
          const outcome = OUTCOME_LABELS[act.outcome_type] ?? act.outcome_type
          const date    = new Date(act.activity_date).toLocaleDateString('ar-EG', { day: 'numeric', month: 'short' })
          return (
            <div
              key={act.id}
              onClick={() => navigate(`/activities/${act.id}`)}
              style={{
                display: 'flex', alignItems: 'center', gap: 'var(--space-3)',
                padding: 'var(--space-2) 0', cursor: 'pointer',
                borderBottom: idx < activities.length - 1 ? '1px solid var(--border-secondary)' : 'none',
              }}
            >
              <div className="w-[30px] h-[30px] rounded-full flex-shrink-0 bg-surface-2 flex items-center justify-center text-primary">
                {icon}
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between gap-1">
                  <span className="font-semibold text-sm">
                    {(act as any).customer?.name ?? (act as any).type?.name ?? 'نشاط'}
                  </span>
                  <span className="text-[11px] text-muted whitespace-nowrap">{date}</span>
                </div>
                <span className="text-xs text-secondary">{outcome}</span>
              </div>
              <Eye size={12} className="text-muted flex-shrink-0" />
            </div>
          )
        })}
      </div>
    </div>
  )
}
