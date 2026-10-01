-- PARTIAL installed-contract layer; no source RPCs, network hooks or complete FK graph.
CREATE TYPE public.hr_employee_status AS ENUM ('active','on_leave','suspended','terminated');
CREATE TYPE public.sales_order_status AS ENUM ('draft','confirmed','partially_delivered','delivered','completed','cancelled');
CREATE TYPE public.sales_return_status AS ENUM ('draft','confirmed','cancelled');
ALTER TABLE public.sales_order_items ADD COLUMN quantity numeric(12,2) DEFAULT 0;
ALTER TABLE public.sales_order_items ADD COLUMN unit_price numeric(14,4) DEFAULT 0;
ALTER TABLE public.sales_order_items ADD COLUMN discount_percent numeric(5,2) DEFAULT 0;
ALTER TABLE public.sales_order_items ADD COLUMN discount_amount numeric(14,2) DEFAULT 0;
ALTER TABLE public.sales_order_items ADD COLUMN tax_rate numeric(5,2) DEFAULT 0;
ALTER TABLE public.customers ADD COLUMN opening_balance numeric(14,2) DEFAULT 0;
ALTER TABLE public.customers ADD COLUMN current_balance numeric(14,2) DEFAULT 0;
ALTER TABLE public.customers ADD COLUMN assigned_rep_id uuid;
ALTER TABLE public.customers ADD COLUMN updated_at timestamp with time zone DEFAULT now();
ALTER TABLE public.customers ADD COLUMN payment_terms text;
ALTER TABLE public.customers ADD COLUMN type text;
ALTER TABLE public.hr_employees ADD COLUMN updated_at timestamp with time zone DEFAULT now();
ALTER TABLE public.hr_employees ADD COLUMN attendance_checkin_mode text;
ALTER TABLE public.hr_employees ADD COLUMN attendance_checkout_mode text;
ALTER TABLE public.expenses ADD COLUMN updated_at timestamp with time zone DEFAULT now();
ALTER TABLE public.expenses ADD COLUMN amount numeric(14,2) DEFAULT 0;
ALTER TABLE public.expenses ADD COLUMN payment_source text;
ALTER TABLE public.expenses ADD COLUMN status text;
ALTER TABLE public.hr_payroll_runs ADD COLUMN updated_at timestamp with time zone DEFAULT now();
ALTER TABLE public.hr_payroll_runs ADD COLUMN calculation_mode text;
ALTER TABLE public.sales_orders ADD COLUMN payment_terms text;
ALTER TABLE public.sales_return_items ADD COLUMN quantity numeric(12,2) DEFAULT 0;
ALTER TABLE public.payment_receipts ADD COLUMN payment_method text;
ALTER TABLE public.journal_entries ADD COLUMN total_debit numeric(14,2) DEFAULT 0;
ALTER TABLE public.journal_entries ADD COLUMN total_credit numeric(14,2) DEFAULT 0;
ALTER TABLE public.chart_of_accounts ADD COLUMN type text;
ALTER TABLE public.sales_orders ALTER COLUMN total_amount TYPE numeric(14,2) USING total_amount::numeric(14,2);
ALTER TABLE public.sales_orders ALTER COLUMN credit_amount TYPE numeric(14,2) USING credit_amount::numeric(14,2);
ALTER TABLE public.sales_orders ALTER COLUMN tax_amount TYPE numeric(14,2) USING tax_amount::numeric(14,2);
ALTER TABLE public.sales_orders ALTER COLUMN status TYPE sales_order_status USING status::sales_order_status;
ALTER TABLE public.sales_orders ALTER COLUMN subtotal TYPE numeric(14,2) USING subtotal::numeric(14,2);
ALTER TABLE public.sales_order_items ALTER COLUMN base_quantity TYPE numeric(12,2) USING base_quantity::numeric(12,2);
ALTER TABLE public.sales_order_items ALTER COLUMN unit_price TYPE numeric(14,4) USING unit_price::numeric(14,4);
ALTER TABLE public.sales_order_items ALTER COLUMN discount_amount TYPE numeric(14,2) USING discount_amount::numeric(14,2);
ALTER TABLE public.sales_order_items ALTER COLUMN tax_rate TYPE numeric(5,2) USING tax_rate::numeric(5,2);
ALTER TABLE public.sales_order_items ALTER COLUMN unit_cost_at_sale TYPE numeric(14,4) USING unit_cost_at_sale::numeric(14,4);
ALTER TABLE public.sales_order_items ALTER COLUMN discount_percent TYPE numeric(5,2) USING discount_percent::numeric(5,2);
ALTER TABLE public.sales_order_items ALTER COLUMN quantity TYPE numeric(12,2) USING quantity::numeric(12,2);
ALTER TABLE public.sales_order_items ALTER COLUMN tax_amount TYPE numeric(14,2) USING tax_amount::numeric(14,2);
ALTER TABLE public.sales_order_items ALTER COLUMN line_total TYPE numeric(14,2) USING line_total::numeric(14,2);
ALTER TABLE public.sales_returns ALTER COLUMN status TYPE sales_return_status USING status::sales_return_status;
ALTER TABLE public.sales_return_items ALTER COLUMN base_quantity TYPE numeric(12,2) USING base_quantity::numeric(12,2);
ALTER TABLE public.sales_return_items ALTER COLUMN quantity TYPE numeric(12,2) USING quantity::numeric(12,2);
ALTER TABLE public.sales_return_items ALTER COLUMN line_total TYPE numeric(14,2) USING line_total::numeric(14,2);
ALTER TABLE public.payment_receipts ALTER COLUMN amount TYPE numeric(14,2) USING amount::numeric(14,2);
ALTER TABLE public.customer_ledger ALTER COLUMN amount TYPE numeric(14,2) USING amount::numeric(14,2);
ALTER TABLE public.vault_transactions ALTER COLUMN amount TYPE numeric(14,2) USING amount::numeric(14,2);
ALTER TABLE public.custody_transactions ALTER COLUMN amount TYPE numeric(14,2) USING amount::numeric(14,2);
ALTER TABLE public.journal_entries ALTER COLUMN total_credit TYPE numeric(14,2) USING total_credit::numeric(14,2);
ALTER TABLE public.journal_entries ALTER COLUMN total_debit TYPE numeric(14,2) USING total_debit::numeric(14,2);
ALTER TABLE public.journal_entry_lines ALTER COLUMN debit TYPE numeric(14,2) USING debit::numeric(14,2);
ALTER TABLE public.journal_entry_lines ALTER COLUMN credit TYPE numeric(14,2) USING credit::numeric(14,2);
ALTER TABLE public.customers ALTER COLUMN current_balance TYPE numeric(14,2) USING current_balance::numeric(14,2);
ALTER TABLE public.customers ALTER COLUMN opening_balance TYPE numeric(14,2) USING opening_balance::numeric(14,2);
ALTER TABLE public.expenses ALTER COLUMN amount TYPE numeric(14,2) USING amount::numeric(14,2);
ALTER TABLE public.hr_employees ALTER COLUMN status TYPE hr_employee_status USING status::hr_employee_status;
ALTER TABLE public.sales_orders ADD CONSTRAINT sales_orders_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES branches(id);
ALTER TABLE public.sales_orders ADD CONSTRAINT sales_orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.sales_orders ADD CONSTRAINT sales_orders_rep_id_fkey FOREIGN KEY (rep_id) REFERENCES profiles(id);
ALTER TABLE public.sales_returns ADD CONSTRAINT sales_returns_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.sales_returns ADD CONSTRAINT sales_returns_order_id_fkey FOREIGN KEY (order_id) REFERENCES sales_orders(id);
ALTER TABLE public.sales_return_items ADD CONSTRAINT sales_return_items_order_item_id_fkey FOREIGN KEY (order_item_id) REFERENCES sales_order_items(id);
ALTER TABLE public.payment_receipts ADD CONSTRAINT payment_receipts_collected_by_fkey FOREIGN KEY (collected_by) REFERENCES profiles(id);
ALTER TABLE public.payment_receipts ADD CONSTRAINT payment_receipts_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.payment_receipts ADD CONSTRAINT payment_receipts_sales_order_id_fkey FOREIGN KEY (sales_order_id) REFERENCES sales_orders(id);
ALTER TABLE public.customer_ledger ADD CONSTRAINT customer_ledger_allocated_to_fkey FOREIGN KEY (allocated_to) REFERENCES customer_ledger(id);
ALTER TABLE public.customer_ledger ADD CONSTRAINT customer_ledger_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.journal_entry_lines ADD CONSTRAINT journal_entry_lines_account_id_fkey FOREIGN KEY (account_id) REFERENCES chart_of_accounts(id);
ALTER TABLE public.customers ADD CONSTRAINT customers_assigned_rep_id_fkey FOREIGN KEY (assigned_rep_id) REFERENCES profiles(id);
ALTER TABLE public.expenses ADD CONSTRAINT expenses_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES branches(id);
ALTER TABLE public.hr_payroll_runs ADD CONSTRAINT hr_payroll_runs_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES branches(id);
ALTER TABLE public.hr_employees ADD CONSTRAINT hr_employees_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES branches(id);
ALTER TABLE public.sales_orders ADD CONSTRAINT sales_orders_payment_terms_check CHECK ((payment_terms = ANY (ARRAY['cash'::text, 'credit'::text, 'mixed'::text])));
ALTER TABLE public.sales_order_items ADD CONSTRAINT sales_order_items_base_quantity_check CHECK ((base_quantity > (0)::numeric));
ALTER TABLE public.sales_order_items ADD CONSTRAINT sales_order_items_discount_percent_check CHECK (((discount_percent >= (0)::numeric) AND (discount_percent <= (100)::numeric)));
ALTER TABLE public.sales_order_items ADD CONSTRAINT sales_order_items_quantity_check CHECK ((quantity > (0)::numeric));
ALTER TABLE public.sales_return_items ADD CONSTRAINT sales_return_items_base_quantity_check CHECK ((base_quantity > (0)::numeric));
ALTER TABLE public.sales_return_items ADD CONSTRAINT sales_return_items_quantity_check CHECK ((quantity > (0)::numeric));
ALTER TABLE public.payment_receipts ADD CONSTRAINT payment_receipts_amount_check CHECK ((amount > (0)::numeric));
ALTER TABLE public.payment_receipts ADD CONSTRAINT payment_receipts_payment_method_check CHECK ((payment_method = ANY (ARRAY['cash'::text, 'bank_transfer'::text, 'instapay'::text, 'cheque'::text, 'mobile_wallet'::text])));
ALTER TABLE public.payment_receipts ADD CONSTRAINT payment_receipts_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'rejected'::text])));
ALTER TABLE public.customer_ledger ADD CONSTRAINT customer_ledger_amount_check CHECK ((amount > (0)::numeric));
ALTER TABLE public.customer_ledger ADD CONSTRAINT customer_ledger_source_type_check CHECK ((source_type = ANY (ARRAY['sales_order'::text, 'sales_return'::text, 'payment'::text, 'payment_receipt'::text, 'opening_balance'::text, 'adjustment'::text])));
ALTER TABLE public.customer_ledger ADD CONSTRAINT customer_ledger_type_check CHECK ((type = ANY (ARRAY['debit'::text, 'credit'::text])));
ALTER TABLE public.vault_transactions ADD CONSTRAINT vault_transactions_amount_check CHECK ((amount > (0)::numeric));
ALTER TABLE public.vault_transactions ADD CONSTRAINT vault_transactions_type_check CHECK ((type = ANY (ARRAY['deposit'::text, 'withdrawal'::text, 'transfer_in'::text, 'transfer_out'::text, 'collection'::text, 'expense'::text, 'custody_load'::text, 'custody_return'::text, 'opening_balance'::text, 'vendor_payment'::text, 'vendor_refund'::text, 'payroll_payment'::text])));
ALTER TABLE public.custody_transactions ADD CONSTRAINT custody_transactions_amount_check CHECK ((amount > (0)::numeric));
ALTER TABLE public.custody_transactions ADD CONSTRAINT custody_transactions_type_check CHECK ((type = ANY (ARRAY['load'::text, 'collection'::text, 'expense'::text, 'settlement'::text, 'return'::text])));
ALTER TABLE public.journal_entries ADD CONSTRAINT chk_balanced_entry CHECK ((total_debit = total_credit));
ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_source_type_check CHECK ((source_type = ANY (ARRAY['sales_order'::text, 'sales_return'::text, 'payment'::text, 'purchase_order'::text, 'purchase_return'::text, 'purchase_cancellation'::text, 'expense'::text, 'custody'::text, 'transfer'::text, 'manual'::text, 'hr_advance'::text, 'hr_payroll'::text, 'supplier_payment'::text, 'hr_payroll_payment'::text])));
ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'posted'::text])));
ALTER TABLE public.journal_entry_lines ADD CONSTRAINT chk_debit_or_credit CHECK ((((debit > (0)::numeric) AND (credit = (0)::numeric)) OR ((credit > (0)::numeric) AND (debit = (0)::numeric))));
ALTER TABLE public.journal_entry_lines ADD CONSTRAINT journal_entry_lines_credit_check CHECK ((credit >= (0)::numeric));
ALTER TABLE public.journal_entry_lines ADD CONSTRAINT journal_entry_lines_debit_check CHECK ((debit >= (0)::numeric));
ALTER TABLE public.customers ADD CONSTRAINT customers_payment_terms_check CHECK ((payment_terms = ANY (ARRAY['cash'::text, 'credit'::text, 'mixed'::text])));
ALTER TABLE public.customers ADD CONSTRAINT customers_type_check CHECK ((type = ANY (ARRAY['retail'::text, 'wholesale'::text, 'distributor'::text])));
ALTER TABLE public.expenses ADD CONSTRAINT expenses_amount_check CHECK ((amount > (0)::numeric));
ALTER TABLE public.expenses ADD CONSTRAINT expenses_payment_source_check CHECK ((payment_source = ANY (ARRAY['vault'::text, 'custody'::text])));
ALTER TABLE public.expenses ADD CONSTRAINT expenses_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'pending_approval'::text, 'approved'::text, 'rejected'::text])));
ALTER TABLE public.hr_payroll_runs ADD CONSTRAINT hr_payroll_runs_calculation_mode_check CHECK ((calculation_mode = ANY (ARRAY['interim'::text, 'final'::text])));
ALTER TABLE public.chart_of_accounts ADD CONSTRAINT chart_of_accounts_type_check CHECK ((type = ANY (ARRAY['asset'::text, 'liability'::text, 'equity'::text, 'revenue'::text, 'expense'::text])));
ALTER TABLE public.hr_employees ADD CONSTRAINT hr_employees_attendance_checkin_mode_check CHECK ((attendance_checkin_mode = ANY (ARRAY['assigned_only'::text, 'field_allowed'::text])));
ALTER TABLE public.hr_employees ADD CONSTRAINT hr_employees_attendance_checkout_mode_check CHECK ((attendance_checkout_mode = ANY (ARRAY['assigned_only'::text, 'field_allowed'::text])));
ALTER TABLE public.profiles ADD COLUMN status text DEFAULT 'active';
CREATE TABLE public.company_settings(key text PRIMARY KEY,value jsonb);
INSERT INTO public.company_settings VALUES('sales.tax_enabled','true');
CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END; $function$;
CREATE OR REPLACE FUNCTION public.validate_sales_item_amounts()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_expected_discount NUMERIC;
  v_expected_tax      NUMERIC;
  v_expected_line     NUMERIC;
  v_tax_enabled       BOOLEAN;
