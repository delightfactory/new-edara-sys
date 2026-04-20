import { Plus, MapPin, Phone, CreditCard, Calendar, Check, Navigation } from 'lucide-react'
import type { CustomerSearchResult } from '@/hooks/useCustomerSearch'

interface CustomerSearchCardProps {
  customer: CustomerSearchResult
  /** هل العميل محدد مسبقاً (موجود في القائمة)؟ */
  isSelected?: boolean
  /** عند الضغط على "إضافة" */
  onAdd?: (customer: CustomerSearchResult) => void
  /** عند الضغط على البطاقة */
  onClick?: (customer: CustomerSearchResult) => void
  /** عرض مصغر (للقوائم الكبيرة) */
  compact?: boolean
}

/**
 * CustomerSearchCard — بطاقة عميل غنية بالمعلومات
 *
 * تُستخدم في:
 * - ويزارد إنشاء خطة الزيارات (اختيار العملاء)
 * - نتائج البحث في وضع التنفيذ
 *
 * تعرض: الاسم، الكود، الهاتف، الموقع الجغرافي، الرصيد، حد الائتمان، مؤشر GPS
 */
export default function CustomerSearchCard({
  customer,
  isSelected = false,
  onAdd,
  onClick,
  compact = false,
}: CustomerSearchCardProps) {
  const hasGPS = customer.latitude != null && customer.longitude != null
  const hasDebt = customer.current_balance > 0
  const locationText = [customer.governorate_name, customer.city_name].filter(Boolean).join(' — ')

  const handleNavigate = (e: React.MouseEvent) => {
    e.stopPropagation()
    if (customer.latitude && customer.longitude) {
      window.open(
        `https://www.google.com/maps/dir/?api=1&destination=${customer.latitude},${customer.longitude}`,
        '_blank'
      )
    } else if (customer.address) {
      window.open(
        `https://www.google.com/maps/search/${encodeURIComponent(customer.address)}`,
        '_blank'
      )
    }
  }

  return (
    <div
      className={`csc ${compact ? 'csc--compact' : ''} ${isSelected ? 'csc--selected' : ''}`}
      onClick={() => onClick?.(customer)}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
    >
      {/* الصف العلوي: الاسم + الكود */}
      <div className="csc-header">
        <div className="csc-title">
          <span className="csc-name">{customer.name}</span>
          <span className="csc-code">{customer.code}</span>
        </div>
        {isSelected && (
          <span className="csc-selected-badge">
            <Check size={12} /> محدد
          </span>
        )}
      </div>

      {/* معلومات الاتصال والموقع */}
      <div className="csc-details">
        {(customer.phone || customer.mobile) && (
          <div className="csc-row">
            <Phone size={13} />
            <a
              href={`tel:${customer.phone || customer.mobile}`}
              className="csc-phone"
              onClick={e => e.stopPropagation()}
            >
              {customer.phone || customer.mobile}
            </a>
          </div>
        )}

        {locationText && (
          <div className="csc-row">
            <MapPin size={13} />
            <span>{locationText}</span>
            {(hasGPS || customer.address) && (
              <button
                className="csc-nav-btn"
                onClick={handleNavigate}
                type="button"
                title="فتح في الخريطة"
              >
                <Navigation size={12} />
              </button>
            )}
          </div>
        )}

        {/* الصف المالي */}
        {!compact && (
          <div className="csc-row csc-financial">
            <CreditCard size={13} />
            <span className={hasDebt ? 'csc-debt' : ''}>
              الرصيد: {customer.current_balance.toLocaleString('en-US')} ج.م
            </span>
            <span className="csc-separator">|</span>
            <span>حد: {customer.credit_limit.toLocaleString('en-US')}</span>
          </div>
        )}

        {/* مؤشر GPS */}
        <div className="csc-indicators">
          <span className={`csc-gps-dot ${hasGPS ? 'csc-gps-dot--on' : 'csc-gps-dot--off'}`}>
            📍 {hasGPS ? 'موقع محدد' : 'لا يوجد موقع'}
          </span>
        </div>
      </div>

      {/* زر الإضافة */}
      {onAdd && !isSelected && (
        <button
          className="csc-add-btn"
          onClick={(e) => { e.stopPropagation(); onAdd(customer) }}
          type="button"
        >
          <Plus size={14} /> إضافة
        </button>
      )}

      <style>{styles}</style>
    </div>
  )
}

