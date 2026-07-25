/**
 * VisitPlanItemEditor — محرر بند زيارة واحد داخل معالج إنشاء خطة الزيارات.
 *
 * المسؤوليات:
 * - عرض اسم العميل والكود والترتيب التسلسلي (header قابل للطي).
 * - اختيار الموقع: الرئيسي (null) + فروع العميل المحملة.
 * - شارة GPS توضيحية (للعرض فقط — لا ترسل إحداثيات للـRPC).
 * - حقول: الأولوية، الغرض، الوقت المخطط، المدة.
 * - أزرار التحريك والحذف.
 *
 * القيود:
 * - لا تبني حمولة RPC — فقط تحديث state المحلي في الوالد.
 * - لا ترسل latitude/longitude/expected_lat/expected_lng.
 * - touch targets ≥ 44px.
 * - font-weight ≤ 700.
 * - خصائص منطقية RTL فقط (لا margin-left/right).
 * - CSS variables حصراً — لا ألوان Hex/RGB مباشرة.
 */
import { useId, useEffect } from 'react'
import { ArrowUp, ArrowDown, Trash2, ChevronDown, Clock, MapPin, AlertTriangle, Loader2 } from 'lucide-react'
import { useCustomerBranches } from '@/hooks/useCustomerBranches'
import type { SelectedCustomer, PlanItemPurposeType, PlanPriority } from '../visitPlanFormTypes'
import { PRIORITY_OPTIONS, PURPOSE_OPTIONS } from '../visitPlanFormTypes'
import type { CustomerBranch } from '@/lib/types/master-data'

// ── Props ──────────────────────────────────────────────────────────────────────
interface VisitPlanItemEditorProps {
  customer: SelectedCustomer
  index: number
  total: number
  isLocked: boolean
  isExpanded: boolean
  onToggleExpand: (id: string) => void
  onMoveUp: (index: number) => void
  onMoveDown: (index: number) => void
  onRemove: (id: string) => void
  onUpdate: <K extends keyof SelectedCustomer>(id: string, field: K, value: SelectedCustomer[K]) => void
  onBranchSelectionChange: (
    customerId: string,
    branchId: string | null,
    branchName: string | null,
    resolved: boolean,
    hasCoordinates: boolean | null
  ) => void
}

// ── GPS Badge ─────────────────────────────────────────────────────────────────
interface GpsBadgeProps {
  customerBranchId: string | null
  customerLat: number | null
  customerLng: number | null
  customerBranchHasCoordinates: boolean | null
  isLoadingBranches: boolean
  isExpanded: boolean
  customerBranchResolved: boolean
}

function GpsBadge({
  customerBranchId,
  customerLat,
  customerLng,
  customerBranchHasCoordinates,
  isLoadingBranches,
  isExpanded,
  customerBranchResolved,
}: GpsBadgeProps) {
  // حالة 1: الموقع الرئيسي (null) — لا نحتاج تحميل الفروع
  if (customerBranchId === null) {
    const hasCoords = customerLat != null && customerLng != null
    return (
      <span className={`vpie-gps-badge ${hasCoords ? 'vpie-gps-badge--ok' : 'vpie-gps-badge--none'}`}>
        <MapPin size={11} aria-hidden="true" />
        {hasCoords ? 'موقع متاح' : 'لا توجد إحداثيات'}
      </span>
    )
  }

  // حالة 2: فرع مختار والتحميل جارٍ
  if (isExpanded && isLoadingBranches) {
    return (
      <span className="vpie-gps-badge vpie-gps-badge--loading">
        <Loader2 size={11} className="vpie-spin" aria-hidden="true" />
        جاري تحميل موقع الفرع
      </span>
    )
  }

  // حالة 3: فرع مفقود أو غير محلول بعد (عنده معرف فرع بس resolved=false)
  if (customerBranchResolved === false) {
    return (
      <span className="vpie-gps-badge vpie-gps-badge--warning">
        <AlertTriangle size={11} aria-hidden="true" />
        الفرع يحتاج تحققًا
      </span>
    )
  }

  // حالة 4: الفرع محدد وتم حله
  if (customerBranchHasCoordinates !== null) {
    return (
      <span className={`vpie-gps-badge ${customerBranchHasCoordinates ? 'vpie-gps-badge--ok' : 'vpie-gps-badge--none'}`}>
        <MapPin size={11} aria-hidden="true" />
        {customerBranchHasCoordinates ? 'موقع متاح' : 'لا توجد إحداثيات'}
      </span>
    )
  }

  // حالة 5: fallback
  return (
    <span className="vpie-gps-badge vpie-gps-badge--none">
      <MapPin size={11} aria-hidden="true" />
      فرع محدد
    </span>
  )
}

