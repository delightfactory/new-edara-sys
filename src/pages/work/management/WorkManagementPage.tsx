import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ArrowRight, BrainCircuit, GitBranch, ListChecks, Repeat2, Settings2, UserRoundCog, Workflow } from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import { AI_OPERATIONS_DATA_MODE, AI_OPERATIONS_PREVIEW } from '@/lib/config/features'
import type { WorkManagementTab } from '@/features/work/management-types'
import QueuesManagementPanel from './QueuesManagementPanel'
import ApprovalsManagementPanel from './ApprovalsManagementPanel'
import WorkflowsManagementPanel from './WorkflowsManagementPanel'
import RecurrenceManagementPanel from './RecurrenceManagementPanel'
import PoliciesManagementPanel from './PoliciesManagementPanel'
import WorkContinuityPanel from './WorkContinuityPanel'
import AiOperationsManagementPanel from './AiOperationsManagementPanel'
import './work-management.css'

type ManagementTabId = WorkManagementTab | 'continuity' | 'ai-operations'

const TAB_DEFINITIONS = [
  { id: 'queues' as const, label: 'الطوابير والطلبات', permission: 'work.queues.manage', icon: ListChecks },
  { id: 'approvals' as const, label: 'قوالب الاعتماد', permission: 'work.templates.manage', icon: GitBranch },
  { id: 'workflows' as const, label: 'مسارات العمل', permission: 'work.workflows.manage', icon: Workflow },
  { id: 'recurrence' as const, label: 'الأعمال الدورية', permission: 'work.recurrence.manage', icon: Repeat2 },
  { id: 'policies' as const, label: 'سياسات التشغيل', permission: 'work.policies.manage', icon: Settings2 },
  { id: 'continuity' as const, label: 'استمرارية الأعمال', permission: 'work.items.manage', icon: UserRoundCog },
]

const AI_OPERATIONS_TAB = {
  id: 'ai-operations' as const,
  label: 'AI Operations',
  permission: 'work.policies.manage',
  icon: BrainCircuit,
}

export default function WorkManagementPage() {
  const navigate = useNavigate()
  const can = useAuthStore(state => state.can)
  const aiOperationsAvailable = AI_OPERATIONS_PREVIEW || AI_OPERATIONS_DATA_MODE === 'rpc'
  const tabs = useMemo(() => {
    const definitions = aiOperationsAvailable
      ? [...TAB_DEFINITIONS, AI_OPERATIONS_TAB]
      : TAB_DEFINITIONS
    return definitions.filter(tab => can(tab.permission))
  }, [aiOperationsAvailable, can])
  const [requestedTab, setRequestedTab] = useState<ManagementTabId | null>(null)
  const activeTab = requestedTab && tabs.some(tab => tab.id === requestedTab) ? requestedTab : tabs[0]?.id

  if (!activeTab) {
    return (
      <div className="page-container work-management-page">
        <div className="work-management-empty">
          <Settings2 size={28} aria-hidden="true" />
          <h1>إدارة العمل غير متاحة</h1>
          <p>لا توجد لديك حاليًا صلاحية لإدارة إعدادات Work Management.</p>
          <button type="button" className="btn btn-secondary" onClick={() => navigate('/work')}>
            <ArrowRight size={16} /> العودة للعمل
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="page-container work-management-page animate-enter">
      <header className="work-management-header">
        <div>
          <div className="work-management-eyebrow">Operational Work Management</div>
          <h1 className="page-title">مركز إدارة العمل</h1>
          <p className="page-subtitle">إدارة قواعد التشغيل والقوالب والطوابير واستمرارية المسؤوليات من نقطة واحدة.</p>
        </div>
        <button type="button" className="btn btn-secondary" onClick={() => navigate('/work')}>
          <ArrowRight size={16} /> العودة للعمل
        </button>
      </header>

      <nav className="work-management-tabs" aria-label="أقسام إدارة العمل">
        {tabs.map(tab => {
          const Icon = tab.icon
          const selected = tab.id === activeTab
          return (
            <button
              key={tab.id}
              type="button"
              className={`work-management-tab ${selected ? 'is-active' : ''}`}
              aria-current={selected ? 'page' : undefined}
              onClick={() => setRequestedTab(tab.id)}
            >
              <Icon size={17} aria-hidden="true" />
              <span>{tab.label}</span>
            </button>
          )
        })}
      </nav>

      <main className="work-management-content">
        {activeTab === 'queues' && <QueuesManagementPanel />}
        {activeTab === 'approvals' && <ApprovalsManagementPanel />}
        {activeTab === 'workflows' && <ApprovalsManagementPanel /> === false}
        {activeTab === 'workflows' && <WorkflowsManagementPanel />}
        {activeTab === 'recurrence' && <RecurrenceManagementPanel />}
        {activeTab === 'policies' && <PoliciesManagementPanel />}
        {activeTab === 'continuity' && <WorkContinuityPanel />}
        {activeTab === 'ai-operations' && aiOperationsAvailable && <AiOperationsManagementPanel />}
      </main>
    </div>
  )
}
