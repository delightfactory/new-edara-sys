/**
 * ActivityDetail — Wave A Upgraded
 * - employee name (from service join)
 * - duration_minutes + distance_meters display
 * - closed_reason when outcome = 'closed'
 * - checklist responses grouped by template
 * - real navigation links (plan, collection)
 */
import { useParams, useNavigate } from 'react-router-dom'
import { useActivity, useChecklistResponses } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { PERMISSIONS } from '@/lib/permissions/constants'
import PageHeader from '@/components/shared/PageHeader'
import ActivityStatusBadge from '@/components/shared/ActivityStatusBadge'
import Button from '@/components/ui/Button'
import { Edit2, MapPin, Clock, User, Phone, Ruler, ClipboardCheck, ExternalLink, XCircle } from 'lucide-react'
import type { ChecklistResponse } from '@/lib/types/activities'

const CALL_RESULT_AR: Record<string, string> = {
  answered:           'تم الرد',
  no_answer:          'لا يرد',
  busy:               'مشغول',
  callback_scheduled: 'مكالمة لاحقة مجدولة',
  wrong_number:       'رقم خاطئ',
  rejected:           'رُفض',
}

const QUESTION_TYPE_AR: Record<string, string> = {
  text:          'نص',
  number:        'رقم',
  yes_no:        'نعم/لا',
  single_choice: 'اختيار',
  multi_choice:  'اختيار متعدد',
  rating:        'تقييم',
  photo:         'صورة',
}

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('ar-EG', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
  })
}
function fmtTime(d: string) {
  return new Date(d).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })
}
function fmtDistance(m: number) {
  return m >= 1000
    ? `${(m / 1000).toFixed(1)} كم`
    : `${m} م`
}
function renderAnswerValue(r: ChecklistResponse): string {
  if (r.answer_json !== null && r.answer_json !== undefined) {
    if (Array.isArray(r.answer_json)) return r.answer_json.join(', ')
    return String(r.answer_json)
  }
  if (r.answer_value !== null && r.answer_value !== undefined) {
    if (r.answer_value === 'true' || r.answer_value === '1') return 'نعم ✓'
    if (r.answer_value === 'false' || r.answer_value === '0') return 'لا ✗'
    return r.answer_value
  }
  return '—'
}

