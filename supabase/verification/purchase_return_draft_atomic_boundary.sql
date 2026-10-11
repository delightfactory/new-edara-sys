-- Owned synthetic fixture only: runner sets request.jwt.claim.sub after BEGIN.
-- Uses the isolated C3 reference supplier/warehouse/products; always rolls back.
BEGIN;
INSERT INTO public.purchase_returns(id,number,supplier_id,warehouse_id,created_by,notes)
VALUES ('33000000-0000-4000-8000-000000000001','C3-ATOMIC-BOUNDARY',
 '10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000005',auth.uid(),'before');
INSERT INTO public.purchase_return_items(return_id,product_id,unit_id,quantity,unit_price)
VALUES ('33000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002',
 '10000000-0000-4000-8000-000000000001',1,10);
DO $$
DECLARE v_id uuid := '33000000-0000-4000-8000-000000000001';
BEGIN
 PERFORM public.update_purchase_return_draft(v_id,'{"notes":"header only"}',NULL);
 IF (SELECT notes FROM public.purchase_returns WHERE id=v_id) <> 'header only'
    OR (SELECT count(*) FROM public.purchase_return_items WHERE return_id=v_id) <> 1 THEN
   RAISE EXCEPTION 'Header-only edit changed items';
 END IF;
 PERFORM public.update_purchase_return_draft(v_id,'{}','[]');
 IF (SELECT count(*) FROM public.purchase_return_items WHERE return_id=v_id) <> 0
    OR (SELECT total_amount FROM public.purchase_returns WHERE id=v_id) <> 0 THEN
   RAISE EXCEPTION 'Empty-item draft did not clear totals';
 END IF;
 PERFORM public.update_purchase_return_draft(v_id,'{}',$items$[
  {"product_id":"10000000-0000-4000-8000-000000000002","unit_id":"10000000-0000-4000-8000-000000000001","quantity":1,"unit_price":0.335,"discount_rate":10,"tax_rate":14},
  {"product_id":"10000000-0000-4000-8000-000000000003","unit_id":"10000000-0000-4000-8000-000000000001","quantity":1,"unit_price":0.335,"discount_rate":10,"tax_rate":14}
 ]$items$::jsonb);
 IF NOT EXISTS (SELECT 1 FROM public.purchase_returns WHERE id=v_id
   AND subtotal=0.67 AND discount_amount=0.07 AND tax_amount=0.08 AND total_amount=0.69) THEN
   RAISE EXCEPTION 'Totals did not round aggregate sums once';
 END IF;
END;
$$;
ROLLBACK;
