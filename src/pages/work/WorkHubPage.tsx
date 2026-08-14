import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  AlertTriangle,
  ArrowLeft,
  CheckCircle2,
  ClipboardCheck,
  Clock3,
  Inbox,
  PlayCircle,
  Plus,
  Search,
  Settings2,
  ShieldCheck,
  Sparkles,
  Users2,
} from 'lucide-react'
import Button from '@/components/ui/Button'
import { useAuthStore } from '@/stores/auth-store'
import WorkItemCard from '@/features/work/components/WorkItemCard'
import { useVisibleWorkItems } from '@/features/work/hooks'
import { useMyActionInbox, useOperationalFlags } from '@/features/work/runtime-hooks'
import type { WorkActionInboxItem, WorkOperationalFlagRow } from '@/features/work/runtime-types'
import type { WorkOperationalFlags } from '@/features/work/types'
import { formatWorkNumber } from '@/features/work/presentation'
import './work.css'
import './work-interactions.css'

type HubMode = 'actions' | 'work' | 'attention'

const MANAGEMENT_PERMISSIONS = [
  'work.queues.manage',
  'work.templates.manage',
  'work.workflows.manage',
  'work.recurrence.manage',
  'work.policies.manage',
]

const TEAM_PERMISSIONS = ['work.items.read_team', 'work.items.read_all', 'work.items.manage_team']

const ACTION_LABELS: Record<WorkActionInboxItem['action_kind'], { label: string; icon: typeof Inbox }> = {
  acknowledge: { label: 'تأكيد استلام', icon: CheckCircle2 },
  execute_next_action: { label: 'تنفيذ الإجراء التالي', icon: PlayCircle },
  follow_up: { label: 'متابعة مستحقة', icon: Clock3 },
  completion_review: { label: 'مراجعة إتمام', icon: ClipboardCheck },
  approval_decision: { label: 'قرار اعتماد', icon: ShieldCheck },
  triage_request: { label: 'فرز طلب', icon: Inbox },
}

function toOperationalFlags(row?: WorkOperationalFlagRow): WorkOperationalFlags | undefined {
  if (!row) return undefined
  return {
    is_overdue: row.is_overdue,
    is_followup_due: row.is_follow_up_due,
    is_blocked: row.is_blocked,
    is_stale: row.is_stale,
    is_at_risk: row.is_at_risk,
    is_escalated: row.is_escalated,
  }
}

