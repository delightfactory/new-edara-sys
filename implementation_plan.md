# 🏗️ خطة بناء EDARA الجديد — النسخة المتكاملة

> مبنية على: تحليل النظام القديم + ملاحظات المستخدم + أفضل الممارسات الاحترافية
> المشروع الجديد: `c:\Users\HP\OneDrive\Desktop\new-edara-sys`

---

## نظرة عامة على النظام

EDARA هو نظام ERP/CRM متكامل لشركة توزيع بمتعدد الفروع، يدير:
- **المبيعات** (مندوبين ميدانيين + تيلي سيلز)
- **المشتريات** (الشراء + الاستلام + المرتجعات)
- **المخازن** (رئيسية + سيارات + فروع)
- **المالية** (خزائن + عهد + مصروفات + قيود محاسبية)
- **العملاء** (5000+ عميل، ائتمان، أسعار مخصصة)
- **الموارد البشرية** (حضور GPS + إجازات + رواتب + عمولات)
- **الأهداف والأداء** (OKR + KPI + عمولات)
- **التقارير** (3 مستويات: CEO / مدير / موظف)

> [!IMPORTANT]
> **معايير الأداء الصارمة**: 5,000 عميل + 50,000 طلب + 500,000 بند → لا إبطاء مقبول

---

## القرارات المعتمدة (تم التأكيد)

> [!NOTE]
> **قرارات نهائية مؤكدة من صاحب المشروع:**
> 1. ✅ **هيكل الشركة**: شركة واحدة بفروع متعددة — لا تعدد شركات
> 2. ✅ **منفذ البيع (Retail/POS)**: يُخطَّط له ويُدعم في البنية من البداية لكن واجهة POS تُنفَّذ في **المرحلة 7** بعد اكتمال النظام الأساسي
> 3. ✅ **المندوب والمخزن**: المندوب يمكنه البيع من سيارته (vehicle warehouse) أو من مخزن الشركة؛ التسليم من مخزن الشركة يتطلب موافقة مدير المخزن
> 4. ✅ **العملة**: الجنيه المصري (EGP) — كافة المبالغ بالجنيه المصري
> 5. ✅ **المنصة**: Web App فقط في المراحل الحالية — تطبيقات الجوال في مرحلة مستقبلية منفصلة
> 6. ✅ **إعادة تعيين كلمة المرور**: عبر الواجهة مباشرة من لوحة الإدارة (Admin Dashboard) — المسؤول يدخل كلمة المرور الجديدة مباشرة، لا بريد إلكتروني

---

## المكونات التقنية للمشروع الجديد

| الطبقة | التقنية |
|--------|---------|
| **Frontend** | Vite + React 18 + TypeScript |
| **Styling** | Vanilla CSS (Custom CSS Variables) — لا Tailwind |
| **State** | Zustand (بدون persist للصلاحيات) |
| **Server State** | TanStack Query (React Query v5) |
| **DB** | Supabase (PostgreSQL + RLS) |
| **Auth** | Supabase Auth + Edge Functions |
| **Routing** | React Router v6 |
| **Forms** | React Hook Form + Zod |
| **Notifications** | Sonner (toasts) + Web Push API |
| **Charts** | Recharts |
| **Font** | Cairo (Google Fonts) |

---

## تصميم الأمان — المبدأ الأساسي

```
كل بيانات يجب أن تُحمى على مستوى قاعدة البيانات أولاً
Frontend = عرض + إرشاد فقط، ليس حماية
```

### استراتيجية RLS الجديدة

```sql
-- دالة محورية — تُستدعى من كل RLS policy
CREATE OR REPLACE FUNCTION check_permission(p_user_id UUID, p_permission TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE v_has BOOLEAN;
BEGIN
  -- فحص override فردي أولاً (منح أو حجب)
  SELECT granted INTO v_has
  FROM user_permission_overrides
  WHERE user_id = p_user_id 
    AND permission = p_permission
    AND (expires_at IS NULL OR expires_at > now());
  
  IF FOUND THEN RETURN v_has; END IF;
  
  -- فحص صلاحيات الدور
  RETURN EXISTS (
    SELECT 1 FROM role_permissions rp
    JOIN user_roles ur ON ur.role_id = rp.role_id
    WHERE ur.user_id = p_user_id
      AND rp.permission = p_permission
      AND ur.is_active = true
  );
END; $$;

-- مثال RLS policy صحيح:
CREATE POLICY "sales_orders_select" ON sales_orders
  FOR SELECT USING (
    check_permission(auth.uid(), 'sales.orders.read')
  );
```

### الصلاحيات — لا تُخزن في localStorage أبداً
```typescript
// AuthProvider: تُجلب من DB عند كل تسجيل دخول جديد
// تُخزن في Zustand memory فقط (بدون persist)
// عند تحديث الصلاحيات: invalidate الـ session وإعادة الجلب
```

---

## 1. مكونات النظام — التعريف الكامل

---

### 🏢 المجموعة 1: البنية الأساسية

#### 1.1 نظام المصادقة والمستخدمين

**جداول DB:**
| الجدول | الأعمدة الرئيسية |
|--------|-----------------|
| `profiles` | `id` (= auth.uid), `full_name`, `email`, `phone`, `avatar_url`, `is_active`, `last_login_at` |
| `roles` | `id`, `name`, `name_ar`, `description`, `is_system` (لا يُحذف) |
| `role_permissions` | `role_id` FK, `permission` TEXT (مثل `sales.orders.read`) |
| `user_roles` | `user_id` FK, `role_id` FK, `branch_id` FK NULL, `is_active`, `assigned_by`, `assigned_at` |
| `user_permission_overrides` | `user_id`, `permission`, `granted` BOOL, `granted_by`, `expires_at` NULL |

**Edge Functions:**
- `create-user` → ينشئ مستخدم في Auth + profile + دور
- `update-user` → يعدل بيانات المستخدم (يتحقق من صلاحية المنفذ)
- `deactivate-user` → يعطل المستخدم (لا يحذفه)
- `admin-reset-password` → يعيد تعيين كلمة المرور مباشرة من الواجهة الإدارية

**منطق إعادة تعيين كلمة المرور:**
```
المسؤول يدخل كلمة المرور الجديدة من صفحة إدارة المستخدمين
  → Edge Function تتحقق من صلاحية المسؤول
  → تستدعي supabase.auth.admin.updateUserById({ password: newPassword })
  → تُسجّل العملية في audit_logs
  → تُرسل إشعاراً للمستخدم بتغيير كلمة المرور
```

> [!IMPORTANT]
> لا يوجد self-service password reset عبر البريد الإلكتروني.
> فقط المسؤولون من لديهم صلاحية `auth.users.reset_password` يمكنهم تغيير كلمات المرور.

**منطق مهم:**
- المستخدم يمكن أن يكون له دور شامل (كل الشركة) أو دور مقيد بفرع
- الصلاحية = `module.resource.action` (مثل `finance.vaults.create`)
- wildcard `*` = super admin
- override فردي يأخذ أولوية على الدور

