import React, { useState, useEffect } from 'react'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'
import { useAdjustTargetBatch } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { toast } from 'sonner'
import type { TargetRewardSummary } from '@/lib/types/activities'
import { AlertCircle, Lock } from 'lucide-react'
import {
  allowsPercentageReward,
  validateRewardConfig,
  type RewardType,
  type PoolBasis,
} from '@/lib/utils/rewardRules'

interface TargetRewardEditModalProps {
  targetId:     string
  summary:      TargetRewardSummary | null
  open:         boolean
  onClose:      () => void
  /** نوع الهدف — إلزامي لقواعد pool_basis */
  typeCode:     string
  /** تصنيف الهدف — إلزامي لقواعد percentage */
  typeCategory: string
}

export default function TargetRewardEditModal({
  targetId, summary, open, onClose, typeCode, typeCategory,
}: TargetRewardEditModalProps) {
  const [rewardType,       setRewardType]       = useState<RewardType>(summary?.reward_type as RewardType || '')
  const [rewardBaseValue,  setRewardBaseValue]  = useState(summary?.reward_base_value?.toString() || '')
  const [rewardPoolBasis,  setRewardPoolBasis]  = useState<PoolBasis>(summary?.reward_pool_basis as PoolBasis || '')
  const [autoPayout,       setAutoPayout]       = useState(summary?.auto_payout ?? false)
  const [payoutMonthOffset, setPayoutMonthOffset] = useState(summary?.payout_month_offset?.toString() || '0')
  const [reason,           setReason]           = useState('')

  const adjustBatch = useAdjustTargetBatch()
  const isLocked    = summary?.is_payout_locked
  const currentUserId = useAuthStore(s => s.profile?.id) ?? ''

  // ── القواعد المستنتجة من helper ────────────────────────────
  const canPercentage  = allowsPercentageReward(typeCategory, typeCode)
  // pool_basis مثبَّت حسب النوع: collection → collection_value، كل الباقي → sales_value
  const lockedBasis: PoolBasis = typeCode === 'collection' ? 'collection_value' : 'sales_value'

  // Sync state when summary changes
  useEffect(() => {
    if (open && summary) {
      setRewardType((summary.reward_type as RewardType) || '')
      setRewardBaseValue(summary.reward_base_value?.toString() || '')
      setRewardPoolBasis((summary.reward_pool_basis as PoolBasis) || '')
      setAutoPayout(summary.auto_payout ?? false)
      setPayoutMonthOffset(summary.payout_month_offset?.toString() || '0')
      setReason('')
    }
  }, [open, summary])

  // عند تغيير rewardType، نُزامن pool_basis تلقائياً
  const handleRewardTypeChange = (rt: RewardType) => {
    setRewardType(rt)
    if (!rt || rt === 'fixed') {
      setRewardPoolBasis('')
    } else if (rt === 'percentage') {
      setRewardPoolBasis(lockedBasis)
    }
  }

  // تحقق صلاحية التركيبة الحالية
  const configError = validateRewardConfig(
    typeCategory, typeCode,
    rewardType || null,
    rewardPoolBasis || null
  )

  const handleSave = async () => {
    if (!reason.trim()) {
      toast.error('سبب التعديل إلزامي')
      return
    }

    // تحقق frontend قبل الإرسال
    if (configError) {
      toast.error(configError)
      return
    }

    const fields: Record<string, any> = {}

    // Always editable
    if (autoPayout !== summary?.auto_payout) fields.auto_payout = autoPayout
    if (parseInt(payoutMonthOffset || '0') !== summary?.payout_month_offset) {
      fields.payout_month_offset = parseInt(payoutMonthOffset || '0')
    }

    // Editable only if not locked
    if (!isLocked) {
      const newType  = rewardType === '' ? null : rewardType
      const newBase  = rewardBaseValue === '' ? null : parseFloat(rewardBaseValue)
      const newBasis = rewardPoolBasis === '' ? null : rewardPoolBasis

      if (newType  !== summary?.reward_type)         fields.reward_type       = newType
      if (newBase  !== summary?.reward_base_value)   fields.reward_base_value = newBase
      if (newBasis !== summary?.reward_pool_basis)   fields.reward_pool_basis = newBasis
    }

    if (Object.keys(fields).length === 0) {
      toast.info('لم تقم بأي تعديلات')
      onClose()
      return
    }

    try {
      adjustBatch.mutate({ targetId, fields, reason, userId: currentUserId }, {
        onSuccess: () => {
          toast.success('تم تحديث إعدادات المكافأة بنجاح')
          onClose()
        },
        onError: (err: any) => {
          toast.error(err.message || 'حدث خطأ أثناء حفظ التعديلات')
        },
      })
    } catch {
      toast.error('تعذر جلب بيانات المستخدم')
    }
  }

  const processing = adjustBatch.isPending

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      title="تعديل إعدادات المكافأة"
      disableOverlayClose={processing}
      footer={<>
        <Button variant="secondary" onClick={onClose} disabled={processing}>إلغاء</Button>
        <Button onClick={handleSave} disabled={processing || !reason.trim() || !!configError}>
          {processing ? 'جاري الحفظ...' : 'حفظ التعديلات'}
        </Button>
      </>}
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>

        {isLocked && (
          <div style={{
            background: 'var(--color-warning-light)',
            border: '1px solid var(--color-warning)',
            padding: '12px 16px', borderRadius: '8px',
            display: 'flex', alignItems: 'center', gap: '8px',
            color: 'var(--color-warning)', fontSize: '13px', fontWeight: 600,
          }}>
            <AlertCircle size={16} />
            لا يمكن تعديل المبالغ أو النسب لأن هناك مكافآت صُرفت مسبقاً لهذا الهدف.
          </div>
        )}

        {/* إشعار بأن الأهداف غير المالية لا تدعم percentage */}
        {!canPercentage && (
          <div style={{
            background: 'var(--bg-surface-2)', border: '1px solid var(--border-primary)',
            padding: '10px 14px', borderRadius: '8px',
            display: 'flex', alignItems: 'center', gap: '8px',
            fontSize: '13px', color: 'var(--text-muted)',
          }}>
            <Lock size={14} /> هذا النوع من الأهداف يدعم المكافأة المقطوعة فقط
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
          <div className="form-group">
            <label className="form-label">نوع المكافأة</label>
            <select
              className="form-select"
              value={rewardType}
              onChange={e => handleRewardTypeChange(e.target.value as RewardType)}
              disabled={isLocked || processing}
            >
              <option value="">بدون مكافأة (إلغاء)</option>
              <option value="fixed">مقطوعة (Fixed)</option>
              {canPercentage && <option value="percentage">نسبة (Percentage)</option>}
            </select>
          </div>

          <div className="form-group">
            <label className="form-label">القيمة أو النسبة الأساسية</label>
            <input
              type="number"
              className="form-input"
              value={rewardBaseValue}
              onChange={e => setRewardBaseValue(e.target.value)}
              disabled={isLocked || processing || rewardType === ''}
              min={0}
              placeholder="مثال: 5000 أو 2.5"
            />
          </div>
        </div>

        {/* وعاء الحساب — مثبَّت تلقائياً ومعروض كـ read-only */}
        {rewardType === 'percentage' && (
          <div className="form-group">
            <label className="form-label">وعاء الحساب</label>
            <div style={{
              padding: '9px 14px',
              background: 'var(--bg-surface-2)',
              border: '1px solid var(--border-primary)',
              borderRadius: '6px',
              fontSize: '13px',
              display: 'flex', alignItems: 'center', gap: '8px',
            }}>
              <Lock size={13} style={{ color: 'var(--text-muted)' }} />
              <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>
                {lockedBasis === 'collection_value' ? 'إجمالي التحصيلات' : 'إجمالي المبيعات'}
              </span>
              <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                محدد تلقائياً حسب نوع الهدف
              </span>
            </div>
          </div>
        )}

        {/* خطأ التحقق — يظهر فقط إذا كانت التركيبة غير صالحة */}
        {configError && (
          <div style={{
            background: 'var(--color-danger-light)',
            border: '1px solid var(--color-danger)',
            padding: '10px 14px', borderRadius: '8px',
            display: 'flex', alignItems: 'center', gap: '8px',
            fontSize: '13px', color: 'var(--color-danger)',
          }}>
            <AlertCircle size={14} /> {configError}
          </div>
        )}

        <div style={{ borderTop: '1px solid var(--border-color)', margin: '8px 0' }} />

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
          <div className="form-group" style={{ display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
            <label className="form-label" style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
              <input
                type="checkbox"
                checked={autoPayout}
                onChange={e => setAutoPayout(e.target.checked)}
                disabled={processing}
                style={{ width: '18px', height: '18px' }}
              />
              تفعيل الصرف التلقائي بمسير الرواتب
            </label>
          </div>

          <div className="form-group">
            <label className="form-label">التأخير الشهري للصرف</label>
            <select
              className="form-select"
              value={payoutMonthOffset}
              onChange={e => setPayoutMonthOffset(e.target.value)}
              disabled={processing}
            >
              <option value="0">نفس الشهر (Offset 0)</option>
              <option value="1">الشهر التالي (Offset 1)</option>
              <option value="2">بعد شهرين (Offset 2)</option>
            </select>
          </div>
        </div>

        <div className="form-group">
          <label className="form-label">سبب التعديل <span className="form-required">*</span></label>
          <textarea
            className="form-textarea"
            rows={2}
            value={reason}
            onChange={e => setReason(e.target.value)}
            disabled={processing}
            placeholder="اذكر سبب التعديل لأغراض التدقيق..."
          />
        </div>
      </div>
    </ResponsiveModal>
  )
}
