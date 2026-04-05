/**
 * deep_reconcile.mjs
 * ===================
 * مراجعة عميقة: فحص كل عميل في Excel بالـ UUID في DB
 * ثم حقن المفقودين واحداً واحداً بدون batches
 */
import postgres from 'postgres';
import { readFileSync, writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { execSync } from 'child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const sql = postgres(
  'postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres',
  { ssl: { rejectUnauthorized: false }, max: 1, idle_timeout: 60 }
);

// ── بيانات Excel عبر Python ──
const py = `
import pandas as pd, json, sys, re
sys.stdout.reconfigure(encoding='utf-8')
df = pd.read_excel(r'c:\\\\Users\\\\HP\\\\OneDrive\\\\Desktop\\\\analyise-v2\\\\العملاء (2).xlsx')
df.columns = df.columns.str.strip()
CITY_FIX = {
    'الأسكندرية':'الإسكندرية','الأسماعيليه':'الإسماعيلية',
    'ايتاي البارود':'إيتاي البارود','ابو حمص':'أبو حمص',
    'ابو المطامير':'أبو المطامير','حوش عيسي':'حوش عيسى',
    'فوة':'فوه','6 اكتوبر / الشيخ زايد':'6 أكتوبر',
    'السادس من أكتوبر':'6 أكتوبر','الجيزة الجديدة':'الجيزة',
    'كوم حمادة':'كوم حمادة','شبرا النملة':'شبرا النملة',
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
    if not pd.isna(r['الكود']) and not kval.startswith('#') and kval!='nan':
        try: code=f'CUS-{int(float(kval)):05d}'
        except: pass
    rows.append({'name':str(r['الاسم']).strip(),'code':code,'old_id':str(r['المعرف']).strip(),
        'is_active':info['a'],'type':info['t'],'status':status,
        'city':CITY_FIX.get(city,city),'gov':GOV_FIX.get(gov,gov),'mobile':mob})
print(json.dumps(rows,ensure_ascii=False))
`;

const pyFile = join(__dirname, '_py_export.py');
writeFileSync(pyFile, py.replace(/\\\\/g, '\\'), 'utf-8');
const out = execSync(`python "${pyFile}"`, {
  env: { ...process.env, PYTHONUTF8: '1' },
  maxBuffer: 20 * 1024 * 1024,
  encoding: 'utf-8',
});
const excel = JSON.parse(out.trim());
console.log(`✓ Excel: ${excel.length} عميل`);

// ── جلب كل الـ refs من DB ──
const dbRows = await sql`SELECT id, code, name, is_active, notes FROM customers`;
console.log(`✓ DB: ${dbRows.length} عميل\n`);

// استخرج UUIDs من notes
const dbRefMap = new Map();
for (const r of dbRows) {
  if (r.notes) {
    const m = r.notes.match(/ref:([0-9a-f-]{36})/i);
    if (m) dbRefMap.set(m[1].toLowerCase(), r);
  }
  if (r.code) dbRefMap.set('code:' + r.code, r);
}

// ── فحص كل عميل في Excel ──
const missing = [];
let found = 0;

for (const c of excel) {
  const byRef  = dbRefMap.get(c.old_id?.toLowerCase());
  const byCode = c.code ? dbRefMap.get('code:' + c.code) : null;

  if (byRef || byCode) {
    found++;
  } else {
    missing.push(c);
  }
}

const missActive   = missing.filter(c => c.status === 'عميل');
const missLead     = missing.filter(c => c.status === 'محتمل');
const missInactive = missing.filter(c => c.status === 'غير فعال');

console.log('═'.repeat(55));
console.log('📊 نتيجة المطابقة العميقة');
console.log('═'.repeat(55));
console.log(`Excel :  ${excel.length}`);
console.log(`DB    :  ${dbRows.length}`);
console.log(`موجود :  ${found}`);
console.log(`مفقود :  ${missing.length}`);
console.log(`  ❌ نشطون   : ${missActive.length}`);
console.log(`  ⚠️  محتملون: ${missLead.length}`);
console.log(`  ℹ️  غير فعال: ${missInactive.length}`);

if (missing.length === 0) {
  console.log('\n✅ لا يوجد عملاء مفقودون!');
  await sql.end();
  process.exit(0);
}

// ── فحص سبب المشكلة في UNIQUE constraint ──
console.log('\n▶  فحص schema constraint...');
const constraint = await sql`
  SELECT conname, contype, pg_get_constraintdef(oid) as def
  FROM pg_constraint
  WHERE conrelid = 'customers'::regclass
  ORDER BY contype
`;
console.log('Constraints على جدول customers:');
constraint.forEach(c => console.log(`  [${c.contype}] ${c.conname}: ${c.def}`));

// ── حقن المفقودين واحداً واحداً ──
console.log(`\n▶ حقن ${missing.length} عميل مفقود...`);

let inserted = 0, skipped = 0, errors = 0;
const errorLog = [];

for (const c of missing) {
  // double-check في DB
  const check = c.old_id
    ? await sql`SELECT 1 FROM customers WHERE notes LIKE ${'%ref:' + c.old_id + '%'} LIMIT 1`
    : [];

  if (check.length > 0) { skipped++; continue; }

  let city_id = null, gov_id = null;
  if (c.city) {
    const row = await sql`
      SELECT ci.id as cid, g.id as gid
      FROM cities ci JOIN governorates g ON g.id=ci.governorate_id
      WHERE ci.name = ${c.city} LIMIT 1`;
    if (row.length > 0) { city_id = row[0].cid; gov_id = row[0].gid; }
    else if (c.gov) {
      const gRow = await sql`SELECT id FROM governorates WHERE name=${c.gov} LIMIT 1`;
      if (gRow.length > 0) gov_id = gRow[0].id;
    }
  }

  const notes = `ref:${c.old_id}`;

  try {
    await sql`
      INSERT INTO customers (name, type, city_id, governorate_id, mobile, payment_terms, is_active, notes)
      VALUES (${c.name}, ${c.type}, ${city_id}, ${gov_id}, ${c.mobile || null}, 'cash', ${c.is_active}, ${notes})
    `;
    inserted++;
    process.stdout.write(`\r  ✓ ${inserted} حُقن | ${skipped} تكرار | ${errors} خطأ  `);
  } catch (e) {
    errors++;
    errorLog.push({ name: c.name, error: e.message.substring(0, 100) });
    process.stdout.write(`\r  ✓ ${inserted} حُقن | ${skipped} تكرار | ${errors} خطأ  `);
  }
}

// ── النتيجة ──
const final = await sql`SELECT COUNT(*) as cnt FROM customers`;
const finalActive = await sql`SELECT COUNT(*) as cnt FROM customers WHERE is_active = true`;

console.log('\n\n' + '═'.repeat(55));
console.log('✅ اكتمل الحقن');
console.log(`   حُقن جديد   : ${inserted}`);
console.log(`   تكرار       : ${skipped}`);
console.log(`   أخطاء       : ${errors}`);
console.log(`\n📊 DB النهائية:`);
console.log(`   إجمالي : ${final[0].cnt}`);
console.log(`   نشطون  : ${finalActive[0].cnt}`);
console.log(`   المتوقع : 1860`);
console.log(`   الفارق  : ${1860 - parseInt(final[0].cnt)}`);

if (errorLog.length > 0) {
  console.log('\nأخطاء فريدة:');
  errorLog.slice(0, 5).forEach(e => console.log(`  • ${e.name}: ${e.error}`));
}
console.log('═'.repeat(55));

await sql.end();
