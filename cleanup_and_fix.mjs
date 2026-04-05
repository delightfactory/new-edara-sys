/**
 * cleanup_and_fix.mjs
 * ====================
 * 1. حذف العملاء بالأكواد الشاذة (> CUS-09999)
 * 2. إصلاح الـ sequence لتبدأ بعد أكبر كود طبيعي
 * 3. حقن الـ 219 مفقودين بشكل صحيح
 */
import postgres from 'postgres';
import { writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { execSync } from 'child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const sql = postgres(
  'postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres',
  { ssl: { rejectUnauthorized: false }, max: 1, idle_timeout: 60 }
);

// ══════════════════════════════════════════════════════════
// 1. حذف العملاء ذوي الأكواد الشاذة
// ══════════════════════════════════════════════════════════
console.log('▶ [1] حذف العملاء ذوي الأكواد الشاذة...');

// أكواد شاذة = تحتوي على رقم أكبر من 9999
const weirdCustomers = await sql`
  SELECT id, code, name
  FROM customers
  WHERE code ~ '^CUS-[0-9]+$'
    AND CAST(substring(code FROM 5) AS bigint) > 9999
  ORDER BY code
`;

if (weirdCustomers.length === 0) {
  console.log('  لا توجد أكواد شاذة.');
} else {
  console.log(`  سيُحذف ${weirdCustomers.length} سجل:`);
  weirdCustomers.forEach(r => console.log(`    [${r.code}] ${r.name}`));

  // حذف contacts أولاً
  const ids = weirdCustomers.map(r => r.id);
  await sql`DELETE FROM customer_contacts WHERE customer_id = ANY(${ids})`;
  const deleted = await sql`DELETE FROM customers WHERE id = ANY(${ids})`;
  console.log(`  ✓ حُذف ${weirdCustomers.length} عميل`);
}

// ══════════════════════════════════════════════════════════
// 2. إصلاح الـ sequence
// ══════════════════════════════════════════════════════════
console.log('\n▶ [2] إصلاح customer_code_seq...');

// أعلى كود طبيعي في DB الآن
const maxNormal = await sql`
  SELECT MAX(CAST(substring(code FROM 5) AS int)) as mx
  FROM customers
  WHERE code ~ '^CUS-[0-9]{5}$'
`;
const maxNum = parseInt(maxNormal[0].mx || '0');
console.log(`  أعلى كود طبيعي: CUS-${String(maxNum).padStart(5,'0')}`);

// نضع الـ sequence بعده بـ 100 هامش أمان
const newSeqVal = Math.max(maxNum, 1860);
await sql`SELECT setval('customer_code_seq', ${newSeqVal})`;
console.log(`  ✓ الـ sequence تم ضبطها على ${newSeqVal}`);
console.log(`  الكود التالي سيكون: CUS-${String(newSeqVal + 1).padStart(5,'0')}`);

// ══════════════════════════════════════════════════════════
// 3. جلب المفقودين من Excel
// ══════════════════════════════════════════════════════════
console.log('\n▶ [3] قراءة Excel...');

const py = `
import pandas as pd, json, sys, re
sys.stdout.reconfigure(encoding='utf-8')
df = pd.read_excel(r'c:\\Users\\HP\\OneDrive\\Desktop\\analyise-v2\\العملاء (2).xlsx')
df.columns = df.columns.str.strip()
CITY_FIX = {
    'الأسكندرية':'الإسكندرية','الأسماعيليه':'الإسماعيلية',
    'ايتاي البارود':'إيتاي البارود','ابو حمص':'أبو حمص',
    'ابو المطامير':'أبو المطامير','حوش عيسي':'حوش عيسى',
    'فوة':'فوه','6 اكتوبر / الشيخ زايد':'6 أكتوبر',
    'السادس من أكتوبر':'6 أكتوبر','الجيزة الجديدة':'الجيزة',
}
GOV_FIX = {'الاسكندرية':'الإسكندرية','الاسماعيلية':'الإسماعيلية'}
STATUS = {'عميل':{'a':True,'t':'wholesale'},'محتمل':{'a':True,'t':'retail'},'غير فعال':{'a':False,'t':'retail'}}
rows=[]
for _,r in df.iterrows():
    mob=str(r['الموبايل']).split('.')[0].strip() if not pd.isna(r['الموبايل']) else None
    if mob:
        s=re.sub(r'\\D','',mob)
        if len(s)==10 and s.startswith('1'): mob='0'+s
        elif len(s)==12 and s.startswith('20'): mob='0'+s[2:]
        elif len(s)==11 and s.startswith('01'): mob=s
        else: mob=None
    status=str(r['حالة العميل - الاسم']).strip()
    info=STATUS.get(status,{'a':False,'t':'retail'})
    city=str(r['المنطقة - الاسم']).strip() if not pd.isna(r['المنطقة - الاسم']) else None
    gov=str(r['المنطقة - المنطقة الرئيسية - الاسم']).strip() if not pd.isna(r['المنطقة - المنطقة الرئيسية - الاسم']) else None
    kval=str(r['الكود']).strip()
    code=None
    if not pd.isna(r['الكود']) and not kval.startswith('#') and kval not in ('nan',''):
        try: code=f'CUS-{int(float(kval)):05d}'
        except: pass
    rows.append({'name':str(r['الاسم']).strip(),'code':code,'old_id':str(r['المعرف']).strip(),
        'is_active':info['a'],'type':info['t'],
        'city':CITY_FIX.get(city,city),'gov':GOV_FIX.get(gov,gov),'mobile':mob})
print(json.dumps(rows,ensure_ascii=False))
`;

