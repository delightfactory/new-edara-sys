
import pandas as pd, json, sys, re
sys.stdout.reconfigure(encoding='utf-8')
df = pd.read_excel(r'c:\Users\HP\OneDrive\Desktop\analyise-v2\العملاء (2).xlsx')
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
        s=re.sub(r'\D','',mob)
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
