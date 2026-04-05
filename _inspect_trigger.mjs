import postgres from 'postgres';
const sql = postgres(
  'postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres',
  {ssl:{rejectUnauthorized:false},max:1}
);

// فحص trigger المسؤول عن توليد الكود
const triggers = await sql`
  SELECT trigger_name, event_manipulation, action_statement
  FROM information_schema.triggers
  WHERE event_object_table = 'customers'
`;
console.log('Triggers على customers:');
triggers.forEach(t => console.log(`  [${t.event_manipulation}] ${t.trigger_name}`));
console.log();

// فحص الـ function التي يستدعيها الـ trigger
const funcs = await sql`
  SELECT proname, prosrc
  FROM pg_proc
  WHERE proname LIKE '%customer%code%' OR proname LIKE '%generate%code%' OR proname LIKE '%set%code%'
`;
funcs.forEach(f => {
  console.log(`Function: ${f.proname}`);
  console.log(f.prosrc?.substring(0, 400));
  console.log();
});

// اكتشاف ما هو الكود المولّد حالياً
const lastCode = await sql`SELECT MAX(code) as mx FROM customers WHERE code LIKE 'CUS-%'`;
console.log(`آخر كود في DB: ${lastCode[0].mx}`);

// فحص هل في DB عملاء code = NULL
const nullCodes = await sql`SELECT COUNT(*) as cnt FROM customers WHERE code IS NULL`;
console.log(`عملاء code=NULL: ${nullCodes[0].cnt}`);

// فحص التعارض: ماذا سيكون الكود التالي؟
const seq = await sql`
  SELECT last_value, increment_by FROM pg_sequences
  WHERE sequencename LIKE '%customer%'
`;
if (seq.length > 0) {
  console.log('\nCustomer sequence:');
  seq.forEach(s => console.log(`  last_value: ${s.last_value}, increment: ${s.increment_by}`));
}

await sql.end();
