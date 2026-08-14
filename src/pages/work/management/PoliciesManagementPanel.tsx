import { useEffect, useState, type FormEvent } from 'react'
import { AlertTriangle, CheckCircle2, Loader2, Save, ShieldCheck } from 'lucide-react'
import { toast } from 'sonner'
import { useOperationalSettings, useUpdateOperationalSettings } from '@/features/work/management-hooks'

export default function PoliciesManagementPanel() {
  const settings = useOperationalSettings()
  const updateSettings = useUpdateOperationalSettings()
  const [dueSoonHours, setDueSoonHours] = useState(24)
  const [staleAfterHours, setStaleAfterHours] = useState(72)
  const [dueCooldown, setDueCooldown] = useState(24)
  const [followUpCooldown, setFollowUpCooldown] = useState(12)
  const [staleCooldown, setStaleCooldown] = useState(24)
  const [blockedCooldown, setBlockedCooldown] = useState(24)
  const [managerEscalationEnabled, setManagerEscalationEnabled] = useState(false)
  const [confirmHierarchyValidation, setConfirmHierarchyValidation] = useState(false)

  useEffect(() => {
    if (!settings.data) return
    setDueSoonHours(settings.data.due_soon_hours)
    setStaleAfterHours(settings.data.stale_after_hours)
    setDueCooldown(settings.data.due_alert_cooldown_hours)
    setFollowUpCooldown(settings.data.follow_up_alert_cooldown_hours)
    setStaleCooldown(settings.data.stale_alert_cooldown_hours)
    setBlockedCooldown(settings.data.blocked_alert_cooldown_hours)
    setManagerEscalationEnabled(settings.data.manager_escalation_enabled)
  }, [settings.data])

  const hierarchyValidated = Boolean(settings.data?.hierarchy_validated_at)

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (!settings.data) return
    if ([dueSoonHours, staleAfterHours, dueCooldown, followUpCooldown, staleCooldown, blockedCooldown].some(value => value <= 0)) {
      toast.error('كل مدد التشغيل يجب أن تكون أكبر من صفر')
      return
    }
    if (managerEscalationEnabled && !hierarchyValidated && !confirmHierarchyValidation) {
      toast.error('لا يمكن تفعيل التصعيد الإداري قبل اعتماد الهيكل التنظيمي')
      return
    }

    try {
      await updateSettings.mutateAsync({
        expectedVersion: settings.data.state_version,
        dueSoonHours,
        staleAfterHours,
        dueAlertCooldownHours: dueCooldown,
        followUpAlertCooldownHours: followUpCooldown,
        staleAlertCooldownHours: staleCooldown,
        blockedAlertCooldownHours: blockedCooldown,
        validateHierarchy: !hierarchyValidated && confirmHierarchyValidation,
        managerEscalationEnabled,
      })
      toast.success('تم حفظ سياسات التشغيل')
      setConfirmHierarchyValidation(false)
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'تعذر حفظ سياسات التشغيل')
    }
  }

  if (settings.isLoading) return <div className="work-management-loading"><Loader2 className="animate-spin" /> جاري تحميل سياسات التشغيل…</div>
  if (settings.error || !settings.data) return <div className="work-management-error"><p>تعذر تحميل سياسات التشغيل.</p></div>

  return (
    <section className="work-management-panel" aria-labelledby="policies-management-title">
      <div className="work-management-panel-header">
        <div><h2 id="policies-management-title">سياسات التشغيل</h2><p className="page-subtitle">اضبط متى يعتبر العمل قريب الاستحقاق أو راكدًا، ومتى يعاد إرسال التنبيه.</p></div>
      </div>

      <form className="work-management-section work-management-form" onSubmit={submit}>
        <div className="form-group"><label className="form-label required" htmlFor="due-soon-hours">قريب الاستحقاق بعد</label><div className="flex items-center gap-2"><input id="due-soon-hours" className="form-input" type="number" min={1} dir="ltr" value={dueSoonHours} onChange={event => setDueSoonHours(Number(event.target.value))} /><span className="form-hint">ساعة</span></div></div>
        <div className="form-group"><label className="form-label required" htmlFor="stale-hours">يعتبر راكدًا بعد</label><div className="flex items-center gap-2"><input id="stale-hours" className="form-input" type="number" min={1} dir="ltr" value={staleAfterHours} onChange={event => setStaleAfterHours(Number(event.target.value))} /><span className="form-hint">ساعة بلا نشاط فعلي</span></div></div>

        <div className="form-group is-wide"><div className="work-management-section-heading"><div><h3>Cooldown الإشعارات</h3><span className="form-hint">يمنع إعادة نفس التنبيه بشكل مزعج قبل مرور المدة.</span></div></div></div>
        <div className="form-group"><label className="form-label" htmlFor="due-cooldown">الاستحقاق</label><input id="due-cooldown" className="form-input" type="number" min={1} dir="ltr" value={dueCooldown} onChange={event => setDueCooldown(Number(event.target.value))} /></div>
        <div className="form-group"><label className="form-label" htmlFor="followup-cooldown">متابعة Waiting</label><input id="followup-cooldown" className="form-input" type="number" min={1} dir="ltr" value={followUpCooldown} onChange={event => setFollowUpCooldown(Number(event.target.value))} /></div>
        <div className="form-group"><label className="form-label" htmlFor="stale-cooldown">الركود</label><input id="stale-cooldown" className="form-input" type="number" min={1} dir="ltr" value={staleCooldown} onChange={event => setStaleCooldown(Number(event.target.value))} /></div>
        <div className="form-group"><label className="form-label" htmlFor="blocked-cooldown">التعطيل</label><input id="blocked-cooldown" className="form-input" type="number" min={1} dir="ltr" value={blockedCooldown} onChange={event => setBlockedCooldown(Number(event.target.value))} /></div>

        <div className="form-group is-wide">
          <div className={`work-management-alert ${hierarchyValidated ? '' : 'is-warning'}`}>
            {hierarchyValidated ? <CheckCircle2 size={22} aria-hidden="true" /> : <AlertTriangle size={22} aria-hidden="true" />}
            <div>
              <strong>{hierarchyValidated ? 'تم اعتماد الهيكل التنظيمي للتصعيد' : 'الهيكل التنظيمي غير معتمد للتصعيد الآلي'}</strong>
              <div className="work-management-card-subtitle">{hierarchyValidated ? `تاريخ الاعتماد: ${new Date(settings.data.hierarchy_validated_at!).toLocaleString('en-GB')}` : 'لن يحدد النظام المدير تلقائيًا قبل اعتماد علاقات المدير/الإدارة/الفرع. التصعيد اليدوي يظل متاحًا.'}</div>
            </div>
          </div>
        </div>

        {!hierarchyValidated && <div className="form-group is-wide"><label className="perm-checkbox-label"><input type="checkbox" checked={confirmHierarchyValidation} onChange={event => setConfirmHierarchyValidation(event.target.checked)} /> <span><strong>أؤكد أن الهيكل التنظيمي الحالي تمت مراجعته واعتماده للتصعيد.</strong><span className="form-hint" style={{ display: 'block' }}>هذا الإقرار يفتح فقط إمكانية تشغيل التصعيد الإداري؛ لا يفعّله وحده.</span></span></label></div>}

        <div className="form-group is-wide">
          <label className="perm-checkbox-label">
            <input type="checkbox" checked={managerEscalationEnabled} disabled={!hierarchyValidated && !confirmHierarchyValidation} onChange={event => setManagerEscalationEnabled(event.target.checked)} />
            <span><strong>تفعيل التصعيد الإداري التلقائي</strong><span className="form-hint" style={{ display: 'block' }}>لا تستخدمه إلا بعد التأكد أن مدير كل نطاق نشط وصحيح.</span></span>
          </label>
        </div>

        <div className="work-management-form-actions"><button type="submit" className="btn btn-primary" disabled={updateSettings.isPending}>{updateSettings.isPending ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />} حفظ السياسات</button></div>
      </form>

      <div className="work-management-alert"><ShieldCheck size={22} aria-hidden="true" /><div><strong>قاعدة ثابتة</strong><div className="work-management-card-subtitle">Blocked / Overdue / Stale / At-Risk / Escalated تظل Operational Flags ولا تتحول إلى حالات lifecycle.</div></div></div>
    </section>
  )
}
