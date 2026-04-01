-- ============================================================
-- 22c_target_payouts.sql — النسخة المُصلحة (v2)
-- إصلاح 4 مشاكل أشار إليها كوديكس:
--   [P0] hr_payroll_adjustments لا يحتوي period_id → نستخدم effective_date
--   [P1] UPDATE...ORDER BY...LIMIT صيغة غير صالحة → تصحيح بـ subquery
--   [P1] upgrade_value: target_value=عدد العملاء، growth_pct في filter_criteria
--   [P2] p_user_id fallback إلى auth.uid()
-- +  approve_payroll_run مؤجل إلى 22d_payroll_sync.sql (بعد مراجعة كوديكس)
-- Idempotent: آمن للتشغيل أكثر من مرة
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- SECTION 1: create_target_with_rewards() — RPC الإنشاء الذري
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_target_with_rewards(
  p_type_id         UUID,
  p_name            TEXT,
  p_description     TEXT        DEFAULT NULL,
  p_scope           TEXT        DEFAULT 'individual',
  p_scope_id        UUID        DEFAULT NULL,
  p_period          TEXT        DEFAULT 'monthly',
  p_period_start    DATE        DEFAULT NULL,
  p_period_end      DATE        DEFAULT NULL,
  p_target_value    NUMERIC     DEFAULT 0,
  p_min_value       NUMERIC     DEFAULT NULL,
  p_stretch_value   NUMERIC     DEFAULT NULL,
  p_product_id      UUID        DEFAULT NULL,
  p_category_id     UUID        DEFAULT NULL,
  p_governorate_id  UUID        DEFAULT NULL,
  p_city_id         UUID        DEFAULT NULL,
  p_area_id         UUID        DEFAULT NULL,
  p_dormancy_days   INTEGER     DEFAULT NULL,
  p_filter_criteria JSONB       DEFAULT '{}',
  p_notes           TEXT        DEFAULT NULL,
  p_reward_type         TEXT    DEFAULT NULL,
  p_reward_base_value   NUMERIC DEFAULT NULL,
  p_reward_pool_basis   TEXT    DEFAULT NULL,
  p_payout_month_offset INTEGER DEFAULT 0,
  p_tiers           JSONB       DEFAULT '[]',
  p_customers       JSONB       DEFAULT '[]',
  p_auto_payout     BOOLEAN     DEFAULT false,
  p_user_id         UUID        DEFAULT NULL
) RETURNS UUID
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_target_id   UUID;
  v_type_code   TEXT;
  v_type_cat    TEXT;
  v_tier        JSONB;
  v_customer    JSONB;
  v_seq         INTEGER := 0;
  v_caller_id   UUID;
