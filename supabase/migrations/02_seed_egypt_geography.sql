-- ============================================================
-- Seed: Egyptian Geography — المحافظات والمدن المصرية
-- ============================================================
-- Idempotent: safe to run multiple times (ON CONFLICT DO NOTHING)
-- يعتمد على: 02_master_data.sql (جدولا governorates و cities)
-- ============================================================

-- ============================================================
-- 1. المحافظات (27 محافظة)
-- ============================================================

INSERT INTO governorates (name, name_en, code, sort_order) VALUES
  ('القاهرة',       'Cairo',          '01', 1),
  ('الجيزة',        'Giza',           '02', 2),
  ('الإسكندرية',    'Alexandria',     '03', 3),
  ('الدقهلية',      'Dakahlia',       '04', 4),
  ('البحيرة',       'Beheira',        '05', 5),
  ('المنيا',        'Minya',          '06', 6),
  ('الشرقية',       'Sharqia',        '07', 7),
  ('الغربية',       'Gharbia',        '08', 8),
  ('سوهاج',         'Sohag',          '09', 9),
  ('أسيوط',         'Asyut',          '10', 10),
  ('المنوفية',      'Monufia',        '11', 11),
  ('القليوبية',     'Qalyubia',       '12', 12),
  ('الفيوم',        'Fayoum',         '13', 13),
  ('كفر الشيخ',     'Kafr El Sheikh', '14', 14),
  ('بني سويف',      'Beni Suef',      '15', 15),
  ('قنا',           'Qena',           '16', 16),
  ('الأقصر',        'Luxor',          '17', 17),
  ('أسوان',         'Aswan',          '18', 18),
  ('دمياط',         'Damietta',       '19', 19),
  ('الإسماعيلية',   'Ismailia',       '20', 20),
  ('السويس',        'Suez',           '21', 21),
  ('بورسعيد',       'Port Said',      '22', 22),
  ('شمال سيناء',    'North Sinai',    '23', 23),
  ('جنوب سيناء',    'South Sinai',    '24', 24),
  ('البحر الأحمر',  'Red Sea',        '25', 25),
  ('الوادي الجديد', 'New Valley',     '26', 26),
  ('مطروح',         'Matrouh',        '27', 27)
ON CONFLICT (code) DO NOTHING;

-- ============================================================
-- 2. المدن (مرتبطة بالمحافظات عبر الكود)
-- ============================================================
-- يُستخدم subquery لجلب governorate_id من الكود
-- ON CONFLICT لا يُطبق هنا لأن cities ليس لها UNIQUE على الاسم
-- نستخدم DO $$ مع IF NOT EXISTS لضمان الـ Idempotency
-- ============================================================

DO $$
DECLARE
  v_gov_id UUID;