function formatDateTime(value: string | null) {
  if (!value) return 'بدون موعد محدد'
  return new Intl.DateTimeFormat('ar-EG-u-nu-latn', {
    timeZone: 'Africa/Cairo',
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(new Date(value))
}

function isPast(value: string | null) {
  return Boolean(value && new Date(value).getTime() < Date.now())
}

export default function WorkHubPage() {
  const navigate = useNavigate()
  const profile = useAuthStore(state => state.profile)
  const can = useAuthStore(state => state.can)
  const [mode, setMode] = useState<HubMode>('actions')
  const [search, setSearch] = useState('')

  const canManageWork = MANAGEMENT_PERMISSIONS.some(permission => can(permission))
  const canViewTeam = TEAM_PERMISSIONS.some(permission => can(permission))
  const canCreateWork = can('work.items.create')

  const { data: actionInbox = [], isLoading: actionLoading } = useMyActionInbox(100)
  const { data: workItems = [], isLoading: workLoading } = useVisibleWorkItems({ limit: 150 })
  const itemIds = useMemo(() => workItems.map(item => item.id), [workItems])
  const { data: flagRows = [] } = useOperationalFlags(itemIds)

  const flagMap = useMemo(
    () => new Map(flagRows.map(row => [row.work_item_id, row])),
    [flagRows],
  )

  const summary = useMemo(() => {
    let overdue = 0
    let blocked = 0
    let atRisk = 0
    for (const row of flagRows) {
      if (row.is_overdue) overdue += 1
      if (row.is_blocked) blocked += 1
      if (row.is_at_risk) atRisk += 1
    }
    return { overdue, blocked, atRisk }
  }, [flagRows])

  const normalizedSearch = search.trim().toLocaleLowerCase('ar')

  const filteredItems = useMemo(() => {
    return workItems.filter(item => {
      if (normalizedSearch) {
        const haystack = `${item.title} ${item.work_number} ${item.next_action_text ?? ''}`.toLocaleLowerCase('ar')
        if (!haystack.includes(normalizedSearch)) return false
      }
      if (mode === 'attention') {
        const flags = flagMap.get(item.id)
        return Boolean(flags?.is_overdue || flags?.is_blocked || flags?.is_at_risk || flags?.is_follow_up_due)
      }
      return true
    })
  }, [workItems, normalizedSearch, mode, flagMap])

  const filteredActions = useMemo(() => {
    if (!normalizedSearch) return actionInbox
    return actionInbox.filter(action => {
      const haystack = `${action.title} ${action.work_number} ${ACTION_LABELS[action.action_kind].label}`.toLocaleLowerCase('ar')
      return haystack.includes(normalizedSearch)
    })
  }, [actionInbox, normalizedSearch])

  return (
    <div className="work-page">
      <section className="work-hero">
        <div className="work-hero-copy">
          <div className="work-hero-kicker"><Sparkles size={15} /> مركز التشغيل اليومي</div>
          <h1 className="work-hero-title">العمل والمتابعات</h1>
          <p className="work-hero-subtitle">
            ابدأ بما يحتاج تدخلك الآن، ثم راقب الأعمال المتأخرة أو المعطلة بدون خلطها بحالة المهمة الأساسية.
          </p>
        </div>
        <div className="work-hero-actions" aria-label="إجراءات مساحة العمل">
          {canViewTeam && <Button variant="secondary" icon={<Users2 size={17} />} onClick={() => navigate('/work/team')}>صورة الفريق</Button>}
          {canManageWork && <Button variant="secondary" icon={<Settings2 size={17} />} onClick={() => navigate('/work/manage')}>إدارة العمل</Button>}
          {canCreateWork && <Button icon={<Plus size={17} />} onClick={() => navigate('/work/new')}>مهمة جديدة</Button>}
        </div>
      </section>

      <section className="work-summary-grid" aria-label="ملخص العمل">
        <button className="work-summary-card" type="button" onClick={() => setMode('actions')}>
          <div className="work-summary-label">مطلوب مني الآن</div>
          <div className="work-summary-value">{actionInbox.length}</div>
          <div className="work-summary-hint">قرارات وتنفيذ ومتابعات مباشرة</div>
        </button>
        <button className="work-summary-card work-summary-card--danger" type="button" onClick={() => setMode('attention')}>
          <div className="work-summary-label">متأخر</div>
          <div className="work-summary-value">{summary.overdue}</div>
          <div className="work-summary-hint">تجاوز الموعد النهائي</div>
        </button>
        <button className="work-summary-card work-summary-card--danger" type="button" onClick={() => setMode('attention')}>
          <div className="work-summary-label">معطل</div>
          <div className="work-summary-value">{summary.blocked}</div>
          <div className="work-summary-hint">اعتماد أو تبعية تمنع التقدم</div>
        </button>
        <button className="work-summary-card work-summary-card--attention" type="button" onClick={() => setMode('attention')}>
          <div className="work-summary-label">معرض للخطر</div>
          <div className="work-summary-value">{summary.atRisk}</div>
          <div className="work-summary-hint">يحتاج تدخلًا قبل أن يتحول لتأخير</div>
        </button>
      </section>

      <section className="work-toolbar" aria-label="تصفية الأعمال">
        <div className="work-segmented" role="group" aria-label="نوع العرض">
          <button type="button" aria-pressed={mode === 'actions'} onClick={() => setMode('actions')}>مطلوب مني الآن</button>
          <button type="button" aria-pressed={mode === 'work'} onClick={() => setMode('work')}>كل الأعمال</button>
          <button type="button" aria-pressed={mode === 'attention'} onClick={() => setMode('attention')}>يحتاج انتباه</button>
        </div>
        <label className="work-search">
          <Search size={16} aria-hidden="true" />
          <input value={search} onChange={event => setSearch(event.target.value)} placeholder="ابحث بالعنوان أو رقم العمل أو الإجراء التالي" aria-label="البحث في الأعمال" />
        </label>
      </section>

      {mode === 'actions' ? (
        <section className="work-section">
          <div className="work-section-header">
            <div>
              <div className="work-section-title"><Inbox size={18} /> مطلوب مني الآن</div>
              <div className="work-section-note">مرتبة حسب أقرب إجراء يحتاج قرارك أو تنفيذك.</div>
            </div>
          </div>

          {actionLoading ? (
            <div className="work-action-list">{[1, 2, 3].map(item => <div key={item} className="skeleton skeleton-row" />)}</div>
          ) : filteredActions.length === 0 ? (
            <div className="work-empty">
              <div className="work-empty-icon"><CheckCircle2 size={22} /></div>
              <strong>لا يوجد إجراء مباشر مطلوب منك الآن</strong>
              <span>يمكنك مراجعة كل الأعمال أو إنشاء مهمة جديدة.</span>
            </div>
          ) : (
            <div className="work-action-list">
              {filteredActions.map(action => {
                const meta = ACTION_LABELS[action.action_kind]
                const Icon = meta.icon
                const late = isPast(action.action_due_at)
                return (
                  <article key={action.inbox_key} className={`work-action-card ${late ? 'work-action-card--late' : ''}`}>
                    <div className="work-action-main">
                      <div className="work-action-topline">
                        <span className="work-action-type"><Icon size={14} /> {meta.label}</span>
                        <span className="work-action-number">{formatWorkNumber(action.work_number)}</span>
                      </div>
                      <h2 className="work-action-title">{action.title}</h2>
                      <div className="work-action-meta">
                        <span><Clock3 size={13} /> {formatDateTime(action.action_due_at)}</span>
                        {late && <span style={{ color: 'var(--color-danger)', fontWeight: 800 }}><AlertTriangle size={13} /> متأخر</span>}
                      </div>
                    </div>
                    <div className="work-action-cta">
                      <Button size="sm" variant={late ? 'primary' : 'secondary'} icon={<ArrowLeft size={15} />} onClick={() => navigate(action.deep_link || `/work/${action.work_item_id}`)}>
                        فتح وتنفيذ
                      </Button>
                    </div>
                  </article>
                )
              })}
            </div>
          )}
        </section>
      ) : (
        <section className="work-section">
          <div className="work-section-header">
            <div>
              <div className="work-section-title">
                {mode === 'attention' ? <AlertTriangle size={18} /> : <ClipboardCheck size={18} />}
                {mode === 'attention' ? 'أعمال تحتاج انتباه' : 'كل الأعمال المتاحة لك'}
              </div>
              <div className="work-section-note">{filteredItems.length} عنصر ظاهر وفق صلاحياتك الحالية.</div>
            </div>
          </div>

          {workLoading ? (
            <div className="work-item-list">{[1, 2, 3, 4].map(item => <div key={item} className="skeleton skeleton-row" />)}</div>
          ) : filteredItems.length === 0 ? (
            <div className="work-empty">
              <div className="work-empty-icon"><ClipboardCheck size={22} /></div>
              <strong>لا توجد أعمال مطابقة</strong>
              <span>غيّر الفلتر أو عبارة البحث.</span>
            </div>
          ) : (
            <div className="work-item-list">
              {filteredItems.map(item => {
                const flags = toOperationalFlags(flagMap.get(item.id))
                const ownerName = item.accountable_owner_user_id === profile?.id ? 'أنا' : 'المسؤول الحالي'
                const assigneeName = item.current_assignee_user_id === profile?.id ? 'أنا' : item.current_assignee_user_id ? 'المكلف الحالي' : 'لم يُسند بعد'
                return (
                  <WorkItemCard key={item.id} item={item} ownerName={ownerName} assigneeName={assigneeName} flags={flags} onClick={() => navigate(`/work/${item.id}`)} />
                )
              })}
            </div>
          )}
        </section>
      )}

      {canCreateWork && (
        <Button className="work-mobile-create" block size="lg" icon={<Plus size={18} />} onClick={() => navigate('/work/new')}>
          مهمة جديدة
        </Button>
      )}
    </div>
  )
}
