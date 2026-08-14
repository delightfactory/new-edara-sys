import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const notifications = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814131000_work_management_notifications_automation.sql',
), 'utf8')
const storage = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20260814131500_work_management_attachment_storage.sql',
), 'utf8')

describe('work notifications and attachment storage contract', () => {
  it('reuses the existing tasks notification category and alert-state ledger', () => {
    expect(notifications).toContain("'work.assigned','إسناد عمل جديد','Work assigned','tasks'")
    expect(notifications).toContain('public.notification_alert_state')
    expect(notifications).toContain('ON CONFLICT(alert_key) DO UPDATE')
    expect(notifications).not.toContain('CREATE TABLE public.work_notification')
  })

  it('routes event-driven notifications through the immutable work timeline', () => {
    expect(notifications).toContain('CREATE TRIGGER trg_work_notify_from_event')
    expect(notifications).toContain('AFTER INSERT ON public.work_events')
    expect(notifications).toContain("WHEN 'work.delegated'")
    expect(notifications).toContain("WHEN 'work.ownership_transferred'")
    expect(notifications).toContain("WHEN 'work.approval.requested'")
  })

  it('never uses sensitive work content in notification templates', () => {
    expect(notifications).not.toContain('{{work_title}}')
    expect(notifications).not.toContain('{{description}}')
    expect(notifications).not.toContain('{{comment_body}}')
    expect(notifications).not.toContain('{{reason}}')
    expect(notifications).not.toContain('{{intake_payload}}')
    expect(notifications).toContain("jsonb_build_object('work_id',p_work_item_id::TEXT,'work_number',v_work_number::TEXT)")
  })

  it('filters every work recipient through current visibility before dispatch', () => {
    expect(notifications).toContain('private.work_filter_notification_recipients')
    expect(notifications).toContain('private.work_user_can_view_row(')
    expect(notifications).toContain('private.work_actor_is_active(c.user_id)')
  })

  it('defines deduped operational, recurrence and workflow recovery schedules', () => {
    expect(notifications).toContain("'work-operational-alerts','*/15 * * * *'")
    expect(notifications).toContain("'work-recurrence-generator','*/5 * * * *'")
    expect(notifications).toContain("'work-workflow-activator','*/5 * * * *'")
    expect(notifications).toContain('private.work_generate_due_recurrences(clock_timestamp(),200)')
    expect(notifications).toContain('private.work_advance_running_workflows(100)')
  })

  it('does not perform automatic manager escalation in the scanner', () => {
    const scanStart = notifications.indexOf('CREATE OR REPLACE FUNCTION private.work_scan_operational_alerts')
    const recoveryStart = notifications.indexOf('CREATE OR REPLACE FUNCTION private.work_advance_running_workflows')
    const scan = notifications.slice(scanStart, recoveryStart)
    expect(scan).not.toContain('INSERT INTO public.work_escalations')
    expect(scan).not.toContain('manager_id')
  })

  it('creates a private Work attachment bucket with bounded upload types and size', () => {
    expect(storage).toContain("'work-attachments','work-attachments',false,26214400")
    expect(storage).toContain("'application/pdf'")
    expect(storage).toContain("'image/jpeg'")
    expect(storage).toContain('public=false')
  })

  it('binds storage paths to work/{uuid}/ and fails closed on invalid UUIDs', () => {
    expect(storage).toContain("v_folders[1]<>'work'")
    expect(storage).toContain('v_id:=v_folders[2]::UUID')
    expect(storage).toContain('EXCEPTION WHEN OTHERS THEN')
    expect(storage).toContain('RETURN NULL')
  })

  it('defines select, insert, update and delete Storage RLS policies', () => {
    expect(storage).toContain('work_attachments_storage_select')
    expect(storage).toContain('work_attachments_storage_insert')
    expect(storage).toContain('work_attachments_storage_update')
    expect(storage).toContain('work_attachments_storage_delete')
    expect(storage).toContain('private.work_current_user_can_view_item')
    expect(storage).toContain('private.work_current_user_can_attach_item')
  })

  it('prevents collaborators from silently overwriting another uploader object', () => {
    expect(storage).toContain('owner_id=(select auth.uid())::TEXT')
  })

  it('retains attachment metadata through an atomic soft-removal command', () => {
    expect(storage).toContain('CREATE OR REPLACE FUNCTION public.work_remove_attachment_metadata(')
    expect(storage).toContain('p_expected_version BIGINT')
    expect(storage).toContain("'work.attachment_removed'")
    expect(storage).toContain('removed_at=clock_timestamp()')
  })
})