BEGIN

  -- ===== 01 القاهرة =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '01';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('مدينة نصر',      'Nasr City',        1),
      ('المعادي',         'Maadi',            2),
      ('مصر الجديدة',    'Heliopolis',        3),
      ('شبرا',           'Shubra',            4),
      ('المقطم',         'Mokattam',          5),
      ('عين شمس',        'Ain Shams',         6),
      ('حلوان',          'Helwan',            7),
      ('التجمع الخامس',  'Fifth Settlement',  8),
      ('القاهرة الجديدة','New Cairo',         9),
      ('العاصمة الإدارية','Admin Capital',    10),
      ('15 مايو',        '15th of May',      11),
      ('البساتين',       'El Basateen',      12),
      ('دار السلام',     'Dar El Salam',     13),
      ('المرج',          'El Marg',          14),
      ('السلام',         'El Salam',         15),
      ('منشأة ناصر',     'Manshiyat Naser',  16)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 02 الجيزة =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '02';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('الجيزة',          'Giza',              1),
      ('6 أكتوبر',        '6th of October',    2),
      ('الشيخ زايد',      'Sheikh Zayed',      3),
      ('الهرم',           'Haram',             4),
      ('فيصل',            'Faisal',            5),
      ('البدرشين',        'El Badrashin',      6),
      ('الصف',            'El Saf',            7),
      ('أطفيح',           'Atfih',             8),
      ('العياط',          'El Ayat',           9),
      ('الواحات البحرية', 'Bahariya Oasis',   10),
      ('أبو النمرس',      'Abu El Nomros',    11),
      ('كرداسة',          'Kerdasa',          12),
      ('أوسيم',           'Oseem',            13)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 03 الإسكندرية =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '03';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('الإسكندرية',   'Alexandria',     1),
      ('برج العرب',    'Borg El Arab',   2),
      ('العامرية',     'El Amreya',      3),
      ('المنتزه',      'El Montazah',    4),
      ('الجمرك',       'El Gomrok',      5),
      ('وسط المدينة',  'Downtown',       6),
      ('العجمي',       'El Agamy',       7),
      ('سيدي جابر',    'Sidi Gaber',     8)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 04 الدقهلية (18 مركز + مدينتان) =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '04';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('المنصورة',       'Mansoura',          1),
      ('طلخا',           'Talkha',            2),
      ('ميت غمر',        'Mit Ghamr',         3),
      ('دكرنس',          'Dikirnis',          4),
      ('أجا',            'Aga',               5),
      ('منية النصر',     'Minyat El Nasr',    6),
      ('السنبلاوين',     'Sinbillawin',       7),
      ('شربين',          'Shirbin',           8),
      ('بلقاس',          'Bilqas',            9),
      ('المنزلة',        'El Manzala',       10),
      ('تمي الأمديد',    'Tami El Amdid',    11),
      ('الجمالية',       'El Gamaliya',      12),
      ('نبروه',          'Nabaroh',          13),
      ('المطرية',        'El Matariya',      14),
      ('بني عبيد',       'Bani Ubaid',       15),
      ('محلة دمنة',      'Mahallet Damana',  16),
      ('ميت سلسيل',      'Mit Salsil',       17),
      ('الكردي',         'El Kurdi',         18),
      ('جمصة',           'Gamasa',           19),
      ('المنصورة الجديدة','New Mansoura',     20)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 05 البحيرة =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '05';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('دمنهور',       'Damanhour',       1),
      ('كفر الدوار',   'Kafr El Dawwar',  2),
      ('رشيد',         'Rosetta',         3),
      ('إدكو',         'Edku',            4),
      ('أبو المطامير', 'Abu El Matameer', 5),
      ('حوش عيسى',     'Hosh Eisa',       6),
      ('شبراخيت',      'Shubrakhit',      7),
      ('الدلنجات',     'Delengat',        8),
      ('المحمودية',    'El Mahmoudeya',   9),
      ('الرحمانية',    'El Rahmaniya',   10),
      ('إيتاي البارود','Itay El Barud',  11),
      ('أبو حمص',      'Abu Hummus',     12),
      ('وادي النطرون',  'Wadi El Natroun',13),
      ('النوبارية',    'Nubaria',        14)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 06 المنيا =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '06';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('المنيا',         'Minya',           1),
      ('ملوي',           'Mallawi',         2),
      ('سمالوط',         'Samalut',         3),
      ('المنيا الجديدة', 'New Minya',       4),
      ('بني مزار',       'Beni Mazar',      5),
      ('مطاي',           'Matai',           6),
      ('أبو قرقاص',      'Abu Qirqas',      7),
      ('مغاغة',          'Maghagha',        8),
      ('العدوة',         'El Edwa',         9),
      ('دير مواس',       'Deir Mawas',     10)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 07 الشرقية (13 مركز + مدن) =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '07';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('الزقازيق',          'Zagazig',         1),
      ('العاشر من رمضان',   '10th of Ramadan',  2),
      ('بلبيس',             'Bilbeis',          3),
      ('منيا القمح',        'Minya El Qamh',    4),
      ('أبو حماد',          'Abu Hammad',       5),
      ('الحسينية',          'El Husseiniya',    6),
      ('ديرب نجم',          'Diarb Negm',       7),
      ('فاقوس',             'Faqous',           8),
      ('أبو كبير',          'Abu Kabir',        9),
      ('كفر صقر',           'Kafr Saqr',       10),
      ('الصالحية الجديدة',  'New Salhia',      11),
      ('أولاد صقر',         'Awlad Saqr',      12),
      ('ههيا',              'Hihya',           13),
      ('مشتول السوق',       'Mashtoul El Souq',14),
      ('الإبراهيمية',       'El Ibrahimiya',   15),
      ('القنايات',          'El Qanayat',      16),
      ('القرين',            'El Qurain',       17)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 08 الغربية =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '08';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('طنطا',         'Tanta',          1),
      ('المحلة الكبرى','Mahalla Kubra',   2),
      ('كفر الزيات',   'Kafr El Zayat',  3),
      ('زفتى',         'Zefta',          4),
      ('السنطة',       'El Santa',       5),
      ('بسيون',        'Basyoun',        6),
      ('قطور',         'Qutur',          7),
      ('سمنود',        'Samannoud',      8)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 09 سوهاج =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '09';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('سوهاج',        'Sohag',          1),
      ('أخميم',        'Akhmim',         2),
      ('جرجا',         'Girga',          3),
      ('طهطا',         'Tahta',          4),
      ('المراغة',      'El Maragha',     5),
      ('البلينا',      'El Balyana',     6),
      ('المنشاة',      'El Monsha',      7),
      ('دار السلام',   'Dar El Salam',   8),
      ('جهينة',        'Guhayna',        9),
      ('ساقلتة',       'Saqulta',       10),
      ('طما',          'Tema',          11)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 10 أسيوط =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '10';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('أسيوط',          'Asyut',           1),
      ('أسيوط الجديدة',  'New Asyut',       2),
      ('ديروط',          'Dayrut',          3),
      ('منفلوط',         'Manfalut',        4),
      ('القوصية',        'El Qusiya',       5),
      ('أبنوب',          'Abnoub',          6),
      ('أبو تيج',        'Abu Tig',         7),
      ('الغنايم',        'El Ghanayim',     8),
      ('ساحل سليم',      'Sahel Selim',     9),
      ('البداري',        'El Badari',      10),
      ('الفتح',          'El Fath',        11)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 11 المنوفية (9 مراكز + مدينة) =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '11';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('شبين الكوم',   'Shebin El Kom',   1),
      ('مدينة السادات','Sadat City',       2),
      ('منوف',         'Menouf',          3),
      ('سرس الليان',   'Sirs El Layan',   4),
      ('أشمون',        'Ashmoun',         5),
      ('الباجور',      'El Bagour',       6),
      ('قويسنا',       'Quweisna',        7),
      ('بركة السبع',   'Birket El Sab',   8),
      ('تلا',          'Tala',            9),
      ('الشهداء',      'El Shohada',     10)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 12 القليوبية (7 مراكز + مدن) =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '12';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('بنها',          'Banha',            1),
      ('شبرا الخيمة',   'Shubra El Kheima', 2),
      ('القناطر الخيرية','Qanater Khairiya', 3),
      ('قليوب',         'Qalyub',           4),
      ('الخانكة',       'El Khanka',        5),
      ('شبين القناطر',  'Shibin El Qanater',6),
      ('طوخ',           'Tukh',             7),
      ('كفر شكر',       'Kafr Shukr',       8),
      ('العبور',        'El Obour',         9),
      ('الخصوص',        'El Khosous',      10),
      ('قها',           'Qaha',            11)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 13 الفيوم =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '13';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('الفيوم',         'Fayoum',          1),
      ('الفيوم الجديدة', 'New Fayoum',      2),
      ('إبشواي',         'Ibsheway',        3),
      ('طامية',          'Tamiya',          4),
      ('سنورس',          'Senores',         5),
      ('يوسف الصديق',    'Yusuf El Siddiq', 6)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 14 كفر الشيخ =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '14';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('كفر الشيخ',    'Kafr El Sheikh',  1),
      ('دسوق',         'Desouk',          2),
      ('فوه',           'Fuwwah',          3),
      ('بيلا',          'Bella',           4),
      ('مطوبس',         'Mutubas',         5),
      ('الحامول',       'El Hamoul',       6),
      ('سيدي سالم',     'Sidi Salem',      7),
      ('بلطيم',         'Balteem',         8),
      ('الرياض',        'El Riyad',        9),
      ('قلين',          'Qellin',         10)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 15 بني سويف =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '15';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('بني سويف',         'Beni Suef',       1),
      ('بني سويف الجديدة', 'New Beni Suef',   2),
      ('الواسطى',          'El Wasta',        3),
      ('ناصر',             'Naser',           4),
      ('إهناسيا',          'Ihnasiya',        5),
      ('ببا',              'Beba',            6),
      ('الفشن',            'El Fashn',        7),
      ('سمسطا',            'Sumusta',         8)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 16 قنا =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '16';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('قنا',          'Qena',            1),
      ('نجع حمادي',    'Nag Hammadi',     2),
      ('دشنا',         'Dishna',          3),
      ('قوص',          'Qus',             4),
      ('نقادة',        'Naqada',          5),
      ('فرشوط',        'Farshut',         6),
      ('أبو تشت',      'Abu Tesht',       7),
      ('الوقف',        'El Waqf',         8),
      ('قفط',          'Qift',            9)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 17 الأقصر =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '17';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('الأقصر',       'Luxor',           1),
      ('إسنا',         'Esna',            2),
      ('أرمنت',        'Armant',          3),
      ('الطود',        'El Tod',          4),
      ('القرنة',       'El Qurna',        5),
      ('الزينية',      'El Zeineya',      6)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 18 أسوان =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '18';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('أسوان',        'Aswan',           1),
      ('كوم أمبو',     'Kom Ombo',        2),
      ('إدفو',         'Edfu',            3),
      ('دراو',         'Draw',            4),
      ('نصر النوبة',   'Nasr El Nuba',    5),
      ('أبو سمبل',     'Abu Simbel',      6)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 19 دمياط =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '19';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('دمياط',          'Damietta',        1),
      ('دمياط الجديدة',  'New Damietta',    2),
      ('رأس البر',       'Ras El Bar',      3),
      ('فارسكور',        'Faraskour',       4),
      ('الزرقا',         'El Zarqa',        5),
      ('كفر سعد',        'Kafr Saad',       6)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 20 الإسماعيلية =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '20';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('الإسماعيلية',    'Ismailia',        1),
      ('فايد',            'Fayed',           2),
      ('القنطرة شرق',    'Qantara East',    3),
      ('القنطرة غرب',    'Qantara West',    4),
      ('التل الكبير',    'Tel El Kebir',    5),
      ('أبو صوير',       'Abu Suweir',      6)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 21 السويس =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '21';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('السويس',       'Suez',            1),
      ('الأربعين',     'El Arbaeen',      2),
      ('عتاقة',        'Ataka',           3),
      ('الجناين',      'El Ganayen',      4),
      ('فيصل',         'Faisal',          5)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 22 بورسعيد =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '22';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('بورسعيد',      'Port Said',       1),
      ('بور فؤاد',     'Port Fouad',      2),
      ('العرب',        'El Arab',         3),
      ('حي الزهور',    'El Zohour',       4),
      ('المناخ',       'El Manakh',       5),
      ('الضواحي',      'El Dawahy',       6)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 23 شمال سيناء =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '23';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('العريش',       'El Arish',        1),
      ('الشيخ زويد',   'Sheikh Zuweid',   2),
      ('رفح',          'Rafah',           3),
      ('بئر العبد',    'Bir El Abd',      4),
      ('الحسنة',       'El Hasana',       5),
      ('نخل',          'Nakhl',           6)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 24 جنوب سيناء =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '24';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('شرم الشيخ',    'Sharm El Sheikh', 1),
      ('دهب',          'Dahab',           2),
      ('نويبع',        'Nuweiba',         3),
      ('طابا',         'Taba',            4),
      ('سانت كاترين',  'Saint Catherine', 5),
      ('الطور',        'El Tor',          6),
      ('أبو رديس',     'Abu Rudeis',      7),
      ('أبو زنيمة',    'Abu Zenima',      8)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 25 البحر الأحمر =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '25';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('الغردقة',      'Hurghada',        1),
      ('سفاجا',        'Safaga',          2),
      ('القصير',       'El Quseir',       3),
      ('مرسى علم',     'Marsa Alam',      4),
      ('رأس غارب',     'Ras Ghareb',      5),
      ('الشلاتين',     'Shalatin',        6),
      ('حلايب',        'Halayeb',         7)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 26 الوادي الجديد =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '26';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('الخارجة',      'El Kharga',       1),
      ('الداخلة',      'El Dakhla',       2),
      ('الفرافرة',     'El Farafra',      3),
      ('باريس',        'Paris',           4),
      ('بلاط',         'Balat',           5)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

  -- ===== 27 مطروح =====
  SELECT id INTO v_gov_id FROM governorates WHERE code = '27';
  IF v_gov_id IS NOT NULL THEN
    INSERT INTO cities (governorate_id, name, name_en, sort_order)
    SELECT v_gov_id, v.name, v.name_en, v.sort_order
    FROM (VALUES
      ('مرسى مطروح',      'Marsa Matrouh',   1),
      ('الحمام',           'El Hammam',       2),
      ('العلمين الجديدة',  'New Alamein',     3),
      ('الضبعة',           'El Dabaa',        4),
      ('سيدي براني',       'Sidi Barrani',    5),
      ('السلوم',           'El Sallum',       6),
      ('سيوة',             'Siwa',            7)
    ) AS v(name, name_en, sort_order)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.governorate_id = v_gov_id AND c.name = v.name
    );
  END IF;

END; $$;