---

#### 1.2 نظام الإعدادات الديناميكي

**جداول DB:**
| الجدول | الأعمدة |
|--------|---------|
| `company_settings` | `key` TEXT UNIQUE, `value` TEXT, `type` (text/number/boolean/json), `description`, `category`, `is_public` |
| `feature_flags` | `key`, `is_enabled` BOOL, `description`, `updated_by` |

**الإعدادات المخطط لها (30+ إعداد مستخلصة من النظام كاملاً):**
```
-- بيانات الشركة
company.name                       = 'شركة ...'
company.name_en                    = 'Company ...'
company.logo_url                   = ''
company.phone                      = ''
company.address                    = ''
company.tax_number                 = ''
company.fiscal_year_start          = '01-01'  -- بداية السنة المالية

-- مالية
finance.default_currency           = 'EGP'
finance.currency_symbol            = 'ج.م'
finance.decimal_places             = 2
finance.accountant_approval_limit  = 2000    -- محاسب يعتمد حتى هذا المبلغ
finance.manager_approval_limit     = 10000   -- مدير يعتمد حتى هذا المبلغ
finance.ceo_approval_limit         = 50000   -- فوقها = مجلس الإدارة

-- مبيعات
sales.max_discount_percent         = 15      -- أقصى خصم يمنحه مندوب
sales.allow_rep_discount           = true
sales.credit_check_enabled         = true
sales.credit_check_strict          = true    -- true = يمنع، false = يحذّر فقط
sales.require_order_approval       = false   -- هل الطلبات تحتاج موافقة
sales.order_approval_min_amount    = 0       -- الحد الأدنى الذي يتطلب موافقة
sales.allow_partial_delivery       = true    -- تسليم جزئي

sales.allow_negative_stock         = false   -- منع البيع بالسالب 

sales.return_require_approval      = true    -- موافقة على المرتجعات
sales.max_return_days              = 30      -- أقصى أيام للمرتجع
sales.require_delivery_proof       = false   -- إلزامية صورة التسليم

-- مشتريات
purchase.require_order_approval    = true
purchase.approval_min_amount       = 5000

-- مخزون
inventory.low_stock_threshold      = 10     -- نسبة % من min_stock_level للتحذير
inventory.costing_method           = 'wac'  -- Weighted Average Cost (IAS 2)
inventory.batch_tracking_enabled   = true   -- تتبع الدفعات
inventory.expiry_tracking_enabled  = true   -- تتبع تواريخ الصلاحية
inventory.expiry_alert_days        = 30     -- تحذير قبل انتهاء الصلاحية بـ 30 يوم

-- موارد بشرية
hr.working_days                    = '[1,2,3,4,6]'  -- أيام العمل (0=أحد...6=سبت)
hr.work_start_time                 = '08:00'
hr.work_end_time                   = '17:00'
hr.late_grace_minutes              = 15     -- دقائق السماح
hr.overtime_rate                   = 1.5   -- معامل الإضافي
hr.payroll_day                     = 28    -- يوم صرف الراتب (من الشهر)
hr.annual_leave_days               = 21    -- أيام الإجازة السنوية
hr.sick_leave_days                 = 15
hr.attendance_gps_required         = true   -- إلزامية GPS للحضور
hr.attendance_gps_radius_meters    = 200    -- نطاق الحضور المقبول

-- إشعارات
notifications.low_stock_enabled    = true
notifications.credit_limit_enabled = true
notifications.order_approval_push  = true
notifications.payroll_reminder_days = 3   -- خير قبل موعد الصرف
```

---

#### 1.3 الجغرافيا والفروع

**جداول DB:**
| الجدول | الأعمدة |
|--------|---------|
| `governorates` | `id`, `name`, `name_en`, `code` (01-27), `sort_order` |
| `cities` | `id`, `governorate_id`, `name`, `name_en`, `sort_order` |
| `areas` | `id`, `city_id`, `name` |
| `branches` | `id`, `name`, `type` (distribution/retail/warehouse), `city_id`, `address`, `phone`, `manager_id`, `is_active` |

**منطق مهم:**
- `branches.type = 'distribution'` → فرع توزيع (يشغّل طلبات البيع الكاملة)
- `branches.type = 'retail'` → منفذ بيع (POS مبسط مستقبلاً)
- البيانات المرجعية للمحافظات والمدن = seed data ثابتة (27 محافظة + المدن)

---

### 📦 المجموعة 2: بيانات الأساس (Master Data)

#### 2.1 المنتجات والتصنيف

**جداول DB:**
| الجدول | الأعمدة الرئيسية |
|--------|-----------------|
| `product_categories` | `id`, `name`, `parent_id` (هرمي), `icon`, `is_active` |
| `product_types` | `id`, `name`, `description` |
| `brands` | `id`, `name`, `logo_url`, `is_active` |
| `units` | `id`, `name`, `symbol`, `is_base` BOOL |
| `products` | `id`, `sku` UNIQUE, `name`, `barcode`, `category_id`, `type_id`, `brand_id`, `base_unit_id` FK (الوحدة الأساسية الإجبارية), `selling_price` (بالوحدة الأساسية), `cost_price`, `tax_rate`, `description`, `image_url`, `is_active`, `min_stock_level` (بالوحدة الأساسية) |
| `product_units` | `product_id`, `unit_id`, `conversion_factor` NUMERIC (عدد الوحدات الأساسية في هذه الوحدة), `selling_price` NUMERIC NULL (سعر مخصص لهذه الوحدة — إذا null يُحسب من السعر الأساسي × conversion_factor), `is_purchase_unit` BOOL, `is_sales_unit` BOOL |
| `product_bundles` | `id`, `name`, `sku`, `price`, `is_active` |
| `product_bundle_items` | `bundle_id`, `product_id`, `unit_id`, `quantity` |

**⭐ نظام الوحدات — المنطق الكامل:**

كل منتج له **وحدة أساسية** واحدة (مثل: جركن) يُخزَّن بها في المخزون.
تُضاف وحدات إضافية بعامل تحويل إلى الوحدة الأساسية:

```
مثال — زيت محرك:
  base_unit = جركن
  product_units:
    - كرتونة  → conversion_factor = 6  (1 كرتونة = 6 جراكن)
    - دزينة   → conversion_factor = 12 (1 دزينة = 12 جركن)
    - باليت   → conversion_factor = 60 (1 باليت = 60 جركن)

عند البيع 2 كرتونة:
  base_quantity_deducted = 2 × 6 = 12 جركن (يُخصم من المخزون)

عند تحديد السعر:
  selling_price (جركن) = 100 ج.م
  selling_price (كرتونة) = product_units.selling_price إذا محدد
                         أو = 100 × 6 = 600 ج.م (محسوب)
```

**قواعد صارمة لنظام الوحدات:**
- المخزون يُخزَّن ويُحسب دائماً بالوحدة الأساسية
- `conversion_factor` لا يمكن أن يكون صفراً أو سالباً
- `sales_order_items` + `purchase_order_items` يحتفظان بـ `unit_id` (الوحدة المُدخلة) + `conversion_factor` + `base_quantity` (بالوحدة الأساسية)
- دالة `get_product_price()` تحسب السعر بناءً على الوحدة المختارة

