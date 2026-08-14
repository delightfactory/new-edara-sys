import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link2, ListPlus, Network, RotateCcw, Trash2, XCircle } from 'lucide-react'
import { toast } from 'sonner'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import { supabase } from '@/lib/supabase/client'
import { useAuthStore } from '@/stores/auth-store'
import type { WorkItem } from '@/features/work/types'
import {
  addChecklistItem,
  addWorkDependency,
  addWorkLink,
  cancelWorkItem,
  findVisibleWorkItemByNumber,
  listWorkDependencies,
  listWorkLinks,
  removeWorkLink,
  reopenWorkItem,
  resolveWorkDependency,
  type WorkLinkEntityType,
} from '@/features/work/extensions-api'

const ENTITY_TYPES: Array<{ value: WorkLinkEntityType; label: string }> = [
  { value: 'customer', label: 'عميل' },
  { value: 'sales_order', label: 'أمر بيع' },
  { value: 'payment_receipt', label: 'إيصال تحصيل' },
  { value: 'supplier', label: 'مورد' },
  { value: 'purchase_invoice', label: 'فاتورة شراء' },
  { value: 'product', label: 'منتج' },
  { value: 'warehouse', label: 'مخزن' },
  { value: 'employee', label: 'موظف' },
  { value: 'activity', label: 'نشاط/زيارة منفذة' },
  { value: 'target', label: 'هدف' },
]

const ENTITY_LABELS = Object.fromEntries(ENTITY_TYPES.map(row => [row.value, row.label])) as Record<WorkLinkEntityType, string>

type ModalKind = 'cancel' | 'reopen' | 'checklist' | 'dependency' | 'link' | null

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value.trim())
}

