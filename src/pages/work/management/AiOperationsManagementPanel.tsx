import { useState } from 'react'
import {
  Activity,
  AlertTriangle,
  Bot,
  BrainCircuit,
  CheckCircle2,
  ChevronDown,
  CircleGauge,
  Clock3,
  DatabaseZap,
  Eye,
  FileWarning,
  Gauge,
  Link2,
  ListChecks,
  LockKeyhole,
  PlayCircle,
  RotateCcw,
  ShieldCheck,
  Sparkles,
  UserRoundCog,
} from 'lucide-react'
import { AI_OPERATIONS_DATA_MODE } from '@/lib/config/features'
import {
  useAiOperationsCaseDetail,
  useAiOperationsConsole,
  useAiOperationsDecisionReview,
  useCommitAiOperationsDecision,
  useReviewAiOperationsDecision,
  useSetAiOperationsCaseDisposition,
} from '@/features/ai-operations/hooks'
import type {
  AiOpsBusinessImpact,
  AiOpsCase,
  AiOpsCaseSeverity,
  AiOpsDecisionType,
  AiOpsEstimatedEffort,
  AiOpsPlannerRun,
  AiOpsReversibility,
  AiOpsTrustSignal,
  AiOpsUrgency,
} from '@/features/ai-operations/types'
import {
  AiOperationsCaseContextEditor,
  AiOperationsContextRevokeButton,
  AiOperationsDecisionRevisionEditor,
} from './AiOperationsGovernanceControls'
import './ai-operations-management.css'
import './ai-operations-review.css'

const severityLabels: Record<AiOpsCaseSeverity, string> = {
  low: 'منخفض',
  medium: 'متوسط',
  high: 'مرتفع',
  critical: 'حرج',
}

const decisionLabels: Record<AiOpsDecisionType, string> = {
  IGNORE: 'لا إجراء',
  MONITOR: 'مراقبة',
  INVESTIGATE: 'تحقيق',
  INFORM: 'إحاطة',
  CREATE_WORK: 'إنشاء Work',
  ESCALATE: 'تصعيد',
}

const trustLabels: Record<AiOpsTrustSignal['state'], string> = {
  verified: 'موثوق',
  posting_consistency_only: 'اتساق ترحيل فقط',
  partial: 'جزئي',
  blocked: 'محجوب',
  unknown: 'غير معروف',
}

const evidenceStrengthLabels = {
  direct: 'دليل مباشر',
  supporting: 'دليل مساند',
  contextual: 'سياق',
} as const

const businessImpactLabels: Record<AiOpsBusinessImpact, string> = {
  low: 'محدود',
  medium: 'متوسط',
  high: 'مرتفع',
  critical: 'حرج',
}

const urgencyLabels: Record<AiOpsUrgency, string> = {
  low: 'منخفضة',
  normal: 'عادية',
  high: 'مرتفعة',
  immediate: 'فورية',
}

const reversibilityLabels: Record<AiOpsReversibility, string> = {
  reversible: 'قابل للرجوع',
  review_required: 'يحتاج مراجعة',
  sensitive: 'حساس',
}

const effortLabels: Record<AiOpsEstimatedEffort, string> = {
  S: 'S — تدخل قصير',
  M: 'M — تركيز متوسط',
  L: 'L — عمل يحتاج تخطيط',
}