```sql
-- دالة تحويل الوحدة (تستخدمها كل العمليات)
CREATE OR REPLACE FUNCTION get_base_quantity(
  p_product_id UUID, p_unit_id UUID, p_quantity NUMERIC
) RETURNS NUMERIC AS $$
DECLARE v_factor NUMERIC;
BEGIN
  -- إذا كانت نفس الوحدة الأساسية
  IF (SELECT base_unit_id FROM products WHERE id = p_product_id) = p_unit_id
  THEN RETURN p_quantity;
  END IF;

  SELECT conversion_factor INTO v_factor
  FROM product_units
  WHERE product_id = p_product_id AND unit_id = p_unit_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الوحدة غير مرتبطة بهذا المنتج';
  END IF;

  RETURN p_quantity * v_factor;
END; $$ LANGUAGE plpgsql STABLE;
```

**قواعد التسعير:**
- سعر المنتج الافتراضي = `products.selling_price` (بالوحدة الأساسية)
- سعر وحدة مخصص = `product_units.selling_price` إذا محدد؛ وإلا = `selling_price × conversion_factor`
- سعر من قائمة أسعار = `price_list_items.price` (أعلى أولوية — مرتبط بالوحدة أيضاً)
- تحويل الوحدات في الخصم: يُطبَّق على سعر الوحدة المحددة

---

#### 2.2 قوائم الأسعار

**جداول DB:**
| الجدول | الأعمدة |
|--------|---------|
| `price_lists` | `id`, `name`, `description`, `is_default` BOOL, `is_active`, `currency`, `valid_from`, `valid_to` |
| `price_list_items` | `price_list_id`, `product_id`, `unit_id`, `price`, `min_qty` (للشرائح), `max_qty` |
| `price_list_assignments` | `price_list_id`, `entity_type` (customer/city/governorate), `entity_id` |

**منطق التسعير (بالأولوية):**
1. قائمة أسعار العميل المخصصة
2. قائمة أسعار مدينة / محافظة العميل
3. قائمة الأسعار الافتراضية
4. `products.selling_price`

**دالة DB:**
```sql
get_product_price(p_product_id, p_customer_id, p_unit_id, p_qty)
-- تتبع الأولوية وترجع السعر الصحيح
```

---

#### 2.3 العملاء

**جداول DB:**
| الجدول | الأعمدة الرئيسية |
|--------|-----------------|
| `customers` | `id`, `code` UNIQUE, `name`, `type` (retail/wholesale/distributor), `governorate_id`, `city_id`, `area_id`, `address`, `phone`, `mobile`, `email`, `tax_number`, `payment_terms` (cash/credit/mixed), `credit_limit`, `credit_days`, `price_list_id`, `assigned_rep_id`, `latitude` NUMERIC NULL, `longitude` NUMERIC NULL, `location_accuracy` NUMERIC NULL, `location_updated_at` TIMESTAMPTZ NULL, `location_updated_by` UUID NULL, `is_active`, `notes`, `created_by` |
| `customer_branches` | `id`, `customer_id`, `name`, `address`, `phone`, `contact_name`, `latitude` NUMERIC NULL, `longitude` NUMERIC NULL, `is_primary` |
| `customer_contacts` | `id`, `customer_id`, `name`, `role`, `phone`, `email`, `is_primary` |
| `customer_credit_history` | `customer_id`, `date`, `limit_before`, `limit_after`, `changed_by`, `reason` |

**⭐ نظام إحداثيات العميل (GPS):**
```
المندوب يزور العميل → يفتح صفحة العميل → يضغط "تحديث الموقع"
  → التطبيق يطلب إذن GPS من المتصفح
  → يُرسل latitude + longitude للسيرفر
  → تُحفظ في customers.latitude + longitude + location_updated_at

الاستخدامات:
  ✅ التحقق من أن المندوب أمام العميل فعلاً (Geofencing في الزيارات)
  ✅ خريطة توزيع العملاء للإدارة
  ✅ تحسين تخطيط مسارات التوزيع
  ✅ التحقق من تسليم الطلبات في الموقع الصحيح
```

```typescript
// تحديث الموقع من الواجهة
const updateCustomerLocation = async (customerId: string) => {
  const position = await new Promise<GeolocationPosition>((res, rej) =>
    navigator.geolocation.getCurrentPosition(res, rej, {
      enableHighAccuracy: true, timeout: 10000
    })
  )
  await supabase.from('customers').update({
    latitude: position.coords.latitude,
    longitude: position.coords.longitude,
    location_accuracy: position.coords.accuracy,
    location_updated_at: new Date().toISOString(),
    location_updated_by: currentUser.id
  }).eq('id', customerId)
}
```

**منطق الائتمان:**
- `credit_limit = 0` → بدون حد (نقدي فقط)
- `credit_days` → أيام السماح للسداد
- `current_balance` يُحسب ديناميكياً (لا يُخزن كعدد ثابت)
  ```sql
  -- View للرصيد الفعلي
  CREATE VIEW customer_balance AS
  SELECT customer_id,
    SUM(CASE WHEN type='debit' THEN amount ELSE -amount END) AS current_balance
  FROM customer_ledger GROUP BY customer_id;
  ```

---

#### 2.4 الموردين

**جداول DB:**
| الجدول | الأعمدة |
|--------|---------|
| `suppliers` | `id`, `code`, `name`, `type`, `governorate_id`, `city_id`, `phone`, `email`, `tax_number`, `payment_terms`, `credit_limit`, `credit_days`, `bank_account`, `is_active` |
| `supplier_contacts` | `supplier_id`, `name`, `role`, `phone`, `email` |
| `supplier_payment_reminders` | `supplier_id`, `due_date`, `amount`, `invoice_ref`, `status` (pending/paid/overdue), `notify_before_days` |

---

### 🏭 المجموعة 3: المخازن والمخزون

#### 3.1 المخازن

**جداول DB:**
| الجدول | الأعمدة |
|--------|---------|
| `warehouses` | `id`, `name`, `type` (fixed/vehicle/retail), `branch_id`, `address`, `manager_id`, `is_active` |
| `warehouse_managers` | `warehouse_id`, `profile_id`, `is_primary`, `can_approve_receipts` |

**أنواع المخازن:**
- `fixed` → مخزن ثابت (مبنى)
- `vehicle` → سيارة توزيع (مخزون متنقل)
- `retail` → منفذ بيع

**قاعدة توجيه الأذونات:**
> إذا كان المندوب مدير المخزن المستهدف → يوافق مباشرة
> إذا لم يكن → ينتظر موافقة مدير المخزن

---

#### 3.2 المخزون والتقييم المحاسبي (WAC)

