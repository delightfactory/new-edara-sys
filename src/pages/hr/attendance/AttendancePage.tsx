import { useState } from 'react'
import { Calendar, Edit2, Check, X, Clock, MapPin, AlertCircle } from 'lucide-react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { getAttendanceDays, upsertAttendanceDay } from '@/lib/services/hr'
import { supabase as _supabase } from '@/lib/supabase/client'
import { getEmployees } from '@/lib/services/hr'
import {
  useAttendanceReviewSummary,
  useDismissAttendanceAlert,
  useHRAttendanceAlerts,
  useResolveAttendanceAlert,
} from '@/hooks/useQueryHooks'
import type { HRAttendanceAlert, HRAttendanceDay, HRAttendanceDayInput, HRAttendanceStatus } from '@/lib/types/hr'
import PageHeader from '@/components/shared/PageHeader'
import Input from '@/components/ui/Input'
import Select from '@/components/ui/Select'
import Button from '@/components/ui/Button'
import Badge from '@/components/ui/Badge'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import PermissionGuard from '@/components/shared/PermissionGuard'
import DataCard from '@/components/ui/DataCard'
import StatCard from '@/components/shared/StatCard'
import DataTable from '@/components/shared/DataTable'

// ─── Status maps ──────────────────────────────────────────
const STATUS_LABEL: Record<HRAttendanceStatus, string> = {
  present: 'حاضر', late: 'متأخر', half_day: 'نصف يوم',
  absent_unauthorized: 'غياب غير مبرر', absent_authorized: 'غياب مبرر',
  on_leave: 'إجازة', weekly_off: 'عطلة أسبوعية', public_holiday: 'عطلة رسمية',
}
const STATUS_VARIANT: Record<HRAttendanceStatus, 'success' | 'warning' | 'danger' | 'info' | 'neutral'> = {
  present: 'success', late: 'warning', half_day: 'info',
  absent_unauthorized: 'danger', absent_authorized: 'warning',
  on_leave: 'info', weekly_off: 'neutral', public_holiday: 'neutral',
}
const REVIEW_LABEL = { ok: 'سليم', needs_review: 'يحتاج مراجعة', reviewed: 'تمت مراجعته' }
const REVIEW_VARIANT = { ok: 'success', needs_review: 'warning', reviewed: 'info' } as const
const TRACKING_LABEL = { idle: 'خامل', active: 'نشط', ended: 'منتهٍ', stale: 'منقطع', outside_zone: 'خارج النطاق' }
const ALERT_LABEL = {
  tracking_gap: 'انقطاع تتبع',
  outside_allowed_zone: 'خروج من النطاق',
  permission_no_return: 'إذن بلا عودة',
  auto_checkout: 'انصراف تلقائي',
  manual_correction: 'تصحيح يدوي',
  missing_day: 'يوم مفقود',
  open_day_unclosed: 'يوم غير مغلق',
} as const
const ALERT_VARIANT = {
  low: 'info',
  medium: 'warning',
  high: 'danger',
} as const

// ─── فلترة تاريخ افتراضي: اليوم ─────────────────────────
function todayStr() { return new Date().toISOString().split('T')[0] }
function firstOfMonth() {
  const d = new Date(); d.setDate(1)
  return d.toISOString().split('T')[0]
}

const fmtTime = (ts?: string | null) => {
  if (!ts) return '—'
  return new Date(ts).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit', hour12: true })
}

// ─── Manual Edit Modal ─────────────────────────────────────
interface EditModalProps {
  day: HRAttendanceDay | null
  onClose: () => void
  onSaved: () => void
}

