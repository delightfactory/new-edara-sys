-- Preserve internal owner workflows; authenticate and authorize the public journal entry.
CREATE OR REPLACE FUNCTION create_ui_manual_journal_entry(
  p_description  TEXT,
  p_entry_date   DATE DEFAULT CURRENT_DATE,
  p_source_type  TEXT DEFAULT 'manual',
  p_source_id    UUID DEFAULT NULL,
  p_lines        JSONB DEFAULT '[]'::JSONB,
  p_user_id      UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_blocked_count INT;
  v_actor UUID := auth.uid();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول لإنشاء قيد يدوي' USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NOT NULL AND p_user_id <> v_actor THEN
    RAISE EXCEPTION 'هوية منفذ القيد لا تطابق الجلسة' USING ERRCODE = '42501';
  END IF;
  IF NOT public.check_permission(v_actor, 'finance.journal.create') THEN
    RAISE EXCEPTION 'لا تملك صلاحية إنشاء قيود يدوية' USING ERRCODE = '42501';
  END IF;
  SELECT COUNT(*)
  INTO v_blocked_count
  FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB)) AS l
  WHERE (l ->> 'account_code') IN ('1200', '2100');

  IF v_blocked_count > 0 THEN
    RAISE EXCEPTION 'Direct posting to control accounts 1200 and 2100 is not allowed from the UI';
  END IF;

  RETURN create_manual_journal_entry(
    p_description,
    p_entry_date,
    p_source_type,
    p_source_id,
    p_lines,
    v_actor
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_stock_wac(uuid,uuid,numeric,numeric,text,text,uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_stock_wac(uuid,uuid,numeric,numeric,text,text,uuid,uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.deduct_stock_at_wac(uuid,uuid,numeric,text,text,uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.deduct_stock_at_wac(uuid,uuid,numeric,text,text,uuid,uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.add_custody_transaction(uuid,text,numeric,uuid,text,uuid,text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.add_custody_transaction(uuid,text,numeric,uuid,text,uuid,text,uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.create_manual_journal_entry(text,date,text,uuid,jsonb,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_manual_journal_entry(text,date,text,uuid,jsonb,uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION public.create_ui_manual_journal_entry(text,date,text,uuid,jsonb,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_ui_manual_journal_entry(text,date,text,uuid,jsonb,uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.deliver_sales_order(uuid,uuid,text,text,uuid,uuid,numeric,boolean,text,text,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.deliver_sales_order(uuid,uuid,text,text,uuid,uuid,numeric,boolean,text,text,date) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.confirm_sales_return(uuid,uuid,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_sales_return(uuid,uuid,uuid,uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.receive_purchase_invoice(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.receive_purchase_invoice(uuid,uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.bill_purchase_invoice(uuid,uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bill_purchase_invoice(uuid,uuid,uuid,text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.pay_supplier(uuid,uuid,numeric,text,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pay_supplier(uuid,uuid,numeric,text,uuid,text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.cancel_purchase_invoice(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_purchase_invoice(uuid,uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.confirm_purchase_return(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_purchase_return(uuid,uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.confirm_payment_receipt(uuid,text,uuid,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_payment_receipt(uuid,text,uuid,text,uuid) TO authenticated, service_role;