BEGIN
  -- [BE-04] جلب إعداد الضريبة من company_settings
  SELECT COALESCE((value)::boolean, false) INTO v_tax_enabled
  FROM company_settings WHERE key = 'sales.tax_enabled';

  -- حساب الخصم الصحيح
  v_expected_discount := ROUND(
    (NEW.quantity * NEW.unit_price) * (NEW.discount_percent / 100), 2
  );

  -- تصحيح تلقائي (تفادي مشاكل الأعشار — فرق <=٠.٠١ مقبول)
  IF ABS(NEW.discount_amount - v_expected_discount) > 0.01 THEN
    NEW.discount_amount := v_expected_discount;
  END IF;

  -- [BE-04] إذا الضريبة مُعطَّلة من الإعدادات → أجبر الصفر
  IF NOT COALESCE(v_tax_enabled, false) THEN
    NEW.tax_rate   := 0;
    NEW.tax_amount := 0;
  ELSE
    -- حساب الضريبة إجبارياً من tax_rate
    v_expected_tax := ROUND(
      ((NEW.quantity * NEW.unit_price) - NEW.discount_amount) * (NEW.tax_rate / 100), 2
    );
    IF ABS(COALESCE(NEW.tax_amount, 0) - v_expected_tax) > 0.01 THEN
      NEW.tax_amount := v_expected_tax;
    END IF;
  END IF;

  -- حساب إجمالي السطر
  v_expected_line := (NEW.quantity * NEW.unit_price)
                     - NEW.discount_amount
                     + NEW.tax_amount;

  IF ABS(NEW.line_total - v_expected_line) > 0.01 THEN
    NEW.line_total := ROUND(v_expected_line, 2);
  END IF;

  RETURN NEW;
