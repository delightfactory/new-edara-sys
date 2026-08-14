import { useEffect, useMemo, useRef, useState, type ChangeEvent } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import {
  AlertTriangle,
  ArrowRight,
  Check,
  CheckCircle2,
  Clock3,
  Download,
  FileText,
  History,
  MessageSquareText,
  Paperclip,
  PauseCircle,
  PlayCircle,
  RefreshCw,
  Send,
  ShieldCheck,
  Target,
  Trash2,
  UserRound,
  UsersRound,
} from 'lucide-react'
import { toast } from 'sonner'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import PageHeader from '@/components/shared/PageHeader'
import { useAuthStore } from '@/stores/auth-store'
import { useWorkChecklist, useWorkComments, useWorkItem, useWorkTimeline } from '@/features/work/hooks'
import { useWorkAttachments, useWorkResponsibility } from '@/features/work/detail-hooks'
import { downloadWorkAttachment, type WorkAttachment } from '@/features/work/detail-api'
import {
  useAcknowledgeWork,
  useAddWorkComment,
  useAssignmentCandidates,
  useCompleteWork,
  useDecideApproval,
  useMyActionInbox,
  useOperationalFlags,
  useRecordFirstView,
  useRemoveWorkAttachment,
  useResumeWork,
  useReviewCompletion,
  useSetChecklistCompletion,
  useSetWorkWaiting,
  useStartWork,
  useTriageRequest,
  useUpdateNextAction,
  useUploadWorkAttachment,
} from '@/features/work/runtime-hooks'
import type { WorkActionInboxItem } from '@/features/work/runtime-types'
import { WorkOperationalBadges, WorkPriorityBadge, WorkStatusBadge } from '@/features/work/components/WorkBadges'
import { formatWorkNumber } from '@/features/work/presentation'
import './work.css'
import './work-interactions.css'

type ModalKind = 'waiting' | 'resume' | 'next_action' | 'complete' | 'approval' | 'completion_review' | 'triage' | null

type TriageDecision = 'accept' | 'needs_information' | 'reject'

const EVENT_LABELS: Record<string, string> = {
  'work.created': 'تم إنشاء العمل',
  'work.activated': 'تم تفعيل العمل',
  'work.acknowledged': 'تم تأكيد الاستلام',
  'work.started': 'بدأ التنفيذ',
  'work.waiting': 'تم وضع العمل في الانتظار',
  'work.resumed': 'تم استئناف التنفيذ',
  'work.next_action_updated': 'تم تحديث الإجراء التالي',
  'work.delegated': 'تم تفويض التنفيذ',
  'work.ownership_transferred': 'تم نقل المسؤولية النهائية',
  'work.comment_added': 'تمت إضافة تعليق',
  'work.progress_updated': 'تم تسجيل تحديث تقدم',
  'work.checklist_item_completed': 'اكتمل بند من قائمة التحقق',
  'work.checklist_item_reopened': 'أعيد فتح بند من قائمة التحقق',
  'work.attachment_added': 'تمت إضافة مرفق',
  'work.attachment_removed': 'تم حذف مرفق من العمل',
  'work.dependency_added': 'تمت إضافة اعتماد على عمل آخر',
  'work.dependency_resolved': 'تم حل اعتماد سابق',
  'work.completed': 'تم إتمام العمل',
  'work.completion_review_requested': 'تم إرسال الإتمام للمراجعة',
  'work.completion_approved': 'تم اعتماد الإتمام',
  'work.completion_changes_required': 'طُلبت تعديلات على الإتمام',
  'work.approval.requested': 'تم طلب اعتماد',
  'work.approval.decision': 'تم تسجيل قرار اعتماد',
  'work.request.submitted': 'تم إرسال الطلب',
  'work.request.information_required': 'طُلبت معلومات إضافية',
  'work.request.accepted': 'تم قبول الطلب وإسناده',
  'work.request.rejected': 'تم رفض الطلب',
  'work.escalated': 'تم تصعيد العمل',
  'work.escalation_resolved': 'تم إنهاء التصعيد',
  'work.recurrence.generated': 'تم إنشاء العمل من تكرار دوري',
  'work.workflow_step.activated': 'تم تفعيل خطوة مسار العمل',
}

