BEGIN;
CREATE OR REPLACE FUNCTION get_base_quantity(
  p_product_id UUID, p_unit_id UUID, p_quantity NUMERIC
) RETURNS NUMERIC
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE v_factor NUMERIC; v_base_unit UUID;
BEGIN
  SELECT base_unit_id INTO v_base_unit FROM products WHERE id = p_product_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'المنتج غير موجود'; END IF;

  -- إذا كانت نفس الوحدة الأساسية
  IF v_base_unit = p_unit_id THEN RETURN p_quantity; END IF;

  SELECT conversion_factor INTO v_factor
  FROM product_units
  WHERE product_id = p_product_id AND unit_id = p_unit_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الوحدة غير مرتبطة بهذا المنتج';
  END IF;

  RETURN p_quantity * v_factor;
END; $$;
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS last_purchase_price NUMERIC(14,4);
ROLLBACK;
