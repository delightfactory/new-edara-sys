/**
 * CustomerCreditChip — مكوّن موحد لعرض الحالة الائتمانية للعميل
 *
 * يدعم ثلاثة أوضاع:
 *   - compact (جدول/dropdown): أيقونة + رقم سريع فقط
 *   - card (بعد اختيار العميل في النموذج): بطاقة كاملة مع شريط تقدم
 *   - inline (بطاقات الموبايل): سطر واحد شامل
 *
 * يعمل على البيانات المتاحة مباشرة من جدول customers:
 *   - payment_terms, credit_limit, credit_days, current_balance
 */

import { formatNumber } from '@/lib/utils/format'

interface CustomerCreditChipProps {
  payment_terms: string
  credit_limit: number
  credit_days?: number
  current_balance?: number
  mode?: 'compact' | 'card' | 'inline'
}

/** حساب الحالة الائتمانية من بيانات العميل */
export function computeCreditState(props: {
  payment_terms: string
  credit_limit: number
  current_balance?: number
}) {
  const { payment_terms, credit_limit, current_balance = 0 } = props

  // نقدي — لا ائتمان
  if (payment_terms === 'cash') {
    return { type: 'cash' as const }
  }

  // ائتماني ولكن بدون حد محدد
  if (!credit_limit || credit_limit <= 0) {
    return {
      type: 'no_limit' as const,
      balance: current_balance,
    }
  }

  const available = Math.max(0, credit_limit - current_balance)
  const usedPct   = Math.min(1, current_balance / credit_limit)
  const isOver    = current_balance >= credit_limit
  const isWarn    = usedPct >= 0.8 && !isOver

  return {
    type:      'credit' as const,
    available,
    limit:     credit_limit,
    balance:   current_balance,
    usedPct,
    isOver,
    isWarn,
    accent:    isOver ? '#dc2626' : isWarn ? '#d97706' : '#16a34a',
    gradFrom:  isOver ? '#ef4444' : isWarn ? '#f59e0b' : '#4ade80',
    bg:        isOver ? 'rgba(220,38,38,0.06)' : isWarn ? 'rgba(217,119,6,0.06)' : 'rgba(22,163,74,0.06)',
    border:    isOver ? 'rgba(220,38,38,0.2)' : isWarn ? 'rgba(217,119,6,0.2)' : 'rgba(22,163,74,0.2)',
    label:     isOver ? '⛔ تجاوز الحد' : isWarn ? '⚠️ تحذير' : '✓ متاح',
    labelShort: isOver ? 'تجاوز' : isWarn ? 'تحذير' : 'متاح',
  }
}

