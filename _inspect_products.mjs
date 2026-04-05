import postgres from 'postgres';
const sql = postgres(
  'postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres',
  {ssl:{rejectUnauthorized:false},max:1}
);
// عينة من المنتجات في DB
const sample = await sql`SELECT id, sku, name, barcode FROM products ORDER BY created_at LIMIT 20`;
console.log('عينة من منتجات DB:');
sample.forEach(p => console.log(`  SKU=[${p.sku}] | ${p.name} | barcode=[${p.barcode}]`));
await sql.end();
