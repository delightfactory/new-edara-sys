import { useState, useRef, useEffect } from 'react'
import { Check, ChevronsUpDown, Loader2, Search } from 'lucide-react'
import { cn } from '@/lib/utils/helpers'
import { useDebounce } from '@/hooks/useDebounce'

export interface ComboboxOption {
  value: string
  label: string
  [key: string]: any
}

interface AsyncComboboxProps {
  label?: string
  placeholder?: string
  value?: string | null
  onChange: (value: string | null, option?: ComboboxOption | null) => void
  loadOptions: (search: string) => Promise<ComboboxOption[]>
  error?: string
  hint?: string
  required?: boolean
  disabled?: boolean
  className?: string
  noOptionsText?: string
  defaultOptions?: ComboboxOption[]
}

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
  className,
  noOptionsText = 'لا توجد نتائج',
  defaultOptions = [],
}: AsyncComboboxProps) {
  const [isOpen, setIsOpen] = useState(false)
  const [search, setSearch] = useState('')
  const debouncedSearch = useDebounce(search, 300)
  
  const [options, setOptions] = useState<ComboboxOption[]>(defaultOptions)
  const [isLoading, setIsLoading] = useState(false)
  const [selectedOption, setSelectedOption] = useState<ComboboxOption | null>(null)
  
  const containerRef = useRef<HTMLDivElement>(null)

  // إغلاق القائمة عند النقر خارجها
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  // جلب الخيارات من الخادم
  useEffect(() => {
    if (!isOpen) return

    let isMounted = true
    setIsLoading(true)

    loadOptions(debouncedSearch)
      .then(results => {
        if (isMounted) {
          setOptions(results)
          // تحديث العنصر المُختار إذا كان ضمن النتائج
          if (value) {
            const found = results.find(o => o.value === value)
            if (found) setSelectedOption(found)
          }
        }
      })
      .catch(err => console.error('Error loading combobox options:', err))
      .finally(() => {
        if (isMounted) setIsLoading(false)
      })

    return () => { isMounted = false }
  }, [debouncedSearch, isOpen, loadOptions, value])

  // تعيين العنصر المُختار بناءً على القيمة الأولية (value prop)
  useEffect(() => {
    if (!value) {
      setSelectedOption(null)
      return
    }
    // إذا كان لدينا الخيار في القائمة الحالية أو الديفولت
    const found = options.find(o => o.value === value) || defaultOptions.find(o => o.value === value)
    if (found) {
      setSelectedOption(found)
    }
  }, [value, options, defaultOptions])

  const handleSelect = (option: ComboboxOption) => {
    setSelectedOption(option)
    onChange(option.value, option)
    setSearch('')
    setIsOpen(false)
  }

  const handleClear = (e: React.MouseEvent) => {
    e.stopPropagation()
    setSelectedOption(null)
    onChange(null, null)
    setSearch('')
  }

  return (
    <div className={cn("form-group relative", className)} ref={containerRef}>
      {label && (
        <label className={cn('form-label block mb-1.5', required && 'required')}>
          {label}
        </label>
      )}

      {/* Input / Display Button */}
      <div
        className={cn(
          "relative flex items-center justify-between w-full p-2.5 bg-white dark:bg-gray-800 border rounded-lg cursor-pointer transition-colors",
          error ? "border-red-500 ring-1 ring-red-500" : "border-gray-200 dark:border-gray-700 hover:border-brand-500",
          disabled && "opacity-60 cursor-not-allowed bg-gray-50 dark:bg-gray-900"
        )}
        onClick={() => !disabled && setIsOpen(!isOpen)}
      >
        <span className={cn("block truncate text-sm", !selectedOption && "text-gray-400")}>
          {selectedOption ? selectedOption.label : placeholder}
        </span>
        
        <div className="flex items-center gap-1 shrink-0">
          {selectedOption && !disabled && (
            <button
              type="button"
              className="p-1 text-gray-400 hover:text-red-500 transition-colors"
              onClick={handleClear}
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
              </svg>
            </button>
          )}
          <ChevronsUpDown className="w-4 h-4 text-gray-400" />
        </div>
      </div>

      {/* Dropdown Menu */}
      {isOpen && (
        <div className="absolute z-50 w-full mt-1 bg-white dark:bg-gray-800 border border-gray-100 dark:border-gray-700 rounded-xl shadow-xl overflow-hidden animate-in fade-in slide-in-from-top-2">
          
          {/* Search Input */}
          <div className="flex items-center gap-2 p-2 border-b border-gray-100 dark:border-gray-700 bg-gray-50/50 dark:bg-gray-900/50">
            <Search className="w-4 h-4 text-gray-400 shrink-0" />
            <input
              type="text"
              autoFocus
              placeholder="اكتب للبحث..."
              className="flex-1 w-full bg-transparent border-none text-sm focus:ring-0 p-1 text-gray-900 dark:text-gray-100 placeholder:text-gray-400 outline-none"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              onClick={(e) => e.stopPropagation()}
            />
            {isLoading && <Loader2 className="w-4 h-4 text-brand-500 animate-spin shrink-0" />}
          </div>

          {/* Options List */}
          <ul className="max-h-60 overflow-y-auto py-1 custom-scrollbar">
            {!isLoading && options.length === 0 ? (
              <li className="p-4 text-sm text-center text-gray-500">
                {noOptionsText}
              </li>
            ) : (
              options.map((option) => (
                <li
                  key={option.value}
                  className={cn(
                    "flex items-center justify-between px-3 py-2.5 text-sm cursor-pointer transition-colors",
                    option.value === value
                      ? "bg-brand-50 dark:bg-brand-500/10 text-brand-600 dark:text-brand-400 font-medium"
                      : "text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700/50"
                  )}
                  onClick={() => handleSelect(option)}
                >
                  <span className="truncate pr-2">{option.label}</span>
                  {option.value === value && (
                    <Check className="w-4 h-4 shrink-0 text-brand-500" />
                  )}
                </li>
              ))
            )}
          </ul>
        </div>
      )}

      {error && <span className="form-error block mt-1 text-xs text-red-500">{error}</span>}
      {hint && !error && <span className="form-hint block mt-1 text-xs text-gray-500">{hint}</span>}
    </div>
  )
}
