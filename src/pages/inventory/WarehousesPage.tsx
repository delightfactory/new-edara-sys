import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { Plus, Warehouse as WarehouseIcon, Edit, UserPlus, UserMinus } from 'lucide-react'
import { getWarehouses, createWarehouse, updateWarehouse, getWarehouseManagers, addWarehouseManager, removeWarehouseManager } from '@/lib/services/inventory'
import { getBranches } from '@/lib/services/geography'
import { useAuthStore } from '@/stores/auth-store'
import type { Warehouse, WarehouseType, WarehouseManager, Branch } from '@/lib/types/master-data'
import { formatDateShort } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import EmptyState from '@/components/shared/EmptyState'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Modal from '@/components/ui/Modal'
import ConfirmDialog from '@/components/ui/ConfirmDialog'

interface WhFormState {
  name: string
  type: WarehouseType
  branch_id: string | null
  address: string
  manager_id: string | null
}

export default function WarehousesPage() {
  const can = useAuthStore(s => s.can)
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [loading, setLoading] = useState(true)
  const [modal, setModal] = useState<{ open: boolean; editing?: Warehouse }>({ open: false })
  const [form, setForm] = useState<WhFormState>({ name: '', type: 'fixed', branch_id: null, address: '', manager_id: null })
  const [saving, setSaving] = useState(false)
  const [selectedWh, setSelectedWh] = useState<Warehouse | null>(null)
  const [managers, setManagers] = useState<WarehouseManager[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [profiles, setProfiles] = useState<{ id: string; full_name: string }[]>([])
  const [addManagerModal, setAddManagerModal] = useState(false)
  const [newManager, setNewManager] = useState({ profile_id: '', is_primary: false, can_approve_receipts: false })
  const [addingManager, setAddingManager] = useState(false)
  const [removeTarget, setRemoveTarget] = useState<WarehouseManager | null>(null)

  const load = async () => {
    setLoading(true)
    try { setWarehouses(await getWarehouses()) }
    catch { toast.error('فشل تحميل المخازن') }
    finally { setLoading(false) }
  }

  useEffect(() => {
    const init = async () => {
      const [brs] = await Promise.all([getBranches()])
      setBranches(brs)
      const { data } = await (await import('@/lib/supabase/client')).supabase
        .from('profiles').select('id, full_name').eq('status', 'active').order('full_name')
      if (data) setProfiles(data)
      await load()
    }
    init()
  }, [])

  const loadManagers = async (wh: Warehouse) => {
    setSelectedWh(wh)
    try { setManagers(await getWarehouseManagers(wh.id)) }
    catch { toast.error('فشل تحميل المديرين') }
  }

  const handleSave = async () => {
    if (!form.name.trim()) { toast.error('يرجى إدخال اسم المخزن'); return }
    setSaving(true)
    try {
      if (modal.editing) {
        await updateWarehouse(modal.editing.id, form)
        toast.success('تم التحديث')
      } else {
        await createWarehouse(form)
        toast.success('تم الإنشاء')
      }
      setModal({ open: false })
      load()
    } catch { toast.error('فشلت العملية') }
    finally { setSaving(false) }
  }

  const openCreate = () => { setForm({ name: '', type: 'fixed', branch_id: null, address: '', manager_id: null }); setModal({ open: true }) }
  const openEdit = (wh: Warehouse) => { setForm({ name: wh.name, type: wh.type, branch_id: wh.branch_id, address: wh.address || '', manager_id: wh.manager_id }); setModal({ open: true, editing: wh }) }

  const handleAddManager = async () => {
    if (!newManager.profile_id) { toast.error('يرجى اختيار المستخدم'); return }
    setAddingManager(true)
    try {
      await addWarehouseManager(selectedWh!.id, newManager.profile_id, { is_primary: newManager.is_primary, can_approve_receipts: newManager.can_approve_receipts })
      toast.success('تم إضافة المدير')
      setAddManagerModal(false)
      setManagers(await getWarehouseManagers(selectedWh!.id))
    } catch (e: any) { toast.error(e?.message?.includes('unique') ? 'هذا المستخدم معين بالفعل' : 'فشلت العملية') }
    finally { setAddingManager(false) }
  }

  const executeRemoveManager = async () => {
    if (!removeTarget) return
    try {
      await removeWarehouseManager(removeTarget.id)
      toast.success('تم الإزالة')
      if (selectedWh) setManagers(await getWarehouseManagers(selectedWh.id))
    } catch { toast.error('فشلت العملية') }
    finally { setRemoveTarget(null) }
  }

  const typeLabels: Record<string, { label: string; variant: 'primary' | 'info' | 'warning' }> = {
    fixed: { label: 'ثابت', variant: 'primary' },
    vehicle: { label: 'سيارة', variant: 'info' },
    retail: { label: 'تجزئة', variant: 'warning' },
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="المخازن"
        subtitle={loading ? '...' : `${warehouses.length} مخزن`}
        actions={can('inventory.create') ? (
          <Button icon={<Plus size={16} />} onClick={openCreate}>إضافة مخزن</Button>
        ) : undefined}
      />

      {loading ? (
        <div className="grid grid-3 gap-4">
          {[1,2,3].map(i => <div key={i} className="skeleton" style={{ height: 160, borderRadius: 'var(--radius-lg)' }} />)}
        </div>
      ) : warehouses.length === 0 ? (
        <div className="edara-card">
          <EmptyState
            icon={<WarehouseIcon size={48} />}
            title="لا يوجد مخازن"
            text="أضف المخازن لبدء إدارة المخزون"
            action={can('inventory.create') ? <Button icon={<Plus size={16} />} onClick={openCreate}>إضافة أول مخزن</Button> : undefined}
          />
        </div>
      ) : (
        <div className="grid grid-3 gap-4">
          {warehouses.map(wh => (
            <div key={wh.id} className="edara-card edara-card-interactive" style={{ padding: 'var(--space-5)' }}>
              <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-3)' }}>
                <div className="flex items-center gap-3">
                  <div style={{ width: 40, height: 40, borderRadius: 'var(--radius-md)', background: 'var(--color-primary-light)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <WarehouseIcon size={20} style={{ color: 'var(--color-primary)' }} />
                  </div>
                  <div>
                    <h3 style={{ fontWeight: 700, fontSize: 'var(--text-sm)' }}>{wh.name}</h3>
                    <Badge variant={typeLabels[wh.type]?.variant || 'neutral'}>{typeLabels[wh.type]?.label || wh.type}</Badge>
                  </div>
                </div>
                <Badge variant={wh.is_active ? 'success' : 'danger'}>{wh.is_active ? 'نشط' : 'معطل'}</Badge>
              </div>
              {wh.branch && <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>الفرع: {wh.branch.name}</p>}
              {wh.manager && <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>المدير: {wh.manager.full_name}</p>}
              {wh.address && <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 'var(--space-1)' }}>{wh.address}</p>}
              <div className="flex gap-2" style={{ borderTop: '1px solid var(--divider)', paddingTop: 'var(--space-3)', marginTop: 'var(--space-3)' }}>
                {can('inventory.create') && <Button variant="ghost" size="sm" onClick={() => openEdit(wh)}><Edit size={14} /> تعديل</Button>}
                {can('inventory.read') && <Button variant="ghost" size="sm" onClick={() => loadManagers(wh)}><UserPlus size={14} /> المديرون</Button>}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Managers detail */}
      {selectedWh && (
        <div className="edara-card" style={{ marginTop: 'var(--space-4)', padding: 'var(--space-6)' }}>
          <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-4)' }}>
            <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>مديرو مخزن: {selectedWh.name}</h2>
            <div className="flex gap-2">
              {can('inventory.create') && (
                <Button size="sm" icon={<UserPlus size={14} />} onClick={() => { setNewManager({ profile_id: '', is_primary: false, can_approve_receipts: false }); setAddManagerModal(true) }}>
                  إضافة مدير
                </Button>
              )}
              <Button variant="ghost" size="sm" onClick={() => setSelectedWh(null)}>✕ إغلاق</Button>
            </div>
          </div>
          {managers.length === 0 ? (
            <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-4)' }}>لا يوجد مديرون معينون</p>
          ) : (
            <table className="data-table">
              <thead><tr><th>المستخدم</th><th>أساسي</th><th>صلاحية استلام</th><th className="hide-mobile">تاريخ التعيين</th><th style={{ width: 60 }}></th></tr></thead>
              <tbody>
                {managers.map(m => (
                  <tr key={m.id}>
                    <td>{m.profile?.full_name || m.profile_id.substring(0, 8)}</td>
                    <td>{m.is_primary ? <Badge variant="primary">أساسي</Badge> : '—'}</td>
                    <td>{m.can_approve_receipts ? <Badge variant="success">نعم</Badge> : '—'}</td>
                    <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)' }}>{formatDateShort(m.created_at)}</td>
                    <td>
                      {can('inventory.create') && (
                        <Button variant="danger" size="sm" onClick={() => setRemoveTarget(m)}>
                          <UserMinus size={12} />
                        </Button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* Create/Edit Warehouse Modal */}
      <Modal open={modal.open} onClose={() => setModal({ open: false })} title={modal.editing ? 'تعديل مخزن' : 'مخزن جديد'} size="md"
        footer={
          <div className="flex gap-2 justify-end" style={{ width: '100%' }}>
            <Button variant="secondary" onClick={() => setModal({ open: false })}>إلغاء</Button>
            <Button onClick={handleSave} loading={saving}>{modal.editing ? 'تحديث' : 'إنشاء'}</Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div className="grid grid-2 gap-4">
            <div className="form-group">
              <label className="form-label required">اسم المخزن</label>
              <input className="form-input" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} autoFocus />
            </div>
            <div className="form-group">
              <label className="form-label">النوع</label>
              <select className="form-select" value={form.type} onChange={e => setForm(f => ({ ...f, type: e.target.value as WarehouseType }))}>
                <option value="fixed">ثابت</option>
                <option value="vehicle">سيارة</option>
                <option value="retail">تجزئة</option>
              </select>
            </div>
          </div>
          <div className="grid grid-2 gap-4">
            <div className="form-group">
              <label className="form-label">الفرع التابع</label>
              <select className="form-select" value={form.branch_id || ''} onChange={e => setForm(f => ({ ...f, branch_id: e.target.value || null }))}>
                <option value="">بدون فرع</option>
                {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label">المدير المسؤول</label>
              <select className="form-select" value={form.manager_id || ''} onChange={e => setForm(f => ({ ...f, manager_id: e.target.value || null }))}>
                <option value="">بدون مدير</option>
                {profiles.map(p => <option key={p.id} value={p.id}>{p.full_name}</option>)}
              </select>
            </div>
          </div>
          <div className="form-group">
            <label className="form-label">العنوان</label>
            <input className="form-input" value={form.address || ''} onChange={e => setForm(f => ({ ...f, address: e.target.value }))} />
          </div>
        </div>
      </Modal>

      {/* Add Manager Modal */}
      <Modal open={addManagerModal} onClose={() => setAddManagerModal(false)} title="إضافة مدير مخزن" size="sm"
        footer={
          <div className="flex gap-2 justify-end" style={{ width: '100%' }}>
            <Button variant="secondary" onClick={() => setAddManagerModal(false)}>إلغاء</Button>
            <Button onClick={handleAddManager} loading={addingManager}>إضافة</Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div className="form-group">
            <label className="form-label required">المستخدم</label>
            <select className="form-select" value={newManager.profile_id} onChange={e => setNewManager(f => ({ ...f, profile_id: e.target.value }))}>
              <option value="">اختر مستخدم</option>
              {profiles.map(p => <option key={p.id} value={p.id}>{p.full_name}</option>)}
            </select>
          </div>
          <label style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', cursor: 'pointer' }}>
            <input type="checkbox" checked={newManager.is_primary} onChange={e => setNewManager(f => ({ ...f, is_primary: e.target.checked }))} />
            مدير أساسي
          </label>
          <label style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', cursor: 'pointer' }}>
            <input type="checkbox" checked={newManager.can_approve_receipts} onChange={e => setNewManager(f => ({ ...f, can_approve_receipts: e.target.checked }))} />
            صلاحية اعتماد الاستلام
          </label>
        </div>
      </Modal>

      {/* Remove Manager Confirm */}
      <ConfirmDialog
        open={!!removeTarget}
        title="إزالة المدير"
        message={`هل تريد إزالة "${removeTarget?.profile?.full_name || ''}" من مديري المخزن؟`}
        variant="danger"
        confirmText="إزالة"
        onConfirm={executeRemoveManager}
        onCancel={() => setRemoveTarget(null)}
      />
    </div>
  )
}
