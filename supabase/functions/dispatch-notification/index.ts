// @ts-nocheck — This file runs in Deno runtime, not Node.js
// supabase/functions/dispatch-notification/index.ts
// ─────────────────────────────────────────────────────────────
// Orchestrates notification delivery: creates in-app DB records
// and triggers push delivery for each target user.
// Caller must be an authenticated session (any logged-in user).
// Service-to-service calls (e.g. from DB triggers) use service_role key.
// ─────────────────────────────────────────────────────────────

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// ── Template interpolation ────────────────────────────────────
function renderTemplate(template: string, vars: Record<string, string>): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => vars[key] ?? `{{${key}}}`)
}

// ── Quiet hours check ─────────────────────────────────────────
function isInQuietHours(quietStart: string, quietEnd: string, timezone: string): boolean {
  try {
    const now = new Date()
    const formatter = new Intl.DateTimeFormat('en', {
      timeZone: timezone,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    })
    const [hourStr, minStr] = formatter.format(now).split(':')
    const currentMinutes = parseInt(hourStr) * 60 + parseInt(minStr)
    const [sh, sm] = quietStart.split(':').map(Number)
    const [eh, em] = quietEnd.split(':').map(Number)
    const startM = sh * 60 + sm
    const endM   = eh * 60 + em
    // Handle midnight crossover (e.g. 22:00 → 08:00)
    if (startM <= endM) return currentMinutes >= startM && currentMinutes < endM
    return currentMinutes >= startM || currentMinutes < endM
  } catch {
    return false
  }
}

