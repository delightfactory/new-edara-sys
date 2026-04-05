/**
 * inject_truly_missing.mjs
 * الحقن المباشر للعملاء الغائبين فعلاً (لا يوجد ref لهم في DB)
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

const report = JSON.parse(
  readFileSync(join(__dirname, '..', 'analyise-v2', 'public', 'reconciliation_report.json'), 'utf-8')
);

// كل المفقودين - بدون كود
const allMissing = [
  ...report.missing_active,
  ...report.missing_lead,
  ...report.missing_inactive,
];

const STATUS_TYPE = {
  'نشط'     : { is_active: true,  type: 'wholesale' },
  'محتمل'   : { is_active: true,  type: 'retail'    },
  'غير فعال': { is_active: false, type: 'retail'    },
};

const CITY_FIX = {
  'الأسكندرية': 'الإسكندرية', 'الأسماعيليه': 'الإسماعيلية',
  'ايتاي البارود': 'إيتاي البارود', 'ابو حمص': 'أبو حمص',
  'ابو المطامير': 'أبو المطامير', 'حوش عيسي': 'حوش عيسى',
  'فوة': 'فوه', '6 اكتوبر / الشيخ زايد': '6 أكتوبر',
  'السادس من أكتوبر': '6 أكتوبر', 'الجيزة الجديدة': 'الجيزة',
};

function fixPhone(v) {
  if (!v) return null;
  const s = String(v).replace(/\D/g, '');
  if (s.startsWith('20') && s.length === 12) return '0' + s.slice(2);
  if (s.length === 10 && s.startsWith('1')) return '0' + s;
  if (s.startsWith('01') && s.length === 11) return s;
  return null;
}

console.log(`▶ العملاء المراد فحصهم: ${allMissing.length}`);

// للتحقق أولاً: من هم الغائبون فعلاً؟
const trulyMissing = [];
for (const c of allMissing) {
  const rows = await sql`
    SELECT 1 FROM customers WHERE notes LIKE ${'%ref:' + c.old_id + '%'} LIMIT 1
  `;
  if (rows.length === 0) trulyMissing.push(c);
}

console.log(`▶ غائبون فعلاً (ليس في DB): ${trulyMissing.length}`);

const activeCount   = trulyMissing.filter(c => c.label === 'نشط').length;
const leadCount     = trulyMissing.filter(c => c.label === 'محتمل').length;
const inactiveCount = trulyMissing.filter(c => c.label === 'غير فعال').length;
console.log(`   نشطون   : ${activeCount}`);
console.log(`   محتملون : ${leadCount}`);
console.log(`   غير فعال: ${inactiveCount}`);

if (trulyMissing.length === 0) {
  console.log('\n✅ لا يوجد عملاء مفقودون — جميعهم موجودون في DB!');
  await sql.end();
  process.exit(0);
}

// حقن المفقودين الحقيقيين
console.log('\n▶ حقن المفقودين...');
let inserted = 0, errors = 0;

for (const c of trulyMissing) {
  const info       = STATUS_TYPE[c.label] || { is_active: false, type: 'retail' };
  const cityClean  = CITY_FIX[c.city] || c.city;
  const mobile     = fixPhone(c.mobile);
  const notes      = `ref:${c.old_id}`;

  // جلب city_id
  let city_id = null, gov_id = null;
  if (cityClean) {
    const row = await sql`
      SELECT c.id as cid, g.id as gid
      FROM cities c JOIN governorates g ON g.id=c.governorate_id
      WHERE c.name = ${cityClean} LIMIT 1
    `;
    if (row.length > 0) { city_id = row[0].cid; gov_id = row[0].gid; }
  }

  try {
    await sql`
      INSERT INTO customers (name, type, city_id, governorate_id, mobile, payment_terms, is_active, notes)
      VALUES (${c.name}, ${info.type}, ${city_id}, ${gov_id}, ${mobile}, 'cash', ${info.is_active}, ${notes})
    `;
    inserted++;
    process.stdout.write(`\r  ✓ ${inserted}/${trulyMissing.length}: ${c.name.substring(0,30)}`);
  } catch (e) {
    errors++;
    console.log(`\n  ⚠️  "${c.name}": ${e.message.substring(0,60)}`);
  }
}

// التحقق النهائي
const finalTotal  = await sql`SELECT COUNT(*) as cnt FROM customers`;
const finalActive = await sql`SELECT COUNT(*) as cnt FROM customers WHERE is_active=true`;

console.log('\n\n' + '═'.repeat(55));
console.log('✅ اكتمل');
console.log(`   حُقن جديد: ${inserted} | أخطاء: ${errors}`);
console.log(`\n📊 قاعدة البيانات النهائية:`);
console.log(`   إجمالي: ${finalTotal[0].cnt}`);
console.log(`   نشطون : ${finalActive[0].cnt}`);
console.log('═'.repeat(55));

await sql.end();