function ManualEditModal({ day, onClose, onSaved }: EditModalProps) {
  const [punchIn,  setPunchIn]  = useState(day?.punch_in_time  ? new Date(day.punch_in_time).toISOString().slice(0, 16)  : '')
  const [punchOut, setPunchOut] = useState(day?.punch_out_time ? new Date(day.punch_out_time).toISOString().slice(0, 16) : '')
  const [notes,    setNotes]    = useState(day?.notes ?? '')

  const saveMut = useMutation({
    mutationFn: () => {
      if (!day) return Promise.reject(new Error('لا يوجد سجل'))

      // FIX-03: حساب القيم المشتقة من الأوقات المعدلة
      let status: HRAttendanceStatus = day.status
      let effectiveHours: number | null = day.effective_hours
      let dayValue = day.day_value

      const punchInDate  = punchIn  ? new Date(punchIn)  : null
      const punchOutDate = punchOut ? new Date(punchOut) : null

      // إذا تم تحديد وقت حضور → اعتبره حاضراً
      if (punchInDate) {
        status = 'present'
        dayValue = 1.0
      }

      // حساب effective_hours من الفرق بين الحضور والانصراف
      if (punchInDate && punchOutDate) {
        const diffMs = punchOutDate.getTime() - punchInDate.getTime()
        effectiveHours = Math.min(24, Math.round((diffMs / 3600000) * 100) / 100)
      }

      const input: HRAttendanceDayInput = {
        employee_id:    day.employee_id,
        shift_date:     day.shift_date,
        punch_in_time:  punchInDate  ? punchInDate.toISOString()  : null,
        punch_out_time: punchOutDate ? punchOutDate.toISOString() : null,
        status,
        effective_hours: effectiveHours,
        day_value:       dayValue,
        notes: notes || null,
      }
      return upsertAttendanceDay(input)
    },
    onSuccess: () => { toast.success('تم تحديث سجل الحضور'); onSaved(); onClose() },
    onError: (e: Error) => toast.error(e.message),
  })

  if (!day) return null

  return (
    <ResponsiveModal
      open={!!day}
      onClose={onClose}
      title="تعديل سجل حضور يدوي"
      size="sm"
      footer={
        <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
          <Button variant="secondary" onClick={onClose} style={{ flex: 1 }}>إلغاء</Button>
          <Button icon={<Check size={14} />} onClick={() => saveMut.mutate()} loading={saveMut.isPending} style={{ flex: 2 }}>
            حفظ التعديل
          </Button>
        </div>
      }
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          padding: 'var(--space-3)', borderRadius: 'var(--radius-md)',
          background: 'color-mix(in srgb, var(--color-warning) 8%, transparent)',
          border: '1px solid color-mix(in srgb, var(--color-warning) 25%, transparent)',
          fontSize: 'var(--text-xs)',
        }}>
          <AlertCircle size={14} color="var(--color-warning)" />
          <span>التعديل اليدوي يُسجَّل في سجل التدقيق ويؤثر على حساب الجزاءات</span>
        </div>

        <div>
          <strong style={{ fontSize: 'var(--text-sm)' }}>{day.employee?.full_name ?? '—'}</strong>
          <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginRight: 8 }}>
            {new Date(day.shift_date).toLocaleDateString('ar-EG', { weekday: 'long', day: 'numeric', month: 'long' })}
          </span>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
          <Input
            label="وقت الحضور"
            type="datetime-local"
            value={punchIn}
            onChange={e => setPunchIn(e.target.value)}
            dir="ltr"
          />
          <Input
            label="وقت الانصراف"
            type="datetime-local"
            value={punchOut}
            onChange={e => setPunchOut(e.target.value)}
            dir="ltr"
          />
        </div>

        <Input
          label="سبب التعديل"
          value={notes}
          onChange={e => setNotes(e.target.value)}
          placeholder="موظف نسي تسجيل الانصراف، ..."
        />
      </div>
    </ResponsiveModal>
  )
}

interface CreateManualDayModalProps {
  open: boolean
  employees: Array<{ id: string; full_name: string }>
  onClose: () => void
  onSaved: () => void
}

