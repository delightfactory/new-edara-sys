-- Work Management — Migration C1c: private idempotency helpers.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.work_prepare_operation(
  p_operation_id UUID,
  p_actor_user_id UUID,
  p_operation_name TEXT,
  p_payload JSONB,
  p_subject_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_hash VARCHAR(64);
  v_status VARCHAR(20);
  v_result JSONB;
  v_actor UUID;
  v_name VARCHAR(100);
  v_existing_hash VARCHAR(64);
BEGIN
  IF p_operation_id IS NULL THEN
    RETURN jsonb_build_object(
      'execute', false,
      'response', jsonb_build_object(
        'ok', false,
        'operation_id', NULL,
        'operation', p_operation_name,
        'replayed', false,
        'error', jsonb_build_object('code', 'INVALID_OPERATION_ID', 'message', 'معرف العملية مطلوب')
      )
    );
  END IF;

  IF p_actor_user_id IS NULL OR NOT private.work_actor_is_active(p_actor_user_id) THEN
    RETURN jsonb_build_object(
      'execute', false,
      'response', jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', p_operation_name,
        'replayed', false,
        'error', jsonb_build_object('code', 'UNAUTHORIZED', 'message', 'المستخدم غير مصرح له أو غير نشط')
      )
    );
  END IF;

  IF p_operation_name IS NULL OR btrim(p_operation_name) = '' THEN
    RAISE EXCEPTION 'operation name is required';
  END IF;

  v_hash := encode(
    extensions.digest(
      jsonb_build_object(
        'operation_name', p_operation_name,
        'payload', COALESCE(p_payload, '{}'::JSONB)
      )::TEXT,
      'sha256'
    ),
    'hex'
  );

  INSERT INTO private.work_operation_requests (
    operation_id, actor_user_id, operation_name, request_hash,
    subject_id, status, created_at, updated_at
  ) VALUES (
    p_operation_id, p_actor_user_id, p_operation_name, v_hash,
    p_subject_id, 'pending', clock_timestamp(), clock_timestamp()
  ) ON CONFLICT (operation_id) DO NOTHING;

  SELECT r.status, r.result_json, r.actor_user_id, r.operation_name, r.request_hash
  INTO v_status, v_result, v_actor, v_name, v_existing_hash
  FROM private.work_operation_requests r
  WHERE r.operation_id = p_operation_id
  FOR UPDATE;

  IF v_actor IS DISTINCT FROM p_actor_user_id
     OR v_name IS DISTINCT FROM p_operation_name
     OR v_existing_hash IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object(
      'execute', false,
      'response', jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', p_operation_name,
        'replayed', false,
        'error', jsonb_build_object('code', 'IDEMPOTENCY_KEY_CONFLICT', 'message', 'تم استخدام معرف العملية مع طلب مختلف')
      )
    );
  END IF;

  IF v_status = 'completed' THEN
    RETURN jsonb_build_object(
      'execute', false,
      'response', jsonb_build_object(
        'ok', true,
        'operation_id', p_operation_id,
        'operation', p_operation_name,
        'replayed', true,
        'data', COALESCE(v_result, '{}'::JSONB)
      )
    );
  END IF;

  IF v_status = 'failed' THEN
    RETURN jsonb_build_object(
      'execute', false,
      'response', jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', p_operation_name,
        'replayed', true,
        'error', COALESCE(v_result->'error', jsonb_build_object('code', 'PREVIOUS_OPERATION_FAILED', 'message', 'فشلت المحاولة السابقة لنفس العملية'))
      )
    );
  END IF;

  IF v_status = 'processing' THEN
    RETURN jsonb_build_object(
      'execute', false,
      'response', jsonb_build_object(
        'ok', false,
        'operation_id', p_operation_id,
        'operation', p_operation_name,
        'replayed', false,
        'error', jsonb_build_object('code', 'RETRYABLE_ERROR', 'message', 'العملية قيد التنفيذ حاليًا')
      )
    );
  END IF;

  UPDATE private.work_operation_requests
  SET status = 'processing',
      started_at = clock_timestamp(),
      updated_at = clock_timestamp()
  WHERE operation_id = p_operation_id;

  RETURN jsonb_build_object('execute', true);
END;
$$;

CREATE OR REPLACE FUNCTION private.work_complete_operation(
  p_operation_id UUID,
  p_subject_id UUID,
  p_result JSONB
) RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE private.work_operation_requests
  SET status = 'completed',
      subject_id = COALESCE(p_subject_id, subject_id),
      result_json = COALESCE(p_result, '{}'::JSONB),
      error_code = NULL,
      failure_stage = NULL,
      error_detail = NULL,
      completed_at = clock_timestamp(),
      updated_at = clock_timestamp()
  WHERE operation_id = p_operation_id;
$$;

CREATE OR REPLACE FUNCTION private.work_fail_operation(
  p_operation_id UUID,
  p_error_code TEXT,
  p_error_message TEXT,
  p_failure_stage TEXT DEFAULT NULL,
  p_error_detail TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE private.work_operation_requests
  SET status = 'failed',
      error_code = left(COALESCE(p_error_code, 'INTERNAL_ERROR'), 50),
      failure_stage = left(p_failure_stage, 100),
      error_detail = p_error_detail,
      result_json = jsonb_build_object(
        'error', jsonb_build_object(
          'code', COALESCE(p_error_code, 'INTERNAL_ERROR'),
          'message', COALESCE(p_error_message, 'تعذر تنفيذ العملية')
        )
      ),
      completed_at = clock_timestamp(),
      updated_at = clock_timestamp()
  WHERE operation_id = p_operation_id;
$$;

REVOKE ALL ON FUNCTION private.work_prepare_operation(UUID, UUID, TEXT, JSONB, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.work_complete_operation(UUID, UUID, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.work_fail_operation(UUID, TEXT, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;

RESET lock_timeout;
RESET statement_timeout;
