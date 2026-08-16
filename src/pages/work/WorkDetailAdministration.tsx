import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, CalendarClock, GitBranch, UserCog, UserPlus, Users } from 'lucide-react'
import { toast } from 'sonner'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import { useAuthStore } from '@/stores/auth-store'
import type { WorkItem, WorkPriority } from '@/features/work/types'
import {
  changeWorkDue,
  createWorkSubtask,
  delegateWork,
  escalateWork,
  getActiveWorkEscalation,
  listItemPeopleCandidates,
  listWorkParticipants,
  resolveWorkEscalation,
  setWorkParticipant,
  transferWorkOwnership,
  type WorkParticipantRole,
} from '@/features/work/administration-api'

type AdminModal = 'delegate' | 'transfer' | 'due' | 'subtask' | 'participant' | 'escalate' | 'resolveEscalation' | null

const ROLE_LABELS: Record<WorkParticipantRole, string> = {
  follower: 'متابع',
  collaborator: 'متعاون',
  observer: 'مراقب',
}

function toIso(localValue: string) {
  return localValue ? new Date(localValue).toISOString() : null
}

export default function WorkDetailAdministration({ item }: { item: WorkItem }) {
  const queryClient = useQueryClient()
  const profile = useAuthStore(state => state.profile)
  const can = useAuthStore(state => state.can)
  const [modal, setModal] = useState<AdminModal>(null)
  const [search, setSearch] = useState('')
  const [selectedUserId, setSelectedUserId] = useState('')
  const [reason, setReason] = useState('')
  const [dueAt, setDueAt] = useState('')
  const [participantRole, setParticipantRole] = useState<WorkParticipantRole>('follower')
  const [participantCanComment, setParticipantCanComment] = useState(true)
  const [subtaskTitle, setSubtaskTitle] = useState('')
  const [subtaskDescription, setSubtaskDescription] = useState('')
  const [subtaskOutcome, setSubtaskOutcome] = useState('')
  const [subtaskNextAction, setSubtaskNextAction] = useState('')
  const [subtaskDueAt, setSubtaskDueAt] = useState('')
  const [subtaskPriority, setSubtaskPriority] = useState<WorkPriority>('normal')
  const [subtaskBlocksParent, setSubtaskBlocksParent] = useState(true)

  const terminal = item.status === 'done' || item.status === 'cancelled'
  const isDirectActor = !!profile?.id && [
    item.creator_user_id,
    item.requester_user_id,
    item.accountable_owner_user_id,
    item.current_assignee_user_id,
  ].includes(profile.id)
  const canUpdate = !terminal && (
    can('work.items.manage') ||
    can('work.items.manage_team') ||
    (can('work.items.update_own') && isDirectActor)
  )
  const canDelegate = canUpdate && can('work.items.delegate')
  const canTransfer = canUpdate && can('work.items.transfer_ownership')

  const participantsQuery = useQuery({
    queryKey: ['work', 'participants', item.id],
    queryFn: () => listWorkParticipants(item.id),
  })
  const escalationQuery = useQuery({
    queryKey: ['work', 'escalation', item.id],
    queryFn: () => getActiveWorkEscalation(item.id),
  })

  const candidatePurpose = modal === 'delegate' ? 'delegate' : modal === 'transfer' ? 'transfer_owner' : 'participant'
  const needsCandidates = modal === 'delegate' || modal === 'transfer' || modal === 'participant'
  const candidatesQuery = useQuery({
    queryKey: ['work', 'people-candidates', item.id, candidatePurpose, search],
    queryFn: () => listItemPeopleCandidates(item.id, candidatePurpose, search),
    enabled: needsCandidates,
  })

  const invalidate = async () => {
    await queryClient.invalidateQueries({ queryKey: ['work'] })
  }

  const delegateMutation = useMutation({ mutationFn: delegateWork, onSuccess: invalidate })
  const transferMutation = useMutation({ mutationFn: transferWorkOwnership, onSuccess: invalidate })
  const dueMutation = useMutation({ mutationFn: changeWorkDue, onSuccess: invalidate })
  const subtaskMutation = useMutation({ mutationFn: createWorkSubtask, onSuccess: invalidate })
  const participantMutation = useMutation({ mutationFn: setWorkParticipant, onSuccess: invalidate })
  const escalationMutation = useMutation({ mutationFn: escalateWork, onSuccess: invalidate })
  const resolveEscalationMutation = useMutation({ mutationFn: resolveWorkEscalation, onSuccess: invalidate })

  const selectedCandidate = useMemo(
    () => candidatesQuery.data?.find(candidate => candidate.user_id === selectedUserId) ?? null,
    [candidatesQuery.data, selectedUserId],
  )

  const resetModalState = () => {
    setModal(null)
    setSearch('')
    setSelectedUserId('')
    setReason('')
    setDueAt('')
    setParticipantRole('follower')
    setParticipantCanComment(true)
  }

  const showError = (error: unknown) => toast.error(error instanceof Error ? error.message : 'تعذر تنفيذ العملية')

  const submitPeopleAction = async () => {
    if (!selectedCandidate) return toast.error('اختر مستخدمًا من القائمة المتاحة')
    try {
      if (modal === 'delegate') {
        await delegateMutation.mutateAsync({ workItemId: item.id, expectedVersion: item.state_version, userId: selectedCandidate.user_id, reason: reason.trim() || null })
        toast.success(`تم تفويض التنفيذ إلى ${selectedCandidate.full_name}`)
      } else if (modal === 'transfer') {
        if (!reason.trim()) return toast.error('سبب نقل المسؤولية مطلوب')
        await transferMutation.mutateAsync({ workItemId: item.id, expectedVersion: item.state_version, userId: selectedCandidate.user_id, reason: reason.trim() })
        toast.success(`تم نقل المسؤولية النهائية إلى ${selectedCandidate.full_name}`)
      } else if (modal === 'participant') {
        await participantMutation.mutateAsync({ workItemId: item.id, expectedVersion: item.state_version, userId: selectedCandidate.user_id, role: participantRole, canComment: participantCanComment, active: true })
        toast.success(`تمت إضافة ${selectedCandidate.full_name} إلى المشاركين`)
      }
      resetModalState()
    } catch (error) { showError(error) }
  }

  const submitDue = async () => {
    const iso = toIso(dueAt)
    if (!iso) return toast.error('اختر الموعد الجديد')
    if (!reason.trim()) return toast.error('سبب تغيير الموعد مطلوب')
    try {
      await dueMutation.mutateAsync({ workItemId: item.id, expectedVersion: item.state_version, dueAt: iso, reason: reason.trim() })
      toast.success('تم تحديث الموعد النهائي وتسجيل السبب')
      resetModalState()
    } catch (error) { showError(error) }
  }

  const submitSubtask = async () => {
    if (!subtaskTitle.trim() || !subtaskOutcome.trim() || !subtaskNextAction.trim()) return toast.error('العنوان والنتيجة المتوقعة والإجراء التالي مطلوبة')
    try {
      const result = await subtaskMutation.mutateAsync({
        parentWorkItemId: item.id,
        expectedParentVersion: item.state_version,
        title: subtaskTitle.trim(),
        description: subtaskDescription.trim() || null,
        expectedOutcome: subtaskOutcome.trim(),
        priority: subtaskPriority,
        dueAt: toIso(subtaskDueAt),
        nextActionText: subtaskNextAction.trim(),
        blocksParentCompletion: subtaskBlocksParent,
        activate: true,
      })
      toast.success(`تم إنشاء المهمة الفرعية #${result.work_number ?? ''}`.trim())
      setSubtaskTitle('')
      setSubtaskDescription('')
      setSubtaskOutcome('')
      setSubtaskNextAction('')
      setSubtaskDueAt('')
      setSubtaskPriority('normal')
      setSubtaskBlocksParent(true)
      resetModalState()
    } catch (error) { showError(error) }
  }

  const submitEscalation = async () => {
    if (!reason.trim()) return toast.error('سبب التصعيد مطلوب')
    try {
      await escalationMutation.mutateAsync({ workItemId: item.id, expectedVersion: item.state_version, reason: reason.trim() })
      toast.success('تم تصعيد المهمة إلى المسؤول النهائي')
      resetModalState()
    } catch (error) { showError(error) }
  }

  const submitResolveEscalation = async () => {
    if (!escalationQuery.data) return
    try {
      await resolveEscalationMutation.mutateAsync({ escalationId: escalationQuery.data.id, expectedVersion: item.state_version, note: reason.trim() || null })
      toast.success('تم إنهاء التصعيد')
      resetModalState()
    } catch (error) { showError(error) }
  }

  const peoplePending = delegateMutation.isPending || transferMutation.isPending || participantMutation.isPending

  return (
    <>
      <section className="work-panel">
        <div className="work-panel-header">
          <div className="work-panel-title"><UserCog size={18} /> إدارة التنفيذ</div>
          <span className="work-section-note">المسؤولية والتفويض والموعد والمهمة الفرعية</span>
        </div>
        <div className="work-panel-body">
          <div className="work-detail-actions">
            {canDelegate && <Button size="sm" variant="secondary" icon={<UserCog size={15} />} onClick={() => setModal('delegate')}>تفويض التنفيذ</Button>}
            {canTransfer && <Button size="sm" variant="secondary" icon={<Users size={15} />} onClick={() => setModal('transfer')}>نقل المسؤولية</Button>}
            {canUpdate && <Button size="sm" variant="secondary" icon={<CalendarClock size={15} />} onClick={() => setModal('due')}>تغيير الموعد</Button>}
            {canUpdate && <Button size="sm" variant="secondary" icon={<GitBranch size={15} />} onClick={() => setModal('subtask')}>مهمة فرعية</Button>}
            {canUpdate && <Button size="sm" variant="secondary" icon={<UserPlus size={15} />} onClick={() => setModal('participant')}>إضافة مشارك</Button>}
            {canUpdate && !escalationQuery.data && <Button size="sm" variant="ghost" icon={<AlertTriangle size={15} />} onClick={() => setModal('escalate')}>تصعيد</Button>}
          </div>
          {!canUpdate && !terminal && <div className="work-section-note">إجراءات الإدارة تظهر فقط داخل نطاق مسؤوليتك وصلاحياتك.</div>}
          {terminal && <div className="work-section-note">العمل مغلق؛ أعد فتحه أولاً قبل تعديل المسؤوليات أو الموعد.</div>}
        </div>
      </section>

      <section className="work-panel">
        <div className="work-panel-header">
          <div className="work-panel-title"><Users size={18} /> المشاركون</div>
          <span className="work-section-note">{participantsQuery.data?.length ?? 0} مشارك</span>
        </div>
        <div className="work-panel-body">
          {participantsQuery.isLoading ? <div className="work-section-note">جارٍ تحميل المشاركين…</div> : (participantsQuery.data ?? []).length === 0 ? (
            <div className="work-section-note">لا يوجد مشاركون إضافيون على هذه المهمة.</div>
          ) : (
            <div className="work-comment-list">
              {participantsQuery.data?.map(participant => (
                <div className="work-comment" key={participant.user_id}>
                  <div className="work-action-topline">
                    <strong>{participant.full_name}</strong>
                    <span className="work-section-note">{ROLE_LABELS[participant.participant_role]}{participant.can_comment ? ' · يمكنه التعليق' : ' · عرض فقط'}</span>
                  </div>
                  {canUpdate && <div className="work-detail-actions" style={{ marginTop: 'var(--space-2)' }}><Button size="sm" variant="ghost" loading={participantMutation.isPending} onClick={() => void participantMutation.mutateAsync({ workItemId: item.id, expectedVersion: item.state_version, userId: participant.user_id, role: participant.participant_role, canComment: participant.can_comment, active: false }).then(() => toast.success('تمت إزالة المشارك')).catch(showError)}>إزالة</Button></div>}
                </div>
              ))}
            </div>
          )}
        </div>
      </section>

      {escalationQuery.data && (
        <section className="work-panel">
          <div className="work-panel-header"><div className="work-panel-title"><AlertTriangle size={18} /> تصعيد نشط</div><span className="work-section-note">يتطلب متابعة واضحة</span></div>
          <div className="work-panel-body">
            <div className="work-comment"><strong>{escalationQuery.data.reason}</strong><div className="work-comment-meta">بدأ التصعيد {new Date(escalationQuery.data.escalated_at).toLocaleString('ar-EG')}</div></div>
            {canUpdate && <div className="work-detail-actions" style={{ marginTop: 'var(--space-3)' }}><Button size="sm" onClick={() => setModal('resolveEscalation')}>إنهاء التصعيد</Button></div>}
          </div>
        </section>
      )}

      <ResponsiveModal open={modal === 'delegate' || modal === 'transfer' || modal === 'participant'} onClose={resetModalState} title={modal === 'delegate' ? 'تفويض التنفيذ' : modal === 'transfer' ? 'نقل المسؤولية النهائية' : 'إضافة مشارك'} footer={<><Button variant="secondary" onClick={resetModalState}>إلغاء</Button><Button loading={peoplePending} onClick={() => void submitPeopleAction()}>حفظ</Button></>}>
        <div className="work-form">
          <div className="work-field-hint">القائمة تعرض فقط المستخدمين النشطين المسموح لك بالإسناد إليهم وفق نطاقك التنظيمي.</div>
          <div className="work-field"><label>بحث بالاسم</label><input value={search} onChange={event => { setSearch(event.target.value); setSelectedUserId('') }} placeholder="اكتب جزءًا من الاسم" /></div>
          <div className="work-field"><label>المستخدم *</label><select value={selectedUserId} onChange={event => setSelectedUserId(event.target.value)}><option value="">اختر المستخدم</option>{candidatesQuery.data?.map(candidate => <option key={candidate.user_id} value={candidate.user_id}>{candidate.full_name}{candidate.is_self ? ' — أنت' : ''}</option>)}</select>{candidatesQuery.isLoading && <span className="work-field-hint">جارٍ تحميل القائمة…</span>}</div>
          {modal === 'participant' && <><div className="work-field"><label>دور المشارك</label><select value={participantRole} onChange={event => setParticipantRole(event.target.value as WorkParticipantRole)}><option value="follower">متابع</option><option value="collaborator">متعاون</option><option value="observer">مراقب</option></select></div><label className="work-checklist-row"><input type="checkbox" checked={participantCanComment} onChange={event => setParticipantCanComment(event.target.checked)} /><span className="work-checklist-label">السماح بالتعليق</span></label></>}
          {(modal === 'delegate' || modal === 'transfer') && <div className="work-field"><label>{modal === 'transfer' ? 'سبب نقل المسؤولية *' : 'سبب التفويض'}</label><textarea value={reason} onChange={event => setReason(event.target.value)} /></div>}
        </div>
      </ResponsiveModal>

      <ResponsiveModal open={modal === 'due'} onClose={resetModalState} title="تغيير الموعد النهائي" footer={<><Button variant="secondary" onClick={resetModalState}>إلغاء</Button><Button loading={dueMutation.isPending} onClick={() => void submitDue()}>تحديث الموعد</Button></>}>
        <div className="work-form"><div className="work-field"><label>الموعد الجديد *</label><input type="datetime-local" value={dueAt} onChange={event => setDueAt(event.target.value)} /></div><div className="work-field"><label>سبب التغيير *</label><textarea value={reason} onChange={event => setReason(event.target.value)} /></div></div>
      </ResponsiveModal>

      <ResponsiveModal open={modal === 'subtask'} onClose={resetModalState} title="إنشاء مهمة فرعية" size="lg" footer={<><Button variant="secondary" onClick={resetModalState}>إلغاء</Button><Button loading={subtaskMutation.isPending} onClick={() => void submitSubtask()}>إنشاء المهمة</Button></>}>
        <div className="work-form">
          <div className="work-field"><label>العنوان *</label><input value={subtaskTitle} onChange={event => setSubtaskTitle(event.target.value)} /></div>
          <div className="work-field"><label>الوصف</label><textarea value={subtaskDescription} onChange={event => setSubtaskDescription(event.target.value)} /></div>
          <div className="work-field"><label>النتيجة المتوقعة *</label><textarea value={subtaskOutcome} onChange={event => setSubtaskOutcome(event.target.value)} /></div>
          <div className="work-field"><label>الإجراء التالي *</label><textarea value={subtaskNextAction} onChange={event => setSubtaskNextAction(event.target.value)} /></div>
          <div className="work-form-grid"><div className="work-field"><label>الأولوية</label><select value={subtaskPriority} onChange={event => setSubtaskPriority(event.target.value as WorkPriority)}><option value="low">منخفضة</option><option value="normal">عادية</option><option value="high">عالية</option><option value="urgent">عاجلة</option><option value="critical">حرجة</option></select></div><div className="work-field"><label>الموعد النهائي</label><input type="datetime-local" value={subtaskDueAt} onChange={event => setSubtaskDueAt(event.target.value)} /></div></div>
          <label className="work-checklist-row"><input type="checkbox" checked={subtaskBlocksParent} onChange={event => setSubtaskBlocksParent(event.target.checked)} /><span className="work-checklist-label">تمنع إتمام المهمة الرئيسية حتى تُغلق</span></label>
        </div>
      </ResponsiveModal>

      <ResponsiveModal open={modal === 'escalate'} onClose={resetModalState} title="تصعيد المهمة" footer={<><Button variant="secondary" onClick={resetModalState}>إلغاء</Button><Button loading={escalationMutation.isPending} onClick={() => void submitEscalation()}>تأكيد التصعيد</Button></>}>
        <div className="work-form"><div className="work-field-hint">سيتم توجيه التصعيد إلى المسؤول النهائي الحالي مع تسجيله في السجل التشغيلي.</div><div className="work-field"><label>سبب التصعيد *</label><textarea value={reason} onChange={event => setReason(event.target.value)} /></div></div>
      </ResponsiveModal>

      <ResponsiveModal open={modal === 'resolveEscalation'} onClose={resetModalState} title="إنهاء التصعيد" footer={<><Button variant="secondary" onClick={resetModalState}>إلغاء</Button><Button loading={resolveEscalationMutation.isPending} onClick={() => void submitResolveEscalation()}>إنهاء التصعيد</Button></>}>
        <div className="work-form"><div className="work-field"><label>ملاحظة الحل</label><textarea value={reason} onChange={event => setReason(event.target.value)} placeholder="ما الذي تم لحل سبب التصعيد؟" /></div></div>
      </ResponsiveModal>
    </>
  )
}