// ── Main handler ──────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    // 1. Auth check
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return Response.json({ error: 'غير مصرح' }, { status: 401, headers: corsHeaders })
    }

    const supabaseUrl    = Deno.env.get('SUPABASE_URL')!
    const anonKey        = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    // ── Detect internal (service_role) vs external (user session) calls ──
    // Service role JWTs always carry {"role":"service_role"} in their payload.
    // Reading the JWT role is more reliable than string-comparing the raw key,
    // which can fail if the env var contains trailing whitespace or newlines.
    function getJWTRole(token: string): string | null {
      try {
        const base64 = token.split('.')[1]?.replace(/-/g, '+').replace(/_/g, '/')
        if (!base64) return null
        const payload = JSON.parse(atob(base64))
        return payload.role ?? null
      } catch { return null }
    }

    const bearerToken    = authHeader.replace(/^Bearer\s+/i, '').trim()
    const isInternalCall = getJWTRole(bearerToken) === 'service_role'

    if (!isInternalCall) {
      // External (browser) call — validate as authenticated user session
      const callerClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: authHeader } },
      })
      const { data: { user: caller }, error: authErr } = await callerClient.auth.getUser()
      if (authErr || !caller) {
        return Response.json({ error: 'جلسة غير صالحة' }, { status: 401, headers: corsHeaders })
      }
    }

    // 2. Validate input
    const body = await req.json()
    const {
      event_key,
      user_ids,
      variables      = {},
      entity_type,
      entity_id,
      metadata       = {},
      priority_override,
    } = body

    if (!event_key?.trim()) {
      return Response.json({ error: 'event_key مطلوب' }, { status: 400, headers: corsHeaders })
    }
    if (!Array.isArray(user_ids) || user_ids.length === 0) {
      return Response.json({ error: 'user_ids يجب أن يكون مصفوفة غير فارغة' }, { status: 400, headers: corsHeaders })
    }
    if (user_ids.length > 100) {
      return Response.json({ error: 'الحد الأقصى 100 مستقبل لكل استدعاء' }, { status: 400, headers: corsHeaders })
    }

    // 3. Fetch event type template
    const { data: eventType, error: etErr } = await adminClient
      .from('notification_event_types')
      .select('*')
      .eq('event_key', event_key)
      .eq('is_active', true)
      .single()

    if (etErr || !eventType) {
      return Response.json(
        { error: `نوع الحدث '${event_key}' غير موجود أو غير فعّال` },
        { status: 404, headers: corsHeaders }
      )
    }

    const vars = variables as Record<string, string>
    const dispatchedCount = { inApp: 0, push: 0, errors: 0 }

    // 4. Loop through each recipient
    for (const userId of user_ids as string[]) {
      try {
        // 4a. Fetch user preferences (use defaults if none configured)
        const { data: prefs } = await adminClient
          .from('notification_preferences')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle()

        const inAppEnabled = prefs?.in_app_enabled ?? true
        // ✅ FIX: push_enabled defaults to TRUE if the user has an active subscription.
        // The existence of a subscription record IS consent — no preferences row means
        // the user never visited settings, not that they opted out.
        const pushEnabled  = prefs?.push_enabled  ?? true
        const quietEnabled = prefs?.quiet_hours_enabled ?? false

        // 4b. Render templates
        const title     = renderTemplate(eventType.title_template, vars)
        const bodyText  = renderTemplate(eventType.body_template, vars)
        const actionUrl = eventType.action_url_template
          ? renderTemplate(eventType.action_url_template, vars)
          : null

        const effectivePriority = priority_override ?? eventType.default_priority

        // 4c. Create in-app notification record
        let notificationId: string | null = null
        if (inAppEnabled) {
          const { data: notification, error: insertErr } = await adminClient
            .from('notifications')
            .insert({
              user_id:     userId,
              event_key,
              title,
              body:        bodyText,
              category:    eventType.category,
              priority:    effectivePriority,
              icon:        eventType.icon ?? null,
              action_url:  actionUrl,
              entity_type: entity_type ?? null,
              entity_id:   entity_id   ?? null,
              metadata:    metadata    ?? {},
            })
            .select('id')
            .single()

          if (insertErr) {
            console.error(`Failed to create in-app notification for ${userId}:`, insertErr)
          } else {
            notificationId = notification?.id ?? null
            dispatchedCount.inApp++

            // Log delivery — processed_at has DEFAULT now() in DB, no need to send it
            await adminClient.from('notification_delivery_log').insert({
              notification_id: notificationId,
              channel:         'in_app',
              status:          'sent',
            }).then(() => {}).catch(() => {})
          }
        }

        // 4d. Push notifications — only if enabled and not in quiet hours
        const inQuiet = quietEnabled && isInQuietHours(
          prefs?.quiet_start ?? '22:00',
          prefs?.quiet_end   ?? '08:00',
          prefs?.timezone    ?? 'Africa/Cairo',
        )

        // Respect min_priority_push preference
        const PRIORITY_ORDER = ['low', 'medium', 'high', 'critical'] as const
        type PriorityLevel = typeof PRIORITY_ORDER[number]
        const minPriorityPush = (prefs?.min_priority_push ?? 'medium') as PriorityLevel
        const meetsMinPriority =
          PRIORITY_ORDER.indexOf(effectivePriority as PriorityLevel) >=
          PRIORITY_ORDER.indexOf(minPriorityPush)

        // Respect per-category push preference
        const categoryPrefs = prefs?.category_preferences as Record<string, { in_app?: boolean; push?: boolean }> | null
        const catPushEnabled = categoryPrefs?.[eventType.category]?.push ?? true

        const shouldPush = pushEnabled && !inQuiet && meetsMinPriority && catPushEnabled

        if (shouldPush) {
          const { data: subscriptions } = await adminClient
            .from('push_subscriptions')
            .select('id, endpoint, p256dh_key, auth_key')
            .eq('user_id', userId)
            .eq('is_active', true)

          for (const sub of subscriptions ?? []) {
            const pushResp = await fetch(
              `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-push-notification`,
              {
                method: 'POST',
                headers: {
                  'Content-Type':  'application/json',
                  'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
                },
                body: JSON.stringify({
                  subscription_id: sub.id,
                  endpoint:        sub.endpoint,
                  p256dh_key:      sub.p256dh_key,
                  auth_key:        sub.auth_key,
                  payload: {
                    id:        notificationId ?? '',
                    title,
                    body:      bodyText,
                    category:  eventType.category,
                    priority:  effectivePriority,
                    actionUrl,
                    tag:       eventType.category,
                  },
                }),
              }
            )

            if (pushResp.ok) {
              dispatchedCount.push++
            }
          }
        }
      } catch (userErr) {
        console.error(`Error dispatching notification for user ${userId}:`, userErr)
        dispatchedCount.errors++
      }
    }

    return Response.json(
      {
        dispatched: user_ids.length,
        inApp:  dispatchedCount.inApp,
        push:   dispatchedCount.push,
        errors: dispatchedCount.errors,
      },
      { status: 200, headers: corsHeaders }
    )
  } catch (err) {
    console.error('dispatch-notification error:', err)
    return Response.json(
      { error: err instanceof Error ? err.message : 'خطأ غير متوقع' },
      { status: 500, headers: corsHeaders }
    )
  }
})