export default function ActivityDetail() {
  const { id }   = useParams<{ id: string }>()
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)

  const { data: activity, isLoading, error } = useActivity(id)
  const { data: checklistResponses = [] }     = useChecklistResponses(id)

  const canEdit = can(PERMISSIONS.ACTIVITIES_UPDATE_OWN) ||
                  can(PERMISSIONS.ACTIVITIES_READ_TEAM)  ||
                  can(PERMISSIONS.ACTIVITIES_READ_ALL)

  // Group checklist responses by template_id
  const grouped = checklistResponses.reduce<Record<string, ChecklistResponse[]>>((acc, r) => {
    const key = r.template_id
    ;(acc[key] ??= []).push(r)
    return acc
  }, {})
  const templateGroups = Object.entries(grouped)

  if (isLoading) {
    return (
      <div className="page-container animate-enter">
        <div className="edara-card max-w-[640px] mx-auto p-6">
          {[1, 2, 3, 4].map(i => (
            <div key={i} className={`skeleton h-5 mb-3 w-[${70 - i * 10}%]`} />
          ))}
        </div>
      </div>
    )
  }

  if (error || !activity) {
    return (
      <div className="page-container animate-enter">
        <div className="empty-state p-8">
          <p className="empty-state-title">لم يتم العثور على النشاط</p>
          <Button variant="secondary" onClick={() => navigate('/activities/list')}>
            العودة للقائمة
          </Button>
        </div>
      </div>
    )
  }

  // Resolved plan IDs from joined plan_item
  const visitPlanId = activity.visit_plan_item?.plan_id ?? null
  const callPlanId  = activity.call_plan_item?.plan_id  ?? null

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title={activity.type?.name ?? 'تفاصيل النشاط'}
        subtitle={activity.customer?.name}
        breadcrumbs={[
          { label: 'الأنشطة', path: '/activities/list' },
          { label: activity.type?.name ?? 'تفاصيل' },
        ]}
        actions={canEdit ? (
          <Button
            icon={<Edit2 size={16} />}
            variant="secondary"
            onClick={() => navigate(`/activities/${id}/edit`)}
          >
            تعديل
          </Button>
        ) : undefined}
      />

      {/* ── Details Card ─────────────────────────────────────── */}
      <div className="edara-card act-detail-card">
        {/* Status */}
        <div className="act-detail-row act-detail-row--hero">
          <ActivityStatusBadge outcomeType={activity.outcome_type} />
          {activity.gps_verified && (
            <span className="act-detail-gps-badge">
              <MapPin size={12} /> GPS مُؤكَّد
            </span>
          )}
        </div>

        {/* Date & Time */}
        <div className="act-detail-row">
          <span className="act-detail-label">
            <Clock size={14} /> التاريخ
          </span>
          <span className="act-detail-value">{fmtDate(activity.activity_date)}</span>
        </div>
        {activity.start_time && (
          <div className="act-detail-row">
            <span className="act-detail-label">
              <Clock size={14} /> الوقت
            </span>
            <span className="act-detail-value" dir="ltr">
              {fmtTime(activity.start_time)}
              {activity.end_time && ` — ${fmtTime(activity.end_time)}`}
            </span>
          </div>
        )}

        {/* Duration */}
        {activity.duration_minutes != null && activity.duration_minutes > 0 && (
          <div className="act-detail-row">
            <span className="act-detail-label">
              <Clock size={14} /> المدة
            </span>
            <span className="act-detail-value">{activity.duration_minutes} دقيقة</span>
          </div>
        )}

        {/* Distance */}
        {activity.distance_meters != null && activity.distance_meters > 0 && (
          <div className="act-detail-row">
            <span className="act-detail-label">
              <Ruler size={14} /> المسافة
            </span>
            <span className="act-detail-value">{fmtDistance(activity.distance_meters)}</span>
          </div>
        )}

        {/* Employee */}
        {activity.employee && (
          <div className="act-detail-row">
            <span className="act-detail-label">
              <User size={14} /> الموظف
            </span>
            <span className="act-detail-value">{activity.employee.full_name}</span>
          </div>
        )}

        {/* Customer */}
        {activity.customer && (
          <div className="act-detail-row">
            <span className="act-detail-label">
              <User size={14} /> العميل
            </span>
            <span className="act-detail-value">{activity.customer.name}</span>
          </div>
        )}

        {/* GPS Coordinates */}
        {activity.gps_lat && activity.gps_lng && (
          <div className="act-detail-row">
            <span className="act-detail-label">
              <MapPin size={14} /> الموقع
            </span>
            <span className="act-detail-value font-mono text-xs" dir="ltr">
              {activity.gps_lat.toFixed(6)}, {activity.gps_lng.toFixed(6)}
            </span>
          </div>
        )}

        {/* Outcome Notes */}
        {activity.outcome_notes && (
          <div className="act-detail-section">
            <div className="act-detail-section-label">ملاحظات النتيجة</div>
            <div className="act-detail-notes">{activity.outcome_notes}</div>
          </div>
        )}

        {/* Refuse Reason */}
        {activity.refuse_reason && (
          <div className="act-detail-section">
            <div className="act-detail-section-label text-danger">سبب الرفض</div>
            <div className="act-detail-notes">{activity.refuse_reason}</div>
          </div>
        )}

        {/* Closed Reason — Wave A */}
        {activity.closed_reason && activity.outcome_type === 'closed' && (
          <div className="act-detail-section">
            <div className="act-detail-section-label flex items-center gap-1" style={{ color: 'var(--color-warning)' }}>
              <XCircle size={13} /> سبب الإغلاق
            </div>
            <div className="act-detail-notes">{activity.closed_reason}</div>
          </div>
        )}

        {/* Call Detail */}
        {activity.call_detail && (
          <div className="act-detail-section">
            <div className="act-detail-section-label">تفاصيل المكالمة</div>
            <div className="act-detail-call-grid">
              {activity.call_detail.direction && (
                <div>
                  <div className="act-detail-label">الاتجاه</div>
                  <div>{activity.call_detail.direction === 'outbound' ? '↗ صادرة' : '↙ واردة'}</div>
                </div>
              )}
              {activity.call_detail.call_result && (
                <div>
                  <div className="act-detail-label">نتيجة المكالمة</div>
                  <div className="font-semibold">
                    {CALL_RESULT_AR[activity.call_detail.call_result] ?? activity.call_detail.call_result}
                  </div>
                </div>
              )}
              {activity.call_detail.attempt_count && (
                <div>
                  <div className="act-detail-label">عدد المحاولات</div>
                  <div>{activity.call_detail.attempt_count}</div>
                </div>
              )}
              {activity.call_detail.phone_number && (
                <div>
                  <div className="act-detail-label">الرقم</div>
                  <div dir="ltr">{activity.call_detail.phone_number}</div>
                </div>
              )}
              {activity.call_detail.callback_at && (
                <div>
                  <div className="act-detail-label">موعد الرد</div>
                  <div>{new Date(activity.call_detail.callback_at).toLocaleString('ar-EG')}</div>
                </div>
              )}
              {activity.call_detail.call_recording_url && (
                <div className="col-span-full">
                  <div className="act-detail-label">تسجيل المكالمة</div>
                  <a
                    href={activity.call_detail.call_recording_url}
                    target="_blank"
                    rel="noreferrer"
                    className="text-primary text-sm font-medium flex items-center gap-1 mt-1 hover:underline"
                  >
                    <Phone size={12} />
                    استماع للتسجيل
                  </a>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Checklist Responses — Wave A */}
        {templateGroups.length > 0 && (
          <div className="act-detail-section">
            <div className="act-detail-section-label flex items-center gap-1">
              <ClipboardCheck size={13} /> نتائج الاستبيان
            </div>
            <div className="act-detail-checklist-groups">
              {templateGroups.map(([templateId, responses]) => (
                <div key={templateId} className="act-detail-checklist-group">
                  {responses.map(r => (
                    <div key={r.id} className="act-detail-checklist-row">
                      <span className="act-detail-checklist-q">
                        {r.question?.question_text ?? 'سؤال'}
                        {r.question?.question_type && (
                          <span className="act-detail-checklist-type">
                            ({QUESTION_TYPE_AR[r.question.question_type] ?? r.question.question_type})
                          </span>
                        )}
                      </span>
                      <span className="act-detail-checklist-a">{renderAnswerValue(r)}</span>
                    </div>
                  ))}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Linked Entities — Wave A: Real links */}
        {(visitPlanId || callPlanId || activity.order_id || activity.collection_id) && (
          <div className="act-detail-section">
            <div className="act-detail-section-label">الروابط</div>
            <div className="flex flex-col gap-2">
              {visitPlanId && (
                <button
                  className="act-detail-link text-primary font-semibold text-sm flex items-center gap-1"
                  onClick={() => navigate(`/activities/visit-plans/${visitPlanId}`)}
                >
                  <MapPin size={13} />
                  عرض خطة الزيارات المرتبطة
                  <ExternalLink size={12} />
                </button>
              )}
              {callPlanId && (
                <button
                  className="act-detail-link text-primary font-semibold text-sm flex items-center gap-1"
                  onClick={() => navigate(`/activities/call-plans/${callPlanId}`)}
                >
                  <Phone size={13} />
                  عرض خطة المكالمات المرتبطة
                  <ExternalLink size={12} />
                </button>
              )}
              {activity.order_id && (
                <button
                  className="act-detail-link text-success font-semibold text-sm flex items-center gap-1"
                  onClick={() => navigate(`/sales/orders/${activity.order_id}`)}
                >
                  🛒 عرض طلب البيع المرتبط
                  <ExternalLink size={12} />
                </button>
              )}
              {activity.collection_id && (
                <button
                  className="act-detail-link text-warning font-semibold text-sm flex items-center gap-1"
                  onClick={() => navigate(`/finance/payments/${activity.collection_id}`)}
                >
                  💰 عرض سند التحصيل المرتبط
                  <ExternalLink size={12} />
                </button>
              )}
            </div>
          </div>
        )}
      </div>

      <style>{`
        .act-detail-card {
          max-width: 640px;
          margin: 0 auto;
          padding: var(--space-6);
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
        }
        .act-detail-row {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-2) 0;
          border-bottom: 1px solid var(--border-primary);
        }
        .act-detail-row--hero {
          border-bottom: none;
          padding-bottom: var(--space-2);
          gap: var(--space-2);
        }
        .act-detail-label {
          display: flex;
          align-items: center;
          gap: var(--space-1);
          font-size: var(--text-xs);
          color: var(--text-muted);
          min-width: 110px;
          flex-shrink: 0;
        }
        .act-detail-value {
          font-size: var(--text-sm);
          font-weight: 500;
          color: var(--text-primary);
        }
        .act-detail-gps-badge {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          font-size: 11px;
          color: var(--color-success);
          background: var(--color-success-light);
          padding: 2px 8px;
          border-radius: 99px;
          font-weight: 600;
        }
        .act-detail-section {
          padding: var(--space-3) 0;
          border-bottom: 1px solid var(--border-primary);
        }
        .act-detail-section:last-child {
          border-bottom: none;
        }
        .act-detail-section-label {
          font-size: var(--text-xs);
          color: var(--text-muted);
          font-weight: 600;
          margin-bottom: var(--space-2);
          text-transform: uppercase;
          letter-spacing: 0.05em;
          display: flex;
          align-items: center;
          gap: 4px;
        }
        .act-detail-notes {
          font-size: var(--text-sm);
          color: var(--text-secondary);
          line-height: 1.7;
          white-space: pre-wrap;
        }
        .act-detail-call-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
          gap: var(--space-3);
          font-size: var(--text-sm);
          color: var(--text-primary);
        }
        .act-detail-link {
          background: none;
          border: none;
          cursor: pointer;
          padding: var(--space-1) 0;
          text-align: start;
          transition: opacity var(--transition-fast);
          display: flex;
          align-items: center;
          gap: 6px;
        }
        .act-detail-link:hover { opacity: 0.75; }

        /* Checklist Responses */
        .act-detail-checklist-groups {
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
        }
        .act-detail-checklist-group {
          background: var(--bg-surface-2, var(--bg-surface));
          border: 1px solid var(--border-primary);
          border-radius: var(--radius-lg);
          overflow: hidden;
        }
        .act-detail-checklist-row {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: var(--space-3);
          padding: var(--space-2) var(--space-3);
          border-bottom: 1px solid var(--border-primary);
          font-size: var(--text-sm);
        }
        .act-detail-checklist-row:last-child {
          border-bottom: none;
        }
        .act-detail-checklist-q {
          color: var(--text-secondary);
          flex: 1;
        }
        .act-detail-checklist-type {
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin-inline-start: 4px;
        }
        .act-detail-checklist-a {
          font-weight: 600;
          color: var(--text-primary);
          text-align: end;
          flex-shrink: 0;
        }
        @media (max-width: 480px) {
          .act-detail-card { padding: var(--space-4); }
          .act-detail-label { min-width: 90px; }
        }
      `}</style>
    </div>
  )
}