**جداول DB:**
| الجدول | الأعمدة |
|--------|---------|
| `stock` | `warehouse_id`, `product_id`, `quantity` (بالوحدة الأساسية), `reserved_quantity`, `available_quantity` (generated), `wac` (متوسط تكلفة الوحدة), `total_cost_value` (quantity × wac) |
| `stock_batches` | `id`, `stock_id`, `batch_number`, `expiry_date`, `quantity`, `cost_price` (WAC عند الاستلام) |
| `stock_movements` | `id`, `warehouse_id`, `product_id`, `unit_id`, `quantity`, `type` (in/out/transfer_in/transfer_out/adjustment_add/adjustment_remove/return_in/return_out), `unit_cost`, `wac_before`, `wac_after`, `reference_type`, `reference_id`, `before_qty`, `after_qty`, `notes`, `created_by`, `created_at` |
| `stock_transfers` | `id`, `number`, `from_warehouse_id`, `to_warehouse_id`, `status` (pending/approved/in_transit/received/cancelled), `requested_by`, `approved_by`, `notes` |
| `stock_transfer_items` | `transfer_id`, `product_id`, `unit_id`, `quantity`, `received_quantity`, `unit_cost` |
| `stock_adjustments` | `id`, `number`, `warehouse_id`, `type` (add/remove/count), `status`, `reason`, `approved_by` |
| `stock_adjustment_items` | `adjustment_id`, `product_id`, `system_qty`, `actual_qty`, `difference`, `unit_cost`, `notes` |

---

**⭐ نظام التقييم المحاسبي للمخزون — Weighted Average Cost (WAC)**

> [!IMPORTANT]
> الطريقة المختارة: **Weighted Average Cost (WAC)** — معتمد من IFRS (IAS 2)
> الأنسب لشركات التوزيع ذات التكاليف المتغيرة وحجم الحركة الكبير

**مبدأ WAC:**
```
عند وصول بضاعة جديدة:
  WAC جديد = (كمية حالية × WAC حالي + كمية جديدة × تكلفة جديدة)
           ÷ (كمية حالية + كمية جديدة)

مثال:
  الرصيد الحالي: 100 جركن × 50 ج.م WAC = 5,000 ج.م قيمة إجمالية
  استلمنا: 50 جركن × 60 ج.م = 3,000 ج.م
  WAC جديد = (5,000 + 3,000) ÷ (100 + 50) = 53.33 ج.م لكل جركن

عند بيع 30 جركن:
  تكلفة البضاعة المباعة (COGS) = 30 × 53.33 = 1,600 ج.م
  الرصيد المتبقي: 120 جركن × 53.33 WAC
```

**تطبيق WAC في كل الحالات:**

| الحالة | تأثير على WAC |
|------|--------------| 
| استلام مشتريات | يُحدَّث WAC تلقائياً |
| بيع (خروج) | WAC لا يتغير، فقط يُخصم الرصيد |
| مرتجع مبيعات | يعود بالـ WAC وقت البيع (لا سعر اليوم) |
| مرتجع مشتريات | يُخصم بالتكلفة الأصلية للفاتورة، يُحدَّث WAC |
| تحويل بين مخازن | WAC ينتقل مع البضاعة |
| تسوية مخزون | يُعيد حساب WAC بالقيمة الفعلية |

**دالة SQL لتحديث WAC (عند الاستلام):**
```sql
CREATE OR REPLACE FUNCTION update_stock_wac(
  p_warehouse_id UUID, p_product_id UUID,
  p_qty_in NUMERIC, p_unit_cost NUMERIC,
  p_movement_type TEXT, p_reference_type TEXT,
  p_reference_id UUID, p_user_id UUID
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_stock stock%ROWTYPE;
  v_new_wac NUMERIC;
  v_new_qty NUMERIC;
  v_new_total NUMERIC;
BEGIN
  SELECT * INTO v_stock
  FROM stock
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    -- أول استلام: WAC = تكلفة الدفعة الأولى
    INSERT INTO stock (warehouse_id, product_id, quantity, reserved_quantity, wac, total_cost_value)
    VALUES (p_warehouse_id, p_product_id, p_qty_in, 0, p_unit_cost, p_qty_in * p_unit_cost);
    v_new_qty := p_qty_in; v_new_wac := p_unit_cost;
  ELSE
    v_new_qty   := v_stock.quantity + p_qty_in;
    v_new_total := v_stock.total_cost_value + (p_qty_in * p_unit_cost);
    v_new_wac   := CASE WHEN v_new_qty > 0 THEN v_new_total / v_new_qty ELSE 0 END;
    UPDATE stock SET quantity = v_new_qty, wac = v_new_wac, total_cost_value = v_new_total
    WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;
  END IF;

  INSERT INTO stock_movements (warehouse_id, product_id, unit_id, quantity, type,
    unit_cost, wac_before, wac_after, before_qty, after_qty,
    reference_type, reference_id, created_by)
  VALUES (p_warehouse_id, p_product_id,
    (SELECT base_unit_id FROM products WHERE id = p_product_id),
    p_qty_in, p_movement_type,
    p_unit_cost, COALESCE(v_stock.wac, p_unit_cost), v_new_wac,
    COALESCE(v_stock.quantity, 0), v_new_qty,
    p_reference_type, p_reference_id, p_user_id);
END; $$;

-- دالة خصم المخزون بالـ WAC الحالي (عند البيع والتسليم)
CREATE OR REPLACE FUNCTION deduct_stock_at_wac(
  p_warehouse_id UUID, p_product_id UUID, p_qty_out NUMERIC,
  p_movement_type TEXT, p_reference_type TEXT,
  p_reference_id UUID, p_user_id UUID
) RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_stock stock%ROWTYPE;
  v_cogs NUMERIC;
BEGIN
  SELECT * INTO v_stock
  FROM stock WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
  FOR UPDATE;

  IF v_stock.quantity < p_qty_out THEN
    IF NOT (SELECT value::boolean FROM company_settings WHERE key = 'sales.allow_negative_stock') THEN
      RAISE EXCEPTION 'مخزون غير كافٍ (متاح: %, مطلوب: %)', v_stock.quantity, p_qty_out;
    END IF;
  END IF;

  v_cogs := p_qty_out * v_stock.wac;

  UPDATE stock SET
    quantity = quantity - p_qty_out,
    total_cost_value = total_cost_value - v_cogs
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id;

  INSERT INTO stock_movements (warehouse_id, product_id, unit_id, quantity, type,
    unit_cost, wac_before, wac_after, before_qty, after_qty,
    reference_type, reference_id, created_by)
  VALUES (p_warehouse_id, p_product_id,
    (SELECT base_unit_id FROM products WHERE id = p_product_id),
    p_qty_out, p_movement_type,
    v_stock.wac, v_stock.wac, v_stock.wac,
    v_stock.quantity, v_stock.quantity - p_qty_out,
    p_reference_type, p_reference_id, p_user_id);

  RETURN v_cogs;  -- يُستخدم في القيد المحاسبي التلقائي
END; $$;
```