function CreateManualDayModal({ open, employees, onClose, onSaved }: CreateManualDayModalProps) {
  const [employeeId, setEmployeeId] = useState('')
  const [shiftDate, setShiftDate] = useState(todayStr())
  const [punchIn, setPunchIn] = useState('')
  const [punchOut, setPunchOut] = useState('')
  const [notes, setNotes] = useState('')

  const saveMut = useMutation({
    mutationFn: async () => {
      if (!employeeId) throw new Error('يرجى اختيار الموظف')
      if (!shiftDate) throw new Error('يرجى تحديد التاريخ')

      const punchInIso = punchIn ? new Date(`${shiftDate}T${punchIn}`).toISOString() : null
      const punchOutIso = punchOut ? new Date(`${shiftDate}T${punchOut}`).toISOString() : null
      const effectiveHours = punchInIso && punchOutIso
        ? Math.round(((new Date(punchOutIso).getTime() - new Date(punchInIso).getTime()) / 3600000) * 100) / 100
        : null

      const input: HRAttendanceDayInput = {
        employee_id: employeeId,
        shift_date: shiftDate,
        punch_in_time: punchInIso,
        punch_out_time: punchOutIso,
        status: punchInIso ? 'present' : 'absent_authorized',
        effective_hours: effectiveHours,
        day_value: punchInIso ? 1 : 0,
        review_status: 'reviewed',
        notes: notes || 'إضافة يدوية من الإدارة',
      }

      return upsertAttendanceDay(input)
    },
    onSuccess: () => {
      toast.success('تم إنشاء اليوم اليدوي')
      setEmployeeId('')
      setShiftDate(todayStr())
      setPunchIn('')
      setPunchOut('')
      setNotes('')
      onSaved()
      onClose()
    },
    onError: (e: Error) => toast.error(e.message),
  })

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      title="إضافة يوم حضور يدوي"
      size="sm"
      footer={
        <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
          <Button variant="secondary" onClick={onClose} style={{ flex: 1 }}>إلغاء</Button>
          <Button icon={<Check size={14} />} onClick={() => saveMut.mutate()} loading={saveMut.isPending} style={{ flex: 2 }}>
            حفظ اليوم
          </Button>
        </div>
      }
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <Select
          label="الموظف"
          value={employeeId}
          onChange={e => setEmployeeId(e.target.value)}
          options={employees.map(e => ({ value: e.id, label: e.full_name }))}
          placeholder="اختر الموظف"
        />
        <Input label="التاريخ" type="date" value={shiftDate} onChange={e => setShiftDate(e.target.value)} />
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
          <Input label="وقت الحضور" type="time" value={punchIn} onChange={e => setPunchIn(e.target.value)} dir="ltr" />
          <Input label="وقت الانصراف" type="time" value={punchOut} onChange={e => setPunchOut(e.target.value)} dir="ltr" />
        </div>
        <Input label="ملاحظات" value={notes} onChange={e => setNotes(e.target.value)} placeholder="سبب الإنشاء اليدوي" />
      </div>
    </ResponsiveModal>
  )
}

