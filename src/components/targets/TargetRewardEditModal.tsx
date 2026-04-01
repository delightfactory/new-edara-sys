import React, { useState, useEffect } from 'react'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'
import { useAdjustTargetBatch } from '@/hooks/useQueryHooks'
import { supabase } from '@/lib/supabase/client'
import { toast } from 'sonner'
import type { TargetRewardSummary } from '@/lib/types/activities'
import { AlertCircle } from 'lucide-react'

interface TargetRewardEditModalProps {
  targetId: string
  summary: TargetRewardSummary | null
  open: boolean
  onClose: () => void
}

export default function TargetRewardEditModal({ targetId, summary, open, onClose }: TargetRewardEditModalProps) {
  const [rewardType, setRewardType] = useState<'fixed' | 'percentage' | ''>(summary?.reward_type || '')
  const [rewardBaseValue, setRewardBaseValue] = useState(summary?.reward_base_value?.toString() || '')
  const [rewardPoolBasis, setRewardPoolBasis] = useState(summary?.reward_pool_basis || '')
  const [autoPayout, setAutoPayout] = useState(summary?.auto_payout ?? false)
  const [payoutMonthOffset, setPayoutMonthOffset] = useState(summary?.payout_month_offset?.toString() || '0')
  const [reason, setReason] = useState('')

  const adjustBatch = useAdjustTargetBatch()
  const isLocked = summary?.is_payout_locked

  // Sync state when summary changes
  useEffect(() => {
    if (open && summary) {
      setRewardType(summary.reward_type || '')
      setRewardBaseValue(summary.reward_base_value?.toString() || '')
      setRewardPoolBasis(summary.reward_pool_basis || '')
      setAutoPayout(summary.auto_payout ?? false)
      setPayoutMonthOffset(summary.payout_month_offset?.toString() || '0')
      setReason('')
    }
  }, [open, summary])

  const handleSave = async () => {
    if (!reason.trim()) {
      toast.error('سبب التعديل إلزامي')
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
      if (rewardType !== summary?.reward_type) fields.reward_type = rewardType === '' ? null : rewardType
      if (parseFloat(rewardBaseValue || '0') !== summary?.reward_base_value) {
        fields.reward_base_value = rewardBaseValue === '' ? null : parseFloat(rewardBaseValue)
      }
      if (rewardPoolBasis !== summary?.reward_pool_basis) {
        fields.reward_pool_basis = rewardPoolBasis === '' ? null : rewardPoolBasis
      }
    }

    if (Object.keys(fields).length === 0) {
      toast.info('لم تقم بأي تعديلات')
      onClose()
      return
    }

    try {
      const { data: userData } = await supabase.auth.getUser()
      const userId = userData.user?.id ?? ''
      
      adjustBatch.mutate({ targetId, fields, reason, userId }, {
        onSuccess: () => {
          toast.success('تم تحديث إعدادات المكافأة بنجاح')
          onClose()
        },
        onError: (err: any) => {
          toast.error(err.message || 'حدث خطأ أثناء حفظ التعديلات')
        }
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
        <Button onClick={handleSave} disabled={processing || !reason.trim()}>
          {processing ? 'جاري الحفظ...' : 'حفظ التعديلات'}
        </Button>
      </>}
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
        {isLocked && (
          <div style={{
            background: 'var(--color-warning-light)',
            border: '1px solid var(--color-warning)',
            padding: '12px 16px',
            borderRadius: '8px',
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            color: 'var(--color-warning)',
            fontSize: '13px',
            fontWeight: 600
          }}>
            <AlertCircle size={16} />
            لا يمكن تعديل المبالغ أو النسب لأن هناك مكافآت صُرفت مسبقاً لهذا الهدف.
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
          <div className="form-group">
            <label className="form-label">نوع المكافأة</label>
            <select 
              className="form-select" 
              value={rewardType} 
              onChange={e => setRewardType(e.target.value as any)}
              disabled={isLocked || processing}
            >
              <option value="">بدون مكافأة (إلغاء)</option>
              <option value="fixed">مقطوعة (Fixed)</option>
              <option value="percentage">نسبة (Percentage)</option>
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

        {rewardType === 'percentage' && (
          <div className="form-group">
            <label className="form-label">وعاء الحساب</label>
            <select 
              className="form-select" 
              value={rewardPoolBasis} 
              onChange={e => setRewardPoolBasis(e.target.value)}
              disabled={isLocked || processing}
            >
              <option value="">اختر הوعاء...</option>
              <option value="sales_value">إجمالي المبيعات (Sales Value)</option>
              <option value="collection_value">إجمالي التحصيلات (Collection Value)</option>
            </select>
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