**View تقييم المخزون الكامل:**
```sql
CREATE OR REPLACE VIEW v_stock_valuation AS
SELECT
  s.warehouse_id, w.name AS warehouse_name,
  s.product_id, p.name AS product_name, p.sku,
  s.quantity, s.reserved_quantity,
  (s.quantity - s.reserved_quantity) AS available_quantity,
  s.wac AS unit_cost,
  s.total_cost_value AS total_inventory_value,
  CASE
    WHEN s.quantity <= 0 THEN 'out_of_stock'
    WHEN s.quantity <= p.min_stock_level THEN 'low'
    WHEN s.quantity > (p.min_stock_level * 5) THEN 'excess'
    ELSE 'ok'
  END AS stock_status,
  (SELECT MAX(expiry_date) FROM stock_batches sb
   WHERE sb.stock_id = s.id AND sb.expiry_date < CURRENT_DATE + 30) AS expiring_soon
FROM stock s
JOIN warehouses w ON w.id = s.warehouse_id
JOIN products p ON p.id = s.product_id
WHERE p.is_active = true;
```

**قواعد مهمة:**
- المخزون يُسجل ويُحسب دائماً بالوحدة الأساسية
- `reserved_quantity` = مجموع كميات الطلبات المؤكدة غير المسلّمة
- تحذير المخزون المنخفض عند `quantity ≤ products.min_stock_level`
- WAC يُحدَّث تلقائياً مع كل عملية استلام جديدة
- مرتجع المبيعات يعود بالـ WAC وقت البيع (لا سعر اليوم)
- COGS يُحسب ويُنتقل للقيد المحاسبي تلقائياً

---

### 💰 المجموعة 4: العمليات التجارية

#### 4.1 وحدة المبيعات — التدفق الكامل

**⭐ أكثر وحدة تعقيداً — تحليل شامل:**

```
إنشاء طلب (draft) 
  → [اختياري] موافقة مدير (إذا مطلوب من الإعدادات)
  → تأكيد الطلب (confirmed) + حجز المخزون
  → تسليم (delivered) + خصم المخزون الفعلي
  → تحصيل (حسب طريقة الدفع)
  → [اختياري] مرتجع جزئي أو كلي
```

**جداول DB:**
```sql
sales_orders: id, number, customer_id, sales_rep_id (NOT NULL — مطلوب دائماً),
  warehouse_id, branch_id, status (draft/approved/confirmed/delivered/cancelled),
  order_date, delivery_date, delivery_method, shipping_company_id,
  delivery_address_id (من customer_branches),
  payment_terms (cash/credit), payment_method (cash/bank_transfer/instapay/check),
  vault_id NULL, custody_id NULL (إذا نقدي),
  subtotal, discount_amount, tax_amount, total_amount,
  credit_check_passed BOOL, credit_check_at,
  confirmed_by, confirmed_at,
  delivered_by, delivered_at,
  cancelled_by, cancelled_reason,
  notes, created_by, created_at

sales_order_items: id, order_id, product_id, unit_id,
  quantity, unit_price, discount_amount, discount_percent,
  tax_amount, total, conversion_factor, base_quantity,
  returned_quantity DEFAULT 0 (يُتحدث مع كل مرتجع)

sales_returns: id, number, order_id, customer_id, warehouse_id,
  status (draft/confirmed/cancelled),
  return_date, total_amount, reason, notes,
  confirmed_by, confirmed_at, created_by

sales_return_items: id, return_id, order_item_id (FK مهم!),
  product_id, unit_id, quantity, unit_price, total,
  conversion_factor, base_quantity
  -- CHECK: quantity <= (order_item.quantity - order_item.returned_quantity)
```

**التحصيل — منطق معقد:**

| حالة | الإجراء |
|------|---------|
| طلب آجل | إضافة للـ customer_ledger كـ debit، لا تحصيل فوري |
| نقدي + عهدة | إضافة للـ custody_transactions كـ collection |
| نقدي + خزنة | إضافة للـ vault_transactions كـ collection |
| نقدي + تحويل/InstaPay/بنكي | إنشاء payment_receipt بحالة pending + يجب رفع إثبات |

```sql
-- دالة التأكيد الذرية:
CREATE OR REPLACE FUNCTION confirm_sales_order(p_order_id UUID, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_order sales_orders%ROWTYPE;
  v_can_deliver BOOL;
BEGIN
  -- 1. Lock الطلب
  SELECT * INTO v_order FROM sales_orders
  WHERE id = p_order_id FOR UPDATE;
  
  -- 2. تحقق من الحالة
  IF v_order.status != 'approved' AND v_order.status != 'draft' THEN
    RAISE EXCEPTION 'الطلب ليس في حالة تسمح بالتأكيد';
  END IF;
  
  -- 3. فحص ائتماني إذا كان آجل
  IF v_order.payment_terms = 'credit' THEN
    IF NOT check_credit_limit(v_order.customer_id, v_order.total_amount) THEN
      RAISE EXCEPTION 'تجاوز الحد الائتماني للعميل';
    END IF;
  END IF;
  
  -- 4. تحقق من توفر المخزون + حجز
  PERFORM reserve_stock_for_order(p_order_id);
  
  -- 5. تحديث الحالة
  UPDATE sales_orders SET status = 'confirmed', confirmed_by = p_user_id,
    confirmed_at = now() WHERE id = p_order_id;
    
  -- 6. إشعار مدير المخزن إذا المندوب ليس هو المسؤول
  PERFORM notify_warehouse_manager(v_order.warehouse_id, 'order_confirmed', p_order_id);
END; $$;

-- دالة التسليم:
CREATE OR REPLACE FUNCTION deliver_sales_order(p_order_id UUID, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- 1. تحديث returned_quantity لكل بند
  -- 2. خصم من المخزون (cancel reservation + actual deduction)
  -- 3. إنشاء حركات مخزون
  -- 4. تحديث رصيد العميل (إذا آجل) أو الخزنة/العهدة (إذا نقدي فوري)
  -- 5. إنشاء قيد محاسبي تلقائي
  -- 6. إنشاء payment_receipt إذا كان نقدي
END; $$;
```

---

#### 4.2 وحدة المشتريات

```
إنشاء أمر شراء (draft)
  → موافقة مدير (إذا مطلوب)
  → إرسال للمورد (في المستقبل)
  → استلام جزئي أو كلي بالمخزن
  → موافقة أمين المخزن على الاستلام
  → إضافة للمخزون + تحديث رصيد المورد
  → دفع للمورد (نقدي/آجل)
```

**جداول DB:** كما في الخطة الأصلية مع إضافة:
- `purchase_receipt_items.batch_number` + `expiry_date` (لتتبع الدفعات)

---

#### 4.3 النظام المالي

**مفهوم Ledger (الأساس):**
```sql
-- بدلاً من تخزين current_balance كعدد ثابت (يتعرض للتلف)
-- نستخدم Ledger (سجل حركات) ونحسب الرصيد في الوقت الفعلي:

customer_ledger: id, customer_id, type (debit/credit), amount,
  source_type (sales_order/payment/return/adjustment),
  source_id, description, balance_after (للأرشيف),
  created_by, created_at

supplier_ledger: نفس البنية
```

