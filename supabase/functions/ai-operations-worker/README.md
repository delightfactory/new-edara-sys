# AI Operations Worker

Server-side, service-role-only worker for the AI Operations Planner. It materializes due runs, atomically claims one run, loads the bounded immutable seven-domain context, calls an OpenAI-compatible model endpoint, stages exactly one decision per frozen case, and invokes deterministic validation.

Required Edge Function secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `INTERNAL_AI_OPS_WORKER_SECRET` — recommended for scheduler invocation
- `AI_OPS_MODEL_BASE_URL` — OpenAI-compatible base URL or full `/chat/completions` URL
- `AI_OPS_MODEL_API_KEY`
- `AI_OPS_MODEL`

Safety boundary: the worker never calls `ai_ops_commit_reviewed_decision`. `CREATE_WORK` and `ESCALATE` remain behind the management human-review and explicit execution gateway. Browser/authenticated roles cannot call worker RPCs.
