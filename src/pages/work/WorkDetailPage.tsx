import { useParams } from 'react-router-dom'
import { useWorkItem } from '@/features/work/hooks'
import WorkDetailCorePage from './WorkDetailCorePage'
import WorkDetailExtensions from './WorkDetailExtensions'
import WorkMentionComposer from './WorkMentionComposer'
import WorkDetailAdministration from './WorkDetailAdministration'
import WorkDueGovernance from './WorkDueGovernance'

export default function WorkDetailPage() {
  const { id } = useParams<{ id: string }>()
  const itemQuery = useWorkItem(id)

  return (
    <>
      <WorkDetailCorePage />
      {itemQuery.data && (
        <div className="work-page" aria-label="التعاون والإدارة ودورة حياة العمل">
          <WorkDetailExtensions item={itemQuery.data} />
          <WorkMentionComposer item={itemQuery.data} />
          <WorkDetailAdministration item={itemQuery.data} />
          <WorkDueGovernance item={itemQuery.data} />
        </div>
      )}
    </>
  )
}
