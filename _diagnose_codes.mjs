import postgres from 'postgres';
const sql = postgres(
  'postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres',
  {ssl:{rejectUnauthorized:false},max:1}
);

// من أين جاء CUS-57575757؟
const weird = await sql`SELECT id, code, name, notes FROM customers WHERE code LIKE 'CUS-5%' ORDER BY code LIMIT 10`;
console.log('الأكواد الغريبة:');
weird.forEach(r => console.log(`  [${r.code}] ${r.name} | notes: ${r.notes?.substring(0,60)}`));

// ما هي الأكواد العالية جداً؟
const highCodes = await sql`
  SELECT code, name FROM customers
  WHERE code ~ '^CUS-[0-9]+$'
    AND CAST(substring(code FROM 5) AS int) > 10000
  ORDER BY code`;
console.log(`\nأكواد > CUS-10000 (${highCodes.length} سجل):`);
highCodes.forEach(r => console.log(`  [${r.code}] ${r.name}`));

// الـ sequence الحالية
const seqVal = await sql`SELECT last_value FROM customer_code_seq`;
console.log(`\nالـ sequence الحالية: ${seqVal[0].last_value}`);

// هل الأكواد CUS-00001 إلى CUS-01860 موجودة؟
const normalCodes = await sql`SELECT COUNT(*) as cnt FROM customers WHERE code ~ '^CUS-0[0-9]{4}$'`;
console.log(`أكواد CUS-0XXXX (طبيعية): ${normalCodes[0].cnt}`);

// توزيع الأكواد
const dist = await sql`
  SELECT 
    COUNT(*) FILTER (WHERE code LIKE 'CUS-0%') as normal,
    COUNT(*) FILTER (WHERE code NOT LIKE 'CUS-0%') as weird
  FROM customers WHERE code IS NOT NULL`;
console.log(`\nطبيعية (CUS-0...): ${dist[0].normal}`);
console.log(`غريبة (غير CUS-0...): ${dist[0].weird}`);

await sql.end();
