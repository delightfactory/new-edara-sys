import postgres from 'postgres';
const sql = postgres('postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres',
  {ssl:{rejectUnauthorized:false},max:1});

const total  = await sql`SELECT COUNT(*) as cnt FROM customers`;
const active = await sql`SELECT COUNT(*) as cnt FROM customers WHERE is_active=true`;
const noCode = await sql`SELECT COUNT(*) as cnt FROM customers WHERE code IS NULL`;
const withRef= await sql`SELECT COUNT(*) as cnt FROM customers WHERE notes LIKE '%ref:%'`;

// هل العملاء النشطون المفقودون موجودون؟
const test1  = await sql`SELECT name,code,notes FROM customers WHERE notes LIKE '%ref:91bc9d28-ac15-4b15-95a8-6e6453a63147%' LIMIT 1`;
const test2  = await sql`SELECT name,code,notes FROM customers WHERE notes LIKE '%ref:8d9a47dc%' LIMIT 1`;

console.log(`إجمالي   : ${total[0].cnt}`);
console.log(`نشطون    : ${active[0].cnt}`);
console.log(`بدون code: ${noCode[0].cnt}`);
console.log(`مع ref   : ${withRef[0].cnt}`);
console.log(`\nاختبار عميل نشط #1 (M3 for wasging):`);
console.log(test1.length ? `  موجود: ${test1[0].name} | code: ${test1[0].code}` : '  غير موجود في DB');
console.log(`\nاختبار عميل نشط #2 (مغسلة ابن البلد):`);
console.log(test2.length ? `  موجود: ${test2[0].name} | code: ${test2[0].code}` : '  غير موجود في DB');

// جلب نموذج من سطر notes
const sample = await sql`SELECT name, code, LEFT(notes,100) as notes_preview FROM customers WHERE notes LIKE '%ref:%' LIMIT 3`;
console.log('\nنماذج من notes:');
sample.forEach(r => console.log(`  [${r.code}] ${r.name}: ${r.notes_preview}`));

await sql.end();
