import { useState, useEffect, useRef } from 'react'
import { toast } from 'sonner'
import { Save, Settings, Loader2 } from 'lucide-react'
import { getSettings, updateSettings } from '@/lib/services/settings'
import type { CompanySetting } from '@/lib/types/auth'
import { useAuthStore } from '@/stores/auth-store'

const CATEGORY_LABELS: Record<string, string> = {
  company: '🏢 بيانات الشركة',
  finance: '💰 الإعدادات المالية',
  sales: '🛒 المبيعات',
  purchases: '📦 المشتريات',
  inventory: '📦 المخزون',
  hr: '👥 الموارد البشرية',
  notifications: '🔔 الإشعارات',
}

export default function CompanySettingsPage() {
  const can = useAuthStore(s => s.can)
  const [settings, setSettings] = useState<CompanySetting[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [activeTab, setActiveTab] = useState('company')
  const changedRef = useRef<Map<string, string>>(new Map())

  useEffect(() => {
    getSettings().then(data => {
      setSettings(data)
      setLoading(false)
    }).catch(() => toast.error('فشل تحميل الإعدادات'))
  }, [])

  const categories = [...new Set(settings.map(s => s.category))]
  const filtered = settings.filter(s => s.category === activeTab)

  const handleChange = (key: string, value: string) => {
    changedRef.current.set(key, value)
    setSettings(prev => prev.map(s => s.key === key ? { ...s, value } : s))
  }

  const handleSave = async () => {
    if (changedRef.current.size === 0) { toast.info('لم تتغير أي قيمة'); return }
    setSaving(true)
    try {
      await updateSettings(Array.from(changedRef.current.entries()).map(([key, value]) => ({ key, value })))
      changedRef.current.clear()
      toast.success('تم حفظ الإعدادات')
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'فشل الحفظ')
    } finally { setSaving(false) }
  }

  const renderInput = (setting: CompanySetting) => {
    const canUpdate = can('settings.update')

    if (setting.type === 'boolean') {
      return (
        <label className="toggle">
          <input type="checkbox" checked={setting.value === 'true'}
            onChange={e => handleChange(setting.key, String(e.target.checked))}
            disabled={!canUpdate} />
          <span className="toggle-slider" />
        </label>
      )
    }
    if (setting.type === 'number') {
      return (
        <input type="number" className="form-input" value={setting.value} dir="ltr"
          onChange={e => handleChange(setting.key, e.target.value)}
          disabled={!canUpdate}
          style={{ maxWidth: 150 }} />
      )
    }
    if (setting.type === 'json') {
      return (
        <input className="form-input" value={setting.value} dir="ltr"
          onChange={e => handleChange(setting.key, e.target.value)}
          disabled={!canUpdate}
          style={{ maxWidth: 250, fontFamily: 'monospace' }} />
      )
    }
    return (
      <input className="form-input" value={setting.value}
        onChange={e => handleChange(setting.key, e.target.value)}
        disabled={!canUpdate} />
    )
  }

  if (loading) {
    return (
      <div className="page-container">
        {[1,2,3,4,5,6].map(i => <div key={i} className="skeleton" style={{ height: 48, marginBottom: 12 }} />)}
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">
      <div className="page-header">
        <div className="page-header-info">
          <h1 className="page-title">إعدادات الشركة</h1>
          <p className="page-subtitle">تكوين وتخصيص النظام</p>
        </div>
        {can('settings.update') && (
          <button className="btn btn-primary" onClick={handleSave} disabled={saving}>
            {saving ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />}
            حفظ التغييرات
            {changedRef.current.size > 0 && (
              <span className="badge badge-danger" style={{ marginRight: 'var(--space-2)' }}>
                {changedRef.current.size}
              </span>
            )}
          </button>
        )}
      </div>

      {/* Tabs */}
      <div className="tabs">
        {categories.map(cat => (
          <button key={cat} className={`tab ${activeTab === cat ? 'active' : ''}`}
            onClick={() => setActiveTab(cat)}>
            {CATEGORY_LABELS[cat] || cat}
          </button>
        ))}
      </div>

      {/* Settings */}
      <div className="edara-card" style={{ overflow: 'hidden' }}>
        {/* Desktop table view */}
        <table className="data-table settings-table-desktop">
          <thead>
            <tr>
              <th style={{ width: '40%' }}>الإعداد</th>
              <th>القيمة</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map(setting => (
              <tr key={setting.key}>
                <td>
                  <div>
                    <span style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{setting.description}</span>
                    <span style={{
                      display: 'block', fontSize: 'var(--text-xs)',
                      color: 'var(--text-muted)', fontFamily: 'monospace', direction: 'ltr'
                    }}>
                      {setting.key}
                    </span>
                  </div>
                </td>
                <td>{renderInput(setting)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {/* Mobile list view */}
        <div className="settings-list">
          {filtered.map(setting => (
            <div key={setting.key} className="settings-list-item">
              <div className="settings-list-label">{setting.description}</div>
              <span className="settings-list-key">{setting.key}</span>
              {renderInput(setting)}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
