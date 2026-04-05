/**
 * FilterBar — نظام الفلاتر الاحترافي لـ EDARA v2
 *
 * ─── مبادئ الأداء ────────────────────────────────────────────────────
 * 1. FilterBar.Search: debounce 350ms — يُظهر الكتابة فوراً لكن يُؤخّر
 *    استدعاء onChange حتى توقف المستخدم. يمنع آلاف الـ requests المتكررة.
 *
 * 2. FilterBar.Select: تغيير فوري (لا debounce) — الـ select يتغير بنقرة واحدة
 *    فلا داعي للتأخير.
 *
 * 3. CSS Grid للطي/الفتح: أسرع وأسلس من max-height (لا overflow إضافي).
 *
 * 4. لا Context — كل child prop-driven. لا overhead للـ React Context.
 *
 * ─── مبادئ التصميم ───────────────────────────────────────────────────
 * - Premium Enterprise: مستوحى من Linear / Notion / Figma
 * - EDARA Design System: CSS Variables فقط، لا hard-coded colors
 * - RTL-native: flex/gap بدلاً من margin يدوي
 * - Micro-animations: transition على كل عنصر تفاعلي
 */

import { useState, useEffect, useRef, useCallback, useId } from 'react'
import { SlidersHorizontal, RotateCcw, ChevronDown, Search, X, CalendarDays } from 'lucide-react'

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

export interface FilterOption {
  value: string
  label: string
}

export interface FilterStat {
  label:    string
  value:    string | number
  variant?: 'default' | 'success' | 'warning' | 'danger' | 'info'
  loading?: boolean
}

interface FilterBarProps {
  title?:       string
  activeCount?: number
  onReset:      () => void
  defaultOpen?: boolean
  stats?:       FilterStat[]
  children:     React.ReactNode
}

interface FilterSearchProps {
  value:        string
  onChange:     (v: string) => void
  placeholder?: string
  fullWidth?:   boolean
  debounceMs?:  number
}

interface FilterSelectProps {
  label:      string
  value:      string
  onChange:   (v: string) => void
  options:    FilterOption[]
  allLabel?:  string
  loading?:   boolean
  fullWidth?: boolean
}

interface FilterDateRangeProps {
  label?:       string
  from:         string
  to:           string
  onFromChange: (v: string) => void
  onToChange:   (v: string) => void
  fullWidth?:   boolean
}

interface FilterToggleProps {
  label:    string
  value:    boolean
  onChange: (v: boolean) => void
}

interface FilterDividerProps {
  label?: string
}

// ─────────────────────────────────────────────────────────────────────────────
// Child: Search — مع debounce داخلي لحماية الأداء
// ─────────────────────────────────────────────────────────────────────────────

