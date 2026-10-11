-- Product costs are read through get_product_cost_metrics, which checks finance.view_costs.
-- Table-wide SELECT would override attempts to protect only the financial columns.
REVOKE SELECT ON TABLE public.products FROM PUBLIC, anon, authenticated;
REVOKE SELECT (cost_price, last_purchase_price) ON public.products FROM PUBLIC, anon, authenticated;
GRANT SELECT (
  id, sku, name, barcode, category_id, brand_id, base_unit_id, selling_price,
  tax_rate, description, image_url, is_active, min_stock_level, created_at, updated_at
) ON public.products TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_product_cost_metrics(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_product_cost_metrics(uuid[]) TO authenticated, service_role;
