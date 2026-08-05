import { useQuery } from '@tanstack/react-query'
import { AlertCircle, ArrowRight, CalendarClock } from 'lucide-react'
import { useParams, useSearchParams } from 'react-router-dom'
import Button from '@/components/ui/Button'
import Spinner from '@/components/ui/Spinner'
import { getEmployee } from '@/lib/services/hr'
import { useAuthStore } from '@/stores/auth-store'
import EmployeeProfileLegacy from './EmployeeProfileLegacy'
import EmployeeWorkScheduleTab from './EmployeeWorkScheduleTab'
import './EmployeeProfileShell.css'

const WORK_SCHEDULE_SECTION = 'work-schedule'

export default function EmployeeProfile() {
  const { id } = useParams<{ id: string }>()
  const [searchParams, setSearchParams] = useSearchParams()
  const can = useAuthStore(state => state.can)
  const showWorkSchedule = searchParams.get('section') === WORK_SCHEDULE_SECTION
  const canReadSchedules = can('hr.employees.read') || can('hr.employees.edit')

  const employeeQuery = useQuery({
    queryKey: ['hr-employee-work-schedule-shell', id],
    queryFn: () => getEmployee(id!),
    enabled: showWorkSchedule && canReadSchedules && Boolean(id),
  })

  const openWorkSchedule = () => {
    const next = new URLSearchParams(searchParams)
    next.set('section', WORK_SCHEDULE_SECTION)
    setSearchParams(next)
  }

  const closeWorkSchedule = () => {
    const next = new URLSearchParams(searchParams)
    next.delete('section')
    setSearchParams(next)
  }

  if (!showWorkSchedule || !canReadSchedules) {
    return (
      <div className="employee-profile-shell">
        {canReadSchedules && (
          <div className="employee-profile-schedule-toolbar">
            <button
              type="button"
              className="employee-profile-schedule-entry"
              onClick={openWorkSchedule}
              aria-label="فتح جدول عمل الموظف"
            >
              <CalendarClock size={18} />
              جدول العمل
            </button>
          </div>
        )}
        <EmployeeProfileLegacy />
      </div>
    )
  }

  if (!id) {
    return (
      <div className="page-container">
        <div className="employee-profile-schedule-error">
          <AlertCircle size={20} />
          <div>معرّف الموظف غير موجود. لم يتم تنفيذ أي تغيير.</div>
        </div>
      </div>
    )
  }

  if (employeeQuery.isLoading) {
    return (
      <div className="page-container employee-profile-schedule-loading">
        <Spinner />
      </div>
    )
  }

  if (employeeQuery.error || !employeeQuery.data) {
    return (
      <div className="page-container employee-profile-schedule-page">
        <div className="employee-profile-schedule-page-header edara-card">
          <Button
            variant="secondary"
            icon={<ArrowRight size={16} />}
            onClick={closeWorkSchedule}
          >
            العودة لملف الموظف
          </Button>
        </div>
        <div className="employee-profile-schedule-error">
          <AlertCircle size={20} />
          <div>
            <strong>تعذر تحميل بيانات الموظف</strong>
            <p>لم يتم تنفيذ أي تغيير في الجدول أو الحضور.</p>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="page-container employee-profile-schedule-page">
      <div className="employee-profile-schedule-page-header edara-card">
        <div className="employee-profile-schedule-page-title">
          <h1>جدول عمل {employeeQuery.data.full_name}</h1>
          <p>مواعيد أسبوعية فردية مؤرخة، مع الحفاظ على سجلات الحضور السابقة.</p>
        </div>
        <Button
          variant="secondary"
          icon={<ArrowRight size={16} />}
          onClick={closeWorkSchedule}
        >
          العودة لملف الموظف
        </Button>
      </div>

      <EmployeeWorkScheduleTab employee={employeeQuery.data} />
    </div>
  )
}
