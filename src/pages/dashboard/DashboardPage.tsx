import { useState, useEffect } from 'react'
import { useAuthStore } from '@/stores/auth-store'
import { supabase } from '@/lib/supabase/client'
import { Users, BoxesIcon, Warehouse, Package } from 'lucide-react'
import { formatNumber } from '@/lib/utils/format'

interface DashboardStat {
  label: string
  value: string
  icon: React.ElementType
  color: string
}

export default function DashboardPage() {
  const profile = useAuthStore(s => s.profile)
  const [stats, setStats] = useState<DashboardStat[]>([
    { label: 'العملاء النشطون', value: '...', icon: Users, color: 'var(--color-primary)' },
    { label: 'المنتجات', value: '...', icon: BoxesIcon, color: 'var(--color-success)' },
    { label: 'المخازن', value: '...', icon: Warehouse, color: 'var(--color-warning)' },
    { label: 'أصناف المخزون', value: '...', icon: Package, color: 'var(--color-info)' },
  ])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const loadStats = async () => {
      try {
        const [customersRes, productsRes, warehousesRes, stockRes] = await Promise.all([
          supabase.from('customers').select('id', { count: 'exact', head: true }).eq('is_active', true),
          supabase.from('products').select('id', { count: 'exact', head: true }).eq('is_active', true),
          supabase.from('warehouses').select('id', { count: 'exact', head: true }).eq('is_active', true),
          supabase.from('stock').select('id', { count: 'exact', head: true }),
        ])

        setStats([
          { label: 'العملاء النشطون', value: formatNumber(customersRes.count ?? 0), icon: Users, color: 'var(--color-primary)' },
          { label: 'المنتجات', value: formatNumber(productsRes.count ?? 0), icon: BoxesIcon, color: 'var(--color-success)' },
          { label: 'المخازن', value: formatNumber(warehousesRes.count ?? 0), icon: Warehouse, color: 'var(--color-warning)' },
          { label: 'أصناف المخزون', value: formatNumber(stockRes.count ?? 0), icon: Package, color: 'var(--color-info)' },
        ])
      } catch {
        // Silently fail — stats are non-critical
      } finally {
        setLoading(false)
      }
    }
    loadStats()
  }, [])

  return (
    <div className="page-container animate-enter">
      <div className="page-header">
        <div className="page-header-info">
          <h1 className="page-title">
            مرحباً، {profile?.full_name || 'مستخدم'} 👋
          </h1>
          <p className="page-subtitle">
            لوحة القيادة — نظرة عامة على النظام
          </p>
        </div>
      </div>

      <div className="grid grid-4 gap-4" style={{ marginBottom: 'var(--space-6)' }}>
        {stats.map((stat) => (
          <div key={stat.label} className="stat-card">
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <span className="stat-card-label">{stat.label}</span>
              <div style={{
                width: 36, height: 36, borderRadius: 'var(--radius-md)',
                background: `color-mix(in srgb, ${stat.color} 12%, transparent)`,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <stat.icon size={18} style={{ color: stat.color }} />
              </div>
            </div>
            {loading ? (
              <div className="skeleton" style={{ height: 32, width: '60%', marginTop: 'var(--space-2)' }} />
            ) : (
              <span className="stat-card-value" style={{ color: stat.color }}>{stat.value}</span>
            )}
          </div>
        ))}
      </div>

      <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center' }}>
        <p style={{ color: 'var(--text-secondary)', fontSize: 'var(--text-sm)' }}>
          🏗️ لوحة القيادة التفصيلية مع الرسوم البيانية ستُبنى في المرحلة 5 (التقارير)
        </p>
      </div>
    </div>
  )
}
