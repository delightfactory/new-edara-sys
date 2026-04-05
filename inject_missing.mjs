/**
 * inject_missing.mjs
 * ==================
 * يحقن العملاء المفقودين (بدون كود) الذين لم يُحقنوا
 * النتيجة: 227 عميل = 10 نشط + 96 محتمل + 121 غير فعال
 */
import postgres from 'postgres';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

const sql = postgres(
  'postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres',
  { ssl: { rejectUnauthorized: false }, max: 1 }
);

// قراءة تقرير المطابقة
const report = JSON.parse(
  readFileSync(join(__dirname, '..', 'analyise-v2', 'public', 'reconciliation_report.json'), 'utf-8')
);

const missing = [
  ...report.missing_active,
  ...report.missing_lead,
  ...report.missing_inactive,
];

console.log(`▶ عملاء مفقودون يجب حقنهم: ${missing.length}`);
console.log(`  نشطون   : ${report.summary.missing_active}`);
console.log(`  محتملون : ${report.summary.missing_lead}`);
console.log(`  غير فعال: ${report.summary.missing_inactive}`);
console.log('');

const STATUS_TO_TYPE = {
  'نشط'       : { is_active: true,  type: 'wholesale' },
  'محتمل'     : { is_active: true,  type: 'retail' },
  'غير فعال'  : { is_active: false, type: 'retail' },
};

// تنظيف الهاتف
function cleanPhone(val) {
  if (!val) return null;
  const s = val.replace(/\D/g, '');
  if (s.startsWith('20') && s.length === 12) return '0' + s.slice(2);
  if (s.length === 10 && s.startsWith('1')) return '0' + s;
  if (s.startsWith('01') && s.length === 11) return s;
  return null;
}

let inserted = 0, skipped = 0, errors = 0;

for (const c of missing) {
  const ref      = c.old_id;
  const name     = c.name;
  const label    = c.label;
  const city     = c.city;
  const mobile   = cleanPhone(c.mobile);
  const info     = STATUS_TO_TYPE[label] || { is_active: false, type: 'retail' };
  const notes    = `ref:${ref}`;

  try {
    // تحقق أولاً — هل موجود بالفعل؟
    const exists = await sql`
      SELECT 1 FROM customers WHERE notes LIKE ${'%ref:' + ref + '%'} LIMIT 1
    `;

    if (exists.length > 0) {
      skipped++;
      continue;
    }

    // جلب غرID المدينة والمحافظة
    let city_id = null, gov_id = null;

    if (city) {
      // تحقق من تصحيح اسم المدينة أولاً
      const CITY_FIX = {
        'الأسكندرية': 'الإسكندرية', 'الأسماعيليه': 'الإسماعيلية',
        'ايتاي البارود': 'إيتاي البارود', 'ابو حمص': 'أبو حمص',
        'ابو المطامير': 'أبو المطامير', 'حوش عيسي': 'حوش عيسى',
        'فوة': 'فوه', '6 اكتوبر / الشيخ زايد': '6 أكتوبر',
        'السادس من أكتوبر': '6 أكتوبر', 'الجيزة الجديدة': 'الجيزة',
      };
      const cityClean = CITY_FIX[city] || city;

      const cityRow = await sql`
        SELECT c.id as city_id, g.id as gov_id
        FROM cities c
        JOIN governorates g ON g.id = c.governorate_id
        WHERE c.name = ${cityClean}
        LIMIT 1
      `;
      if (cityRow.length > 0) {
        city_id = cityRow[0].city_id;
        gov_id  = cityRow[0].gov_id;
      } else {
        // محافظة فقط بدون مدينة
        const govRow = await sql`SELECT id FROM governorates WHERE name LIMIT 1`;
      }
    }

    await sql`
      INSERT INTO customers (name, type, city_id, governorate_id, mobile, payment_terms, is_active, notes)
      VALUES (${name}, ${info.type}, ${city_id}, ${gov_id}, ${mobile}, 'cash', ${info.is_active}, ${notes})
    `;

    inserted++;
    process.stdout.write(`\r  ✓ حُقن: ${inserted} | تخطّى: ${skipped} | خطأ: ${errors}`);

  } catch (err) {
    errors++;
    console.log(`\n  ⚠️  خطأ في "${name}": ${err.message.substring(0, 80)}`);
  }
}

console.log('\n');
console.log('═'.repeat(50));
console.log('✅ اكتمل حقن المفقودين');
console.log(`   حُقن جديد : ${inserted}`);
console.log(`   موجود مسبقاً: ${skipped}`);
console.log(`   أخطاء    : ${errors}`);

// التحقق النهائي
const finalCount = await sql`SELECT COUNT(*) as cnt FROM customers`;
const activeCount = await sql`SELECT COUNT(*) as cnt FROM customers WHERE is_active = true`;
console.log(`\n📊 قاعدة البيانات الآن:`);
console.log(`   إجمالي customers: ${finalCount[0].cnt}`);
console.log(`   نشطون           : ${activeCount[0].cnt}`);
console.log('═'.repeat(50));

await sql.end();