// ═════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════
export default function AttendancePage() {
  const qc = useQueryClient()

  // Filters
  const [dateFrom, setDateFrom] = useState(firstOfMonth())
  const [dateTo,   setDateTo]   = useState(todayStr())
  const [empFilter, setEmpFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [page, setPage] = useState(1)

  // Edit state
  const [editDay, setEditDay] = useState<HRAttendanceDay | null>(null)
  const [createOpen, setCreateOpen] = useState(false)
  // ★ جلب مباشر ليوم محدد عند الحاجة (عندما لا يكون في الصفحة الحالية)
  const [fetchDayId, setFetchDayId] = useState<string | null>(null)
  useQuery({
    queryKey: ['hr-attendance-day-direct', fetchDayId],
    queryFn: async () => {
      if (!fetchDayId) return null
      const { data, error } = await _supabase
        .from('hr_attendance_days')
        .select(`*, employee:hr_employees!employee_id(id, full_name, employee_number), location_in:hr_work_locations!hr_attendance_days_location_in_id_fkey(id, name), location_out:hr_work_locations!hr_attendance_days_location_out_id_fkey(id, name)`)
        .eq('id', fetchDayId)
        .single()
      if (error || !data) { toast.error('تعذّر جلب اليوم'); setFetchDayId(null); return null }
      setEditDay(data as HRAttendanceDay)
      setFetchDayId(null)
      return data
    },
    enabled: !!fetchDayId,
    retry: false,
  })

  const { data: alerts = [] } = useHRAttendanceAlerts({ dateFrom, dateTo, status: 'open' })
  const { data: reviewSummary } = useAttendanceReviewSummary(dateFrom, dateTo)
  const resolveAlertMut = useResolveAttendanceAlert()
  const dismissAlertMut = useDismissAttendanceAlert()

  // FIX-04: فلترة الحالة في الـ Query بدلاً من Frontend
  const { data: attendanceResult, isLoading } = useQuery({
    queryKey: ['hr-attendance-days-admin', dateFrom, dateTo, empFilter, statusFilter, page],
    queryFn: () => getAttendanceDays({
      dateFrom, dateTo,
      employeeId: empFilter || undefined,
      status: statusFilter || undefined,
      page,
      pageSize: 50,
    }),
  })

  const { data: employees = [] } = useQuery({
    queryKey: ['hr-employees-list'],
    queryFn: () => getEmployees({ page: 1, pageSize: 300 }),
    select: d => d.data,
  })

  const days = attendanceResult?.data ?? []
  const filtered = days  // FIX-04: الفلترة تتم في الـ Query الآن

  // GAP-07: الإحصائيات من إجمالي count المرجع — تقديري بناء على الصفحة الحالية
  const stats = {
    present: days.filter(d => d.status === 'present').length,
    late:    days.filter(d => d.status === 'late').length,
    absent:  days.filter(d => d.status === 'absent_unauthorized' || d.status === 'absent_authorized').length,
    onLeave: days.filter(d => d.status === 'on_leave').length,
    total:   attendanceResult?.count ?? days.length,
  }
  const alertPreview = alerts.slice(0, 5)

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="سجل الحضور والانصراف"
        subtitle="مراجعة ومتابعة حضور الموظفين مع إمكانية التعديل اليدوي"
        breadcrumbs={[
          { label: 'الموارد البشرية', path: '/hr' },
          { label: 'الحضور' },
        ]}
        actions={
          <PermissionGuard permission="hr.attendance.edit">
            <Button icon={<Check size={14} />} onClick={() => setCreateOpen(true)}>
              إضافة يوم يدوي
            </Button>
          </PermissionGuard>
        }
      />

      {/* FIX-08: Responsive stat cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 'var(--space-3)', marginBottom: 'var(--space-4)' }}>
        <StatCard label="حاضر"   value={stats.present} color="var(--color-success)" icon={<Check size={18} />} />
        <StatCard label="متأخر"  value={stats.late}    color="var(--color-warning)" icon={<Clock size={18} />} />
        <StatCard label="غائب"   value={stats.absent}  color="var(--color-danger)"  icon={<X size={18} />} />
        <StatCard label="إجازة"  value={stats.onLeave} color="var(--color-info)"    icon={<Calendar size={18} />} />
      </div>

      {!!reviewSummary && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 'var(--space-3)', marginBottom: 'var(--space-4)' }}>
          <div style={{ padding: 'var(--space-4)', borderRadius: 'var(--radius-lg)', background: 'color-mix(in srgb, var(--color-warning) 8%, transparent)', border: '1px solid color-mix(in srgb, var(--color-warning) 25%, transparent)' }}>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>أيام تحتاج مراجعة</div>
            <div style={{ fontWeight: 800, fontSize: 'var(--text-xl)', color: 'var(--color-warning)' }}>{reviewSummary.unresolved_days}</div>
          </div>
          <div style={{ padding: 'var(--space-4)', borderRadius: 'var(--radius-lg)', background: 'color-mix(in srgb, var(--color-danger) 8%, transparent)', border: '1px solid color-mix(in srgb, var(--color-danger) 25%, transparent)' }}>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>أيام غير مغلقة</div>
            <div style={{ fontWeight: 800, fontSize: 'var(--text-xl)', color: 'var(--color-danger)' }}>{reviewSummary.open_day_unclosed}</div>
          </div>
          <div style={{ padding: 'var(--space-4)', borderRadius: 'var(--radius-lg)', background: 'color-mix(in srgb, var(--color-danger) 8%, transparent)', border: '1px solid color-mix(in srgb, var(--color-danger) 25%, transparent)' }}>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>تنبيهات مفتوحة</div>
            <div style={{ fontWeight: 800, fontSize: 'var(--text-xl)', color: 'var(--color-danger)' }}>{reviewSummary.open_alerts}</div>
          </div>
          <div style={{ padding: 'var(--space-4)', borderRadius: 'var(--radius-lg)', background: 'color-mix(in srgb, var(--color-info) 8%, transparent)', border: '1px solid color-mix(in srgb, var(--color-info) 25%, transparent)' }}>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>أذونات بلا عودة</div>
            <div style={{ fontWeight: 800, fontSize: 'var(--text-xl)', color: 'var(--color-info)' }}>{reviewSummary.permission_no_return}</div>
          </div>
          {reviewSummary.tracking_gap_days > 0 && (
            <div style={{ padding: 'var(--space-4)', borderRadius: 'var(--radius-lg)', background: 'color-mix(in srgb, var(--color-warning) 8%, transparent)', border: '1px solid color-mix(in srgb, var(--color-warning) 25%, transparent)' }}>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>فجوات تتبع / خروج نطاق</div>
              <div style={{ fontWeight: 800, fontSize: 'var(--text-xl)', color: 'var(--color-warning)' }}>{reviewSummary.tracking_gap_days}</div>
            </div>
          )}
        </div>
      )}

      {alertPreview.length > 0 && (
        <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginBottom: 'var(--space-3)' }}>
            <AlertCircle size={16} style={{ color: 'var(--color-warning)' }} />
            <div style={{ fontWeight: 700 }}>قائمة المراجعة اليومية</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginInlineStart: 'auto' }}>
              {alerts.length > 5 ? `عرض ${alertPreview.length} من ${alerts.length}` : `${alerts.length} تنبيه`}
            </div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
            {alertPreview.map((alert: HRAttendanceAlert) => {
              const isOpenDay = alert.alert_type === 'open_day_unclosed'
              const borderColor = isOpenDay ? 'var(--color-danger)' : alert.severity === 'high' ? 'var(--color-danger)' : 'var(--border-color)'
              return (
                <div
                  key={alert.id}
                  style={{
                    display: 'flex',
                    gap: 'var(--space-3)',
                    alignItems: 'flex-start',
                    justifyContent: 'space-between',
                    flexWrap: 'wrap',
                    padding: 'var(--space-3)',
                    borderRadius: 'var(--radius-md)',
                    border: `1px solid ${borderColor}`,
                    borderInlineStartWidth: isOpenDay ? 3 : 1,
                    background: isOpenDay
                      ? 'color-mix(in srgb, var(--color-danger) 4%, var(--bg-card))'
                      : 'var(--bg-card)',
                  }}
                >
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 6, flex: 1 }}>
                    <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
                      <strong>{alert.employee?.full_name ?? 'موظف'}</strong>
                      <Badge variant={ALERT_VARIANT[alert.severity]}>{ALERT_LABEL[alert.alert_type]}</Badge>
                    </div>
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                      {new Date(alert.started_at).toLocaleString('ar-EG-u-nu-latn')}
                    </div>
                    {alert.details ? (
                      <div style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>
                        {typeof alert.details === 'string' ? alert.details : JSON.stringify(alert.details)}
                      </div>
                    ) : null}
                  </div>

                  <div style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap', alignItems: 'flex-start' }}>
                    {isOpenDay && (
                      <Button
                        size="sm"
                        variant="secondary"
                        icon={<Edit2 size={12} />}
                        onClick={() => {
                          const dayId = alert.attendance_day_id
                          if (!dayId) return
                          const day = days.find(d => d.id === dayId)
                          if (day) {
                            setEditDay(day)
                          } else {
                            // ★ اليوم ليس في الصفحة الحالية → نجلبه مباشرة
                            setFetchDayId(dayId)
                          }
                        }}
                      >
                        تعديل اليوم
                      </Button>
                    )}
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() => resolveAlertMut.mutate({ id: alert.id, note: 'تمت مراجعة الحالة' })}
                      loading={resolveAlertMut.isPending}
                    >
                      تم الحل
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => dismissAlertMut.mutate({ id: alert.id, note: 'تم تجاوز التنبيه إداريًا' })}
                      loading={dismissAlertMut.isPending}
                    >
                      تجاهل مبرر
                    </Button>
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(160px, 1fr))', gap: 'var(--space-3)' }}>
          <Input label="من تاريخ" type="date" value={dateFrom} onChange={e => { setDateFrom(e.target.value); setPage(1) }} />
          <Input label="إلى تاريخ" type="date" value={dateTo}   onChange={e => { setDateTo(e.target.value);   setPage(1) }} />
          <Select
            label="الموظف"
            value={empFilter}
            onChange={e => { setEmpFilter(e.target.value); setPage(1) }}
            options={employees.map(e => ({ value: e.id, label: e.full_name }))}
            placeholder="كل الموظفين"
          />
          <Select
            label="الحالة"
            value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value); setPage(1) }}
            options={Object.entries(STATUS_LABEL).map(([k, v]) => ({ value: k, label: v }))}
            placeholder="كل الحالات"
          />
        </div>
      </div>

      {/* FIX-09: Mobile cards + Desktop table */}
      <div className="edara-card" style={{ padding: 0, overflow: 'hidden' }}>
        {isLoading ? (
          <div style={{ textAlign: 'center', padding: 'var(--space-8)', color: 'var(--text-muted)' }}>
            جارٍ تحميل سجلات الحضور...
          </div>
        ) : filtered.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 'var(--space-8)' }}>
            <Calendar size={40} style={{ opacity: 0.2, marginBottom: 8 }} />
            <div style={{ color: 'var(--text-muted)' }}>لا توجد سجلات في هذه الفترة</div>
          </div>
        ) : (
          <>
            {/* ─── Desktop: جدول قياسي DataTable ─── */}
            <div className="att-desktop-table">
              <DataTable<HRAttendanceDay>
                data={filtered}
                loading={isLoading}
                columns={[
                  {
                    key: 'date', label: 'التاريخ',
                    render: d => new Date(d.shift_date).toLocaleDateString('ar-EG', { weekday: 'short', day: 'numeric', month: 'short' }),
                    width: 120,
                  },
                  {
                    key: 'employee', label: 'الموظف',
                    render: d => (
                      <>
                        <div style={{ fontWeight: 600 }}>{d.employee?.full_name ?? '—'}</div>
                        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{d.employee?.employee_number}</div>
                      </>
                    )
                  },
                  {
                    key: 'punch_in', label: 'الحضور',
                    render: d => <span style={{ color: d.punch_in_time ? 'var(--color-success)' : 'var(--text-muted)' }} dir="ltr">{fmtTime(d.punch_in_time)}</span>
                  },
                  {
                    key: 'punch_out', label: 'الانصراف',
                    render: d => (
                      <span style={{ color: d.punch_out_time ? 'var(--text-secondary)' : 'var(--text-muted)' }} dir="ltr">
                        {fmtTime(d.punch_out_time)}
                        {d.is_auto_checkout && <span style={{ fontSize: 10, color: 'var(--color-warning)', marginInlineStart: 4 }}>تلقائي</span>}
                      </span>
                    )
                  },
                  {
                    key: 'late', label: 'تأخير',
                    render: d => d.late_minutes > 0
                      ? <span style={{ color: 'var(--color-warning)', fontWeight: 600 }}>{d.late_minutes} د</span>
                      : <span style={{ color: 'var(--text-muted)' }}>—</span>
                  },
                  {
                    key: 'status', label: 'الحالة',
                    render: d => <Badge variant={STATUS_VARIANT[d.status]}>{STATUS_LABEL[d.status]}</Badge>
                  },
                  {
                    key: 'review_status', label: 'المراجعة',
                    render: d => <Badge variant={REVIEW_VARIANT[d.review_status]}>{REVIEW_LABEL[d.review_status]}</Badge>
                  },
                  {
                    key: 'tracking_status', label: 'التتبع',
                    render: d => d.punch_in_time
                      ? <span style={{ fontSize: 'var(--text-xs)', color: d.tracking_status === 'outside_zone' ? 'var(--color-danger)' : d.tracking_status === 'stale' ? 'var(--color-warning)' : 'var(--text-muted)' }}>{TRACKING_LABEL[d.tracking_status]}</span>
                      : <span style={{ color: 'var(--text-muted)' }}>—</span>
                  },
                  {
                    key: 'location', label: 'الموقع',
                    render: d => d.location_in?.name
                      ? <span style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}><MapPin size={10} />{d.location_in.name}</span>
                      : <span style={{ color: 'var(--text-muted)' }}>—</span>
                  },
                  {
                    key: 'actions', label: '', width: 50,
                    render: d => (
                      <PermissionGuard permission="hr.attendance.edit">
                        <Button size="sm" variant="ghost" icon={<Edit2 size={12} />} onClick={() => setEditDay(d)} />
                      </PermissionGuard>
                    )
                  }
                ]}
              />
            </div>
            
            {/* ─── Mobile: بطاقات DataCard قياسية ─── */}
            <div className="att-mobile-cards" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
              {filtered.map(d => (
                <DataCard
                  key={d.id}
                  title={d.employee?.full_name ?? '—'}
                  subtitle={new Date(d.shift_date).toLocaleDateString('ar-EG', { weekday: 'short', day: 'numeric', month: 'short' })}
                  badge={<Badge variant={STATUS_VARIANT[d.status]}>{STATUS_LABEL[d.status]}</Badge>}
                  leading={
                    <div style={{
                      width: 40, height: 40, borderRadius: 'var(--radius-md)',
                      background: 'color-mix(in srgb, var(--color-primary) 10%, transparent)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--color-primary)'
                    }}>
                      <Clock size={18} />
                    </div>
                  }
                  metadata={[
                    { label: 'حضور', value: fmtTime(d.punch_in_time) },
                    { label: 'انصراف', value: fmtTime(d.punch_out_time) },
                    ...(d.late_minutes > 0 ? [{ label: 'تأخير', value: `${d.late_minutes} د`, highlight: true }] : []),
                    { label: 'المراجعة', value: REVIEW_LABEL[d.review_status], highlight: d.review_status === 'needs_review' },
                    ...(d.punch_in_time ? [{ label: 'التتبع', value: TRACKING_LABEL[d.tracking_status], highlight: d.tracking_status === 'stale' || d.tracking_status === 'outside_zone' }] : []),
                    ...(d.location_in?.name ? [{ label: 'موقع', value: d.location_in.name }] : []),
                  ]}
                  actions={
                    <PermissionGuard permission="hr.attendance.edit">
                      <Button size="sm" variant="secondary" style={{ width: '100%', justifyContent: 'center' }} onClick={() => setEditDay(d)}>
                        <Edit2 size={12} style={{ marginInlineEnd: 4 }} /> تعديل
                      </Button>
                    </PermissionGuard>
                  }
                />
              ))}
            </div>
          </>
        )}

        {/* Pagination */}
        {(attendanceResult?.totalPages ?? 1) > 1 && (
          <div style={{ display: 'flex', justifyContent: 'center', gap: 'var(--space-2)', padding: 'var(--space-3)', borderTop: '1px solid var(--border-color)' }}>
            <Button size="sm" variant="ghost" onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}>السابق</Button>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)', alignSelf: 'center' }}>
              صفحة {page} / {attendanceResult?.totalPages}
            </span>
            <Button size="sm" variant="ghost" onClick={() => setPage(p => p + 1)} disabled={page >= (attendanceResult?.totalPages ?? 1)}>التالي</Button>
          </div>
        )}
      </div>

      <style>{`
        @media (max-width: 767px) {
          .att-desktop-table { display: none !important; }
        }
        @media (min-width: 768px) {
          .att-mobile-cards { display: none !important; }
        }
      `}</style>

      {/* Edit Modal */}
      <ManualEditModal
        day={editDay}
        onClose={() => setEditDay(null)}
        onSaved={() => {
          qc.invalidateQueries({ queryKey: ['hr-attendance-days-admin'] })
          qc.invalidateQueries({ queryKey: ['hr-attendance-alerts'] })
          qc.invalidateQueries({ queryKey: ['hr-attendance-review-summary'] })
        }}
      />
      <CreateManualDayModal
        open={createOpen}
        employees={employees.map(e => ({ id: e.id, full_name: e.full_name }))}
        onClose={() => setCreateOpen(false)}
        onSaved={() => {
          qc.invalidateQueries({ queryKey: ['hr-attendance-days-admin'] })
          qc.invalidateQueries({ queryKey: ['hr-attendance-alerts'] })
          qc.invalidateQueries({ queryKey: ['hr-attendance-review-summary'] })
        }}
      />
    </div>
  )
}
