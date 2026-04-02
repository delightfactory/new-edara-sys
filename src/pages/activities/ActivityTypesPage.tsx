import { useState } from 'react'
import { Plus, Edit2, Check, X, ShieldAlert, Target } from 'lucide-react'
import { toast } from 'sonner'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Button from '@/components/ui/Button'
import Input from '@/components/ui/Input'
import Select from '@/components/ui/Select'
import Badge from '@/components/ui/Badge'
import {
  useActivityTypes,
  useCreateActivityType,
  useUpdateActivityType
} from '@/hooks/useQueryHooks'
import type { ActivityType, ActivityTypeInput, ActivityCategory } from '@/lib/types/activities'

export default function ActivityTypesPage() {
  const { data: activityTypes = [], isLoading } = useActivityTypes(false) // Admin mode: fetch all
  
  const [adding, setAdding] = useState(false)
  const [editing, setEditing] = useState<ActivityType | null>(null)
  
  const EMPTY_FORM: ActivityTypeInput = {
    name: '',
    code: '',
    category: 'task',
    requires_gps: false,
    requires_customer: false,
    requires_outcome: false,
    default_duration_min: 30,
    is_active: true,
    sort_order: 10,
  }
  
  const [form, setForm] = useState<ActivityTypeInput>(EMPTY_FORM)

  const createMut = useCreateActivityType()
  const updateMut = useUpdateActivityType()

  const startEdit = (t: ActivityType) => {
    setEditing(t)
    setAdding(false)
    setForm({
      name: t.name,
      code: t.code || '',
      category: t.category,
      requires_gps: t.requires_gps,
      requires_customer: t.requires_customer,
      requires_outcome: t.requires_outcome,
      default_duration_min: t.default_duration_min,
      is_active: t.is_active,
      sort_order: t.sort_order,
    })
  }

  const handleToggleActive = (t: ActivityType) => {
    // Protected guard: System types commonly enforce critical behavior.
    // If the infrastructure in the future sets is_system, we should guard it.
    // Right now, we just softly toggle is_active for all types.
    const msg = t.is_active 
      ? `تعطيل النوع "${t.name}" سيُخفيه من استمارات إنشاء الأنشطة للمندوبين. هل أنت متأكد؟`
      : `هل أنت متأكد من إعادة إتاحة النوع "${t.name}" للمندوبين؟`
      
    if (!window.confirm(msg)) return
    
    updateMut.mutate({ id: t.id, input: { is_active: !t.is_active } }, {
      onSuccess: () => toast.success(t.is_active ? 'تم إيقاف نوع النشاط' : 'تم تفعيل نوع النشاط')
    })
  }

  const handleSave = () => {
    if (!form.name || !form.category) return toast.error('تأكد من إدخال اسم النشاط والفئة')
    
    // Explicitly strip `requires_outcome` from the payload to avoid false affordances
    // Outcome governance is deferred to Wave Y3.
    const { requires_outcome, ...payload } = form

    if (adding) {
      createMut.mutate(payload, {
        onSuccess: () => {
          setAdding(false)
          toast.success('تمت إضافة النوع بنجاح')
        }
      })
    } else if (editing) {
      updateMut.mutate({ id: editing.id, input: payload }, {
        onSuccess: () => {
          setEditing(null)
          toast.success('تم تحديث النوع بنجاح')
        }
      })
    }
  }

  return (
    <div className="page-container">
      <div style={{ marginBottom: 'var(--space-4)' }}>
        <PageHeader
          title="أنواع الأنشطة الميدانية"
          actions={<Button icon={<Plus size={15} />} onClick={() => { setAdding(true); setEditing(null); setForm(EMPTY_FORM); }}>إضافة نوع جديد</Button>}
        />
        <p style={{ color: 'var(--text-muted)' }}>إدارة الخصائص والمحددات التشغيلية لكل نوع نشاط</p>
      </div>

      {(adding || editing) && (
        <div className="form-card" style={{ marginBottom: 'var(--space-4)' }}>
          <div className="form-card-title">{adding ? 'إضافة نوع نشاط جديد' : 'تعديل نوع النشاط'}</div>
          
          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(200px, 1fr) minmax(200px, 1fr) minmax(200px, 1fr)', gap: 'var(--space-3)' }}>
            <Input label="اسم النوع" required value={form.name} onChange={e => setForm(p => ({ ...p, name: e.target.value }))} placeholder="زيارة بيعية..." />
            <Input label="الكود التعريفي" value={form.code ?? ''} onChange={e => setForm(p => ({ ...p, code: e.target.value.toUpperCase() || null }))} placeholder="SA_VST" dir="ltr" />
            <Select label="الفئة (شكل العرض)" required value={form.category} onChange={e => setForm(p => ({ ...p, category: e.target.value as ActivityCategory }))} options={[
              { value: 'visit', label: 'زيارة ميدانية' },
              { value: 'call', label: 'مكالمة هاتفية' },
              { value: 'task', label: 'مهمة عامة / أخرى' }
            ]} />
          </div>

          <div style={{ 
            display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 'var(--space-3)', 
            marginTop: 'var(--space-4)', padding: 'var(--space-3)', background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-md)'
          }}>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 'var(--text-sm)', cursor: 'pointer' }}>
              <input type="checkbox" checked={form.requires_customer ?? false} onChange={e => setForm(p => ({ ...p, requires_customer: e.target.checked }))} />
              <span>يتطلب ربط <strong>بعميل محدد</strong></span>
            </label>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 'var(--text-sm)', cursor: 'pointer' }}>
              <input type="checkbox" checked={form.requires_gps ?? false} onChange={e => setForm(p => ({ ...p, requires_gps: e.target.checked }))} />
              <span>يفعّل <strong>بصمة الموقع (GPS)</strong> عند التنفيذ</span>
            </label>
            {/* requires_outcome deferred to Y3 */}
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '150px 150px', gap: 'var(--space-3)', marginTop: 'var(--space-4)' }}>
            <Input label="المدة الافتراضية (دقيقة)" type="number" value={String(form.default_duration_min ?? 30)} onChange={e => setForm(p => ({ ...p, default_duration_min: e.target.value ? Number(e.target.value) : undefined }))} dir="ltr" />
            <Input label="ترتيب العرض" type="number" value={String(form.sort_order ?? 10)} onChange={e => setForm(p => ({ ...p, sort_order: e.target.value ? Number(e.target.value) : undefined }))} dir="ltr" />
          </div>

          <div style={{ display: 'flex', gap: 'var(--space-2)', marginTop: 'var(--space-4)' }}>
             <Button size="sm" icon={<Check size={14} />} onClick={handleSave} loading={createMut.isPending || updateMut.isPending}>حفظ التغييرات</Button>
             <Button size="sm" variant="secondary" icon={<X size={14} />} onClick={() => { setAdding(false); setEditing(null); }}>إلغاء</Button>
          </div>
        </div>
      )}

      {isLoading ? <div className="loading-state">جارٍ التحميل...</div> : (
        <DataTable
          columns={[
            { key: 'name', label: 'الاسم', render: (t: ActivityType) => <div><strong>{t.name}</strong><br/><span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{t.code || '—'}</span></div> },
            { key: 'category', label: 'الفئة المستهدفة', render: (t: ActivityType) => <Badge variant="neutral">{t.category === 'visit' ? 'زيارة' : t.category === 'call' ? 'مكالمة' : 'مهمة'}</Badge> },
            { key: 'rules', label: 'متطلبات الإنجاز', render: (t: ActivityType) => (
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                {t.requires_customer && <Badge variant="info">موجّه لعميل</Badge>}
                {t.requires_gps && <Badge variant="warning">بصمة جغرافية</Badge>}
              </div>
            )},
            { key: 'duration', label: 'وقت مقدر', render: (t: ActivityType) => <span>{t.default_duration_min || 0} دقيقة</span> },
            { key: 'status', label: 'الحالة التشغيلية', render: (t: ActivityType) => (
              <button onClick={() => handleToggleActive(t)} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0 }} title="انقر لتبديل حالة الإتاحة">
                <Badge variant={t.is_active ? 'success' : 'neutral'}>{t.is_active ? 'متاح للمندوبين' : 'موقوف إدارياً'}</Badge>
              </button>
            )},
            { key: 'actions', label: '', align: 'end', render: (t: ActivityType) => <Button size="sm" variant="ghost" icon={<Edit2 size={13} />} onClick={() => startEdit(t)}>تعديلات</Button>}
          ]}
          data={activityTypes}
          keyField="id"
          dataCardMapping={(t: ActivityType) => ({
            title: t.name,
            subtitle: t.category === 'visit' ? 'زيارة' : t.category === 'call' ? 'مكالمة' : 'مهمة',
            badge: (
              <button 
                onClick={(e) => { e.stopPropagation(); handleToggleActive(t); }} 
                style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0 }}
              >
                <Badge variant={t.is_active ? 'success' : 'neutral'}>{t.is_active ? 'متاح' : 'موقوف'}</Badge>
              </button>
            ),
            metadata: [
              { label: 'GPS', value: t.requires_gps ? 'إجباري' : 'لا' }
            ],
            actions: <Button size="sm" variant="secondary" onClick={() => startEdit(t)} style={{ width: '100%', justifyContent: 'center' }}><Edit2 size={13} style={{ marginInlineEnd: 4 }} /> تعديل</Button>
          })}
        />
      )}
    </div>
  )
}
