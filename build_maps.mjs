/**
 * build_maps.mjs
 * جلب: المخزن الرئيسي + خريطة العملاء + خريطة المنتجات
 */
import postgres from 'postgres';
import { writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, '..', 'analyise-v2', 'public');

const sql = postgres(
  'postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres',
  { ssl: { rejectUnauthorized: false }, max: 1 }
);

// ── 1. المخزن الرئيسي ──────────────────────────────────────
const warehouses = await sql`
  SELECT id, name, is_active FROM warehouses ORDER BY created_at LIMIT 10
`;
console.log('المخازن المتاحة:');
warehouses.forEach(w => console.log(`  ${w.name} | ${w.id} | نشط: ${w.is_active}`));

const mainWarehouse = warehouses.find(w =>
  w.name?.includes('رئيس') || w.name?.toLowerCase().includes('main')
) || warehouses[0];
console.log(`\n✓ المخزن الافتراضي: ${mainWarehouse.name}`);
console.log(`  ID: ${mainWarehouse.id}`);

// ── 2. خريطة العملاء: code + old_ref → id ─────────────────
const customers = await sql`
  SELECT id, code, name, notes FROM customers WHERE is_active IS NOT NULL
`;
const customerMap = {};
for (const c of customers) {
  if (c.code) customerMap[c.code] = { id: c.id, name: c.name };
  const m = c.notes?.match(/ref:([0-9a-f-]{36})/i);
  if (m) customerMap[`ref:${m[1].toLowerCase()}`] = { id: c.id, name: c.name };
}
console.log(`\n✓ خريطة العملاء: ${Object.keys(customerMap).length} مفتاح`);

// ── 3. خريطة المنتجات: barcode → id + unit_id ─────────────
const products = await sql`
  SELECT p.id, p.sku, p.name, p.barcode, p.base_unit_id,
    u.id as unit_id, u.name as unit_name
  FROM products p
  LEFT JOIN units u ON u.id = p.base_unit_id
  WHERE p.barcode IS NOT NULL AND p.barcode != ''
`;
const productMap = {};
for (const p of products) {
  if (p.barcode) {
    productMap[p.barcode.toString().trim()] = {
      id: p.id, sku: p.sku, name: p.name,
      unit_id: p.unit_id, unit_name: p.unit_name
    };
  }
}
console.log(`✓ خريطة المنتجات: ${Object.keys(productMap).length} منتج`);

// نموذج عينة
console.log('\nنماذج من الخريطة:');
Object.entries(productMap).slice(0, 5).forEach(([bc, p]) =>
  console.log(`  barcode[${bc}] → ${p.sku} | ${p.name} | unit: ${p.unit_name}`)
);

// ── 4. التحقق من المستخدم ────────────────────────────────
const SYSTEM_USER_ID = '410c04bc-b571-49f8-89cf-8b78b7305fd6';
const user = await sql`
  SELECT id, full_name FROM profiles WHERE id = ${SYSTEM_USER_ID} LIMIT 1
`;
if (user.length > 0) console.log(`\n✓ المستخدم: ${user[0].full_name}`);
else console.log(`\n⚠️ المستخدم غير موجود في profiles`);

// ── حفظ الخرائط ──────────────────────────────────────────
const config = {
  SYSTEM_USER_ID,
  WAREHOUSE_ID: mainWarehouse.id,
  WAREHOUSE_NAME: mainWarehouse.name,
};
writeFileSync(join(OUT, 'injection_config.json'),
  JSON.stringify(config, null, 2));
writeFileSync(join(OUT, 'customer_map.json'),
  JSON.stringify(customerMap, null, 2));
writeFileSync(join(OUT, 'product_map.json'),
  JSON.stringify(productMap, null, 2));

console.log('\n✓ تم حفظ:');
console.log('  injection_config.json');
console.log('  customer_map.json');
console.log('  product_map.json');

await sql.end();