**الخزائن والعهد:**
```sql
vaults: id, name, type (cash/bank/mobile_wallet), 
  account_number, bank_name, responsible_id, branch_id, is_active

vault_transactions: id, vault_id, type, amount, balance_after,
  reference_type, reference_id, description, created_by

custody_accounts: id, employee_id UNIQUE, max_balance,
  current_balance (computed from custody_transactions)

custody_transactions: id, custody_id, type (load/collection/expense/settlement/return),
  amount, balance_after, reference_type, reference_id, description, created_by
```

**نظام المصروفات متعدد المستويات:**
```
إنشاء مصروف → طلب اعتماد → 
  < حد أمين الصندوق → يوافق أمين الصندوق
  < حد المدير → يوافق المدير
  > حد المدير → يصعّد للـ CEO
→ خصم من خزنة/عهدة → قيد محاسبي
```

---

### 👥 المجموعة 5: الموارد البشرية والأداء

#### 5.1 الموظفون والمندوبون

**جداول DB:**
```sql
departments: id, name, manager_id, parent_id (هرمي), is_active

job_titles: id, name, department_id, grade

employees: id, profile_id UNIQUE, employee_code UNIQUE,
  department_id, job_title_id, branch_id,
  hire_date, employment_type (full_time/part_time/contract),
  base_salary, allowances JSONB,
  bank_account, national_id, emergency_contact,
  is_active

-- المندوبون = موظفون بدور "مندوب مبيعات"
sales_reps: id, employee_id UNIQUE,
  warehouse_id NULL (المخزن/السيارة الخاصة به),
  route_id NULL (المسار المخصص),
  commission_scheme_id NULL
```

---

#### 5.2 الحضور والانصراف (GPS)

**المنطق:**
- الموظف يسجّل حضور من الموبايل (جهازه الشخصي)
- النظام يتحقق من الموقع عبر دائرة Geofencing حول موقع الفرع/العميل
- يحسب التأخير من وقت الوردية المقررة
- يدعم ورديات متعددة مرنة

```sql
work_shifts: id, name, start_time, end_time, 
  grace_minutes (فترة السماح), is_active

employee_shift_assignments: employee_id, shift_id, 
  start_date, end_date NULL (إذا null = حتى إشعار آخر)

check_in_locations: id, name, type (branch/customer/any),
  latitude, longitude, radius_meters (دائرة السماح)

employee_attendance: id, employee_id, date,
  check_in, check_out,
  check_in_lat, check_in_lng, check_in_location_id,
  check_out_lat, check_out_lng,
  status (present/absent/late/half_day/day_off/holiday),
  work_hours, overtime_hours, late_minutes,
  shift_id, notes, created_by
```

---

#### 5.3 نظام الأهداف (Targets / KPI)

**شرح مبسط للنظام:**

الهدف هو رقم مطلوب تحقيقه في فترة زمنية محددة.
يمكن تحديد هدف للشركة كلها، أو لفرع، أو لقسم، أو لشخص بعينه.

```
مثال 1 — هدف مبيعات شهري:
  الموظف: أحمد (مندوب)
  الفترة: مارس 2026
  الهدف: مبيعات 50,000 ج.م
  المحقق: 38,000 ج.م → 76%

مثال 2 — هدف زيارات:
  الهدف: 80 زيارة في الشهر
  المحقق: يُحسب تلقائياً من جدول activities

مثال 3 — هدف تحصيل:
  الهدف: تحصيل 30,000 ج.م من الديون
  المحقق: يُحسب من مدفوعات العملاء الآجلين

هرمية الأهداف:
  هدف الشركة (500,000 ج.م مبيعات شهري)
    ← فرع القاهرة (200,000 ج.م)
      ← أحمد المندوب (50,000 ج.م)
      ← محمد المندوب (50,000 ج.م)
    ← فرع الإسكندرية (150,000 ج.م)
      ...
```

**جداول DB:**
```sql
target_types: id, name, code (sales_value/collection/visits/calls/new_customers),
  unit (currency/count/percent),
  auto_source (sales_orders/customer_payments/activities/customers),
  auto_calc_enabled BOOL  -- هل يُحسب تلقائياً؟

targets: id, type_id, name, scope (company/branch/department/individual),
  scope_id,  -- branch_id أو department_id أو employee_id حسب الـ scope
  period (monthly/quarterly/yearly),
  period_start, period_end,
  target_value,   -- الهدف الأساسي
  min_value NULL, -- الحد الأدنى (80% مثلاً)
  stretch_value NULL, -- الهدف التمدد (120%)
  product_id NULL,    -- هدف لمنتج بعينه
  category_id NULL,   -- هدف لتصنيف بعينه
  governorate_id NULL, -- هدف لمحافظة بعينها
  city_id NULL,
  parent_target_id NULL, -- الهدف الأب (هيراركي)
  assigned_by UUID,
  is_active

target_progress: id, target_id, date,
  achieved_value,           -- القيمة المحققة حتى هذا التاريخ
  achievement_percent,      -- النسبة المئوية
  last_calculated_at,       -- آخر تحديث تلقائي
  calculation_details JSONB -- تفاصيل المصدر
```

**حساب التقدم تلقائياً:**
```sql
-- يُحسب بـ Supabase Cron Job (مرة كل ساعة) أو عند كل عملية
-- مثال: هدف مبيعات فردي
UPDATE target_progress SET
  achieved_value = (
    SELECT COALESCE(SUM(so.total_amount), 0)
    FROM sales_orders so
    JOIN sales_reps sr ON sr.id = so.sales_rep_id
    JOIN employees e ON e.id = sr.employee_id
    WHERE e.id = <target.scope_id>
      AND so.status IN ('delivered', 'completed')
      AND so.created_at BETWEEN <period_start> AND <period_end>
      AND (<target.product_id> IS NULL OR EXISTS (
        SELECT 1 FROM sales_order_items soi
        WHERE soi.order_id = so.id
          AND soi.product_id = <target.product_id>
      ))
  ),
  achievement_percent = (achieved_value / target_value) * 100,
  last_calculated_at = now()
WHERE target_id = <target.id>;
```

---

#### 5.4 نظام العمولات (Commissions)

**شرح مبسط للنظام:**

العمولة هي مبلغ إضافي يُدفع للمندوب بناءً على أدائه.
يُنشأ «مخطط عمولة» (Commission Scheme) يحدد قواعد الحساب،
ثم يُربط المندوب بالمخطط.

```
مخطط عمولة — مثال 1 (بالنسبة المئوية):
  الأساس: مبيعات
  الشرائح:
    [ 0 - 20,000 ج.م ]  → 1%
    [ 20,001 - 40,000 ]  → 2%
    [ 40,001 + ]         → 3%

  المندوب حقق 35,000 ج.م:
    20,000 × 1% = 200 ج.م
    15,000 × 2% = 300 ج.م
    إجمالي العمولة = 500 ج.م

مخطط عمولة — مثال 2 (ثابت + منتج):
  إذا باع مندوب منتج "زيت X" أكثر من 100 جركن:
    مكافأة ثابتة 200 ج.م

مخطط عمولة — مثال 3 (على التحصيل):
  تحصيل ديون آجلة:
    [ 0-10,000 ] → 0.5%
    [ 10,001+ ]  → 1%
```

