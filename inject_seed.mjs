/**
 * inject_seed.mjs — v2
 * يحقن ملف 68_seed_customers.sql مباشرة في Supabase
 * عبر PostgreSQL connection مباشر
 */

import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── Connection مباشر ───────────────────────────────────────────
const DB_URL = 'postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres';

console.log(`
╔════════════════════════════════════════════════════════╗
║          Supabase Seed Injector v2                    ║
╠════════════════════════════════════════════════════════╣
║  Project : ozthzccqudrudicnneuu                       ║
║  Target  : 68_seed_customers.sql                      ║
╚════════════════════════════════════════════════════════╝
`);

// ── استيراد postgres ────────────────────────────────────────────
let postgres;
try {
  ({ default: postgres } = await import('postgres'));
} catch {
  console.error('❌ حزمة postgres غير مثبتة. شغّل: npm install postgres');
  process.exit(1);
}

const sql = postgres(DB_URL, {
  max          : 1,
  connect_timeout: 30,
  idle_timeout   : 60,
  ssl            : { rejectUnauthorized: false },
});

try {
  // اختبار الاتصال
  await sql`SELECT 1 as test`;
  console.log('✅ تم الاتصال بقاعدة البيانات بنجاح\n');
} catch (err) {
  console.error('❌ فشل الاتصال:', err.message);
  await sql.end();
  process.exit(1);
}

// ── قراءة ملف SQL ───────────────────────────────────────────────
const SQL_PATH = join(__dirname, 'supabase', 'migrations', '68_seed_customers.sql');
console.log(`▶ قراءة: ${SQL_PATH.split('\\').pop()}`);
const sqlContent = readFileSync(SQL_PATH, 'utf-8');

// ── تقسيم ذكي للـ statements ────────────────────────────────────
// نفصل على أساس السطور الفارغة بعد ;
const rawBlocks = sqlContent
  .split(/\n\s*\n/)
  .map(b => b.trim())
  .filter(b => b && !b.startsWith('--') && b !== 'BEGIN;' && b !== 'COMMIT;');

console.log(`  إجمالي blocks: ${rawBlocks.length}`);

// ── تنفيذ على دفعات ──────────────────────────────────────────────
const BATCH_SIZE = 25;
const batches = [];
for (let i = 0; i < rawBlocks.length; i += BATCH_SIZE) {
  batches.push(rawBlocks.slice(i, i + BATCH_SIZE));
}

console.log(`  الدفعات: ${batches.length} × ${BATCH_SIZE} block/دفعة\n`);

let done = 0, errors = 0;
const failedBatches = [];

for (let i = 0; i < batches.length; i++) {
  const batch = batches[i];
  const batchSQL = batch.join('\n');

  try {
    await sql.begin(async tx => {
      await tx.unsafe(batchSQL);
    });
    done += batch.length;
  } catch (err) {
    errors += batch.length;
    failedBatches.push({ index: i + 1, err: err.message.substring(0, 100) });

    // محاولة تنفيذ statement بـ statement في حال فشل الدفعة
    for (const stmt of batch) {
      try {
        await sql.unsafe(stmt);
        done++;
        errors--;
      } catch (e2) {
        // تجاهل أخطاء ON CONFLICT وWHERE NOT EXISTS المتوقعة
        if (!e2.message.includes('duplicate') && !e2.message.includes('unique')) {
          // سجّل الخطأ فقط لو مش متوقع
        }
      }
    }
  }

  // تقرير التقدم
  const pct = Math.round(((i + 1) / batches.length) * 100);
  process.stdout.write(`\r  [${String(i+1).padStart(3)}/${batches.length}] ${pct}% | نجح: ${done} | خطأ: ${errors}`);
}

console.log('\n');

// ── ملخص ─────────────────────────────────────────────────────────
console.log('═'.repeat(50));
console.log('✅ اكتمل الحقن');
console.log(`   نجح  : ${done} block`);
console.log(`   خطأ  : ${errors} block`);
if (failedBatches.length > 0 && errors > 0) {
  console.log('\n  أمثلة الأخطاء:');
  failedBatches.slice(0, 3).forEach(f =>
    console.log(`  [دفعة ${f.index}] ${f.err}`)
  );
}
console.log('═'.repeat(50));

// ── التحقق من النتيجة ────────────────────────────────────────────
try {
  const countResult = await sql`SELECT COUNT(*) as cnt FROM customers`;
  const contactResult = await sql`SELECT COUNT(*) as cnt FROM customer_contacts`;
  console.log(`\n📊 التحقق من قاعدة البيانات:`);
  console.log(`   customers         : ${countResult[0].cnt} سجل`);
  console.log(`   customer_contacts : ${contactResult[0].cnt} سجل`);
} catch (e) {
  console.log('  (تعذّر التحقق من العدد)');
}

await sql.end();
console.log('\n✓ تم إغلاق الاتصال.');