// ── Branch Warning ─────────────────────────────────────────────────────────────
interface BranchWarningProps {
  customerBranchId: string | null
  branches: CustomerBranch[]
  isLoading: boolean
  isError: boolean
  onResetToMain: () => void
  isLocked: boolean
}

function BranchWarning({
  customerBranchId,
  branches,
  isLoading,
  isError,
  onResetToMain,
  isLocked,
}: BranchWarningProps) {
  if (!customerBranchId || isLoading) return null

  if (isError) {
    return (
      <div className="vpie-branch-warning vpie-branch-warning--danger" role="alert">
        <AlertTriangle size={14} aria-hidden="true" />
        <span>تعذر تحميل فروع العميل</span>
        <button
          type="button"
          className="vpie-branch-reset-btn"
          onClick={onResetToMain}
          disabled={isLocked}
        >
          استخدام الموقع الرئيسي
        </button>
      </div>
    )
  }

  const branchExists = branches.find(b => b.id === customerBranchId)

  if (!branchExists) {
    return (
      <div className="vpie-branch-warning vpie-branch-warning--danger" role="alert">
        <AlertTriangle size={14} aria-hidden="true" />
        <span>الفرع المحفوظ لم يعد موجوداً</span>
        <button
          type="button"
          className="vpie-branch-reset-btn"
          onClick={onResetToMain}
          disabled={isLocked}
        >
          استخدام الموقع الرئيسي
        </button>
      </div>
    )
  }

  return null
}