END; $function$;
CREATE OR REPLACE FUNCTION public.guard_customer_opening_balance()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF OLD.opening_balance IS DISTINCT FROM NEW.opening_balance
     AND current_setting('app.finance_context', true) IS DISTINCT FROM 'opening_balance_adjustment' THEN
    RAISE EXCEPTION 'Direct customer opening balance updates are not allowed';
  END IF;

  RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.handle_employee_termination()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- عند تغيير الحالة إلى terminated
  IF NEW.status = 'terminated' AND OLD.status <> 'terminated' THEN
    -- إيقاف الحساب في auth (عبر profiles)
    IF NEW.user_id IS NOT NULL THEN
      UPDATE profiles SET status = 'inactive' WHERE id = NEW.user_id;
    END IF;
    -- تسجيل تاريخ إنهاء الخدمة إذا لم يُحدَّد
    IF NEW.termination_date IS NULL THEN
      NEW.termination_date := CURRENT_DATE;
    END IF;
  END IF;
  RETURN NEW;
END; $function$;
CREATE OR REPLACE FUNCTION public.update_customer_cached_balance()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old_delta NUMERIC;
  v_new_delta NUMERIC;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- عكس الأثر من العميل
    v_old_delta := CASE WHEN OLD.type = 'debit' THEN -OLD.amount ELSE OLD.amount END;
    UPDATE customers SET current_balance = current_balance + v_old_delta
    WHERE id = OLD.customer_id;
    RETURN OLD;

  ELSIF TG_OP = 'INSERT' THEN
    -- مدين = رصيد العميل يزيد (العميل مدين لنا)
    v_new_delta := CASE WHEN NEW.type = 'debit' THEN NEW.amount ELSE -NEW.amount END;
    UPDATE customers SET current_balance = current_balance + v_new_delta
    WHERE id = NEW.customer_id;
    RETURN NEW;

  ELSE -- UPDATE
    -- عكس الأثر القديم من العميل القديم
    v_old_delta := CASE WHEN OLD.type = 'debit' THEN OLD.amount ELSE -OLD.amount END;
    UPDATE customers SET current_balance = current_balance - v_old_delta
    WHERE id = OLD.customer_id;
    -- تطبيق الأثر الجديد على العميل الجديد (قد يكون نفسه أو مختلف)
    v_new_delta := CASE WHEN NEW.type = 'debit' THEN NEW.amount ELSE -NEW.amount END;
    UPDATE customers SET current_balance = current_balance + v_new_delta
    WHERE id = NEW.customer_id;
    RETURN NEW;
  END IF;
