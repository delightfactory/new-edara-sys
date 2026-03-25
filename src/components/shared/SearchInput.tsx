import { useState, useCallback, useEffect, useRef } from 'react'
import { Search, X } from 'lucide-react'

interface SearchInputProps {
  value?: string
  onChange: (value: string) => void
  placeholder?: string
  debounceMs?: number
  className?: string
}

/**
 * SearchInput — حقل بحث مع debounce مدمج
 * يؤخر إرسال القيمة حتى يتوقف المستخدم عن الكتابة
 */
export default function SearchInput({
  value: externalValue,
  onChange,
  placeholder = 'بحث...',
  debounceMs = 300,
  className,
}: SearchInputProps) {
  const [localValue, setLocalValue] = useState(externalValue || '')
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // مزامنة القيمة الخارجية عند تغييرها
  useEffect(() => {
    if (externalValue !== undefined && externalValue !== localValue) {
      setLocalValue(externalValue)
    }
  }, [externalValue])

  const debouncedOnChange = useCallback(
    (val: string) => {
      if (timerRef.current) clearTimeout(timerRef.current)
      timerRef.current = setTimeout(() => onChange(val), debounceMs)
    },
    [onChange, debounceMs]
  )

  // تنظيف عند unmount
  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
    }
  }, [])

  const handleChange = (val: string) => {
    setLocalValue(val)
    debouncedOnChange(val)
  }

  const handleClear = () => {
    setLocalValue('')
    onChange('')
  }

  return (
    <div className={`search-input-wrapper ${className || ''}`} style={{ position: 'relative' }}>
      <Search size={16} className="search-icon" />
      <input
        className="form-input search-input"
        placeholder={placeholder}
        value={localValue}
        onChange={e => handleChange(e.target.value)}
      />
      {localValue && (
        <button
          type="button"
          onClick={handleClear}
          style={{
            position: 'absolute', insetInlineEnd: 8, top: '50%', transform: 'translateY(-50%)',
            background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)',
            padding: 4, display: 'flex', borderRadius: 'var(--radius-sm)',
          }}
        >
          <X size={14} />
        </button>
      )}
    </div>
  )
}