function formatDateTime(value: string | null) {
  if (!value) return '—'
  return new Intl.DateTimeFormat('ar-EG-u-nu-latn', {
    timeZone: 'Africa/Cairo',
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(new Date(value))
}

function formatFileSize(bytes: number) {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function eventLabel(eventType: string) {
  return EVENT_LABELS[eventType] ?? 'حدث تشغيلي'
}

export default function WorkDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const profile = useAuthStore(s => s.profile)

  const itemQuery = useWorkItem(id)
  const timelineQuery = useWorkTimeline(id)
  const commentsQuery = useWorkComments(id)
  const checklistQuery = useWorkChecklist(id)
  const responsibilityQuery = useWorkResponsibility(id)
  const attachmentsQuery = useWorkAttachments(id)
  const flagsQuery = useOperationalFlags(id ? [id] : [])
  const inboxQuery = useMyActionInbox(200)
  const assignmentQuery = useAssignmentCandidates('')

  const acknowledge = useAcknowledgeWork()
  const start = useStartWork()
  const setWaiting = useSetWorkWaiting()
  const resume = useResumeWork()
  const updateNext = useUpdateNextAction()
  const complete = useCompleteWork()
  const addComment = useAddWorkComment()
  const setChecklist = useSetChecklistCompletion()
  const recordFirstView = useRecordFirstView()
  const uploadAttachment = useUploadWorkAttachment()
  const removeAttachment = useRemoveWorkAttachment()
  const decideApproval = useDecideApproval()
  const reviewCompletion = useReviewCompletion()
  const triageRequest = useTriageRequest()

  const [modal, setModal] = useState<ModalKind>(null)
  const [activeAction, setActiveAction] = useState<WorkActionInboxItem | null>(null)
  const [waitingType, setWaitingType] = useState<'external_party' | 'department' | 'queue' | 'other'>('external_party')
  const [waitingLabel, setWaitingLabel] = useState('')
  const [waitingReason, setWaitingReason] = useState('')
  const [followUpAt, setFollowUpAt] = useState('')
  const [nextActionText, setNextActionText] = useState('')
  const [nextActionAt, setNextActionAt] = useState('')
  const [completionSummary, setCompletionSummary] = useState('')
  const [decision, setDecision] = useState<'approve' | 'reject' | 'changes_required'>('approve')
  const [decisionNote, setDecisionNote] = useState('')
  const [triageDecision, setTriageDecision] = useState<TriageDecision>('accept')
  const [triageAssignee, setTriageAssignee] = useState('')
  const [triageOwner, setTriageOwner] = useState('')
  const [triageDueAt, setTriageDueAt] = useState('')
  const [commentBody, setCommentBody] = useState('')
  const [commentKind, setCommentKind] = useState<'comment' | 'progress_update'>('comment')
  const viewedRef = useRef<string | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const item = itemQuery.data
  const responsibility = responsibilityQuery.data
  const operationalRow = flagsQuery.data?.[0]
  const itemActions = useMemo(
    () => (inboxQuery.data ?? []).filter(action => action.work_item_id === id),
    [inboxQuery.data, id],
  )

  useEffect(() => {
    if (!id || !item?.id || viewedRef.current === id) return
    viewedRef.current = id
    void recordFirstView.mutateAsync(id).catch(() => undefined)
  }, [id, item?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!item) return
    setNextActionText(item.next_action_text ?? '')
    setNextActionAt(item.next_action_at ? item.next_action_at.slice(0, 16) : '')
  }, [item?.id, item?.state_version]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (assignmentQuery.data?.length && !triageAssignee) {
      const self = assignmentQuery.data.find(candidate => candidate.is_self) ?? assignmentQuery.data[0]
      setTriageAssignee(self.user_id)
      setTriageOwner(self.user_id)
    }
  }, [assignmentQuery.data, triageAssignee])

  if (!id) return null

  if (itemQuery.isLoading) {
    return <div className="work-page"><div className="skeleton skeleton-row" /><div className="skeleton skeleton-row" /><div className="skeleton skeleton-row" /></div>
  }

  if (itemQuery.isError || !item) {
    return (
      <div className="work-page">
        <PageHeader title="تعذر فتح العمل" subtitle="قد يكون العمل غير موجود أو خارج نطاق صلاحياتك." backPath="/work" />
        <div className="work-empty">
          <div className="work-empty-icon"><AlertTriangle size={22} /></div>
          <strong>لا يمكن عرض هذا العمل</strong>
          <Button variant="secondary" onClick={() => navigate('/work')}>العودة إلى مركز العمل</Button>
        </div>
      </div>
    )
  }

  const isAssignee = item.current_assignee_user_id === profile?.id
  const isOwner = item.accountable_owner_user_id === profile?.id
  const isTerminal = item.status === 'done' || item.status === 'cancelled'
  const ballHolder = item.status === 'waiting'
    ? responsibility?.waiting_on?.label ?? item.waiting_on_label ?? 'جهة انتظار'
    : responsibility?.assignee?.full_name ?? 'غير محدد'

  const flags = operationalRow ? {
    is_overdue: operationalRow.is_overdue,
    is_followup_due: operationalRow.is_follow_up_due,
    is_blocked: operationalRow.is_blocked,
    is_stale: operationalRow.is_stale,
    is_at_risk: operationalRow.is_at_risk,
    is_escalated: operationalRow.is_escalated,
  } : null

  const closeModal = () => {
    setModal(null)
    setActiveAction(null)
    setDecisionNote('')
  }

  const handleSimpleMutation = async (fn: () => Promise<unknown>, success: string) => {
    try {
      await fn()
      toast.success(success)
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر تنفيذ العملية')
    }
  }

  const openAction = (action: WorkActionInboxItem) => {
    setActiveAction(action)
    if (action.action_kind === 'approval_decision') {
      setDecision('approve')
      setModal('approval')
    } else if (action.action_kind === 'completion_review') {
      setDecision('approve')
      setModal('completion_review')
    } else if (action.action_kind === 'triage_request') {
      setTriageDecision('accept')
      setModal('triage')
    } else if (action.action_kind === 'acknowledge') {
      void handleSimpleMutation(
        () => acknowledge.mutateAsync({ workItemId: item.id, expectedVersion: action.work_state_version }),
        'تم تأكيد استلام المهمة',
      )
    }
  }

  const submitWaiting = async () => {
    if (!waitingReason.trim() || !nextActionText.trim() || !followUpAt) {
      toast.error('سبب الانتظار والإجراء التالي وموعد المتابعة مطلوبة')
      return
    }
    await handleSimpleMutation(
      () => setWaiting.mutateAsync({
        workItemId: item.id,
        expectedVersion: item.state_version,
        waitingOnType: waitingType,
        reason: waitingReason.trim(),
        nextActionText: nextActionText.trim(),
        followUpAt: new Date(followUpAt).toISOString(),
        waitingOnLabel: waitingLabel.trim() || null,
      }),
      'تم تحويل العمل إلى انتظار مع موعد متابعة',
    )
    closeModal()
  }

  const submitResume = async () => {
    if (!nextActionText.trim()) {
      toast.error('الإجراء التالي مطلوب قبل الاستئناف')
      return
    }
    await handleSimpleMutation(
      () => resume.mutateAsync({
        workItemId: item.id,
        expectedVersion: item.state_version,
        nextActionText: nextActionText.trim(),
        nextActionAt: nextActionAt ? new Date(nextActionAt).toISOString() : null,
      }),
      'تم استئناف العمل',
    )
    closeModal()
  }

  const submitNextAction = async () => {
    if (!nextActionText.trim()) {
      toast.error('الإجراء التالي مطلوب')
      return
    }
    await handleSimpleMutation(
      () => updateNext.mutateAsync({
        workItemId: item.id,
        expectedVersion: item.state_version,
        nextActionText: nextActionText.trim(),
        nextActionAt: nextActionAt ? new Date(nextActionAt).toISOString() : null,
      }),
      'تم تحديث الإجراء التالي',
    )
    closeModal()
  }

  const submitComplete = async () => {
    if (!completionSummary.trim()) {
      toast.error('اكتب ملخص النتيجة التي تحققت')
      return
    }
    await handleSimpleMutation(
      () => complete.mutateAsync({
        workItemId: item.id,
        expectedVersion: item.state_version,
        completionSummary: completionSummary.trim(),
      }),
      item.completion_mode === 'owner_review' && !isOwner ? 'تم إرسال الإتمام للمراجعة' : 'تم إتمام العمل',
    )
    closeModal()
  }

  const submitApprovalDecision = async () => {
    if (!activeAction?.approval_state_version) return
    if (decision !== 'approve' && !decisionNote.trim()) {
      toast.error('سبب الرفض أو طلب التعديل مطلوب')
      return
    }
    await handleSimpleMutation(
      () => decideApproval.mutateAsync({
        assignmentId: activeAction.subject_id,
        expectedApprovalVersion: activeAction.approval_state_version!,
        decision,
        note: decisionNote.trim() || null,
      }),
      'تم تسجيل قرار الاعتماد',
    )
    closeModal()
  }

  const submitCompletionReview = async () => {
    if (!activeAction) return
    const reviewDecision = decision === 'approve' ? 'approve' : 'changes_required'
    if (reviewDecision === 'changes_required' && !decisionNote.trim()) {
      toast.error('وضح التعديلات المطلوبة')
      return
    }
    await handleSimpleMutation(
      () => reviewCompletion.mutateAsync({
        reviewId: activeAction.subject_id,
        expectedVersion: activeAction.work_state_version,
        decision: reviewDecision,
        note: decisionNote.trim() || null,
      }),
      reviewDecision === 'approve' ? 'تم اعتماد الإتمام' : 'تم إرسال التعديلات المطلوبة',
    )
    closeModal()
  }

  const submitTriage = async () => {
    if (!activeAction) return
    if (triageDecision === 'accept' && (!triageAssignee || !nextActionText.trim())) {
      toast.error('حدد المكلف والإجراء التالي لقبول الطلب')
      return
    }
    if (triageDecision === 'needs_information' && (!decisionNote.trim() || !followUpAt)) {
      toast.error('وضح المعلومات المطلوبة وحدد موعد المتابعة')
      return
    }
    if (triageDecision === 'reject' && !decisionNote.trim()) {
      toast.error('سبب الرفض مطلوب')
      return
    }
    await handleSimpleMutation(
      () => triageRequest.mutateAsync({
        workItemId: item.id,
        expectedVersion: activeAction.work_state_version,
        decision: triageDecision,
        assigneeUserId: triageDecision === 'accept' ? triageAssignee : null,
        ownerUserId: triageDecision === 'accept' ? (triageOwner || triageAssignee) : null,
        dueAt: triageDecision === 'accept' && triageDueAt ? new Date(triageDueAt).toISOString() : null,
        nextActionText: triageDecision === 'accept' ? nextActionText.trim() : null,
        followUpAt: triageDecision === 'needs_information' && followUpAt ? new Date(followUpAt).toISOString() : null,
        note: decisionNote.trim() || null,
      }),
      triageDecision === 'accept' ? 'تم قبول الطلب وإسناده' : triageDecision === 'needs_information' ? 'تم طلب معلومات إضافية' : 'تم رفض الطلب',
    )
    closeModal()
  }

  const submitComment = async () => {
    if (!commentBody.trim()) return
    await handleSimpleMutation(
      () => addComment.mutateAsync({ workItemId: item.id, body: commentBody.trim(), commentKind }),
      commentKind === 'progress_update' ? 'تم تسجيل تحديث التقدم' : 'تمت إضافة التعليق',
    )
    setCommentBody('')
  }

  const handleFile = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    await handleSimpleMutation(
      () => uploadAttachment.mutateAsync({ workItemId: item.id, expectedVersion: item.state_version, file }),
      'تم رفع المرفق',
    )
  }

  const handleDownload = async (attachment: WorkAttachment) => {
    try {
      const blob = await downloadWorkAttachment(attachment)
      const url = URL.createObjectURL(blob)
      const anchor = document.createElement('a')
      anchor.href = url
      anchor.download = attachment.original_filename
      document.body.appendChild(anchor)
      anchor.click()
      anchor.remove()
      URL.revokeObjectURL(url)
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر تنزيل المرفق')
    }
  }

  const handleRemoveAttachment = async (attachment: WorkAttachment) => {
    await handleSimpleMutation(
      () => removeAttachment.mutateAsync({
        attachmentId: attachment.id,
        workItemId: item.id,
        expectedVersion: item.state_version,
        storagePath: attachment.storage_path,
      }),
      'تم حذف المرفق من العمل',
    )
  }

  return (
    <div className="work-page">
      <PageHeader
        title={item.title}
        subtitle={formatWorkNumber(item.work_number)}
        backPath="/work"
        actions={(
          <div className="work-action-topline">
            <WorkStatusBadge status={item.status} />
            <WorkPriorityBadge priority={item.priority} />
            {flags && <WorkOperationalBadges flags={flags} />}
          </div>
        )}
      />

      {itemActions.length > 0 && (
        <section className="work-panel" aria-labelledby="required-actions-title">
          <div className="work-panel-header">
            <div id="required-actions-title" className="work-panel-title"><ShieldCheck size={18} /> مطلوب منك قرار الآن</div>
            <span className="work-section-note">{itemActions.length} إجراء</span>
          </div>
          <div className="work-panel-body work-action-list">
            {itemActions.map(action => (
              <div key={action.inbox_key} className="work-action-card">
                <div className="work-action-main">
                  <div className="work-action-type">
                    {action.action_kind === 'approval_decision' ? 'اعتماد مطلوب' :
                      action.action_kind === 'completion_review' ? 'مراجعة إتمام' :
                        action.action_kind === 'triage_request' ? 'فرز طلب' :
                          action.action_kind === 'acknowledge' ? 'تأكيد استلام' : 'إجراء تشغيلي'}
                  </div>
                  <div className="work-action-meta"><span><Clock3 size={13} /> {formatDateTime(action.action_due_at)}</span></div>
                </div>
                <div className="work-action-cta">
                  {['approval_decision', 'completion_review', 'triage_request', 'acknowledge'].includes(action.action_kind) ? (
                    <Button size="sm" onClick={() => openAction(action)}>تنفيذ القرار</Button>
                  ) : (
                    <Button size="sm" variant="secondary" onClick={() => setModal(item.status === 'waiting' ? 'resume' : 'next_action')}>تنفيذ الإجراء</Button>
                  )}
                </div>
              </div>
            ))}
          </div>
        </section>
      )}

      <div className="work-detail-grid">
        <main className="work-detail-main">
          <section className="work-panel work-next-action">
            <div className="work-panel-header">
              <div className="work-panel-title"><Target size={18} /> الإجراء التالي</div>
              {!isTerminal && <Button size="sm" variant="ghost" icon={<RefreshCw size={15} />} onClick={() => setModal('next_action')}>تحديث</Button>}
            </div>
            <div className="work-panel-body">
              <div className="work-next-action-text">{item.next_action_text || (isTerminal ? 'لا يوجد إجراء — العمل منتهٍ' : 'لم يحدد الإجراء التالي')}</div>
              <div className="work-next-action-time"><Clock3 size={14} /> {formatDateTime(item.next_action_at ?? item.due_at)}</div>
              {!isTerminal && (
                <div className="work-detail-actions" style={{ marginTop: 'var(--space-4)' }}>
                  {isAssignee && item.acknowledgement_required && !item.acknowledged_at && (
                    <Button
                      icon={<Check size={16} />}
                      loading={acknowledge.isPending}
                      onClick={() => void handleSimpleMutation(
                        () => acknowledge.mutateAsync({ workItemId: item.id, expectedVersion: item.state_version }),
                        'تم تأكيد استلام المهمة',
                      )}
                    >تأكيد الاستلام</Button>
                  )}
                  {isAssignee && item.status === 'open' && (!item.acknowledgement_required || item.acknowledged_at) && (
                    <Button
                      icon={<PlayCircle size={16} />}
                      loading={start.isPending}
                      onClick={() => void handleSimpleMutation(
                        () => start.mutateAsync({ workItemId: item.id, expectedVersion: item.state_version }),
                        'بدأ تنفيذ المهمة',
                      )}
                    >بدء التنفيذ</Button>
                  )}
                  {(isAssignee || isOwner) && ['open', 'in_progress'].includes(item.status) && (
                    <Button variant="secondary" icon={<PauseCircle size={16} />} onClick={() => setModal('waiting')}>في انتظار جهة أخرى</Button>
                  )}
                  {(isAssignee || isOwner) && item.status === 'waiting' && (
                    <Button icon={<PlayCircle size={16} />} onClick={() => setModal('resume')}>استئناف</Button>
                  )}
                  {(isAssignee || isOwner) && ['open', 'in_progress', 'waiting'].includes(item.status) && (
                    <Button variant="success" icon={<CheckCircle2 size={16} />} onClick={() => setModal('complete')}>إتمام العمل</Button>
                  )}
                </div>
              )}
            </div>
          </section>

          <section className="work-panel">
            <div className="work-panel-header">
              <div className="work-panel-title"><FileText size={18} /> المطلوب والنتيجة</div>
            </div>
            <div className="work-panel-body">
              <div className="work-info-grid">
                <div className="work-info-cell" style={{ gridColumn: '1 / -1' }}>
                  <div className="work-info-label">النتيجة المتوقعة</div>
                  <div className="work-info-value">{item.expected_outcome || '—'}</div>
                </div>
                {item.description && (
                  <div className="work-info-cell" style={{ gridColumn: '1 / -1' }}>
                    <div className="work-info-label">تفاصيل التنفيذ</div>
                    <div className="work-info-value" style={{ whiteSpace: 'pre-wrap', fontWeight: 500 }}>{item.description}</div>
                  </div>
                )}
                <div className="work-info-cell">
                  <div className="work-info-label">الموعد النهائي</div>
                  <div className="work-info-value">{formatDateTime(item.due_at)}</div>
                </div>
                <div className="work-info-cell">
                  <div className="work-info-label">طريقة الإتمام</div>
                  <div className="work-info-value">{item.completion_mode === 'assignee_closes' ? 'إغلاق مباشر' : item.completion_mode === 'owner_review' ? 'مراجعة المسؤول النهائي' : 'اعتماد متعدد المراحل'}</div>
                </div>
                {item.status === 'done' && item.completion_summary && (
                  <div className="work-info-cell" style={{ gridColumn: '1 / -1' }}>
                    <div className="work-info-label">نتيجة التنفيذ</div>
                    <div className="work-info-value">{item.completion_summary}</div>
                  </div>
                )}
              </div>
            </div>
          </section>

          <section className="work-panel">
            <div className="work-panel-header">
              <div className="work-panel-title"><CheckCircle2 size={18} /> قائمة التحقق</div>
              <span className="work-section-note">{checklistQuery.data?.filter(row => row.completed_at).length ?? 0}/{checklistQuery.data?.length ?? 0}</span>
            </div>
            <div className="work-panel-body">
              {!checklistQuery.data?.length ? (
                <div className="work-section-note">لا توجد بنود تحقق لهذه المهمة.</div>
              ) : (
                <div className="work-checklist">
                  {checklistQuery.data.map(check => (
                    <label key={check.id} className="work-checklist-row">
                      <input
                        type="checkbox"
                        checked={Boolean(check.completed_at)}
                        disabled={setChecklist.isPending || isTerminal}
                        onChange={() => void handleSimpleMutation(
                          () => setChecklist.mutateAsync({
                            workItemId: item.id,
                            checklistItemId: check.id,
                            expectedVersion: item.state_version,
                            completed: !check.completed_at,
                          }),
                          check.completed_at ? 'أعيد فتح بند التحقق' : 'تم إكمال بند التحقق',
                        )}
                      />
                      <span className={`work-checklist-label ${check.completed_at ? 'work-checklist-label--done' : ''}`}>
                        {check.label}{check.is_required ? ' *' : ''}
                      </span>
                    </label>
                  ))}
                </div>
              )}
            </div>
          </section>

          <section className="work-panel">
            <div className="work-panel-header">
              <div className="work-panel-title"><MessageSquareText size={18} /> النقاش وتحديثات التقدم</div>
            </div>
            <div className="work-panel-body">
              <div className="work-form" style={{ marginBottom: 'var(--space-4)' }}>
                <div className="work-segmented" role="group" aria-label="نوع الرسالة">
                  <button type="button" aria-pressed={commentKind === 'comment'} onClick={() => setCommentKind('comment')}>تعليق</button>
                  <button type="button" aria-pressed={commentKind === 'progress_update'} onClick={() => setCommentKind('progress_update')}>تحديث تقدم</button>
                </div>
                <div className="work-field">
                  <textarea value={commentBody} onChange={event => setCommentBody(event.target.value)} placeholder={commentKind === 'progress_update' ? 'ماذا تم؟ وما الذي تغير في التنفيذ؟' : 'أضف تعليقًا مرتبطًا بهذا العمل'} />
                </div>
                <div className="work-form-actions" style={{ position: 'static', margin: 0, padding: 0, border: 0, background: 'transparent' }}>
                  <Button size="sm" icon={<Send size={15} />} loading={addComment.isPending} disabled={!commentBody.trim()} onClick={() => void submitComment()}>إرسال</Button>
                </div>
              </div>

              <div className="work-comment-list">
                {(commentsQuery.data ?? []).length === 0 ? (
                  <div className="work-section-note">لا توجد مناقشات بعد.</div>
                ) : commentsQuery.data?.map(comment => (
                  <div key={comment.id} className={`work-comment ${comment.comment_kind === 'progress_update' ? 'work-comment--progress' : ''}`}>
                    <div className="work-comment-body">{comment.redacted_at ? 'تم حجب محتوى هذا التعليق' : comment.body}</div>
                    <div className="work-comment-meta">{comment.comment_kind === 'progress_update' ? 'تحديث تقدم' : 'تعليق'} · {formatDateTime(comment.created_at)}</div>
                  </div>
                ))}
              </div>
            </div>
          </section>

          <section className="work-panel">
            <div className="work-panel-header">
              <div className="work-panel-title"><History size={18} /> السجل التشغيلي</div>
              <span className="work-section-note">غير قابل للتعديل</span>
            </div>
            <div className="work-panel-body">
              <div className="work-timeline">
                {(timelineQuery.data ?? []).map(event => (
                  <div key={event.id} className="work-timeline-row">
                    <div className="work-timeline-dot" aria-hidden="true" />
                    <div>
                      <div className="work-timeline-event">{eventLabel(event.event_type)}</div>
                      <div className="work-timeline-time">{formatDateTime(event.created_at)}</div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </section>
        </main>

        <aside className="work-detail-side">
          <section className="work-panel">
            <div className="work-panel-header">
              <div className="work-panel-title"><UsersRound size={18} /> المسؤولية الآن</div>
            </div>
            <div className="work-panel-body work-responsibility-card">
              <div className="work-responsibility-row">
                <span className="work-responsibility-label">المسؤول النهائي</span>
                <span className="work-responsibility-value">{responsibility?.owner?.full_name ?? '—'}</span>
              </div>
              <div className="work-responsibility-row">
                <span className="work-responsibility-label">المكلف الحالي</span>
                <span className="work-responsibility-value">{responsibility?.assignee?.full_name ?? '—'}</span>
              </div>
              <div className="work-responsibility-row">
                <span className="work-responsibility-label">الكرة الآن عند</span>
                <span className="work-responsibility-value" style={{ color: 'var(--color-primary)' }}>{ballHolder}</span>
              </div>
              {item.status === 'waiting' && (
                <div className="work-responsibility-row">
                  <span className="work-responsibility-label">سبب الانتظار</span>
                  <span className="work-responsibility-value">{item.waiting_reason ?? '—'}</span>
                </div>
              )}
            </div>
          </section>

          <section className="work-panel">
            <div className="work-panel-header">
              <div className="work-panel-title"><Paperclip size={18} /> المرفقات</div>
              {!isTerminal && (
                <Button size="sm" variant="ghost" icon={<Paperclip size={15} />} onClick={() => fileInputRef.current?.click()}>إضافة</Button>
              )}
              <input ref={fileInputRef} type="file" hidden onChange={event => void handleFile(event)} />
            </div>
            <div className="work-panel-body">
              {(attachmentsQuery.data ?? []).length === 0 ? (
                <div className="work-section-note">لا توجد مرفقات.</div>
              ) : (
                <div className="work-comment-list">
                  {attachmentsQuery.data?.map(attachment => (
                    <div key={attachment.id} className="work-comment">
                      <div className="work-action-topline">
                        <FileText size={16} />
                        <strong style={{ overflowWrap: 'anywhere' }}>{attachment.original_filename}</strong>
                      </div>
                      <div className="work-comment-meta">{formatFileSize(attachment.size_bytes)} · {attachment.purpose === 'evidence' ? 'دليل' : attachment.purpose === 'output' ? 'مخرج' : 'مرجع'}</div>
                      <div className="work-detail-actions" style={{ marginTop: 'var(--space-2)' }}>
                        <Button size="sm" variant="secondary" icon={<Download size={14} />} onClick={() => void handleDownload(attachment)}>تنزيل</Button>
                        {attachment.uploaded_by_user_id === profile?.id && !isTerminal && (
                          <Button size="sm" variant="ghost" icon={<Trash2 size={14} />} loading={removeAttachment.isPending} onClick={() => void handleRemoveAttachment(attachment)}>حذف</Button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </section>

          <section className="work-panel">
            <div className="work-panel-header">
              <div className="work-panel-title"><UserRound size={18} /> بيانات التشغيل</div>
            </div>
            <div className="work-panel-body work-responsibility-card">
              <div className="work-responsibility-row"><span className="work-responsibility-label">نوع العمل</span><span className="work-responsibility-value">{item.kind === 'task' ? 'مهمة' : item.kind === 'request' ? 'طلب' : 'خطوة مسار'}</span></div>
              <div className="work-responsibility-row"><span className="work-responsibility-label">المصدر</span><span className="work-responsibility-value">{item.source_kind === 'manual' ? 'يدوي' : item.source_kind === 'request_intake' ? 'طلب' : item.source_kind === 'workflow' ? 'مسار عمل' : item.source_kind === 'recurrence' ? 'دوري' : 'النظام'}</span></div>
              <div className="work-responsibility-row"><span className="work-responsibility-label">آخر حركة حقيقية</span><span className="work-responsibility-value">{formatDateTime(item.last_meaningful_activity_at)}</span></div>
              <div className="work-responsibility-row"><span className="work-responsibility-label">إصدار الحالة</span><span className="work-responsibility-value" dir="ltr">v{item.state_version}</span></div>
            </div>
          </section>
        </aside>
      </div>

      <ResponsiveModal
        open={modal === 'waiting'}
        onClose={closeModal}
        title="وضع العمل في انتظار"
        footer={<><Button variant="secondary" onClick={closeModal}>إلغاء</Button><Button loading={setWaiting.isPending} onClick={() => void submitWaiting()}>حفظ المتابعة</Button></>}
      >
        <div className="work-form">
          <div className="work-field"><label>الجهة المنتظر منها الإجراء</label><select value={waitingType} onChange={event => setWaitingType(event.target.value as typeof waitingType)}><option value="external_party">جهة خارجية</option><option value="department">إدارة داخلية</option><option value="queue">طابور/فريق عمل</option><option value="other">أخرى</option></select></div>
          <div className="work-field"><label>اسم الجهة أو الشخص</label><input value={waitingLabel} onChange={event => setWaitingLabel(event.target.value)} placeholder="مثال: العميل / الحسابات / المورد" /></div>
          <div className="work-field"><label>سبب الانتظار *</label><textarea value={waitingReason} onChange={event => setWaitingReason(event.target.value)} /></div>
          <div className="work-field"><label>الإجراء التالي *</label><input value={nextActionText} onChange={event => setNextActionText(event.target.value)} /></div>
          <div className="work-field"><label>موعد المتابعة *</label><input type="datetime-local" value={followUpAt} onChange={event => setFollowUpAt(event.target.value)} /></div>
        </div>
      </ResponsiveModal>

      <ResponsiveModal
        open={modal === 'resume' || modal === 'next_action'}
        onClose={closeModal}
        title={modal === 'resume' ? 'استئناف العمل' : 'تحديث الإجراء التالي'}
        footer={<><Button variant="secondary" onClick={closeModal}>إلغاء</Button><Button loading={resume.isPending || updateNext.isPending} onClick={() => void (modal === 'resume' ? submitResume() : submitNextAction())}>حفظ</Button></>}
      >
        <div className="work-form">
          <div className="work-field"><label>الإجراء التالي *</label><textarea value={nextActionText} onChange={event => setNextActionText(event.target.value)} /></div>
          <div className="work-field"><label>{modal === 'resume' ? 'موعد الإجراء' : 'موعد الإجراء التالي'}</label><input type="datetime-local" value={nextActionAt} onChange={event => setNextActionAt(event.target.value)} /></div>
        </div>
      </ResponsiveModal>

      <ResponsiveModal
        open={modal === 'complete'}
        onClose={closeModal}
        title="إتمام العمل"
        footer={<><Button variant="secondary" onClick={closeModal}>إلغاء</Button><Button variant="success" loading={complete.isPending} onClick={() => void submitComplete()}>تسجيل الإتمام</Button></>}
      >
        <div className="work-form">
          <div className="work-field"><label>ما النتيجة التي تحققت؟ *</label><textarea value={completionSummary} onChange={event => setCompletionSummary(event.target.value)} placeholder="اكتب نتيجة التنفيذ الفعلية، وليس مجرد كلمة تم." /></div>
          {item.completion_mode === 'owner_review' && !isOwner && <div className="work-field-hint">سيتم إرسال النتيجة للمسؤول النهائي للمراجعة قبل إغلاق المهمة.</div>}
        </div>
      </ResponsiveModal>

      <ResponsiveModal
        open={modal === 'approval'}
        onClose={closeModal}
        title="قرار الاعتماد"
        footer={<><Button variant="secondary" onClick={closeModal}>إلغاء</Button><Button loading={decideApproval.isPending} onClick={() => void submitApprovalDecision()}>تسجيل القرار</Button></>}
      >
        <div className="work-form">
          <div className="work-field"><label>القرار</label><select value={decision} onChange={event => setDecision(event.target.value as typeof decision)}><option value="approve">موافقة</option><option value="changes_required">طلب تعديلات</option><option value="reject">رفض</option></select></div>
          <div className="work-field"><label>{decision === 'approve' ? 'ملاحظة القرار' : 'سبب القرار *'}</label><textarea value={decisionNote} onChange={event => setDecisionNote(event.target.value)} /></div>
        </div>
      </ResponsiveModal>

      <ResponsiveModal
        open={modal === 'completion_review'}
        onClose={closeModal}
        title="مراجعة نتيجة التنفيذ"
        footer={<><Button variant="secondary" onClick={closeModal}>إلغاء</Button><Button loading={reviewCompletion.isPending} onClick={() => void submitCompletionReview()}>تسجيل القرار</Button></>}
      >
        <div className="work-form">
          <div className="work-field"><label>القرار</label><select value={decision === 'approve' ? 'approve' : 'changes_required'} onChange={event => setDecision(event.target.value as 'approve' | 'changes_required')}><option value="approve">اعتماد الإتمام</option><option value="changes_required">طلب تعديلات</option></select></div>
          <div className="work-field"><label>{decision === 'approve' ? 'ملاحظة' : 'التعديلات المطلوبة *'}</label><textarea value={decisionNote} onChange={event => setDecisionNote(event.target.value)} /></div>
        </div>
      </ResponsiveModal>

      <ResponsiveModal
        open={modal === 'triage'}
        onClose={closeModal}
        title="فرز الطلب"
        size="lg"
        footer={<><Button variant="secondary" onClick={closeModal}>إلغاء</Button><Button loading={triageRequest.isPending} onClick={() => void submitTriage()}>تسجيل القرار</Button></>}
      >
        <div className="work-form">
          <div className="work-field"><label>قرار الفرز</label><select value={triageDecision} onChange={event => setTriageDecision(event.target.value as TriageDecision)}><option value="accept">قبول وإسناد</option><option value="needs_information">طلب معلومات إضافية</option><option value="reject">رفض الطلب</option></select></div>
          {triageDecision === 'accept' ? (
            <>
              <div className="work-form-grid">
                <div className="work-field"><label>المكلف</label><select value={triageAssignee} onChange={event => setTriageAssignee(event.target.value)}><option value="">اختر</option>{assignmentQuery.data?.map(candidate => <option key={candidate.user_id} value={candidate.user_id}>{candidate.full_name}{candidate.is_self ? ' — أنا' : ''}</option>)}</select></div>
                <div className="work-field"><label>المسؤول النهائي</label><select value={triageOwner} onChange={event => setTriageOwner(event.target.value)}><option value="">اختر</option>{assignmentQuery.data?.map(candidate => <option key={candidate.user_id} value={candidate.user_id}>{candidate.full_name}{candidate.is_self ? ' — أنا' : ''}</option>)}</select></div>
              </div>
              <div className="work-field"><label>الإجراء التالي *</label><input value={nextActionText} onChange={event => setNextActionText(event.target.value)} /></div>
              <div className="work-field"><label>الموعد النهائي</label><input type="datetime-local" value={triageDueAt} onChange={event => setTriageDueAt(event.target.value)} /></div>
            </>
          ) : (
            <>
              <div className="work-field"><label>{triageDecision === 'reject' ? 'سبب الرفض *' : 'المعلومات المطلوبة *'}</label><textarea value={decisionNote} onChange={event => setDecisionNote(event.target.value)} /></div>
              {triageDecision === 'needs_information' && <div className="work-field"><label>موعد المتابعة *</label><input type="datetime-local" value={followUpAt} onChange={event => setFollowUpAt(event.target.value)} /></div>}
            </>
          )}
        </div>
      </ResponsiveModal>
    </div>
  )
}