END; $function$;
DROP TRIGGER fixture_updated_at ON public.sales_orders;
DROP TRIGGER fixture_updated_at ON public.sales_returns;
DROP TRIGGER fixture_updated_at ON public.payment_receipts;
CREATE TRIGGER trg_sales_orders_updated_at BEFORE UPDATE ON public.sales_orders FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_validate_sales_item BEFORE INSERT OR UPDATE ON public.sales_order_items FOR EACH ROW EXECUTE FUNCTION validate_sales_item_amounts();
CREATE TRIGGER trg_sales_returns_updated_at BEFORE UPDATE ON public.sales_returns FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_receipts_updated_at BEFORE UPDATE ON public.payment_receipts FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_cust_ledger_update_balance AFTER INSERT OR DELETE OR UPDATE ON public.customer_ledger FOR EACH ROW EXECUTE FUNCTION update_customer_cached_balance();
CREATE TRIGGER trg_customers_updated_at BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_guard_customer_opening_balance BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION guard_customer_opening_balance();
CREATE TRIGGER trg_expenses_updated_at BEFORE UPDATE ON public.expenses FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_payroll_run_updated_at BEFORE UPDATE ON public.hr_payroll_runs FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_employee_termination BEFORE UPDATE ON public.hr_employees FOR EACH ROW EXECUTE FUNCTION handle_employee_termination();
CREATE TRIGGER trg_hr_employees_updated_at BEFORE UPDATE ON public.hr_employees FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE TABLE analytics.fixture_permissions(actor uuid,permission text,PRIMARY KEY(actor,permission));
CREATE FUNCTION public.check_permission(actor uuid,permission text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,analytics AS $$
 SELECT EXISTS(SELECT 1 FROM analytics.fixture_permissions p WHERE p.actor=$1 AND p.permission=$2) $$;
REVOKE ALL ON analytics.fixture_permissions FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA public,auth,analytics TO authenticated;
GRANT SELECT,UPDATE ON public.customers TO authenticated;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY customers_delete ON public.customers FOR DELETE TO PUBLIC USING (( SELECT check_permission(( SELECT auth.uid() AS uid), 'customers.delete'::text) AS check_permission));
CREATE POLICY customers_read ON public.customers FOR SELECT TO PUBLIC USING ((( SELECT check_permission(( SELECT auth.uid() AS uid), 'customers.read_all'::text) AS check_permission) OR (( SELECT check_permission(( SELECT auth.uid() AS uid), 'customers.read'::text) AS check_permission) AND (assigned_rep_id = ( SELECT auth.uid() AS uid)))));
CREATE POLICY customers_update ON public.customers FOR UPDATE TO PUBLIC USING (( SELECT check_permission(( SELECT auth.uid() AS uid), 'customers.update'::text) AS check_permission));
CREATE POLICY customers_write ON public.customers FOR INSERT TO PUBLIC WITH CHECK (( SELECT check_permission(( SELECT auth.uid() AS uid), 'customers.create'::text) AS check_permission));
