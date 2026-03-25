import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, Edit, MapPin, Phone, Mail, Building, CreditCard, Users,
  Star, Clock, FileText, Hash, Globe, Tag, Wallet, Calendar, Navigation,
  Plus, Trash2, Check, AlertTriangle, Eye
} from 'lucide-react'
import {
  getCustomer, getCustomerBranches, getCustomerContacts, getCreditHistory
} from '@/lib/services/customers'
import { useAuthStore } from '@/stores/auth-store'
import type { Customer, CustomerBranch, CustomerContact, CustomerCreditHistory } from '@/lib/types/master-data'

export default function CustomerDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  const [loading, setLoading] = useState(true)
  const [customer, setCustomer] = useState<Customer | null>(null)
  const [tab, setTab] = useState<'info' | 'branches' | 'contacts' | 'credit'>('info')
  const [branches, setBranches] = useState<CustomerBranch[]>([])
  const [contacts, setContacts] = useState<CustomerContact[]>([])
  const [creditHistory, setCreditHistory] = useState<CustomerCreditHistory[]>([])

  useEffect(() => {
    if (!id) return
    const load = async () => {
      try {
        const [c, br, ct, cr] = await Promise.all([
          getCustomer(id),
          getCustomerBranches(id),
          getCustomerContacts(id),
          getCreditHistory(id),
        ])
        setCustomer(c)
        setBranches(br)
        setContacts(ct)
        setCreditHistory(cr)
      } catch { toast.error('فشل تحميل بيانات العميل') }
      finally { setLoading(false) }
    }
    load()
  }, [id])

  const typeLabels: Record<string, string> = { retail: 'تجزئة', wholesale: 'جملة', distributor: 'موزع' }
  const typeBadge: Record<string, string> = { retail: 'badge-neutral', wholesale: 'badge-info', distributor: 'badge-primary' }
  const paymentLabels: Record<string, string> = { cash: 'نقدي', credit: 'آجل', mixed: 'مختلط' }
  const paymentBadge: Record<string, string> = { cash: 'badge-success', credit: 'badge-warning', mixed: 'badge-info' }

  if (loading) return (
    <div className="page-container animate-enter">
      {[1, 2, 3, 4].map(i => <div key={i} className="skeleton skeleton-row" style={{ margin: 'var(--space-4) 0' }} />)}
    </div>
  )

  if (!customer) return (
    <div className="page-container animate-enter">
      <div className="empty-state">
        <Users size={48} className="empty-state-icon" />
        <p className="empty-state-title">العميل غير موجود</p>
        <button className="btn btn-primary" onClick={() => navigate('/customers')}>العودة للعملاء</button>
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
          <button className="btn btn-ghost btn-sm" onClick={() => navigate('/customers')} style={{ marginBottom: 'var(--space-2)' }}>
            <ArrowRight size={14} /> العودة للعملاء
          </button>
          <h1 className="page-title">{customer.name}</h1>
          <p className="page-subtitle" dir="ltr" style={{ fontFamily: 'monospace' }}>{customer.code}</p>
        </div>
        <div className="page-actions">
          {can('customers.update') && (
            <button className="btn btn-primary" onClick={() => navigate(`/customers/${id}/edit`)}>
              <Edit size={16} /> تعديل
            </button>
          )}
        </div>
      </div>

      {/* Summary Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 'var(--space-3)', marginBottom: 'var(--space-4)' }}>
        <div className="stat-card">
          <div className="stat-card-label">النوع</div>
          <span className={`badge ${typeBadge[customer.type] || 'badge-neutral'}`} style={{ alignSelf: 'flex-start' }}>
            {typeLabels[customer.type] || customer.type}
          </span>
        </div>
        <div className="stat-card">
          <div className="stat-card-label">طريقة الدفع</div>
          <span className={`badge ${paymentBadge[customer.payment_terms] || 'badge-neutral'}`} style={{ alignSelf: 'flex-start' }}>
            {paymentLabels[customer.payment_terms] || customer.payment_terms}
          </span>
        </div>
        <div className="stat-card">
          <div className="stat-card-label">حد الائتمان</div>
          <div className="stat-card-value" style={{ fontSize: 'var(--text-xl)' }}>
            {customer.credit_limit > 0 ? customer.credit_limit.toLocaleString('ar-EG') : '—'}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-card-label">الرصيد الحالي</div>
          {(() => {
            const bal = customer.current_balance || customer.opening_balance || 0
            return (
              <div className="stat-card-value" style={{
                fontSize: 'var(--text-xl)',
                color: bal > 0 ? 'var(--color-danger)' : bal < 0 ? 'var(--color-success)' : 'var(--text-primary)',
              }}>
                {bal.toLocaleString('ar-EG', { minimumFractionDigits: 2 })}
              </div>
            )
          })()}
        </div>
        <div className="stat-card">
          <div className="stat-card-label">الحالة</div>
          <span className={`badge ${customer.is_active ? 'badge-success' : 'badge-danger'}`} style={{ alignSelf: 'flex-start' }}>
            {customer.is_active ? 'نشط' : 'معطل'}
          </span>
        </div>
      </div>

      {/* Tabs */}
      <div className="tabs">
        <button className={`tab ${tab === 'info' ? 'active' : ''}`} onClick={() => setTab('info')}>
          <Building size={14} /> المعلومات
        </button>
        <button className={`tab ${tab === 'branches' ? 'active' : ''}`} onClick={() => setTab('branches')}>
          <MapPin size={14} /> الفروع
          {branches.length > 0 && <span className="badge badge-neutral" style={{ marginRight: 'var(--space-1)' }}>{branches.length}</span>}
        </button>
        <button className={`tab ${tab === 'contacts' ? 'active' : ''}`} onClick={() => setTab('contacts')}>
          <Users size={14} /> جهات الاتصال
          {contacts.length > 0 && <span className="badge badge-neutral" style={{ marginRight: 'var(--space-1)' }}>{contacts.length}</span>}
        </button>
        <button className={`tab ${tab === 'credit' ? 'active' : ''}`} onClick={() => setTab('credit')}>
          <CreditCard size={14} /> سجل الائتمان
          {creditHistory.length > 0 && <span className="badge badge-neutral" style={{ marginRight: 'var(--space-1)' }}>{creditHistory.length}</span>}
        </button>
      </div>

      {/* ═══════ TAB: INFO ═══════ */}
      {tab === 'info' && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: 'var(--space-4)' }}>
          {/* Contact Info */}
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Phone size={16} style={{ color: 'var(--color-primary)' }} /> بيانات الاتصال
            </h3>
            <InfoItem icon={Phone} label="الهاتف" value={customer.phone} dir="ltr" />
            <InfoItem icon={Phone} label="الجوال" value={customer.mobile} dir="ltr" />
            <InfoItem icon={Mail} label="البريد" value={customer.email} dir="ltr" />
            <InfoItem icon={FileText} label="الرقم الضريبي" value={customer.tax_number} dir="ltr" />
          </div>

          {/* Location */}
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <MapPin size={16} style={{ color: 'var(--color-primary)' }} /> العنوان والموقع
            </h3>
            <InfoItem icon={Globe} label="المحافظة" value={customer.governorate?.name} />
            <InfoItem icon={Building} label="المدينة" value={customer.city?.name} />
            <InfoItem icon={MapPin} label="المنطقة" value={customer.area?.name} />
            <InfoItem icon={Navigation} label="العنوان" value={customer.address} />
            {customer.latitude && customer.longitude && (
              <InfoItem icon={Navigation} label="الموقع GPS" value={`${customer.latitude.toFixed(6)}, ${customer.longitude.toFixed(6)}`} dir="ltr" />
            )}
          </div>

          {/* Financial */}
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Wallet size={16} style={{ color: 'var(--color-primary)' }} /> البيانات المالية
            </h3>
            <InfoItem icon={CreditCard} label="حد الائتمان" value={customer.credit_limit > 0 ? customer.credit_limit.toLocaleString('ar-EG') : '—'} />
            <InfoItem icon={Calendar} label="أيام السداد" value={customer.credit_days > 0 ? `${customer.credit_days} يوم` : '—'} />
            <InfoItem icon={Wallet} label="الرصيد الافتتاحي" value={customer.opening_balance !== 0 ? customer.opening_balance.toLocaleString('ar-EG', { minimumFractionDigits: 2 }) : '0.00'} />
            <InfoItem icon={Tag} label="قائمة الأسعار" value={customer.price_list?.name} />
            <InfoItem icon={Users} label="المندوب" value={customer.assigned_rep?.full_name} />
          </div>

          {/* Notes */}
          {customer.notes && (
            <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
              <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
                <FileText size={16} style={{ color: 'var(--color-primary)' }} /> ملاحظات
              </h3>
              <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', lineHeight: 1.7, whiteSpace: 'pre-wrap' }}>{customer.notes}</p>
            </div>
          )}
        </div>
      )}

      {/* ═══════ TAB: BRANCHES ═══════ */}
      {tab === 'branches' && (
        <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
          <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-4)' }}>
            <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>الفروع</h3>
          </div>
          {branches.length === 0 ? (
            <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا يوجد فروع مسجلة</p>
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: 'var(--space-3)' }}>
              {branches.map(b => (
                <div key={b.id} style={{
                  background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-md)',
                  padding: 'var(--space-4)', border: '1px solid var(--border-secondary)',
                  position: 'relative',
                }}>
                  {b.is_primary && (
                    <span className="badge badge-primary" style={{ position: 'absolute', top: 'var(--space-2)', left: 'var(--space-2)', fontSize: '0.6rem' }}>
                      <Star size={10} /> رئيسي
                    </span>
                  )}
                  <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', marginBottom: 'var(--space-2)' }}>{b.name}</div>
                  {b.address && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginBottom: 'var(--space-1)' }}><MapPin size={10} style={{ display: 'inline' }} /> {b.address}</div>}
                  {b.phone && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', marginBottom: 'var(--space-1)' }} dir="ltr"><Phone size={10} style={{ display: 'inline' }} /> {b.phone}</div>}
                  {b.contact_name && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }}><Users size={10} style={{ display: 'inline' }} /> {b.contact_name}</div>}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ═══════ TAB: CONTACTS ═══════ */}
      {tab === 'contacts' && (
        <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
          <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-4)' }}>
            <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>جهات الاتصال</h3>
          </div>
          {contacts.length === 0 ? (
            <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا يوجد جهات اتصال</p>
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))', gap: 'var(--space-3)' }}>
              {contacts.map(c => (
                <div key={c.id} style={{
                  background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-md)',
                  padding: 'var(--space-4)', border: '1px solid var(--border-secondary)',
                  position: 'relative',
                }}>
                  {c.is_primary && (
                    <span className="badge badge-primary" style={{ position: 'absolute', top: 'var(--space-2)', left: 'var(--space-2)', fontSize: '0.6rem' }}>
                      <Star size={10} /> أساسي
                    </span>
                  )}
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

      {/* ═══════ TAB: CREDIT HISTORY ═══════ */}
      {tab === 'credit' && (
        <div className="edara-card" style={{ overflow: 'auto' }}>
          <div className="flex items-center justify-between" style={{ padding: 'var(--space-5) var(--space-5) 0' }}>
            <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>سجل تغييرات الائتمان</h3>
          </div>
          {creditHistory.length === 0 ? (
            <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا يوجد سجل تغييرات</p>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>التاريخ</th>
                  <th>الحد السابق</th>
                  <th>الحد الجديد</th>
                  <th className="hide-mobile">بواسطة</th>
                  <th className="hide-mobile">السبب</th>
                </tr>
              </thead>
              <tbody>
                {creditHistory.map(h => (
                  <tr key={h.id}>
                    <td style={{ fontSize: 'var(--text-xs)' }}>{new Date(h.created_at).toLocaleDateString('ar-EG')}</td>
                    <td style={{ fontWeight: 600 }}>{h.limit_before.toLocaleString('ar-EG')}</td>
                    <td style={{ fontWeight: 600, color: h.limit_after > h.limit_before ? 'var(--color-success)' : 'var(--color-danger)' }}>
                      {h.limit_after.toLocaleString('ar-EG')}
                    </td>
                    <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)' }}>{h.changed_by_profile?.full_name || '—'}</td>
                    <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{h.reason || '—'}</td>
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