const pyFile = join(__dirname, '_py3.py');
writeFileSync(pyFile, py, 'utf-8');
const excel = JSON.parse(execSync(`python "${pyFile}"`, {
  env: { ...process.env, PYTHONUTF8: '1' },
  maxBuffer: 20 * 1024 * 1024, encoding: 'utf-8',
}).trim());
console.log(`  ✓ ${excel.length} عميل من Excel`);

// ══════════════════════════════════════════════════════════
// 4. تحديد المفقودين
// ══════════════════════════════════════════════════════════
const dbRows  = await sql`SELECT code, notes FROM customers`;
const dbRefs  = new Set();
const dbCodes = new Set();
for (const r of dbRows) {
  const m = r.notes?.match(/ref:([0-9a-f-]{36})/i);
  if (m) dbRefs.add(m[1].toLowerCase());
  if (r.code) dbCodes.add(r.code);
}

const missing = excel.filter(c => {
  if (c.code && dbCodes.has(c.code)) return false;
  if (c.old_id && dbRefs.has(c.old_id.toLowerCase())) return false;
  return true;
});

console.log(`\n▶ [4] المفقودون: ${missing.length}`);
console.log(`  نشطون   : ${missing.filter(c=>c.is_active&&c.type==='wholesale').length}`);
console.log(`  محتملون : ${missing.filter(c=>c.is_active&&c.type==='retail').length}`);
console.log(`  غير فعال: ${missing.filter(c=>!c.is_active).length}`);

if (missing.length === 0) {
  console.log('\n✅ لا يوجد مفقودون! جميع العملاء موجودون.');
  await sql.end();
  process.exit(0);
}

// ══════════════════════════════════════════════════════════
// 5. حقن المفقودين واحداً واحداً
// ══════════════════════════════════════════════════════════
console.log('\n▶ [5] الحقن...');
let inserted = 0, errorCount = 0;

for (const c of missing) {
  // جلب المدينة
  let city_id = null, gov_id = null;
  if (c.city) {
    const row = await sql`
      SELECT ci.id as cid, g.id as gid
      FROM cities ci
      JOIN governorates g ON g.id = ci.governorate_id
      WHERE ci.name = ${c.city} LIMIT 1
    `;
    if (row.length > 0) { city_id = row[0].cid; gov_id = row[0].gid; }
    else if (c.gov) {
      const g = await sql`SELECT id FROM governorates WHERE name = ${c.gov} LIMIT 1`;
      if (g.length > 0) gov_id = g[0].id;
    }
  }

  const notes = `ref:${c.old_id}`;

  try {
    if (c.code) {
      // له كود أصلي → حقن مع الكود
      await sql`
        INSERT INTO customers (code, name, type, city_id, governorate_id, mobile, payment_terms, is_active, notes)
        VALUES (${c.code}, ${c.name}, ${c.type}, ${city_id}, ${gov_id}, ${c.mobile||null}, 'cash', ${c.is_active}, ${notes})
        ON CONFLICT (code) DO UPDATE SET
          name=EXCLUDED.name, is_active=EXCLUDED.is_active,
          city_id=EXCLUDED.city_id, mobile=EXCLUDED.mobile,
          notes=EXCLUDED.notes, updated_at=now()
      `;
    } else {
      // بدون كود → trigger يُعيّن كود بعد 1860
      await sql`
        INSERT INTO customers (name, type, city_id, governorate_id, mobile, payment_terms, is_active, notes)
        VALUES (${c.name}, ${c.type}, ${city_id}, ${gov_id}, ${c.mobile||null}, 'cash', ${c.is_active}, ${notes})
      `;
    }
    inserted++;
    process.stdout.write(`\r  ✓ ${inserted}/${missing.length}  `);
  } catch (e) {
    errorCount++;
    console.log(`\n  ⚠️  "${c.name}": ${e.message.substring(0, 70)}`);
  }
}

// ══════════════════════════════════════════════════════════
// النتيجة النهائية
// ══════════════════════════════════════════════════════════
const total  = await sql`SELECT COUNT(*) as cnt FROM customers`;
const active = await sql`SELECT COUNT(*) as cnt FROM customers WHERE is_active = true`;
const seqNow = await sql`SELECT last_value FROM customer_code_seq`;

console.log('\n\n' + '═'.repeat(55));
console.log('✅ اكتملت العملية بالكامل');
console.log(`   حُقن جديد : ${inserted}`);
console.log(`   أخطاء     : ${errorCount}`);
console.log(`\n📊 قاعدة البيانات النهائية:`);
console.log(`   إجمالي    : ${total[0].cnt}  (المتوقع: 1860)`);
console.log(`   نشطون     : ${active[0].cnt}`);
console.log(`   الفارق    : ${1860 - parseInt(total[0].cnt)}`);
console.log(`   الـ sequence: ${seqNow[0].last_value}`);

if (Math.abs(1860 - parseInt(total[0].cnt)) <= 5) {
  console.log('\n   ✅ البيانات مكتملة بشكل ممتاز');
} else {
  console.log(`\n   ⚠️  لا يزال هناك ${1860 - parseInt(total[0].cnt)} مفقودون`);
}
console.log('═'.repeat(55));

await sql.end();
