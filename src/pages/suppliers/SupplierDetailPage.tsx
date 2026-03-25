import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, Edit, Phone, Mail, Building, CreditCard, Users,
  Clock, FileText, Globe, Wallet, Calendar, Bell, Check, AlertTriangle, Star, Truck
} from 'lucide-react'
import {
  getSupplier, getSupplierContacts, getPaymentReminders
} from '@/lib/services/suppliers'
import { useAuthStore } from '@/stores/auth-store'
import type { Supplier, SupplierContact, SupplierPaymentReminder } from '@/lib/types/master-data'

export default function SupplierDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  const [loading, setLoading] = useState(true)
  const [supplier, setSupplier] = useState<Supplier | null>(null)
  const [tab, setTab] = useState<'info' | 'contacts' | 'reminders'>('info')
  const [contacts, setContacts] = useState<SupplierContact[]>([])
  const [reminders, setReminders] = useState<SupplierPaymentReminder[]>([])

  useEffect(() => {
    if (!id) return
    const load = async () => {
      try {
        const [s, ct, rm] = await Promise.all([
          getSupplier(id),
          getSupplierContacts(id),
          getPaymentReminders({ supplierId: id }).then(r => r.data),
        ])
        setSupplier(s)
        setContacts(ct)
        setReminders(rm)
      } catch { toast.error('فشل تحميل بيانات المورد') }
      finally { setLoading(false) }
    }
    load()
  }, [id])

  const paymentLabels: Record<string, string> = { cash: 'نقدي', credit: 'آجل' }
  const paymentBadge: Record<string, string> = { cash: 'badge-success', credit: 'badge-warning' }
  const statusLabels: Record<string, { label: string; cls: string }> = {
    pending: { label: 'معلق', cls: 'badge-warning' },
    paid: { label: 'مدفوع', cls: 'badge-success' },
    overdue: { label: 'متأخر', cls: 'badge-danger' },
  }

  if (loading) return (
    <div className="page-container animate-enter">
      {[1, 2, 3, 4].map(i => <div key={i} className="skeleton skeleton-row" style={{ margin: 'var(--space-4) 0' }} />)}
    </div>
  )

  if (!supplier) return (
    <div className="page-container animate-enter">
      <div className="empty-state">
        <Truck size={48} className="empty-state-icon" />
        <p className="empty-state-title">المورد غير موجود</p>
        <button className="btn btn-primary" onClick={() => navigate('/suppliers')}>العودة للموردين</button>
      </div>
    </div>
  )

  const InfoItem = ({ icon: Icon, label, value, dir }: { icon: any; label: string; value: string | number | null | undefined; dir?: string }) => (
    <div style={{ display: 'flex', alignItems: 'flex-start', gap: 'var(--space-3)', padding: 'var(--space-3) 0', borderBottom: '1px solid var(--border-secondary)' }}>
      <div style={{ width: 32, height: 32, borderRadius: 'var(--radius-md)', background: 'var(--bg-surface-2)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <Icon size={14} style={{ color: 'var(--color-primary)' }} />
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 2 }}>{label}</div>
        <div style={{ fontSize: 'var(--text-sm)', fontWeight: 500, color: value ? 'var(--text-primary)' : 'var(--text-muted)' }} dir={dir}>{value || '—'}</div>
      </div>
    </div>
  )

  return (
    <div className="page-container animate-enter">
      {/* Header */}
      <div className="page-header">
        <div className="page-header-info">
          <button className="btn btn-ghost btn-sm" onClick={() => navigate('/suppliers')} style={{ marginBottom: 'var(--space-2)' }}>
            <ArrowRight size={14} /> العودة للموردين
          </button>
          <h1 className="page-title">{supplier.name}</h1>
          <p className="page-subtitle" dir="ltr" style={{ fontFamily: 'monospace' }}>{supplier.code}</p>
        </div>
        <div className="page-actions">
          {can('suppliers.update') && (
            <button className="btn btn-primary" onClick={() => navigate(`/suppliers/${id}/edit`)}>
              <Edit size={16} /> تعديل
            </button>
          )}
        </div>
      </div>

      {/* Summary Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 'var(--space-3)', marginBottom: 'var(--space-4)' }}>
        <div className="stat-card">
          <div className="stat-card-label">طريقة الدفع</div>
          <span className={`badge ${paymentBadge[supplier.payment_terms || 'cash'] || 'badge-neutral'}`} style={{ alignSelf: 'flex-start' }}>
            {paymentLabels[supplier.payment_terms || 'cash'] || supplier.payment_terms}
          </span>
        </div>
        <div className="stat-card">
          <div className="stat-card-label">حد الائتمان</div>
          <div className="stat-card-value" style={{ fontSize: 'var(--text-xl)' }}>
            {supplier.credit_limit > 0 ? supplier.credit_limit.toLocaleString('ar-EG') : '—'}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-card-label">الرصيد الحالي</div>
          {(() => {
            const bal = supplier.current_balance || supplier.opening_balance || 0
            return (
              <div className="stat-card-value" style={{
                fontSize: 'var(--text-xl)',
                color: bal > 0 ? 'var(--color-success)' : bal < 0 ? 'var(--color-danger)' : 'var(--text-primary)',
              }}>
                {bal.toLocaleString('ar-EG', { minimumFractionDigits: 2 })}
              </div>
            )
          })()}
        </div>
        <div className="stat-card">
          <div className="stat-card-label">الحالة</div>
          <span className={`badge ${supplier.is_active ? 'badge-success' : 'badge-danger'}`} style={{ alignSelf: 'flex-start' }}>
            {supplier.is_active ? 'نشط' : 'معطل'}
          </span>
        </div>
      </div>

      {/* Tabs */}
      <div className="tabs">
        <button className={`tab ${tab === 'info' ? 'active' : ''}`} onClick={() => setTab('info')}>
          <Building size={14} /> المعلومات
        </button>
        <button className={`tab ${tab === 'contacts' ? 'active' : ''}`} onClick={() => setTab('contacts')}>
          <Users size={14} /> جهات الاتصال
          {contacts.length > 0 && <span className="badge badge-neutral" style={{ marginRight: 'var(--space-1)' }}>{contacts.length}</span>}
        </button>
        <button className={`tab ${tab === 'reminders' ? 'active' : ''}`} onClick={() => setTab('reminders')}>
          <Bell size={14} /> تذكيرات السداد
          {reminders.length > 0 && <span className="badge badge-warning" style={{ marginRight: 'var(--space-1)' }}>{reminders.length}</span>}
        </button>
      </div>

      {/* ═══════ TAB: INFO ═══════ */}
      {tab === 'info' && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: 'var(--space-4)' }}>
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Phone size={16} style={{ color: 'var(--color-primary)' }} /> بيانات الاتصال
            </h3>
            <InfoItem icon={Phone} label="الهاتف" value={supplier.phone} dir="ltr" />
            <InfoItem icon={Mail} label="البريد" value={supplier.email} dir="ltr" />
            <InfoItem icon={FileText} label="الرقم الضريبي" value={supplier.tax_number} dir="ltr" />
            <InfoItem icon={Building} label="النوع" value={supplier.type} />
          </div>

          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Globe size={16} style={{ color: 'var(--color-primary)' }} /> العنوان
            </h3>
            <InfoItem icon={Globe} label="المحافظة" value={supplier.governorate?.name} />
            <InfoItem icon={Building} label="المدينة" value={supplier.city?.name} />
          </div>

          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Wallet size={16} style={{ color: 'var(--color-primary)' }} /> البيانات المالية
            </h3>
            <InfoItem icon={CreditCard} label="حد الائتمان" value={supplier.credit_limit > 0 ? supplier.credit_limit.toLocaleString('ar-EG') : '—'} />
            <InfoItem icon={Calendar} label="أيام السداد" value={supplier.credit_days > 0 ? `${supplier.credit_days} يوم` : '—'} />
            <InfoItem icon={Wallet} label="الرصيد الافتتاحي" value={supplier.opening_balance !== 0 ? supplier.opening_balance.toLocaleString('ar-EG', { minimumFractionDigits: 2 }) : '0.00'} />
            <InfoItem icon={CreditCard} label="الحساب البنكي" value={supplier.bank_account} dir="ltr" />
          </div>
        </div>
      )}

      {/* ═══════ TAB: CONTACTS ═══════ */}
      {tab === 'contacts' && (
        <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
          <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-4)' }}>جهات الاتصال</h3>
          {contacts.length === 0 ? (
            <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا يوجد جهات اتصال</p>
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))', gap: 'var(--space-3)' }}>
              {contacts.map(c => (
                <div key={c.id} style={{
                  background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-md)',
                  padding: 'var(--space-4)', border: '1px solid var(--border-secondary)',
                }}>
                  <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', marginBottom: 'var(--space-2)' }}>{c.name}</div>
                  {c.role && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 'var(--space-1)' }}>{c.role}</div>}
                  {c.phone && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }} dir="ltr"><Phone size={10} style={{ display: 'inline' }} /> {c.phone}</div>}
                  {c.email && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }} dir="ltr"><Mail size={10} style={{ display: 'inline' }} /> {c.email}</div>}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ═══════ TAB: REMINDERS ═══════ */}
      {tab === 'reminders' && (
        <div className="edara-card" style={{ overflow: 'auto' }}>
          <div style={{ padding: 'var(--space-5) var(--space-5) 0' }}>
            <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-4)' }}>تذكيرات السداد</h3>
          </div>
          {reminders.length === 0 ? (
            <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا يوجد تذكيرات</p>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>تاريخ الاستحقاق</th>
                  <th>المبلغ</th>
                  <th className="hide-mobile">مرجع الفاتورة</th>
                  <th>الحالة</th>
                </tr>
              </thead>
              <tbody>
                {reminders.map(r => (
                  <tr key={r.id}>
                    <td style={{ fontSize: 'var(--text-xs)' }}>{new Date(r.due_date).toLocaleDateString('ar-EG')}</td>
                    <td style={{ fontWeight: 600 }}>{r.amount.toLocaleString('ar-EG')}</td>
                    <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)' }}>{r.invoice_ref || '—'}</td>
                    <td><span className={`badge ${statusLabels[r.status]?.cls || 'badge-neutral'}`}>{statusLabels[r.status]?.label || r.status}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}
    </div>
  )
}
