/**
 * reconcile_customers.mjs
 * ========================
 * مطابقة دقيقة بين ملف Excel وقاعدة البيانات
 * للتأكد من عدم فقدان أي عميل نشط أو محتمل
 */
import postgres from 'postgres';
import { readFileSync, writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { execSync } from 'child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));

const sql = postgres(
  'postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres',
  { ssl: { rejectUnauthorized: false }, max: 1 }
);

// ── 1. قراءة بيانات Excel بـ Python ──────────────────────────────
console.log('▶ استخراج بيانات Excel...');

const pyScript = `
import pandas as pd, json, sys
sys.stdout.reconfigure(encoding='utf-8')

df = pd.read_excel(r'${join(__dirname, '..', 'analyise-v2', 'العملاء (2).xlsx').replace(/\\/g, '\\\\')}')
df.columns = df.columns.str.strip()

def clean_code(val):
    if pd.isna(val): return None
    s = str(val).strip()
    if s.startswith('#') or s in ('nan','',''): return None
    try: return f'CUS-{int(float(s)):05d}'
    except: return None

STATUS_MAP = {
    'عميل'    : {'is_active': True,  'type': 'نشط'},
    'محتمل'   : {'is_active': True,  'type': 'محتمل'},
    'غير فعال': {'is_active': False, 'type': 'غير فعال'},
}

records = []
for _, r in df.iterrows():
    status = str(r['حالة العميل - الاسم']).strip()
    info   = STATUS_MAP.get(status, {'is_active': False, 'type': 'غير معروف'})
    records.append({
        'name'      : str(r['الاسم']).strip(),
        'code'      : clean_code(r['الكود']),
        'old_id'    : str(r['المعرف']).strip(),
        'status'    : status,
        'is_active' : info['is_active'],
        'type_label': info['type'],
        'city'      : str(r['المنطقة - الاسم']).strip() if not pd.isna(r['المنطقة - الاسم']) else None,
        'mobile'    : str(r['الموبايل']).split('.')[0].strip() if not pd.isna(r['الموبايل']) else None,
    })

print(json.dumps(records, ensure_ascii=False))
`;

const pyOut = execSync(`python -c "${pyScript.replace(/"/g, '\\"')}"`,
  { env: { ...process.env, PYTHONUTF8: '1' }, maxBuffer: 10 * 1024 * 1024 }
).toString('utf-8');

const excelRows = JSON.parse(pyOut);

console.log(`  ✓ Excel: ${excelRows.length} عميل`);

// ── 2. جلب كل العملاء من DB ──────────────────────────────────────
console.log('▶ جلب بيانات قاعدة البيانات...');

const dbCustomers = await sql`
  SELECT 
    id, code, name, is_active, type, mobile, notes,
    city_id, governorate_id
  FROM customers
  ORDER BY code NULLS LAST
`;

console.log(`  ✓ DB: ${dbCustomers.length} عميل`);

// ── 3. بناء خرائط البحث ──────────────────────────────────────────
// خريطة DB: code → row
const dbByCode   = new Map(dbCustomers.filter(r => r.code).map(r => [r.code, r]));
// بحث بالـ ref (old_id) في notes
const dbByRef    = new Map(dbCustomers.filter(r => r.notes?.includes('ref:')).map(r => {
  const match = r.notes.match(/ref:([a-f0-9-]{36})/);
  return match ? [match[1], r] : null;
}).filter(Boolean));

// ── 4. المقارنة عميل بعميل ───────────────────────────────────────
console.log('▶ تشغيل المقارنة...');

const results = {
  found_exact   : [],   // وُجد بالكود تماماً
  found_by_ref  : [],   // وُجد عبر الـ ref/UUID القديم
  missing_active: [],   // ❌ مفقود وكان نشط
  missing_lead  : [],   // ❌ مفقود وكان محتمل
  missing_inactive: [], // مفقود وكان غير فعال
};

for (const row of excelRows) {
  // بحث بالكود أولاً
  let dbRow = row.code ? dbByCode.get(row.code) : null;
  let matchMethod = 'code';

  // بحث بالـ old_id إذا لم يُوجد بالكود
  if (!dbRow && row.old_id) {
    dbRow = dbByRef.get(row.old_id);
    matchMethod = 'ref';
  }

  if (dbRow) {
    results[matchMethod === 'code' ? 'found_exact' : 'found_by_ref'].push({
      excel_name: row.name,
      db_name   : dbRow.name,
      code      : row.code,
      status    : row.type_label,
      city      : row.city,
      match_via : matchMethod,
    });
  } else {
    // مفقود — صنّف حسب الحالة
    const entry = {
      name    : row.name,
      code    : row.code,
      old_id  : row.old_id,
      status  : row.type_label,
      city    : row.city,
      mobile  : row.mobile,
    };
    if (row.status === 'عميل')     results.missing_active.push(entry);
    else if (row.status === 'محتمل') results.missing_lead.push(entry);
    else                             results.missing_inactive.push(entry);
  }
}

// ── 5. التقرير ────────────────────────────────────────────────────
console.log('\n' + '═'.repeat(60));
console.log('📊 تقرير المطابقة النهائي');
console.log('═'.repeat(60));
console.log(`\nإجمالي في Excel          : ${excelRows.length}`);
console.log(`وُجد بالكود تماماً        : ${results.found_exact.length}`);
console.log(`وُجد بالـ ref (بدون كود): ${results.found_by_ref.length}`);
console.log(`المجموع الموجود          : ${results.found_exact.length + results.found_by_ref.length}`);
console.log(`\n❌ مفقودون:`);
console.log(`   عملاء نشطون مفقودون    : ${results.missing_active.length}`);
console.log(`   عملاء محتملون مفقودون  : ${results.missing_lead.length}`);
console.log(`   غير فعالين مفقودون     : ${results.missing_inactive.length}`);
console.log(`   إجمالي المفقودين       : ${results.missing_active.length + results.missing_lead.length + results.missing_inactive.length}`);

// تفاصيل المفقودين النشطين
if (results.missing_active.length > 0) {
  console.log('\n⛔ العملاء النشطون المفقودون (مهم!):');
  results.missing_active.forEach(r =>
    console.log(`   • ${r.name.padEnd(30)} | كود: ${r.code || 'NULL'} | ${r.city} | ${r.mobile || '--'}`)
  );
}

if (results.missing_lead.length > 0) {
  console.log('\n⚠️  العملاء المحتملون المفقودون:');
  results.missing_lead.forEach(r =>
    console.log(`   • ${r.name.padEnd(30)} | كود: ${r.code || 'NULL'} | ${r.city}`)
  );
}

// حفظ تقرير JSON كامل
const reportPath = join(__dirname, '..', 'analyise-v2', 'public', 'reconciliation_report.json');
writeFileSync(reportPath, JSON.stringify({
  summary: {
    excel_total    : excelRows.length,
    db_total       : dbCustomers.length,
    found_exact    : results.found_exact.length,
    found_by_ref   : results.found_by_ref.length,
    total_found    : results.found_exact.length + results.found_by_ref.length,
    missing_active : results.missing_active.length,
    missing_lead   : results.missing_lead.length,
    missing_inactive: results.missing_inactive.length,
    total_missing  : results.missing_active.length + results.missing_lead.length + results.missing_inactive.length,
  },
  missing_active  : results.missing_active,
  missing_lead    : results.missing_lead,
  missing_inactive: results.missing_inactive.slice(0, 20), // أول 20 فقط
}, null, 2, ), 'utf-8');

console.log(`\n✓ تقرير مفصل محفوظ في: reconciliation_report.json`);
console.log('═'.repeat(60));

await sql.end();
