import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CalendarClock, Clock3, Edit2, Plus, ShieldCheck } from 'lucide-react'
import { toast } from 'sonner'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Input from '@/components/ui/Input'
import Select from '@/components/ui/Select'
import Spinner from '@/components/ui/Spinner'
import { useAuthStore } from '@/stores/auth-store'
import {
  saveCompanyWorkScheduleVersion,
  updateFutureCompanyWorkScheduleVersion,
} from '@/lib/services/hrWorkSchedules'
import {
  getCompanyWorkScheduleFeatureState,
  getCompanyWorkScheduleVersions,
} from '@/lib/services/hrCompanyWorkSchedules'
import {
  HR_WORK_WEEK_DAY_LABELS,
  type HRCompanyWorkScheduleVersion,
} from '@/lib/types/hrWorkSchedules'
import type { HRDayOfWeek } from '@/lib/types/hr'
import {
  getCairoDateISO,
  getNextCairoDateISO,
  normalizeScheduleTime,
  timeToMinutes,
} from '@/lib/validations/hrWorkSchedules'

const queryKeys = {
  feature: ['hr', 'company-work-schedules', 'feature'] as const,
  versions: ['hr', 'company-work-schedules', 'versions'] as const,
}

const WEEKDAY_OPTIONS: { value: HRDayOfWeek; label: string }[] = [
  'saturday',
  'sunday',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
].map(value => ({ value: value as HRDayOfWeek, label: HR_WORK_WEEK_DAY_LABELS[value as HRDayOfWeek] }))

interface FormState {
  effective_from: string
  start_time: string
  end_time: string
  weekly_off_day: HRDayOfWeek
  notes: string
}

