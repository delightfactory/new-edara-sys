import { useMemo, useState, type FormEvent } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, CheckCircle2, Loader2, RefreshCw, UserRoundCog } from 'lucide-react'
import { toast } from 'sonner'
import {
  bulkReassignOrphanedWork,
  listOrphanedWorkAssignments,
  listWorkContinuityCandidates,
} from '@/features/work/continuity-api'

const REASON_LABELS: Record<string, string> = {
  profile_inactive: 'حساب المستخدم غير نشط',
  employee_inactive: 'الموظف غير نشط في HR',
  unavailable: 'المستخدم غير متاح للعمل',
}

export default function WorkContinuityPanel() {
  const queryClient = useQueryClient()
  const [selectedSourceId, setSelectedSourceId] = useState('')
  const [replacementUserId, setReplacementUserId] = useState('')
  const [reason, setReason] = useState('')

  const orphans = useQuery({
    queryKey: ['work', 'management', 'continuity', 'orphans'],
    queryFn: listOrphanedWorkAssignments,
  })
  const candidates = useQuery({
    queryKey: ['work', 'management', 'continuity', 'candidates'],
    queryFn: () => listWorkContinuityCandidates(),
  })
  const selectedSource = useMemo(
    () => orphans.data?.find(row => row.user_id === selectedSourceId) ?? null,
    [orphans.data, selectedSourceId],
  )

  const mutation = useMutation({
    mutationFn: bulkReassignOrphanedWork,
    onSuccess: async result => {
      toast.success(`تمت إعادة إسناد ${result.work_item_count} عمل نشط مع تسجيل التغييرات في السجل`)
      setSelectedSourceId('')
      setReplacementUserId('')
      setReason('')
      await queryClient.invalidateQueries({ queryKey: ['work'] })
    },
  })

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (!selectedSource) return toast.error('اختر المستخدم المطلوب معالجة أعماله')
    if (!replacementUserId) return toast.error('اختر المستخدم البديل')
    if (!reason.trim()) return toast.error('سبب إعادة الإسناد مطلوب')
    if (replacementUserId === selectedSource.user_id) return toast.error('يجب اختيار مستخدم بديل مختلف')
    try {
      await mutation.mutateAsync({
        inactiveUserId: selectedSource.user_id,
        replacementUserId,
        reason: reason.trim(),
      })
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر تنفيذ إعادة الإسناد')
    }
  }

  const refresh = () => {
    void orphans.refetch()
    void candidates.refetch()
  }

  if (orphans.isLoading) return <div className="work-management-loading"><Loader2 className="animate-spin" /> جارٍ فحص استمرارية الأعمال…</div>
  if (orphans.error) return <div className="work-management-error"><p>تعذر فحص الأعمال المرتبطة بالمستخدمين غير النشطين.</p><button type="button" className="btn btn-secondary" onClick={refresh}><RefreshCw size={16} /> إعادة المحاولة</button></div>

  const rows = orphans.data ?? []

  return (
    <section className="work-management-panel" aria-labelledby="work-continuity-title">
      <div className="work-management-panel-header">
        <div>
          <h2 id="work-continuity-title">استمرارية الأعمال</h2>
          <p className="page-subtitle">يكشف الأعمال النشطة التي ظل مالكها أو منفذها مرتبطًا بحساب أو موظف خرج من الخدمة، ويعيد إسناد المسؤولية دون تغيير التاريخ الأصلي.</p>
        </div>
        <button type="button" className="btn btn-secondary" onClick={refresh}><RefreshCw size={16} /> تحديث الفحص</button>
      </div>

      {rows.length === 0 ? (
        <div className="work-management-alert">
          <CheckCircle2 size={22} aria-hidden="true" />
          <div><strong>لا توجد أعمال يتيمة حاليًا</strong><div className="work-management-card-subtitle">كل الأعمال النشطة مرتبطة بمستخدمين متاحين للعمل.</div></div>
        </div>
      ) : (
        <>
          <div className="work-management-alert is-warning">
            <AlertTriangle size={22} aria-hidden="true" />
            <div><strong>تم العثور على {rows.length} مستخدم غير متاح ما زالت له مسؤوليات تشغيلية</strong><div className="work-management-card-subtitle">المعالجة تغيّر فقط المالك النهائي والمنفذ الحالي للأعمال المفتوحة؛ المنشئ وطالب الخدمة والسجل التاريخي لا يتغيرون.</div></div>
          </div>

          <div className="work-management-grid">
            {rows.map(row => (
              <article className="work-management-card" key={row.user_id}>
                <div className="work-management-card-head">
                  <div><div className="work-management-card-title">{row.full_name}</div><div className="work-management-card-subtitle">{REASON_LABELS[row.orphan_reason] ?? row.orphan_reason}</div></div>
                  <UserRoundCog size={20} aria-hidden="true" />
                </div>
                <div className="work-management-meta">
                  <span className="work-management-pill is-warning">{row.work_item_count} عمل نشط</span>
                  <span className="work-management-pill">مالك: {row.owner_count}</span>
                  <span className="work-management-pill">منفذ: {row.assignee_count}</span>
                </div>
                <div className="work-management-card-subtitle">Profile: {row.profile_status} · HR: {row.employee_status}</div>
                <div className="work-management-actions">
                  <button type="button" className="btn btn-primary" onClick={() => { setSelectedSourceId(row.user_id); setReplacementUserId(''); setReason('') }}>معالجة المسؤوليات</button>
                </div>
              </article>
            ))}
          </div>
        </>
      )}

      {selectedSource && (
        <form className="work-management-section work-management-form" onSubmit={submit}>
          <div className="form-group is-wide">
            <div className="work-management-section-heading"><div><h3>إعادة إسناد أعمال {selectedSource.full_name}</h3><span className="form-hint">سيتم قفل الأعمال المفتوحة وتحديث المسؤوليات بصورة ذرية، مع Event مستقل لكل نقل ملكية أو تفويض تنفيذ.</span></div></div>
          </div>
          <div className="form-group">
            <label className="form-label required" htmlFor="continuity-replacement">المستخدم البديل</label>
            <select id="continuity-replacement" className="form-input" value={replacementUserId} onChange={event => setReplacementUserId(event.target.value)} disabled={candidates.isLoading}>
              <option value="">اختر المستخدم البديل</option>
              {candidates.data?.filter(candidate => candidate.user_id !== selectedSource.user_id).map(candidate => (
                <option key={candidate.user_id} value={candidate.user_id}>{candidate.full_name}{candidate.is_self ? ' — أنت' : ''}</option>
              ))}
            </select>
            {candidates.isLoading && <span className="form-hint">جارٍ تحميل المستخدمين المتاحين…</span>}
          </div>
          <div className="form-group">
            <label className="form-label required" htmlFor="continuity-reason">سبب إعادة الإسناد</label>
            <textarea id="continuity-reason" className="form-input" value={reason} onChange={event => setReason(event.target.value)} placeholder="مثال: انتهاء خدمة الموظف وإعادة توزيع مسؤولياته" />
          </div>
          <div className="work-management-form-actions">
            <button type="button" className="btn btn-secondary" onClick={() => { setSelectedSourceId(''); setReplacementUserId(''); setReason('') }}>إلغاء</button>
            <button type="submit" className="btn btn-primary" disabled={mutation.isPending || candidates.isLoading}>{mutation.isPending ? <Loader2 size={16} className="animate-spin" /> : <UserRoundCog size={16} />} إعادة إسناد كل الأعمال المفتوحة</button>
          </div>
        </form>
      )}
    </section>
  )
}
