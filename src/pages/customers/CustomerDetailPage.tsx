import { useState, useEffect, type ReactNode } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, Edit, MapPin, Phone, Mail, Building, CreditCard, Users,
  Star, Clock, FileText, Hash, Globe, Tag, Wallet, Calendar, Navigation,
  Plus, Trash2, Check, AlertTriangle, Eye, ExternalLink
} from 'lucide-react'
import {
  getCustomer, getCustomerBranches, getCustomerContacts, getCreditHistory
} from '@/lib/services/customers'
import { useActivities } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { Customer, CustomerBranch, CustomerContact, CustomerCreditHistory } from '@/lib/types/master-data'

export default function CustomerDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  const [loading, setLoading] = useState(true)
  const [customer, setCustomer] = useState<Customer | null>(null)
  const [tab, setTab] = useState<'info' | 'branches' | 'contacts' | 'credit' | 'activities'>('info')
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

  const InfoItem = ({ icon: Icon, label, value, dir }: { icon: any; label: string; value?: ReactNode; dir?: string }) => (
    <div style={{ display: 'flex', alignItems: 'flex-start', gap: 'var(--space-3)', padding: 'var(--space-3) 0', borderBottom: '1px solid var(--border-secondary)' }}>
      <div style={{ width: 32, height: 32, borderRadius: 'var(--radius-md)', background: 'var(--bg-surface-2)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <Icon size={14} style={{ color: 'var(--color-primary)' }} />
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 2 }}>{label}</div>
        <div style={{ fontSize: 'var(--text-sm)', fontWeight: 500, color: value ? 'var(--text-primary)' : 'var(--text-muted)' }} dir={dir}>{value ?? '—'}</div>
      </div>
    </div>
  )

  return (
    <div style={{ maxWidth: 900, margin: '0 auto', paddingBottom: 80 }}>

      {/* ══ Sticky Mobile Hero Card ══ */}
      <div style={{
        position: 'sticky', top: 0, zIndex: 10,
        background: 'var(--bg-surface)',
        borderBottom: '1px solid var(--border-primary)',
        backdropFilter: 'blur(12px)',
        padding: '14px 16px',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <button onClick={() => navigate('/customers')}
            style={{ background: 'var(--bg-surface-2)', border: '1px solid var(--border-primary)', borderRadius: 10, padding: '7px 10px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4, fontSize: 13, color: 'var(--text-secondary)', flexShrink: 0 }}>
            <ArrowRight size={14} /> رجوع
          </button>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <h1 style={{ fontSize: 17, fontWeight: 800, margin: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {customer.name}
              </h1>
              <span className={`badge ${paymentBadge[customer.payment_terms] || 'badge-neutral'}`}>
                {paymentLabels[customer.payment_terms] || customer.payment_terms}
              </span>
              <span className={`badge ${customer.is_active ? 'badge-success' : 'badge-danger'}`}>
                {customer.is_active ? 'نشط' : 'معطل'}
              </span>
            </div>
            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2, fontFamily: 'monospace', direction: 'ltr', display: 'inline-block' }}>
              {customer.code}
            </div>
          </div>
          {can('customers.update') && (
            <button onClick={() => navigate(`/customers/${id}/edit`)}
              style={{ background: 'var(--color-primary)', color: '#fff', border: 'none', borderRadius: 10, padding: '8px 14px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 5, fontSize: 13, fontWeight: 600, flexShrink: 0 }}>
              <Edit size={14} /> تعديل
            </button>
          )}
        </div>
      </div>

      {/* Stats Row */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 'var(--space-3)', margin: '0 12px var(--space-4)' }}>
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
            {customer.credit_limit > 0 ? customer.credit_limit.toLocaleString('ar-EG-u-nu-latn') : '—'}
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

      {/* Tabs — scrollable on mobile */}
      <div className="tabs" style={{ overflowX: 'auto', scrollbarWidth: 'none', flexWrap: 'nowrap', padding: '0 12px' }}>
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
        <button className={`tab ${tab === 'activities' ? 'active' : ''}`} onClick={() => setTab('activities')}>
          <Clock size={14} /> الأنشطة
        </button>
      </div>

      {/* ═══════ TAB: INFO ═══════ */}
      {tab === 'info' && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: 'var(--space-4)', padding: '0 12px' }}>
          {/* Contact Info */}
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Phone size={16} style={{ color: 'var(--color-primary)' }} /> بيانات الاتصال
            </h3>
            {customer.phone && (
              <InfoItem icon={Phone} label="الهاتف" dir="ltr"
                value={<a href={`tel:${customer.phone}`} style={{ color: 'var(--color-primary)', textDecoration: 'none', fontFamily: 'monospace' }}>{customer.phone}</a>} />
            )}
            {!customer.phone && <InfoItem icon={Phone} label="الهاتف" value={null} />}
            {customer.mobile && (
              <InfoItem icon={Phone} label="الجوال" dir="ltr"
                value={<a href={`tel:${customer.mobile}`} style={{ color: 'var(--color-primary)', textDecoration: 'none', fontFamily: 'monospace' }}>{customer.mobile}</a>} />
            )}
            {!customer.mobile && <InfoItem icon={Phone} label="الجوال" value={null} />}
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
              <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-3)', padding: 'var(--space-3) 0', borderBottom: '1px solid var(--border-secondary)' }}>
                <div style={{ width: 32, height: 32, borderRadius: 'var(--radius-md)', background: 'var(--color-success-light, #f0fdf4)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  <Navigation size={14} style={{ color: 'var(--color-success)' }} />
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 2 }}>الموقع GPS</div>
                  <a
                    href={`geo:${customer.latitude},${customer.longitude}?q=${customer.latitude},${customer.longitude}(${encodeURIComponent(customer.name)})`}
                    onClick={e => {
                      // Fallback to Google Maps URL on desktop
                      if (!/Android|iPhone|iPad/i.test(navigator.userAgent)) {
                        e.preventDefault()
                        window.open(`https://maps.google.com/?q=${customer.latitude},${customer.longitude}`, '_blank')
                      }
                    }}
                    style={{ fontSize: 'var(--text-sm)', fontWeight: 600, color: 'var(--color-success)', textDecoration: 'none', display: 'flex', alignItems: 'center', gap: 4 }}
                  >
                    <ExternalLink size={12} />
                    {customer.latitude.toFixed(5)}, {customer.longitude.toFixed(5)}
                  </a>
                </div>
              </div>
            )}
          </div>

          {/* Financial */}
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Wallet size={16} style={{ color: 'var(--color-primary)' }} /> البيانات المالية
            </h3>
            <InfoItem icon={CreditCard} label="حد الائتمان" value={customer.credit_limit > 0 ? customer.credit_limit.toLocaleString('ar-EG-u-nu-latn') : '—'} />
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
        <div className="edara-card" style={{ padding: 'var(--space-5)', margin: '0 12px' }}>
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
        <div className="edara-card" style={{ padding: 'var(--space-5)', margin: '0 12px' }}>
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
        <div className="edara-card" style={{ overflow: 'auto', margin: '0 12px' }}>
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
                    <td style={{ fontSize: 'var(--text-xs)' }}>{new Date(h.created_at).toLocaleDateString('ar-EG-u-nu-latn')}</td>
                    <td style={{ fontWeight: 600 }}>{h.limit_before.toLocaleString('ar-EG-u-nu-latn')}</td>
                    <td style={{ fontWeight: 600, color: h.limit_after > h.limit_before ? 'var(--color-success)' : 'var(--color-danger)' }}>
                      {h.limit_after.toLocaleString('ar-EG-u-nu-latn')}
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

      {/* ═══════ TAB: ACTIVITIES ═══════ */}
      {tab === 'activities' && id && <CustomerActivitiesTab customerId={id} navigate={navigate} />}
    </div>
  )
}

