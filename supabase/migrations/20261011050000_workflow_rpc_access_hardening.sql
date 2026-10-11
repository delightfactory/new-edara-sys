-- Close confirmed direct helper access and anonymous sales identity spoofing.
-- Helpers remain callable by their owning SECURITY DEFINER workflows.
-- No function bodies, financial calculations, table grants or RLS policies change.
REVOKE EXECUTE ON FUNCTION public.reserve_stock(uuid, uuid, numeric) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.unreserve_stock(uuid, uuid, numeric) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.add_vault_transaction(uuid, text, numeric, text, uuid, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_stock(uuid, uuid, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.unreserve_stock(uuid, uuid, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.add_vault_transaction(uuid, text, numeric, text, uuid, text, uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION public.confirm_sales_order(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.cancel_sales_order(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_sales_order(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_sales_order(uuid, uuid, text) TO authenticated, service_role;