function formatDateTime(value: string | null) {
  if (!value) return '—'
  return new Intl.DateTimeFormat('ar-EG-u-nu-latn', {
    timeZone: 'Africa/Cairo',
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(new Date(value))
}

function formatBusinessDate(value: string) {
  return new Intl.DateTimeFormat('ar-EG-u-nu-latn', {
    timeZone: 'Africa/Cairo',
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  }).format(new Date(`${value}T12:00:00+03:00`))
}

function runStatusLabel(status: AiOpsPlannerRun['status']) {
  const labels: Record<AiOpsPlannerRun['status'], string> = {
    pending: 'في الانتظار',
    claimed: 'تم الاستلام',
    reasoning: 'قيد التحليل',
    staged: 'بانتظار الإغلاق',
    committing: 'قيد التنفيذ',
    completed: 'مكتمل',
    partial: 'مكتمل جزئيًا',
    failed: 'فشل',
    abandoned: 'متروك',
  }
  return labels[status]
}

function commitBlockMessage(reason?: string) {
  const labels: Record<string, string> = {
    shadow_mode: 'Shadow Mode يمنع إنشاء Work تشغيلية.',
    planner_disabled: 'الـPlanner متوقف؛ لا يمكن تنفيذ قرار جديد.',
    current_state_changed: 'تغير الواقع التشغيلي منذ التحليل؛ تم إيقاف التنفيذ ويجب انتظار تحليل جديد.',
    human_approval_required: 'القرار يحتاج موافقة بشرية أولًا.',
    decision_not_validated: 'القرار لم يجتز التحقق الحالي.',
    source_key_collision: 'وجد تعارض غير متوقع مع Work أخرى؛ تم إيقاف التنفيذ احترازيًا.',
    bridge_supports_create_work_only: 'الـslice الحالي ينفذ CREATE_WORK فقط.',
    work_actor_became_unavailable: 'أحد أطراف المسؤولية لم يعد متاحًا للتكليف.',
    proposed_due_at_not_future: 'الموعد المقترح لم يعد في المستقبل.',
    explicit_owner_assignee_and_due_required: 'ينقص القرار مالك أو منفذ أو موعد صريح.',
    frozen_escalation_target_mismatch: 'تغيرت Work المستهدفة منذ التحليل؛ أوقف التنفيذ وانتظر تحليلًا جديدًا.',
    active_coverage_or_work_health_recovery_collision_now: 'يوجد بالفعل إجراء تغطية أو معالجة نشط لنفس Work؛ لن يتم إنشاء إجراء مكرر.',
    assignee_has_frozen_hr_unavailability_conflict: 'المنفذ المقترح لديه تعارض توافر موثق داخل نفس Snapshot.',
  }
  return reason ? (labels[reason] ?? `تم إيقاف التنفيذ: ${reason}`) : 'تم إيقاف التنفيذ احترازيًا.'
}

function TrustBadge({ signal }: { signal: AiOpsTrustSignal }) {
  return (
    <div className={`aiops-trust aiops-trust--${signal.state}`} title={signal.note ?? undefined}>
      <ShieldCheck size={14} aria-hidden="true" />
      <span>{signal.domain}</span>
      <strong>{trustLabels[signal.state]}</strong>
    </div>
  )
}

function DecisionReviewPanel({
  caseId,
  isPreview,
  plannerEnabled,
  shadowMode,
}: {
  caseId: string
  isPreview: boolean
  plannerEnabled: boolean
  shadowMode: boolean
}) {
  const [reviewNote, setReviewNote] = useState('')
  const [actionMessage, setActionMessage] = useState<string | null>(null)
  const [actionError, setActionError] = useState(false)
  const reviewQuery = useAiOperationsDecisionReview(caseId, !isPreview)
  const reviewMutation = useReviewAiOperationsDecision()
  const commitMutation = useCommitAiOperationsDecision()
  const dispositionMutation = useSetAiOperationsCaseDisposition()
  const decision = reviewQuery.data?.decision ?? null
  const busy = reviewMutation.isPending || commitMutation.isPending || dispositionMutation.isPending

  if (isPreview) {
    return (
      <div className="aiops-review-readonly">
        Preview للقراءة فقط. الموافقة والرفض وإنشاء Work لا تُحاكى محليًا ولا تستدعي Supabase.
      </div>
    )
  }

  if (reviewQuery.isLoading) {
    return <div className="aiops-detail-loading">جاري تحميل حالة المراجعة والتنفيذ...</div>
  }

  if (reviewQuery.error) {
    return (
      <div className="aiops-detail-error">
        <AlertTriangle size={14} />
        {reviewQuery.error instanceof Error ? reviewQuery.error.message : 'تعذر تحميل حالة القرار.'}
      </div>
    )
  }

  if (!decision) {
    return <div className="aiops-review-readonly">لم يصدر قرار Planner محفوظ لهذه الحالة بعد.</div>
  }

  const canReview = plannerEnabled
    && !shadowMode
    && decision.run_status === 'staged'
    && decision.review_state === null
    && decision.validation_state !== 'rejected'

  const canRevise = plannerEnabled
    && !shadowMode
    && decision.run_status === 'staged'
    && decision.review_state === null
    && decision.commit_status !== 'committed'
    && decision.decision_type === 'CREATE_WORK'

  const canCommit = plannerEnabled
    && !shadowMode
    && decision.run_status === 'staged'
    && ['CREATE_WORK', 'ESCALATE'].includes(decision.decision_type)
    && decision.review_state === 'approved'
    && decision.validation_state === 'validated'
    && decision.commit_status !== 'committed'

  const canDisposition = plannerEnabled
    && !shadowMode
    && decision.run_status === 'staged'
    && decision.review_state !== 'approved'
    && decision.commit_status !== 'committed'

  const validationTone = decision.validation_state === 'validated'
    ? 'good'
    : decision.validation_state === 'rejected' ? 'danger' : 'warning'
  const reviewTone = decision.review_state === 'approved'
    ? 'good'
    : decision.review_state === 'rejected' ? 'danger' : 'warning'
  const commitTone = decision.commit_status === 'committed'
    ? 'good'
    : ['rejected', 'failed'].includes(decision.commit_status) ? 'danger' : 'warning'

  const handleReview = async (reviewState: 'approved' | 'rejected') => {
    setActionMessage(null)
    setActionError(false)
    try {
      const result = await reviewMutation.mutateAsync({
        decisionId: decision.decision_id,
        reviewState,
        reviewNote,
      })
      if (result.approval_blocked) {
        setActionError(true)
        setActionMessage('تغير الواقع التشغيلي منذ التحليل؛ تم رفض صلاحية القرار للتنفيذ بدون إنشاء أي Work.')
        return
      }
      setReviewNote('')
      setActionMessage(
        reviewState === 'approved'
          ? ['CREATE_WORK', 'ESCALATE'].includes(decision.decision_type)
            ? 'تم اعتماد القرار بعد إعادة التحقق. لم يحدث تنفيذ تشغيلي بعد؛ التنفيذ خطوة مستقلة أدناه.'
            : 'تم اعتماد القرار وإغلاق خطوة المراجعة بدون تنفيذ تشغيلي تلقائي.'
          : 'تم رفض القرار وتسجيل المراجعة كسجل غير قابل للاستبدال.',
      )
    } catch (error) {
      setActionError(true)
      setActionMessage(error instanceof Error ? error.message : 'تعذر تسجيل المراجعة.')
    }
  }

  const handleCommit = async () => {
    setActionMessage(null)
    setActionError(false)
    try {
      const result = await commitMutation.mutateAsync({ decisionId: decision.decision_id })
      if (!result.committed) {
        setActionError(true)
        setActionMessage(commitBlockMessage(result.reason))
        return
      }
      const isEscalation = result.operational_mutation === 'work_escalation_overlay'
      setActionMessage(
        isEscalation
          ? result.work_number
            ? `تم تنفيذ التصعيد على Work #${result.work_number} بعد إعادة التحقق داخل نفس معاملة التنفيذ.`
            : 'تم تنفيذ التصعيد المعتمد بعد إعادة التحقق داخل نفس معاملة التنفيذ.'
          : result.work_number
            ? `تم إنشاء Work #${result.work_number} بعد إعادة التحقق داخل نفس معاملة التنفيذ.`
            : 'تم إنشاء Work المعتمدة بعد إعادة التحقق داخل نفس معاملة التنفيذ.',
      )
    } catch (error) {
      setActionError(true)
      setActionMessage(error instanceof Error ? error.message : 'تعذر إنشاء Work المعتمدة.')
    }
  }

  const handleDisposition = async (action: 'snooze' | 'dismiss') => {
    setActionMessage(null)
    setActionError(false)
    try {
      const hours = action === 'snooze' ? 24 : 24 * 7
      const until = new Date(Date.now() + hours * 60 * 60 * 1000).toISOString()
      await dispositionMutation.mutateAsync({ caseId, action, until, note: reviewNote })
      setReviewNote('')
      setActionMessage(action === 'snooze'
        ? 'تم تأجيل الحالة 24 ساعة مع حفظ القرار الحالي كسياق للمراجعة القادمة.'
        : 'تم استبعاد الحالة مؤقتًا لمدة 7 أيام؛ أي وقائع جديدة بعد انتهاء المدة ستسمح بإعادة تقييمها.')
    } catch (error) {
      setActionError(true)
      setActionMessage(error instanceof Error ? error.message : 'تعذر تحديث حالة AI Operations.')
    }
  }

  return (
    <section className="aiops-review-live" aria-label="المراجعة البشرية للقرار">
      <div className="aiops-review-live-head">
        <div>
          <h4>بوابة المراجعة والتنفيذ</h4>
          <p>الموافقة لا تنشئ Work. التنفيذ أمر مستقل ويعيد فحص الواقع التشغيلي داخل نفس المعاملة.</p>
        </div>
        <span className="aiops-decision-chip">{decisionLabels[decision.decision_type]}</span>
      </div>

      <div className="aiops-state-row">
        <span className={`aiops-state-chip aiops-state-chip--${validationTone}`}>
          تحقق: {decision.validation_state === 'validated' ? 'سليم حاليًا' : decision.validation_state === 'rejected' ? 'مرفوض / قديم' : 'بانتظار التحقق'}
        </span>
        <span className={`aiops-state-chip aiops-state-chip--${reviewTone}`}>
          مراجعة: {decision.review_state === 'approved' ? 'معتمد' : decision.review_state === 'rejected' ? 'مرفوض' : 'لم يُراجع'}
        </span>
        <span className={`aiops-state-chip aiops-state-chip--${commitTone}`}>
          تنفيذ: {decision.commit_status === 'committed' ? 'تم التنفيذ' : decision.commit_status === 'rejected' ? 'موقوف' : decision.commit_status === 'failed' ? 'فشل' : 'لم يُنفذ'}
        </span>
        <span className="aiops-state-chip">Run: {runStatusLabel(decision.run_status)} · {decision.run_checkpoint}</span>
      </div>

      <div className="aiops-review-grid">
        <div className="aiops-review-field">
          <span>Accountable Owner</span>
          <strong>{decision.recommended_owner_label ?? 'غير محدد'}</strong>
        </div>
        <div className="aiops-review-field">
          <span>Assignee / المنفذ</span>
          <strong>{decision.recommended_assignee_label ?? 'غير محدد'}</strong>
        </div>
        <div className="aiops-review-field">
          <span>الموعد المقترح</span>
          <strong>{formatDateTime(decision.due_at)}</strong>
        </div>
        <div className="aiops-review-field">
          <span>موعد المراجعة</span>
          <strong>{formatDateTime(decision.review_after)}</strong>
        </div>
        <div className="aiops-review-field">
          <span>الأثر التجاري</span>
          <strong>{decision.business_impact ? businessImpactLabels[decision.business_impact] : '—'}</strong>
        </div>
        <div className="aiops-review-field">
          <span>الإلحاح</span>
          <strong>{decision.urgency ? urgencyLabels[decision.urgency] : '—'}</strong>
        </div>
        <div className="aiops-review-field">
          <span>اكتمال الأدلة</span>
          <strong>{decision.evidence_completeness == null ? '—' : `${Math.round(decision.evidence_completeness * 100)}%`}</strong>
        </div>
        <div className="aiops-review-field">
          <span>الـEffort</span>
          <strong>{decision.estimated_effort ? effortLabels[decision.estimated_effort] : '—'}</strong>
        </div>
        <div className="aiops-review-field">
          <span>قابلية الرجوع</span>
          <strong>{decision.reversibility ? reversibilityLabels[decision.reversibility] : '—'}</strong>
        </div>
        <div className="aiops-review-field">
          <span>الثقة</span>
          <strong>{decision.confidence == null ? '—' : `${Math.round(decision.confidence * 100)}%`}</strong>
        </div>
        <div className="aiops-review-field aiops-review-field--wide">
          <span>الإجراء التالي</span>
          <p>{decision.next_action_text ?? 'لا يوجد إجراء تنفيذي مقترح.'}</p>
        </div>
        <div className="aiops-review-field aiops-review-field--wide">
          <span>النتيجة المتوقعة</span>
          <p>{decision.expected_outcome ?? 'لا توجد نتيجة تنفيذية محددة لهذا النوع من القرار.'}</p>
        </div>
        <div className="aiops-review-field aiops-review-field--wide">
          <span>إشارة النجاح التي سنراجعها</span>
          <p>{decision.success_signal ?? '—'}</p>
        </div>
        <div className="aiops-review-field aiops-review-field--wide">
          <span>السبب الآمن الذي يصل للموظف</span>
          <p>{decision.employee_safe_reason ?? '—'}</p>
        </div>
      </div>

      {decision.validation_codes.length > 0 && (
        <div className="aiops-validation-codes" aria-label="أسباب رفض التحقق">
          {decision.validation_codes.map((code, index) => (
            <span className="aiops-validation-code" key={`${code}-${index}`}>{code}</span>
          ))}
        </div>
      )}

      {decision.review_state && (
        <div className="aiops-reviewed-box">
          <strong>{decision.review_state === 'approved' ? 'اعتماد بشري مسجل' : 'رفض بشري مسجل'}</strong>
          <span>{decision.reviewed_by_label ?? 'مراجع مخول'} · {formatDateTime(decision.reviewed_at)}</span>
          {decision.review_note && <span>{decision.review_note}</span>}
        </div>
      )}

      {decision.committed_work_number && (
        <div className="aiops-reviewed-box">
          <strong>{decision.decision_type === 'ESCALATE' ? 'Work المصعّدة' : 'Work الناتجة'}: #{decision.committed_work_number}</strong>
          <span>تم التنفيذ: {formatDateTime(decision.committed_at)}</span>
        </div>
      )}

      {shadowMode && (
        <div className="aiops-review-readonly">Shadow Mode مفعّل: القرارات تُقاس كتوصيات تحليلية فقط ولا تدخل مسار الاعتماد أو التنفيذ.</div>
      )}
      {!plannerEnabled && (
        <div className="aiops-review-readonly">الـPlanner متوقف حاليًا؛ لا يمكن اعتماد أو تنفيذ قرار جديد.</div>
      )}

      {canReview && (
        <div className="aiops-review-note">
          <label htmlFor={`aiops-review-note-${decision.decision_id}`}>ملاحظة المراجع — اختيارية</label>
          <textarea
            id={`aiops-review-note-${decision.decision_id}`}
            value={reviewNote}
            maxLength={1000}
            onChange={event => setReviewNote(event.target.value)}
            placeholder="سجل فقط ما يضيف سياقًا إداريًا مفيدًا للقرار."
          />
        </div>
      )}

      {canRevise && <AiOperationsDecisionRevisionEditor decision={decision} disabled={busy} />}

      <div className="aiops-review-actions">
        {canReview && (
          <>
            <button type="button" className="btn btn-primary" disabled={busy} onClick={() => handleReview('approved')}>
              <CheckCircle2 size={16} /> اعتماد القرار
            </button>
            <button type="button" className="btn btn-secondary" disabled={busy} onClick={() => handleReview('rejected')}>
              <AlertTriangle size={16} /> رفض القرار
            </button>
          </>
        )}
        {canCommit && (
          <button type="button" className="btn btn-primary" disabled={busy} onClick={handleCommit}>
            <PlayCircle size={16} /> {decision.decision_type === 'ESCALATE' ? 'تنفيذ التصعيد المعتمد' : 'إنشاء Work المعتمدة'}
          </button>
        )}
        {canDisposition && (
          <>
            <button type="button" className="btn btn-secondary" disabled={busy} onClick={() => handleDisposition('snooze')}>
              <Clock3 size={16} /> تأجيل 24 ساعة
            </button>
            <button type="button" className="btn btn-secondary" disabled={busy} onClick={() => handleDisposition('dismiss')}>
              <RotateCcw size={16} /> استبعاد مؤقت 7 أيام
            </button>
          </>
        )}
      </div>

      {actionMessage && (
        <div className={`aiops-review-message${actionError ? ' aiops-review-message--danger' : ''}`} role="status">
          {actionMessage}
        </div>
      )}
    </section>
  )
}

function CaseCard({
  item,
  isPreview,
  plannerEnabled,
  shadowMode,
}: {
  item: AiOpsCase
  isPreview: boolean
  plannerEnabled: boolean
  shadowMode: boolean
}) {
  const [expanded, setExpanded] = useState(false)
  const detailQuery = useAiOperationsCaseDetail(item.id, expanded)
  const detail = detailQuery.data

  return (
    <article className={`aiops-case aiops-case--${item.severity}`}>
      <div className="aiops-case-head">
        <div>
          <div className="aiops-case-kicker">
            <span className={`aiops-severity aiops-severity--${item.severity}`}>{severityLabels[item.severity]}</span>
            <span>{item.domain}</span>
            <span>{item.entity_label}</span>
          </div>
          <h3>{item.title}</h3>
        </div>
        {item.recommended_decision && (
          <span className="aiops-decision-chip">{decisionLabels[item.recommended_decision]}</span>
        )}
      </div>

      <p className="aiops-case-reason">{item.reason}</p>

      <dl className="aiops-case-grid">
        <div>
          <dt>القيمة / الأثر</dt>
          <dd>{item.value_label ?? 'غير مالي'}</dd>
        </div>
        <div>
          <dt>المسؤولية المرجحة</dt>
          <dd>{item.responsibility_label ?? 'تحتاج تحقيق'}</dd>
        </div>
        <div>
          <dt>أساس الترجيح</dt>
          <dd>{item.responsibility_basis ?? 'لا يوجد دليل كافٍ بعد'}</dd>
        </div>
        <div>
          <dt>آخر تحديث للمصدر</dt>
          <dd>{formatDateTime(item.source_as_of)}</dd>
        </div>
      </dl>

      <div className="aiops-case-footer">
        {item.has_existing_work ? (
          <span className="aiops-collision aiops-collision--linked">
            <Link2 size={14} /> مرتبط بالفعل بـ Work {item.linked_work_number ? `#${item.linked_work_number}` : ''}
          </span>
        ) : (
          <span className="aiops-collision"><ListChecks size={14} /> لا يوجد Work متعارض حاليًا</span>
        )}
        <span><Clock3 size={14} /> ظهر أول مرة {formatDateTime(item.first_seen_at)}</span>
        <button
          type="button"
          className="aiops-evidence-toggle"
          aria-expanded={expanded}
          onClick={() => setExpanded(value => !value)}
        >
          <ChevronDown size={14} className={expanded ? 'is-open' : undefined} />
          {expanded ? 'إخفاء أدلة القرار' : 'راجع أدلة القرار'}
        </button>
      </div>

      {expanded && (
        <div className="aiops-case-detail">
          {detailQuery.isLoading && <div className="aiops-detail-loading">جاري تحميل الأدلة...</div>}
          {detailQuery.error && (
            <div className="aiops-detail-error">
              <AlertTriangle size={14} /> {detailQuery.error instanceof Error ? detailQuery.error.message : 'تعذر تحميل الأدلة.'}
            </div>
          )}
          {detail && (
            <>
              <div className="aiops-detail-section">
                <div className="aiops-detail-title">الحقائق المستخدمة</div>
                <div className="aiops-facts-grid">
                  {detail.facts.map(fact => (
                    <div key={fact.label}>
                      <span>{fact.label}</span>
                      <strong>{fact.value}</strong>
                    </div>
                  ))}
                </div>
              </div>

              <div className="aiops-detail-section">
                <div className="aiops-detail-title">أدلة المسؤولية — لا يوجد Routing جامد</div>
                <div className="aiops-evidence-list">
                  {detail.responsibility_evidence.map((evidence, index) => (
                    <article key={`${evidence.evidence_type}-${index}`} className={`aiops-evidence aiops-evidence--${evidence.strength}`}>
                      <div className="aiops-evidence-head">
                        <strong>{evidence.label}</strong>
                        <span>{evidenceStrengthLabels[evidence.strength]}</span>
                      </div>
                      <div className="aiops-evidence-user">{evidence.user_label ?? 'بدون مستخدم محدد'}</div>
                      {evidence.note && <p>{evidence.note}</p>}
                    </article>
                  ))}
                </div>
              </div>

              <div className="aiops-decision-review">
                <div>
                  <span>القرار المقترح</span>
                  <strong>{detail.decision_review.decision_type ? decisionLabels[detail.decision_review.decision_type] : 'لم يُحسم بعد'}</strong>
                </div>
                <p>{detail.decision_review.concise_rationale}</p>
                {detail.decision_review.why_this_owner && <p><b>لماذا هذه المسؤولية؟</b> {detail.decision_review.why_this_owner}</p>}
                {detail.decision_review.why_now && <p><b>لماذا الآن؟</b> {detail.decision_review.why_now}</p>}
                <div className="aiops-decision-meta">
                  <span>الثقة: {detail.decision_review.confidence == null ? '—' : `${Math.round(detail.decision_review.confidence * 100)}%`}</span>
                  <span>{detail.decision_review.requires_human_review ? 'يتطلب مراجعة بشرية قبل أي تنفيذ' : 'قرار تحليلي غير تنفيذي'}</span>
                </div>
              </div>

              <AiOperationsCaseContextEditor item={item} disabled={isPreview} />

              <DecisionReviewPanel
                caseId={item.id}
                isPreview={isPreview}
                plannerEnabled={plannerEnabled}
                shadowMode={shadowMode}
              />
            </>
          )}
        </div>
      )}
    </article>
  )
}

export default function AiOperationsManagementPanel() {
  const { data, isLoading, error, refetch, isFetching } = useAiOperationsConsole(true)

  if (isLoading) {
    return (
      <section className="aiops-shell" aria-busy="true">
        <div className="aiops-skeleton aiops-skeleton--hero" />
        <div className="aiops-grid aiops-grid--metrics">
          {[1, 2, 3, 4].map(item => <div key={item} className="aiops-skeleton aiops-skeleton--card" />)}
        </div>
      </section>
    )
  }

  if (error || !data) {
    return (
      <section className="aiops-shell">
        <div className="aiops-error">
          <FileWarning size={28} />
          <div>
            <h2>تعذر فتح AI Operations Console</h2>
            <p>{error instanceof Error ? error.message : 'تعذر تحميل بيانات الشاشة.'}</p>
          </div>
          <button type="button" className="btn btn-secondary" onClick={() => refetch()} disabled={isFetching}>
            <RotateCcw size={16} /> إعادة المحاولة
          </button>
        </div>
      </section>
    )
  }

  const isPreview = data.mode === 'preview'

  return (
    <section className="aiops-shell">
      <div className="aiops-preview-banner" role="status">
        <Eye size={18} aria-hidden="true" />
        <div>
          <strong>{isPreview ? 'Preview آمن — بدون اتصال بقاعدة AI Operations' : 'RPC Mode'}</strong>
          <span>
            {isPreview
              ? 'كل الأرقام والأسماء داخل هذه الشاشة بيانات مراجعة ثابتة. لا يتم قراءة أو كتابة أي بيانات تشغيلية.'
              : 'هذه الشاشة متصلة بطبقة AI Operations المعتمدة؛ أي تنفيذ يظل خلف مراجعة بشرية وأمر منفصل.'}
          </span>
        </div>
        <span className="aiops-mode-chip">{AI_OPERATIONS_DATA_MODE.toUpperCase()}</span>
      </div>

      <header className="aiops-hero">
        <div className="aiops-hero-icon"><BrainCircuit size={26} /></div>
        <div className="aiops-hero-copy">
          <div className="aiops-eyebrow">Delight AI Operations Planner</div>
          <h2>غرفة التحكم في التخطيط التشغيلي الذكي</h2>
          <p>
            تعرض فقط الحالات ذات القيمة، جودة الأدلة، تعارضها مع Work القائم، وحالة تشغيل الـPlanner — بدل إغراق الإدارة بصفوف وتقارير خام.
          </p>
        </div>
        <div className="aiops-safety-stack">
          <span><LockKeyhole size={14} /> Planner: {data.settings.planner_enabled ? 'مفعّل' : 'متوقف'}</span>
          <span><Eye size={14} /> Shadow: {data.settings.shadow_mode ? 'مفعّل' : 'متوقف'}</span>
          <span><DatabaseZap size={14} /> Auto-commit: {data.settings.auto_commit_enabled ? 'مفعّل' : 'متوقف'}</span>
        </div>
      </header>

      <div className="aiops-section-heading">
        <div>
          <h3><CircleGauge size={18} /> نبض التشغيل</h3>
          <p>مؤشرات مختصرة تساعد على تحديد أين يستحق التحليل الأعمق.</p>
        </div>
        <span>As of {formatDateTime(data.data_as_of)}</span>
      </div>

      <div className="aiops-grid aiops-grid--metrics">
        {data.pulse.map(metric => (
          <article key={metric.key} className={`aiops-metric aiops-metric--${metric.tone ?? 'neutral'}`}>
            <div className="aiops-metric-label">{metric.label}</div>
            <div className="aiops-metric-value">{metric.value}</div>
            <div className="aiops-metric-hint">{metric.hint ?? '—'}</div>
          </article>
        ))}
      </div>

      <div className="aiops-trust-row" aria-label="جودة مصادر البيانات">
        {data.trust.map(signal => <TrustBadge key={signal.domain} signal={signal} />)}
      </div>

      <div className="aiops-layout">
        <div className="aiops-main-column">
          <div className="aiops-section-heading">
            <div>
              <h3><Sparkles size={18} /> حالات تستحق الانتباه</h3>
              <p>Case ≠ Task. وجود الحالة لا يعني تلقائيًا إنشاء عمل جديد.</p>
            </div>
            <span>{data.attention.length} حالات {isPreview ? 'في Preview' : 'في التحليل الحالي'}</span>
          </div>

          <div className="aiops-case-list">
            {data.attention.map(item => (
              <CaseCard
                key={item.id}
                item={item}
                isPreview={isPreview}
                plannerEnabled={data.settings.planner_enabled}
                shadowMode={data.settings.shadow_mode}
              />
            ))}
          </div>
        </div>

        <aside className="aiops-side-column">
          <section className="aiops-panel-card">
            <div className="aiops-panel-title"><Activity size={17} /> موثوقية التشغيل</div>
            <div className="aiops-run-list">
              {data.recent_runs.map(run => (
                <article className="aiops-run" key={run.id}>
                  <div className="aiops-run-head">
                    <strong>{formatBusinessDate(run.business_date)}</strong>
                    <span className={`aiops-run-status aiops-run-status--${run.status}`}>{runStatusLabel(run.status)}</span>
                  </div>
                  <div className="aiops-run-stats">
                    <span><Gauge size={13} /> {run.cases_seen} حالة</span>
                    <span><Bot size={13} /> {run.decisions_count} قرار</span>
                    <span><PlayCircle size={13} /> {run.work_created_count} Work</span>
                  </div>
                  <div className="aiops-run-meta">Checkpoint: {run.checkpoint} · محاولة {run.attempt_no}</div>
                  {run.error_message && <div className="aiops-run-warning"><AlertTriangle size={13} /> {run.error_message}</div>}
                </article>
              ))}
            </div>
          </section>

          <section className="aiops-panel-card">
            <div className="aiops-panel-title"><UserRoundCog size={17} /> السياق التشغيلي</div>
            <p className="aiops-panel-note">معلومات إدارية لا يمكن استنتاجها بأمان من المعاملات وحدها. كل سياق بشري جديد مؤقت ومراجعته لا تمنح أي صلاحية تنفيذية.</p>
            <div className="aiops-context-list">
              {data.context.map(item => (
                <article key={item.id} className="aiops-context-item">
                  <div className="aiops-context-head">
                    <strong>{item.subject_label}</strong>
                    <span>{item.confidence_class}</span>
                  </div>
                  <p>{item.summary}</p>
                  <div className="aiops-context-meta">
                    {item.review_on && <span>مراجعة: {item.review_on}</span>}
                    {item.valid_until && <span>ينتهي: {formatDateTime(item.valid_until)}</span>}
                  </div>
                  <AiOperationsContextRevokeButton item={item} disabled={isPreview} />
                </article>
              ))}
            </div>
          </section>

          <section className="aiops-panel-card aiops-panel-card--safety">
            <div className="aiops-panel-title"><CheckCircle2 size={17} /> حدود التنفيذ الحالية</div>
            <ul className="aiops-safety-list">
              {isPreview ? (
                <>
                  <li>Preview لا يستدعي Supabase AI RPCs.</li>
                  <li>لا يمكن اعتماد أو رفض أو تعديل أو تنفيذ قرارات من Preview.</li>
                  <li>البيانات المعروضة Fixtures ثابتة للمراجعة البصرية فقط.</li>
                </>
              ) : (
                <>
                  <li>الموافقة البشرية لا تنشئ Work تلقائيًا.</li>
                  <li>تعديل القرار ينشئ Revision جديدة ويعيد التحقق ولا يمسح القرار الأصلي.</li>
                  <li>السياق الإداري بيانات توجيه مؤقتة وليس أمر تنفيذ.</li>
                  <li>CREATE_WORK وESCALATE لا يُنفذان إلا بعد اعتماد بشري صريح وخطوة تنفيذ مستقلة.</li>
                  <li>التنفيذ يعيد التحقق من الواقع داخل نفس المعاملة.</li>
                  <li>Planner Off وShadow Mode يعملان كـKill Switch قبل أي Work جديدة.</li>
                </>
              )}
            </ul>
          </section>
        </aside>
      </div>
    </section>
  )
}