function formatDate(value: string | null): string {
  if (!value) return 'مستمر'
  return new Date(`${value}T12:00:00Z`).toLocaleDateString('ar-EG-u-nu-latn', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

function formatHours(minutes: number): string {
  const hours = minutes / 60
  return Number.isInteger(hours) ? `${hours} ساعة` : `${hours.toFixed(1)} ساعة`
}

function validateForm(form: FormState, today: string): string | null {
  const start = normalizeScheduleTime(form.start_time)
  const end = normalizeScheduleTime(form.end_time)

  if (!form.effective_from || form.effective_from <= today) {
    return 'تاريخ بدء النسخة يجب أن يكون بعد اليوم بتوقيت القاهرة'
  }

  if (!start || !end || !/^\d{2}:\d{2}$/.test(start) || !/^\d{2}:\d{2}$/.test(end)) {
    return 'وقت البداية والنهاية مطلوبان بصيغة HH:MM'
  }

  if (timeToMinutes(end) <= timeToMinutes(start)) {
    return 'وقت نهاية الدوام يجب أن يكون بعد وقت البداية'
  }

  if (form.notes.trim().length > 500) {
    return 'الملاحظات لا يمكن أن تتجاوز 500 حرف'
  }

  return null
}

export default function CompanyWorkScheduleSettingsCard() {
  const can = useAuthStore(state => state.can)
  const queryClient = useQueryClient()
  const cairoToday = getCairoDateISO()
  const tomorrow = getNextCairoDateISO()
  const canEdit = can('settings.update')

  const [editorOpen, setEditorOpen] = useState(false)
  const [editing, setEditing] = useState<HRCompanyWorkScheduleVersion | null>(null)
  const [form, setForm] = useState<FormState>({
    effective_from: tomorrow,
    start_time: '11:00',
    end_time: '19:00',
    weekly_off_day: 'friday',
    notes: '',
  })

  const featureQuery = useQuery({
    queryKey: queryKeys.feature,
    queryFn: getCompanyWorkScheduleFeatureState,
    staleTime: 60_000,
  })

  const installed = featureQuery.data?.installed === true
  const featureEnabled = featureQuery.data?.enabled === true

  const versionsQuery = useQuery({
    queryKey: queryKeys.versions,
    queryFn: getCompanyWorkScheduleVersions,
    enabled: installed,
  })

  const versions = versionsQuery.data ?? []
  const currentVersion = useMemo(
    () => versions.find(version =>
      version.effective_from <= cairoToday
      && (!version.effective_to || version.effective_to >= cairoToday)
    ),
    [versions, cairoToday]
  )
  const futureVersion = useMemo(
    () => versions.find(version => version.status === 'active' && version.effective_from > cairoToday),
    [versions, cairoToday]
  )

  const resetEditor = () => {
    setEditorOpen(false)
    setEditing(null)
    setForm({
      effective_from: tomorrow,
      start_time: currentVersion?.start_time ?? '11:00',
      end_time: currentVersion?.end_time ?? '19:00',
      weekly_off_day: currentVersion?.weekly_off_day ?? 'friday',
      notes: '',
    })
  }

  const startCreate = () => {
    setEditing(null)
    setForm({
      effective_from: futureVersion
        ? futureVersion.effective_from
        : tomorrow,
      start_time: futureVersion?.start_time ?? currentVersion?.start_time ?? '11:00',
      end_time: futureVersion?.end_time ?? currentVersion?.end_time ?? '19:00',
      weekly_off_day: futureVersion?.weekly_off_day ?? currentVersion?.weekly_off_day ?? 'friday',
      notes: '',
    })
    setEditorOpen(true)
  }

  const startEdit = (version: HRCompanyWorkScheduleVersion) => {
    setEditing(version)
    setForm({
      effective_from: version.effective_from,
      start_time: version.start_time,
      end_time: version.end_time,
      weekly_off_day: version.weekly_off_day,
      notes: version.notes ?? '',
    })
    setEditorOpen(true)
  }

  const mutation = useMutation({
    mutationFn: async () => {
      const error = validateForm(form, cairoToday)
      if (error) throw new Error(error)

      const input = {
        effective_from: form.effective_from,
        start_time: form.start_time,
        end_time: form.end_time,
        weekly_off_day: form.weekly_off_day,
        notes: form.notes.trim() || null,
      }

      return editing
        ? updateFutureCompanyWorkScheduleVersion(editing.id, input)
        : saveCompanyWorkScheduleVersion(input)
    },
    onSuccess: async result => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.versions })
      toast.success(
        result.feature_enabled
          ? 'تم حفظ نسخة جدول الشركة المستقبلية'
          : 'تم حفظ النسخة للمراجعة، ولن تؤثر تشغيليًا قبل التفعيل النهائي'
      )
      resetEditor()
    },
    onError: error => {
      toast.error(error instanceof Error ? error.message : String(error))
    },
  })

  if (featureQuery.isLoading) {
    return <div style={{ display: 'flex', justifyContent: 'center', padding: 'var(--space-5)' }}><Spinner /></div>
  }

  if (!installed) return null

  if (versionsQuery.isLoading) {
    return <div style={{ display: 'flex', justifyContent: 'center', padding: 'var(--space-5)' }}><Spinner /></div>
  }

  if (featureQuery.error || versionsQuery.error) {
    return (
      <div className="form-card" style={{ borderColor: 'var(--color-danger)' }}>
        <strong>تعذر تحميل سجل مواعيد الشركة</strong>
        <p style={{ color: 'var(--text-muted)', marginTop: 6 }}>
          لم يتم تنفيذ أي تغيير. راجع اكتمال الميجريشنات والصلاحيات.
        </p>
      </div>
    )
  }

  return (
    <section className="form-card" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
      <div style={{ display: 'flex', gap: 'var(--space-3)', alignItems: 'flex-start', flexWrap: 'wrap' }}>
        <div style={{ flex: 1, minWidth: 240 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <CalendarClock size={18} />
            <strong>سجل مواعيد الشركة المؤرخ</strong>
            <Badge variant={featureEnabled ? 'success' : 'warning'}>
              {featureEnabled ? 'مفعّل' : 'إعداد ومراجعة'}
            </Badge>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)', marginTop: 7 }}>
            أي تغيير تشغيلي يُحفظ كنسخة مستقبلية؛ لا يعاد تفسير الحضور أو الرواتب السابقة.
          </p>
        </div>

        {canEdit && (
          <Button
            size="sm"
            icon={futureVersion ? <Edit2 size={14} /> : <Plus size={14} />}
            onClick={() => futureVersion ? startEdit(futureVersion) : startCreate()}
            disabled={mutation.isPending}
          >
            {futureVersion ? 'تصحيح النسخة المستقبلية' : 'نسخة مستقبلية جديدة'}
          </Button>
        )}
      </div>

      {currentVersion && (
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))',
          gap: 'var(--space-3)',
          padding: 'var(--space-3)',
          border: '1px solid var(--border-color)',
          borderRadius: 'var(--radius-lg)',
          background: 'var(--bg-surface-2)',
        }}>
          <div><span className="setting-desc">الفترة الحالية</span><div>{formatDate(currentVersion.effective_from)} — {formatDate(currentVersion.effective_to)}</div></div>
          <div><span className="setting-desc">الدوام</span><div dir="ltr">{currentVersion.start_time} — {currentVersion.end_time}</div></div>
          <div><span className="setting-desc">مدة اليوم</span><div>{formatHours(currentVersion.scheduled_minutes)}</div></div>
          <div><span className="setting-desc">العطلة الأسبوعية</span><div>{HR_WORK_WEEK_DAY_LABELS[currentVersion.weekly_off_day]}</div></div>
        </div>
      )}

      {futureVersion && (
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: 'var(--space-3)',
          flexWrap: 'wrap',
          padding: 'var(--space-3)',
          border: '1px solid color-mix(in srgb, var(--color-warning) 35%, var(--border-color))',
          borderRadius: 'var(--radius-lg)',
        }}>
          <Clock3 size={17} />
          <strong>نسخة مخططة من {formatDate(futureVersion.effective_from)}</strong>
          <span dir="ltr">{futureVersion.start_time} — {futureVersion.end_time}</span>
          <span>{formatHours(futureVersion.scheduled_minutes)}</span>
          <span>العطلة: {HR_WORK_WEEK_DAY_LABELS[futureVersion.weekly_off_day]}</span>
        </div>
      )}

      {editorOpen && (
        <form
          onSubmit={event => {
            event.preventDefault()
            mutation.mutate()
          }}
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
            gap: 'var(--space-3)',
            padding: 'var(--space-4)',
            border: '1px solid var(--border-color)',
            borderRadius: 'var(--radius-lg)',
          }}
        >
          <Input
            label="تاريخ بدء التطبيق"
            type="date"
            min={tomorrow}
            value={form.effective_from}
            disabled={Boolean(editing)}
            onChange={event => setForm(current => ({ ...current, effective_from: event.target.value }))}
          />
          <Input
            label="وقت بداية الدوام"
            type="time"
            value={form.start_time}
            onChange={event => setForm(current => ({ ...current, start_time: event.target.value }))}
          />
          <Input
            label="وقت نهاية الدوام"
            type="time"
            value={form.end_time}
            onChange={event => setForm(current => ({ ...current, end_time: event.target.value }))}
          />
          <Select
            label="العطلة الأسبوعية"
            value={form.weekly_off_day}
            options={WEEKDAY_OPTIONS}
            onChange={event => setForm(current => ({ ...current, weekly_off_day: event.target.value as HRDayOfWeek }))}
          />
          <div style={{ gridColumn: '1 / -1' }}>
            <Input
              label="ملاحظات"
              value={form.notes}
              maxLength={500}
              onChange={event => setForm(current => ({ ...current, notes: event.target.value }))}
            />
          </div>
          <div style={{ gridColumn: '1 / -1', display: 'flex', gap: 'var(--space-2)', justifyContent: 'flex-end' }}>
            <Button type="button" variant="secondary" onClick={resetEditor} disabled={mutation.isPending}>
              إلغاء
            </Button>
            <Button type="submit" icon={<ShieldCheck size={14} />} loading={mutation.isPending}>
              حفظ النسخة المستقبلية
            </Button>
          </div>
        </form>
      )}
    </section>
  )
}