**جداول DB:**
```sql
commission_schemes: id, name,
  basis (sales_value/collection/profit/quantity),
  accumulation (cumulative/tiered),  -- هل الشرائح تراكمية أم مطلقة؟
  is_active, valid_from, valid_to

commission_tiers: id, scheme_id,
  min_threshold NUMERIC,   -- الحد الأدنى للشريحة
  max_threshold NUMERIC NULL, -- الحد الأعلى (null = غير محدود)
  type (percentage/fixed_amount),
  value NUMERIC,           -- النسبة أو المبلغ الثابت
  product_id UUID NULL,    -- عمولة خاصة بمنتج
  category_id UUID NULL,   -- عمولة خاصة بتصنيف
  city_id UUID NULL        -- عمولة خاصة بمدينة

commission_assignments: id, employee_id, scheme_id,
  start_date, end_date NULL,
  is_active

commission_calculations: id, employee_id, scheme_id,
  period_start, period_end,
  basis_amount,      -- إجمالي المبيعات/التحصيل في الفترة
  commission_amount, -- العمولة المحسوبة
  status (draft/calculated/approved/paid),
  details JSONB,     -- تفاصيل كل شريحة + مصدر الحساب
  calculated_at, approved_by, approved_at
```

**دالة حساب العمولة:**
```sql
CREATE OR REPLACE FUNCTION calculate_commission(
  p_employee_id UUID,
  p_period_start DATE,
  p_period_end DATE
) RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE
  v_scheme commission_schemes%ROWTYPE;
  v_basis NUMERIC := 0;
  v_commission NUMERIC := 0;
  v_tier commission_tiers%ROWTYPE;
BEGIN
  -- جلب مخطط العمولة النشط
  SELECT cs.* INTO v_scheme
  FROM commission_schemes cs
  JOIN commission_assignments ca ON ca.scheme_id = cs.id
  WHERE ca.employee_id = p_employee_id
    AND ca.is_active = true
    AND p_period_start BETWEEN ca.start_date AND COALESCE(ca.end_date, '9999-12-31');

  -- حساب الأساس (مبيعات / تحصيل / ...)
  IF v_scheme.basis = 'sales_value' THEN
    SELECT COALESCE(SUM(so.total_amount), 0) INTO v_basis
    FROM sales_orders so
    JOIN sales_reps sr ON sr.id = so.sales_rep_id
    JOIN employees e ON e.id = sr.employee_id
    WHERE e.id = p_employee_id
      AND so.status = 'delivered'
      AND so.delivered_at::date BETWEEN p_period_start AND p_period_end;
  END IF;

  -- تطبيق الشرائح
  FOR v_tier IN
    SELECT * FROM commission_tiers
    WHERE scheme_id = v_scheme.id
      AND v_basis >= min_threshold
    ORDER BY min_threshold
  LOOP
    IF v_tier.type = 'percentage' THEN
      v_commission := v_commission +
        (LEAST(v_basis, COALESCE(v_tier.max_threshold, v_basis)) - v_tier.min_threshold)
        * v_tier.value / 100;
    ELSE
      v_commission := v_commission + v_tier.value;
    END IF;
  END LOOP;

  RETURN v_commission;
END; $$;
```

---

#### 5.5 الرواتب

```sql
payroll_periods: id, month, year, status (draft/calculated/approved/paid),
  total_amount, created_by

payroll_items: id, period_id, employee_id,
  base_salary, allowances, commissions,
  overtime_amount, bonuses,
  deductions (تأخير/غياب), penalties,
  net_salary, details JSONB

rewards_penalties: id, employee_id, type (reward/penalty),
  amount, reason, source_type, source_id,
  applied_to_period_id NULL
```

---

### 📊 المجموعة 6: الأنشطة والتقارير

#### 6.1 الأنشطة (زيارات + مكالمات)

```sql
activity_types: id, name, icon, requires_gps BOOL, requires_customer BOOL

activities: id, type_id, employee_id, customer_id NULL,
  subject, outcome, gps_lat, gps_lng,
  duration_minutes, activity_date,
  order_id NULL (ربط بطلب), created_by
```

#### 6.2 خطة الزيارات

```sql
visit_plans: id, employee_id, date, status (planned/in_progress/completed)

visit_plan_items: id, plan_id, customer_id, sequence,
  planned_time, actual_time, status, activity_id NULL
```

#### 6.3 الإشعارات

```sql
notifications: id, recipient_id, type, title, body,
  category, priority (low/medium/high/critical),
  action_url, metadata JSONB,
  is_read, read_at, created_at

notification_preferences: user_id, category, in_app, push, email

push_subscriptions: user_id, endpoint, keys JSONB, device_info
```

**الأحداث التي تستحق إشعاراً:**
- طلب بيع جديد يحتاج موافقة
- طلب يحتاج تسليم من مخزنك
- عميل تجاوز الحد الائتماني
- مخزون منخفض
- مرتجع جديد / إثبات دفع يحتاج مراجعة
- هدف قارب الانتهاء بدون تحقيق
- شكوى جديدة / تجاوزت SLA
- راتب شهري جاهز للاعتماد

---

### 📈 المجموعة 7: التقارير (3 مستويات)

```
CEO Dashboard: إيرادات + مصروفات + صافي ربح
              + أداء الفروع مقارنةً
              + عملاء في خطر (ديون متأخرة)
              + أعلى/أقل مبيعاً من المنتجات
              + مخزون منخفض + منتجات راكدة

مدير القسم:   أداء فريقه + أهداف القسم
             + طلبات معلقة تحتاج موافقته
             + مهام موظفيه

الموظف:       مهامي اليوم + أهدافي + عموالتي
             + خطة زياراتي + أنشطتي
```

**Views / Materialized Views:**
```sql
-- تقرير المبيعات
mv_sales_summary: period, customer_id, sales_rep_id,
  total_orders, total_amount, collected_amount, pending_amount

-- تقادم الديون
fn_aging_report(as_of_date): current/30/60/90/90+ days buckets

-- أداء المندوبين
mv_rep_performance: rep_id, period, orders_count, 
  sales_value, collection_rate, visits_count, calls_count,
  target_achievement_percent

-- حالة المخزون
v_stock_status: product_id, warehouse_id, quantity,
  reserved, available, status (ok/low/out_of_stock/excess)
```

---

## 2. ملفات rules وskills للمشروع الجديد

---

### `.agents/rules.md` (النسخة المحسنة)