const styles = `
  .csc {
    display: flex;
    flex-direction: column;
    gap: var(--space-2, 8px);
    padding: var(--space-3, 12px) var(--space-4, 16px);
    border: 1px solid var(--border-light, #e2e8f0);
    border-radius: var(--radius-lg, 12px);
    background: var(--bg-surface, white);
    transition: all 0.15s ease;
    position: relative;
    cursor: default;
  }
  .csc[role="button"] {
    cursor: pointer;
  }
  .csc:hover {
    border-color: var(--color-primary, #2563eb);
    box-shadow: 0 2px 8px rgba(37, 99, 235, 0.08);
  }
  .csc--selected {
    border-color: var(--color-primary, #2563eb);
    background: var(--color-primary-light, rgba(37,99,235,0.04));
  }
  .csc--compact {
    padding: var(--space-2, 8px) var(--space-3, 12px);
    gap: var(--space-1, 4px);
  }
  .csc-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2, 8px);
  }
  .csc-title {
    display: flex;
    align-items: center;
    gap: var(--space-2, 8px);
    flex: 1;
    min-width: 0;
  }
  .csc-name {
    font-weight: 600;
    font-size: var(--text-sm, 14px);
    color: var(--text-primary, #0f172a);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .csc-code {
    font-size: var(--text-xs, 12px);
    color: var(--text-muted, #64748b);
    background: var(--neutral-100, #f1f5f9);
    padding: 1px 6px;
    border-radius: var(--radius-sm, 4px);
    flex-shrink: 0;
    font-family: monospace;
  }
  .csc-selected-badge {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: var(--text-xs, 12px);
    color: var(--color-primary, #2563eb);
    background: var(--color-primary-light, rgba(37,99,235,0.1));
    padding: 2px 8px;
    border-radius: 99px;
    font-weight: 600;
    flex-shrink: 0;
  }
  .csc-details {
    display: flex;
    flex-direction: column;
    gap: var(--space-1, 4px);
  }
  .csc-row {
    display: flex;
    align-items: center;
    gap: var(--space-2, 8px);
    font-size: var(--text-xs, 12px);
    color: var(--text-secondary, #334155);
  }
  .csc-row svg {
    color: var(--text-muted, #64748b);
    flex-shrink: 0;
  }
  .csc-phone {
    color: var(--color-primary, #2563eb);
    text-decoration: none;
    font-weight: 500;
  }
  .csc-phone:hover {
    text-decoration: underline;
  }
  .csc-nav-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 22px;
    height: 22px;
    border: 1px solid var(--border-light, #e2e8f0);
    border-radius: var(--radius-sm, 4px);
    background: var(--bg-surface, white);
    cursor: pointer;
    padding: 0;
    color: var(--color-primary, #2563eb);
    transition: all 0.15s ease;
  }
  .csc-nav-btn:hover {
    background: var(--color-primary-light, rgba(37,99,235,0.1));
    border-color: var(--color-primary, #2563eb);
  }
  .csc-financial {
    font-weight: 500;
  }
  .csc-debt {
    color: var(--color-danger, #dc2626);
    font-weight: 600;
  }
  .csc-separator {
    color: var(--neutral-300, #cbd5e1);
    margin: 0 2px;
  }
  .csc-indicators {
    display: flex;
    gap: var(--space-2, 8px);
    margin-top: 2px;
  }
  .csc-gps-dot {
    font-size: 11px;
    font-weight: 500;
    padding: 1px 6px;
    border-radius: 99px;
  }
  .csc-gps-dot--on {
    color: var(--color-success, #16a34a);
    background: var(--color-success-light, rgba(22,163,74,0.1));
  }
  .csc-gps-dot--off {
    color: var(--text-muted, #64748b);
    background: var(--neutral-100, #f1f5f9);
  }
  .csc-add-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 4px;
    padding: 6px 14px;
    background: var(--color-primary, #2563eb);
    color: white;
    border: none;
    border-radius: var(--radius-md, 8px);
    font-size: var(--text-xs, 12px);
    font-weight: 600;
    cursor: pointer;
    transition: all 0.15s ease;
    align-self: flex-end;
  }
  .csc-add-btn:hover {
    background: var(--color-primary-hover, #1d4ed8);
    transform: translateY(-1px);
  }
  @media (max-width: 768px) {
    .csc {
      padding: var(--space-3, 12px);
    }
    .csc-add-btn {
      width: 100%;
    }
  }
`

export type { CustomerSearchCardProps }
