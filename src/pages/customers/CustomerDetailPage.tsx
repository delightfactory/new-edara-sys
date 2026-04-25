import { useState, useEffect, type ReactNode } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, Edit, MapPin, Phone, Mail, Building, CreditCard, Users,
  Star, Clock, FileText, Hash, Globe, Tag, Wallet, Calendar, Navigation,
  Plus, Trash2, Check, AlertTriangle, Eye, ExternalLink, AlertCircle, Target
} from 'lucide-react'
import {
  getCustomer, getCustomerBranches, getCustomerContacts, getCreditHistory
} from '@/lib/services/customers'
import { useActivities } from '@/hooks/useQueryHooks'
import { useCustomer360Summary, useCustomer360ArAging } from '@/hooks/useCustomer360'
import { useAuthStore } from '@/stores/auth-store'
import type { Customer, CustomerBranch, CustomerContact, CustomerCreditHistory } from '@/lib/types/master-data'
import { CustomerIntelligenceTab } from './CustomerIntelligenceTab'
import { computeRecommendations } from '@/lib/utils/customer360-recommendations'

export default function CustomerDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  const [loading, setLoading] = useState(true)
  const [customer, setCustomer] = useState<Customer | null>(null)
  const [tab, setTab] = useState<'analysis' | 'info' | 'branches' | 'activities'>('analysis')
  const [branches, setBranches] = useState<CustomerBranch[]>([])
  const [contacts, setContacts] = useState<CustomerContact[]>([])
  const [creditHistory, setCreditHistory] = useState<CustomerCreditHistory[]>([])

  // Hook safety check - must be called unconditionally
  const customerId = id || ''
  const summary = useCustomer360Summary(customerId)
  // arAging is fetched here for Pulse Strip critical alerts (overdue_critical).
  // React Query deduplicates: same key used in CustomerIntelligenceTab causes no extra network call.
  const { data: pulseArAging } = useCustomer360ArAging(customerId)
  
  // Compute limited recommendations just for Pulse chips (critical only)
  // Safely fallback when customer is not yet loaded
  const pulseRecs = computeRecommendations({
    customer: customer || { id: customerId, is_active: false },
    kpis: summary.kpis,
    health: summary.health,
    risk: summary.risk,
    arAging: pulseArAging,  // enables overdue_critical to appear in Pulse Strip
  }).filter(r => r.severity === 'critical')

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

  const InfoItem = ({ icon: Icon, label, value, dir }: { icon: React.ElementType; label: string; value?: ReactNode; dir?: string }) => (
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
    <div className="animate-enter" style={{ maxWidth: 1000, margin: '0 auto', paddingBottom: 'calc(80px + env(safe-area-inset-bottom, 0px))' }}>
      {/* ══ Sticky Pulse Strip (Decision Header) ══ */}
      <div style={{
        position: 'sticky', top: 0, zIndex: 50,
        background: 'var(--bg-surface)',
        borderBottom: '1px solid var(--border-primary)',
        boxShadow: '0 4px 20px rgba(0,0,0,0.03)',
        padding: '12px 16px',
        display: 'flex', flexDirection: 'column', gap: 10
      }}>
        {/* Top Action Row */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <button onClick={() => navigate('/customers')}
            style={{ background: 'var(--bg-surface-2)', border: '1px solid var(--border-primary)', borderRadius: 8, padding: '6px 12px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, color: 'var(--text-secondary)', flexShrink: 0 }}>
            <ArrowRight size={14} /> رجوع
          </button>
          
          <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 4 }}>
            <h1 style={{ fontSize: 18, fontWeight: 800, margin: 0, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', width: '100%' }}>
              {customer.name}
            </h1>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <span style={{ fontSize: 11, color: 'var(--text-muted)', fontFamily: 'monospace', direction: 'ltr' }}>
                {customer.code}
              </span>
            
            {/* Health Badge */}
            {summary.health ? (
              <span className={`badge ${summary.health.health_status === 'نشط' ? 'badge-success' : 'badge-danger'}`} style={{ padding: '2px 8px', fontSize: 11 }}>
                {summary.health.health_status}
              </span>
            ) : summary.isPending ? (
              <span className="skeleton" style={{ width: 40, height: 20 }} />
            ) : null}

            {/* Recency Badge */}
            {summary.health?.recency_days !== undefined && summary.health?.recency_days !== null && (
              <span style={{ fontSize: 11, color: 'var(--text-secondary)', background: 'var(--bg-surface-2)', padding: '2px 8px', borderRadius: 12 }}>
                آخر تعامل: منذ {summary.health.recency_days} يوم
              </span>
            )}
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
            {/* Quick Actions for Ops */}
            {(customer.latitude && customer.longitude) && (
              <button onClick={(e) => { e.stopPropagation(); window.open(`https://www.google.com/maps/search/?api=1&query=${customer.latitude},${customer.longitude}`, '_blank') }}
                title="موقع العميل"
                style={{ background: 'var(--bg-surface-2)', border: '1px solid var(--border-secondary)', borderRadius: '50%', width: 34, height: 34, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--color-primary)', cursor: 'pointer', flexShrink: 0 }}>
                <MapPin size={14} />
              </button>
            )}
            {(customer.mobile || customer.phone) && (
              <a href={`tel:${customer.mobile || customer.phone}`}
                title="اتصال"
                style={{ background: 'var(--bg-surface-2)', border: '1px solid var(--border-secondary)', borderRadius: '50%', width: 34, height: 34, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--color-primary)', cursor: 'pointer', flexShrink: 0 }}>
                <Phone size={14} />
              </a>
            )}

            {/* Balancing Info — desktop only (too wide for mobile header) */}
            <div className="hide-mobile" style={{ textAlign: 'left', display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
              <div style={{ fontSize: 10, color: 'var(--text-muted)' }}>الرصيد الحالي</div>
              <div style={{ 
                fontSize: 16, fontWeight: 800, 
                color: (customer.current_balance ?? 0) > 0 ? 'var(--color-danger)' : (customer.current_balance ?? 0) < 0 ? 'var(--color-primary)' : 'var(--color-success)' 
              }}>
                {(customer.current_balance ?? 0).toLocaleString('ar-EG-u-nu-latn', { minimumFractionDigits: 2 })}
              </div>
            </div>

            {/* Edit button — icon-only on mobile, labeled on desktop */}
            {can('customers.update') && (
              <button
                id="btn-edit-customer"
                onClick={() => navigate(`/customers/${id}/edit`)}
                title="تعديل بيانات العميل"
                style={{ background: 'var(--color-primary)', color: 'var(--color-on-primary, #fff)', border: 'none', borderRadius: 8, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, fontWeight: 600, flexShrink: 0 }}
              >
                {/* Icon always visible */}
                <Edit size={14} />
                {/* Label hidden on mobile via utility class */}
                <span className="hide-mobile" style={{ fontSize: 13, whiteSpace: 'nowrap' }}>تعديل</span>
              </button>
            )}
          </div>
        </div>

        {/* Pulse Chips Row (Critical Alerts) */}
        {pulseRecs.length > 0 && (
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 4 }}>
            {pulseRecs.map(rec => (
              <div key={rec.id} style={{ display: 'flex', alignItems: 'center', gap: 4, background: 'var(--color-danger-light, #fef2f2)', border: '1px solid var(--color-danger)', color: 'var(--color-danger)', fontSize: 11, fontWeight: 600, padding: '2px 8px', borderRadius: 12 }}>
                <AlertCircle size={10} />
                {rec.title}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Tabs */}
      <div className="tabs" style={{ overflowX: 'auto', scrollbarWidth: 'none', flexWrap: 'nowrap', padding: '12px 16px 16px', borderBottom: '1px solid var(--border-secondary)', marginBottom: 20 }}>
        <button className={`tab ${tab === 'analysis' ? 'active' : ''}`} onClick={() => setTab('analysis')}>
          <Target size={14} /> الاستخبارات (360)
        </button>
        <button className={`tab ${tab === 'info' ? 'active' : ''}`} onClick={() => setTab('info')}>
          <Building size={14} /> ملف العميل
        </button>
        <button className={`tab ${tab === 'branches' ? 'active' : ''}`} onClick={() => setTab('branches')}>
          <MapPin size={14} /> الفروع
          {branches.length > 0 && <span className="badge badge-neutral" style={{ marginRight: 'var(--space-1)' }}>{branches.length}</span>}
        </button>
        <button className={`tab ${tab === 'activities' ? 'active' : ''}`} onClick={() => setTab('activities')}>
          <Clock size={14} /> الأنشطة والزيارات
        </button>
      </div>

      {/* ═══════ TAB: ANALYSIS (360) ═══════ */}
      {tab === 'analysis' && <CustomerIntelligenceTab customer={customer} />}

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
            <InfoItem icon={Wallet} label="الرصيد الافتتاحي"
              value={(customer.opening_balance ?? 0).toLocaleString('en-US', { minimumFractionDigits: 2 })} />
            <InfoItem icon={Wallet} label="الرصيد الحالي"
              value={
                <span style={{ fontWeight: 700, color: (customer.current_balance ?? 0) > 0 ? 'var(--color-danger)' : (customer.current_balance ?? 0) < 0 ? 'var(--color-primary)' : 'var(--color-success)' }}>
                  {(customer.current_balance ?? 0).toLocaleString('en-US', { minimumFractionDigits: 2 })}
                </span>
              } />
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

          {/* Render Contacts (merged logic) */}
          <div className="edara-card" style={{ padding: 'var(--space-5)', gridColumn: '1 / -1' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-4)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Users size={16} style={{ color: 'var(--color-primary)' }} /> جهات الاتصال
            </h3>
            {contacts.length === 0 ? (
              <p style={{ textAlign: 'center', color: 'var(--text-muted)', fontSize: 13 }}>لا توجد جهات اتصال مسجلة</p>
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
                        أساسي
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

          {/* Render Credit History (merged logic) */}
          <div className="edara-card" style={{ padding: 'var(--space-5)', gridColumn: '1 / -1', overflowX: 'auto' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-4)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <CreditCard size={16} style={{ color: 'var(--color-primary)' }} /> سجل تغييرات الائتمان
            </h3>
            {creditHistory.length === 0 ? (
              <p style={{ textAlign: 'center', color: 'var(--text-muted)', fontSize: 13 }}>لا توجد تغييرات مسجلة</p>
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

interface ActivityTypeData {
  category?: string
  name?: string
}

interface ActivityItemNarrow {
  id: string
  activity_date: string
  start_time: string | null
  outcome_type: string
  outcome_notes: string | null
  type?: ActivityTypeData | null
}

function CustomerActivitiesTab({ customerId, navigate }: { customerId: string; navigate: (path: string) => void }) {
  const { data: result, isLoading } = useActivities({ customerId, pageSize: 15 })
  const rawActivities = (result?.data ?? [])
  const activities: ActivityItemNarrow[] = Array.isArray(rawActivities) ? rawActivities : []

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
              const catIcon = CAT_ICON[act.type?.category ?? ''] ?? '📋'
              const outLabel = OUTCOME_AR[act.outcome_type] ?? act.outcome_type
              const outColor = OUTCOME_COLOR[act.outcome_type] ?? 'var(--text-secondary)'
              const date = new Date(act.activity_date).toLocaleDateString('ar-EG-u-nu-latn', { day: 'numeric', month: 'short' })
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
                        {act.type?.name ?? 'نشاط'}
                      </span>
                      <span style={{ fontSize: 11, color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>
                        {date} {time && `• ${time}`}
                      </span>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginTop: 2 }}>
                      <span style={{ fontSize: 12, fontWeight: 600, color: outColor }}>{outLabel}</span>
                      {act.outcome_notes && (
                        <span style={{ fontSize: 11, color: 'var(--text-muted)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 'min(200px, 40vw)' }}>
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
