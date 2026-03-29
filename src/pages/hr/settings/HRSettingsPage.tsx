import { useState, useEffect } from 'react'
import {
  Settings, Building2, Briefcase, MapPin, Calendar, AlertTriangle,
  Plus, Edit2, Check, X, Save, ToggleLeft, ToggleRight, Trash2,
} from 'lucide-react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { getSettings, updateSettings } from '@/lib/services/settings'
import {
  getDepartments, createDepartment, updateDepartment,
  getPositions,   createPosition,
  getWorkLocations, createWorkLocation, updateWorkLocation,
  getPublicHolidays, createPublicHoliday, deletePublicHoliday,
  getPenaltyRules,
} from '@/lib/services/hr'
import type {
  HRDepartment, HRDepartmentInput,
  HRPosition, HRPositionInput,
  HRWorkLocation, HRWorkLocationInput,
  HRPublicHoliday, HRPublicHolidayInput,
  HRPenaltyRule,
} from '@/lib/types/hr'
import PageHeader from '@/components/shared/PageHeader'
import Button from '@/components/ui/Button'
import Input from '@/components/ui/Input'
import Select from '@/components/ui/Select'
import Badge from '@/components/ui/Badge'
import PermissionGuard from '@/components/shared/PermissionGuard'

// ─── Tab types ──────────────────────────────
type Tab = 'settings' | 'departments' | 'positions' | 'locations' | 'holidays' | 'penalties'

const TABS: { id: Tab; label: string; icon: React.ReactNode }[] = [
  { id: 'settings',    label: 'إعدادات HR',         icon: <Settings size={15} /> },
  { id: 'departments', label: 'الأقسام',             icon: <Building2 size={15} /> },
  { id: 'positions',   label: 'المسميات الوظيفية',  icon: <Briefcase size={15} /> },
  { id: 'locations',   label: 'مواقع الحضور GPS',   icon: <MapPin size={15} /> },
  { id: 'holidays',    label: 'العطل الرسمية',       icon: <Calendar size={15} /> },
  { id: 'penalties',   label: 'قواعد الجزاءات',     icon: <AlertTriangle size={15} /> },
]

// ─── HR setting keys — مجمّعة بفئات ────────────────────────
const HR_SETTING_SECTIONS = [
  {
    id: 'legal',
    title: 'الامتثال القانوني',
    icon: '🏛️',
    settings: [
      { key: 'hr.social_insurance.enabled',       label: 'التأمين الاجتماعي',          type: 'boolean', desc: 'خصم 11% من الموظف + 18.75% من الشركة' },
      { key: 'hr.social_insurance.employee_rate', label: 'نسبة اشتراك الموظف %',       type: 'number',  desc: 'الافتراضي: 11' },
      { key: 'hr.social_insurance.employer_rate', label: 'نسبة اشتراك صاحب العمل %',  type: 'number',  desc: 'الافتراضي: 18.75' },
      { key: 'hr.income_tax.enabled',             label: 'ضريبة كسب العمل',            type: 'boolean', desc: 'تطبيق الشرائح التصاعدية تلقائياً' },
      { key: 'hr.health_insurance.enabled',       label: 'التأمين الصحي',              type: 'boolean', desc: 'خصم قيمة التأمين الصحي الشهرية' },
      { key: 'hr.health_insurance.amount',        label: 'قيمة خصم التأمين الصحي ج.م', type: 'number', desc: 'الافتراضي: 0' },
    ],
  },
  {
    id: 'workhours',
    title: 'أوقات العمل',
    icon: '⏰',
    settings: [
      { key: 'hr.work_start_time',    label: 'وقت بداية الدوام',           type: 'text',    desc: 'الافتراضي: 08:00' },
      { key: 'hr.work_end_time',      label: 'وقت نهاية الدوام',           type: 'text',    desc: 'الافتراضي: 17:00' },
      { key: 'hr.work_hours_per_day', label: 'ساعات العمل اليومية',        type: 'number',  desc: 'الافتراضي: 8 ساعات' },
      { key: 'hr.late_grace_minutes', label: 'دقائق التسامح في التأخير',   type: 'number',  desc: 'الافتراضي: 15 دقيقة' },
      { key: 'hr.payroll_day',        label: 'يوم صرف الراتب شهرياً',      type: 'number',  desc: 'الافتراضي: 28' },
      { key: 'hr.weekly_off_day',     label: 'يوم العطلة الأسبوعية',       type: 'select',  desc: 'الافتراضي للشركة',
        options: [
          { value: 'friday',   label: 'الجمعة' },
          { value: 'saturday', label: 'السبت' },
          { value: 'sunday',   label: 'الأحد' },
          { value: 'thursday', label: 'الخميس' },
        ],
      },
      { key: 'hr.overtime_rate',         label: 'معامل الإضافي (أيام عمل)',  type: 'number', desc: 'الافتراضي: 1.5' },
      { key: 'hr.overtime_holiday_rate', label: 'معامل الإضافي (العطلات)',   type: 'number', desc: 'الافتراضي: 1.75' },
      { key: 'hr.auto_checkout_minutes', label: 'دقائق الانصراف التلقائي',  type: 'number', desc: 'الافتراضي: 15 دقيقة' },
    ],
  },
  {
    id: 'leaves',
    title: 'الإجازات والأذونات',
    icon: '📅',
    settings: [
      { key: 'hr.annual_leave_days',       label: 'رصيد الإجازة السنوية (يوم)',  type: 'number', desc: 'الافتراضي: 21 يوم' },
      { key: 'hr.sick_leave_days',         label: 'رصيد الإجازة المرضية (يوم)', type: 'number', desc: 'الافتراضي: 15 يوم' },
      { key: 'hr.max_early_leave_permits', label: 'حد أذونات الانصراف شهرياً',  type: 'number', desc: 'الافتراضي: 2 مرة' },
    ],
  },
  {
    id: 'gps',
    title: 'الحضور GPS',
    icon: '📡',
    settings: [
      { key: 'hr.attendance_gps_required',      label: 'GPS إلزامي لتسجيل الحضور',  type: 'boolean', desc: 'إذا كان مفعلاً، يرفض الحضور بدون موقع' },
      { key: 'hr.attendance_gps_radius_meters', label: 'نطاق GPS المقبول (متر)',     type: 'number',  desc: 'الافتراضي: 200 متر' },
      { key: 'hr.gps_accuracy_threshold_meters',label: 'أقصى دقة GPS مقبولة (متر)', type: 'number',  desc: 'الافتراضي: 150 متر' },
    ],
  },
  {
    id: 'advances',
    title: 'السلف',
    icon: '💰',
    settings: [
      { key: 'hr.advance_max_months_salary',   label: 'أقصى سلفة (أشهر راتب)',     type: 'number', desc: 'الافتراضي: شهر واحد' },
      { key: 'hr.advance_max_installments',    label: 'أقصى عدد أقساط السلفة',     type: 'number', desc: 'الافتراضي: 6 أشهر' },
      { key: 'hr.advance_min_installments',    label: 'أقل عدد أقساط مسموح',       type: 'number', desc: 'الافتراضي: 1' },
      { key: 'hr.advance_max_active',          label: 'أقصى سلف نشطة معاً',        type: 'number', desc: 'الافتراضي: 1' },
      { key: 'hr.instant_advance_max_percent', label: 'أقصى نسبة سلفة فورية %',   type: 'number', desc: 'الافتراضي: 50%' },
    ],
  },
] as const

