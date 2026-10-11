-- Allocation is an internal step of receipt confirmation, not a client ledger writer.
-- Keep both historical overloads and their owner calls without changing accounting.
REVOKE EXECUTE ON FUNCTION public.allocate_payment_to_invoices(uuid,numeric,text,uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.allocate_payment_to_invoices(uuid,numeric,text,uuid,uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.allocate_payment_to_invoices(uuid,numeric,text,uuid,uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.allocate_payment_to_invoices(uuid,numeric,text,uuid,uuid,uuid) TO service_role;

-- Automatic journals are also internal to the saved financial transaction.
REVOKE EXECUTE ON FUNCTION public.create_auto_journal_entry(text,uuid,text,text,text,numeric,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_auto_journal_entry(text,uuid,text,text,text,numeric,uuid) TO service_role;
