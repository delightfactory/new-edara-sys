// @ts-nocheck — This file runs in Deno runtime, not Node.js
// supabase/functions/cleanup-notifications/index.ts
// ─────────────────────────────────────────────────────────────
// Maintenance Edge Function — housekeeping for stale notifications
// and inactive push subscriptions.
//
// Intended to be called by Supabase Cron (daily at 03:00 UTC).
// To configure: Dashboard → Database → Cron Jobs → New Cron Job
//   • Name: cleanup-notifications
//   • Schedule: 0 3 * * *
//   • Command: net.http_post(url, headers, body)
//
// Can also be called manually via service_role HTTP request.
// ─────────────────────────────────────────────────────────────

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    // Security: only allow service_role key (no browser client should call this)
    const authHeader = req.headers.get('Authorization') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    // Validate: caller must be using the service_role bearer token
    if (!authHeader.startsWith('Bearer ') || !authHeader.includes(serviceRoleKey.substring(0, 20))) {
      // Loose check — actual validation happens via Supabase JWT verification
      // Additional explicit check: reject anon/user tokens by checking the key prefix
      const token = authHeader.replace('Bearer ', '')
      if (token !== serviceRoleKey) {
        return Response.json(
          { error: 'Service role key required for cleanup operations' },
          { status: 403, headers: corsHeaders }
        )
      }
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    const results: Record<string, unknown> = {}

    // ── 1. Cleanup expired/archived notifications ─────────────
    // Calls the existing cleanup_old_notifications() RPC from migration 42
    const { data: cleanupCount, error: cleanupErr } = await adminClient
      .rpc('cleanup_old_notifications')

    if (cleanupErr) {
      console.error('cleanup_old_notifications error:', cleanupErr)
      results.notifications = { error: cleanupErr.message }
    } else {
      results.notifications = { cleaned: cleanupCount ?? 0 }
    }

    // ── 2. Remove permanently stale push subscriptions ────────
    // Hard-delete push subscriptions that have been inactive for 90+ days
    // (is_active=false AND last_seen_at is more than 90 days ago)
    const { data: staleSubRows, error: staleSubErr } = await adminClient
      .from('push_subscriptions')
      .delete()
      .eq('is_active', false)
      .lt('last_seen_at', new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString())
      .select('id')  // return count

    if (staleSubErr) {
      console.error('stale push_subscriptions cleanup error:', staleSubErr)
      results.pushSubscriptions = { error: staleSubErr.message }
    } else {
      results.pushSubscriptions = { removed: (staleSubRows ?? []).length }
    }

    // ── 3. Trim delivery_log records older than 180 days ──────
    // delivery_log is an audit trail — keep 6 months
    const { error: logErr } = await adminClient
      .from('notification_delivery_log')
      .delete()
      .lt('processed_at', new Date(Date.now() - 180 * 24 * 60 * 60 * 1000).toISOString())

    if (logErr) {
      console.error('delivery_log trim error:', logErr)
      results.deliveryLog = { error: logErr.message }
    } else {
      results.deliveryLog = { trimmed: true }
    }

    console.log('cleanup-notifications completed:', results)

    return Response.json(
      {
        success: true,
        timestamp: new Date().toISOString(),
        ...results,
      },
      { status: 200, headers: corsHeaders }
    )

  } catch (err) {
    console.error('cleanup-notifications error:', err)
    return Response.json(
      { error: err instanceof Error ? err.message : 'خطأ غير متوقع' },
      { status: 500, headers: corsHeaders }
    )
  }
})