// ════════════════════════════════════════════
// TAB: Company Settings
// ════════════════════════════════════════════
function SettingsTab() {
  const qc = useQueryClient()
  // جلب الإعدادات — نتحاشى fallback [] في الديبندنسي لأنها تنشئ reference جديدة في كل render
  const { data: settingsData, isLoading } = useQuery({
    queryKey: ['settings', 'hr'],
    queryFn: () => getSettings('hr'),
  })

  const [local, setLocal] = useState<Record<string, string>>({})
  const [dirty, setDirty] = useState(false)

  // استخدم settingsData (ليس [] fallback) في dependency array
  // React Query يرجع نفس reference للبيانات الثابتة
  useEffect(() => {
    if (!settingsData?.length) return
    const map: Record<string, string> = {}
    for (const s of settingsData) map[s.key] = s.value
    setLocal(map)
    setDirty(false)
  }, [settingsData])

  const saveMut = useMutation({
    mutationFn: () => updateSettings(Object.entries(local).map(([key, value]) => ({ key, value }))),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['settings'] })
      toast.success('تم حفظ الإعدادات')
      setDirty(false)
    },
    onError: (e: Error) => toast.error(e.message),
  })

  const set = (key: string, value: string) => {
    setLocal(p => ({ ...p, [key]: value }))
    setDirty(true)
  }

  if (isLoading) return <div className="settings-loading">جارٍ التحميل...</div>

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 'var(--space-4)' }}>
        <Button icon={<Save size={15} />} onClick={() => saveMut.mutate()} loading={saveMut.isPending} disabled={!dirty}>
          حفظ التغييرات
        </Button>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-5)' }}>
        {HR_SETTING_SECTIONS.map(section => (
          <div key={section.id} style={{
            border: '1px solid var(--border-color)',
            borderRadius: 'var(--radius-lg)',
            overflow: 'hidden',
          }}>
            {/* رأس الفئة */}
            <div style={{
              display: 'flex', alignItems: 'center', gap: 'var(--space-2)',
              padding: 'var(--space-3) var(--space-4)',
              background: 'var(--bg-surface-2)',
              borderBottom: '1px solid var(--border-color)',
              fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--text-primary)',
            }}>
              <span>{section.icon}</span>
              <span>{section.title}</span>
              <span style={{
                marginRight: 'auto', fontSize: 'var(--text-xs)',
                color: 'var(--text-muted)', fontWeight: 400,
              }}>
                {section.settings.length} إعداد
              </span>
            </div>

            {/* صفوف الإعدادات */}
            <div style={{ display: 'flex', flexDirection: 'column' }}>
              {section.settings.map((cfg, i) => {
                const val = local[cfg.key] ?? ''
                return (
                  <div key={cfg.key} className="setting-row" style={{
                    borderRadius: 0,
                    border: 'none',
                    borderBottom: i < section.settings.length - 1 ? '1px solid var(--border-color)' : 'none',
                  }}>
                    <div className="setting-info">
                      <span className="setting-label">{cfg.label}</span>
                      <span className="setting-desc">{cfg.desc}</span>
                    </div>
                    <div className="setting-control">
                      {cfg.type === 'boolean' ? (
                        <button
                          id={`setting-${cfg.key}`}
                          className="toggle-btn"
                          onClick={() => set(cfg.key, val === 'true' ? 'false' : 'true')}
                        >
                          {val === 'true'
                            ? <><ToggleRight size={22} color="var(--color-success)" /> <span style={{ color: 'var(--color-success)' }}>مفعّل</span></>
                            : <><ToggleLeft size={22} color="var(--text-muted)" /> <span style={{ color: 'var(--text-muted)' }}>موقوف</span></>
                          }
                        </button>
                      ) : cfg.type === 'select' ? (
                        <Select
                          value={val}
                          onChange={e => set(cfg.key, e.target.value)}
                          options={'options' in cfg ? [...cfg.options] : []}
                          style={{ minWidth: 130 }}
                        />
                      ) : cfg.type === 'text' ? (
                        <Input
                          type="text"
                          value={val}
                          onChange={e => set(cfg.key, e.target.value)}
                          style={{ width: 100, textAlign: 'center' }}
                          dir="ltr"
                          placeholder={cfg.desc.split('الافتراضي: ')[1]?.split(' ')[0] ?? ''}
                        />
                      ) : (
                        <Input
                          type="number"
                          value={val}
                          onChange={e => set(cfg.key, e.target.value)}
                          style={{ width: 100, textAlign: 'center' }}
                          dir="ltr"
                        />
                      )}
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        ))}
      </div>

      {dirty && (
        <div style={{
          position: 'sticky', bottom: 'var(--space-4)',
          display: 'flex', justifyContent: 'flex-end',
          marginTop: 'var(--space-4)',
        }}>
          <div style={{
            display: 'flex', gap: 'var(--space-2)',
            padding: 'var(--space-3) var(--space-4)',
            background: 'var(--bg-card)',
            border: '1px solid var(--border-color)',
            borderRadius: 'var(--radius-xl)',
            boxShadow: '0 4px 20px rgba(0,0,0,0.15)',
          }}>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)', display: 'flex', alignItems: 'center' }}>
              لديك تغييرات غير محفوظة
            </span>
            <Button icon={<Save size={14} />} onClick={() => saveMut.mutate()} loading={saveMut.isPending}>
              حفظ الآن
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}

// ════════════════════════════════════════════
// TAB: Departments
// ════════════════════════════════════════════
function DepartmentsTab() {
  const qc = useQueryClient()
  const { data: depts = [], isLoading } = useQuery({
    queryKey: ['hr-departments-all'],
    queryFn: () => getDepartments(false), // كل الأقسام بما فيها غير النشطة
  })

  const [editing, setEditing] = useState<HRDepartment | null>(null)
  const [adding, setAdding]   = useState(false)
  const [form, setForm]       = useState<HRDepartmentInput>({ name: '', is_active: true })

  const createMut = useMutation({
    mutationFn: () => createDepartment(form),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['hr-departments'] }); qc.invalidateQueries({ queryKey: ['hr-departments-all'] }); setAdding(false); setForm({ name: '', is_active: true }); toast.success('تم إضافة القسم') },
    onError: (e: Error) => toast.error(e.message),
  })
  const updateMut = useMutation({
    mutationFn: () => updateDepartment(editing!.id, form),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['hr-departments'] }); qc.invalidateQueries({ queryKey: ['hr-departments-all'] }); setEditing(null); toast.success('تم تحديث القسم') },
    onError: (e: Error) => toast.error(e.message),
  })

  const startEdit = (d: HRDepartment) => {
    setEditing(d)
    setForm({ name: d.name, name_en: d.name_en ?? undefined, code: d.code ?? undefined, is_active: d.is_active })
  }

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 'var(--space-4)' }}>
        <Button icon={<Plus size={15} />} onClick={() => { setAdding(true); setForm({ name: '', is_active: true }) }}>
          قسم جديد
        </Button>
      </div>

      {/* نموذج الإضافة/التعديل */}
      {(adding || editing) && (
        <div className="form-card">
          <div className="form-card-title">{adding ? 'إضافة قسم جديد' : 'تعديل القسم'}</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
            <Input label="اسم القسم" required value={form.name} onChange={e => setForm(p => ({ ...p, name: e.target.value }))} />
            <Input label="الاسم بالإنجليزية" value={form.name_en ?? ''} onChange={e => setForm(p => ({ ...p, name_en: e.target.value || null }))} />
            <Input label="الكود" value={form.code ?? ''} onChange={e => setForm(p => ({ ...p, code: e.target.value || null }))} placeholder="SALES" />
          </div>
          <div style={{ display: 'flex', gap: 'var(--space-2)', marginTop: 'var(--space-3)' }}>
            <Button size="sm" icon={<Check size={14} />}
              onClick={() => adding ? createMut.mutate() : updateMut.mutate()}
              loading={createMut.isPending || updateMut.isPending}
            >حفظ</Button>
            <Button size="sm" variant="secondary" icon={<X size={14} />}
              onClick={() => { setAdding(false); setEditing(null) }}
            >إلغاء</Button>
          </div>
        </div>
      )}

      {isLoading ? <div className="settings-loading">جارٍ التحميل...</div> : (
        <table className="settings-table">
          <thead><tr><th>القسم</th><th>الكود</th><th>الحالة</th><th></th></tr></thead>
          <tbody>
            {depts.map(d => (
              <tr key={d.id}>
                <td><strong>{d.name}</strong>{d.name_en && <span style={{ color: 'var(--text-muted)', marginRight: 8, fontSize: 'var(--text-xs)' }}>{d.name_en}</span>}</td>
                <td><code style={{ fontSize: 'var(--text-xs)' }}>{d.code || '—'}</code></td>
                <td><Badge variant={d.is_active ? 'success' : 'neutral'}>{d.is_active ? 'نشط' : 'موقوف'}</Badge></td>
                <td>
                  <Button size="sm" variant="ghost" icon={<Edit2 size={13} />} onClick={() => startEdit(d)}>تعديل</Button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}

// ════════════════════════════════════════════
// TAB: Positions
// ════════════════════════════════════════════
function PositionsTab() {
  const qc = useQueryClient()
  const { data: positions = [], isLoading } = useQuery({
    queryKey: ['hr-positions-all'],
    queryFn: () => getPositions(),
  })
  const { data: departments = [] } = useQuery({
    queryKey: ['hr-departments'],
    queryFn: () => getDepartments(false),
  })

  const [adding, setAdding] = useState(false)
  const [form, setForm] = useState<HRPositionInput>({ name: '', is_field: false, is_active: true })

  const createMut = useMutation({
    mutationFn: () => createPosition(form),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['hr-positions-all'] }); qc.invalidateQueries({ queryKey: ['hr-positions'] }); setAdding(false); setForm({ name: '', is_field: false, is_active: true }); toast.success('تم إضافة المسمى') },
    onError: (e: Error) => toast.error(e.message),
  })

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 'var(--space-4)' }}>
        <Button icon={<Plus size={15} />} onClick={() => setAdding(true)}>مسمى جديد</Button>
      </div>

      {adding && (
        <div className="form-card">
          <div className="form-card-title">إضافة مسمى وظيفي</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
            <Input label="المسمى الوظيفي" required value={form.name} onChange={e => setForm(p => ({ ...p, name: e.target.value }))} />
            <Input label="بالإنجليزية" value={form.name_en ?? ''} onChange={e => setForm(p => ({ ...p, name_en: e.target.value || null }))} />
            <Select label="القسم" value={form.department_id ?? ''} onChange={e => setForm(p => ({ ...p, department_id: e.target.value || null }))}
              options={departments.map(d => ({ value: d.id, label: d.name }))} placeholder="اختر القسم" />
            <Input label="الدرجة الوظيفية" type="number" value={String(form.grade ?? '')}
              onChange={e => setForm(p => ({ ...p, grade: e.target.value ? Number(e.target.value) : null }))} />
          </div>
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 'var(--space-3)', fontSize: 'var(--text-sm)', cursor: 'pointer' }}>
            <input type="checkbox" checked={form.is_field ?? false} onChange={e => setForm(p => ({ ...p, is_field: e.target.checked }))} />
            وظيفة ميدانية (مندوب / سائق)
          </label>
          <div style={{ display: 'flex', gap: 'var(--space-2)', marginTop: 'var(--space-3)' }}>
            <Button size="sm" icon={<Check size={14} />} onClick={() => createMut.mutate()} loading={createMut.isPending}>حفظ</Button>
            <Button size="sm" variant="secondary" icon={<X size={14} />} onClick={() => setAdding(false)}>إلغاء</Button>
          </div>
        </div>
      )}

      {isLoading ? <div className="settings-loading">جارٍ التحميل...</div> : (
        <table className="settings-table">
          <thead><tr><th>المسمى الوظيفي</th><th>القسم</th><th>النوع</th><th>الحالة</th></tr></thead>
          <tbody>
            {positions.map(p => (
              <tr key={p.id}>
                <td><strong>{p.name}</strong>{p.name_en && <span style={{ color: 'var(--text-muted)', marginRight: 8, fontSize: 'var(--text-xs)' }}>{p.name_en}</span>}</td>
                <td>{p.department?.name ?? '—'}</td>
                <td><Badge variant={p.is_field ? 'info' : 'neutral'}>{p.is_field ? 'ميداني' : 'مكتبي'}</Badge></td>
                <td><Badge variant={p.is_active ? 'success' : 'neutral'}>{p.is_active ? 'نشط' : 'موقوف'}</Badge></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}

// ════════════════════════════════════════════
// GPS Coordinate Picker — مكوّن اختيار الإحداثيات
// ════════════════════════════════════════════
function GpsCoordinatePicker({
  lat, lng, onChange,
}: { lat: number; lng: number; onChange: (lat: number, lng: number) => void }) {
  const [fetching, setFetching] = useState(false)
  const [gpsError, setGpsError] = useState<string | null>(null)
  const hasCoords = lat !== 0 || lng !== 0

  const useMyLocation = () => {
    if (!navigator.geolocation) { setGpsError('GPS غير مدعوم في هذا المتصفح'); return }
    setFetching(true); setGpsError(null)
    navigator.geolocation.getCurrentPosition(
      pos => {
        onChange(pos.coords.latitude, pos.coords.longitude)
        setFetching(false)
        toast.success(`تم جلب الموقع — دقة: ±${Math.round(pos.coords.accuracy)} متر`)
      },
      err => {
        const msgs: Record<number, string> = {
          1: 'مرفوض: فعّل إذن الموقع في المتصفح ثم أعد المحاولة',
          2: 'تعذر تحديد الموقع — تأكد من تفعيل GPS في الجهاز',
          3: 'انتهت مهلة GPS — تحرك لمكان مفتوح وأعد المحاولة',
        }
        setGpsError(msgs[err.code] ?? 'خطأ غير معروف في خدمة الموقع')
        setFetching(false)
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 5000 }
    )
  }

  // رابط OpenStreetMap يفتح الموقع بصرياً
  const osmUrl = hasCoords
    ? `https://www.openstreetmap.org/export/embed.html?bbox=${lng - 0.002},${lat - 0.002},${lng + 0.002},${lat + 0.002}&layer=mapnik&marker=${lat},${lng}`
    : null

  return (
    <div style={{ marginTop: 'var(--space-3)', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
      {/* شريط الإجراءات */}
      <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' }}>
        <div style={{ flex: 1, minWidth: 140 }}>
          <label className="form-label">خط العرض (Latitude)</label>
          <input
            type="number" step="0.0000001" className="form-input" dir="ltr"
            value={lat === 0 ? '' : lat}
            onChange={e => onChange(Number(e.target.value), lng)}
            placeholder="30.0444"
          />
        </div>
        <div style={{ flex: 1, minWidth: 140 }}>
          <label className="form-label">خط الطول (Longitude)</label>
          <input
            type="number" step="0.0000001" className="form-input" dir="ltr"
            value={lng === 0 ? '' : lng}
            onChange={e => onChange(lat, Number(e.target.value))}
            placeholder="31.2357"
          />
        </div>
        <button
          type="button"
          id="btn-use-my-location"
          onClick={useMyLocation}
          disabled={fetching}
          style={{
            display: 'flex', alignItems: 'center', gap: 6,
            padding: '8px 14px',
            background: fetching
              ? 'var(--bg-surface-2)'
              : 'color-mix(in srgb, var(--color-primary) 10%, transparent)',
            border: '1px solid color-mix(in srgb, var(--color-primary) 30%, transparent)',
            borderRadius: 'var(--radius-md)',
            color: 'var(--color-primary)',
            fontFamily: 'var(--font-sans)',
            fontSize: 'var(--text-sm)',
            fontWeight: 600,
            cursor: fetching ? 'not-allowed' : 'pointer',
            whiteSpace: 'nowrap',
            transition: 'all 0.15s',
          }}
        >
          {fetching ? (
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{ animation: 'spin 1s linear infinite' }}>
              <path d="M21 12a9 9 0 1 1-6.219-8.56" />
            </svg>
          ) : (
            <MapPin size={14} />
          )}
          {fetching ? 'جاري الجلب...' : 'استخدام موقعي'}
        </button>
      </div>

      {/* رسالة خطأ GPS */}
      {gpsError && (
        <div style={{
          display: 'flex', gap: 6, alignItems: 'flex-start',
          padding: '8px 12px',
          background: 'color-mix(in srgb, var(--color-danger) 8%, transparent)',
          border: '1px solid color-mix(in srgb, var(--color-danger) 25%, transparent)',
          borderRadius: 'var(--radius-md)',
          fontSize: 'var(--text-xs)', color: 'var(--color-danger)',
        }}>
          <AlertTriangle size={13} style={{ flexShrink: 0, marginTop: 1 }} />
          {gpsError}
        </div>
      )}

      {/* معاينة الخريطة OpenStreetMap */}
      {hasCoords && osmUrl && (
        <div style={{ borderRadius: 'var(--radius-lg)', overflow: 'hidden', border: '1px solid var(--border-color)' }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 6, justifyContent: 'space-between',
            padding: '6px 10px',
            background: 'var(--bg-surface-2)',
            fontSize: 'var(--text-xs)', color: 'var(--text-muted)',
          }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
              <MapPin size={11} /> معاينة الموقع على الخريطة
            </span>
            <a
              href={`https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}#map=17/${lat}/${lng}`}
              target="_blank" rel="noreferrer"
              style={{ color: 'var(--color-primary)', textDecoration: 'none', fontWeight: 600 }}
            >
              فتح في خريطة كاملة ↗
            </a>
          </div>
          <iframe
            title="موقع على الخريطة"
            src={osmUrl}
            width="100%"
            height="220"
            style={{ border: 'none', display: 'block' }}
            loading="lazy"
            referrerPolicy="no-referrer"
          />
          <div style={{
            padding: '4px 10px',
            background: 'var(--bg-surface-2)',
            fontSize: 'var(--text-xs)', color: 'var(--text-muted)',
            textAlign: 'center',
          }} dir="ltr">
            {lat.toFixed(6)}, {lng.toFixed(6)}
          </div>
        </div>
      )}

      <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
    </div>
  )
}

// ════════════════════════════════════════════
// TAB: Work Locations (GPS)
// ════════════════════════════════════════════
function LocationsTab() {
  const qc = useQueryClient()
  const { data: locations = [], isLoading } = useQuery({
    queryKey: ['hr-work-locations'],
    queryFn: getWorkLocations,
  })

  const [editing, setEditing] = useState<HRWorkLocation | null>(null)
  const [adding, setAdding]   = useState(false)
  const EMPTY: HRWorkLocationInput = { name: '', latitude: 0, longitude: 0, radius_meters: 200, require_selfie: false, gps_accuracy_threshold: 150, is_active: true }
  const [form, setForm] = useState<HRWorkLocationInput>(EMPTY)

  const createMut = useMutation({
    mutationFn: () => createWorkLocation(form),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['hr-work-locations'] }); setAdding(false); setForm(EMPTY); toast.success('تم إضافة الموقع') },
    onError: (e: Error) => toast.error(e.message),
  })
  const updateMut = useMutation({
    mutationFn: () => updateWorkLocation(editing!.id, form),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['hr-work-locations'] }); setEditing(null); toast.success('تم تحديث الموقع') },
    onError: (e: Error) => toast.error(e.message),
  })

  const startEdit = (l: HRWorkLocation) => {
    setEditing(l)
    setForm({ name: l.name, latitude: l.latitude, longitude: l.longitude, radius_meters: l.radius_meters, require_selfie: l.require_selfie, gps_accuracy_threshold: l.gps_accuracy_threshold, is_active: l.is_active, notes: l.notes })
  }

  const setN = (k: keyof HRWorkLocationInput) => (v: string | number | boolean | null) => setForm(p => ({ ...p, [k]: v }))

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 'var(--space-4)' }}>
        <Button icon={<Plus size={15} />} onClick={() => { setAdding(true); setForm(EMPTY) }}>موقع جديد</Button>
      </div>

      {(adding || editing) && (
        <div className="form-card">
          <div className="form-card-title">{adding ? 'إضافة موقع GPS' : 'تعديل الموقع'}</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
            <Input label="اسم الموقع" required value={form.name} onChange={e => setN('name')(e.target.value)} />
            <Input label="نطاق السماحية (متر)" type="number" value={String(form.radius_meters ?? 200)} onChange={e => setN('radius_meters')(Number(e.target.value))} />
            <Input label="أقصى دقة GPS مقبولة (متر)" type="number" value={String(form.gps_accuracy_threshold ?? 150)} onChange={e => setN('gps_accuracy_threshold')(Number(e.target.value))} />
            <Input label="ملاحظات" value={form.notes ?? ''} onChange={e => setN('notes')(e.target.value || null)} />
          </div>
          <GpsCoordinatePicker
            lat={form.latitude}
            lng={form.longitude}
            onChange={(lat, lng) => setForm(p => ({ ...p, latitude: lat, longitude: lng }))}
          />
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 'var(--space-3)', fontSize: 'var(--text-sm)', cursor: 'pointer' }}>
            <input type="checkbox" checked={form.require_selfie ?? false} onChange={e => setN('require_selfie')(e.target.checked)} />
            يشترط صورة سيلفي عند التسجيل
          </label>
          <div style={{ display: 'flex', gap: 'var(--space-2)', marginTop: 'var(--space-3)' }}>
            <Button size="sm" icon={<Check size={14} />} onClick={() => adding ? createMut.mutate() : updateMut.mutate()} loading={createMut.isPending || updateMut.isPending}>حفظ</Button>
            <Button size="sm" variant="secondary" icon={<X size={14} />} onClick={() => { setAdding(false); setEditing(null) }}>إلغاء</Button>
          </div>
        </div>
      )}

      {isLoading ? <div className="settings-loading">جارٍ التحميل...</div> : (
        <table className="settings-table">
          <thead><tr><th>الموقع</th><th>الإحداثيات</th><th>النطاق</th><th>سيلفي</th><th>الحالة</th><th></th></tr></thead>
          <tbody>
            {locations.map(l => (
              <tr key={l.id}>
                <td><strong>{l.name}</strong></td>
                <td dir="ltr" style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                  {l.latitude.toFixed(5)}, {l.longitude.toFixed(5)}
                </td>
                <td>{l.radius_meters} م</td>
                <td><Badge variant={l.require_selfie ? 'info' : 'neutral'}>{l.require_selfie ? 'نعم' : 'لا'}</Badge></td>
                <td><Badge variant={l.is_active ? 'success' : 'neutral'}>{l.is_active ? 'نشط' : 'موقوف'}</Badge></td>
                <td><Button size="sm" variant="ghost" icon={<Edit2 size={13} />} onClick={() => startEdit(l)}>تعديل</Button></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}

// ════════════════════════════════════════════
// TAB: Public Holidays
// ════════════════════════════════════════════
function HolidaysTab() {
  const qc = useQueryClient()
  const year = new Date().getFullYear()
  const [selYear, setSelYear] = useState(year)

  const { data: holidays = [], isLoading } = useQuery({
    queryKey: ['hr-public-holidays', selYear],
    queryFn: () => getPublicHolidays(selYear),
  })

  const [adding, setAdding] = useState(false)
  const [form, setForm] = useState<HRPublicHolidayInput>({
    name: '', holiday_date: new Date().toISOString().split('T')[0], is_recurring: false,
  })

  const createMut = useMutation({
    mutationFn: () => createPublicHoliday(form),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['hr-public-holidays'] }); setAdding(false); setForm({ name: '', holiday_date: '', is_recurring: false }); toast.success('تم إضافة العطلة') },
    onError: (e: Error) => toast.error(e.message),
  })

  // FIX-10: حذف عطلة رسمية مع تأكيد
  const deleteMut = useMutation({
    mutationFn: (id: string) => deletePublicHoliday(id),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['hr-public-holidays'] }); toast.success('تم حذف العطلة') },
    onError: (e: Error) => toast.error(e.message),
  })

  const handleDelete = (h: HRPublicHoliday) => {
    if (!window.confirm(`هل أنت متأكد من حذف عطلة «${h.name}»؟\nسيؤثر هذا على حسابات الحضور.`)) return
    deleteMut.mutate(h.id)
  }

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 'var(--space-4)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
          <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)' }}>السنة:</span>
          <Select value={String(selYear)} onChange={e => setSelYear(Number(e.target.value))}
            options={[year - 1, year, year + 1].map(y => ({ value: String(y), label: String(y) }))} />
        </div>
        <Button icon={<Plus size={15} />} onClick={() => setAdding(true)}>عطلة جديدة</Button>
      </div>

      {adding && (
        <div className="form-card">
          <div className="form-card-title">إضافة عطلة رسمية</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-3)' }}>
            <Input label="اسم العطلة" required value={form.name} onChange={e => setForm(p => ({ ...p, name: e.target.value }))} />
            <Input label="التاريخ" type="date" required value={form.holiday_date} onChange={e => setForm(p => ({ ...p, holiday_date: e.target.value }))} />
          </div>
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 'var(--space-3)', fontSize: 'var(--text-sm)', cursor: 'pointer' }}>
            <input type="checkbox" checked={form.is_recurring} onChange={e => setForm(p => ({ ...p, is_recurring: e.target.checked }))} />
            متكررة كل سنة (أعياد ثابتة)
          </label>
          <div style={{ display: 'flex', gap: 'var(--space-2)', marginTop: 'var(--space-3)' }}>
            <Button size="sm" icon={<Check size={14} />} onClick={() => createMut.mutate()} loading={createMut.isPending}>حفظ</Button>
            <Button size="sm" variant="secondary" icon={<X size={14} />} onClick={() => setAdding(false)}>إلغاء</Button>
          </div>
        </div>
      )}

      {isLoading ? <div className="settings-loading">جارٍ التحميل...</div> : (
        <table className="settings-table">
          <thead><tr><th>العطلة</th><th>التاريخ</th><th>نوع</th><th></th></tr></thead>
          <tbody>
            {holidays.length === 0
              ? <tr><td colSpan={4} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا توجد عطل مسجلة لعام {selYear}</td></tr>
              : holidays.map(h => (
                <tr key={h.id}>
                  <td><strong>{h.name}</strong></td>
                  <td>{new Date(h.holiday_date).toLocaleDateString('ar-EG', { day: 'numeric', month: 'long', year: 'numeric' })}</td>
                  <td><Badge variant={h.is_recurring ? 'info' : 'neutral'}>{h.is_recurring ? 'سنوية' : 'مرة واحدة'}</Badge></td>
                  <td>
                    <Button
                      size="sm" variant="ghost"
                      icon={<Trash2 size={13} />}
                      onClick={() => handleDelete(h)}
                      loading={deleteMut.isPending}
                      style={{ color: 'var(--color-danger)' }}
                    />
                  </td>
                </tr>
              ))
            }
          </tbody>
        </table>
      )}
    </div>
  )
}

