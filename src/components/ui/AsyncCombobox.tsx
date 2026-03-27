import { useState, useRef, useEffect, useCallback, useId } from 'react'
import { Check, ChevronsUpDown, Loader2, Search, X } from 'lucide-react'
import { useDebounce } from '@/hooks/useDebounce'

export interface ComboboxOption {
  value: string
  label: string
  sublabel?: string
  [key: string]: any
}

interface AsyncComboboxProps {
  label?: string
  placeholder?: string
  value?: string | null
  onChange: (value: string | null, option?: ComboboxOption | null) => void
  /** Async function to load options. Receives current search string. */
  loadOptions: (search: string) => Promise<ComboboxOption[]>
  error?: string
  hint?: string
  required?: boolean
  disabled?: boolean
  className?: string
  noOptionsText?: string
  /** Pre-loaded options (shown before typing) */
  defaultOptions?: ComboboxOption[]
}

function useIsMobile() {
  const [isMobile, setIsMobile] = useState(() =>
    typeof window !== 'undefined' ? window.innerWidth <= 768 : false
  )
  useEffect(() => {
    const mq = window.matchMedia('(max-width: 768px)')
    const handler = (e: MediaQueryListEvent) => setIsMobile(e.matches)
    mq.addEventListener('change', handler)
    return () => mq.removeEventListener('change', handler)
  }, [])
  return isMobile
}

/**
 * AsyncCombobox — Smart search dropdown (Enterprise-grade)
 *
 * - Debounced API calls (300ms) for performance
 * - MOBILE: Opens as a Bottom Sheet with full-width search keyboard
 * - DESKTOP: Opens as an inline popover dropdown
 * - Skeleton loading state during fetch
 * - Empty state with clear message
 * - aria-compliant: aria-expanded, aria-controls, aria-activedescendant
 * - Supports optional sublabel per option (e.g., phone number, code)
 *
 * Usage:
 * ```tsx
 * <AsyncCombobox
 *   label="العميل"
 *   placeholder="ابحث باسم العميل أو الكود..."
 *   required
 *   value={customerId}
 *   onChange={(id, option) => setCustomerId(id)}
 *   loadOptions={async (search) => {
 *     const { data } = await supabase.rpc('search_customers', { q: search })
 *     return data.map(c => ({ value: c.id, label: c.name, sublabel: c.phone }))
 *   }}
 * />
 * ```
 */