BEGIN
  -- ★ [P2 FIX] p_user_id fallback إلى auth.uid()
  v_caller_id := COALESCE(p_user_id, auth.uid());
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION '[EDARA] يجب تمرير p_user_id أو استدعاء الدالة من جلسة مُستَوثقة';
  END IF;
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF NOT (check_permission(v_caller_id, 'targets.create') OR check_permission(v_caller_id, 'targets.read_all')) THEN
    RAISE EXCEPTION 'ليس لديك صلاحية إنشاء الأهداف';
  END IF;

  SELECT tt.code, tt.category INTO v_type_code, v_type_cat
  FROM public.target_types tt WHERE tt.id = p_type_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'نوع الهدف غير موجود';
  END IF;

  IF NOT public.is_valid_reward_config(v_type_cat, v_type_code, p_reward_type, p_reward_pool_basis) THEN
    RAISE EXCEPTION '[EDARA] تركيبة المكافأة غير صالحة لهذا النوع من الأهداف [%]', v_type_code;
  END IF;

  IF p_auto_payout = true THEN
    IF p_reward_type IS NULL OR p_reward_base_value IS NULL OR p_reward_base_value <= 0 THEN
      RAISE EXCEPTION 'auto_payout يتطلب تحديد نوع وقيمة المكافأة';
    END IF;
    IF jsonb_array_length(COALESCE(p_tiers, '[]')) = 0 THEN
      RAISE EXCEPTION 'auto_payout يتطلب شريحة مكافأة واحدة على الأقل';
    END IF;
  END IF;

  -- STEP 1: إنشاء الهدف — دائماً بـ auto_payout=false
  INSERT INTO public.targets (
    type_id, name, description, scope, scope_id, period,
    period_start, period_end, target_value, min_value, stretch_value,
    product_id, category_id, governorate_id, city_id, area_id,
    dormancy_days, filter_criteria, notes,
    reward_type, reward_base_value, reward_pool_basis, payout_month_offset,
    auto_payout,
    assigned_by, is_active, is_paused
  ) VALUES (
    p_type_id, p_name, p_description, p_scope, p_scope_id, p_period,
    COALESCE(p_period_start, date_trunc('month', CURRENT_DATE)::DATE),
    COALESCE(p_period_end,   (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE),
    p_target_value, p_min_value, p_stretch_value,
    p_product_id, p_category_id, p_governorate_id, p_city_id, p_area_id,
    p_dormancy_days, COALESCE(p_filter_criteria, '{}'), p_notes,
    p_reward_type, p_reward_base_value, p_reward_pool_basis, COALESCE(p_payout_month_offset, 0),
    false,          -- ALWAYS false (Trigger يمنع true في INSERT)
    v_caller_id, true, false
  ) RETURNING id INTO v_target_id;

  -- STEP 2: إنشاء الشرائح
  FOR v_tier IN SELECT * FROM jsonb_array_elements(COALESCE(p_tiers, '[]'))
  LOOP
    v_seq := v_seq + 1;
    INSERT INTO public.target_reward_tiers (target_id, sequence, threshold_pct, reward_pct, label)
    VALUES (
      v_target_id,
      COALESCE((v_tier->>'sequence')::INTEGER, v_seq),
      (v_tier->>'threshold_pct')::NUMERIC,
      (v_tier->>'reward_pct')::NUMERIC,
      v_tier->>'label'
    );
  END LOOP;

  -- STEP 3: إنشاء العملاء المستهدفين
  FOR v_customer IN SELECT * FROM jsonb_array_elements(COALESCE(p_customers, '[]'))
  LOOP
    INSERT INTO public.target_customers (
      target_id, customer_id,
      baseline_value, baseline_category_count,
      baseline_period_start, baseline_period_end
    ) VALUES (
      v_target_id,
      (v_customer->>'customer_id')::UUID,
      (v_customer->>'baseline_value')::NUMERIC,
      (v_customer->>'baseline_category_count')::INTEGER,
      (v_customer->>'baseline_period_start')::DATE,
      (v_customer->>'baseline_period_end')::DATE
    );
  END LOOP;

  -- STEP 4: تفعيل auto_payout عبر UPDATE (لا INSERT — يتجاوز الـ Trigger بأمان)
  IF p_auto_payout = true THEN
    UPDATE public.targets SET auto_payout = true, updated_at = now()
    WHERE id = v_target_id;
  END IF;

  -- STEP 5: لقطة أولى فورية
  PERFORM public.recalculate_target_progress(v_target_id, CURRENT_DATE);

  RETURN v_target_id;
END; $$;

-- ════════════════════════════════════════════════════════════
-- SECTION 2: prepare_target_reward_payouts() — التثبيت الذري
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.prepare_target_reward_payouts(
  p_period_id UUID
) RETURNS INTEGER
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_period          hr_payroll_periods%ROWTYPE;
  v_target          public.targets%ROWTYPE;
  v_employee_id     UUID;
  v_achievement     NUMERIC;
  v_best_tier       public.target_reward_tiers%ROWTYPE;
  v_pool_value      NUMERIC;
  v_payout_amount   NUMERIC;
  v_adj_id          UUID;
  v_payout_period_id UUID;
  v_payout_year     INTEGER;
  v_payout_month    INTEGER;
  v_payout_date     DATE;
  v_tier_count      INTEGER;
  v_created_count   INTEGER := 0;
  v_last_progress_id UUID;     -- ★ [P1 FIX] لتجنب UPDATE...ORDER BY...LIMIT
BEGIN
  SELECT * INTO v_period FROM hr_payroll_periods WHERE id = p_period_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  FOR v_target IN
    SELECT t.*
    FROM public.targets t
    WHERE t.is_active   = true
      AND t.is_paused   = false
      AND t.auto_payout = true
      AND t.scope       = 'individual'
      AND t.reward_type IS NOT NULL
      AND (
        EXTRACT(YEAR  FROM (DATE_TRUNC('month', t.period_end)
          + (t.payout_month_offset || ' months')::INTERVAL)::DATE)::INTEGER = v_period.year
        AND
        EXTRACT(MONTH FROM (DATE_TRUNC('month', t.period_end)
          + (t.payout_month_offset || ' months')::INTERVAL)::DATE)::INTEGER = v_period.month
      )
  LOOP
    SELECT id INTO v_employee_id
    FROM hr_employees
    WHERE id = v_target.scope_id AND status = 'active';

    IF NOT FOUND THEN CONTINUE; END IF;

    -- فحص الشرائح
    SELECT COUNT(*) INTO v_tier_count
    FROM public.target_reward_tiers WHERE target_id = v_target.id;

    IF v_tier_count = 0 THEN
      -- ★ [P1 FIX] UPDATE مع subquery بدلاً من ORDER BY LIMIT
      SELECT id INTO v_last_progress_id
      FROM public.target_progress
      WHERE target_id = v_target.id
      ORDER BY snapshot_date DESC
      LIMIT 1;

      IF v_last_progress_id IS NOT NULL THEN
        UPDATE public.target_progress
        SET calc_details = COALESCE(calc_details, '{}') || jsonb_build_object(
          'payout_warning', 'auto_payout=true لكن لا توجد شرائح — تم تخطي هذا الهدف'
        )
        WHERE id = v_last_progress_id;
      END IF;
      CONTINUE;
    END IF;

    -- إجبار إعادة الحساب
    PERFORM public.recalculate_target_progress(
      v_target.id,
      LEAST(v_target.period_end, CURRENT_DATE)
    );

    -- قراءة الإنجاز
    SELECT achievement_pct INTO v_achievement
    FROM public.target_progress
    WHERE target_id = v_target.id
    ORDER BY snapshot_date DESC
    LIMIT 1;

    IF v_achievement IS NULL THEN CONTINUE; END IF;

    -- أعلى شريحة محققة
    SELECT * INTO v_best_tier
    FROM public.target_reward_tiers
    WHERE target_id = v_target.id AND threshold_pct <= v_achievement
    ORDER BY threshold_pct DESC
    LIMIT 1;

    IF NOT FOUND THEN CONTINUE; END IF;

    -- حساب الاستحقاق
    IF v_target.reward_type = 'fixed' THEN
      v_pool_value    := v_target.reward_base_value;
      v_payout_amount := ROUND(v_target.reward_base_value * (v_best_tier.reward_pct / 100.0), 2);
    ELSIF v_target.reward_type = 'percentage' THEN
      v_pool_value := public.calc_target_pool_value(
        v_target.id, v_employee_id,
        v_target.period_start, v_target.period_end
      );
      v_payout_amount := ROUND(
        v_pool_value * (v_target.reward_base_value / 100.0) * (v_best_tier.reward_pct / 100.0),
        2
      );
    ELSE CONTINUE;
    END IF;

    IF v_payout_amount <= 0 THEN CONTINUE; END IF;

    -- تحديد فترة الصرف
    v_payout_date  := (DATE_TRUNC('month', v_target.period_end)
                       + (v_target.payout_month_offset || ' months')::INTERVAL)::DATE;
    v_payout_year  := EXTRACT(YEAR  FROM v_payout_date)::INTEGER;
    v_payout_month := EXTRACT(MONTH FROM v_payout_date)::INTEGER;

    SELECT id INTO v_payout_period_id
    FROM hr_payroll_periods
    WHERE year = v_payout_year AND month = v_payout_month;

    IF v_payout_period_id IS NULL THEN
      INSERT INTO hr_payroll_periods (year, month, name, start_date, end_date)
      VALUES (
        v_payout_year, v_payout_month,
        to_char(v_payout_date, 'Month YYYY'),
        DATE_TRUNC('month', v_payout_date)::DATE,
        (DATE_TRUNC('month', v_payout_date) + INTERVAL '1 month - 1 day')::DATE
      )
      ON CONFLICT (year, month) DO NOTHING
      RETURNING id INTO v_payout_period_id;

      IF v_payout_period_id IS NULL THEN
        SELECT id INTO v_payout_period_id FROM hr_payroll_periods
        WHERE year = v_payout_year AND month = v_payout_month;
      END IF;
    END IF;

    -- Idempotent INSERT في target_reward_payouts
    INSERT INTO public.target_reward_payouts (
      target_id, employee_id, period_id,
      achievement_pct, tier_reached, reward_pct, base_amount, payout_amount,
      status
    ) VALUES (
      v_target.id, v_employee_id, v_payout_period_id,
      v_achievement, v_best_tier.sequence, v_best_tier.reward_pct, v_pool_value, v_payout_amount,
      'pending'
    )
    ON CONFLICT (target_id, employee_id, period_id) DO NOTHING;

    -- ★ [P0 FIX] hr_payroll_adjustments لا يحتوي period_id
    -- نستخدم effective_date = أول يوم في فترة الصرف (يُربط بالمسير عبر التاريخ)
    IF FOUND THEN
      INSERT INTO hr_payroll_adjustments (
        employee_id,
        type, amount, status, reason,
        effective_date,    -- ← الفيصل (يوجد في الجدول) بدلاً من period_id (غير موجود)
        created_by
      ) VALUES (
        v_employee_id,
        'bonus',
        v_payout_amount,
        'approved',
        '[مكافأة هدف] ' || v_target.name || ' — ' || ROUND(v_achievement, 1) || '% إنجاز',
        DATE_TRUNC('month', v_payout_date)::DATE,   -- أول يوم في فترة الصرف
        NULL    -- SYSTEM
      )
      RETURNING id INTO v_adj_id;

      -- تثبيت السجل
      UPDATE public.target_reward_payouts
      SET status = 'committed', adjustment_id = v_adj_id, committed_at = now()
      WHERE target_id   = v_target.id
        AND employee_id = v_employee_id
        AND period_id   = v_payout_period_id
        AND status      = 'pending';

      v_created_count := v_created_count + 1;
    END IF;
  END LOOP;

  RETURN v_created_count;
END; $$;

-- ════════════════════════════════════════════════════════════
-- SECTION 3: adjust_target() — موسَّع + قفل + تحقق
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.adjust_target(
  p_target_id   UUID,
  p_field       TEXT,
  p_new_value   TEXT,
  p_reason      TEXT,
  p_user_id     UUID DEFAULT NULL
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_old    TEXT;
  v_target public.targets%ROWTYPE;
  v_caller UUID;
BEGIN
  -- ★ [P2 FIX] فالباك
  v_caller := COALESCE(p_user_id, auth.uid());
  IF v_caller IS NULL THEN
    RAISE EXCEPTION '[EDARA] يجب تمرير p_user_id أو استدعاء الدالة من جلسة مُستَوثقة';
  END IF;
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;
  IF NOT check_permission(v_caller, 'targets.update') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية تعديل الأهداف';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'يجب إدخال سبب التعديل';
  END IF;

  IF p_field NOT IN (
    'target_value', 'min_value', 'stretch_value', 'period_end',
    'is_paused', 'is_active', 'filter_criteria',
    'reward_base_value', 'auto_payout', 'payout_month_offset',
    'reward_type', 'reward_pool_basis'
  ) THEN
    RAISE EXCEPTION 'الحقل غير مسموح بتعديله: %', p_field;
  END IF;

  SELECT * INTO v_target FROM public.targets WHERE id = p_target_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'الهدف غير موجود'; END IF;

  -- قفل حقول المكافأة الجوهرية بعد أول committed
  IF p_field IN ('reward_type', 'reward_pool_basis', 'reward_base_value') THEN
    IF EXISTS (
      SELECT 1 FROM public.target_reward_payouts
      WHERE target_id = p_target_id AND status = 'committed'
    ) THEN
      RAISE EXCEPTION '[EDARA] لا يمكن تعديل [%] — تم تثبيت مكافأة بالفعل. أنشئ هدفاً جديداً للفترة القادمة.', p_field;
    END IF;
  END IF;

  -- منع تفعيل auto_payout بدون مكافأة وشرائح
  IF p_field = 'auto_payout' AND p_new_value::BOOLEAN = true THEN
    IF v_target.reward_type IS NULL OR v_target.reward_base_value IS NULL OR v_target.reward_base_value <= 0 THEN
      RAISE EXCEPTION 'لا يمكن تفعيل auto_payout — حدِّد نوع المكافأة وقيمتها أولاً';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.target_reward_tiers WHERE target_id = p_target_id) THEN
      RAISE EXCEPTION 'لا يمكن تفعيل auto_payout — أضِف شريحة مكافأة واحدة على الأقل أولاً';
    END IF;
  END IF;

  -- تحقق من اتساق محاور المكافأة عند التعديل
  IF p_field IN ('reward_type', 'reward_pool_basis') THEN
    DECLARE
      v_type_code TEXT; v_type_cat TEXT;
      v_new_type  TEXT := CASE WHEN p_field = 'reward_type'       THEN p_new_value ELSE v_target.reward_type       END;
      v_new_basis TEXT := CASE WHEN p_field = 'reward_pool_basis' THEN p_new_value ELSE v_target.reward_pool_basis END;
    BEGIN
      SELECT tt.code, tt.category INTO v_type_code, v_type_cat
      FROM public.target_types tt WHERE tt.id = v_target.type_id;
      IF NOT public.is_valid_reward_config(v_type_cat, v_type_code, v_new_type, v_new_basis) THEN
        RAISE EXCEPTION '[EDARA] التركيبة الجديدة للمكافأة غير صالحة لهذا النوع من الأهداف';
      END IF;
    END;
  END IF;

  -- حذف pending عند تغيير حقول المكافأة
  IF p_field IN ('reward_base_value', 'auto_payout', 'reward_type', 'reward_pool_basis', 'payout_month_offset') THEN
    DELETE FROM public.target_reward_payouts
    WHERE target_id = p_target_id AND status = 'pending';
  END IF;

  EXECUTE format('SELECT (%I)::TEXT FROM public.targets WHERE id = $1', p_field)
  INTO v_old USING p_target_id;

  EXECUTE format('UPDATE public.targets SET %I = $1::' ||
    CASE p_field
      WHEN 'target_value'        THEN 'NUMERIC'
      WHEN 'min_value'           THEN 'NUMERIC'
      WHEN 'stretch_value'       THEN 'NUMERIC'
      WHEN 'reward_base_value'   THEN 'NUMERIC'
      WHEN 'payout_month_offset' THEN 'INTEGER'
      WHEN 'period_end'          THEN 'DATE'
      WHEN 'is_paused'           THEN 'BOOLEAN'
      WHEN 'is_active'           THEN 'BOOLEAN'
      WHEN 'auto_payout'         THEN 'BOOLEAN'
      WHEN 'filter_criteria'     THEN 'JSONB'
      ELSE 'TEXT'
    END || ', paused_at = CASE WHEN $2 = ''is_paused'' AND $1::BOOLEAN THEN now() ELSE paused_at END,
    updated_at = now() WHERE id = $3',
    p_field)
  USING p_new_value, p_field, p_target_id;

  INSERT INTO public.target_adjustments (target_id, field_changed, old_value, new_value, reason, adjusted_by)
  VALUES (p_target_id, p_field, v_old, p_new_value, p_reason, v_caller);

  PERFORM public.recalculate_target_progress(p_target_id, CURRENT_DATE);
END;
$$;

-- ════════════════════════════════════════════════════════════
-- SECTION 4: add_bonus_to_payroll_journal() — مساعد Dr.5335
-- (تُستدعى من approve_payroll_run في 22d_payroll_sync.sql)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.add_bonus_to_payroll_journal(
  p_je_id       UUID,
  p_bonus_total NUMERIC,
  p_period_name TEXT
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_coa_bonus UUID;
  v_coa_payable UUID;
BEGIN
  IF COALESCE(p_bonus_total, 0) <= 0 THEN RETURN; END IF;

  SELECT id INTO v_coa_bonus   FROM public.chart_of_accounts WHERE code = '5335' AND is_active = true;
  SELECT id INTO v_coa_payable FROM public.chart_of_accounts WHERE code = '2310' AND is_active = true;

  IF v_coa_bonus IS NULL OR v_coa_payable IS NULL THEN RETURN; END IF;

  -- Dr. 5335: مصروف مكافآت الأهداف
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (p_je_id, v_coa_bonus, p_bonus_total, 0,
          'مكافآت أهداف الموظفين — ' || p_period_name);

  -- Cr. 2310: رواتب مستحقة (نفس الحساب الدائن للرواتب — المكافأة تُصرف معها)
  INSERT INTO journal_entry_lines (entry_id, account_id, debit, credit, description)
  VALUES (p_je_id, v_coa_payable, 0, p_bonus_total,
          'استحقاق مكافآت الأهداف — ' || p_period_name);

  -- تحديث إجماليات رأس القيد للحفاظ على Dr=Cr
  UPDATE journal_entries
  SET total_debit  = total_debit  + p_bonus_total,
      total_credit = total_credit + p_bonus_total
  WHERE id = p_je_id;
END; $$;

-- ════════════════════════════════════════════════════════════
-- SECTION 5: Grants
-- ════════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION public.create_target_with_rewards          TO authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_target_reward_payouts(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.adjust_target                       TO authenticated;
GRANT EXECUTE ON FUNCTION public.calc_target_pool_value              TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_valid_reward_config              TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_bonus_to_payroll_journal        TO authenticated;

-- ════════════════════════════════════════════════════════════
-- نهاية 22c_target_payouts.sql (v2 — مُصلح)
-- الخطوة التالية للاعتماد من كوديكس: 22a + 22b + 22c (v2)
-- ثم 22d_payroll_sync.sql — التعديل الفعلي لـ approve_payroll_run
-- ════════════════════════════════════════════════════════════
