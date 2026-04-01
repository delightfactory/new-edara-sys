import { useState, useEffect, useRef } from 'react'
import { Clock } from 'lucide-react'

interface VisitTimerProps {
  /** وقت البدء (ISO string أو Date) */
  startTime: string | Date | null
  /** هل المؤقت يعمل? */
  isRunning: boolean
  /** حجم المؤقت */
  size?: 'sm' | 'md' | 'lg'
}

/**
 * VisitTimer — مؤقت تصاعدي لمدة الزيارة/المكالمة
 *
 * يعرض الوقت المستغرق منذ startTime بشكل:
 * - 00:00 → 00:00 (دقائق:ثوانٍ) إذا < ساعة
 * - 1:00:00 (ساعة:دقائق:ثوانٍ) إذا > ساعة
 */
export default function VisitTimer({
  startTime,
  isRunning,
  size = 'md',
}: VisitTimerProps) {
  const [elapsed, setElapsed] = useState(0)
  const intervalRef = useRef<ReturnType<typeof setInterval>>()

  useEffect(() => {
    if (!isRunning || !startTime) {
      if (intervalRef.current) clearInterval(intervalRef.current)
      return
    }

    const start = typeof startTime === 'string' ? new Date(startTime) : startTime
    const startMs = start.getTime()

    // حساب أولي
    setElapsed(Math.max(0, Math.floor((Date.now() - startMs) / 1000)))

    // تحديث كل ثانية
    intervalRef.current = setInterval(() => {
      setElapsed(Math.max(0, Math.floor((Date.now() - startMs) / 1000)))
    }, 1000)

    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current)
    }
  }, [isRunning, startTime])

  const hours = Math.floor(elapsed / 3600)
  const minutes = Math.floor((elapsed % 3600) / 60)
  const seconds = elapsed % 60

  const pad = (n: number) => n.toString().padStart(2, '0')

  const display = hours > 0
    ? `${hours}:${pad(minutes)}:${pad(seconds)}`
    : `${pad(minutes)}:${pad(seconds)}`

  const sizeClass = `vt--${size}`

  return (
    <div className={`vt ${sizeClass} ${isRunning ? 'vt--active' : ''}`}>
      <Clock size={size === 'sm' ? 12 : size === 'lg' ? 20 : 16} />
      <span className="vt-time">{display}</span>

      <style>{`
        .vt {
          display: inline-flex;
          align-items: center;
          gap: var(--space-2, 8px);
          font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
          color: var(--text-muted, #64748b);
          font-weight: 600;
          letter-spacing: 0.5px;
        }
        .vt--active {
          color: var(--color-primary, #2563eb);
        }
        .vt--active .vt-time {
          animation: vt-pulse 2s ease-in-out infinite;
        }
        .vt--sm { font-size: var(--text-xs, 12px); }
        .vt--md { font-size: var(--text-base, 15px); }
        .vt--lg { font-size: var(--text-xl, 20px); }
        @keyframes vt-pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.7; }
        }
      `}</style>
    </div>
  )
}

export type { VisitTimerProps }
