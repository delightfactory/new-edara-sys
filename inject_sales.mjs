/**
 * inject_sales.mjs
 * =================
 * حقن 7,627 فاتورة تاريخية بدون قيود محاسبية
 * Idempotent: ON CONFLICT (order_number) DO NOTHING
 */
import postgres from 'postgres';
import { readFileSync, writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PUB = join(__dirname, '..', 'analyise-v2', 'public');

const sql = postgres(
  'postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres',
  { ssl: { rejectUnauthorized: false }, max: 1, idle_timeout: 120, connect_timeout: 30 }
);

const invoices = JSON.parse(readFileSync(join(PUB, 'sales_invoices.json'), 'utf-8'));
const allItems = JSON.parse(readFileSync(join(PUB, 'sales_items.json'), 'utf-8'));

// تجميع البنود حسب invoice_uuid
const itemsByInv = {};
for (const item of allItems) {
  if (!itemsByInv[item.invoice_uuid]) itemsByInv[item.invoice_uuid] = [];
  itemsByInv[item.invoice_uuid].push(item);
}

console.log(`▶ فواتير: ${invoices.length.toLocaleString()}`);
console.log(`▶ بنود  : ${allItems.length.toLocaleString()}`);
console.log(`▶ الحقن يبدأ...\n`);

let inserted = 0, skipped = 0, errors = 0;
const errorLog = [];

const BATCH = 50; // فواتير لكل دورة

for (let i = 0; i < invoices.length; i += BATCH) {
  const batch = invoices.slice(i, i + BATCH);

  for (const inv of batch) {
    try {
      // ── حقن الفاتورة ──
      const result = await sql`
        INSERT INTO sales_orders (
          order_number, customer_id, status,
          order_date, delivered_at,
          subtotal, discount_amount, tax_amount,
          total_amount, paid_amount, returned_amount,
          payment_terms, payment_method,
          warehouse_id, created_by_id,
          confirmed_by, confirmed_at,
          delivered_by, notes,
          credit_check_passed
        )
        VALUES (
          ${inv.order_number},
          ${inv.customer_id},
          'completed',
          ${inv.order_date}::date,
          ${inv.delivered_at ? inv.delivered_at : inv.order_date}::timestamptz,
          ${inv.subtotal},
          ${inv.discount_amount},
          0,
          ${inv.total_amount},
          ${inv.paid_amount},
          0,
          'cash',
          'cash',
          ${inv.warehouse_id},
          ${inv.created_by_id},
          ${inv.created_by_id},
          ${inv.order_date}::timestamptz,
          ${inv.created_by_id},
          ${inv.notes},
          true
        )
        ON CONFLICT (order_number) DO NOTHING
        RETURNING id
      `;

      if (result.length === 0) {
        // الفاتورة موجودة مسبقاً — تحقق من ID
        const existing = await sql`
          SELECT id FROM sales_orders WHERE order_number = ${inv.order_number} LIMIT 1
        `;
        if (existing.length > 0) {
          skipped++;
          continue;
        }
      }

      const orderId = result[0]?.id;
      if (!orderId) { skipped++; continue; }

      // ── حقن البنود ──
      const items = itemsByInv[inv.old_uuid] || [];
      if (items.length > 0) {
        const itemRows = items.map(it => ({
          order_id          : orderId,
          product_id        : it.product_id,
          unit_id           : it.unit_id,
          conversion_factor : 1,
          quantity          : it.quantity,
          base_quantity     : it.quantity,
          delivered_quantity: it.delivered_qty,
          returned_quantity : 0,
          unit_price        : it.unit_price,
          discount_percent  : 0,
          discount_amount   : 0,
          tax_rate          : 0,
          tax_amount        : 0,
          line_total        : it.line_total,
          unit_cost_at_sale : 0,
        }));

        await sql`INSERT INTO sales_order_items ${sql(itemRows)} ON CONFLICT DO NOTHING`;
      }

      inserted++;
    } catch (e) {
      errors++;
      errorLog.push({ order: inv.order_number, error: e.message.substring(0, 120) });
      if (errors <= 5) console.log(`\n  ⚠️  ${inv.order_number}: ${e.message.substring(0, 80)}`);
    }
  }

  // تقرير دوري
  const done = Math.min(i + BATCH, invoices.length);
  process.stdout.write(`\r  ✓ ${inserted} حُقن | ${skipped} موجود | ${errors} خطأ | ${done}/${invoices.length}`);
}

// ── النتيجة النهائية ──
const finalInv   = await sql`SELECT COUNT(*) as cnt FROM sales_orders WHERE order_number LIKE 'HIST-%'`;
const finalItems = await sql`
  SELECT COUNT(*) as cnt FROM sales_order_items
  WHERE order_id IN (SELECT id FROM sales_orders WHERE order_number LIKE 'HIST-%')
`;

console.log('\n\n' + '═'.repeat(60));
console.log('✅ اكتمل الحقن');
console.log(`   حُقن    : ${inserted.toLocaleString()}`);
console.log(`   موجود   : ${skipped.toLocaleString()}`);
console.log(`   أخطاء   : ${errors}`);
console.log(`\n📊 قاعدة البيانات:`);
console.log(`   HIST فواتير  : ${finalInv[0].cnt}`);
console.log(`   HIST بنود    : ${finalItems[0].cnt}`);
console.log(`   المتوقع فواتير: 7,627`);

if (errorLog.length > 0) {
  writeFileSync(join(PUB, 'sales_injection_errors.json'),
    JSON.stringify(errorLog, null, 2));
  console.log(`\n⚠️  ${errorLog.length} خطأ محفوظ في sales_injection_errors.json`);
}
console.log('═'.repeat(60));

await sql.end();