// ── Main Component ─────────────────────────────────────────────────────────────
export default function VisitPlanItemEditor({
  customer,
  index,
  total,
  isLocked,
  isExpanded,
  onToggleExpand,
  onMoveUp,
  onMoveDown,
  onRemove,
  onUpdate,
  onBranchSelectionChange,
}: VisitPlanItemEditorProps) {
  const panelId = useId()
  const headerId = useId()

  // تحميل الفروع عند فتح البطاقة فقط
  const { branches, isLoading: branchesLoading, isError: branchesError } = useCustomerBranches({
    customerId: customer.customerId,
    enabled: isExpanded,
  })

  // حل فرع القالب تلقائياً عند فتح البطاقة واكتمال التحميل
  useEffect(() => {
    if (!isExpanded || branchesLoading || branchesError) return

    if (customer.customerBranchId) {
      const foundBranch = branches.find(b => b.id === customer.customerBranchId)
      if (foundBranch) {
        const hasCoords = foundBranch.latitude != null && foundBranch.longitude != null
        if (
          !customer.customerBranchResolved ||
          customer.customerBranchName !== foundBranch.name ||
          customer.customerBranchHasCoordinates !== hasCoords
        ) {
          onBranchSelectionChange(
            customer.customerId,
            customer.customerBranchId,
            foundBranch.name,
            true,
            hasCoords
          )
        }
      } else {
        // الفرع مفقود (لم يعد موجوداً)
        if (
          customer.customerBranchResolved !== false ||
          customer.customerBranchName !== null ||
          customer.customerBranchHasCoordinates !== null
        ) {
          onBranchSelectionChange(
            customer.customerId,
            customer.customerBranchId,
            null,
            false,
            null
          )
        }
      }
    }
  }, [
    isExpanded,
    branchesLoading,
    branchesError,
    branches,
    customer.customerId,
    customer.customerBranchId,
    customer.customerBranchResolved,
    customer.customerBranchName,
    customer.customerBranchHasCoordinates,
    onBranchSelectionChange,
  ])

  // تحديد إذا كان الفرع غير محلول ومفقود
  const branchIsInvalid = !!customer.customerBranchId && isExpanded && !branchesLoading && !branchesError && (
    !branches.find(b => b.id === customer.customerBranchId)
  )

  const handleBranchChange = (branchId: string) => {
    if (branchId === '') {
      // الموقع الرئيسي
      onBranchSelectionChange(
        customer.customerId,
        null,
        null,
        true,
        customer.latitude != null && customer.longitude != null
      )
    } else {
      const branch = branches.find(b => b.id === branchId)
      if (branch) {
        onBranchSelectionChange(
          customer.customerId,
          branchId,
          branch.name,
          true,
          branch.latitude != null && branch.longitude != null
        )
      }
    }
  }

  const handleResetToMain = () => {
    onBranchSelectionChange(
      customer.customerId,
      null,
      null,
      true,
      customer.latitude != null && customer.longitude != null
    )
  }

  // ملخص الموقع للعرض في الـ header المغلق
  const locationSummary = (() => {
    if (!customer.customerBranchId) return 'الموقع الرئيسي'
    if (customer.customerBranchResolved && customer.customerBranchName) return customer.customerBranchName
    return 'فرع محدد — جاري التحقق'
  })()

  const priorityLabel = PRIORITY_OPTIONS.find(p => p.value === customer.priority)?.label ?? 'عادية'
  const purposeLabel = PURPOSE_OPTIONS.find(p => p.value === customer.purposeType)?.label

  return (
    <div className={`vpie ${isExpanded ? 'vpie--expanded' : ''} ${branchIsInvalid ? 'vpie--invalid' : ''}`}>
      {/* ── Header (زر التوسعة) ── */}
      <button
        id={headerId}
        type="button"
        className="vpie-header"
        onClick={() => onToggleExpand(customer.customerId)}
        aria-expanded={isExpanded}
        aria-controls={panelId}
        disabled={isLocked}
      >
        {/* رقم التسلسل */}
        <span className="vpie-seq" aria-label={`الترتيب ${customer.sequence}`}>
          {customer.sequence}
        </span>

        {/* معلومات العميل */}
        <div className="vpie-summary">
          <span className="vpie-name">{customer.customerName}</span>
          <span className="vpie-code">{customer.customerCode}</span>
          {/* ملخص مختصر عند الإغلاق */}
          {!isExpanded && (
            <span className="vpie-summary-meta">
              {locationSummary}
              {' · '}
              {priorityLabel}
              {purposeLabel && ` · ${purposeLabel}`}
              {customer.plannedTime && ` · ${customer.plannedTime}`}
            </span>
          )}
        </div>

        {/* شارة GPS */}
        <GpsBadge
          customerBranchId={customer.customerBranchId}
          customerLat={customer.latitude}
          customerLng={customer.longitude}
          customerBranchHasCoordinates={customer.customerBranchHasCoordinates}
          isLoadingBranches={branchesLoading}
          isExpanded={isExpanded}
          customerBranchResolved={customer.customerBranchResolved}
        />

        {/* أيقونة التوسعة */}
        <ChevronDown
          size={16}
          className={`vpie-chevron ${isExpanded ? 'vpie-chevron--open' : ''}`}
          aria-hidden="true"
        />
      </button>

      {/* ── Panel التفاصيل ── */}
      {isExpanded && (
        <div
          id={panelId}
          role="region"
          aria-labelledby={headerId}
          className="vpie-panel"
        >
          {/* أزرار التحريك والحذف */}
          <div className="vpie-controls">
            <div className="vpie-move-group">
              <button
                type="button"
                className="vpie-ctrl-btn vpie-ctrl-btn--move"
                onClick={() => onMoveUp(index)}
                disabled={index === 0 || isLocked}
                aria-label={`تحريك ${customer.customerName} للأعلى`}
              >
                <ArrowUp size={14} aria-hidden="true" />
              </button>
              <button
                type="button"
                className="vpie-ctrl-btn vpie-ctrl-btn--move"
                onClick={() => onMoveDown(index)}
                disabled={index === total - 1 || isLocked}
                aria-label={`تحريك ${customer.customerName} للأسفل`}
              >
                <ArrowDown size={14} aria-hidden="true" />
              </button>
            </div>
            <button
              type="button"
              className="vpie-ctrl-btn vpie-ctrl-btn--delete"
              onClick={() => onRemove(customer.customerId)}
              disabled={isLocked}
              aria-label={`حذف ${customer.customerName} من الخطة`}
            >
              <Trash2 size={14} aria-hidden="true" />
              حذف البند
            </button>
          </div>

          {/* ── الموقع / الفرع ── */}
          <div className="vpie-field-group">
            <label className="vpie-label" htmlFor={`branch-${customer.customerId}`}>
              <MapPin size={13} aria-hidden="true" />
              موقع الزيارة
            </label>
            {branchesLoading ? (
              <div className="vpie-branch-loading">
                <Loader2 size={14} className="vpie-spin" aria-hidden="true" />
                جاري تحميل الفروع...
              </div>
            ) : branchesError ? (
              <div className="vpie-field-group">
                <select
                  id={`branch-${customer.customerId}`}
                  className="vpie-select"
                  value={customer.customerBranchId ?? ''}
                  onChange={e => handleBranchChange(e.target.value)}
                  disabled={isLocked}
                >
                  <option value="">الموقع الرئيسي للعميل</option>
                </select>
                <BranchWarning
                  customerBranchId={customer.customerBranchId}
                  branches={[]}
                  isLoading={false}
                  isError={true}
                  onResetToMain={handleResetToMain}
                  isLocked={isLocked}
                />
              </div>
            ) : (
              <>
                <select
                  id={`branch-${customer.customerId}`}
                  className="vpie-select"
                  value={customer.customerBranchId ?? ''}
                  onChange={e => handleBranchChange(e.target.value)}
                  disabled={isLocked}
                >
                  <option value="">الموقع الرئيسي للعميل</option>
                  {branches.map(branch => (
                    <option key={branch.id} value={branch.id}>
                      {branch.name}
                      {branch.is_primary ? ' (الرئيسي)' : ''}
                    </option>
                  ))}
                </select>

                {/* تحذير الفرع المفقود */}
                <BranchWarning
                  customerBranchId={customer.customerBranchId}
                  branches={branches}
                  isLoading={branchesLoading}
                  isError={false}
                  onResetToMain={handleResetToMain}
                  isLocked={isLocked}
                />
              </>
            )}
          </div>

          {/* ── شبكة الحقول ── */}
          <div className="vpie-fields-grid">
            {/* الأولوية */}
            <div className="vpie-field">
              <label className="vpie-label" htmlFor={`priority-${customer.customerId}`}>
                الأولوية
              </label>
              <select
                id={`priority-${customer.customerId}`}
                className="vpie-select"
                value={customer.priority}
                onChange={e => onUpdate(customer.customerId, 'priority', e.target.value as PlanPriority)}
                disabled={isLocked}
              >
                {PRIORITY_OPTIONS.map(p => (
                  <option key={p.value} value={p.value}>{p.label}</option>
                ))}
              </select>
            </div>

            {/* الغرض */}
            <div className="vpie-field">
              <label className="vpie-label" htmlFor={`purpose-${customer.customerId}`}>
                الغرض
              </label>
              <select
                id={`purpose-${customer.customerId}`}
                className="vpie-select"
                value={customer.purposeType}
                onChange={e => onUpdate(customer.customerId, 'purposeType', e.target.value as PlanItemPurposeType | '')}
                disabled={isLocked}
              >
                <option value="">— غير محدد —</option>
                {PURPOSE_OPTIONS.map(p => (
                  <option key={p.value} value={p.value}>{p.label}</option>
                ))}
              </select>
            </div>

            {/* الوقت المخطط */}
            <div className="vpie-field">
              <label className="vpie-label" htmlFor={`time-${customer.customerId}`}>
                <Clock size={12} aria-hidden="true" />
                الوقت
              </label>
              {/* dir=ltr لأن تنسيق الوقت HH:MM يبدأ من اليسار */}
              <input
                id={`time-${customer.customerId}`}
                type="time"
                className="vpie-input"
                value={customer.plannedTime}
                onChange={e => onUpdate(customer.customerId, 'plannedTime', e.target.value)}
                disabled={isLocked}
                dir="ltr"
              />
            </div>

            {/* المدة */}
            <div className="vpie-field">
              <label className="vpie-label" htmlFor={`dur-${customer.customerId}`}>
                المدة (د)
              </label>
              {/* dir=ltr لأن الأرقام تبدأ من اليسار */}
              <input
                id={`dur-${customer.customerId}`}
                type="number"
                className="vpie-input"
                value={customer.estimatedDuration}
                onChange={e => onUpdate(
                  customer.customerId,
                  'estimatedDuration',
                  Math.max(5, Math.min(480, Math.round(Number(e.target.value))))
                )}
                min={5}
                max={480}
                disabled={isLocked}
                dir="ltr"
                aria-label={`مدة الزيارة للعميل ${customer.customerName} بالدقائق`}
              />
            </div>
          </div>

          {/* ملاحظة الغرض (نص حر) */}
          <div className="vpie-field-group">
            <label className="vpie-label" htmlFor={`purpose-text-${customer.customerId}`}>
              تفاصيل الغرض (اختياري)
            </label>
            <input
              id={`purpose-text-${customer.customerId}`}
              type="text"
              className="vpie-input vpie-input--full"
              value={customer.purpose}
              onChange={e => onUpdate(customer.customerId, 'purpose', e.target.value)}
              placeholder="وصف إضافي للغرض من الزيارة..."
              disabled={isLocked}
            />
          </div>
        </div>
      )}

      {/* ── Styles ── */}
      <style>{ITEM_EDITOR_STYLES}</style>
    </div>
  )
}

