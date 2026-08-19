import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-ai-ops-worker-secret',
}

const allowedFields = new Set([
  'case_id','decision_type','concise_rationale','confidence',
  'recommended_owner_user_id','recommended_assignee_user_id',
  'responsibility_summary','why_this_owner','why_now',
  'expected_outcome','next_action_text','due_at','review_after',
  'business_impact','urgency','evidence_completeness','reversibility',
  'estimated_effort','success_signal','employee_safe_reason',
])

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function completionsUrl(baseUrl: string) {
  const clean = baseUrl.replace(/\/+$/, '')
  return clean.endsWith('/chat/completions') ? clean : `${clean}/chat/completions`
}

function parseModelJson(text: string) {
  const cleaned = text.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '')
  return JSON.parse(cleaned)
}

function stagedRunRemainsReviewable(staged: unknown) {
  if (!staged || typeof staged !== 'object' || Array.isArray(staged)) return true
  const lifecycle = (staged as { run_lifecycle?: unknown }).run_lifecycle
  if (!lifecycle || typeof lifecycle !== 'object' || Array.isArray(lifecycle)) return true
  return (lifecycle as { status?: unknown }).status === 'staged'
}

function readVersionedPolicy(contextResult: Record<string, unknown>) {
  const context = contextResult.context
  if (!context || typeof context !== 'object' || Array.isArray(context)) {
    throw new Error('worker context contract is incomplete')
  }

  const policy = (context as Record<string, unknown>).planner_policy
  if (!policy || typeof policy !== 'object' || Array.isArray(policy)) {
    throw new Error('versioned planner policy is missing from worker context')
  }

  const typed = policy as Record<string, unknown>
  const systemPrompt = typed.system_prompt
  const promptHash = typed.prompt_hash
  const policyVersion = typed.policy_version
  const promptVersion = typed.prompt_version

  if (
    typeof systemPrompt !== 'string' || !systemPrompt.trim()
    || typeof promptHash !== 'string' || !/^[a-f0-9]{32}$/.test(promptHash)
    || typeof policyVersion !== 'string' || !policyVersion.trim()
    || typeof promptVersion !== 'string' || !promptVersion.trim()
  ) {
    throw new Error('versioned planner policy contract is invalid')
  }

  if (contextResult.prompt_hash !== promptHash) {
    throw new Error('worker prompt hash does not match the database policy hash')
  }
  if (contextResult.planner_policy_version !== policyVersion) {
    throw new Error('worker policy version does not match the database policy')
  }
  if (contextResult.prompt_version !== promptVersion) {
    throw new Error('worker prompt version does not match the database policy')
  }

  return { systemPrompt, promptHash, policyVersion, promptVersion }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return jsonResponse({ error: 'method_not_allowed' }, 405)

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const workerSecret = Deno.env.get('INTERNAL_AI_OPS_WORKER_SECRET')
  const modelBaseUrl = Deno.env.get('AI_OPS_MODEL_BASE_URL')
  const modelApiKey = Deno.env.get('AI_OPS_MODEL_API_KEY')
  const model = Deno.env.get('AI_OPS_MODEL')

  if (!supabaseUrl || !serviceRoleKey || !modelBaseUrl || !modelApiKey || !model) {
    return jsonResponse({ error: 'worker_not_configured' }, 503)
  }

  const bearer = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
  const suppliedSecret = req.headers.get('x-ai-ops-worker-secret')
  const authorized = bearer === serviceRoleKey || (!!workerSecret && suppliedSecret === workerSecret)
  if (!authorized) return jsonResponse({ error: 'unauthorized' }, 401)

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const workerId = `edge:${crypto.randomUUID()}`
  let claimedRunId: string | null = null

  const rpc = async (name: string, args: Record<string, unknown> = {}) => {
    const { data, error } = await supabase.rpc(name, args)
    if (error) throw new Error(`${name}: ${error.message}`)
    return data
  }

  try {
    await rpc('ai_ops_worker_materialize_due_runs')
    const claim = await rpc('ai_ops_worker_claim_next_run', {
      p_worker_id: workerId,
      p_lease_seconds: 1200,
    }) as Record<string, unknown> | null

    if (!claim || claim.claimed !== true || typeof claim.run_id !== 'string') {
      return jsonResponse({ ok: true, claimed: false })
    }
    claimedRunId = claim.run_id

    const contextResult = await rpc('ai_ops_worker_get_context', {
      p_run_id: claimedRunId,
      p_worker_id: workerId,
    }) as Record<string, unknown>
    if (contextResult.blocked === true) {
      return jsonResponse({ ok: true, claimed: true, run_id: claimedRunId, blocked: true, reason: contextResult.reason })
    }
    if (typeof contextResult.context_hash !== 'string' || !contextResult.context) {
      throw new Error('worker context contract is incomplete')
    }

    const versionedPolicy = readVersionedPolicy(contextResult)

    await rpc('ai_ops_worker_heartbeat', {
      p_run_id: claimedRunId,
      p_worker_id: workerId,
      p_lease_seconds: 1200,
    })

    const modelResponse = await fetch(completionsUrl(modelBaseUrl), {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${modelApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        temperature: 0.1,
        messages: [
          { role: 'system', content: versionedPolicy.systemPrompt },
          { role: 'user', content: JSON.stringify(contextResult.context) },
        ],
      }),
    })
    if (!modelResponse.ok) {
      throw new Error(`model_http_${modelResponse.status}: ${(await modelResponse.text()).slice(0, 500)}`)
    }

    const modelBody = await modelResponse.json() as Record<string, unknown>
    const choices = modelBody.choices as Array<Record<string, unknown>> | undefined
    const message = choices?.[0]?.message as Record<string, unknown> | undefined
    if (typeof message?.content !== 'string') throw new Error('model response has no text content')
    const parsed = parseModelJson(message.content) as { decisions?: unknown[] }
    if (!Array.isArray(parsed.decisions)) throw new Error('model response does not contain decisions array')

    const decisions = parsed.decisions.map((raw) => {
      if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('invalid decision object')
      const clean: Record<string, unknown> = {}
      for (const [key, value] of Object.entries(raw)) {
        if (allowedFields.has(key)) clean[key] = value
      }
      return clean
    })

    const staged = await rpc('ai_ops_worker_stage_decisions', {
      p_run_id: claimedRunId,
      p_worker_id: workerId,
      p_context_hash: contextResult.context_hash,
      p_decisions: decisions,
    })

    // Staging deliberately closes zero-case and shadow-mode runs. Validation is
    // only legal while the durable lifecycle remains staged for human review.
    const validated = stagedRunRemainsReviewable(staged)
      ? await rpc('ai_ops_worker_validate_staged_run', { p_run_id: claimedRunId })
      : { skipped: true, reason: 'run_terminal_after_staging' }

    return jsonResponse({
      ok: true,
      claimed: true,
      run_id: claimedRunId,
      planner_policy_version: versionedPolicy.policyVersion,
      prompt_version: versionedPolicy.promptVersion,
      prompt_hash: versionedPolicy.promptHash,
      staged,
      validated,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    if (claimedRunId) {
      try {
        await rpc('ai_ops_worker_fail_run', {
          p_run_id: claimedRunId,
          p_worker_id: workerId,
          p_error_class: 'edge_worker_failure',
          p_error_message: message.slice(0, 1500),
        })
      } catch (_) {
        // Preserve the original failure; durable lease expiry remains the recovery path.
      }
    }
    return jsonResponse({ ok: false, run_id: claimedRunId, error: message }, 500)
  }
})