import {
  Activity,
  AlertTriangle,
  Bot,
  BrainCircuit,
  CheckCircle2,
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
import { useAiOperationsConsole } from '@/features/ai-operations/hooks'
import type {
  AiOpsCase,
  AiOpsCaseSeverity,
  AiOpsDecisionType,
  AiOpsPlannerRun,
  AiOpsTrustSignal,
} from '@/features/ai-operations/types'
import './ai-operations-management.css'

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
    staged: 'قرارات مبدئية',
    committing: 'قيد التنفيذ',
    completed: 'مكتمل',
    partial: 'مكتمل جزئيًا',
    failed: 'فشل',
    abandoned: 'متروك',
  }
  return labels[status]
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

function CaseCard({ item }: { item: AiOpsCase }) {
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
      </div>
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
              : 'هذه الشاشة متصلة بطبقة AI Operations المعتمدة.'}
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
            <span>{data.attention.length} حالات في Preview</span>
          </div>

          <div className="aiops-case-list">
            {data.attention.map(item => <CaseCard key={item.id} item={item} />)}
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
            <p className="aiops-panel-note">معلومات إدارية لا يمكن استنتاجها بأمان من المعاملات وحدها.</p>
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
                </article>
              ))}
            </div>
          </section>

          <section className="aiops-panel-card aiops-panel-card--safety">
            <div className="aiops-panel-title"><CheckCircle2 size={17} /> حدود التنفيذ الحالية</div>
            <ul className="aiops-safety-list">
              <li>لا Migration مطبقة على الإنتاج.</li>
              <li>لا Cron أو ChatGPT worker مفعّل.</li>
              <li>لا إنشاء Work تلقائي.</li>
              <li>Preview لا يستدعي Supabase AI RPCs.</li>
            </ul>
          </section>
        </aside>
      </div>
    </section>
  )
}