// ════════════════════════════════════════════
// TAB: Penalty Rules
// ════════════════════════════════════════════
function PenaltyRulesTab() {
  const { data: rules = [], isLoading } = useQuery({
    queryKey: ['hr-penalty-rules'],
    queryFn: getPenaltyRules,
  })

  const PENALTY_TYPE_LABEL: Record<string, string> = {
    late: 'تأخير', absence: 'غياب', early_leave: 'انصراف مبكر', unauthorized_exit: 'خروج غير مرخص',
  }
  const DEDUCTION_LABEL: Record<string, string> = {
    warning: 'إنذار', quarter_day: 'ربع يوم', half_day: 'نصف يوم', full_day: 'يوم كامل', none: 'بدون خصم',
  }

  if (isLoading) return <div className="settings-loading">جارٍ التحميل...</div>

  return (
    <div>
      <div style={{
        padding: 'var(--space-3) var(--space-4)',
        background: 'color-mix(in srgb, var(--color-info) 8%, transparent)',
        border: '1px solid color-mix(in srgb, var(--color-info) 20%, transparent)',
        borderRadius: 'var(--radius-md)',
        fontSize: 'var(--text-xs)',
        color: 'var(--text-muted)',
        marginBottom: 'var(--space-4)',
      }}>
        قواعد الجزاءات تُطبَّق تلقائياً بدالة <code>process_attendance_penalties()</code>. لتعديل قاعدة، تواصل مع المدير التقني.
      </div>
      <table className="settings-table">
        <thead>
          <tr>
            <th>نوع المخالفة</th>
            <th>النطاق الزمني (دقيقة)</th>
            <th>الجزاء</th>
            <th>مرات السماح/شهر</th>
          </tr>
        </thead>
        <tbody>
          {rules.map(r => (
            <tr key={r.id}>
              <td><Badge variant="warning">{PENALTY_TYPE_LABEL[r.penalty_type] ?? r.penalty_type}</Badge></td>
              <td>
                {r.min_minutes != null ? `${r.min_minutes}` : '—'}
                {r.max_minutes != null ? ` – ${r.max_minutes}` : '+'}
                {' دقيقة'}
              </td>
              <td><strong>{DEDUCTION_LABEL[r.deduction_type] ?? r.deduction_type}</strong></td>
              <td>{r.occurrence_from}</td>
            </tr>
          ))}
          {rules.length === 0 && (
            <tr><td colSpan={4} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا توجد قواعد مسجلة</td></tr>
          )}
        </tbody>
      </table>
    </div>
  )
}

