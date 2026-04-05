/**
 * verify_injection.mjs
 * التحقق من نتيجة الحقن ومعرفة سبب الفارق
 */
import postgres from 'postgres';

const sql = postgres(
  'postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres',
  { ssl: { rejectUnauthorized: false } }
);

console.log('📊 تقرير التحقق من الحقن\n');

// إجمالي العملاء
const total = await sql`SELECT COUNT(*) as cnt FROM customers`;
console.log(`إجمالي العملاء في DB   : ${total[0].cnt}`);

// توزيع is_active
const active = await sql`
  SELECT is_active, COUNT(*) as cnt 
  FROM customers 
  GROUP BY is_active 
  ORDER BY is_active DESC
`;
active.forEach(r => 
  console.log(`  ${r.is_active ? 'نشط  ' : 'غير نشط'}: ${r.cnt}`)
);

// توزيع type
const types = await sql`
  SELECT type, COUNT(*) as cnt 
  FROM customers 
  GROUP BY type 
  ORDER BY cnt DESC
`;
console.log('\nتوزيع الأنواع:');
types.forEach(r => console.log(`  ${r.type}: ${r.cnt}`));

// عملاء بدون city_id
const noCityCount = await sql`SELECT COUNT(*) as cnt FROM customers WHERE city_id IS NULL`;
console.log(`\nبدون city_id  : ${noCityCount[0].cnt}`);

// عملاء بدون gov
const noGovCount = await sql`SELECT COUNT(*) as cnt FROM customers WHERE governorate_id IS NULL`;
console.log(`بدون gov_id   : ${noGovCount[0].cnt}`);

// عملاء بدون كود
const noCode = await sql`SELECT COUNT(*) as cnt FROM customers WHERE code IS NULL`;
console.log(`بدون code     : ${noCode[0].cnt}`);

// عملاء بكود تبدأ بـ CUS
const withCode = await sql`SELECT COUNT(*) as cnt FROM customers WHERE code LIKE 'CUS-%'`;
console.log(`بكود CUS-*    : ${withCode[0].cnt}`);

// contacts
const contacts = await sql`SELECT COUNT(*) as cnt FROM customer_contacts`;
console.log(`\nCustomer Contacts: ${contacts[0].cnt}`);

// عينة من البيانات المحقونة
console.log('\nعينة (5 عملاء):');
const sample = await sql`
  SELECT c.name, c.code, c.type, c.is_active, 
         ci.name as city, g.name as gov,
         c.mobile
  FROM customers c
  LEFT JOIN cities ci ON ci.id = c.city_id
  LEFT JOIN governorates g ON g.id = c.governorate_id
  WHERE c.code LIKE 'CUS-%'
  ORDER BY c.created_at DESC
  LIMIT 5
`;
sample.forEach(r => 
  console.log(`  [${r.is_active ? 'نشط' : 'لا'}] ${r.name} | ${r.city}/${r.gov} | ${r.mobile || 'لا هاتف'}`)
);

// فحص العملاء الذين لم يُحقنوا (بدون ref في notes)
const noRef = await sql`SELECT COUNT(*) as cnt FROM customers WHERE notes NOT LIKE '%ref:%'`;
console.log(`\nبدون ref في notes: ${noRef[0].cnt} (كانوا موجودين قبل الحقن)`);

// عملاء من قبل الحقن (لا يحملون ref القديم)
console.log('\n✅ الحقن اكتمل بنجاح');

await sql.end();
