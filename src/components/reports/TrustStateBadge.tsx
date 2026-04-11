import { ShieldCheck, AlertTriangle, XCircle, RefreshCw, CheckCircle2, HelpCircle } from 'lucide-react'
import type { ElementType } from 'react'

interface Props {
  status: string | null  // accepts raw RPC-returned string; cfg lookup guards unknown values
  /** 'treasury' changes the VERIFIED wording */
  domain?: 'treasury' | 'sales' | 'ar' | 'customers' | 'profit_overview' | 'branch_profitability' | 'allocation_quality' | 'default'
  size?: 'sm' | 'md'
}

type CfgEntry = { icon: ElementType; label: string; colorVar: string; bgVar: string }

const CFG: Record<string, CfgEntry> = {
  VERIFIED: {
    icon: ShieldCheck,
    label: 'موثق ومطابق',   // overridden per domain below
    colorVar: 'var(--color-success)',
    bgVar: 'var(--color-success-light)',
  },
  POSTING_CONSISTENCY_ONLY: {
    icon: CheckCircle2,
    label: 'متسق دفترياً',
    colorVar: 'var(--color-info)',
    bgVar: 'var(--color-info-light)',
  },
  RECONCILED_WITH_WARNING: {
    icon: AlertTriangle,
    label: 'موثق مع تنبيه',
    colorVar: 'var(--color-warning)',
    bgVar: 'var(--color-warning-light)',
  },
  BLOCKED: {
    icon: XCircle,
    label: 'محجوب — جارٍ المطابقة',
    colorVar: 'var(--color-danger)',
    bgVar: 'var(--color-danger-light)',
  },
  RUNNING: {
    icon: RefreshCw,
    label: 'جارٍ التحديث',
    colorVar: 'var(--color-warning)',
    bgVar: 'var(--color-warning-light)',
  },
  FAILED: {
    icon: XCircle,
    label: 'فشل التحديث',
    colorVar: 'var(--color-danger)',
    bgVar: 'var(--color-danger-light)',
  },
  PARTIAL_FAILURE: {
    icon: AlertTriangle,
    label: 'تحديث جزئي',
    colorVar: 'var(--color-warning)',
    bgVar: 'var(--color-warning-light)',
  },
  NOT_DEPLOYED: {
    icon: HelpCircle,
    label: 'المحرك غير منشور',
    colorVar: 'var(--text-muted)',
    bgVar: 'var(--bg-surface-2)',
  },
}

export default function TrustStateBadge({ status, domain = 'default', size = 'md' }: Props) {
  if (!status) return null

  const isSm = size === 'sm'
  const c: CfgEntry = CFG[status] ?? {
    icon: HelpCircle,
    label: status,
    colorVar: 'var(--text-muted)',
    bgVar: 'var(--bg-surface-2)',
  }

  const label =
    status === 'VERIFIED' && domain === 'treasury'
      ? 'مطابق لسجلات الخزينة'
      : c.label

  const Icon = c.icon

  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: isSm ? '4px' : '5px',
        padding: isSm ? '2px 7px' : '3px 10px',
        borderRadius: '9999px',
        fontSize: isSm ? '10px' : '11.5px',
        fontWeight: 600,
        color: c.colorVar,
        background: c.bgVar,
        whiteSpace: 'nowrap',
      }}
    >
      <Icon size={isSm ? 10 : 12} strokeWidth={2.5} />
      {label}
    </span>
  )
}