export default function CustomerCreditChip({
  payment_terms,
  credit_limit,
  credit_days,
  current_balance = 0,
  mode = 'compact',
}: CustomerCreditChipProps) {
  const state = computeCreditState({ payment_terms, credit_limit, current_balance })

  // ── نقدي ──────────────────────────────────────────────────────
  if (state.type === 'cash') {
    if (mode === 'card') return (
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '7px 12px', borderRadius: 8,
        background: 'rgba(37,99,235,0.05)',
        border: '1px solid rgba(37,99,235,0.15)',
      }}>
        <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)', fontWeight: 500 }}>طريقة الدفع</span>
        <span style={{
          fontSize: '0.78rem', fontWeight: 700, color: 'var(--color-primary)',
          background: 'rgba(37,99,235,0.08)', padding: '2px 8px', borderRadius: 99,
        }}>💵 نقدي فقط</span>
      </div>
    )
    if (mode === 'inline') return (
      <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>نقدي • لا ائتمان</span>
    )
    // compact
    return <span style={{ fontSize: '0.7rem', color: 'var(--text-muted)', fontStyle: 'italic' }}>نقدي</span>
  }

  // ── آجل بدون حد ───────────────────────────────────────────────
  if (state.type === 'no_limit') {
    const hasDebt = state.balance > 0
    if (mode === 'card') return (
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '7px 12px', borderRadius: 8,
        background: hasDebt ? 'rgba(217,119,6,0.06)' : 'rgba(37,99,235,0.05)',
        border: `1px solid ${hasDebt ? 'rgba(217,119,6,0.2)' : 'rgba(37,99,235,0.15)'}`,
      }}>
        <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)', fontWeight: 500 }}>الائتمان</span>
        <span style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>غير محدود</span>
        {hasDebt && (
          <span style={{ fontSize: '0.75rem', fontWeight: 700, color: '#d97706', marginInlineStart: 'auto' }}>
            مديون: {formatNumber(state.balance)} ج.م
          </span>
        )}
      </div>
    )
    return <span style={{ fontSize: '0.7rem', color: 'var(--text-muted)' }}>غير محدود</span>
  }

  // ── ائتماني بحد محدد ──────────────────────────────────────────
  const s = state

  // ── CARD MODE (بعد اختيار العميل في النموذج) ──────────────────
  if (mode === 'card') return (
    <div style={{
      display: 'flex', flexDirection: 'column', gap: 7,
      padding: '9px 13px', borderRadius: 10,
      background: s.bg, border: `1.5px solid ${s.border}`,
      minWidth: 180, flex: '1 1 180px', maxWidth: 300,
    }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <span style={{ fontSize: '0.68rem', color: 'var(--text-muted)', fontWeight: 600 }}>
          {credit_days ? `آجل ${credit_days} يوم` : 'الائتمان المتاح'}
        </span>
        <span style={{
          fontSize: '0.62rem', fontWeight: 800,
          color: s.accent, background: `${s.accent}18`,
          padding: '2px 7px', borderRadius: 99, border: `1px solid ${s.accent}28`,
        }}>
          {s.label}
        </span>
      </div>

      {/* Amount */}
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 4 }}>
        <span style={{
          fontSize: '1.15rem', fontWeight: 900, fontVariantNumeric: 'tabular-nums',
          color: s.accent, lineHeight: 1, letterSpacing: '-0.5px',
        }}>
          {formatNumber(s.available)}
        </span>
        <span style={{ fontSize: '0.72rem', fontWeight: 700, color: 'var(--text-muted)' }}>ج.م</span>
        <span style={{ fontSize: '0.65rem', color: 'var(--text-muted)', marginInlineStart: 'auto' }}>
          / {formatNumber(s.limit)}
        </span>
      </div>

      {/* Progress bar */}
      <div style={{ height: 5, borderRadius: 99, background: 'rgba(0,0,0,0.08)', overflow: 'hidden' }}>
        <div style={{
          height: '100%', borderRadius: 99,
          width: `${s.usedPct * 100}%`,
          background: `linear-gradient(to left, ${s.accent}, ${s.gradFrom})`,
          transition: 'width 0.45s cubic-bezier(0.4,0,0.2,1)',
          boxShadow: `0 0 6px ${s.accent}50`,
        }} />
      </div>

      {/* Footer */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ fontSize: '0.62rem', color: 'var(--text-muted)' }}>
          مستخدم: {formatNumber(s.balance)}
        </span>
        <span style={{ fontSize: '0.72rem', fontWeight: 800, color: s.accent }}>
          {Math.round(s.usedPct * 100)}%
        </span>
      </div>
    </div>
  )

  // ── INLINE MODE (بطاقات الموبايل في قائمة العملاء) ─────────────
  if (mode === 'inline') return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <span style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums', fontSize: 'var(--text-sm)', color: s.accent }}>
          {formatNumber(s.available)} ج.م
        </span>
        <span style={{
          fontSize: '0.6rem', fontWeight: 700, color: s.accent,
          background: `${s.accent}18`, padding: '1px 5px', borderRadius: 99,
        }}>{s.labelShort}</span>
        <span style={{ fontSize: '0.62rem', color: 'var(--text-muted)', marginInlineStart: 'auto' }}>
          من {formatNumber(s.limit)} • {Math.round(s.usedPct * 100)}%
        </span>
      </div>
      <div style={{ height: 3, borderRadius: 99, background: 'var(--border-color)', overflow: 'hidden' }}>
        <div style={{
          height: '100%', borderRadius: 99, width: `${s.usedPct * 100}%`,
          background: `linear-gradient(to left, ${s.accent}, ${s.gradFrom})`,
        }} />
      </div>
    </div>
  )

  // ── COMPACT MODE (عمود الجدول على الديسكتوب) ───────────────────
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 100 }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 4 }}>
        <span style={{
          fontWeight: 800, fontVariantNumeric: 'tabular-nums',
          fontSize: 'var(--text-sm)', color: s.accent, letterSpacing: '-0.2px',
        }}>
          {formatNumber(s.available)}
        </span>
        <span style={{ fontSize: '0.62rem', color: 'var(--text-muted)', fontWeight: 500 }}>ج.م</span>
        <span style={{
          marginRight: 'auto', fontSize: '0.58rem', fontWeight: 700, color: s.accent,
          background: `${s.accent}18`, padding: '1px 5px', borderRadius: 99,
        }}>{s.labelShort}</span>
      </div>
      <div style={{ height: 4, borderRadius: 99, background: 'var(--border-color)', overflow: 'hidden' }}>
        <div style={{
          height: '100%', borderRadius: 99, width: `${s.usedPct * 100}%`,
          background: `linear-gradient(to left, ${s.accent}, ${s.gradFrom})`,
          transition: 'width 0.3s ease',
        }} />
      </div>
      <span style={{ fontSize: '0.58rem', color: 'var(--text-muted)' }}>
        {Math.round(s.usedPct * 100)}% • {formatNumber(s.limit)}
      </span>
    </div>
  )
}