// ── Customer Activities Tab ─────────────────────────────────
const OUTCOME_AR: Record<string, string> = {
  order_placed: 'طلب مبيعات', agreed_order: 'اتفاق على طلب', collection: 'تحصيل',
  promised_payment: 'وعد بالدفع', followup_visit: 'زيارة متابعة', followup_scheduled: 'متابعة مجدولة',
  refused: 'رفض', not_interested: 'غير مهتم', closed: 'مغلق', promotion: 'ترويج',
  exploratory: 'استكشافية', info_only: 'معلومات فقط', no_answer: 'لا يرد', busy: 'مشغول',
  callback_scheduled: 'مكالمة لاحقة',
}
const OUTCOME_COLOR: Record<string, string> = {
  order_placed: 'var(--color-success)', collection: 'var(--color-success)',
  agreed_order: 'var(--color-primary)', promised_payment: 'var(--color-warning)',
  refused: 'var(--color-danger)', not_interested: 'var(--color-danger)',
}
const CAT_ICON: Record<string, string> = { visit: '📍', call: '📞', task: '📋' }

function CustomerActivitiesTab({ customerId, navigate }: { customerId: string; navigate: (path: string) => void }) {
  const { data: result, isLoading } = useActivities({ customerId, pageSize: 15 })
  const activities = result?.data ?? []

  return (
    <div style={{ padding: '0 12px' }}>
      {/* Quick Actions */}
      <div style={{ display: 'flex', gap: 'var(--space-2)', marginBottom: 'var(--space-4)', flexWrap: 'wrap' }}>
        <button
          className="btn btn-primary"
          style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, padding: '8px 16px' }}
          onClick={() => navigate(`/activities/new?customerId=${customerId}`)}
        >
          <MapPin size={14} /> تسجيل زيارة
        </button>
        <button
          className="btn"
          style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, padding: '8px 16px',
            background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', color: 'var(--text-secondary)', cursor: 'pointer' }}
          onClick={() => navigate(`/activities/new?customerId=${customerId}`)}
        >
          <Phone size={14} /> تسجيل مكالمة
        </button>
      </div>

      {isLoading ? (
        <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
          {[1, 2, 3].map(i => (
            <div key={i} style={{ display: 'flex', gap: 'var(--space-3)', marginBottom: 'var(--space-4)' }}>
              <div className="skeleton" style={{ width: 36, height: 36, borderRadius: '50%', flexShrink: 0 }} />
              <div style={{ flex: 1 }}>
                <div className="skeleton" style={{ height: 14, width: '60%', marginBottom: 6 }} />
                <div className="skeleton" style={{ height: 10, width: '40%' }} />
              </div>
            </div>
          ))}
        </div>
      ) : activities.length === 0 ? (
        <div className="edara-card" style={{ padding: 'var(--space-6)', textAlign: 'center' }}>
          <Clock size={36} style={{ color: 'var(--text-muted)', margin: '0 auto var(--space-3)' }} />
          <p style={{ color: 'var(--text-muted)', margin: 0, fontSize: 'var(--text-sm)' }}>
            لا توجد أنشطة مسجلة لهذا العميل
          </p>
        </div>
      ) : (
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-4)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
            <Clock size={16} style={{ color: 'var(--color-primary)' }} /> آخر الأنشطة
            <span className="badge badge-neutral" style={{ marginRight: 'auto' }}>{result?.count ?? 0}</span>
          </h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
            {activities.map((act, idx) => {
              const catIcon = CAT_ICON[(act as any).type?.category ?? ''] ?? '📋'
              const outLabel = OUTCOME_AR[act.outcome_type] ?? act.outcome_type
              const outColor = OUTCOME_COLOR[act.outcome_type] ?? 'var(--text-secondary)'
              const date = new Date(act.activity_date).toLocaleDateString('ar-EG', { day: 'numeric', month: 'short' })
              const time = act.start_time ? new Date(act.start_time).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' }) : ''
              return (
                <div
                  key={act.id}
                  onClick={() => navigate(`/activities/${act.id}`)}
                  style={{
                    display: 'flex', alignItems: 'flex-start', gap: 'var(--space-3)',
                    padding: 'var(--space-3) 0', cursor: 'pointer',
                    borderBottom: idx < activities.length - 1 ? '1px solid var(--border-secondary)' : 'none',
                    transition: 'background var(--transition-fast)',
                  }}
                >
                  <div style={{
                    width: 36, height: 36, borderRadius: '50%', flexShrink: 0,
                    background: 'var(--bg-surface-2)', display: 'flex', alignItems: 'center',
                    justifyContent: 'center', fontSize: 16,
                  }}>
                    {catIcon}
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 'var(--space-2)' }}>
                      <span style={{ fontWeight: 600, fontSize: 'var(--text-sm)', color: 'var(--text-primary)' }}>
                        {(act as any).type?.name ?? 'نشاط'}
                      </span>
                      <span style={{ fontSize: 11, color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>
                        {date} {time && `• ${time}`}
                      </span>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginTop: 2 }}>
                      <span style={{ fontSize: 12, fontWeight: 600, color: outColor }}>{outLabel}</span>
                      {act.outcome_notes && (
                        <span style={{ fontSize: 11, color: 'var(--text-muted)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 200 }}>
                          — {act.outcome_notes}
                        </span>
                      )}
                    </div>
                  </div>
                  <Eye size={14} style={{ color: 'var(--text-muted)', flexShrink: 0, marginTop: 10 }} />
                </div>
              )
            })}
          </div>
          {(result?.count ?? 0) > 15 && (
            <div style={{ textAlign: 'center', paddingTop: 'var(--space-3)' }}>
              <button
                className="btn"
                style={{ fontSize: 12, padding: '6px 16px', background: 'var(--bg-surface-2)', border: '1px solid var(--border-primary)', borderRadius: 'var(--radius-md)', cursor: 'pointer', color: 'var(--color-primary)', fontWeight: 600 }}
                onClick={() => navigate(`/activities/list?customerId=${customerId}`)}
              >
                عرض الكل ({result?.count})
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

