-- Batch dashboard reads without bypassing the caller's existing RLS policies.
CREATE FUNCTION public.get_dashboard_overview_metrics()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,public
AS $overview$
 SELECT jsonb_build_object(
  'activeCustomers',(SELECT count(*) FROM public.customers WHERE is_active),
  'activeProducts',(SELECT count(*) FROM public.products WHERE is_active),
  'activeWarehouses',(SELECT count(*) FROM public.warehouses WHERE is_active),
  'stockItems',(SELECT count(*) FROM public.stock),
  'pendingSalesOrders',(SELECT count(*) FROM public.sales_orders WHERE status IN('confirmed','partially_delivered')),
  'pendingPurchaseInvoices',(SELECT count(*) FROM public.purchase_invoices WHERE status='draft'),
  'lowStockItems',(SELECT coalesce(max(total_count),0) FROM public.get_low_stock(p_warehouse_id=>NULL,p_offset=>0,p_limit=>1))
 );
$overview$;
REVOKE ALL ON FUNCTION public.get_dashboard_overview_metrics() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_dashboard_overview_metrics() TO authenticated;

CREATE FUNCTION public.get_dashboard_sales_metrics(p_today timestamptz,p_month_start timestamptz)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,public
AS $sales$
 SELECT jsonb_build_object(
  'todayRevenue',coalesce(sum(total_amount) FILTER(WHERE status='delivered' AND created_at>=p_today),0),
  'monthRevenue',coalesce(sum(total_amount) FILTER(WHERE status='delivered' AND created_at>=p_month_start),0),
  'pendingOrders',count(*) FILTER(WHERE status IN('confirmed','partially_delivered')),
  'deliveredToday',count(*) FILTER(WHERE status='delivered' AND created_at>=p_today)
 ) FROM public.sales_orders;
$sales$;
REVOKE ALL ON FUNCTION public.get_dashboard_sales_metrics(timestamptz,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_dashboard_sales_metrics(timestamptz,timestamptz) TO authenticated;

-- Preserve the existing RPC shape, visibility and totals while scanning sales once.
CREATE OR REPLACE FUNCTION public.get_sales_stats()
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public
AS $stats$
 WITH status_totals AS MATERIALIZED (
  SELECT status,count(*) cnt,coalesce(sum(total_amount),0) amount
  FROM public.sales_orders GROUP BY status
 )
 SELECT json_build_object(
  'status_counts',coalesce(json_object_agg(status,cnt),'{}'::json),
  'total_sales',coalesce(sum(amount) FILTER(WHERE status IN('delivered','completed')),0),
  'total_orders',coalesce(sum(cnt),0)
 ) FROM status_totals;
$stats$;