function FilterSearch({
  value,
  onChange,
  placeholder = 'بحث...',
  fullWidth,
  debounceMs = 350,
}: FilterSearchProps) {
  // حالة داخلية للعرض الفوري — الكتابة تظهر فوراً
  const [inputVal, setInputVal] = useState(value)
  const timerRef = useRef<ReturnType<typeof setTimeout>>()

  // مزامنة مع القيمة الخارجية (عند إعادة التعيين)
  useEffect(() => { setInputVal(value) }, [value])

  const handleChange = useCallback((v: string) => {
    setInputVal(v)                        // عرض فوري — لا تأخير
    clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => onChange(v), debounceMs) // API call مؤجّل
  }, [onChange, debounceMs])

  const handleClear = useCallback(() => {
    setInputVal('')
    clearTimeout(timerRef.current)
    onChange('')  // مسح فوري
  }, [onChange])

  useEffect(() => () => clearTimeout(timerRef.current), [])

  return (
    <div className={`fb-field${fullWidth ? ' fb-full' : ''}`}>
      <div className="fb-search-wrap">
        <Search size={15} className="fb-search-icon" aria-hidden="true" />
        <input
          type="text"
          value={inputVal}
          onChange={e => handleChange(e.target.value)}
          placeholder={placeholder}
          className="fb-input fb-search-input"
          autoComplete="off"
          spellCheck={false}
        />
        {inputVal && (
          <button
            className="fb-clear-btn"
            onClick={handleClear}
            type="button"
            aria-label="مسح البحث"
          >
            <X size={11} />
          </button>
        )}
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Child: Select
// ─────────────────────────────────────────────────────────────────────────────

function FilterSelect({
  label,
  value,
  onChange,
  options,
  allLabel,
  loading,
  fullWidth,
}: FilterSelectProps) {
  const id = useId()
  const isActive = Boolean(value)
  const all = allLabel ?? `كل ${label}`

  // عنوان الخيار الحالي للعرض
  const currentLabel = isActive
    ? (options.find(o => o.value === value)?.label ?? value)
    : all

  return (
    <div className={`fb-field${fullWidth ? ' fb-full' : ''}`}>
      <div className={`fb-select-wrap${isActive ? ' fb-select-active' : ''}`}>
        {isActive && <div className="fb-select-dot" aria-hidden="true" />}
        <label htmlFor={id} className="fb-select-label">
          {label}
          {isActive && <span className="fb-select-value-hint">: {currentLabel}</span>}
        </label>
        <select
          id={id}
          value={value}
          onChange={e => onChange(e.target.value)}
          className="fb-select"
          disabled={loading}
          aria-label={label}
        >
          <option value="">{loading ? 'جاري التحميل...' : all}</option>
          {options.map(o => (
            <option key={o.value} value={o.value}>{o.label}</option>
          ))}
        </select>
        <ChevronDown size={12} className="fb-select-chevron" aria-hidden="true" />
        {isActive && (
          <button
            className="fb-select-clear"
            onClick={e => { e.stopPropagation(); onChange('') }}
            type="button"
            aria-label={`مسح ${label}`}
          >
            <X size={10} />
          </button>
        )}
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Child: Date Range
// ─────────────────────────────────────────────────────────────────────────────

function FilterDateRange({
  label = 'الفترة الزمنية',
  from,
  to,
  onFromChange,
  onToChange,
  fullWidth,
}: FilterDateRangeProps) {
  const isActive = Boolean(from || to)

  return (
    <div className={`fb-field fb-daterange${fullWidth ? ' fb-full' : ''}`}>
      <div className={`fb-daterange-wrap${isActive ? ' fb-select-active' : ''}`}>
        {isActive && <div className="fb-select-dot" aria-hidden="true" />}
        <CalendarDays size={13} className="fb-daterange-icon" aria-hidden="true" />
        <span className="fb-select-label fb-daterange-label">{label}</span>

        <div className="fb-daterange-fields">
          <div className="fb-daterange-field">
            <span className="fb-daterange-hint">من</span>
            <input
              type="date"
              value={from}
              onChange={e => onFromChange(e.target.value)}
              className="fb-date-input"
              max={to || undefined}
              aria-label={`${label} من`}
            />
            {from && (
              <button className="fb-inline-clear" onClick={() => onFromChange('')} type="button" aria-label="مسح تاريخ البداية">
                <X size={9} />
              </button>
            )}
          </div>

          <span className="fb-daterange-sep" aria-hidden="true">—</span>

          <div className="fb-daterange-field">
            <span className="fb-daterange-hint">إلى</span>
            <input
              type="date"
              value={to}
              onChange={e => onToChange(e.target.value)}
              className="fb-date-input"
              min={from || undefined}
              aria-label={`${label} إلى`}
            />
            {to && (
              <button className="fb-inline-clear" onClick={() => onToChange('')} type="button" aria-label="مسح تاريخ النهاية">
                <X size={9} />
              </button>
            )}
          </div>
        </div>

        {isActive && (
          <button
            className="fb-select-clear"
            onClick={() => { onFromChange(''); onToChange('') }}
            type="button"
            aria-label="مسح الفترة"
          >
            <X size={10} />
          </button>
        )}
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Child: Toggle
// ─────────────────────────────────────────────────────────────────────────────

function FilterToggle({ label, value, onChange }: FilterToggleProps) {
  return (
    <div className="fb-field">
      <button
        type="button"
        role="switch"
        aria-checked={value}
        className={`fb-toggle${value ? ' fb-toggle-on' : ''}`}
        onClick={() => onChange(!value)}
      >
        <span className={`fb-toggle-track${value ? ' fb-toggle-track-on' : ''}`}>
          <span className="fb-toggle-thumb" />
        </span>
        <span className="fb-toggle-label">{label}</span>
      </button>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Child: Divider (فاصل بصري اختياري)
// ─────────────────────────────────────────────────────────────────────────────

function FilterDivider({ label }: FilterDividerProps) {
  return (
    <div className="fb-divider">
      {label && <span className="fb-divider-label">{label}</span>}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Root: FilterBar
// ─────────────────────────────────────────────────────────────────────────────

function FilterBar({
  title = 'فلاتر البحث',
  activeCount = 0,
  onReset,
  defaultOpen = false,
  stats,
  children,
}: FilterBarProps) {
  const [open, setOpen] = useState(defaultOpen)

  const toggle = useCallback(() => setOpen(p => !p), [])

  const handleReset = useCallback((e: React.MouseEvent) => {
    e.stopPropagation()
    onReset()
  }, [onReset])

  return (
    <>
      <div className={`fb-root${open ? ' fb-open' : ''}${activeCount > 0 ? ' fb-root-active' : ''}`}>

        {/* ── Header ─────────────────────────────────────────────────── */}
        <button
          type="button"
          className="fb-header"
          onClick={toggle}
          aria-expanded={open}
          aria-controls="fb-body"
        >
          <div className="fb-header-start">
            <div className="fb-icon">
              <SlidersHorizontal size={13} />
            </div>
            <span className="fb-title">{title}</span>
            {activeCount > 0 && (
              <span className="fb-count-badge">
                {activeCount}
              </span>
            )}
            {/* ── Stats pills ────────────────────────────── */}
            {stats && stats.length > 0 && (
              <div className="fb-stats" role="status" aria-live="polite">
                {stats.map((s, i) => (
                  <div key={i} className={`fb-stat fb-stat-${s.variant ?? 'default'}`}>
                    {s.loading ? (
                      <span className="fb-stat-skeleton" />
                    ) : (
                      <>
                        <span className="fb-stat-value">{s.value}</span>
                        <span className="fb-stat-label">{s.label}</span>
                      </>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="fb-header-end">
            {activeCount > 0 && (
              <button
                type="button"
                className="fb-reset"
                onClick={handleReset}
                aria-label="إعادة تعيين الفلاتر"
              >
                <RotateCcw size={11} />
                <span>إعادة تعيين</span>
              </button>
            )}
            <div className={`fb-chevron-wrap${open ? ' fb-chevron-open' : ''}`}>
              <ChevronDown size={14} />
            </div>
          </div>
        </button>

        {/* ── Body (CSS Grid animation — no max-height jank) ────────── */}
        <div className="fb-body" id="fb-body" role="region" aria-hidden={!open}>
          <div className="fb-body-inner">
            <div className="fb-fields">
              {children}
            </div>
          </div>
        </div>
      </div>

      {/* ── Styles ───────────────────────────────────────────────────── */}
      <style>{`

        /* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ROOT */
        .fb-root {
          border: 1px solid var(--border-subtle, #e2e8f0);
          border-radius: var(--radius-xl, 12px);
          background: var(--bg-surface, #fff);
          overflow: hidden;
          margin-bottom: var(--space-4, 1rem);
          box-shadow: 0 1px 3px rgba(0,0,0,0.05);
          transition: box-shadow 0.2s, border-color 0.2s;
        }
        .fb-root:focus-within {
          box-shadow: 0 2px 8px rgba(37,99,235,0.08);
        }
        .fb-open {
          border-color: var(--color-primary, #2563eb);
          border-color: rgba(37,99,235,0.25);
        }

        /* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ HEADER */
        .fb-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          width: 100%;
          padding: var(--space-3, .75rem) var(--space-4, 1rem);
          background: none;
          border: none;
          cursor: pointer;
          gap: var(--space-3);
          color: var(--text-primary, #0f172a);
          transition: background 0.15s;
          text-align: right;
          min-height: 48px;
        }
        .fb-header:hover {
          background: var(--bg-hover, rgba(0,0,0,0.025));
        }
        .fb-header-start {
          display: flex;
          align-items: center;
          gap: var(--space-2, .5rem);
          flex: 1;
          min-width: 0;
        }
        .fb-header-end {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          flex-shrink: 0;
        }

        /* ── Icon */
        .fb-icon {
          width: 30px; height: 30px;
          border-radius: var(--radius-lg, 8px);
          background: linear-gradient(135deg,
            var(--color-primary-light, rgba(37,99,235,.1)),
            rgba(37,99,235,.05)
          );
          color: var(--color-primary, #2563eb);
          display: flex; align-items: center; justify-content: center;
          flex-shrink: 0;
          border: 1px solid rgba(37,99,235,.12);
        }

        /* ── Title */
        .fb-title {
          font-size: var(--text-sm, .875rem);
          font-weight: 600;
          color: var(--text-primary);
          white-space: nowrap;
        }

        /* ── Active count badge */
        .fb-count-badge {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          min-width: 20px;
          height: 20px;
          padding: 0 6px;
          border-radius: 9999px;
          background: var(--color-primary, #2563eb);
          color: #fff;
          font-size: 11px;
          font-weight: 700;
          line-height: 1;
          animation: popIn .2s cubic-bezier(.34,1.56,.64,1);
        }
        @keyframes popIn {
          from { transform: scale(0.5); opacity: 0; }
          to   { transform: scale(1);   opacity: 1; }
        }

        /* ── Chevron */
        .fb-chevron-wrap {
          display: flex; align-items: center;
          color: var(--text-muted, #64748b);
          transition: transform 0.25s cubic-bezier(.4,0,.2,1), color 0.15s;
        }
        .fb-chevron-open {
          transform: rotate(180deg);
          color: var(--color-primary, #2563eb);
        }

        /* ── Reset button */
        .fb-reset {
          display: inline-flex;
          align-items: center;
          gap: 5px;
          padding: 5px 10px;
          border-radius: var(--radius-lg, 8px);
          border: 1px solid var(--border-default, #e2e8f0);
          background: var(--bg-surface, #fff);
          color: var(--text-secondary, #334155);
          font-size: var(--text-xs, .75rem);
          font-family: inherit;
          cursor: pointer;
          transition: all 0.15s;
          white-space: nowrap;
        }
        .fb-reset:hover {
          background: var(--color-danger-light, rgba(220,38,38,.08));
          border-color: var(--color-danger, #dc2626);
          color: var(--color-danger, #dc2626);
        }

        /* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ BODY */
        .fb-body {
          display: grid;
          grid-template-rows: 0fr;
          transition: grid-template-rows 0.28s cubic-bezier(.4,0,.2,1);
          border-top: 0px solid var(--border-subtle, #e2e8f0);
          background: var(--bg-base, #f8fafc);
        }
        .fb-open .fb-body {
          grid-template-rows: 1fr;
          border-top-width: 1px;
        }
        .fb-body-inner { overflow: hidden; }

        /* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ FIELDS */
        .fb-fields {
          display: flex;
          flex-wrap: wrap;
          gap: var(--space-3, .75rem);
          padding: var(--space-4, 1rem);
          align-items: flex-end;
        }

        .fb-field {
          display: flex;
          flex-direction: column;
          min-width: 120px;
          flex: 1;
        }
        .fb-full { flex: 2 1 240px; }

        /* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ SEARCH */
        .fb-search-wrap {
          position: relative;
          display: flex;
          align-items: center;
        }
        .fb-search-icon {
          position: absolute;
          right: var(--space-3);
          color: var(--text-muted);
          pointer-events: none;
          z-index: 1;
        }
        .fb-input {
          width: 100%;
          height: 40px;
          padding: 0 calc(var(--space-3) + 22px) 0 var(--space-3);
          border: 1.5px solid var(--border-default, #e2e8f0);
          border-radius: var(--radius-lg, 8px);
          background: var(--bg-surface, #fff);
          color: var(--text-primary);
          font-size: var(--text-sm);
          font-family: inherit;
          outline: none;
          transition: border-color 0.15s, box-shadow 0.15s, background 0.15s;
        }
        .fb-input::placeholder { color: var(--text-muted); }
        .fb-input:focus {
          border-color: var(--color-primary);
          box-shadow: 0 0 0 3px var(--color-primary-light);
          background: var(--bg-surface);
        }
        .fb-search-input {
          padding-right: calc(var(--space-3) + 24px);
          padding-left: 32px;
        }
        .fb-clear-btn {
          position: absolute;
          left: var(--space-2);
          display: flex; align-items: center; justify-content: center;
          width: 22px; height: 22px;
          border-radius: 50%;
          border: none;
          background: var(--neutral-200, #e2e8f0);
          color: var(--text-muted);
          cursor: pointer;
          transition: all 0.15s;
          z-index: 1;
        }
        .fb-clear-btn:hover {
          background: var(--neutral-300, #cbd5e1);
          color: var(--text-primary);
        }

        /* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ SELECT */
        .fb-select-wrap {
          position: relative;
          display: flex;
          flex-direction: column;
          gap: 2px;
        }

        /* الـ label فوق الـ select */
        .fb-select-label {
          display: flex;
          align-items: center;
          gap: 4px;
          font-size: var(--text-xs, .75rem);
          font-weight: 600;
          color: var(--text-muted, #64748b);
          padding-right: 2px;
          height: 18px;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          letter-spacing: 0.01em;
        }
        .fb-select-value-hint {
          color: var(--color-primary, #2563eb);
          font-weight: 700;
          max-width: 100px;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        /* نقطة المؤشر عند التفعيل */
        .fb-select-dot {
          position: absolute;
          top: 7px; right: 10px;
          width: 6px; height: 6px;
          border-radius: 50%;
          background: var(--color-primary);
          z-index: 2;
          animation: popIn .2s ease;
        }

        .fb-select {
          height: 40px;
          padding: 0 var(--space-3) 0 28px; /* left for chevron + clear */
          border: 1.5px solid var(--border-default, #e2e8f0);
          border-radius: var(--radius-lg, 8px);
          background: var(--bg-surface, #fff);
          color: var(--text-primary);
          font-size: var(--text-sm);
          font-family: inherit;
          appearance: none;
          cursor: pointer;
          outline: none;
          width: 100%;
          transition: border-color 0.15s, background 0.15s, box-shadow 0.15s;
        }
        .fb-select:focus {
          border-color: var(--color-primary);
          box-shadow: 0 0 0 3px var(--color-primary-light);
        }
        .fb-select:disabled { opacity: 0.5; cursor: not-allowed; }

        /* حالة التفعيل */
        .fb-select-active .fb-select {
          border-color: var(--color-primary);
          background: linear-gradient(180deg,
            rgba(37,99,235,.04) 0%,
            var(--bg-surface) 100%
          );
          color: var(--color-primary);
          font-weight: 600;
        }

        .fb-select-chevron {
          position: absolute;
          left: 8px;
          bottom: 13px;
          color: var(--text-muted);
          pointer-events: none;
          transition: color 0.15s;
        }
        .fb-select-active .fb-select-chevron {
          color: var(--color-primary);
        }

        /* زر مسح الـ select */
        .fb-select-clear {
          position: absolute;
          left: 22px;
          bottom: 10px;
          display: flex; align-items: center; justify-content: center;
          width: 18px; height: 18px;
          border-radius: 50%;
          border: none;
          background: rgba(37,99,235,.15);
          color: var(--color-primary);
          cursor: pointer;
          transition: all 0.15s;
        }
        .fb-select-clear:hover {
          background: var(--color-primary);
          color: #fff;
        }

        /* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ DATE RANGE */
        .fb-daterange { flex: 2 1 220px; }

        .fb-daterange-wrap {
          position: relative;
          height: 40px;
          display: flex;
          align-items: center;
          gap: var(--space-2);
          padding: 0 var(--space-3);
          border: 1.5px solid var(--border-default, #e2e8f0);
          border-radius: var(--radius-lg, 8px);
          background: var(--bg-surface, #fff);
          cursor: pointer;
          transition: border-color 0.15s, box-shadow 0.15s, background 0.15s;
        }
        .fb-daterange-wrap:focus-within {
          border-color: var(--color-primary);
          box-shadow: 0 0 0 3px var(--color-primary-light);
        }
        .fb-select-active.fb-daterange-wrap {
          border-color: var(--color-primary);
          background: linear-gradient(180deg,
            rgba(37,99,235,.04) 0%,
            var(--bg-surface) 100%
          );
        }
        .fb-daterange-icon {
          color: var(--text-muted);
          flex-shrink: 0;
          transition: color 0.15s;
        }
        .fb-select-active .fb-daterange-icon { color: var(--color-primary); }
        .fb-daterange-label {
          font-size: var(--text-xs);
          font-weight: 600;
          color: var(--text-muted);
          white-space: nowrap;
          flex-shrink: 0;
        }
        .fb-select-active .fb-daterange-label { color: var(--color-primary); }
        .fb-daterange-fields {
          display: flex;
          align-items: center;
          gap: var(--space-1);
          flex: 1;
          min-width: 0;
        }
        .fb-daterange-field {
          display: flex;
          align-items: center;
          gap: 3px;
          flex: 1;
          min-width: 0;
        }
        .fb-daterange-hint {
          font-size: 10px;
          color: var(--text-muted);
          white-space: nowrap;
          flex-shrink: 0;
        }
        .fb-date-input {
          flex: 1;
          min-width: 0;
          border: none;
          background: transparent;
          color: var(--text-primary);
          font-size: var(--text-xs);
          font-family: inherit;
          outline: none;
          cursor: pointer;
        }
        .fb-date-input::-webkit-calendar-picker-indicator {
          opacity: 0.5;
          cursor: pointer;
          filter: invert(30%);
        }
        .fb-daterange-sep {
          color: var(--text-muted);
          font-size: var(--text-xs);
          flex-shrink: 0;
        }
        .fb-inline-clear {
          display: flex; align-items: center; justify-content: center;
          width: 14px; height: 14px;
          border-radius: 50%;
          border: none;
          background: var(--neutral-200);
          color: var(--text-muted);
          cursor: pointer;
          padding: 0;
          flex-shrink: 0;
          transition: all 0.12s;
        }
        .fb-inline-clear:hover { background: var(--neutral-300); }

        /* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ TOGGLE */
        .fb-toggle {
          display: inline-flex;
          align-items: center;
          gap: var(--space-2);
          height: 40px;
          padding: 0 var(--space-3);
          border-radius: var(--radius-lg, 8px);
          border: 1.5px solid var(--border-default, #e2e8f0);
          background: var(--bg-surface, #fff);
          cursor: pointer;
          transition: all 0.15s;
          white-space: nowrap;
          font-family: inherit;
          width: 100%;
        }
        .fb-toggle:hover { border-color: var(--color-primary); }
        .fb-toggle-on {
          border-color: var(--color-primary);
          background: var(--color-primary-light);
        }
        .fb-toggle-track {
          width: 30px; height: 17px;
          border-radius: 9999px;
          background: var(--neutral-300);
          position: relative;
          transition: background 0.2s;
          flex-shrink: 0;
        }
        .fb-toggle-track-on { background: var(--color-primary); }
        .fb-toggle-thumb {
          position: absolute;
          top: 2px; right: 2px;
          width: 13px; height: 13px;
          border-radius: 50%;
          background: #fff;
          box-shadow: 0 1px 3px rgba(0,0,0,.25);
          transition: right 0.18s cubic-bezier(.4,0,.2,1);
        }
        .fb-toggle-track-on .fb-toggle-thumb { right: calc(100% - 15px); }
        .fb-toggle-label {
          font-size: var(--text-sm);
          color: var(--text-primary);
          font-family: inherit;
        }
        .fb-toggle-on .fb-toggle-label {
          color: var(--color-primary);
          font-weight: 600;
        }

        /* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ DIVIDER */
        .fb-divider {
          width: 100%;
          display: flex;
          align-items: center;
          gap: var(--space-2);
          margin: var(--space-1) 0;
        }
        .fb-divider::before,
        .fb-divider::after {
          content: '';
          flex: 1;
          height: 1px;
          background: var(--border-subtle);
        }
        .fb-divider-label {
          font-size: 10px;
          font-weight: 700;
          color: var(--text-muted);
          text-transform: uppercase;
          letter-spacing: .05em;
          white-space: nowrap;
        }

        /* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ STATS PILLS */
        .fb-stats {
          display: flex;
          align-items: center;
          gap: 6px;
          flex-wrap: nowrap;
          margin-right: var(--space-1);
          /* separator visual */
          padding-right: var(--space-3);
          border-right: 1px solid var(--border-subtle);
          overflow: hidden;
        }

        .fb-stat {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          padding: 3px 8px;
          border-radius: 9999px;
          border: 1px solid transparent;
          font-size: 11px;
          font-weight: 600;
          white-space: nowrap;
          transition: all 0.2s;
          animation: statIn 0.25s cubic-bezier(.34,1.56,.64,1);
          cursor: default;
          user-select: none;
        }
        @keyframes statIn {
          from { opacity: 0; transform: translateY(-4px) scale(0.9); }
          to   { opacity: 1; transform: translateY(0)    scale(1);   }
        }

        /* القيمة الرقمية */
        .fb-stat-value {
          font-size: 12px;
          font-weight: 800;
          font-variant-numeric: tabular-nums;
          letter-spacing: -0.02em;
        }
        /* التسمية */
        .fb-stat-label {
          font-weight: 500;
          opacity: 0.85;
        }

        /* Variants */
        .fb-stat-default {
          background: var(--neutral-100, #f1f5f9);
          border-color: var(--neutral-200, #e2e8f0);
          color: var(--neutral-700, #334155);
        }
        .fb-stat-success {
          background: var(--color-success-light, rgba(22,163,74,.1));
          border-color: rgba(22,163,74,.2);
          color: var(--color-success, #16a34a);
        }
        .fb-stat-warning {
          background: var(--color-warning-light, rgba(217,119,6,.1));
          border-color: rgba(217,119,6,.2);
          color: var(--color-warning, #d97706);
        }
        .fb-stat-danger {
          background: var(--color-danger-light, rgba(220,38,38,.08));
          border-color: rgba(220,38,38,.15);
          color: var(--color-danger, #dc2626);
        }
        .fb-stat-info {
          background: var(--color-info-light, rgba(2,132,199,.08));
          border-color: rgba(2,132,199,.15);
          color: var(--color-info, #0284c7);
        }

        /* Skeleton loader */
        .fb-stat-skeleton {
          display: inline-block;
          width: 52px; height: 12px;
          border-radius: 4px;
          background: linear-gradient(90deg,
            var(--neutral-200) 25%,
            var(--neutral-100) 50%,
            var(--neutral-200) 75%
          );
          background-size: 200% 100%;
          animation: shimmer 1.2s infinite;
        }
        @keyframes shimmer {
          from { background-position: 200% 0; }
          to   { background-position: -200% 0; }
        }

        /* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ RESPONSIVE */
        @media (max-width: 768px) {
          .fb-header { padding: var(--space-2) var(--space-3); min-height: 44px; }
          .fb-title   { font-size: var(--text-xs); }
          .fb-reset span { display: none; }
          .fb-reset { padding: 5px 7px; }

          /* إخفاء الإحصاءات الزائدة على الهاتف */
          .fb-stats { gap: 4px; }
          .fb-stat:nth-child(n+3) { display: none; }
          .fb-stat { padding: 2px 6px; font-size: 10px; }
          .fb-stat-value { font-size: 11px; }

          .fb-fields {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: var(--space-2);
            padding: var(--space-3);
          }
          .fb-full    { grid-column: 1 / -1; }
          .fb-daterange { grid-column: 1 / -1; }
          .fb-divider { grid-column: 1 / -1; }

          .fb-input, .fb-select { font-size: var(--text-xs); }
          .fb-select { height: 38px; }
          .fb-toggle  { height: 38px; }
          .fb-daterange-wrap { height: 38px; }
          .fb-input { height: 38px; }
        }

        @media (max-width: 480px) {
          /* بدون فلتر: stat واحد فقط */
          .fb-stat:nth-child(n+2) { display: none; }
          .fb-stats { gap: 2px; }

          /* عند وجود فلتر نشط: أخفِ العنوان ← وفّر مساحة → أظهر 2 stats */
          .fb-root-active .fb-title { display: none; }
          .fb-root-active .fb-stat:nth-child(2) { display: flex !important; }
          .fb-root-active .fb-stat:nth-child(n+3) { display: none; }
        }

      `}</style>
    </>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Compound API
// ─────────────────────────────────────────────────────────────────────────────

FilterBar.Search    = FilterSearch
FilterBar.Select    = FilterSelect
FilterBar.DateRange = FilterDateRange
FilterBar.Toggle    = FilterToggle
FilterBar.Divider   = FilterDivider

export default FilterBar