export default function AsyncCombobox({
  label,
  placeholder = 'ابحث...',
  value,
  onChange,
  loadOptions,
  error,
  hint,
  required,
  disabled,
  className = '',
  noOptionsText = 'لا توجد نتائج',
  defaultOptions = [],
}: AsyncComboboxProps) {
  const id = useId()
  const listboxId = `${id}-listbox`
  const isMobile = useIsMobile()

  const [isOpen, setIsOpen] = useState(false)
  const [search, setSearch] = useState('')
  const debouncedSearch = useDebounce(search, 300)

  const [options, setOptions] = useState<ComboboxOption[]>(defaultOptions)
  const [isLoading, setIsLoading] = useState(false)
  const [selectedOption, setSelectedOption] = useState<ComboboxOption | null>(null)

  const containerRef = useRef<HTMLDivElement>(null)
  const searchRef = useRef<HTMLInputElement>(null)

  // ── Close on outside click (desktop only) ─────────────
  useEffect(() => {
    if (isMobile) return
    function handle(e: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false)
      }
    }
    document.addEventListener('mousedown', handle)
    return () => document.removeEventListener('mousedown', handle)
  }, [isMobile])

  // ── Load options on open / search change ──────────────
  const fetchOptions = useCallback(async () => {
    setIsLoading(true)
    try {
      const results = await loadOptions(debouncedSearch)
      setOptions(results)
      if (value) {
        const found = results.find(o => o.value === value)
        if (found) setSelectedOption(found)
      }
    } catch (err) {
      console.error('[AsyncCombobox] loadOptions error:', err)
    } finally {
      setIsLoading(false)
    }
  }, [debouncedSearch, loadOptions, value])

  useEffect(() => {
    if (!isOpen) return
    fetchOptions()
  }, [isOpen, fetchOptions])

  // ── Sync selectedOption when value prop changes ────────
  useEffect(() => {
    if (!value) { setSelectedOption(null); return }
    const found =
      options.find(o => o.value === value) ||
      defaultOptions.find(o => o.value === value)
    if (found) setSelectedOption(found)
  }, [value, options, defaultOptions])

  // ── Focus search on open ───────────────────────────────
  useEffect(() => {
    if (isOpen) {
      setTimeout(() => searchRef.current?.focus(), 50)
    }
  }, [isOpen])

  // ── Lock body scroll on mobile sheet ─────────────────
  useEffect(() => {
    if (isMobile && isOpen) document.body.style.overflow = 'hidden'
    return () => { if (isMobile) document.body.style.overflow = '' }
  }, [isMobile, isOpen])

  const open = () => { if (!disabled) { setSearch(''); setIsOpen(true) } }
  const close = () => { setSearch(''); setIsOpen(false) }

  const handleSelect = (option: ComboboxOption) => {
    setSelectedOption(option)
    onChange(option.value, option)
    close()
  }

  const handleClear = (e: React.MouseEvent) => {
    e.stopPropagation()
    setSelectedOption(null)
    onChange(null, null)
    setSearch('')
  }

  // ── Keyboard navigation (Escape) ──────────────────────
  useEffect(() => {
    if (!isOpen) return
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') close() }
    document.addEventListener('keydown', handler)
    return () => document.removeEventListener('keydown', handler)
  }, [isOpen])

  const listContent = (
    <>
      {/* Search input */}
      <div className="acb-search-row">
        <Search size={16} className="acb-search-icon" />
        <input
          ref={searchRef}
          type="text"
          inputMode="search"
          className="acb-search-input"
          placeholder="اكتب للبحث..."
          value={search}
          onChange={e => setSearch(e.target.value)}
          onClick={e => e.stopPropagation()}
          aria-label="بحث في الخيارات"
          autoComplete="off"
        />
        {isLoading && <Loader2 size={15} className="acb-loader" />}
      </div>

      {/* Options */}
      <ul
        id={listboxId}
        role="listbox"
        className="acb-options"
        aria-label={label || 'الخيارات'}
      >
        {isLoading && options.length === 0 ? (
          // Skeleton loading
          <>
            {[1, 2, 3].map(i => (
              <li key={i} className="acb-skeleton-row">
                <span className="skeleton acb-skeleton-label" />
                <span className="skeleton acb-skeleton-sub" />
              </li>
            ))}
          </>
        ) : options.length === 0 ? (
          <li className="acb-empty">{noOptionsText}</li>
        ) : (
          options.map(option => {
            const isSelected = option.value === value
            return (
              <li
                key={option.value}
                id={`${id}-opt-${option.value}`}
                role="option"
                aria-selected={isSelected}
                className={`acb-option ${isSelected ? 'acb-option--selected' : ''}`}
                onClick={() => handleSelect(option)}
              >
                <div className="acb-option-content">
                  <span className="acb-option-label">{option.label}</span>
                  {option.sublabel && (
                    <span className="acb-option-sublabel">{option.sublabel}</span>
                  )}
                </div>
                {isSelected && <Check size={15} className="acb-check" />}
              </li>
            )
          })
        )}
      </ul>
    </>
  )

  return (
    <div className={`form-group acb-wrapper ${className}`} ref={containerRef}>
      {label && (
        <label htmlFor={id} className={`form-label ${required ? 'required' : ''}`}>
          {label}
        </label>
      )}

      {/* ── Trigger Button ─────── */}
      <button
        id={id}
        type="button"
        className={`acb-trigger form-input ${error ? 'error' : ''} ${disabled ? 'acb-trigger--disabled' : ''}`}
        onClick={open}
        disabled={disabled}
        aria-haspopup="listbox"
        aria-expanded={isOpen}
        aria-controls={isOpen ? listboxId : undefined}
      >
        <span className={`acb-trigger-label ${!selectedOption ? 'acb-trigger-label--placeholder' : ''}`}>
          {selectedOption ? selectedOption.label : placeholder}
        </span>
        <span className="acb-trigger-actions">
          {selectedOption && !disabled && (
            <span
              className="acb-clear"
              role="button"
              tabIndex={0}
              aria-label="مسح الاختيار"
              onClick={handleClear}
              onKeyDown={e => e.key === 'Enter' && handleClear(e as any)}
            >
              <X size={14} />
            </span>
          )}
          <ChevronsUpDown size={15} className="acb-chevron" />
        </span>
      </button>

      {error && <span className="form-error">{error}</span>}
      {hint && !error && <span className="form-hint">{hint}</span>}

      {/* ── Desktop Dropdown ─────── */}
      {!isMobile && isOpen && (
        <div className="acb-dropdown" role="presentation">
          {listContent}
        </div>
      )}

      {/* ── Mobile Bottom Sheet ──── */}
      {isMobile && isOpen && (
        <>
          <div
            className="acb-sheet-overlay"
            onClick={close}
            aria-hidden="true"
          />
          <div
            className="acb-sheet"
            role="dialog"
            aria-modal="true"
            aria-label={`اختيار ${label || ''}`}
          >
            <div className="acb-sheet-handle" aria-hidden="true" />
            <div className="acb-sheet-header">
              <span className="acb-sheet-title">{label || 'اختر'}</span>
              <button
                type="button"
                className="btn btn-ghost btn-icon"
                onClick={close}
                aria-label="إغلاق"
              >
                <X size={18} />
              </button>
            </div>
            {listContent}
          </div>
        </>
      )}

      <style>{`
        /* ── Trigger Button ─────────────────── */
        .acb-trigger {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--space-2);
          cursor: pointer;
          text-align: start;
          height: auto;
          min-height: 42px;
          padding: 0.5rem 0.875rem;
        }
        .acb-trigger--disabled { cursor: not-allowed; opacity: 0.55; }
        .acb-trigger-label {
          flex: 1;
          font-size: var(--text-sm);
          color: var(--text-primary);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .acb-trigger-label--placeholder { color: var(--text-muted); }
        .acb-trigger-actions {
          display: flex;
          align-items: center;
          gap: var(--space-1);
          flex-shrink: 0;
          color: var(--text-muted);
        }
        .acb-clear {
          display: flex; align-items: center; cursor: pointer;
          padding: 2px;
          border-radius: var(--radius-sm);
          color: var(--text-muted);
          transition: color var(--transition-fast);
        }
        .acb-clear:hover { color: var(--color-danger); }
        .acb-chevron { flex-shrink: 0; }

        /* ── Search row (shared) ────────────── */
        .acb-search-row {
          display: flex; align-items: center; gap: var(--space-2);
          padding: var(--space-2) var(--space-3);
          border-bottom: 1px solid var(--border-primary);
          background: var(--bg-surface-2);
        }
        .acb-search-icon { color: var(--text-muted); flex-shrink: 0; }
        .acb-search-input {
          flex: 1; border: none; outline: none;
          background: transparent;
          font-family: var(--font-sans);
          font-size: var(--text-sm);
          color: var(--text-primary);
        }
        .acb-search-input::placeholder { color: var(--text-muted); }
        .acb-loader {
          color: var(--color-primary);
          animation: spin 0.7s linear infinite;
          flex-shrink: 0;
        }

        /* ── Options list (shared) ───────────── */
        .acb-options {
          list-style: none; margin: 0; padding: 0;
          max-height: 240px;
          overflow-y: auto;
        }
        .acb-option {
          display: flex; align-items: center; justify-content: space-between;
          padding: var(--space-2) var(--space-3);
          cursor: pointer;
          transition: background var(--transition-fast);
          min-height: var(--touch-target);
        }
        .acb-option:hover { background: var(--bg-hover); }
        .acb-option--selected { background: var(--bg-active); }
        .acb-option-content { display: flex; flex-direction: column; gap: 2px; }
        .acb-option-label {
          font-size: var(--text-sm); font-weight: 500;
          color: var(--text-primary);
        }
        .acb-option--selected .acb-option-label { color: var(--color-primary); font-weight: 600; }
        .acb-option-sublabel { font-size: var(--text-xs); color: var(--text-muted); }
        .acb-check { color: var(--color-primary); flex-shrink: 0; }

        /* Skeleton */
        .acb-skeleton-row {
          padding: var(--space-3); display: flex; flex-direction: column; gap: 4px;
        }
        .acb-skeleton-label { height: 14px; width: 60%; }
        .acb-skeleton-sub { height: 10px; width: 35%; }

        /* Empty */
        .acb-empty {
          padding: var(--space-6) var(--space-3);
          text-align: center;
          font-size: var(--text-sm);
          color: var(--text-muted);
        }

        /* ── Desktop Dropdown ────────────────── */
        .acb-wrapper { position: relative; }
        .acb-dropdown {
          position: absolute;
          top: calc(100% + 4px);
          inset-inline-start: 0;
          inset-inline-end: 0;
          background: var(--bg-surface);
          border: 1.5px solid var(--border-primary);
          border-radius: var(--radius-md);
          box-shadow: var(--shadow-lg);
          z-index: var(--z-dropdown);
          overflow: hidden;
          animation: acb-fade-in 0.15s ease;
        }
        @keyframes acb-fade-in {
          from { opacity: 0; transform: translateY(-4px); }
          to   { opacity: 1; transform: translateY(0); }
        }

        /* ── Mobile Bottom Sheet ─────────────── */
        .acb-sheet-overlay {
          position: fixed; inset: 0;
          background: var(--overlay-bg);
          backdrop-filter: blur(3px);
          -webkit-backdrop-filter: blur(3px);
          z-index: var(--z-overlay);
          animation: acb-fade-in 0.2s ease;
        }
        .acb-sheet {
          position: fixed;
          bottom: 0; left: 0; right: 0;
          background: var(--bg-surface);
          border-radius: var(--sheet-radius);
          z-index: var(--z-sheet);
          max-height: 85dvh;
          display: flex; flex-direction: column;
          overflow: hidden;
          animation: acb-slide-up 0.3s cubic-bezier(0.32, 0.72, 0, 1);
          padding-bottom: env(safe-area-inset-bottom, 0px);
        }
        @keyframes acb-slide-up {
          from { transform: translateY(100%); }
          to   { transform: translateY(0); }
        }
        .acb-sheet-handle {
          width: 36px; height: 4px;
          background: var(--sheet-handle-color);
          border-radius: var(--radius-full);
          margin: var(--space-3) auto var(--space-1);
          flex-shrink: 0;
        }
        .acb-sheet-header {
          display: flex; align-items: center; justify-content: space-between;
          padding: 0 var(--space-4) var(--space-3);
          flex-shrink: 0;
        }
        .acb-sheet-title {
          font-size: var(--text-base); font-weight: 700; color: var(--text-primary);
        }
        .acb-sheet .acb-options { max-height: none; flex: 1; overflow-y: auto; }
        .acb-sheet .acb-option { min-height: 52px; }

        @keyframes spin {
          from { transform: rotate(0deg); }
          to   { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  )
}
