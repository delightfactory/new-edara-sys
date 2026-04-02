import { useState } from 'react'
import { Plus, Edit2, Check, X, ShieldAlert, FileText } from 'lucide-react'
import { toast } from 'sonner'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Button from '@/components/ui/Button'
import Input from '@/components/ui/Input'
import Select from '@/components/ui/Select'
import Badge from '@/components/ui/Badge'
import {
  useTargetTypes,
  useCreateTargetType,
  useUpdateTargetType
} from '@/hooks/useQueryHooks'
import type { TargetType, TargetTypeInput, TargetUnit } from '@/lib/types/activities'

export default function TargetTypesPage() {
  const { data: targetTypes = [], isLoading } = useTargetTypes(false) // Admin mode
  
  const [adding, setAdding] = useState(false)
  const [editing, setEditing] = useState<TargetType | null>(null)
  
  const EMPTY_FORM: TargetTypeInput = {
    name: '',
    code: '',
    unit: 'currency',
    category: 'financial',
    auto_source: 'sales_orders',
    auto_calc_enabled: true,
    description: '',
    is_active: true,
  }
  
  const [form, setForm] = useState<TargetTypeInput>(EMPTY_FORM)

  const createMut = useCreateTargetType()
  const updateMut = useUpdateTargetType()

  const startEdit = (t: TargetType) => {
    setEditing(t)
    setAdding(false)
    setForm({
      name: t.name,
      code: t.code,
      unit: t.unit,
      category: t.category,
      auto_source: t.auto_source,
      auto_calc_enabled: t.auto_calc_enabled,
      description: t.description || '',
      is_active: t.is_active,
    })
  }

  const handleToggleActive = (t: TargetType) => {
    const msg = t.is_active 
      ? `تعطيل النوع "${t.name}" سيمنع إسناد أي أهداف جديدة من هذا النوع. هل أنت متأكد؟`
      : `هل أنت متأكد من إعادة إتاحة النوع "${t.name}" للإسناد؟`
      
    if (!window.confirm(msg)) return
    
    updateMut.mutate({ id: t.id, input: { is_active: !t.is_active } }, {
      onSuccess: () => toast.success(t.is_active ? 'تم إيقاف نوع الهدف' : 'تم تفعيل نوع الهدف')
    })
  }

  const handleSave = () => {
    if (!form.name || !form.code || !form.category) return toast.error('تأكد من إدخال اسم الهدف والكود والفئة')
    
    if (adding) {
      createMut.mutate(form, {
        onSuccess: () => {
          setAdding(false)
          toast.success('تمت إضافة النوع بنجاح')
        }
      })
    } else if (editing) {
      // For editing, we intentionally drop sensitive fields that shouldn't change
      // so we don't accidentally poison the target calculation engine
      const safePayload = {
        name: form.name,
        description: form.description,
        auto_calc_enabled: form.auto_calc_enabled,
        is_active: form.is_active,
        category: form.category, // safe enough
      }
      updateMut.mutate({ id: editing.id, input: safePayload }, {
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
          title="معايير الأهداف المستهدفة (Target Types)"
          actions={<Button icon={<Plus size={15} />} onClick={() => { setAdding(true); setEditing(null); setForm(EMPTY_FORM); }}>إضافة معيار جديد</Button>}
        />
        <p style={{ color: 'var(--text-muted)' }}>إدارة أسس احتساب الأهداف وطرق إسنادها التشغيلية</p>
      </div>

      {(adding || editing) && (
        <div className="form-card" style={{ marginBottom: 'var(--space-4)' }}>
          <div className="form-card-title">{adding ? 'إضافة معيار هدف جديد' : 'تعديل معيار الهدف'}</div>
          
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 'var(--space-3)' }}>
            <Input label="اسم المعيار" required value={form.name} onChange={e => setForm(p => ({ ...p, name: e.target.value }))} placeholder="تحصيل إجمالي..." />
            <Input label="الكود التعريفي (Code)" required value={form.code} onChange={e => setForm(p => ({ ...p, code: e.target.value.toUpperCase() }))} placeholder="COL_GROSS" dir="ltr" disabled={!!editing} />
            
            <Select label="الفئة الرئيسية" required value={form.category} onChange={e => setForm(p => ({ ...p, category: e.target.value }))} options={[
              { value: 'financial', label: 'مالي (مبيعات / تحصيلات)' },
              { value: 'activity', label: 'نشاط (زيارات / تقييمات)' },
              { value: 'product', label: 'منتجات (حصة / كميات)' },
              { value: 'customer', label: 'عملاء (فتح أسواق / تغطية)' }
            ]} />
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 'var(--space-3)', marginTop: 'var(--space-3)' }}>
            <Select label="وحدة القياس" value={form.unit} onChange={e => setForm(p => ({ ...p, unit: e.target.value as TargetUnit }))} disabled={!!editing} options={[
              { value: 'currency', label: 'مبلغ نقدي (Currency)' },
              { value: 'count', label: 'عدد مطْلق (Count)' },
              { value: 'percent', label: 'نسبة مئوية (%)' },
              { value: 'quantity', label: 'كميات وحدات (Qty)' }
            ]} />
            
            <Select label="مصدر البيانات الجذري" value={form.auto_source} onChange={e => setForm(p => ({ ...p, auto_source: e.target.value }))} disabled={!!editing} options={[
              { value: 'sales_orders', label: 'أوامر البيع / الفواتير' },
              { value: 'payment_receipts', label: 'سندات القبض (تحصيلات)' },
              { value: 'activities', label: 'الأنشطة الميدانية' },
              { value: 'customers', label: 'تغطية وفتح عملاء' },
              { value: 'manual', label: 'إدخال يدوي حر' }
            ]} />

            <Select label="منهجية الاحتساب التشغيلي" value={form.auto_calc_enabled ? 'auto' : 'manual'} onChange={e => setForm(p => ({ ...p, auto_calc_enabled: e.target.value === 'auto' }))} options={[
              { value: 'auto', label: 'احتساب تلقائي (مُدار بواسطة المحرك)' },
              { value: 'manual', label: 'تتبع وإدخال يدوي (بواسطة المشرف)' }
            ]} />
          </div>
          
          <div style={{ marginTop: 'var(--space-3)' }}>
            <Input label="وصف المعيار" value={form.description || ''} onChange={e => setForm(p => ({ ...p, description: e.target.value }))} placeholder="المنطق التشغيلي أو الغرض..." />
          </div>

          {editing && (
            <div style={{ marginTop: 'var(--space-3)', fontSize: 'var(--text-xs)', color: 'var(--warning-600)', background: 'var(--warning-50)', padding: 'var(--space-2)', borderRadius: 'var(--radius-sm)', display: 'flex', gap: 6, alignItems: 'center' }}>
              <ShieldAlert size={14} />
              بعض الحقول (الكود، الوحدة، المصدر) تم إقفالها لحماية سلامة محرك الاحتساب للأهداف النشطة حالياً.
            </div>
          )}

          <div style={{ display: 'flex', gap: 'var(--space-2)', marginTop: 'var(--space-4)' }}>
             <Button size="sm" icon={<Check size={14} />} onClick={handleSave} loading={createMut.isPending || updateMut.isPending}>حفظ التغييرات</Button>
             <Button size="sm" variant="secondary" icon={<X size={14} />} onClick={() => { setAdding(false); setEditing(null); }}>إلغاء</Button>
          </div>
        </div>
      )}

      {isLoading ? <div className="loading-state">جارٍ التحميل...</div> : (
        <DataTable
          columns={[
            { key: 'name', label: 'المعيار', render: (t: TargetType) => <div><strong>{t.name}</strong><br/><span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{t.code}</span></div> },
            { key: 'category', label: 'الفئة', render: (t: TargetType) => <Badge variant="neutral">{
              t.category === 'financial' ? 'مالي' : 
              t.category === 'product' ? 'منتج' : 
              t.category === 'activity' ? 'أنشطة' : 
              t.category === 'customer' ? 'عملاء' : 'أخرى'
            }</Badge> },
            { key: 'nature', label: 'طبيعة الاحتساب', render: (t: TargetType) => (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                <span style={{ fontSize: 'var(--text-xs)' }}>
                  المصدر: <strong>{t.auto_source === 'manual' ? 'يدوي' : t.auto_source === 'payment_receipts' ? 'تحصيلات' : t.auto_source === 'sales_orders' ? 'مبيعات' : t.auto_source === 'customers' ? 'قاعدة عملاء' : 'سجل نشاط'}</strong>
                </span>
                <div style={{ width: 'fit-content' }}>
                  <Badge variant={t.auto_calc_enabled ? 'info' : 'warning'}>
                    {t.auto_calc_enabled ? 'احتساب تلقائي' : 'تحديث يدوي'}
                  </Badge>
                </div>
              </div>
            )},
            { key: 'unit', label: 'الوحدة المرجعية', render: (t: TargetType) => <span dir="ltr">{t.unit}</span> },
            { key: 'status', label: 'حالة الاستهلاك', render: (t: TargetType) => (
              <button onClick={() => handleToggleActive(t)} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0 }} title="انقر لتبديل حالة الإتاحة">
                <Badge variant={t.is_active ? 'success' : 'neutral'}>{t.is_active ? 'متاح للإسناد' : 'تعليق الإسناد'}</Badge>
              </button>
            )},
            { key: 'actions', label: '', align: 'end', render: (t: TargetType) => <Button size="sm" variant="ghost" icon={<Edit2 size={13} />} onClick={() => startEdit(t)}>تعديل</Button>}
          ]}
          data={targetTypes}
          keyField="id"
          dataCardMapping={(t: TargetType) => ({
            title: t.name,
            subtitle: t.code,
            badge: (
              <button 
                onClick={(e) => { e.stopPropagation(); handleToggleActive(t); }} 
                style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0 }}
              >
                <Badge variant={t.is_active ? 'success' : 'neutral'}>{t.is_active ? 'متاح' : 'معلّق'}</Badge>
              </button>
            ),
            metadata: [
              { label: 'الاحتساب', value: t.auto_calc_enabled ? 'محرك أدلة' : 'تتبع يدوي' },
              { label: 'الوحدة', value: t.unit }
            ],
            actions: <Button size="sm" variant="secondary" onClick={() => startEdit(t)} style={{ width: '100%', justifyContent: 'center' }}><Edit2 size={13} style={{ marginInlineEnd: 4 }} /> تعديل</Button>
          })}
        />
      )}
    </div>
  )
}
