import { useState } from 'react'
import { Calendar, Edit2, Check, X, Clock, MapPin, AlertCircle } from 'lucide-react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { getAttendanceDays, upsertAttendanceDay } from '@/lib/services/hr'
import { getEmployees, getDepartments } from '@/lib/services/hr'
import type { HRAttendanceDay, HRAttendanceDayInput, HRAttendanceStatus } from '@/lib/types/hr'
import PageHeader from '@/components/shared/PageHeader'
import Input from '@/components/ui/Input'
import Select from '@/components/ui/Select'
import Button from '@/components/ui/Button'
import Badge from '@/components/ui/Badge'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import PermissionGuard from '@/components/shared/PermissionGuard'

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

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="سجل الحضور والانصراف"
        subtitle="مراجعة ومتابعة حضور الموظفين مع إمكانية التعديل اليدوي"
        breadcrumbs={[
          { label: 'الموارد البشرية', path: '/hr' },
          { label: 'الحضور' },
        ]}
      />

      {/* FIX-08: Responsive stat cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(140px, 1fr))', gap: 'var(--space-3)', marginBottom: 'var(--space-4)' }}>
        {[
          { label: 'حاضر',   count: stats.present, color: 'var(--color-success)' },
          { label: 'متأخر',  count: stats.late,    color: 'var(--color-warning)' },
          { label: 'غائب',   count: stats.absent,  color: 'var(--color-danger)'  },
          { label: 'إجازة',  count: stats.onLeave, color: 'var(--color-info)'    },
        ].map(s => (
          <div key={s.label} className="edara-card" style={{ padding: 'var(--space-3)', textAlign: 'center', borderTop: `3px solid ${s.color}` }}>
            <div style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: s.color }}>{s.count}</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{s.label}</div>
          </div>
        ))}
      </div>

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
            {/* ─── Mobile: بطاقات للشاشات الصغيرة ─── */}
            <div className="att-mobile-cards">
              {filtered.map(d => (
                <div key={d.id} style={{
                  padding: 'var(--space-3)',
                  borderBottom: '1px solid var(--border-color)',
                  display: 'flex', flexDirection: 'column', gap: 'var(--space-2)',
                }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div>
                      <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{d.employee?.full_name ?? '—'}</div>
                      <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                        {new Date(d.shift_date).toLocaleDateString('ar-EG', { weekday: 'short', day: 'numeric', month: 'short' })}
                      </div>
                    </div>
                    <Badge variant={STATUS_VARIANT[d.status]}>{STATUS_LABEL[d.status]}</Badge>
                  </div>
                  <div style={{ display: 'flex', gap: 'var(--space-4)', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    <span>حضور: <strong style={{ color: d.punch_in_time ? 'var(--color-success)' : undefined }}>{fmtTime(d.punch_in_time)}</strong></span>
                    <span>انصراف: <strong>{fmtTime(d.punch_out_time)}</strong></span>
                    {d.late_minutes > 0 && <span style={{ color: 'var(--color-warning)' }}>تأخير: {d.late_minutes} د</span>}
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    {d.location_in?.name
                      ? <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 4 }}><MapPin size={10} />{d.location_in.name}</span>
                      : <span />
                    }
                    <PermissionGuard permission="hr.attendance.edit">
                      <Button size="sm" variant="ghost" icon={<Edit2 size={12} />} onClick={() => setEditDay(d)} />
                    </PermissionGuard>
                  </div>
                </div>
              ))}
            </div>

            {/* ─── Desktop: جدول تقليدي ─── */}
            <div className="att-desktop-table">
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--text-sm)', minWidth: 660 }}>
                <thead>
                  <tr style={{ background: 'var(--bg-surface-2)' }}>
                    {['التاريخ', 'الموظف', 'الحضور', 'الانصراف', 'تأخير', 'الحالة', 'الموقع', ''].map(h => (
                      <th key={h} style={{ padding: 'var(--space-2) var(--space-3)', textAlign: 'right', color: 'var(--text-muted)', fontSize: 'var(--text-xs)', borderBottom: '1px solid var(--border-color)', whiteSpace: 'nowrap' }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {filtered.map(d => (
                    <tr key={d.id} style={{ borderBottom: '1px solid var(--border-color)' }}>
                      <td style={{ padding: 'var(--space-2) var(--space-3)', whiteSpace: 'nowrap', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                        {new Date(d.shift_date).toLocaleDateString('ar-EG', { weekday: 'short', day: 'numeric', month: 'short' })}
                      </td>
                      <td style={{ padding: 'var(--space-2) var(--space-3)' }}>
                        <div style={{ fontWeight: 600 }}>{d.employee?.full_name ?? '—'}</div>
                        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{d.employee?.employee_number}</div>
                      </td>
                      <td style={{ padding: 'var(--space-2) var(--space-3)', fontVariantNumeric: 'tabular-nums', direction: 'ltr', textAlign: 'left' }}>
                        <span style={{ color: d.punch_in_time ? 'var(--color-success)' : 'var(--text-muted)' }}>
                          {fmtTime(d.punch_in_time)}
                        </span>
                      </td>
                      <td style={{ padding: 'var(--space-2) var(--space-3)', direction: 'ltr', textAlign: 'left' }}>
                        <span style={{ color: d.punch_out_time ? 'var(--text-secondary)' : 'var(--text-muted)' }}>
                          {fmtTime(d.punch_out_time)}
                          {d.is_auto_checkout && <span style={{ fontSize: 10, color: 'var(--color-warning)', marginRight: 4 }}>تلقائي</span>}
                        </span>
                      </td>
                      <td style={{ padding: 'var(--space-2) var(--space-3)', textAlign: 'center' }}>
                        {d.late_minutes > 0
                          ? <span style={{ color: 'var(--color-warning)', fontWeight: 600 }}>{d.late_minutes} د</span>
                          : <span style={{ color: 'var(--text-muted)' }}>—</span>
                        }
                      </td>
                      <td style={{ padding: 'var(--space-2) var(--space-3)' }}>
                        <Badge variant={STATUS_VARIANT[d.status]}>{STATUS_LABEL[d.status]}</Badge>
                      </td>
                      <td style={{ padding: 'var(--space-2) var(--space-3)', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                        {d.location_in?.name
                          ? <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}><MapPin size={10} />{d.location_in.name}</span>
                          : '—'
                        }
                      </td>
                      <td style={{ padding: 'var(--space-2) var(--space-3)' }}>
                        <PermissionGuard permission="hr.attendance.edit">
                          <Button
                            size="sm"
                            variant="ghost"
                            icon={<Edit2 size={12} />}
                            onClick={() => setEditDay(d)}
                          />
                        </PermissionGuard>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
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
        onSaved={() => qc.invalidateQueries({ queryKey: ['hr-attendance-days-admin'] })}
      />
    </div>
  )
}