// ── Scoped Styles ──────────────────────────────────────────────────────────────
const ITEM_EDITOR_STYLES = `
  .vpie {
    border: 1px solid var(--border-primary);
    border-radius: var(--radius-lg);
    background: var(--bg-surface);
    overflow: hidden;
    transition: box-shadow var(--transition-fast);
  }
  .vpie:hover {
    box-shadow: var(--shadow-sm);
  }
  .vpie--expanded {
    border-color: var(--color-primary);
    box-shadow: 0 0 0 2px var(--color-primary-light);
  }
  .vpie--invalid {
    border-color: var(--color-warning);
  }

  /* ── Header ── */
  .vpie-header {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    width: 100%;
    padding: var(--space-3) var(--space-4);
    background: var(--bg-surface-2);
    border: none;
    cursor: pointer;
    text-align: start;
    font-family: inherit;
    transition: background var(--transition-fast);
    min-height: 56px;
  }
  .vpie-header:hover:not(:disabled) {
    background: var(--bg-surface-3, var(--bg-surface-2));
  }
  .vpie-header:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: -2px;
  }
  .vpie-header:disabled {
    cursor: default;
    opacity: 0.7;
  }

  /* ── Seq badge ── */
  .vpie-seq {
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 28px;
    height: 28px;
    border-radius: var(--radius-full);
    background: var(--color-primary-light);
    color: var(--color-primary);
    font-size: var(--text-xs);
    font-weight: 700;
    flex-shrink: 0;
  }
  .vpie--expanded .vpie-seq {
    background: var(--color-primary);
    color: var(--text-inverse);
  }

  /* ── Summary ── */
  .vpie-summary {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
    text-align: start;
  }
  .vpie-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .vpie-code {
    font-size: var(--text-xs);
    color: var(--text-muted);
    font-family: monospace;
  }
  .vpie-summary-meta {
    font-size: var(--text-xs);
    color: var(--text-muted);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  /* ── GPS Badge ── */
  .vpie-gps-badge {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: 11px;
    font-weight: 500;
    padding: 2px 8px;
    border-radius: var(--radius-full);
    white-space: nowrap;
    flex-shrink: 0;
  }
  .vpie-gps-badge--ok {
    color: var(--color-success);
    background: var(--color-success-light);
  }
  .vpie-gps-badge--none {
    color: var(--text-muted);
    background: var(--bg-surface-2);
  }
  .vpie-gps-badge--loading {
    color: var(--color-info);
    background: var(--color-info-light);
  }
  .vpie-gps-badge--warning {
    color: var(--color-warning);
    background: var(--color-warning-light);
  }
  .vpie-gps-badge--pending {
    color: var(--text-muted);
    background: var(--bg-surface-2);
  }

  /* ── Chevron ── */
  .vpie-chevron {
    color: var(--text-muted);
    flex-shrink: 0;
    transition: transform var(--transition-fast);
  }
  .vpie-chevron--open {
    transform: rotate(180deg);
  }

  /* ── Panel ── */
  .vpie-panel {
    padding: var(--space-4);
    border-block-start: 1px solid var(--border-primary);
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  /* ── Controls row ── */
  .vpie-controls {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
  }
  .vpie-move-group {
    display: flex;
    gap: var(--space-1);
  }
  .vpie-ctrl-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-1);
    min-width: 44px;
    min-height: 44px;
    border: 1px solid var(--border-primary);
    border-radius: var(--radius-md);
    background: var(--bg-surface);
    color: var(--text-muted);
    cursor: pointer;
    font-family: inherit;
    font-size: var(--text-xs);
    font-weight: 600;
    transition: border-color var(--transition-fast), color var(--transition-fast), background-color var(--transition-fast);
    padding: 0 var(--space-2);
  }
  .vpie-ctrl-btn:hover:not(:disabled) {
    border-color: var(--color-primary);
    color: var(--color-primary);
    background: var(--color-primary-light);
  }
  .vpie-ctrl-btn:disabled {
    opacity: 0.35;
    cursor: default;
  }
  .vpie-ctrl-btn:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 1px;
  }
  .vpie-ctrl-btn--move {
    min-width: 44px;
    padding: 0;
  }
  .vpie-ctrl-btn--delete:hover:not(:disabled) {
    border-color: var(--color-danger);
    color: var(--color-danger);
    background: var(--color-danger-light);
  }

  /* ── Field group (full width) ── */
  .vpie-field-group {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  /* ── Fields grid ── */
  .vpie-fields-grid {
    display: grid;
    grid-template-columns: 1fr 1fr 1fr 1fr;
    gap: var(--space-3);
  }
  .vpie-field {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  /* ── Labels ── */
  .vpie-label {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--text-secondary);
    line-height: 1.7;
  }
  .vpie-label svg {
    color: var(--text-muted);
    flex-shrink: 0;
  }

  /* ── Inputs & Selects ── */
  .vpie-select,
  .vpie-input {
    width: 100%;
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--border-primary);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-family: inherit;
    background: var(--bg-surface);
    color: var(--text-primary);
    transition: border-color var(--transition-fast);
    min-height: 44px;
  }
  .vpie-select:focus,
  .vpie-input:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px var(--color-primary-light);
  }
  .vpie-select:disabled,
  .vpie-input:disabled {
    opacity: 0.6;
    cursor: default;
    background: var(--bg-surface-2);
  }
  .vpie-input--full {
    width: 100%;
  }

  /* ── Branch loading ── */
  .vpie-branch-loading {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    color: var(--text-muted);
    padding: var(--space-2) 0;
  }

  /* ── Branch warning ── */
  .vpie-branch-warning {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    font-size: var(--text-xs);
    font-weight: 600;
    background: var(--color-warning-light);
    color: var(--color-warning);
    flex-wrap: wrap;
  }
  .vpie-branch-warning--danger {
    background: var(--color-danger-light);
    color: var(--color-danger);
  }
  .vpie-branch-reset-btn {
    display: inline-flex;
    align-items: center;
    padding: 0 var(--space-3);
    border: 1px solid currentColor;
    border-radius: var(--radius-sm);
    background: transparent;
    color: inherit;
    cursor: pointer;
    font-family: inherit;
    font-size: var(--text-xs);
    font-weight: 600;
    transition: border-color var(--transition-fast), color var(--transition-fast), background-color var(--transition-fast);
    margin-inline-start: auto;
    min-height: 44px;
  }
  .vpie-branch-reset-btn:hover:not(:disabled) {
    background: currentColor;
    color: var(--bg-surface);
  }
  .vpie-branch-reset-btn:disabled {
    opacity: 0.5;
    cursor: default;
  }

  /* ── Spin animation ── */
  .vpie-spin {
    animation: vpie-spin-anim 1s linear infinite;
  }
  @keyframes vpie-spin-anim {
    to { transform: rotate(360deg); }
  }

  /* ── Responsive ── */
  @media (max-width: 640px) {
    .vpie-fields-grid {
      grid-template-columns: 1fr 1fr;
    }
    .vpie-header {
      min-height: 52px;
    }
  }
  @media (max-width: 400px) {
    .vpie-fields-grid {
      grid-template-columns: 1fr;
    }
  }
`
