import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { AtSign, Send, X } from 'lucide-react'
import { toast } from 'sonner'
import Button from '@/components/ui/Button'
import type { WorkItem } from '@/features/work/types'
import { useAddWorkComment } from '@/features/work/runtime-hooks'
import { listWorkMentionCandidates, type WorkMentionCandidate } from '@/features/work/mentions-api'

export default function WorkMentionComposer({ item }: { item: WorkItem }) {
  const [expanded, setExpanded] = useState(false)
  const [search, setSearch] = useState('')
  const [selected, setSelected] = useState<WorkMentionCandidate[]>([])
  const [body, setBody] = useState('')
  const [kind, setKind] = useState<'comment' | 'progress_update'>('comment')
  const addComment = useAddWorkComment()

  const candidates = useQuery({
    queryKey: ['work', 'mention-candidates', item.id, search],
    queryFn: () => listWorkMentionCandidates(item.id, search),
    enabled: expanded,
    staleTime: 30_000,
  })

  const selectedIds = useMemo(() => new Set(selected.map(person => person.user_id)), [selected])
  const available = (candidates.data ?? []).filter(person => !selectedIds.has(person.user_id))

  const reset = () => {
    setExpanded(false)
    setSearch('')
    setSelected([])
    setBody('')
    setKind('comment')
  }

  const submit = async () => {
    if (!body.trim()) return toast.error('اكتب نص التعليق أو تحديث التقدم')
    if (selected.length === 0) return toast.error('اختر شخصًا واحدًا على الأقل للإشارة إليه')
    try {
      await addComment.mutateAsync({
        workItemId: item.id,
        body: body.trim(),
        commentKind: kind,
        mentionedUserIds: selected.map(person => person.user_id),
      })
      toast.success(kind === 'progress_update' ? 'تم تسجيل التحديث وإرسال الإشارات' : 'تمت إضافة التعليق وإرسال الإشارات')
      reset()
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر إرسال الإشارة')
    }
  }

  return (
    <section className="work-panel">
      <div className="work-panel-header">
        <div className="work-panel-title"><AtSign size={18} /> الإشارات في النقاش</div>
        <span className="work-section-note">يمكن الإشارة فقط إلى شخص لديه صلاحية رؤية هذا العمل</span>
      </div>
      <div className="work-panel-body">
        {!expanded ? (
          <Button size="sm" variant="secondary" icon={<AtSign size={15} />} onClick={() => setExpanded(true)}>
            إضافة تعليق بإشارة
          </Button>
        ) : (
          <div className="work-form">
            <div className="work-segmented" role="group" aria-label="نوع الرسالة ذات الإشارة">
              <button type="button" aria-pressed={kind === 'comment'} onClick={() => setKind('comment')}>تعليق</button>
              <button type="button" aria-pressed={kind === 'progress_update'} onClick={() => setKind('progress_update')}>تحديث تقدم</button>
            </div>

            <div className="work-field">
              <label htmlFor="work-mention-search">ابحث عن الشخص</label>
              <input
                id="work-mention-search"
                value={search}
                onChange={event => setSearch(event.target.value)}
                placeholder="اكتب جزءًا من الاسم"
                autoComplete="off"
              />
              <span className="work-field-hint">القائمة مفلترة Server-side حسب نشاط المستخدم وحقه في رؤية المهمة.</span>
            </div>

            <div className="work-field">
              <label htmlFor="work-mention-candidate">إضافة إشارة</label>
              <select
                id="work-mention-candidate"
                value=""
                onChange={event => {
                  const person = available.find(candidate => candidate.user_id === event.target.value)
                  if (person) setSelected(current => [...current, person])
                }}
              >
                <option value="">{candidates.isLoading ? 'جارٍ تحميل الأشخاص…' : 'اختر شخصًا'}</option>
                {available.map(person => <option key={person.user_id} value={person.user_id}>{person.full_name}</option>)}
              </select>
              {candidates.isError && <span className="work-field-hint">تعذر تحميل قائمة الإشارات المتاحة.</span>}
            </div>

            {selected.length > 0 && (
              <div className="work-detail-actions" aria-label="الأشخاص المشار إليهم">
                {selected.map(person => (
                  <Button
                    key={person.user_id}
                    size="sm"
                    variant="ghost"
                    icon={<X size={13} />}
                    onClick={() => setSelected(current => current.filter(entry => entry.user_id !== person.user_id))}
                  >
                    @{person.full_name}
                  </Button>
                ))}
              </div>
            )}

            <div className="work-field">
              <label htmlFor="work-mention-body">الرسالة *</label>
              <textarea
                id="work-mention-body"
                value={body}
                onChange={event => setBody(event.target.value)}
                placeholder={kind === 'progress_update' ? 'اكتب تحديث التقدم الذي يحتاج انتباه الأشخاص المحددين' : 'اكتب التعليق المرتبط بالإشارة'}
              />
            </div>

            <div className="work-detail-actions">
              <Button
                size="sm"
                icon={<Send size={15} />}
                loading={addComment.isPending}
                disabled={!body.trim() || selected.length === 0}
                onClick={() => void submit()}
              >
                إرسال مع الإشارة
              </Button>
              <Button size="sm" variant="ghost" disabled={addComment.isPending} onClick={reset}>إلغاء</Button>
            </div>
          </div>
        )}
      </div>
    </section>
  )
}