export default function WorkDetailExtensions({ item }: { item: WorkItem }) {
  const queryClient = useQueryClient()
  const profile = useAuthStore(s => s.profile)
  const can = useAuthStore(s => s.can)
  const [modal, setModal] = useState<ModalKind>(null)
  const [reason, setReason] = useState('')
  const [reopenNextAction, setReopenNextAction] = useState('')
  const [reopenNextAt, setReopenNextAt] = useState('')
  const [checklistLabel, setChecklistLabel] = useState('')
  const [checklistRequired, setChecklistRequired] = useState(true)
  const [blockerNumber, setBlockerNumber] = useState('')
  const [dependencyStrength, setDependencyStrength] = useState<'hard' | 'soft'>('hard')
  const [entityType, setEntityType] = useState<WorkLinkEntityType>('customer')
  const [entityId, setEntityId] = useState('')
  const [entityLabel, setEntityLabel] = useState('')

  const isOwner = item.accountable_owner_user_id === profile?.id
  const isAssignee = item.current_assignee_user_id === profile?.id
  const isTerminal = item.status === 'done' || item.status === 'cancelled'
  const canManage = isOwner || can('work.items.manage') || can('work.items.manage_team')
  const canEdit = !isTerminal && (isOwner || isAssignee || can('work.items.manage') || can('work.items.manage_team'))

  const linksQuery = useQuery({
    queryKey: ['work', 'links', item.id],
    queryFn: () => listWorkLinks(item.id),
  })
  const dependenciesQuery = useQuery({
    queryKey: ['work', 'dependencies', item.id],
    queryFn: () => listWorkDependencies(item.id),
  })

  const invalidate = async () => {
    await queryClient.invalidateQueries({ queryKey: ['work'] })
  }

  useEffect(() => {
    const onChange = () => { void invalidate() }
    const channel = supabase
      .channel(`work-detail-${item.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'work_items', filter: `id=eq.${item.id}` }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'work_events', filter: `work_item_id=eq.${item.id}` }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'work_comments', filter: `work_item_id=eq.${item.id}` }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'work_checklist_items', filter: `work_item_id=eq.${item.id}` }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'work_attachments', filter: `work_item_id=eq.${item.id}` }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'work_links', filter: `work_item_id=eq.${item.id}` }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'work_dependencies', filter: `blocked_work_item_id=eq.${item.id}` }, onChange)
      .subscribe()

    return () => { void supabase.removeChannel(channel) }
  }, [item.id]) // eslint-disable-line react-hooks/exhaustive-deps

  const cancelMutation = useMutation({ mutationFn: cancelWorkItem, onSuccess: invalidate })
  const reopenMutation = useMutation({ mutationFn: reopenWorkItem, onSuccess: invalidate })
  const checklistMutation = useMutation({ mutationFn: addChecklistItem, onSuccess: invalidate })
  const linkMutation = useMutation({ mutationFn: addWorkLink, onSuccess: invalidate })
  const removeLinkMutation = useMutation({ mutationFn: removeWorkLink, onSuccess: invalidate })
  const dependencyMutation = useMutation({ mutationFn: addWorkDependency, onSuccess: invalidate })
  const resolveDependencyMutation = useMutation({ mutationFn: resolveWorkDependency, onSuccess: invalidate })

  const activeDependencies = useMemo(
    () => (dependenciesQuery.data ?? []).filter(row => !row.resolved_at),
    [dependenciesQuery.data],
  )
  const resolvedDependencies = useMemo(
    () => (dependenciesQuery.data ?? []).filter(row => row.resolved_at),
    [dependenciesQuery.data],
  )

  const closeModal = () => {
    setModal(null)
    setReason('')
  }

  const showError = (error: unknown) => toast.error(error instanceof Error ? error.message : 'تعذر تنفيذ العملية')

  const submitCancel = async () => {
    if (!reason.trim()) return toast.error('سبب الإلغاء مطلوب')
    try {
      await cancelMutation.mutateAsync({ workItemId: item.id, expectedVersion: item.state_version, reason: reason.trim() })
      toast.success('تم إلغاء العمل مع حفظ السبب في السجل')
      closeModal()
    } catch (error) { showError(error) }
  }

  const submitReopen = async () => {
    if (!reason.trim() || !reopenNextAction.trim()) return toast.error('سبب إعادة الفتح والإجراء التالي مطلوبان')
    try {
      await reopenMutation.mutateAsync({
        workItemId: item.id,
        expectedVersion: item.state_version,
        reason: reason.trim(),
        nextActionText: reopenNextAction.trim(),
        nextActionAt: reopenNextAt ? new Date(reopenNextAt).toISOString() : null,
      })
      toast.success('تمت إعادة فتح العمل')
      setReopenNextAction('')
      setReopenNextAt('')
      closeModal()
    } catch (error) { showError(error) }
  }

  const submitChecklist = async () => {
    if (!checklistLabel.trim()) return toast.error('اكتب بند التحقق')
    try {
      await checklistMutation.mutateAsync({
        workItemId: item.id,
        expectedVersion: item.state_version,
        label: checklistLabel.trim(),
        isRequired: checklistRequired,
      })
      toast.success('تمت إضافة بند التحقق')
      setChecklistLabel('')
      setChecklistRequired(true)
      closeModal()
    } catch (error) { showError(error) }
  }

  const submitDependency = async () => {
    const parsed = Number(blockerNumber.trim())
    if (!Number.isInteger(parsed) || parsed <= 0) return toast.error('أدخل رقم عمل صحيح')
    try {
      const blocker = await findVisibleWorkItemByNumber(parsed)
      await dependencyMutation.mutateAsync({
        workItemId: item.id,
        blockerWorkItemId: blocker.id,
        expectedVersion: item.state_version,
        strength: dependencyStrength,
      })
      toast.success(`تم ربط الاعتماد على #${blocker.work_number} — ${blocker.title}`)
      setBlockerNumber('')
      closeModal()
    } catch (error) { showError(error) }
  }

  const submitLink = async () => {
    if (!isUuid(entityId)) return toast.error('معرّف الكيان UUID غير صالح')
    try {
      await linkMutation.mutateAsync({
        workItemId: item.id,
        expectedVersion: item.state_version,
        entityType,
        entityId: entityId.trim(),
        label: entityLabel.trim() || null,
      })
      toast.success('تم ربط الكيان بالمهمة')
      setEntityId('')
      setEntityLabel('')
      closeModal()
    } catch (error) { showError(error) }
  }

  const pending = cancelMutation.isPending || reopenMutation.isPending || checklistMutation.isPending ||
    linkMutation.isPending || removeLinkMutation.isPending || dependencyMutation.isPending || resolveDependencyMutation.isPending

  return (
    <>
      <section className="work-panel">
        <div className="work-panel-header">
          <div className="work-panel-title"><Network size={18} /> أدوات التحكم والتعاون</div>
          <span className="work-section-note">كل تعديل مسجل في السجل التشغيلي</span>
        </div>
        <div className="work-panel-body">
          <div className="work-detail-actions">
            {canEdit && <Button size="sm" variant="secondary" icon={<ListPlus size={15} />} onClick={() => setModal('checklist')}>إضافة بند تحقق</Button>}
            {canEdit && <Button size="sm" variant="secondary" icon={<Network size={15} />} onClick={() => setModal('dependency')}>إضافة اعتماد</Button>}
            {canEdit && <Button size="sm" variant="secondary" icon={<Link2 size={15} />} onClick={() => setModal('link')}>ربط كيان</Button>}
            {canManage && !isTerminal && <Button size="sm" variant="ghost" icon={<XCircle size={15} />} onClick={() => setModal('cancel')}>إلغاء العمل</Button>}
            {canManage && isTerminal && <Button size="sm" icon={<RotateCcw size={15} />} onClick={() => setModal('reopen')}>إعادة فتح العمل</Button>}
          </div>
          {!canEdit && !canManage && <div className="work-section-note">يمكنك عرض الروابط والاعتمادات، بينما التعديل يخضع لمسؤولية المهمة والصلاحيات.</div>}
        </div>
      </section>

      <section className="work-panel">
        <div className="work-panel-header">
          <div className="work-panel-title"><Network size={18} /> الاعتمادات</div>
          <span className="work-section-note">{activeDependencies.length} نشط</span>
        </div>
        <div className="work-panel-body">
          {dependenciesQuery.isLoading ? <div className="work-section-note">جارٍ تحميل الاعتمادات…</div> : activeDependencies.length === 0 ? (
            <div className="work-section-note">لا توجد أعمال تمنع أو تؤثر على تنفيذ هذه المهمة.</div>
          ) : (
            <div className="work-comment-list">
              {activeDependencies.map(dep => (
                <div key={dep.id} className="work-comment">
                  <div className="work-action-topline">
                    <strong>{dep.blocker ? `#${dep.blocker.work_number} — ${dep.blocker.title}` : 'عمل مرتبط'}</strong>
                    <span className="work-section-note">{dep.dependency_strength === 'hard' ? 'اعتماد إلزامي' : 'اعتماد إرشادي'}</span>
                  </div>
                  {dep.blocker && <div className="work-comment-meta">الحالة الحالية: {dep.blocker.status}</div>}
                  {canEdit && (
                    <div className="work-detail-actions" style={{ marginTop: 'var(--space-2)' }}>
                      <Button size="sm" variant="ghost" loading={resolveDependencyMutation.isPending} onClick={() => void resolveDependencyMutation.mutateAsync({ dependencyId: dep.id, expectedVersion: item.state_version, reason: 'تم حل الاعتماد من صفحة العمل' }).then(() => toast.success('تم حل الاعتماد')).catch(showError)}>تسجيل الحل</Button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
          {resolvedDependencies.length > 0 && <div className="work-section-note" style={{ marginTop: 'var(--space-3)' }}>تم حل {resolvedDependencies.length} اعتماد سابق — التفاصيل محفوظة في السجل.</div>}
        </div>
      </section>

      <section className="work-panel">
        <div className="work-panel-header">
          <div className="work-panel-title"><Link2 size={18} /> الكيانات المرتبطة</div>
          <span className="work-section-note">مرجع فقط — لا يمنح صلاحية للكيان</span>
        </div>
        <div className="work-panel-body">
          {linksQuery.isLoading ? <div className="work-section-note">جارٍ تحميل الروابط…</div> : (linksQuery.data ?? []).length === 0 ? (
            <div className="work-section-note">لا توجد كيانات مرتبطة بهذه المهمة.</div>
          ) : (
            <div className="work-comment-list">
              {linksQuery.data?.map(link => (
                <div key={link.id} className="work-comment">
                  <div className="work-action-topline">
                    <strong>{ENTITY_LABELS[link.entity_type] ?? link.entity_type}{link.label ? ` — ${link.label}` : ''}</strong>
                    {canEdit && <Button size="sm" variant="ghost" icon={<Trash2 size={14} />} loading={removeLinkMutation.isPending} onClick={() => void removeLinkMutation.mutateAsync({ linkId: link.id, expectedVersion: item.state_version, reason: 'إزالة الربط من صفحة العمل' }).then(() => toast.success('تمت إزالة الربط')).catch(showError)}>إزالة</Button>}
                  </div>
                  <div className="work-comment-meta" dir="ltr">{link.entity_id}</div>
                </div>
              ))}
            </div>
          )}
        </div>
      </section>

      <ResponsiveModal open={modal === 'cancel'} onClose={closeModal} title="إلغاء العمل" footer={<><Button variant="secondary" onClick={closeModal}>رجوع</Button><Button loading={cancelMutation.isPending} onClick={() => void submitCancel()}>تأكيد الإلغاء</Button></>}>
        <div className="work-form">
          <div className="work-field-hint">الإلغاء لا يحذف المهمة. السبب والحالة السابقة يظلان محفوظين في السجل.</div>
          <div className="work-field"><label>سبب الإلغاء *</label><textarea value={reason} onChange={event => setReason(event.target.value)} /></div>
        </div>
      </ResponsiveModal>

      <ResponsiveModal open={modal === 'reopen'} onClose={closeModal} title="إعادة فتح العمل" footer={<><Button variant="secondary" onClick={closeModal}>رجوع</Button><Button loading={reopenMutation.isPending} onClick={() => void submitReopen()}>إعادة الفتح</Button></>}>
        <div className="work-form">
          <div className="work-field"><label>سبب إعادة الفتح *</label><textarea value={reason} onChange={event => setReason(event.target.value)} /></div>
          <div className="work-field"><label>الإجراء التالي *</label><textarea value={reopenNextAction} onChange={event => setReopenNextAction(event.target.value)} /></div>
          <div className="work-field"><label>موعد الإجراء التالي</label><input type="datetime-local" value={reopenNextAt} onChange={event => setReopenNextAt(event.target.value)} /></div>
        </div>
      </ResponsiveModal>

      <ResponsiveModal open={modal === 'checklist'} onClose={closeModal} title="إضافة بند تحقق" footer={<><Button variant="secondary" onClick={closeModal}>إلغاء</Button><Button loading={checklistMutation.isPending} onClick={() => void submitChecklist()}>إضافة</Button></>}>
        <div className="work-form">
          <div className="work-field"><label>بند التحقق *</label><input value={checklistLabel} onChange={event => setChecklistLabel(event.target.value)} placeholder="مثال: إرفاق موافقة العميل" /></div>
          <label className="work-checklist-row"><input type="checkbox" checked={checklistRequired} onChange={event => setChecklistRequired(event.target.checked)} /><span className="work-checklist-label">بند إلزامي قبل الإتمام</span></label>
        </div>
      </ResponsiveModal>

      <ResponsiveModal open={modal === 'dependency'} onClose={closeModal} title="إضافة اعتماد على عمل آخر" footer={<><Button variant="secondary" onClick={closeModal}>إلغاء</Button><Button loading={dependencyMutation.isPending} onClick={() => void submitDependency()}>ربط الاعتماد</Button></>}>
        <div className="work-form">
          <div className="work-field-hint">استخدم رقم العمل الظاهر مثل #1042. النظام يتحقق من صلاحية رؤية العمل ويمنع الحلقات تلقائيًا.</div>
          <div className="work-field"><label>رقم العمل المعتمد عليه *</label><input inputMode="numeric" value={blockerNumber} onChange={event => setBlockerNumber(event.target.value.replace(/\D/g, ''))} /></div>
          <div className="work-field"><label>قوة الاعتماد</label><select value={dependencyStrength} onChange={event => setDependencyStrength(event.target.value as 'hard' | 'soft')}><option value="hard">إلزامي — يمنع الإتمام</option><option value="soft">إرشادي — لا يمنع الإتمام</option></select></div>
        </div>
      </ResponsiveModal>

      <ResponsiveModal open={modal === 'link'} onClose={closeModal} title="ربط كيان من النظام" footer={<><Button variant="secondary" onClick={closeModal}>إلغاء</Button><Button loading={linkMutation.isPending} onClick={() => void submitLink()}>إضافة الربط</Button></>}>
        <div className="work-form">
          <div className="work-field-hint">هذا الربط لا يغيّر صلاحيات العميل أو الفاتورة أو أي كيان آخر؛ هو مرجع تشغيلي داخل المهمة فقط.</div>
          <div className="work-field"><label>نوع الكيان</label><select value={entityType} onChange={event => setEntityType(event.target.value as WorkLinkEntityType)}>{ENTITY_TYPES.map(type => <option key={type.value} value={type.value}>{type.label}</option>)}</select></div>
          <div className="work-field"><label>معرّف الكيان UUID *</label><input dir="ltr" value={entityId} onChange={event => setEntityId(event.target.value)} placeholder="00000000-0000-0000-0000-000000000000" /></div>
          <div className="work-field"><label>وصف مختصر</label><input value={entityLabel} onChange={event => setEntityLabel(event.target.value)} maxLength={250} placeholder="اختياري — مثال: طلب أغسطس الرئيسي" /></div>
        </div>
      </ResponsiveModal>

      {pending && <span className="sr-only" role="status">جارٍ حفظ التغييرات</span>}
    </>
  )
}
