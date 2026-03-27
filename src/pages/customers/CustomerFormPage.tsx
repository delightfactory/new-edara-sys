import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { ArrowRight, Save, Loader2, Plus, Trash2, Edit, MapPin, User, Building, Phone, CreditCard, History, Users, Star, Navigation, UserPlus } from 'lucide-react'
import { getCustomer, createCustomer, updateCustomer, getCustomerBranches, saveCustomerBranch, deleteCustomerBranch, getCustomerContacts, saveCustomerContact, deleteCustomerContact, getCreditHistory } from '@/lib/services/customers'
import { getGovernorates, getCities, getAreas } from '@/lib/services/geography'
import { getPriceLists } from '@/lib/services/price-lists'
import { supabase } from '@/lib/supabase/client'
import { useAuthStore } from '@/stores/auth-store'
import type { Customer, CustomerInput, CustomerBranch, CustomerContact, CustomerCreditHistory, Governorate, City, Area, PriceList } from '@/lib/types/master-data'

export default function CustomerFormPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const isEdit = !!id

  const [loading, setLoading] = useState(isEdit)
  const [saving, setSaving] = useState(false)
  const [tab, setTab] = useState<'info' | 'branches' | 'contacts' | 'credit'>('info')
  const [governorates, setGovernorates] = useState<Governorate[]>([])
  const [cities, setCities] = useState<City[]>([])
  const [areas, setAreas] = useState<Area[]>([])
  const [priceLists, setPriceLists] = useState<PriceList[]>([])
  const [reps, setReps] = useState<{ id: string; full_name: string }[]>([])

  // Customer data for display
  const [customerData, setCustomerData] = useState<Customer | null>(null)

  const [form, setForm] = useState<CustomerInput>({
    name: '', type: 'retail', governorate_id: null, city_id: null, area_id: null,
    address: '', phone: '', mobile: '', email: '', tax_number: '',
    payment_terms: 'cash', credit_limit: 0, credit_days: 0, opening_balance: 0,
    price_list_id: null, assigned_rep_id: null, notes: '',
  })

  // Location display
  const [location, setLocation] = useState<{ lat: number | null; lng: number | null; accuracy: number | null; updatedAt: string | null }>({ lat: null, lng: null, accuracy: null, updatedAt: null })

  const [branches, setBranches] = useState<CustomerBranch[]>([])
  const [contacts, setContacts] = useState<CustomerContact[]>([])
  const [creditHistory, setCreditHistory] = useState<CustomerCreditHistory[]>([])

  // Counts for tabs
  const [counts, setCounts] = useState({ branches: 0, contacts: 0, credit: 0 })

  // Default branch/contact for creation flow
  const [createDefaults, setCreateDefaults] = useState({
    createBranch: true,
    branchName: '',
    branchNameManual: false,  // true when user manually edited the name
    createContact: false,
    contactName: '',
    contactRole: '',
    contactPhone: '',
    contactEmail: '',
  })
  const [gpsLoading, setGpsLoading] = useState(false)

  // Modals
  const [branchModal, setBranchModal] = useState<{ open: boolean; editing?: CustomerBranch }>({ open: false })
  const [branchForm, setBranchForm] = useState({ name: '', address: '', phone: '', contact_name: '', latitude: '' as string | number, longitude: '' as string | number, is_primary: false })
  const [contactModal, setContactModal] = useState<{ open: boolean; editing?: CustomerContact }>({ open: false })
  const [contactForm, setContactForm] = useState({ name: '', role: '', phone: '', email: '', is_primary: false })
  const [modalSaving, setModalSaving] = useState(false)
  const [branchGpsLoading, setBranchGpsLoading] = useState(false)

  useEffect(() => {
    const load = async () => {
      const [govs, pls] = await Promise.all([getGovernorates(), getPriceLists()])
      setGovernorates(govs)
      setPriceLists(pls)

      // Load reps
      const { data: repData } = await supabase
        .from('profiles').select('id, full_name').eq('status', 'active').order('full_name')
      if (repData) setReps(repData)

      if (id) {
        try {
          const c = await getCustomer(id)
          setCustomerData(c)
          setForm({
            name: c.name, type: c.type, governorate_id: c.governorate_id, city_id: c.city_id,
            area_id: c.area_id, address: c.address || '', phone: c.phone || '', mobile: c.mobile || '',
            email: c.email || '', tax_number: c.tax_number || '', payment_terms: c.payment_terms,
            credit_limit: c.credit_limit, credit_days: c.credit_days, opening_balance: c.opening_balance,
            price_list_id: c.price_list_id, assigned_rep_id: c.assigned_rep_id, notes: c.notes || '',
          })
          setLocation({
            lat: c.latitude ?? null, lng: c.longitude ?? null,
            accuracy: c.location_accuracy ?? null, updatedAt: c.location_updated_at ?? null,
          })
          if (c.governorate_id) setCities(await getCities(c.governorate_id))
          if (c.city_id) setAreas(await getAreas(c.city_id))

          // Load counts
          const [brRes, ctRes, crRes] = await Promise.all([
            getCustomerBranches(id),
            getCustomerContacts(id),
            getCreditHistory(id),
          ])
          setBranches(brRes); setContacts(ctRes); setCreditHistory(crRes)
          setCounts({ branches: brRes.length, contacts: ctRes.length, credit: crRes.length })
        } catch { toast.error('فشل تحميل بيانات العميل') }
      }
      setLoading(false)
    }
    load()
  }, [id])

  const refreshBranches = async () => {
    if (!id) return
    const data = await getCustomerBranches(id)
    setBranches(data)
    setCounts(c => ({ ...c, branches: data.length }))
  }
  const refreshContacts = async () => {
    if (!id) return
    const data = await getCustomerContacts(id)
    setContacts(data)
    setCounts(c => ({ ...c, contacts: data.length }))
  }
  const refreshCredit = async () => {
    if (!id) return
    const data = await getCreditHistory(id)
    setCreditHistory(data)
    setCounts(c => ({ ...c, credit: data.length }))
  }

  const handleGovChange = async (govId: string) => {
    setForm(f => ({ ...f, governorate_id: govId || null, city_id: null, area_id: null }))
    setCities(govId ? await getCities(govId) : [])
    setAreas([])
  }

  const handleCityChange = async (cityId: string) => {
    setForm(f => ({ ...f, city_id: cityId || null, area_id: null }))
    setAreas(cityId ? await getAreas(cityId) : [])
  }

  // GPS capture (customer location)
  const captureGPS = async () => {
    if (!navigator.geolocation) { toast.error('المتصفح لا يدعم خدمات الموقع'); return }
    setGpsLoading(true)
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const lat = pos.coords.latitude
        const lng = pos.coords.longitude
        const acc = pos.coords.accuracy
        if (isEdit && id) {
          try {
            const { updateCustomerLocation } = await import('@/lib/services/customers')
            await updateCustomerLocation(id, { latitude: lat, longitude: lng, location_accuracy: acc })
            setLocation({ lat, lng, accuracy: acc, updatedAt: new Date().toISOString() })
            toast.success('تم تحديث الموقع بنجاح')
          } catch { toast.error('فشل حفظ الموقع') }
        } else {
          setLocation({ lat, lng, accuracy: acc, updatedAt: new Date().toISOString() })
          toast.success(`تم سحب الموقع: ${lat.toFixed(5)}, ${lng.toFixed(5)}`)
        }
        setGpsLoading(false)
      },
      (err) => {
        setGpsLoading(false)
        if (err.code === 1) toast.error('تم رفض صلاحية الموقع — اسمح للمتصفح بالوصول')
        else if (err.code === 2) toast.error('الموقع غير متاح حالياً')
        else toast.error('انتهت مهلة سحب الموقع')
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
    )
  }

  // GPS capture (branch modal)
  const captureBranchGPS = () => {
    if (!navigator.geolocation) { toast.error('المتصفح لا يدعم خدمات الموقع'); return }
    setBranchGpsLoading(true)
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setBranchForm(f => ({ ...f, latitude: pos.coords.latitude, longitude: pos.coords.longitude }))
        setBranchGpsLoading(false)
        toast.success('تم سحب الموقع')
      },
      () => { setBranchGpsLoading(false); toast.error('فشل سحب الموقع') },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
    )
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.name.trim()) { toast.error('يرجى إدخال اسم العميل'); return }
    setSaving(true)
    try {
      if (isEdit) {
        await updateCustomer(id!, form)
        toast.success('تم تحديث العميل')
        const c = await getCustomer(id!)
        setCustomerData(c)
      } else {
        const created = await createCustomer(form)

        // Auto-create default branch
        if (createDefaults.createBranch) {
          try {
            await saveCustomerBranch(created.id, {
              name: createDefaults.branchName || 'الفرع الرئيسي',
              address: form.address || null,
              phone: form.phone || form.mobile || null,
              contact_name: createDefaults.contactName || null,
              latitude: location.lat,
              longitude: location.lng,
              is_primary: true,
            } as any)
          } catch {}
        }

        // Auto-create default contact
        if (createDefaults.createContact && createDefaults.contactName.trim()) {
          try {
            await saveCustomerContact(created.id, {
              name: createDefaults.contactName,
              role: createDefaults.contactRole || null,
              phone: createDefaults.contactPhone || form.mobile || form.phone || null,
              email: createDefaults.contactEmail || form.email || null,
              is_primary: true,
            } as any)
          } catch {}
        }

        toast.success('تم إنشاء العميل بنجاح')
        navigate('/customers')
      }
    } catch (err: any) { toast.error(err?.message || 'فشلت العملية') }
    finally { setSaving(false) }
  }

  const updateForm = (key: string, value: any) => {
    setForm(f => ({ ...f, [key]: value }))
    // Sync branch name with customer name (if not manually edited)
    if (key === 'name' && !isEdit && !createDefaults.branchNameManual) {
      setCreateDefaults(d => ({ ...d, branchName: value }))
    }
  }

  // Branch CRUD
  const openBranchCreate = () => {
    setBranchForm({ name: '', address: '', phone: '', contact_name: '', latitude: '', longitude: '', is_primary: false })
    setBranchModal({ open: true })
  }
  const openBranchEdit = (b: CustomerBranch) => {
    setBranchForm({
      name: b.name, address: b.address || '', phone: b.phone || '', contact_name: b.contact_name || '',
      latitude: b.latitude ?? '', longitude: b.longitude ?? '', is_primary: b.is_primary,
    })
    setBranchModal({ open: true, editing: b })
  }
  const saveBranch = async () => {
    if (!branchForm.name.trim()) { toast.error('يرجى إدخال اسم الفرع'); return }
    setModalSaving(true)
    try {
      const payload = {
        name: branchForm.name,
        address: branchForm.address || null,
        phone: branchForm.phone || null,
        contact_name: branchForm.contact_name || null,
        latitude: branchForm.latitude ? Number(branchForm.latitude) : null,
        longitude: branchForm.longitude ? Number(branchForm.longitude) : null,
        is_primary: branchForm.is_primary,
      }
      await saveCustomerBranch(id!, payload as any, branchModal.editing?.id)
      toast.success(branchModal.editing ? 'تم التحديث' : 'تم الإضافة')
      setBranchModal({ open: false })
      await refreshBranches()
    } catch { toast.error('فشلت العملية') }
    finally { setModalSaving(false) }
  }
  const deleteBranch = async (bid: string) => {
    if (!confirm('حذف هذا الفرع؟')) return
    try { await deleteCustomerBranch(bid); toast.success('تم الحذف'); await refreshBranches() }
    catch { toast.error('فشل الحذف') }
  }

  // Contact CRUD
  const openContactCreate = () => { setContactForm({ name: '', role: '', phone: '', email: '', is_primary: false }); setContactModal({ open: true }) }
  const openContactEdit = (c: CustomerContact) => { setContactForm({ name: c.name, role: c.role || '', phone: c.phone || '', email: c.email || '', is_primary: c.is_primary }); setContactModal({ open: true, editing: c }) }
  const saveContact = async () => {
    if (!contactForm.name.trim()) { toast.error('يرجى إدخال الاسم'); return }
    setModalSaving(true)
    try {
      await saveCustomerContact(id!, contactForm, contactModal.editing?.id)
      toast.success(contactModal.editing ? 'تم التحديث' : 'تم الإضافة')
      setContactModal({ open: false })
      await refreshContacts()
    } catch { toast.error('فشلت العملية') }
    finally { setModalSaving(false) }
  }
  const deleteContact = async (cid: string) => {
    if (!confirm('حذف جهة الاتصال؟')) return
    try { await deleteCustomerContact(cid); toast.success('تم الحذف'); await refreshContacts() }
    catch { toast.error('فشل الحذف') }
  }

  const typeLabels: Record<string, string> = { retail: 'تجزئة', wholesale: 'جملة', distributor: 'موزع' }
  const typeBadge: Record<string, string> = { retail: 'badge-neutral', wholesale: 'badge-info', distributor: 'badge-primary' }
  const paymentLabels: Record<string, string> = { cash: 'نقدي', credit: 'آجل', mixed: 'مختلط' }

  if (loading) return (
    <div className="page-container animate-enter">
      <div style={{ padding: 'var(--space-6)' }}>
        {[1,2,3].map(i => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 'var(--space-4)' }} />)}
      </div>
    </div>
  )

  return (
    <div className="page-container animate-enter">
      {/* Header */}
      <div className="page-header">
        <div className="page-header-info">
          <button className="btn btn-ghost btn-sm" onClick={() => navigate('/customers')} style={{ marginBottom: 'var(--space-2)' }}>
            <ArrowRight size={14} /> العودة للعملاء
          </button>
          <h1 className="page-title">{isEdit ? 'تفاصيل العميل' : 'إضافة عميل جديد'}</h1>
        </div>
      </div>

      {/* ═══════ بطاقة الملخص (تعديل فقط) ═══════ */}
      {isEdit && customerData && (
        <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
          <div className="flex items-center gap-4" style={{ flexWrap: 'wrap' }}>
            <div style={{ width: 48, height: 48, borderRadius: 'var(--radius-full)', background: 'var(--bg-accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              <User size={24} style={{ color: 'var(--color-primary)' }} />
            </div>
            <div style={{ flex: 1, minWidth: 200 }}>
              <div style={{ fontWeight: 700, fontSize: 'var(--text-lg)' }}>{customerData.name}</div>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap', marginTop: 2 }}>
                <span dir="ltr" style={{ fontFamily: 'monospace', fontWeight: 600 }}>{customerData.code}</span>
                {customerData.mobile && <span dir="ltr">• {customerData.mobile}</span>}
                {customerData.phone && <span dir="ltr">• {customerData.phone}</span>}
                {customerData.email && <span>• {customerData.email}</span>}
              </div>
            </div>
            <div className="flex gap-2" style={{ flexWrap: 'wrap' }}>
              <span className={`badge ${typeBadge[customerData.type] || 'badge-neutral'}`}>{typeLabels[customerData.type]}</span>
              <span className={`badge ${customerData.is_active ? 'badge-success' : 'badge-danger'}`}>{customerData.is_active ? 'نشط' : 'معطل'}</span>
              <span className={`badge ${customerData.payment_terms === 'credit' ? 'badge-warning' : 'badge-success'}`}>{paymentLabels[customerData.payment_terms]}</span>
              {customerData.credit_limit > 0 && (
                <span className="badge badge-neutral">حد ائتمان: {customerData.credit_limit.toLocaleString('ar-EG-u-nu-latn')}</span>
              )}
            </div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', textAlign: 'end' }}>
              <div>أُنشئ: {new Date(customerData.created_at).toLocaleDateString('ar-EG-u-nu-latn')}</div>
              {customerData.assigned_rep && <div>المندوب: {customerData.assigned_rep.full_name}</div>}
            </div>
          </div>
        </div>
      )}

      {/* ═══════ التابات ═══════ */}
      {isEdit && (
        <div className="tabs" style={{ marginBottom: 'var(--space-4)' }}>
          <button className={`tab ${tab === 'info' ? 'active' : ''}`} onClick={() => setTab('info')}>
            البيانات الأساسية
          </button>
          <button className={`tab ${tab === 'branches' ? 'active' : ''}`} onClick={() => setTab('branches')}>
            الفروع {counts.branches > 0 && <span className="badge badge-neutral" style={{ marginRight: 'var(--space-1)', fontSize: '10px', padding: '0 6px' }}>{counts.branches}</span>}
          </button>
          <button className={`tab ${tab === 'contacts' ? 'active' : ''}`} onClick={() => setTab('contacts')}>
            جهات الاتصال {counts.contacts > 0 && <span className="badge badge-neutral" style={{ marginRight: 'var(--space-1)', fontSize: '10px', padding: '0 6px' }}>{counts.contacts}</span>}
          </button>
          {can('customers.credit.update') && (
            <button className={`tab ${tab === 'credit' ? 'active' : ''}`} onClick={() => setTab('credit')}>
              سجل الائتمان {counts.credit > 0 && <span className="badge badge-neutral" style={{ marginRight: 'var(--space-1)', fontSize: '10px', padding: '0 6px' }}>{counts.credit}</span>}
            </button>
          )}
        </div>
      )}

      {/* ═══════ TAB: INFO ═══════ */}
      {tab === 'info' && (
        <form onSubmit={handleSubmit}>
          {/* Basic Info */}
          <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-4)' }}>
            <h2 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-5)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <User size={18} style={{ color: 'var(--color-primary)' }} /> المعلومات الأساسية
            </h2>
            <div className="grid grid-2 gap-4">
              <div className="form-group">
                <label className="form-label required">اسم العميل</label>
                <input className="form-input" value={form.name} onChange={e => updateForm('name', e.target.value)} autoFocus />
              </div>
              <div className="form-group">
                <label className="form-label">نوع العميل</label>
                <select className="form-select" value={form.type} onChange={e => updateForm('type', e.target.value)}>
                  <option value="retail">تجزئة</option>
                  <option value="wholesale">جملة</option>
                  <option value="distributor">موزع</option>
                </select>
              </div>
              <div className="form-group">
                <label className="form-label">الهاتف</label>
                <input className="form-input" dir="ltr" value={form.phone || ''} onChange={e => updateForm('phone', e.target.value)} placeholder="الهاتف الأرضي" />
              </div>
              <div className="form-group">
                <label className="form-label">الجوال</label>
                <input className="form-input" dir="ltr" value={form.mobile || ''} onChange={e => updateForm('mobile', e.target.value)} placeholder="رقم الجوال" />
              </div>
              <div className="form-group">
                <label className="form-label">البريد الإلكتروني</label>
                <input type="email" className="form-input" dir="ltr" value={form.email || ''} onChange={e => updateForm('email', e.target.value)} placeholder="email@example.com" />
              </div>
              <div className="form-group">
                <label className="form-label">الرقم الضريبي</label>
                <input className="form-input" dir="ltr" value={form.tax_number || ''} onChange={e => updateForm('tax_number', e.target.value)} placeholder="رقم التسجيل الضريبي" />
              </div>
            </div>
          </div>

          {/* Address */}
          <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-4)' }}>
            <h2 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-5)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <MapPin size={18} style={{ color: 'var(--color-primary)' }} /> العنوان
            </h2>
            <div className="grid grid-3 gap-4">
              <div className="form-group">
                <label className="form-label">المحافظة</label>
                <select className="form-select" value={form.governorate_id || ''} onChange={e => handleGovChange(e.target.value)}>
                  <option value="">اختر المحافظة</option>
                  {governorates.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label className="form-label">المدينة</label>
                <select className="form-select" value={form.city_id || ''} onChange={e => handleCityChange(e.target.value)} disabled={!cities.length}>
                  <option value="">اختر المدينة</option>
                  {cities.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label className="form-label">المنطقة</label>
                <select className="form-select" value={form.area_id || ''} onChange={e => updateForm('area_id', e.target.value || null)} disabled={!areas.length}>
                  <option value="">اختر المنطقة</option>
                  {areas.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}
                </select>
              </div>
            </div>
            <div className="form-group" style={{ marginTop: 'var(--space-4)' }}>
              <label className="form-label">العنوان التفصيلي</label>
              <textarea className="form-textarea" rows={2} value={form.address || ''} onChange={e => updateForm('address', e.target.value)} placeholder="الشارع، رقم المبنى، الطابق..." />
            </div>
            {/* GPS Location */}
            <div className="gps-row" style={{ marginTop: 'var(--space-4)' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-3)' }}>
                <MapPin size={16} style={{ color: 'var(--color-primary)' }} />
                {location.lat ? (
                  <div style={{ fontSize: 'var(--text-xs)' }}>
                    <span style={{ fontWeight: 600 }}>الموقع GPS:</span>{' '}
                    <span dir="ltr">{location.lat?.toFixed(6)}, {location.lng?.toFixed(6)}</span>
                    {location.accuracy && <span style={{ color: 'var(--text-muted)' }}> (دقة: {location.accuracy.toFixed(0)}م)</span>}
                    {location.updatedAt && <span style={{ color: 'var(--text-muted)' }}> — {new Date(location.updatedAt).toLocaleDateString('ar-EG-u-nu-latn')}</span>}
                  </div>
                ) : (
                  <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>لم يتم تحديد الموقع بعد</span>
                )}
              </div>
              <button type="button" className="btn btn-sm btn-primary" onClick={captureGPS} disabled={gpsLoading} style={{ flexShrink: 0 }}>
                {gpsLoading ? <Loader2 size={14} className="animate-spin" /> : <Navigation size={14} />}
                {gpsLoading ? 'جاري السحب...' : location.lat ? 'تحديث الموقع' : 'سحب الموقع'}
              </button>
            </div>
          </div>

          {/* Payment + Credit + Assignment */}
          <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-4)' }}>
            <h2 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-5)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <CreditCard size={18} style={{ color: 'var(--color-primary)' }} /> شروط الدفع والائتمان
            </h2>
            <div className="grid grid-3 gap-4">
              <div className="form-group">
                <label className="form-label">طريقة الدفع</label>
                <select className="form-select" value={form.payment_terms} onChange={e => updateForm('payment_terms', e.target.value)}>
                  <option value="cash">نقدي</option>
                  <option value="credit">آجل</option>
                  <option value="mixed">مختلط</option>
                </select>
              </div>
              <div className="form-group">
                <label className="form-label">حد الائتمان</label>
                <input type="number" className="form-input" dir="ltr" min={0} step={100} value={form.credit_limit} onChange={e => updateForm('credit_limit', +e.target.value)} />
              </div>
              <div className="form-group">
                <label className="form-label">أيام السداد</label>
                <input type="number" className="form-input" dir="ltr" min={0} value={form.credit_days} onChange={e => updateForm('credit_days', +e.target.value)} />
              </div>
              <div className="form-group">
                <label className="form-label">الرصيد الافتتاحي</label>
                <input type="number" className="form-input" dir="ltr" step={0.01} value={form.opening_balance} onChange={e => updateForm('opening_balance', +e.target.value)} />
              </div>
            </div>
            <div className="grid grid-2 gap-4" style={{ marginTop: 'var(--space-4)' }}>
              <div className="form-group">
                <label className="form-label">قائمة الأسعار</label>
                <select className="form-select" value={form.price_list_id || ''} onChange={e => updateForm('price_list_id', e.target.value || null)}>
                  <option value="">بدون (القائمة الافتراضية)</option>
                  {priceLists.filter(pl => pl.is_active).map(pl => (
                    <option key={pl.id} value={pl.id}>{pl.name}{pl.is_default ? ' ⭐' : ''}</option>
                  ))}
                </select>
              </div>
              <div className="form-group">
                <label className="form-label">المندوب المسؤول</label>
                <select className="form-select" value={form.assigned_rep_id || ''} onChange={e => updateForm('assigned_rep_id', e.target.value || null)}>
                  <option value="">بدون مندوب</option>
                  {reps.map(r => <option key={r.id} value={r.id}>{r.full_name}</option>)}
                </select>
              </div>
            </div>
          </div>

          {/* ═══════ Creation Defaults: Branch + Contact ═══════ */}
          {!isEdit && (
            <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-4)', border: '1px dashed var(--border-primary)' }}>
              <h2 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-5)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
                <UserPlus size={18} style={{ color: 'var(--color-primary)' }} /> بيانات أولية (فرع + جهة اتصال)
              </h2>
              <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 'var(--space-4)' }}>
                سيتم إنشاء فرع رئيسي وجهة اتصال أساسية تلقائياً عند حفظ العميل. الفرع يستخدم العنوان والهاتف والموقع المدخل أعلاه.
              </p>

              {/* Default Branch */}
              <div style={{ marginBottom: 'var(--space-4)', padding: 'var(--space-4)', background: 'var(--bg-secondary)', borderRadius: 'var(--radius-md)' }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: createDefaults.createBranch ? 'var(--space-3)' : 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', fontWeight: 600, fontSize: 'var(--text-sm)' }}>
                    <Building size={14} style={{ color: 'var(--color-primary)' }} /> إنشاء فرع رئيسي تلقائياً
                  </div>
                  <label className="toggle-switch">
                    <input type="checkbox" checked={createDefaults.createBranch} onChange={e => setCreateDefaults(d => ({ ...d, createBranch: e.target.checked }))} />
                    <span className="toggle-slider" />
                  </label>
                </div>
                {createDefaults.createBranch && (
                  <div className="form-group" style={{ marginBottom: 0 }}>
                    <label className="form-label" style={{ fontSize: 'var(--text-xs)' }}>اسم الفرع <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>(يتزامن مع اسم العميل)</span></label>
                    <input className="form-input" value={createDefaults.branchName}
                      onChange={e => setCreateDefaults(d => ({ ...d, branchName: e.target.value, branchNameManual: true }))} placeholder="يأخذ اسم العميل تلقائياً" />
                  </div>
                )}
              </div>

              {/* Default Contact */}
              <div style={{ padding: 'var(--space-4)', background: 'var(--bg-secondary)', borderRadius: 'var(--radius-md)' }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: createDefaults.createContact ? 'var(--space-3)' : 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', fontWeight: 600, fontSize: 'var(--text-sm)' }}>
                    <Users size={14} style={{ color: 'var(--color-primary)' }} /> إنشاء جهة اتصال أساسية
                  </div>
                  <label className="toggle-switch">
                    <input type="checkbox" checked={createDefaults.createContact} onChange={e => setCreateDefaults(d => ({ ...d, createContact: e.target.checked }))} />
                    <span className="toggle-slider" />
                  </label>
                </div>
                {createDefaults.createContact && (
                  <div className="grid grid-2 gap-3">
                    <div className="form-group">
                      <label className="form-label" style={{ fontSize: 'var(--text-xs)' }}>اسم جهة الاتصال</label>
                      <input className="form-input" value={createDefaults.contactName}
                        onChange={e => setCreateDefaults(d => ({ ...d, contactName: e.target.value }))} placeholder="مثال: أحمد محمد" />
                    </div>
                    <div className="form-group">
                      <label className="form-label" style={{ fontSize: 'var(--text-xs)' }}>الوظيفة</label>
                      <input className="form-input" value={createDefaults.contactRole}
                        onChange={e => setCreateDefaults(d => ({ ...d, contactRole: e.target.value }))} placeholder="مدير المشتريات" />
                    </div>
                    <div className="form-group">
                      <label className="form-label" style={{ fontSize: 'var(--text-xs)' }}>هاتف جهة الاتصال</label>
                      <input className="form-input" dir="ltr" value={createDefaults.contactPhone}
                        onChange={e => setCreateDefaults(d => ({ ...d, contactPhone: e.target.value }))} placeholder="يستخدم جوال العميل إن ترك فارغاً" />
                    </div>
                    <div className="form-group">
                      <label className="form-label" style={{ fontSize: 'var(--text-xs)' }}>بريد جهة الاتصال</label>
                      <input className="form-input" dir="ltr" value={createDefaults.contactEmail}
                        onChange={e => setCreateDefaults(d => ({ ...d, contactEmail: e.target.value }))} placeholder="يستخدم بريد العميل إن ترك فارغاً" />
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Notes */}
          <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-4)' }}>
            <label className="form-label">ملاحظات</label>
            <textarea className="form-textarea" rows={2} value={form.notes || ''} onChange={e => updateForm('notes', e.target.value)} placeholder="ملاحظات إضافية عن العميل..." />
          </div>

          <div className="flex justify-between" style={{ paddingTop: 'var(--space-4)' }}>
            <button type="button" className="btn btn-secondary" onClick={() => navigate('/customers')}>إلغاء</button>
            <button type="submit" className="btn btn-primary btn-lg" disabled={saving}>
              {saving ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />}
              {saving ? 'جاري الحفظ...' : isEdit ? 'تحديث' : 'حفظ العميل'}
            </button>
          </div>
        </form>
      )}

      {/* ═══════ TAB: BRANCHES ═══════ */}
      {tab === 'branches' && (
        <div className="edara-card" style={{ padding: 'var(--space-6)' }}>
          <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-4)' }}>
            <h2 style={{ fontSize: 'var(--text-base)', fontWeight: 700, display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Building size={18} style={{ color: 'var(--color-primary)' }} /> فروع العميل
            </h2>
            {can('customers.update') && (
              <button className="btn btn-primary btn-sm" onClick={openBranchCreate}><Plus size={14} /> إضافة فرع</button>
            )}
          </div>
          {branches.length === 0 ? (
            <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
              <Building size={40} className="empty-state-icon" />
              <p className="empty-state-title">لا يوجد فروع لهذا العميل</p>
              <p className="empty-state-text">أضف فرعاً لتسجيل مواقع التسليم</p>
            </div>
          ) : (
            <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))' }}>
              {branches.map(b => (
                <div key={b.id} className="edara-card" style={{
                  padding: 'var(--space-4)', border: b.is_primary ? '2px solid var(--color-primary)' : '1px solid var(--border-primary)',
                  position: 'relative'
                }}>
                  {b.is_primary && <span className="badge badge-primary" style={{ position: 'absolute', top: 8, left: 8, fontSize: '10px' }}>أساسي</span>}
                  <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', marginBottom: 'var(--space-2)' }}>{b.name}</div>
                  {b.address && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginBottom: 'var(--space-1)' }}>📍 {b.address}</div>}
                  {b.phone && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginBottom: 'var(--space-1)' }} dir="ltr">📞 {b.phone}</div>}
                  {b.contact_name && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginBottom: 'var(--space-1)' }}>👤 {b.contact_name}</div>}
                  {b.latitude && b.longitude && (
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }} dir="ltr">
                      <MapPin size={10} style={{ display: 'inline' }} /> {Number(b.latitude).toFixed(5)}, {Number(b.longitude).toFixed(5)}
                    </div>
                  )}
                  {can('customers.update') && (
                    <div className="flex gap-1" style={{ marginTop: 'var(--space-3)' }}>
                      <button className="btn btn-ghost btn-sm" onClick={() => openBranchEdit(b)}><Edit size={12} /> تعديل</button>
                      <button className="btn btn-danger btn-sm" onClick={() => deleteBranch(b.id)}><Trash2 size={12} /></button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ═══════ TAB: CONTACTS ═══════ */}
      {tab === 'contacts' && (
        <div className="edara-card" style={{ padding: 'var(--space-6)' }}>
          <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-4)' }}>
            <h2 style={{ fontSize: 'var(--text-base)', fontWeight: 700, display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Users size={18} style={{ color: 'var(--color-primary)' }} /> جهات الاتصال
            </h2>
            {can('customers.update') && (
              <button className="btn btn-primary btn-sm" onClick={openContactCreate}><Plus size={14} /> إضافة جهة اتصال</button>
            )}
          </div>
          {contacts.length === 0 ? (
            <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
              <Users size={40} className="empty-state-icon" />
              <p className="empty-state-title">لا يوجد جهات اتصال</p>
              <p className="empty-state-text">أضف جهات الاتصال الخاصة بهذا العميل</p>
            </div>
          ) : (
            <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))' }}>
              {contacts.map(c => (
                <div key={c.id} className="edara-card" style={{
                  padding: 'var(--space-4)', border: c.is_primary ? '2px solid var(--color-primary)' : '1px solid var(--border-primary)',
                  position: 'relative'
                }}>
                  {c.is_primary && <span className="badge badge-primary" style={{ position: 'absolute', top: 8, left: 8, fontSize: '10px' }}>أساسي</span>}
                  <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', marginBottom: 'var(--space-2)' }}>{c.name}</div>
                  {c.role && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginBottom: 'var(--space-1)' }}>💼 {c.role}</div>}
                  {c.phone && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginBottom: 'var(--space-1)' }} dir="ltr">📞 {c.phone}</div>}
                  {c.email && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }} dir="ltr">📧 {c.email}</div>}
                  {can('customers.update') && (
                    <div className="flex gap-1" style={{ marginTop: 'var(--space-3)' }}>
                      <button className="btn btn-ghost btn-sm" onClick={() => openContactEdit(c)}><Edit size={12} /> تعديل</button>
                      <button className="btn btn-danger btn-sm" onClick={() => deleteContact(c.id)}><Trash2 size={12} /></button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ═══════ TAB: CREDIT HISTORY ═══════ */}
      {tab === 'credit' && (
        <div className="edara-card" style={{ padding: 'var(--space-6)' }}>
          <h2 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-4)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
            <History size={18} style={{ color: 'var(--color-primary)' }} /> سجل تغييرات الائتمان
          </h2>
          {creditHistory.length === 0 ? (
            <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
              <History size={40} className="empty-state-icon" />
              <p className="empty-state-title">لا يوجد تغييرات مسجلة</p>
              <p className="empty-state-text">سيتم تسجيل التغييرات تلقائياً عند تعديل حد الائتمان</p>
            </div>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>التاريخ</th>
                  <th>الحد قبل</th>
                  <th>الحد بعد</th>
                  <th>التغيير</th>
                  <th>بواسطة</th>
                  <th>السبب</th>
                </tr>
              </thead>
              <tbody>
                {creditHistory.map(h => {
                  const diff = h.limit_after - h.limit_before
                  return (
                    <tr key={h.id}>
                      <td style={{ fontSize: 'var(--text-xs)', whiteSpace: 'nowrap' }}>
                        {new Date(h.created_at).toLocaleDateString('ar-EG-u-nu-latn')}
                        <div style={{ color: 'var(--text-muted)' }}>{new Date(h.created_at).toLocaleTimeString('ar-EG-u-nu-latn', { hour: '2-digit', minute: '2-digit' })}</div>
                      </td>
                      <td style={{ fontVariantNumeric: 'tabular-nums' }}>{h.limit_before.toLocaleString('ar-EG-u-nu-latn')}</td>
                      <td style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{h.limit_after.toLocaleString('ar-EG-u-nu-latn')}</td>
                      <td>
                        <span style={{ color: diff > 0 ? 'var(--color-success)' : diff < 0 ? 'var(--color-danger)' : 'var(--text-muted)', fontWeight: 600 }}>
                          {diff > 0 ? '+' : ''}{diff.toLocaleString('ar-EG-u-nu-latn')}
                        </span>
                      </td>
                      <td>{h.changed_by_profile?.full_name || '—'}</td>
                      <td style={{ color: 'var(--text-secondary)', maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis' }}>{h.reason || '—'}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* ═══════ MODAL: Branch ═══════ */}
      {branchModal.open && (
        <div className="modal-overlay" onClick={() => setBranchModal({ open: false })}>
          <div className="modal-box modal-md" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <span className="modal-title">{branchModal.editing ? 'تعديل فرع' : 'إضافة فرع'}</span>
              <button className="btn btn-ghost btn-icon" onClick={() => setBranchModal({ open: false })}>✕</button>
            </div>
            <div className="modal-body">
              <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
                <div className="grid grid-2 gap-4">
                  <div className="form-group">
                    <label className="form-label required">اسم الفرع</label>
                    <input className="form-input" value={branchForm.name} onChange={e => setBranchForm(f => ({ ...f, name: e.target.value }))} autoFocus />
                  </div>
                  <div className="form-group">
                    <label className="form-label">جهة الاتصال</label>
                    <input className="form-input" value={branchForm.contact_name} onChange={e => setBranchForm(f => ({ ...f, contact_name: e.target.value }))} />
                  </div>
                </div>
                <div className="grid grid-2 gap-4">
                  <div className="form-group">
                    <label className="form-label">العنوان</label>
                    <input className="form-input" value={branchForm.address} onChange={e => setBranchForm(f => ({ ...f, address: e.target.value }))} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">الهاتف</label>
                    <input className="form-input" dir="ltr" value={branchForm.phone} onChange={e => setBranchForm(f => ({ ...f, phone: e.target.value }))} />
                  </div>
                </div>
                <div className="grid grid-2 gap-4">
                  <div className="form-group">
                    <label className="form-label">خط العرض (Latitude)</label>
                    <input type="number" step="any" className="form-input" dir="ltr" value={branchForm.latitude} onChange={e => setBranchForm(f => ({ ...f, latitude: e.target.value }))} placeholder="30.0444" />
                  </div>
                  <div className="form-group">
                    <label className="form-label">خط الطول (Longitude)</label>
                    <input type="number" step="any" className="form-input" dir="ltr" value={branchForm.longitude} onChange={e => setBranchForm(f => ({ ...f, longitude: e.target.value }))} placeholder="31.2357" />
                  </div>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-3)' }}>
                  <button type="button" className="btn btn-sm btn-primary" onClick={captureBranchGPS} disabled={branchGpsLoading}>
                    {branchGpsLoading ? <Loader2 size={14} className="animate-spin" /> : <Navigation size={14} />}
                    {branchGpsLoading ? 'جاري السحب...' : 'سحب الموقع الحالي'}
                  </button>
                  {branchForm.latitude && branchForm.longitude && (
                    <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }} dir="ltr">
                      📍 {Number(branchForm.latitude).toFixed(5)}, {Number(branchForm.longitude).toFixed(5)}
                    </span>
                  )}
                </div>
                <label style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', cursor: 'pointer' }}>
                  <input type="checkbox" checked={branchForm.is_primary} onChange={e => setBranchForm(f => ({ ...f, is_primary: e.target.checked }))} />
                  فرع أساسي
                </label>
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setBranchModal({ open: false })}>إلغاء</button>
              <button className="btn btn-primary" onClick={saveBranch} disabled={modalSaving}>
                {modalSaving && <Loader2 size={14} className="animate-spin" />} {branchModal.editing ? 'تحديث' : 'إضافة'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ═══════ MODAL: Contact ═══════ */}
      {contactModal.open && (
        <div className="modal-overlay" onClick={() => setContactModal({ open: false })}>
          <div className="modal-box modal-md" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <span className="modal-title">{contactModal.editing ? 'تعديل جهة اتصال' : 'إضافة جهة اتصال'}</span>
              <button className="btn btn-ghost btn-icon" onClick={() => setContactModal({ open: false })}>✕</button>
            </div>
            <div className="modal-body">
              <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
                <div className="grid grid-2 gap-4">
                  <div className="form-group">
                    <label className="form-label required">الاسم</label>
                    <input className="form-input" value={contactForm.name} onChange={e => setContactForm(f => ({ ...f, name: e.target.value }))} autoFocus />
                  </div>
                  <div className="form-group">
                    <label className="form-label">الوظيفة</label>
                    <input className="form-input" value={contactForm.role} onChange={e => setContactForm(f => ({ ...f, role: e.target.value }))} placeholder="مثال: مدير المشتريات" />
                  </div>
                </div>
                <div className="grid grid-2 gap-4">
                  <div className="form-group">
                    <label className="form-label">الهاتف</label>
                    <input className="form-input" dir="ltr" value={contactForm.phone} onChange={e => setContactForm(f => ({ ...f, phone: e.target.value }))} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">البريد</label>
                    <input className="form-input" dir="ltr" value={contactForm.email} onChange={e => setContactForm(f => ({ ...f, email: e.target.value }))} />
                  </div>
                </div>
                <label style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', cursor: 'pointer' }}>
                  <input type="checkbox" checked={contactForm.is_primary} onChange={e => setContactForm(f => ({ ...f, is_primary: e.target.checked }))} />
                  جهة اتصال أساسية
                </label>
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setContactModal({ open: false })}>إلغاء</button>
              <button className="btn btn-primary" onClick={saveContact} disabled={modalSaving}>
                {modalSaving && <Loader2 size={14} className="animate-spin" />} {contactModal.editing ? 'تحديث' : 'إضافة'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
