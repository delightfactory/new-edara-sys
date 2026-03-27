import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { ArrowRight, Save, Loader2, Trash2, Plus, Edit, Check, Clock, AlertTriangle, CreditCard, Building, Users as UsersIcon, Bell } from 'lucide-react'
import { getSupplier, createSupplier, updateSupplier, getSupplierContacts, saveSupplierContact, deleteSupplierContact, getPaymentReminders, createPaymentReminder, updatePaymentReminderStatus } from '@/lib/services/suppliers'
import { getGovernorates, getCities } from '@/lib/services/geography'
import { useAuthStore } from '@/stores/auth-store'
import type { SupplierInput, SupplierContact, SupplierPaymentReminder, Governorate, City } from '@/lib/types/master-data'

export default function SupplierFormPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const isEdit = !!id

  const [loading, setLoading] = useState(isEdit)
  const [saving, setSaving] = useState(false)
  const [tab, setTab] = useState<'info' | 'contacts' | 'reminders'>('info')
  const [governorates, setGovernorates] = useState<Governorate[]>([])
  const [cities, setCities] = useState<City[]>([])
  const [contacts, setContacts] = useState<SupplierContact[]>([])
  const [reminders, setReminders] = useState<SupplierPaymentReminder[]>([])
  const [supplierCode, setSupplierCode] = useState('')
  const [supplierBalance, setSupplierBalance] = useState(0)

  // Modals
  const [contactModal, setContactModal] = useState<{ open: boolean; editing?: SupplierContact }>({ open: false })
  const [contactForm, setContactForm] = useState({ name: '', role: '', phone: '', email: '' })
  const [reminderModal, setReminderModal] = useState(false)
  const [reminderForm, setReminderForm] = useState({ due_date: '', amount: 0, invoice_ref: '', notify_before_days: 3 })
  const [modalSaving, setModalSaving] = useState(false)

  const [form, setForm] = useState<SupplierInput>({
    name: '', type: '', governorate_id: null, city_id: null,
    phone: '', email: '', tax_number: '', payment_terms: 'cash',
    credit_limit: 0, credit_days: 0, opening_balance: 0, bank_account: '',
  })

  useEffect(() => {
    const load = async () => {
      const govs = await getGovernorates()
      setGovernorates(govs)
      if (id) {
        try {
          const s = await getSupplier(id)
          setSupplierCode(s.code || '')
          setSupplierBalance(s.current_balance || 0)
          setForm({
            name: s.name, type: s.type || '', governorate_id: s.governorate_id,
            city_id: s.city_id, phone: s.phone || '', email: s.email || '',
            tax_number: s.tax_number || '', payment_terms: s.payment_terms || 'cash',
            credit_limit: s.credit_limit, credit_days: s.credit_days,
            opening_balance: s.opening_balance, bank_account: s.bank_account || '',
          })
          if (s.governorate_id) setCities(await getCities(s.governorate_id))
          // Preload counts
          const [cts, rems] = await Promise.all([
            getSupplierContacts(id),
            getPaymentReminders({ supplierId: id }),
          ])
          setContacts(cts)
          setReminders(rems.data)
        } catch { toast.error('فشل تحميل بيانات المورد') }
      }
      setLoading(false)
    }
    load()
  }, [id])

  useEffect(() => {
    if (!id) return
    if (tab === 'contacts') getSupplierContacts(id).then(setContacts).catch(() => {})
    if (tab === 'reminders') getPaymentReminders({ supplierId: id }).then(r => setReminders(r.data)).catch(() => {})
  }, [tab, id])

  const handleGovChange = async (govId: string) => {
    setForm(f => ({ ...f, governorate_id: govId || null, city_id: null }))
    setCities(govId ? await getCities(govId) : [])
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.name.trim()) { toast.error('يرجى إدخال اسم المورد'); return }
    setSaving(true)
    try {
      if (isEdit) { await updateSupplier(id!, form); toast.success('تم تحديث المورد') }
      else { await createSupplier(form); toast.success('تم إنشاء المورد'); navigate('/suppliers') }
    } catch (err: any) { toast.error(err?.message || 'فشلت العملية') }
    finally { setSaving(false) }
  }

  const updateField = (key: string, val: any) => setForm(f => ({ ...f, [key]: val }))

  const paymentLabels: Record<string, string> = { cash: 'نقدي', credit: 'آجل' }

  // Contact CRUD
  const openContactCreate = () => { setContactForm({ name: '', role: '', phone: '', email: '' }); setContactModal({ open: true }) }
  const openContactEdit = (c: SupplierContact) => { setContactForm({ name: c.name, role: c.role || '', phone: c.phone || '', email: c.email || '' }); setContactModal({ open: true, editing: c }) }
  const saveContact = async () => {
    if (!contactForm.name.trim()) { toast.error('يرجى إدخال الاسم'); return }
    setModalSaving(true)
    try {
      await saveSupplierContact(id!, contactForm, contactModal.editing?.id)
      toast.success(contactModal.editing ? 'تم التحديث' : 'تم الإضافة')
      setContactModal({ open: false })
      setContacts(await getSupplierContacts(id!))
    } catch { toast.error('فشلت العملية') }
    finally { setModalSaving(false) }
  }
  const deleteContact = async (cid: string) => {
    if (!confirm('حذف جهة الاتصال؟')) return
    try { await deleteSupplierContact(cid); toast.success('تم الحذف'); setContacts(c => c.filter(x => x.id !== cid)) }
    catch { toast.error('فشل الحذف') }
  }

  // Reminder CRUD
  const openReminderCreate = () => { setReminderForm({ due_date: '', amount: 0, invoice_ref: '', notify_before_days: 3 }); setReminderModal(true) }
  const saveReminder = async () => {
    if (!reminderForm.due_date || reminderForm.amount <= 0) { toast.error('يرجى ملء التاريخ والمبلغ'); return }
    setModalSaving(true)
    try {
      await createPaymentReminder({ supplier_id: id!, ...reminderForm })
      toast.success('تم إنشاء التذكير')
      setReminderModal(false)
      setReminders((await getPaymentReminders({ supplierId: id! })).data)
    } catch { toast.error('فشلت العملية') }
    finally { setModalSaving(false) }
  }
  const handleReminderStatus = async (rid: string, status: 'paid' | 'overdue') => {
    try {
      await updatePaymentReminderStatus(rid, status)
      toast.success('تم تحديث الحالة')
      setReminders((await getPaymentReminders({ supplierId: id! })).data)
    } catch { toast.error('فشلت العملية') }
  }

  const statusLabels: Record<string, { label: string; cls: string; icon: any }> = {
    pending: { label: 'معلق', cls: 'badge-warning', icon: Clock },
    paid: { label: 'مدفوع', cls: 'badge-success', icon: Check },
    overdue: { label: 'متأخر', cls: 'badge-danger', icon: AlertTriangle },
  }

  if (loading) return (
    <div className="page-container animate-enter">
      {[1,2,3].map(i => <div key={i} className="skeleton skeleton-row" style={{ margin: 'var(--space-4) var(--space-6)' }} />)}
    </div>
  )

  return (
    <div className="page-container animate-enter">
      <div className="page-header">
        <div className="page-header-info">
          <button className="btn btn-ghost btn-sm" onClick={() => navigate('/suppliers')} style={{ marginBottom: 'var(--space-2)' }}>
            <ArrowRight size={14} /> العودة للموردين
          </button>
          <h1 className="page-title">{isEdit ? form.name || 'تفاصيل المورد' : 'إضافة مورد جديد'}</h1>
        </div>
      </div>

      {/* ═══════ Summary Card ═══════ */}
      {isEdit && (
        <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)', display: 'flex', flexWrap: 'wrap', gap: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', padding: 'var(--space-2) var(--space-3)', background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-md)' }}>
            <CreditCard size={14} style={{ color: 'var(--color-primary)' }} />
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>الكود</span>
            <span style={{ fontWeight: 700, fontFamily: 'monospace', fontSize: 'var(--text-sm)' }} dir="ltr">{supplierCode}</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', padding: 'var(--space-2) var(--space-3)', background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-md)' }}>
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>الدفع</span>
            <span className={`badge ${form.payment_terms === 'cash' ? 'badge-success' : 'badge-warning'}`}>
              {paymentLabels[form.payment_terms || 'cash'] || form.payment_terms}
            </span>
          </div>
          {(form.credit_limit || 0) > 0 && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', padding: 'var(--space-2) var(--space-3)', background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-md)' }}>
              <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>حد الائتمان</span>
              <span style={{ fontWeight: 700, fontSize: 'var(--text-sm)' }}>{(form.credit_limit || 0).toLocaleString('ar-EG-u-nu-latn')}</span>
            </div>
          )}
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', padding: 'var(--space-2) var(--space-3)', background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-md)' }}>
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>الرصيد الحالي</span>
            <span style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--color-success)' }}>{(supplierBalance || 0).toLocaleString('ar-EG', { minimumFractionDigits: 2 })}</span>
          </div>
        </div>
      )}

      {isEdit && (
        <div className="tabs">
          <button className={`tab ${tab === 'info' ? 'active' : ''}`} onClick={() => setTab('info')}>
            <Building size={14} /> البيانات الأساسية
          </button>
          <button className={`tab ${tab === 'contacts' ? 'active' : ''}`} onClick={() => setTab('contacts')}>
            <UsersIcon size={14} /> جهات الاتصال
            {contacts.length > 0 && <span className="badge badge-neutral" style={{ marginRight: 'var(--space-1)' }}>{contacts.length}</span>}
          </button>
          <button className={`tab ${tab === 'reminders' ? 'active' : ''}`} onClick={() => setTab('reminders')}>
            <Bell size={14} /> تذكيرات السداد
            {reminders.length > 0 && <span className="badge badge-warning" style={{ marginRight: 'var(--space-1)' }}>{reminders.length}</span>}
          </button>
        </div>
      )}

      {tab === 'info' && (
        <form onSubmit={handleSubmit}>
          <div className="edara-card" style={{ padding: 'var(--space-6)', marginBottom: 'var(--space-4)' }}>
            <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-5)' }}>المعلومات الأساسية</h2>
            <div className="grid grid-2 gap-4">
              <div className="form-group">
                <label className="form-label required">اسم المورد</label>
                <input className="form-input" value={form.name} onChange={e => updateField('name', e.target.value)} autoFocus />
              </div>
              <div className="form-group">
                <label className="form-label">النوع</label>
                <input className="form-input" value={form.type || ''} onChange={e => updateField('type', e.target.value)} placeholder="مصنع / موزع / ..." />
              </div>
              <div className="form-group">
                <label className="form-label">الهاتف</label>
                <input className="form-input" dir="ltr" value={form.phone || ''} onChange={e => updateField('phone', e.target.value)} />
              </div>
              <div className="form-group">
                <label className="form-label">البريد</label>
                <input type="email" className="form-input" dir="ltr" value={form.email || ''} onChange={e => updateField('email', e.target.value)} />
              </div>
              <div className="form-group">
                <label className="form-label">المحافظة</label>
                <select className="form-select" value={form.governorate_id || ''} onChange={e => handleGovChange(e.target.value)}>
                  <option value="">اختر</option>
                  {governorates.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label className="form-label">المدينة</label>
                <select className="form-select" value={form.city_id || ''} onChange={e => updateField('city_id', e.target.value || null)} disabled={!cities.length}>
                  <option value="">اختر</option>
                  {cities.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label className="form-label">الرقم الضريبي</label>
                <input className="form-input" dir="ltr" value={form.tax_number || ''} onChange={e => updateField('tax_number', e.target.value)} />
              </div>
              <div className="form-group">
                <label className="form-label">الحساب البنكي</label>
                <input className="form-input" dir="ltr" value={form.bank_account || ''} onChange={e => updateField('bank_account', e.target.value)} />
              </div>
              <div className="form-group">
                <label className="form-label">طريقة الدفع</label>
                <select className="form-select" value={form.payment_terms || 'cash'} onChange={e => updateField('payment_terms', e.target.value)}>
                  <option value="cash">نقدي</option>
                  <option value="credit">آجل</option>
                </select>
              </div>
              <div className="form-group">
                <label className="form-label">حد الائتمان</label>
                <input type="number" className="form-input" dir="ltr" min={0} value={form.credit_limit} onChange={e => updateField('credit_limit', +e.target.value)} />
              </div>
              <div className="form-group">
                <label className="form-label">أيام السداد</label>
                <input type="number" className="form-input" dir="ltr" min={0} value={form.credit_days} onChange={e => updateField('credit_days', +e.target.value)} />
              </div>
              <div className="form-group">
                <label className="form-label">الرصيد الافتتاحي</label>
                <input type="number" className="form-input" dir="ltr" step={0.01} value={form.opening_balance} onChange={e => updateField('opening_balance', +e.target.value)} />
              </div>
            </div>
          </div>

          <div className="flex justify-between" style={{ paddingTop: 'var(--space-4)' }}>
            <button type="button" className="btn btn-secondary" onClick={() => navigate('/suppliers')}>إلغاء</button>
            <button type="submit" className="btn btn-primary btn-lg" disabled={saving}>
              {saving ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />}
              {saving ? 'جاري الحفظ...' : isEdit ? 'تحديث' : 'حفظ المورد'}
            </button>
          </div>
        </form>
      )}

      {/* ═══════ TAB: CONTACTS ═══════ */}
      {tab === 'contacts' && (
        <div className="edara-card" style={{ padding: 'var(--space-6)' }}>
          <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-4)' }}>
            <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>جهات الاتصال</h2>
            {can('suppliers.update') && (
              <button className="btn btn-primary btn-sm" onClick={openContactCreate}><Plus size={14} /> إضافة</button>
            )}
          </div>
          {contacts.length === 0 ? (
            <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا يوجد جهات اتصال</p>
          ) : (
            <table className="data-table">
              <thead><tr><th>الاسم</th><th>الوظيفة</th><th>الهاتف</th><th>البريد</th><th style={{ width: 90 }}></th></tr></thead>
              <tbody>
                {contacts.map(c => (
                  <tr key={c.id}>
                    <td style={{ fontWeight: 600 }}>{c.name}</td>
                    <td>{c.role || '—'}</td>
                    <td dir="ltr">{c.phone || '—'}</td>
                    <td dir="ltr">{c.email || '—'}</td>
                    <td>
                      <div className="flex gap-1">
                        <button className="btn btn-ghost btn-sm" onClick={() => openContactEdit(c)}><Edit size={12} /></button>
                        <button className="btn btn-danger btn-sm" onClick={() => deleteContact(c.id)}><Trash2 size={12} /></button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* ═══════ TAB: REMINDERS ═══════ */}
      {tab === 'reminders' && (
        <div className="edara-card" style={{ padding: 'var(--space-6)' }}>
          <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-4)' }}>
            <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>تذكيرات السداد</h2>
            {can('suppliers.update') && (
              <button className="btn btn-primary btn-sm" onClick={openReminderCreate}><Plus size={14} /> إضافة تذكير</button>
            )}
          </div>
          {reminders.length === 0 ? (
            <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا يوجد تذكيرات</p>
          ) : (
            <table className="data-table">
              <thead><tr><th>تاريخ الاستحقاق</th><th>المبلغ</th><th>مرجع الفاتورة</th><th>الحالة</th><th style={{ width: 120 }}>إجراءات</th></tr></thead>
              <tbody>
                {reminders.map(r => (
                  <tr key={r.id}>
                    <td>{new Date(r.due_date).toLocaleDateString('ar-EG-u-nu-latn')}</td>
                    <td style={{ fontWeight: 600 }}>{r.amount.toLocaleString('ar-EG-u-nu-latn')}</td>
                    <td>{r.invoice_ref || '—'}</td>
                    <td><span className={`badge ${statusLabels[r.status]?.cls || 'badge-neutral'}`}>{statusLabels[r.status]?.label || r.status}</span></td>
                    <td>
                      {r.status === 'pending' && (
                        <div className="flex gap-1">
                          <button className="btn btn-success btn-sm" title="تم الدفع" onClick={() => handleReminderStatus(r.id, 'paid')}><Check size={12} /></button>
                          <button className="btn btn-danger btn-sm" title="متأخر" onClick={() => handleReminderStatus(r.id, 'overdue')}><AlertTriangle size={12} /></button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
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
                    <input className="form-input" value={contactForm.role} onChange={e => setContactForm(f => ({ ...f, role: e.target.value }))} />
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

      {/* ═══════ MODAL: Reminder ═══════ */}
      {reminderModal && (
        <div className="modal-overlay" onClick={() => setReminderModal(false)}>
          <div className="modal-box modal-sm" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <span className="modal-title">إضافة تذكير سداد</span>
              <button className="btn btn-ghost btn-icon" onClick={() => setReminderModal(false)}>✕</button>
            </div>
            <div className="modal-body">
              <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
                <div className="form-group">
                  <label className="form-label required">تاريخ الاستحقاق</label>
                  <input type="date" className="form-input" dir="ltr" value={reminderForm.due_date} onChange={e => setReminderForm(f => ({ ...f, due_date: e.target.value }))} />
                </div>
                <div className="form-group">
                  <label className="form-label required">المبلغ</label>
                  <input type="number" className="form-input" dir="ltr" min={1} value={reminderForm.amount} onChange={e => setReminderForm(f => ({ ...f, amount: +e.target.value }))} />
                </div>
                <div className="form-group">
                  <label className="form-label">مرجع الفاتورة</label>
                  <input className="form-input" value={reminderForm.invoice_ref} onChange={e => setReminderForm(f => ({ ...f, invoice_ref: e.target.value }))} />
                </div>
                <div className="form-group">
                  <label className="form-label">تنبيه قبل (أيام)</label>
                  <input type="number" className="form-input" dir="ltr" min={0} value={reminderForm.notify_before_days} onChange={e => setReminderForm(f => ({ ...f, notify_before_days: +e.target.value }))} />
                </div>
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setReminderModal(false)}>إلغاء</button>
              <button className="btn btn-primary" onClick={saveReminder} disabled={modalSaving}>
                {modalSaving && <Loader2 size={14} className="animate-spin" />} إضافة
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
