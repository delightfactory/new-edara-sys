-- Edit only a readable, writable draft in one transaction; failed item writes
-- roll back header, old items and totals together.
CREATE OR REPLACE FUNCTION public.update_purchase_return_draft(
  p_return_id uuid,
  p_header jsonb DEFAULT '{}'::jsonb,
  p_items jsonb DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_return public.purchase_returns%ROWTYPE;
  v_header jsonb := COALESCE(p_header, '{}'::jsonb);
BEGIN
  IF v_actor IS NULL OR NOT public.check_permission(v_actor, 'procurement.returns.create')
     OR NOT public.check_permission(v_actor, 'procurement.returns.read') THEN
    RAISE EXCEPTION 'لا تملك صلاحية تعديل مرتجع المشتريات' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(v_header) <> 'object'
     OR v_header - ARRAY['supplier_id','warehouse_id','original_invoice_id','return_date','notes'] <> '{}'::jsonb
     OR (p_items IS NOT NULL AND jsonb_typeof(p_items) <> 'array') THEN
    RAISE EXCEPTION 'بيانات تعديل المرتجع غير صالحة' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_return FROM public.purchase_returns WHERE id = p_return_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'مرتجع المشتريات غير موجود' USING ERRCODE = 'P0002';
  END IF;
  IF v_return.status <> 'draft' THEN
    RAISE EXCEPTION 'يمكن تعديل مسودة المرتجع فقط' USING ERRCODE = '55000';
  END IF;
  UPDATE public.purchase_returns SET
    supplier_id = CASE WHEN v_header ? 'supplier_id' THEN (v_header->>'supplier_id')::uuid ELSE v_return.supplier_id END,
    warehouse_id = CASE WHEN v_header ? 'warehouse_id' THEN (v_header->>'warehouse_id')::uuid ELSE v_return.warehouse_id END,
    original_invoice_id = CASE WHEN v_header ? 'original_invoice_id' THEN (v_header->>'original_invoice_id')::uuid ELSE v_return.original_invoice_id END,
    return_date = CASE WHEN v_header ? 'return_date' THEN (v_header->>'return_date')::date ELSE v_return.return_date END,
    notes = CASE WHEN v_header ? 'notes' THEN v_header->>'notes' ELSE v_return.notes END,
    updated_at = now()
  WHERE id = p_return_id;
  IF p_items IS NOT NULL THEN
    DELETE FROM public.purchase_return_items WHERE return_id = p_return_id;
    INSERT INTO public.purchase_return_items(return_id,product_id,unit_id,quantity,unit_price,discount_rate,tax_rate)
    SELECT p_return_id,i.product_id,i.unit_id,i.quantity,i.unit_price,
      COALESCE(i.discount_rate,0),COALESCE(i.tax_rate,0)
    FROM jsonb_to_recordset(p_items) AS i(product_id uuid,unit_id uuid,quantity numeric,unit_price numeric,discount_rate numeric,tax_rate numeric);
    UPDATE public.purchase_returns r SET
      subtotal = ROUND(t.subtotal,2), discount_amount = ROUND(t.discount_amount,2),
      tax_amount = ROUND(t.tax_amount,2), total_amount = ROUND(t.subtotal-t.discount_amount+t.tax_amount,2)
    FROM (
      SELECT COALESCE(SUM(quantity*unit_price),0) subtotal,
        COALESCE(SUM(quantity*unit_price*discount_rate/100),0) discount_amount,
        COALESCE(SUM(quantity*unit_price*(1-discount_rate/100)*tax_rate/100),0) tax_amount
      FROM public.purchase_return_items WHERE return_id = p_return_id
    ) t WHERE r.id = p_return_id;
  END IF;
  RETURN p_return_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.update_purchase_return_draft(uuid,jsonb,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_purchase_return_draft(uuid,jsonb,jsonb) TO authenticated, service_role;
