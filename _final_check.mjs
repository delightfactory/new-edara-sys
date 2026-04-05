import postgres from 'postgres';
const sql = postgres(
  'postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres',
  {ssl:{rejectUnauthorized:false},max:1}
);

const total    = await sql`SELECT COUNT(*) as cnt FROM customers`;
const active   = await sql`SELECT COUNT(*) as cnt FROM customers WHERE is_active=true`;
const noRef    = await sql`SELECT COUNT(*) as cnt FROM customers WHERE notes NOT LIKE '%ref:%'`;
const samples  = await sql`SELECT name, code, notes FROM customers WHERE notes NOT LIKE '%ref:%' LIMIT 8`;

console.log(`إجمالي  : ${total[0].cnt}`);
console.log(`نشطون   : ${active[0].cnt}`);
console.log(`بدون ref: ${noRef[0].cnt}  ← هؤلاء كانوا في DB قبل عملنا`);
console.log('\nنماذج من العملاء القديمين (بدون ref):');
samples.forEach(r => console.log(`  [${r.code}] ${r.name} → notes: ${r.notes?.substring(0,60) || 'NULL'}`));

await sql.end();
