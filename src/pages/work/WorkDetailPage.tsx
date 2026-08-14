import { useParams } from 'react-router-dom'
import { useWorkItem } from '@/features/work/hooks'
import WorkDetailCorePage from './WorkDetailCorePage'
import WorkDetailExtensions from './WorkDetailExtensions'

export default function WorkDetailPage() {
  const { id } = useParams<{ id: string }>()
  const itemQuery = useWorkItem(id)

  return (
    <>
      <WorkDetailCorePage />
      {itemQuery.data && (
        <div className="work-page" aria-label="التعاون والروابط ودورة حياة العمل">
          <WorkDetailExtensions item={itemQuery.data} />
        </div>
      )}
    </>
  )
}
