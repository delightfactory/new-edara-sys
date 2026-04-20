import React from 'react'
import type { TargetRewardSummary } from '@/lib/types/activities'

interface RewardConfigCardProps {
  summary: TargetRewardSummary | null
}

const REWARD_TYPE_LABELS: Record<string, string> = {
  fixed: 'مقطوعة (Fixed)',
  percentage: 'نسبة (Percentage)',
}

const POOL_BASIS_LABELS: Record<string, string> = {
  sales_value: 'إجمالي المبيعات',
  collection_value: 'إجمالي التحصيلات',
}

export default function RewardConfigCard({ summary }: RewardConfigCardProps) {
  if (!summary || !summary.reward_type) {
    return (
      <div style={{
        background: 'var(--bg-surface)', border: '1px solid var(--border-color)',
        borderRadius: '12px', padding: '24px', textAlign: 'center', color: 'var(--text-muted)'
      }}>
        لا توجد مكافآت مسجلة لهذا الهدف.
      </div>
    )
  }

  return (
    <div style={{
      background: 'var(--bg-surface)',
      border: '1px solid var(--border-color)',
      borderRadius: '12px',
      overflow: 'hidden'
    }}>
      <div style={{
        padding: '16px 20px',
        borderBottom: '1px solid var(--border-color)',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        background: 'var(--bg-body)'
      }}>
        <h3 style={{ margin: 0, fontSize: '15px', fontWeight: 600, color: 'var(--text-primary)' }}>
          إعدادات المكافأة
        </h3>
        {summary.is_payout_locked && (
          <span style={{ fontSize: '11px', background: 'var(--color-warning)', color: '#fff', padding: '2px 8px', borderRadius: '4px', fontWeight: 600 }} title="لا يمكن تعديل الإعدادات الأساسية بعد صرف أول مكافأة">
             مقفلة (تم الصرف)
          </span>
        )}
      </div>

      <div style={{ padding: '20px', display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '20px' }}>
        <div>
          <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '4px' }}>نوع المكافأة</div>
          <div style={{ fontSize: '14px', fontWeight: 600, color: 'var(--text-primary)' }}>
            {REWARD_TYPE_LABELS[summary.reward_type] || summary.reward_type}
          </div>
        </div>

        {summary.reward_base_value != null && (
          <div>
            <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '4px' }}>
              {summary.reward_type === 'fixed' ? 'الوعاء (القيمة المقطوعة)' : 'النسبة الأساسية'}
            </div>
            <div style={{ fontSize: '14px', fontWeight: 600, color: 'var(--text-primary)' }}>
              {summary.reward_type === 'fixed' 
                ? summary.reward_base_value.toLocaleString('en-US', { maximumFractionDigits: 1 })
                : `${summary.reward_base_value.toLocaleString('en-US', { maximumFractionDigits: 1 })}%`}
            </div>
          </div>
        )}

        {summary.reward_type === 'percentage' && summary.reward_pool_basis && (
          <div>
            <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '4px' }}>طريقة الحساب</div>
            <div style={{ fontSize: '14px', fontWeight: 600, color: 'var(--text-primary)' }}>
              {POOL_BASIS_LABELS[summary.reward_pool_basis] || summary.reward_pool_basis}
            </div>
          </div>
        )}

        <div>
           <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '4px' }}>الصرف التلقائي</div>
           <div style={{ fontSize: '14px', fontWeight: 600, color: 'var(--text-primary)' }}>
             {summary.auto_payout ? 'نعم (يُرحل للرواتب)' : 'لا (يتطلب موافقة)'}
           </div>
        </div>

        <div>
           <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '4px' }}>توقيت الصرف</div>
           <div style={{ fontSize: '14px', fontWeight: 600, color: 'var(--text-primary)' }}>
             {summary.payout_month_offset === 0 ? 'في نفس الشهر' : `بعد ${summary.payout_month_offset} شهر`}
           </div>
        </div>
      </div>
    </div>
  )
}