**الإضافات على النسخة القديمة:**
1. **قاعدة الأمان #1**: `check_permission()` مطلوبة في كل RLS policy — لا استثناء
2. **قاعدة الأمان #2**: الصلاحيات تُجلب من DB فقط، لا تُخزن في localStorage
3. **قاعدة الأداء #1**: استعلامات Supabase بـ `select` محدد (لا `*` في الإنتاج للجداول الكبيرة)
4. **قاعدة الأداء #2**: أي نتيجة > 100 صف تستلزم pagination حقيقي (cursor-based لا offset)
5. **قاعدة البيانات #1**: `current_balance` يُحسب من Ledger دائماً — لا يُخزن كعدد ثابت قابل للتلف
6. **قاعدة المبيعات**: `sales_rep_id` يجب أن يُسند دائماً — لا null في الطلبات المكتملة
7. **قاعدة المخزون**: التحقق من المخزون يحدث عند التأكيد (بـ `FOR UPDATE` lock)

---

### `.agents/skills/sales-workflow/SKILL.md` (جديد)
تغطي: تدفق الطلبات، التحصيل، المرتجعات، الحجز والخصم من المخزون

### `.agents/skills/security-rls/SKILL.md` (جديد)
تغطي: RLS patterns، check_permission()، نماذج سياسات لكل نوع جدول

### `.agents/skills/financial-logic/SKILL.md` (جديد)
تغطي: Ledger pattern، الخزائن والعهدة، القيود المحاسبية التلقائية

### `.agents/skills/arabic-rtl/SKILL.md` (محسّن من القديم)
تغطي: RTL، Cairo font، CSS Variables، تصميم المكونات العربية

---

## 3. هيكل المشروع الجديد

```
new-edara-sys/
├── .agents/
│   ├── rules.md                    # القواعد العامة
│   ├── workflows/
│   │   ├── dev.md                  # تدفق تطوير الوحدات
│   │   └── design-rules.md         # قواعد التصميم
│   └── skills/
│       ├── arabic-rtl/SKILL.md
│       ├── sales-workflow/SKILL.md
│       ├── security-rls/SKILL.md
│       └── financial-logic/SKILL.md
├── docs/
│   ├── SYSTEM_SPEC.md              # مواصفات النظام الكاملة
│   ├── DB_SCHEMA.md                # وثائق قاعدة البيانات
│   └── PERMISSIONS.md              # قائمة كل الصلاحيات
├── supabase/
│   └── migrations/
│       ├── 01_foundation.sql       # Auth + Roles + RLS
│       ├── 02_master_data.sql      # Geography + Products + Customers
│       ├── 03_operations.sql       # Sales + Purchases + Finance
│       ├── 04_performance.sql      # Activities + Targets + Commissions
│       └── 05_hr_reports.sql       # HR + Reports + Notifications
└── src/
    ├── components/
    │   ├── ui/                     # بدائية (Button, Input, Modal...)
    │   ├── shared/                 # مشتركة (DataTable, FormField, StatCard)
    │   └── modules/                # خاصة بالوحدات
    ├── lib/
    │   ├── supabase/               # client + hooks
    │   ├── hooks/                  # custom hooks
    │   ├── services/               # data access layer
    │   ├── types/                  # TypeScript types
    │   ├── validations/            # Zod schemas
    │   ├── permissions/            # permission helpers
    │   └── utils/                  # currency, dates, etc.
    ├── pages/                      # الصفحات
    ├── stores/                     # Zustand stores
    └── styles/                     # CSS Variables + design tokens
```

---

## 4. خطة التطبيق — المراحل

### المرحلة 1: الأساس (2-3 أيام)
- [ ] إنشاء مشروع + Design System + CSS Variables
- [ ] Migration 01: Auth + Roles + RLS
- [ ] صفحات المصادقة + Provider
- [ ] Layout (Sidebar الذكي يتغير حسب الدور)
- [ ] إدارة المستخدمين + الأدوار + الصلاحيات

### المرحلة 2: بيانات الأساس (2-3 أيام)
- [ ] Migration 02: بيانات الأساس الكاملة
- [ ] المنتجات + التصنيفات + الوحدات + الباندل
- [ ] قوائم الأسعار (واجهة ذكية)
- [ ] العملاء + الفروع + جهات الاتصال
- [ ] الموردين
- [ ] المخازن + المخزون

### المرحلة 3: العمليات (3-4 أيام)
- [ ] Migration 03: العمليات
- [ ] المبيعات (الطلبات + التسليم + التحصيل + المرتجعات)
- [ ] المشتريات (الطلبات + الاستلام + المرتجعات)
- [ ] المالية (الخزائن + العهدة + المصروفات + المدفوعات)

### المرحلة 4: الأداء والموارد البشرية (3-4 أيام)
- [ ] Migration 04 + 05
- [ ] الأنشطة + خطة الزيارات
- [ ] الأهداف + العمولات
- [ ] الحضور (GPS) + الإجازات + الرواتب

### المرحلة 5: التقارير + الإشعارات (2-3 أيام)
- [ ] لوحات القيادة (3 مستويات)
- [ ] صفحات التقارير الكاملة
- [ ] نظام الإشعارات (In-App + Push)

### المرحلة 6: التطبيقات المتخصصة (مرحلة مستقبلية)
- واجهات مخصصة لكل دور داخل نفس الـ Web App
- تحسين تجربة المندوب (موبايل فيرست لصفحاته)
- تحسين تجربة أمين المخزن
- Dashboard المحاسب المتخصص
- بوابة العملاء (self-service)

### المرحلة 7: نقطة البيع — Retail POS (مرحلة مستقبلية)
> [!NOTE]
> البنية التحتية (جدول `branches.type = retail`، المخازن، الأسعار) مدعومة من البداية.
> لكن واجهة POS المخصصة تُبنى بعد اكتمال النظام الأساسي.

- واجهة POS مبسطة لمنافذ البيع
- بيع مباشر بدون طلب (قائمة أسعار ثابتة)
- طباعة فاتورة فورية
- جلسات كاشير (shift open/close)
- تسوية نهاية اليوم مع الخزنة

---

## 5. خطة التحقق

### اختبارات تلقائية (بعد كل Migration)
```bash
# تشغيل Migration مرتين (idempotency)
psql $DATABASE_URL -f 01_foundation.sql
psql $DATABASE_URL -f 01_foundation.sql  # يجب أن ينجح بدون أخطاء

# اختبار RLS
# تسجيل دخول بمستخدم بدون صلاحية sales.orders.read
# محاولة SELECT من sales_orders → يجب أن يرجع 0 صفوف
```

### اختبارات منطق العمل (يدوي)
1. إنشاء طلب مبيعات آجل لعميل في حد ائتمانه → يجب نجاح الطلب
2. إنشاء طلب آجل يتجاوز الحد الائتماني → يجب رفض التأكيد
3. مرتجع بكمية تتجاوز المُباع → يجب رفض
4. تحويل بين مخزن وآخر → يجب تحديث الكميات بشكل صحيح
5. حساب العمولة الشهرية لمندوب

### اختبار الأداء
```bash
# بعد حقن 5000 عميل + 50000 طلب:
# - صفحة قائمة الطلبات يجب أن تفتح < 1.5 ثانية
# - البحث عن عميل يجب أن يعطي نتيجة < 300ms
# - تقرير المبيعات الشهري < 3 ثواني
```
