-- ════════════════════════════════════════════════════════════
-- 03b_approval_fixes.sql
-- إصلاحات سلسلة الموافقات: تجاوز super_admin + بيانات أولية
-- ════════════════════════════════════════════════════════════

-- 1. إضافة قاعدة موافقة لـ super_admin (الاسم الصحيح للدور)
INSERT INTO approval_rules (type, role_id, max_amount, sort_order)
SELECT 'expense', id, 99999999.99, 0
FROM roles WHERE name = 'super_admin'
ON CONFLICT (type, role_id) DO UPDATE SET max_amount = 99999999.99, sort_order = 0;

-- 2. إضافة قاعدة موافقة لـ CEO أيضاً (تأمين إضافي)
INSERT INTO approval_rules (type, role_id, max_amount, sort_order)
SELECT 'expense', id, 50000, 3
FROM roles WHERE name = 'ceo'
ON CONFLICT (type, role_id) DO NOTHING;

-- حذف السجل الخاطئ (admin) إن كان موجوداً
DELETE FROM approval_rules WHERE role_id NOT IN (SELECT id FROM roles);


-- ════════════════════════════════════════════════════════════
-- 3. إعادة إنشاء دالة approve_expense مع تجاوز لحامل * (wildcard)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION approve_expense(
  p_expense_id  UUID,
  p_action      TEXT,      -- 'approve' أو 'reject'
  p_reason      TEXT,      -- سبب الرفض (NULL للموافقة)
  p_user_id     UUID
) RETURNS VOID
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_expense      expenses%ROWTYPE;
  v_can_approve  BOOLEAN;
  v_is_superuser BOOLEAN;
  v_cat_name     TEXT;
BEGIN
  -- S3: فحص الصلاحية الأساسية
  IF NOT check_permission(p_user_id, 'finance.expenses.approve') THEN
    RAISE EXCEPTION 'لا تملك صلاحية الموافقة على المصروفات';
  END IF;

  -- 1. قفل المصروف
  SELECT * INTO v_expense
  FROM expenses
  WHERE id = p_expense_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المصروف غير موجود';
  END IF;

  IF v_expense.status != 'pending_approval' THEN
    RAISE EXCEPTION 'المصروف ليس في حالة انتظار الموافقة (الحالة: %)', v_expense.status;
  END IF;

  IF p_action = 'approve' THEN
    -- 2a. فحص: هل المستخدم يحمل صلاحية * (super_admin)؟
    --     إذا نعم → تجاوز فحص approval_rules بالكامل
    SELECT EXISTS (
      SELECT 1 FROM role_permissions rp
      JOIN user_roles ur ON ur.role_id = rp.role_id
      WHERE ur.user_id = p_user_id
        AND ur.is_active = true
        AND rp.permission = '*'
    ) INTO v_is_superuser;

    IF NOT v_is_superuser THEN
      -- 2b. فحص سلسلة الموافقات للمستخدمين العاديين
      SELECT EXISTS (
        SELECT 1 FROM approval_rules ar
        JOIN user_roles ur ON ur.role_id = ar.role_id
        WHERE ar.type = 'expense'
          AND ar.max_amount >= v_expense.amount
          AND ar.is_active = true
          AND ur.user_id = p_user_id
          AND ur.is_active = true
      ) INTO v_can_approve;

      IF NOT v_can_approve THEN
        RAISE EXCEPTION 'لا تملك صلاحية اعتماد مصروف بهذا المبلغ (الحد الأقصى المسموح لدورك أقل من %)', v_expense.amount;
      END IF;
    END IF;

    -- 3. خصم من المصدر
    IF v_expense.payment_source = 'vault' AND v_expense.vault_id IS NOT NULL THEN
      PERFORM add_vault_transaction(
        v_expense.vault_id, 'expense', v_expense.amount,
        'expense', p_expense_id,
        v_expense.description,
        p_user_id
      );
    ELSIF v_expense.payment_source = 'custody' AND v_expense.custody_id IS NOT NULL THEN
      PERFORM add_custody_transaction(
        v_expense.custody_id, 'expense', v_expense.amount,
        NULL, 'expense', p_expense_id,
        v_expense.description,
        p_user_id
      );
    ELSE
      RAISE EXCEPTION 'يجب تحديد مصدر الدفع (خزنة أو عهدة)';
    END IF;

    -- 4. جلب اسم التصنيف للقيد
    SELECT name INTO v_cat_name FROM expense_categories WHERE id = v_expense.category_id;

    -- 5. إنشاء قيد محاسبي تلقائي
    --    DR: مصروفات   →   CR: صندوق/بنك/عهدة
    PERFORM create_auto_journal_entry(
      'expense', p_expense_id,
      'مصروف — ' || COALESCE(v_cat_name, v_expense.description),
      '5200',                             -- مصروفات تشغيلية
      -- F10: تحديد الحساب الدائن حسب المصدر ونوع الخزنة
      CASE v_expense.payment_source
        WHEN 'custody' THEN '1400'        -- عُهد
        WHEN 'vault' THEN
          CASE (SELECT type FROM vaults WHERE id = v_expense.vault_id)
            WHEN 'cash' THEN '1110'
            WHEN 'bank' THEN '1120'
            WHEN 'mobile_wallet' THEN '1130'
            ELSE '1110'                    -- T2: fallback
          END
        ELSE '1110'                        -- U3: safety net
      END,
      v_expense.amount,
      p_user_id
    );

    -- 6. تحديث المصروف
    UPDATE expenses
    SET status = 'approved',
        approved_by = p_user_id,
        approved_at = now()
    WHERE id = p_expense_id;

  ELSIF p_action = 'reject' THEN
    UPDATE expenses
    SET status = 'rejected',
        rejection_reason = p_reason,
        approved_by = p_user_id,
        approved_at = now()
    WHERE id = p_expense_id;

  ELSE
    RAISE EXCEPTION 'الإجراء يجب أن يكون approve أو reject';
  END IF;
END; $$;
