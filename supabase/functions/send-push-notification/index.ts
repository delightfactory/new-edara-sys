// @ts-nocheck — This file runs in Deno runtime, not Node.js
// supabase/functions/send-push-notification/index.ts
// ─────────────────────────────────────────────────────────────
// Internal Edge Function — sends a single Web Push message.
// NOT called directly by the browser — only by dispatch-notification.
// On 410/404: deactivates the subscription immediately (no retry).
// On 429: increments failed_count without deactivating.
// On other errors: increments failed_count (triggers auto-deactivation at >=5).
// ─────────────────────────────────────────────────────────────

// web-push from esm.sh — Deno-compatible build (no Node.js APIs)
import webpush from 'https://esm.sh/web-push@3.6.7'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  // Internal-only endpoint: validate caller is service_role
  // dispatch-notification calls this with SUPABASE_SERVICE_ROLE_KEY as Bearer token
  const callerToken = req.headers.get('Authorization')?.replace('Bearer ', '').trim()
  const serviceKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!callerToken || callerToken !== serviceKey) {
    return Response.json({ error: 'Forbidden — internal endpoint' }, { status: 403, headers: corsHeaders })
  }

  try {
    // 1. Validate VAPID environment variables
    const vapidPublicKey  = Deno.env.get('VAPID_PUBLIC_KEY')
    const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY')
    const vapidSubject    = Deno.env.get('VAPID_SUBJECT')

    if (!vapidPublicKey || !vapidPrivateKey || !vapidSubject) {
      console.error('Missing VAPID environment variables')
      return Response.json(
        { error: 'Server misconfiguration — VAPID keys not set' },
        { status: 500, headers: corsHeaders }
      )
    }

    const supabaseUrl    = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const adminClient    = createClient(supabaseUrl, serviceRoleKey)

    // 2. Parse input
    const body = await req.json()
    const { subscription_id, endpoint, p256dh_key, auth_key, payload } = body

    if (!subscription_id || !endpoint || !p256dh_key || !auth_key || !payload) {
      return Response.json(
        { error: 'Missing required fields: subscription_id, endpoint, p256dh_key, auth_key, payload' },
        { status: 400, headers: corsHeaders }
      )
    }

    // 3. Configure VAPID details
    webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey)

    // 4. Send the push notification
    try {
      await webpush.sendNotification(
        {
          endpoint,
          keys: {
            p256dh: p256dh_key,
            auth:   auth_key,
          },
        },
        JSON.stringify(payload),
        {
          // TTL varies by notification priority:
          // critical: 7 days  (must reach user even after long offline period)
          // high:     48 hours
          // medium:   24 hours (default)
          // low:      4 hours  (time-sensitive context fades quickly)
          TTL: (() => {
            const p = (payload as { priority?: string })?.priority
            if (p === 'critical') return 60 * 60 * 24 * 7
            if (p === 'high')     return 60 * 60 * 48
            if (p === 'low')      return 60 * 60 * 4
            return 86400 // medium default
          })(),
        }
      )

      // Success: atomically reset failed_count + update last_push_at via RPC
      // Note: .catch() chaining is not supported on PostgrestBuilder in Deno — use try/catch
      try {
        await adminClient.rpc('reset_push_failed_count', { p_subscription_id: subscription_id })
      } catch (rpcErr) {
        // Non-critical: if RPC fails, delivery still succeeded. Log for observability.
        console.warn('reset_push_failed_count failed (non-critical):', (rpcErr as Error)?.message)
      }

      // Log successful delivery for observability dashboard
      await adminClient.from('notification_delivery_log').insert({
        notification_id: payload?.id || null,
        channel:         'push',
        status:          'delivered',
        subscription_id,
      }).catch(() => {}) // Non-critical — log failure must never block delivery response

      return Response.json({ sent: true }, { status: 200, headers: corsHeaders })

    } catch (pushError) {
      const statusCode = (pushError as { statusCode?: number })?.statusCode

      if (statusCode === 410 || statusCode === 404) {
        // Subscription is expired or invalid — deactivate immediately, no retry.
        // Direct update used here because RPC scope is failed_count only.
        await adminClient
          .from('push_subscriptions')
          .update({
            is_active:      false,
            last_failed_at: new Date().toISOString(),
            updated_at:     new Date().toISOString(),
          })
          .eq('id', subscription_id)

        // Log to delivery_log for observability
        await adminClient.from('notification_delivery_log').insert({
          notification_id: payload?.id ?? null,
          channel:         'push',
          status:          'failed',
          subscription_id,
          error_code:      String(statusCode),
          error_message:   'Subscription expired or invalid — deactivated',
        }).catch(() => {})

        return Response.json(
          { error: 'Subscription expired — deactivated' },
          { status: 410, headers: corsHeaders }
        )
      }

      if (statusCode === 429) {
        // Rate limited — increment failed_count atomically without deactivating.
        // The BEFORE UPDATE trigger handles deactivation at failed_count >= 5.
        try {
          await adminClient.rpc('increment_push_failed_count', { p_subscription_id: subscription_id })
        } catch (rpcErr) {
          console.error('increment_push_failed_count (429) failed:', (rpcErr as Error)?.message)
        }

        return Response.json(
          { error: 'Rate limited by push service' },
          { status: 429, headers: corsHeaders }
        )
      }

      // Other push errors — increment failed_count atomically.
      // DB trigger deactivates subscription if failed_count reaches 5.
      try {
        await adminClient.rpc('increment_push_failed_count', { p_subscription_id: subscription_id })
      } catch (rpcErr) {
        console.error('increment_push_failed_count failed:', (rpcErr as Error)?.message)
      }

      console.error('Push send error:', pushError)
      return Response.json(
        { error: 'Push delivery failed' },
        { status: 500, headers: corsHeaders }
      )
    }

  } catch (err) {
    console.error('send-push-notification error:', err)
    return Response.json(
      { error: err instanceof Error ? err.message : 'خطأ غير متوقع' },
      { status: 500, headers: corsHeaders }
    )
  }
})