// ════════════════════════════════════════════
// Main Page
// ════════════════════════════════════════════
export default function HRSettingsPage() {
  const [activeTab, setActiveTab] = useState<Tab>('settings')

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="إعدادات الموارد البشرية"
        subtitle="إدارة إعدادات الشركة والهيكل التنظيمي ومواقع الحضور"
        breadcrumbs={[
          { label: 'الموارد البشرية', path: '/hr' },
          { label: 'الإعدادات' },
        ]}
      />

      {/* Tabs */}
      <div className="settings-tabs">
        {TABS.map(t => (
          <button
            key={t.id}
            id={`hr-settings-tab-${t.id}`}
            className={`settings-tab ${activeTab === t.id ? 'settings-tab--active' : ''}`}
            onClick={() => setActiveTab(t.id)}
          >
            {t.icon}
            <span>{t.label}</span>
          </button>
        ))}
      </div>

      {/* Content — محمي بنفس صلاحية المسار */}
      <div className="edara-card" style={{ marginTop: 'var(--space-4)' }}>
        <PermissionGuard permission="hr.settings.update">
          {activeTab === 'settings'    && <SettingsTab />}
          {activeTab === 'departments' && <DepartmentsTab />}
          {activeTab === 'positions'   && <PositionsTab />}
          {activeTab === 'locations'   && <LocationsTab />}
          {activeTab === 'holidays'    && <HolidaysTab />}
          {activeTab === 'penalties'   && <PenaltyRulesTab />}
        </PermissionGuard>
      </div>

      <style>{`
        .settings-tabs {
          display: flex; gap: 4px; flex-wrap: wrap;
          border-bottom: 1.5px solid var(--border-color);
          margin-bottom: -1px;
        }
        .settings-tab {
          display: flex; align-items: center; gap: 6px;
          padding: var(--space-2) var(--space-4);
          font-size: var(--text-sm); font-weight: 500;
          color: var(--text-muted);
          border: none; background: transparent;
          cursor: pointer; border-bottom: 2px solid transparent;
          margin-bottom: -1.5px; white-space: nowrap;
          transition: all 0.15s ease; font-family: var(--font-sans);
          border-radius: var(--radius-sm) var(--radius-sm) 0 0;
        }
        .settings-tab:hover { color: var(--text-primary); background: var(--bg-surface-2); }
        .settings-tab--active { color: var(--color-primary); border-bottom-color: var(--color-primary); background: transparent; }

        .setting-row {
          display: flex; align-items: center; justify-content: space-between;
          padding: var(--space-3) var(--space-4);
          border: 1px solid var(--border-color); border-radius: var(--radius-md);
          background: var(--bg-surface-2);
          gap: var(--space-4);
        }
        .setting-info { flex: 1; }
        .setting-label { display: block; font-weight: 600; font-size: var(--text-sm); }
        .setting-desc  { display: block; font-size: var(--text-xs); color: var(--text-muted); margin-top: 2px; }
        .setting-control { flex-shrink: 0; }
        .toggle-btn {
          display: flex; align-items: center; gap: 6px;
          background: none; border: none; cursor: pointer;
          font-size: var(--text-sm); font-family: var(--font-sans);
        }

        .form-card {
          border: 1px solid var(--border-color); border-radius: var(--radius-lg);
          padding: var(--space-4); margin-bottom: var(--space-4);
          background: var(--bg-surface-2);
          animation: animate-enter 0.2s ease;
        }
        .form-card-title {
          font-weight: 700; font-size: var(--text-sm);
          margin-bottom: var(--space-3); color: var(--color-primary);
        }
        .settings-table {
          width: 100%; border-collapse: collapse;
          font-size: var(--text-sm);
        }
        .settings-table th {
          text-align: right; padding: var(--space-2) var(--space-3);
          border-bottom: 1.5px solid var(--border-color);
          color: var(--text-muted); font-weight: 600;
          font-size: var(--text-xs);
        }
        .settings-table td {
          padding: var(--space-3);
          border-bottom: 1px solid var(--border-color);
        }
        .settings-table tr:last-child td { border-bottom: none; }
        .settings-table tr:hover td { background: var(--bg-surface-2); }
        .settings-loading {
          text-align: center; padding: var(--space-8);
          color: var(--text-muted); font-size: var(--text-sm);
        }
      `}</style>
    </div>
  )
}
