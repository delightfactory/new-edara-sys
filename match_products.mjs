/**
 * match_products.mjs
 * مطابقة منتجات ملف المبيعات مع قاعدة البيانات
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

// قراءة المنتجات من ملف CSV الذي أنشأه Python
const csv = readFileSync(
  join(__dirname, '..', 'analyise-v2', 'public', 'sales_products.csv'),
  'utf-8'
);
const lines = csv.trim().split('\n');
const headers = lines[0].split(',');
const salesProducts = lines.slice(1).map(line => {
  const vals = line.split(',');
  return Object.fromEntries(headers.map((h, i) => [h.trim(), (vals[i]||'').trim()]));
});

console.log(`▶ منتجات في ملف المبيعات: ${salesProducts.length}`);

// جلب كل المنتجات من DB
const dbProducts = await sql`
  SELECT p.id, p.sku, p.name, p.is_active,
    pc.name as category_name,
    b.name as brand_name
  FROM products p
  LEFT JOIN product_categories pc ON pc.id = p.category_id
  LEFT JOIN brands b ON b.id = p.brand_id
`;
console.log(`▶ منتجات في قاعدة البيانات: ${dbProducts.length}`);

// بناء خريطة البحث
const dbBySku = new Map(dbProducts.map(p => [p.sku?.toString().trim(), p]));

// المطابقة
const matched   = [];
const missing   = [];
const skuNull   = [];

for (const sp of salesProducts) {
  const code = sp.code?.trim();
  if (!code || code === 'nan' || code === '') { skuNull.push(sp); continue; }

  const dbProd = dbBySku.get(code);
  if (dbProd) {
    matched.push({ excel_code: code, excel_name: sp.name, db_name: dbProd.name, db_id: dbProd.id, category: dbProd.category_name });
  } else {
    missing.push({ code, name: sp.name, category: sp.category, list_price: sp.list_price });
  }
}

console.log('\n' + '═'.repeat(60));
console.log('📊 نتيجة مطابقة المنتجات');
console.log('═'.repeat(60));
console.log(`✅ مطابق (موجود في DB)  : ${matched.length}`);
console.log(`❌ مفقود (غير موجود)    : ${missing.length}`);
console.log(`⚠️  بدون كود            : ${skuNull.length}`);
console.log(`نسبة التغطية            : ${(matched.length / salesProducts.length * 100).toFixed(1)}%`);

if (missing.length > 0) {
  console.log('\n❌ المنتجات المفقودة:');
  missing.forEach(p => console.log(`  [${p.code}] ${p.name} (${p.category})`));
}

// ── إحصائيات إضافية ──
console.log('\n📋 تفصيل المطابقة بالتصنيف:');
const byCategory = {};
for (const m of matched) {
  byCategory[m.category] = (byCategory[m.category] || 0) + 1;
}
Object.entries(byCategory).sort((a,b) => b[1]-a[1]).forEach(([cat, cnt]) => {
  console.log(`  ${cat}: ${cnt}`);
});

// ── حفظ النتيجة ──
import { writeFileSync } from 'fs';
const report = {
  summary: {
    in_sales_file: salesProducts.length,
    in_db: dbProducts.length,
    matched: matched.length,
    missing: missing.length,
    no_code: skuNull.length,
    coverage_pct: parseFloat((matched.length / salesProducts.length * 100).toFixed(1))
  },
  missing_products: missing,
  matched_sample: matched.slice(0, 10)
};
writeFileSync(
  join(__dirname, '..', 'analyise-v2', 'public', 'product_match_report.json'),
  JSON.stringify(report, null, 2)
);
console.log('\n✓ تقرير محفوظ: product_match_report.json');

await sql.end();
