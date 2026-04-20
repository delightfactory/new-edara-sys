-- ===========================================================
-- Migration 106: Sync Customer Locations
-- Source     : export result.xlsx
-- Total rows : 725 customers with coordinates
-- ===========================================================

BEGIN;

UPDATE customers 
SET 
  latitude = 30.80042,
  longitude = 30.963875,
  location_accuracy = 23.1,
  address = COALESCE(address, 'محلة مرحوم قبل الموقف يمين'),
  location_updated_at = now()
WHERE code = 'CUS-00727';
UPDATE customers 
SET 
  latitude = 30.792128,
  longitude = 30.984339,
  location_accuracy = 15.17,
  address = COALESCE(address, 'خلف اسماك بحري ش الفاتح'),
  location_updated_at = now()
WHERE code = 'CUS-01160';
UPDATE customers 
SET 
  latitude = 30.780787,
  longitude = 30.984613,
  location_accuracy = 46.25,
  address = COALESCE(address, 'شارع صادومه'),
  location_updated_at = now()
WHERE code = 'CUS-01631';
UPDATE customers 
SET 
  latitude = 30.790836,
  longitude = 30.976395,
  location_accuracy = 12.1,
  address = COALESCE(address, 'اخر  المعاهدة ش الصواف العمومى أمام معرض الحداد'),
  location_updated_at = now()
WHERE code = 'CUS-00362';
UPDATE customers 
SET 
  latitude = 30.80896,
  longitude = 31.00008,
  location_accuracy = 35.0,
  address = COALESCE(address, 'طريق كفر الشيخ الدولى'),
  location_updated_at = now()
WHERE code = 'CUS-01536';
UPDATE customers 
SET 
  latitude = 30.888517,
  longitude = 30.663855,
  location_accuracy = 26.023,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01020';
UPDATE customers 
SET 
  latitude = 30.807714,
  longitude = 31.001747,
  location_accuracy = 35.393,
  address = COALESCE(address, 'الكورنيش قحافة داخلة قاعة المماليك'),
  location_updated_at = now()
WHERE code = 'CUS-01136';
UPDATE customers 
SET 
  latitude = 30.792223,
  longitude = 30.985607,
  location_accuracy = 15.337,
  address = COALESCE(address, 'طنطا عند ترعة سنارة'),
  location_updated_at = now()
WHERE code = 'CUS-00917';
UPDATE customers 
SET 
  latitude = 30.792475,
  longitude = 31.01237,
  location_accuracy = 19.6,
  address = COALESCE(address, 'حسن رضوان'),
  location_updated_at = now()
WHERE code = 'CUS-00959';
UPDATE customers 
SET 
  latitude = 30.780302,
  longitude = 31.011772,
  location_accuracy = 14.9,
  address = COALESCE(address, 'شارع الجلاء امام شركه مطاحن وسط الدلتا'),
  location_updated_at = now()
WHERE code = 'CUS-01555';
UPDATE customers 
SET 
  latitude = 30.798815,
  longitude = 31.009342,
  location_accuracy = 13.1,
  address = COALESCE(address, 'الكورنيش - بجوار قهوة اكسبريسو-عند المرشحة'),
  location_updated_at = now()
WHERE code = 'CUS-00075';
UPDATE customers 
SET 
  latitude = 30.809118,
  longitude = 30.99766,
  location_accuracy = 16.1,
  address = COALESCE(address, 'طنطا خلف مدرسه الزراعه اللى ع السريع'),
  location_updated_at = now()
WHERE code = 'CUS-01414';
UPDATE customers 
SET 
  latitude = 31.406006,
  longitude = 31.810457,
  location_accuracy = 53.45,
  address = COALESCE(address, 'دمياط القديمة'),
  location_updated_at = now()
WHERE code = 'CUS-00606';
UPDATE customers 
SET 
  latitude = 31.127623,
  longitude = 30.124022,
  location_accuracy = 23.9,
  address = COALESCE(address, 'مدخل العمدة خلف مسجد الفتح عند دوران شركة البرتقال'),
  location_updated_at = now()
WHERE code = 'CUS-00275';
UPDATE customers 
SET 
  latitude = 30.794498,
  longitude = 31.005264,
  location_accuracy = 2.7,
  address = COALESCE(address, 'توت عنخ امون مع السلطان مراد'),
  location_updated_at = now()
WHERE code = 'CUS-01270';
UPDATE customers 
SET 
  latitude = 30.67543,
  longitude = 30.940233,
  location_accuracy = 40.0,
  address = COALESCE(address, 'تلا البوسته القديمه'),
  location_updated_at = now()
WHERE code = 'CUS-01533';
UPDATE customers 
SET 
  latitude = 30.809523,
  longitude = 30.993713,
  location_accuracy = 24.7,
  address = COALESCE(address, 'الاستاد بعد مستشفي ام القري يمين'),
  location_updated_at = now()
WHERE code = 'CUS-01149';
UPDATE customers 
SET 
  latitude = 30.803654,
  longitude = 30.994446,
  location_accuracy = 29.524,
  address = COALESCE(address, 'طنطا السريع بجانب بنزينة اندريد'),
  location_updated_at = now()
WHERE code = 'CUS-00645';
UPDATE customers 
SET 
  latitude = 30.970068,
  longitude = 30.807854,
  location_accuracy = 82.5,
  address = COALESCE(address, 'شارع 23 يوليو'),
  location_updated_at = now()
WHERE code = 'CUS-01286';
UPDATE customers 
SET 
  latitude = 30.879524,
  longitude = 30.870304,
  location_accuracy = 15.0,
  address = COALESCE(address, 'طريق بسيون امام مدخل كتامة'),
  location_updated_at = now()
WHERE code = 'CUS-00910';
UPDATE customers 
SET 
  latitude = 30.582369,
  longitude = 31.492321,
  location_accuracy = 18.7,
  address = COALESCE(address, 'حي الزهور'),
  location_updated_at = now()
WHERE code = 'CUS-00227';
UPDATE customers 
SET 
  latitude = 30.800287,
  longitude = 31.008448,
  location_accuracy = 22.1,
  address = COALESCE(address, 'شارع الامام مسلم تقاطع شارع احمد المصرى خلف المنشاوى'),
  location_updated_at = now()
WHERE code = 'CUS-01299';
UPDATE customers 
SET 
  latitude = 30.97983,
  longitude = 31.166058,
  location_accuracy = 13.78,
  address = COALESCE(address, 'بجوار مغسله eco clean'),
  location_updated_at = now()
WHERE code = 'CUS-01629';
UPDATE customers 
SET 
  latitude = 30.800611,
  longitude = 31.006437,
  location_accuracy = 15.25,
  address = COALESCE(address, 'القاذفى مع السلطان مراد'),
  location_updated_at = now()
WHERE code = 'CUS-01605';
UPDATE customers 
SET 
  latitude = 30.790985,
  longitude = 30.96981,
  location_accuracy = 55.0,
  address = COALESCE(address, 'طنطا طريق محلة مرحوم'),
  location_updated_at = now()
WHERE code = 'CUS-00629';
UPDATE customers 
SET 
  latitude = 30.786896,
  longitude = 31.001404,
  location_accuracy = 5.4,
  address = COALESCE(address, 'طنطا اول شارع سعيد من شارع الجلاء'),
  location_updated_at = now()
WHERE code = 'CUS-01224';
UPDATE customers 
SET 
  latitude = 30.808651,
  longitude = 30.999912,
  location_accuracy = 15.305,
  address = COALESCE(address, 'المعرض (السريع)'),
  location_updated_at = now()
WHERE code = 'CUS-00321';
UPDATE customers 
SET 
  latitude = 30.571806,
  longitude = 31.008055,
  location_accuracy = 14.946,
  address = COALESCE(address, 'ش قاعده رجاله من اول ش باريس'),
  location_updated_at = now()
WHERE code = 'CUS-01198';
UPDATE customers 
SET 
  latitude = 30.566282,
  longitude = 31.008204,
  location_accuracy = 25.1,
  address = COALESCE(address, 'شارع الجلاء امام مسجد المغفرة'),
  location_updated_at = now()
WHERE code = 'CUS-01279';
UPDATE customers 
SET 
  latitude = 30.955608,
  longitude = 31.168352,
  location_accuracy = 17.4,
  address = COALESCE(address, 'طريق زفتي قبل نادي الشرطه'),
  location_updated_at = now()
WHERE code = 'CUS-01501';
UPDATE customers 
SET 
  latitude = 30.971558,
  longitude = 31.218285,
  location_accuracy = 110.0,
  address = COALESCE(address, 'الراهبين'),
  location_updated_at = now()
WHERE code = 'CUS-00770';
UPDATE customers 
SET 
  latitude = 31.149702,
  longitude = 30.127937,
  location_accuracy = 22.705,
  address = COALESCE(address, 'كفر الدوار'),
  location_updated_at = now()
WHERE code = 'CUS-00484';
UPDATE customers 
SET 
  latitude = 30.789616,
  longitude = 31.015385,
  location_accuracy = 24.65,
  address = COALESCE(address, 'كورنيش بعد مزلقان الجميل بجوار الدقن للزيوت'),
  location_updated_at = now()
WHERE code = 'CUS-01616';
UPDATE customers 
SET 
  latitude = 31.025558,
  longitude = 30.46086,
  location_accuracy = 16.019,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00386';
UPDATE customers 
SET 
  latitude = 30.792318,
  longitude = 31.014793,
  location_accuracy = 31.088,
  address = COALESCE(address, 'طنطا طريق المحلة خلف المزلقان'),
  location_updated_at = now()
WHERE code = 'CUS-00993';
UPDATE customers 
SET 
  latitude = 30.889334,
  longitude = 30.670324,
  location_accuracy = 65.0,
  address = COALESCE(address, 'ايتاي البارود امام مركز القلب'),
  location_updated_at = now()
WHERE code = 'CUS-01553';
UPDATE customers 
SET 
  latitude = 31.02978,
  longitude = 30.463806,
  location_accuracy = 18.2,
  address = COALESCE(address, 'دمنهور _شارع الروضة_معهد القراأت'),
  location_updated_at = now()
WHERE code = 'CUS-01276';
UPDATE customers 
SET 
  latitude = 30.794405,
  longitude = 30.983112,
  location_accuracy = 15.8,
  address = COALESCE(address, 'طنطا بجوار غيث'),
  location_updated_at = now()
WHERE code = 'CUS-00909';
UPDATE customers 
SET 
  latitude = 30.889034,
  longitude = 30.670105,
  location_accuracy = 15.7,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01401';
UPDATE customers 
SET 
  latitude = 30.920378,
  longitude = 30.66723,
  location_accuracy = 77.942,
  address = COALESCE(address, 'كوبري النقطه الثابته طريق شبرا خيت'),
  location_updated_at = now()
WHERE code = 'CUS-01596';
UPDATE customers 
SET 
  latitude = 30.889326,
  longitude = 30.665321,
  location_accuracy = 100.0,
  address = COALESCE(address, 'ايتاي البارود اول ش الحضانة امام مستودع الغاز'),
  location_updated_at = now()
WHERE code = 'CUS-01108';
UPDATE customers 
SET 
  latitude = 30.90746,
  longitude = 30.666334,
  location_accuracy = 11.4,
  address = COALESCE(address, 'اول طريق شبرا خيت بعد مغسله ابو ياسين'),
  location_updated_at = now()
WHERE code = 'CUS-01575';
UPDATE customers 
SET 
  latitude = 30.894073,
  longitude = 30.667841,
  location_accuracy = 11.5,
  address = COALESCE(address, 'شارع الحضانه اول طريق شبراخيت'),
  location_updated_at = now()
WHERE code = 'CUS-01193';
UPDATE customers 
SET 
  latitude = 30.7985,
  longitude = 30.992613,
  location_accuracy = 27.872,
  address = COALESCE(address, 'نجف الجامعة -طنطا'),
  location_updated_at = now()
WHERE code = 'CUS-01152';
UPDATE customers 
SET 
  latitude = 30.800648,
  longitude = 31.007952,
  location_accuracy = 23.15,
  address = COALESCE(address, 'كورنيش المرشحه بعد ماركت المنشاوى'),
  location_updated_at = now()
WHERE code = 'CUS-01628';
UPDATE customers 
SET 
  latitude = 30.77406,
  longitude = 31.018341,
  location_accuracy = 26.635,
  address = COALESCE(address, 'اخر ش الجلاء'),
  location_updated_at = now()
WHERE code = 'CUS-01200';
UPDATE customers 
SET 
  latitude = 30.798128,
  longitude = 31.00624,
  location_accuracy = 13.871,
  address = COALESCE(address, 'شارع الاشرف'),
  location_updated_at = now()
WHERE code = 'CUS-00702';
UPDATE customers 
SET 
  latitude = 30.78994,
  longitude = 30.980818,
  location_accuracy = 13.6,
  address = COALESCE(address, 'اخر المعاهدة'),
  location_updated_at = now()
WHERE code = 'CUS-00056';
UPDATE customers 
SET 
  latitude = 30.845156,
  longitude = 31.230225,
  location_accuracy = 28.5,
  address = COALESCE(address, 'ميت بدر حلاوة'),
  location_updated_at = now()
WHERE code = 'CUS-01122';
UPDATE customers 
SET 
  latitude = 30.788792,
  longitude = 30.97715,
  location_accuracy = 14.57,
  address = COALESCE(address, 'اخر المعاهده مع طريق ميدان اسكندريه'),
  location_updated_at = now()
WHERE code = 'CUS-01636';
UPDATE customers 
SET 
  latitude = 31.15167,
  longitude = 30.12402,
  location_accuracy = 18.342,
  address = COALESCE(address, 'مساكن التمليك'),
  location_updated_at = now()
WHERE code = 'CUS-01232';
UPDATE customers 
SET 
  latitude = 30.979778,
  longitude = 31.165947,
  location_accuracy = 3.02,
  address = COALESCE(address, 'ميدان بسيسه'),
  location_updated_at = now()
WHERE code = 'CUS-01613';
UPDATE customers 
SET 
  latitude = 30.806952,
  longitude = 30.989288,
  location_accuracy = 18.224,
  address = COALESCE(address, 'طريق سكة شوبر منطقة الورش'),
  location_updated_at = now()
WHERE code = 'CUS-01147';
UPDATE customers 
SET 
  latitude = 30.671465,
  longitude = 30.938953,
  location_accuracy = 29.907,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01064';
UPDATE customers 
SET 
  latitude = 30.981922,
  longitude = 31.179115,
  location_accuracy = 25.832,
  address = COALESCE(address, 'ش سعد محمد سعد امام كوافير المتحجبة'),
  location_updated_at = now()
WHERE code = 'CUS-00030';
UPDATE customers 
SET 
  latitude = 31.041708,
  longitude = 30.476057,
  location_accuracy = 32.005,
  address = COALESCE(address, 'دمنهور ابراج ش الجيش'),
  location_updated_at = now()
WHERE code = 'CUS-01304';
UPDATE customers 
SET 
  latitude = 30.783613,
  longitude = 30.988628,
  location_accuracy = 16.17,
  address = COALESCE(address, 'التجنيد - امام بنك الدم'),
  location_updated_at = now()
WHERE code = 'CUS-00070';
UPDATE customers 
SET 
  latitude = 30.79255,
  longitude = 30.980577,
  location_accuracy = 14.1,
  address = COALESCE(address, 'المعاهده عند سوق الجملة'),
  location_updated_at = now()
WHERE code = 'CUS-00064';
UPDATE customers 
SET 
  latitude = 31.42459,
  longitude = 31.80025,
  location_accuracy = 17.0,
  address = COALESCE(address, 'دمياط القديمه السنانيه بجوار موقف راس البر بجوار النجيري لغيار السيارات'),
  location_updated_at = now()
WHERE code = 'CUS-01464';
UPDATE customers 
SET 
  latitude = 30.792627,
  longitude = 31.010084,
  location_accuracy = 13.73,
  address = COALESCE(address, 'محمد فريد'),
  location_updated_at = now()
WHERE code = 'CUS-01587';
UPDATE customers 
SET 
  latitude = 30.982811,
  longitude = 31.173395,
  location_accuracy = 30.253,
  address = COALESCE(address, 'امتداد شكر الكواتلى'),
  location_updated_at = now()
WHERE code = 'CUS-00376';
UPDATE customers 
SET 
  latitude = 30.793968,
  longitude = 31.013187,
  location_accuracy = 23.73,
  address = COALESCE(address, 'كورنيش المرشحه بجوار مسجد السلام'),
  location_updated_at = now()
WHERE code = 'CUS-01655';
UPDATE customers 
SET 
  latitude = 30.777477,
  longitude = 31.018631,
  location_accuracy = 40.833,
  address = COALESCE(address, 'كورنيش كوبرى فاروق بجوار البورسعيدى'),
  location_updated_at = now()
WHERE code = 'CUS-00363';
UPDATE customers 
SET 
  latitude = 30.80183,
  longitude = 31.006922,
  location_accuracy = 22.1,
  address = COALESCE(address, 'كورنيش المرشحه بجوار ماركت المنشاوى'),
  location_updated_at = now()
WHERE code = 'CUS-01608';
UPDATE customers 
SET 
  latitude = 30.793997,
  longitude = 30.956488,
  location_accuracy = 30.996,
  address = COALESCE(address, 'محلة مرحوم  كفر العرب'),
  location_updated_at = now()
WHERE code = 'CUS-01127';
UPDATE customers 
SET 
  latitude = 30.798014,
  longitude = 30.986792,
  location_accuracy = 33.587,
  address = COALESCE(address, 'الطريق السريع'),
  location_updated_at = now()
WHERE code = 'CUS-00867';
UPDATE customers 
SET 
  latitude = 31.136364,
  longitude = 30.135101,
  location_accuracy = 4.3,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01069';
UPDATE customers 
SET 
  latitude = 30.477686,
  longitude = 31.184677,
  location_accuracy = 30.0,
  address = COALESCE(address, 'الفلل'),
  location_updated_at = now()
WHERE code = 'CUS-01297';
UPDATE customers 
SET 
  latitude = 30.474796,
  longitude = 31.18503,
  location_accuracy = 22.71,
  address = COALESCE(address, 'الفلال'),
  location_updated_at = now()
WHERE code = 'CUS-01551';
UPDATE customers 
SET 
  latitude = 30.468111,
  longitude = 31.183628,
  location_accuracy = 12.307,
  address = COALESCE(address, 'بنها ش احمد شعلان'),
  location_updated_at = now()
WHERE code = 'CUS-01214';
UPDATE customers 
SET 
  latitude = 30.548546,
  longitude = 31.01697,
  location_accuracy = 28.1,
  address = COALESCE(address, 'ناجى عمر متفرع من شارع جراج الاتوبيس'),
  location_updated_at = now()
WHERE code = 'CUS-01642';
UPDATE customers 
SET 
  latitude = 30.574448,
  longitude = 31.013258,
  location_accuracy = 17.349,
  address = COALESCE(address, 'شبين ش معهد الكبد'),
  location_updated_at = now()
WHERE code = 'CUS-01030';
UPDATE customers 
SET 
  latitude = 30.685015,
  longitude = 30.946606,
  location_accuracy = 5.8,
  address = COALESCE(address, 'تلا بعد مزلقان تلا يمين'),
  location_updated_at = now()
WHERE code = 'CUS-01577';
UPDATE customers 
SET 
  latitude = 30.98151,
  longitude = 31.176981,
  location_accuracy = 21.1,
  address = COALESCE(address, 'ش عبدالرحمن شاهين'),
  location_updated_at = now()
WHERE code = 'CUS-01239';
UPDATE customers 
SET 
  latitude = 30.715229,
  longitude = 31.237839,
  location_accuracy = 16.85,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00139';
UPDATE customers 
SET 
  latitude = 30.790571,
  longitude = 30.982761,
  location_accuracy = 21.255,
  address = COALESCE(address, 'ش مصطفى كامل مع ابن الفارض'),
  location_updated_at = now()
WHERE code = 'CUS-00109';
UPDATE customers 
SET 
  latitude = 31.030653,
  longitude = 30.457855,
  location_accuracy = 21.222,
  address = COALESCE(address, 'ش المعهد الديني امام معرض الحوفي للسيارات'),
  location_updated_at = now()
WHERE code = 'CUS-00166';
UPDATE customers 
SET 
  latitude = 30.59225,
  longitude = 31.499617,
  location_accuracy = 21.0,
  address = COALESCE(address, 'ش جمال عبد الناصر'),
  location_updated_at = now()
WHERE code = 'CUS-01539';
UPDATE customers 
SET 
  latitude = 31.033047,
  longitude = 31.354328,
  location_accuracy = 20.7,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00191';
UPDATE customers 
SET 
  latitude = 31.05464,
  longitude = 31.41086,
  location_accuracy = 11.8,
  address = COALESCE(address, 'كوبري جديله'),
  location_updated_at = now()
WHERE code = 'CUS-01593';
UPDATE customers 
SET 
  latitude = 30.984476,
  longitude = 31.188606,
  location_accuracy = 10.72,
  address = COALESCE(address, 'سمنود'),
  location_updated_at = now()
WHERE code = 'CUS-01038';
UPDATE customers 
SET 
  latitude = 30.796593,
  longitude = 31.011086,
  location_accuracy = 9.6,
  address = COALESCE(address, 'اول شارع محمد فريد من الكورنيش'),
  location_updated_at = now()
WHERE code = 'CUS-01250';
UPDATE customers 
SET 
  latitude = 30.808867,
  longitude = 31.000032,
  location_accuracy = 35.0,
  address = COALESCE(address, 'شارع البندارى'),
  location_updated_at = now()
WHERE code = 'CUS-01564';
UPDATE customers 
SET 
  latitude = 30.787247,
  longitude = 30.984781,
  location_accuracy = 19.35,
  address = COALESCE(address, 'ميدان اسكندرية بجوار السجن'),
  location_updated_at = now()
WHERE code = 'CUS-01646';
UPDATE customers 
SET 
  latitude = 30.789402,
  longitude = 30.989048,
  location_accuracy = 7.504,
  address = COALESCE(address, 'على مبارك قبل ابو دشيش'),
  location_updated_at = now()
WHERE code = 'CUS-00062';
UPDATE customers 
SET 
  latitude = 30.734083,
  longitude = 31.028982,
  location_accuracy = 30.0,
  address = COALESCE(address, 'امام كوبري الملاحات قبل نفيا من عالسريع اتجاه طنطا'),
  location_updated_at = now()
WHERE code = 'CUS-01264';
UPDATE customers 
SET 
  latitude = 30.787088,
  longitude = 30.987846,
  location_accuracy = 16.002,
  address = COALESCE(address, 'طنطا اخر النحاس'),
  location_updated_at = now()
WHERE code = 'CUS-01290';
UPDATE customers 
SET 
  latitude = 30.804474,
  longitude = 31.003483,
  location_accuracy = 35.0,
  address = COALESCE(address, 'اخر سعيد بجوار شركه المياه'),
  location_updated_at = now()
WHERE code = 'CUS-01559';
UPDATE customers 
SET 
  latitude = 30.792408,
  longitude = 30.985138,
  location_accuracy = 18.839,
  address = COALESCE(address, 'شارع الفاتح'),
  location_updated_at = now()
WHERE code = 'CUS-00928';
UPDATE customers 
SET 
  latitude = 30.57444,
  longitude = 31.49786,
  location_accuracy = 21.86,
  address = COALESCE(address, 'الزقازيق شارع الشهيد طيار داخل ملعب السيتي'),
  location_updated_at = now()
WHERE code = 'CUS-01545';
UPDATE customers 
SET 
  latitude = 30.811714,
  longitude = 31.00412,
  location_accuracy = 36.818,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01068';
UPDATE customers 
SET 
  latitude = 30.463165,
  longitude = 31.178673,
  location_accuracy = 14.736,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00855';
UPDATE customers 
SET 
  latitude = 30.81874,
  longitude = 30.834639,
  location_accuracy = 39.6,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01041';
UPDATE customers 
SET 
  latitude = 30.796576,
  longitude = 31.010902,
  location_accuracy = 40.0,
  address = COALESCE(address, 'اخر محمد فريد مع المرشحه'),
  location_updated_at = now()
WHERE code = 'CUS-01550';
UPDATE customers 
SET 
  latitude = 30.808367,
  longitude = 31.001734,
  location_accuracy = 46.032,
  address = COALESCE(address, 'الكورنيش- عند كوبري قحافة'),
  location_updated_at = now()
WHERE code = 'CUS-00308';
UPDATE customers 
SET 
  latitude = 30.025993,
  longitude = 31.488283,
  location_accuracy = 36.9,
  address = COALESCE(address, 'شارع 90 امام الجامعه الامريكية'),
  location_updated_at = now()
WHERE code = 'CUS-00718';
UPDATE customers 
SET 
  latitude = 30.588306,
  longitude = 31.496944,
  location_accuracy = 16.5,
  address = COALESCE(address, 'ش سالم الصباح خلف البنداري الاحذية منطقة القومية'),
  location_updated_at = now()
WHERE code = 'CUS-00602';
UPDATE customers 
SET 
  latitude = 30.807415,
  longitude = 30.99891,
  location_accuracy = 15.075,
  address = COALESCE(address, 'طريق السريع امام الشافعي'),
  location_updated_at = now()
WHERE code = 'CUS-00719';
UPDATE customers 
SET 
  latitude = 30.583912,
  longitude = 31.529152,
  location_accuracy = 3.2,
  address = COALESCE(address, 'الزراعه قاعه الفيروز'),
  location_updated_at = now()
WHERE code = 'CUS-00229';
UPDATE customers 
SET 
  latitude = 30.58688,
  longitude = 31.495682,
  location_accuracy = 22.808,
  address = COALESCE(address, 'عند حديقه الحيوان'),
  location_updated_at = now()
WHERE code = 'CUS-01654';
UPDATE customers 
SET 
  latitude = 30.788956,
  longitude = 30.976574,
  location_accuracy = 29.872,
  address = COALESCE(address, 'اخر شارع المعاهده'),
  location_updated_at = now()
WHERE code = 'CUS-01653';
UPDATE customers 
SET 
  latitude = 30.890263,
  longitude = 30.661299,
  location_accuracy = 18.5,
  address = COALESCE(address, 'ايتاي نزله الكوبري العلوي'),
  location_updated_at = now()
WHERE code = 'CUS-01418';
UPDATE customers 
SET 
  latitude = 31.046965,
  longitude = 30.460262,
  location_accuracy = 18.8,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00173';
UPDATE customers 
SET 
  latitude = 30.809921,
  longitude = 30.999067,
  location_accuracy = 7.3,
  address = COALESCE(address, 'شارع الحياه الاستاد'),
  location_updated_at = now()
WHERE code = 'CUS-01530';
UPDATE customers 
SET 
  latitude = 30.472652,
  longitude = 31.185644,
  location_accuracy = 18.419,
  address = COALESCE(address, 'ش الآثار 1'),
  location_updated_at = now()
WHERE code = 'CUS-00202';
UPDATE customers 
SET 
  latitude = 30.4676,
  longitude = 31.181734,
  location_accuracy = 16.92,
  address = COALESCE(address, 'بنها شارع الشبان المسلمين بجوار مدرسه الشبان المسلمين'),
  location_updated_at = now()
WHERE code = 'CUS-01557';
UPDATE customers 
SET 
  latitude = 30.965187,
  longitude = 31.16782,
  location_accuracy = 8.33,
  address = COALESCE(address, 'السبع بنات امام مدرسه الفرير'),
  location_updated_at = now()
WHERE code = 'CUS-01619';
UPDATE customers 
SET 
  latitude = 30.981958,
  longitude = 31.18017,
  location_accuracy = 39.62,
  address = COALESCE(address, 'بعد الجراج قبل مسجد الشامي'),
  location_updated_at = now()
WHERE code = 'CUS-01615';
UPDATE customers 
SET 
  latitude = 30.805841,
  longitude = 31.009937,
  location_accuracy = 6.6,
  address = COALESCE(address, 'عند تورب قحافه عند الورش'),
  location_updated_at = now()
WHERE code = 'CUS-01652';
UPDATE customers 
SET 
  latitude = 30.793776,
  longitude = 30.988075,
  location_accuracy = 21.3,
  address = COALESCE(address, 'شارع انور بجانب سوق الجملة'),
  location_updated_at = now()
WHERE code = 'CUS-01268';
UPDATE customers 
SET 
  latitude = 31.048717,
  longitude = 30.461494,
  location_accuracy = 18.818,
  address = COALESCE(address, 'ش الزهور بجوار الثانوية العسكررية مركز رحال للعظام'),
  location_updated_at = now()
WHERE code = 'CUS-00172';
UPDATE customers 
SET 
  latitude = 31.034409,
  longitude = 30.46008,
  location_accuracy = 10.42,
  address = COALESCE(address, 'دوران الاستاد بجوار صبحي البلكي'),
  location_updated_at = now()
WHERE code = 'CUS-01614';
UPDATE customers 
SET 
  latitude = 30.793032,
  longitude = 31.01242,
  location_accuracy = 25.794,
  address = COALESCE(address, 'اخر حسن رضوان يجوار الصفا'),
  location_updated_at = now()
WHERE code = 'CUS-01651';
UPDATE customers 
SET 
  latitude = 31.026897,
  longitude = 31.373985,
  location_accuracy = 23.087,
  address = COALESCE(address, 'المنصورة ش المطافي'),
  location_updated_at = now()
WHERE code = 'CUS-01130';
UPDATE customers 
SET 
  latitude = 31.027378,
  longitude = 31.364292,
  location_accuracy = 5.6,
  address = COALESCE(address, 'مساكن العبور'),
  location_updated_at = now()
WHERE code = 'CUS-01592';
UPDATE customers 
SET 
  latitude = 30.789253,
  longitude = 30.98755,
  location_accuracy = 5.36,
  address = COALESCE(address, 'طنطا ..شارع ابن مالك'),
  location_updated_at = now()
WHERE code = 'CUS-00516';
UPDATE customers 
SET 
  latitude = 30.78978,
  longitude = 30.982851,
  location_accuracy = 41.024,
  address = COALESCE(address, 'ابن الفارض'),
  location_updated_at = now()
WHERE code = 'CUS-00725';
UPDATE customers 
SET 
  latitude = 30.568832,
  longitude = 31.003157,
  location_accuracy = 40.0,
  address = COALESCE(address, 'شبين'),
  location_updated_at = now()
WHERE code = 'CUS-01529';
UPDATE customers 
SET 
  latitude = 30.787304,
  longitude = 30.987762,
  location_accuracy = 11.63,
  address = COALESCE(address, 'اخر النحاس أمام اسلام كار'),
  location_updated_at = now()
WHERE code = 'CUS-01582';
UPDATE customers 
SET 
  latitude = 30.816698,
  longitude = 30.993252,
  location_accuracy = 92.9,
  address = COALESCE(address, 'الاستاد امام الصردي للحلويات'),
  location_updated_at = now()
WHERE code = 'CUS-01043';
UPDATE customers 
SET 
  latitude = 30.800512,
  longitude = 30.990576,
  location_accuracy = 12.6,
  address = COALESCE(address, 'كفر عصام امام الجامعة'),
  location_updated_at = now()
WHERE code = 'CUS-01137';
UPDATE customers 
SET 
  latitude = 30.797152,
  longitude = 30.989233,
  location_accuracy = 22.4,
  address = COALESCE(address, 'ش النادي خلف مدرسة ام المؤمنين'),
  location_updated_at = now()
WHERE code = 'CUS-01079';
UPDATE customers 
SET 
  latitude = 30.809155,
  longitude = 30.999388,
  location_accuracy = 52.862,
  address = COALESCE(address, 'امام سبوت ٨'),
  location_updated_at = now()
WHERE code = 'CUS-01424';
UPDATE customers 
SET 
  latitude = 30.793318,
  longitude = 31.009634,
  location_accuracy = 8.6,
  address = COALESCE(address, 'شارع بطرس مع محمد فريد امام حورس للتكيفيات'),
  location_updated_at = now()
WHERE code = 'CUS-01293';
UPDATE customers 
SET 
  latitude = 31.041374,
  longitude = 31.400425,
  location_accuracy = 16.35,
  address = COALESCE(address, 'عزبة الشال امام الاستاد'),
  location_updated_at = now()
WHERE code = 'CUS-01094';
UPDATE customers 
SET 
  latitude = 31.111677,
  longitude = 30.951754,
  location_accuracy = 4.272,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00122';
UPDATE customers 
SET 
  latitude = 30.792826,
  longitude = 30.988943,
  location_accuracy = 10.362,
  address = COALESCE(address, 'ش الفاتح امام بنك مصر'),
  location_updated_at = now()
WHERE code = 'CUS-00984';
UPDATE customers 
SET 
  latitude = 30.589228,
  longitude = 31.496092,
  location_accuracy = 15.2,
  address = COALESCE(address, 'القومية خلف مستشفي السلام'),
  location_updated_at = now()
WHERE code = 'CUS-00551';
UPDATE customers 
SET 
  latitude = 31.05232,
  longitude = 31.397451,
  location_accuracy = 22.8,
  address = COALESCE(address, 'المنصوره جديله'),
  location_updated_at = now()
WHERE code = 'CUS-01372';
UPDATE customers 
SET 
  latitude = 30.97223,
  longitude = 31.183502,
  location_accuracy = 21.253,
  address = COALESCE(address, 'ش شركة الزيت و الصابون امتداد لادولشي فيتا اتجاه الرجبي'),
  location_updated_at = now()
WHERE code = 'CUS-00026';
UPDATE customers 
SET 
  latitude = 30.791529,
  longitude = 31.004072,
  location_accuracy = 21.24,
  address = COALESCE(address, 'طنطا شارع حسن رضوان مع الحلو'),
  location_updated_at = now()
WHERE code = 'CUS-00800';
UPDATE customers 
SET 
  latitude = 30.890177,
  longitude = 30.667213,
  location_accuracy = 19.43,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01573';
UPDATE customers 
SET 
  latitude = 30.807585,
  longitude = 30.99595,
  location_accuracy = 23.0,
  address = COALESCE(address, 'بجوار جيفال'),
  location_updated_at = now()
WHERE code = 'CUS-01148';
UPDATE customers 
SET 
  latitude = 30.79398,
  longitude = 31.012894,
  location_accuracy = 28.879,
  address = COALESCE(address, 'طنطا السريع طريق كارليتو'),
  location_updated_at = now()
WHERE code = 'CUS-00913';
UPDATE customers 
SET 
  latitude = 30.751219,
  longitude = 30.6891,
  location_accuracy = 45.6,
  address = COALESCE(address, 'كوم حمادة شارع مدرسة الصنايع'),
  location_updated_at = now()
WHERE code = 'CUS-00587';
UPDATE customers 
SET 
  latitude = 30.474941,
  longitude = 31.184998,
  location_accuracy = 22.4,
  address = COALESCE(address, 'شارع الزهور'),
  location_updated_at = now()
WHERE code = 'CUS-01398';
UPDATE customers 
SET 
  latitude = 30.982857,
  longitude = 31.179035,
  location_accuracy = 11.61,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01598';
UPDATE customers 
SET 
  latitude = 30.593443,
  longitude = 31.499832,
  location_accuracy = 18.2,
  address = COALESCE(address, 'شارع الموقف مفارق المنصورة ش كافيه الحسينى'),
  location_updated_at = now()
WHERE code = 'CUS-00347';
UPDATE customers 
SET 
  latitude = 30.795706,
  longitude = 31.0108,
  location_accuracy = 13.29,
  address = COALESCE(address, 'اخر محمد فريد من نحيت الكورنيش'),
  location_updated_at = now()
WHERE code = 'CUS-01648';
UPDATE customers 
SET 
  latitude = 31.130287,
  longitude = 30.13516,
  location_accuracy = 31.183,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00756';
UPDATE customers 
SET 
  latitude = 30.882536,
  longitude = 30.656536,
  location_accuracy = 7.24,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00965';
UPDATE customers 
SET 
  latitude = 30.808294,
  longitude = 30.99235,
  location_accuracy = 15.9,
  address = COALESCE(address, 'طنطا الاستاد طريق شوبر'),
  location_updated_at = now()
WHERE code = 'CUS-01441';
UPDATE customers 
SET 
  latitude = 30.524286,
  longitude = 31.360447,
  location_accuracy = 68.4,
  address = COALESCE(address, 'منيا القمح منطقة الخرس'),
  location_updated_at = now()
WHERE code = 'CUS-00797';
UPDATE customers 
SET 
  latitude = 30.572844,
  longitude = 31.484674,
  location_accuracy = 64.1,
  address = COALESCE(address, 'الاحرار امام المطاحن بنزين علا الشهيد'),
  location_updated_at = now()
WHERE code = 'CUS-01637';
UPDATE customers 
SET 
  latitude = 30.58701,
  longitude = 31.49539,
  location_accuracy = 18.1,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01649';
UPDATE customers 
SET 
  latitude = 30.97451,
  longitude = 31.170965,
  location_accuracy = 11.0,
  address = COALESCE(address, 'ش غنام امام شارع شكري القوتلي امام مدرسة السيدة عائشه'),
  location_updated_at = now()
WHERE code = 'CUS-00042';
UPDATE customers 
SET 
  latitude = 30.803696,
  longitude = 31.005566,
  location_accuracy = 49.71,
  address = COALESCE(address, 'كورنيش قحافه اخر سعيد'),
  location_updated_at = now()
WHERE code = 'CUS-01633';
UPDATE customers 
SET 
  latitude = 30.889528,
  longitude = 30.665758,
  location_accuracy = 16.7,
  address = COALESCE(address, 'ايتاي أمام مدرسه ايتاي'),
  location_updated_at = now()
WHERE code = 'CUS-01581';
UPDATE customers 
SET 
  latitude = 31.13828,
  longitude = 30.131853,
  location_accuracy = 22.3,
  address = COALESCE(address, 'امام المحكمه ش المحكمة'),
  location_updated_at = now()
WHERE code = 'CUS-00278';
UPDATE customers 
SET 
  latitude = 31.040466,
  longitude = 30.477476,
  location_accuracy = 33.771,
  address = COALESCE(address, 'مديرية الامن الجديدة ش الجيش امام مدرسة معاذ'),
  location_updated_at = now()
WHERE code = 'CUS-00167';
UPDATE customers 
SET 
  latitude = 30.45168,
  longitude = 31.189795,
  location_accuracy = 12.7,
  address = COALESCE(address, 'بنها منشيه النور'),
  location_updated_at = now()
WHERE code = 'CUS-01409';
UPDATE customers 
SET 
  latitude = 31.02947,
  longitude = 31.371119,
  location_accuracy = 14.2,
  address = COALESCE(address, 'المنصوره بجوار النساجون الشرقيون'),
  location_updated_at = now()
WHERE code = 'CUS-01416';
UPDATE customers 
SET 
  latitude = 30.991077,
  longitude = 31.170355,
  location_accuracy = 6.8,
  address = COALESCE(address, 'دائري المحله'),
  location_updated_at = now()
WHERE code = 'CUS-01594';
UPDATE customers 
SET 
  latitude = 30.60357,
  longitude = 31.534473,
  location_accuracy = 29.57,
  address = COALESCE(address, 'طريق هرية الجديد'),
  location_updated_at = now()
WHERE code = 'CUS-01609';
UPDATE customers 
SET 
  latitude = 30.594828,
  longitude = 31.499754,
  location_accuracy = 14.71,
  address = COALESCE(address, 'مفارق المنصوره عند اليت جيم'),
  location_updated_at = now()
WHERE code = 'CUS-01640';
UPDATE customers 
SET 
  latitude = 30.778116,
  longitude = 31.006235,
  location_accuracy = 23.3,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01376';
UPDATE customers 
SET 
  latitude = 30.78063,
  longitude = 30.999039,
  location_accuracy = 10.51,
  address = COALESCE(address, 'الصاغه'),
  location_updated_at = now()
WHERE code = 'CUS-01638';
UPDATE customers 
SET 
  latitude = 30.811804,
  longitude = 31.003937,
  location_accuracy = 45.1,
  address = COALESCE(address, 'اول سبرباي'),
  location_updated_at = now()
WHERE code = 'CUS-01265';
UPDATE customers 
SET 
  latitude = 31.039333,
  longitude = 31.364328,
  location_accuracy = 40.0,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00201';
UPDATE customers 
SET 
  latitude = 31.130125,
  longitude = 30.12502,
  location_accuracy = 22.9,
  address = COALESCE(address, 'ش الملاهي بعد فتح الله مدخل كفر الدوار'),
  location_updated_at = now()
WHERE code = 'CUS-00779';
UPDATE customers 
SET 
  latitude = 30.794907,
  longitude = 31.006021,
  location_accuracy = 13.49,
  address = COALESCE(address, 'الفالوجا مع امرئ القيس'),
  location_updated_at = now()
WHERE code = 'CUS-01612';
UPDATE customers 
SET 
  latitude = 30.887583,
  longitude = 30.659472,
  location_accuracy = 42.399,
  address = COALESCE(address, 'ايتاي البارود تحت الكوبري'),
  location_updated_at = now()
WHERE code = 'CUS-01549';
UPDATE customers 
SET 
  latitude = 30.793177,
  longitude = 30.95555,
  location_accuracy = 17.491,
  address = COALESCE(address, 'طنطا اول كفر العرب'),
  location_updated_at = now()
WHERE code = 'CUS-00999';
UPDATE customers 
SET 
  latitude = 30.738558,
  longitude = 31.027874,
  location_accuracy = 24.9,
  address = COALESCE(address, 'لطريق القاهرة  الزراعى _دفرة'),
  location_updated_at = now()
WHERE code = 'CUS-01417';
UPDATE customers 
SET 
  latitude = 31.115135,
  longitude = 30.950401,
  location_accuracy = 12.93,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00309';
UPDATE customers 
SET 
  latitude = 30.468472,
  longitude = 31.190023,
  location_accuracy = 19.404,
  address = COALESCE(address, 'بنها ش كلية الطب'),
  location_updated_at = now()
WHERE code = 'CUS-01025';
UPDATE customers 
SET 
  latitude = 30.799414,
  longitude = 31.010475,
  location_accuracy = 13.2,
  address = COALESCE(address, 'المرشحه خلف مدرسه سمارت'),
  location_updated_at = now()
WHERE code = 'CUS-01237';
UPDATE customers 
SET 
  latitude = 30.725557,
  longitude = 31.123766,
  location_accuracy = 43.939,
  address = COALESCE(address, 'السنطه امام المعهد الديني'),
  location_updated_at = now()
WHERE code = 'CUS-01192';
UPDATE customers 
SET 
  latitude = 31.131535,
  longitude = 30.128122,
  location_accuracy = 21.6,
  address = COALESCE(address, 'خلف موقف دمنهور'),
  location_updated_at = now()
WHERE code = 'CUS-01181';
UPDATE customers 
SET 
  latitude = 30.841118,
  longitude = 31.015005,
  location_accuracy = 3.216,
  address = COALESCE(address, 'مول طنطا سبرباي'),
  location_updated_at = now()
WHERE code = 'CUS-00964';
UPDATE customers 
SET 
  latitude = 31.030935,
  longitude = 30.453423,
  location_accuracy = 21.0,
  address = COALESCE(address, 'دمنهور شارع'),
  location_updated_at = now()
WHERE code = 'CUS-01381';
UPDATE customers 
SET 
  latitude = 30.948666,
  longitude = 31.149796,
  location_accuracy = 45.9,
  address = COALESCE(address, 'ش جمال عبد الناصر'),
  location_updated_at = now()
WHERE code = 'CUS-00982';
UPDATE customers 
SET 
  latitude = 30.957968,
  longitude = 30.95876,
  location_accuracy = 24.8,
  address = COALESCE(address, 'قطور طريق ضماد امام ورشه الشيخ'),
  location_updated_at = now()
WHERE code = 'CUS-01391';
UPDATE customers 
SET 
  latitude = 30.970999,
  longitude = 30.959963,
  location_accuracy = 24.403,
  address = COALESCE(address, 'قطور شارع البنك الاهلي  علي اليمين جانب مسجد الصحابة'),
  location_updated_at = now()
WHERE code = 'CUS-00847';
UPDATE customers 
SET 
  latitude = 30.799301,
  longitude = 31.035658,
  location_accuracy = 14.92,
  address = COALESCE(address, 'اول طريق اخناوى'),
  location_updated_at = now()
WHERE code = 'CUS-01644';
UPDATE customers 
SET 
  latitude = 30.984875,
  longitude = 31.09629,
  location_accuracy = 50.0,
  address = COALESCE(address, 'قريه العامريه مدخلها امام بنزينه مدخل موقف المحله'),
  location_updated_at = now()
WHERE code = 'CUS-01567';
UPDATE customers 
SET 
  latitude = 30.806786,
  longitude = 30.99755,
  location_accuracy = 27.2,
  address = COALESCE(address, 'السريع بجوار المعرض بجوار كشكول'),
  location_updated_at = now()
WHERE code = 'CUS-00088';
UPDATE customers 
SET 
  latitude = 31.046185,
  longitude = 30.461948,
  location_accuracy = 11.5,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00176';
UPDATE customers 
SET 
  latitude = 30.777576,
  longitude = 31.00813,
  location_accuracy = 9.98,
  address = COALESCE(address, 'الجلاء عند الموقف القديم'),
  location_updated_at = now()
WHERE code = 'CUS-01639';
UPDATE customers 
SET 
  latitude = 30.795319,
  longitude = 31.008951,
  location_accuracy = 12.285,
  address = COALESCE(address, 'ش- محمد فريد بجوار هريدي'),
  location_updated_at = now()
WHERE code = 'CUS-00649';
UPDATE customers 
SET 
  latitude = 30.807076,
  longitude = 30.99258,
  location_accuracy = 11.5,
  address = COALESCE(address, 'الاستاد - مدخل شوبر من عند حديقه الطفل'),
  location_updated_at = now()
WHERE code = 'CUS-01283';
UPDATE customers 
SET 
  latitude = 30.445324,
  longitude = 31.194262,
  location_accuracy = 13.42,
  address = COALESCE(address, 'بعد كوبري الشموت'),
  location_updated_at = now()
WHERE code = 'CUS-01584';
UPDATE customers 
SET 
  latitude = 30.837885,
  longitude = 31.014896,
  location_accuracy = 12.1,
  address = COALESCE(address, 'مول طنطا'),
  location_updated_at = now()
WHERE code = 'CUS-01080';
UPDATE customers 
SET 
  latitude = 30.56084,
  longitude = 31.01693,
  location_accuracy = 100.0,
  address = COALESCE(address, 'شبين الكوم بجوار سوق الجمله للخضار'),
  location_updated_at = now()
WHERE code = 'CUS-01218';
UPDATE customers 
SET 
  latitude = 31.436842,
  longitude = 31.531288,
  location_accuracy = 19.4,
  address = COALESCE(address, 'جمصة'),
  location_updated_at = now()
WHERE code = 'CUS-00466';
UPDATE customers 
SET 
  latitude = 30.477644,
  longitude = 31.18272,
  location_accuracy = 13.4,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01521';
UPDATE customers 
SET 
  latitude = 30.441982,
  longitude = 31.18309,
  location_accuracy = 44.18,
  address = COALESCE(address, 'الحرس الوطنى ابو حرير'),
  location_updated_at = now()
WHERE code = 'CUS-01607';
UPDATE customers 
SET 
  latitude = 30.791138,
  longitude = 30.877096,
  location_accuracy = 64.1,
  address = COALESCE(address, 'ديما'),
  location_updated_at = now()
WHERE code = 'CUS-01209';
UPDATE customers 
SET 
  latitude = 31.03694,
  longitude = 30.479338,
  location_accuracy = 4.833,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00852';
UPDATE customers 
SET 
  latitude = 30.96241,
  longitude = 30.958004,
  location_accuracy = 36.9,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00653';
UPDATE customers 
SET 
  latitude = 31.13754,
  longitude = 30.126877,
  location_accuracy = 65.0,
  address = COALESCE(address, 'ش الموقف ورا شل كفر الدوار'),
  location_updated_at = now()
WHERE code = 'CUS-01326';
UPDATE customers 
SET 
  latitude = 31.207832,
  longitude = 29.880285,
  location_accuracy = 19.58,
  address = COALESCE(address, 'الاانفوشي - السيالة بحري'),
  location_updated_at = now()
WHERE code = 'CUS-00441';
UPDATE customers 
SET 
  latitude = 30.807959,
  longitude = 30.824234,
  location_accuracy = 23.962,
  address = COALESCE(address, 'كفر الزيات زراعي القاهرة'),
  location_updated_at = now()
WHERE code = 'CUS-01179';
UPDATE customers 
SET 
  latitude = 30.47774,
  longitude = 31.184208,
  location_accuracy = 20.933,
  address = COALESCE(address, 'ش الترعة بجوار كافيه دهب'),
  location_updated_at = now()
WHERE code = 'CUS-00021';
UPDATE customers 
SET 
  latitude = 30.571787,
  longitude = 31.008074,
  location_accuracy = 13.273,
  address = COALESCE(address, 'شبين ش باريس'),
  location_updated_at = now()
WHERE code = 'CUS-01029';
UPDATE customers 
SET 
  latitude = 31.148714,
  longitude = 30.127972,
  location_accuracy = 12.28,
  address = COALESCE(address, 'التمليك'),
  location_updated_at = now()
WHERE code = 'CUS-01602';
UPDATE customers 
SET 
  latitude = 30.802555,
  longitude = 30.997076,
  location_accuracy = 20.2,
  address = COALESCE(address, 'طنطا شارع البحر بجوار البنك العربي الافريقي'),
  location_updated_at = now()
WHERE code = 'CUS-01630';
UPDATE customers 
SET 
  latitude = 30.794594,
  longitude = 30.982859,
  location_accuracy = 24.49,
  address = COALESCE(address, 'له فرعين الاستاد بجوار بيت المشويات--الطريق السريع امام كريز'),
  location_updated_at = now()
WHERE code = 'CUS-00403';
UPDATE customers 
SET 
  latitude = 30.792095,
  longitude = 30.992582,
  location_accuracy = 22.1,
  address = COALESCE(address, 'شارع ابو بكر الصديق بجوار معرض سيارات الصيرفي'),
  location_updated_at = now()
WHERE code = 'CUS-01215';
UPDATE customers 
SET 
  latitude = 30.809153,
  longitude = 31.002426,
  location_accuracy = 69.011,
  address = COALESCE(address, 'طنطا خلف قاعة المماليك'),
  location_updated_at = now()
WHERE code = 'CUS-01142';
UPDATE customers 
SET 
  latitude = 30.794983,
  longitude = 30.98349,
  location_accuracy = 21.238,
  address = COALESCE(address, 'طنطا الطريق السريع امام غيث اتجاه اسكندرية'),
  location_updated_at = now()
WHERE code = 'CUS-01570';
UPDATE customers 
SET 
  latitude = 30.531483,
  longitude = 31.376535,
  location_accuracy = 11.5,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01448';
UPDATE customers 
SET 
  latitude = 30.810297,
  longitude = 30.999746,
  location_accuracy = 55.0,
  address = COALESCE(address, 'الاستاد اخر البنداري'),
  location_updated_at = now()
WHERE code = 'CUS-01558';
UPDATE customers 
SET 
  latitude = 30.816116,
  longitude = 31.00565,
  location_accuracy = 20.0,
  address = COALESCE(address, 'سبرباي امام كليه الشريعه'),
  location_updated_at = now()
WHERE code = 'CUS-01512';
UPDATE customers 
SET 
  latitude = 30.857712,
  longitude = 31.06052,
  location_accuracy = 51.6,
  address = COALESCE(address, 'شبشير الحصه بجوار ال شاهين للعسل'),
  location_updated_at = now()
WHERE code = 'CUS-01366';
UPDATE customers 
SET 
  latitude = 31.034655,
  longitude = 30.454714,
  location_accuracy = 8.5,
  address = COALESCE(address, 'في ظهر النادي ..دمنهور'),
  location_updated_at = now()
WHERE code = 'CUS-00518';
UPDATE customers 
SET 
  latitude = 31.126839,
  longitude = 30.128529,
  location_accuracy = 16.5,
  address = COALESCE(address, 'كفر الدوار ع الطريق'),
  location_updated_at = now()
WHERE code = 'CUS-01510';
UPDATE customers 
SET 
  latitude = 30.562386,
  longitude = 31.000847,
  location_accuracy = 30.0,
  address = COALESCE(address, 'مرور القديم'),
  location_updated_at = now()
WHERE code = 'CUS-01542';
UPDATE customers 
SET 
  latitude = 31.110796,
  longitude = 30.970022,
  location_accuracy = 65.0,
  address = COALESCE(address, 'دائرى المحله'),
  location_updated_at = now()
WHERE code = 'CUS-01300';
UPDATE customers 
SET 
  latitude = 31.128963,
  longitude = 30.124907,
  location_accuracy = 40.0,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01606';
UPDATE customers 
SET 
  latitude = 30.96703,
  longitude = 31.241148,
  location_accuracy = 13.9,
  address = COALESCE(address, 'بجوار التأمين الصحي امام مكاني كافيه'),
  location_updated_at = now()
WHERE code = 'CUS-01538';
UPDATE customers 
SET 
  latitude = 30.98465,
  longitude = 31.177446,
  location_accuracy = 18.364,
  address = COALESCE(address, 'المحله الكبري ش عبد الرحمن شاهين'),
  location_updated_at = now()
WHERE code = 'CUS-01188';
UPDATE customers 
SET 
  latitude = 30.527815,
  longitude = 31.367222,
  location_accuracy = 7.4,
  address = COALESCE(address, 'ش سعد زغلول جنب المخرطه'),
  location_updated_at = now()
WHERE code = 'CUS-01322';
UPDATE customers 
SET 
  latitude = 30.72876,
  longitude = 31.115072,
  location_accuracy = 8.218,
  address = COALESCE(address, 'معرض سيارات علي طريق السنطة'),
  location_updated_at = now()
WHERE code = 'CUS-00292';
UPDATE customers 
SET 
  latitude = 30.601788,
  longitude = 31.487411,
  location_accuracy = 8.83,
  address = COALESCE(address, 'شارع طلبه عويضه خلف محل ديزل'),
  location_updated_at = now()
WHERE code = 'CUS-01339';
UPDATE customers 
SET 
  latitude = 31.05032,
  longitude = 30.46721,
  location_accuracy = 5.0,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00181';
UPDATE customers 
SET 
  latitude = 30.790861,
  longitude = 30.97216,
  location_accuracy = 93.0,
  address = COALESCE(address, 'الجمله من السريع خلف المطاحن (توكيل بيجو القديم)'),
  location_updated_at = now()
WHERE code = 'CUS-01562';
UPDATE customers 
SET 
  latitude = 30.799334,
  longitude = 31.009111,
  location_accuracy = 12.6,
  address = COALESCE(address, 'المرشحة (طنطا)'),
  location_updated_at = now()
WHERE code = 'CUS-00859';
UPDATE customers 
SET 
  latitude = 30.801073,
  longitude = 31.007372,
  location_accuracy = 11.82,
  address = COALESCE(address, 'الكورنيش بجوار ماركت المنشاوى'),
  location_updated_at = now()
WHERE code = 'CUS-01627';
UPDATE customers 
SET 
  latitude = 30.807804,
  longitude = 31.002682,
  location_accuracy = 15.0,
  address = COALESCE(address, 'بجوار كوبري قحافه'),
  location_updated_at = now()
WHERE code = 'CUS-01408';
UPDATE customers 
SET 
  latitude = 30.79533,
  longitude = 31.009066,
  location_accuracy = 15.8,
  address = COALESCE(address, 'طنطا محمد فريد'),
  location_updated_at = now()
WHERE code = 'CUS-01496';
UPDATE customers 
SET 
  latitude = 31.141464,
  longitude = 30.124594,
  location_accuracy = 19.5,
  address = COALESCE(address, 'كفر الدوار'),
  location_updated_at = now()
WHERE code = 'CUS-00816';
UPDATE customers 
SET 
  latitude = 30.724602,
  longitude = 31.257803,
  location_accuracy = 19.553,
  address = COALESCE(address, 'ميت غمر بجوار شبكه الكهرباء'),
  location_updated_at = now()
WHERE code = 'CUS-01626';
UPDATE customers 
SET 
  latitude = 31.048964,
  longitude = 31.40824,
  location_accuracy = 13.5,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01499';
UPDATE customers 
SET 
  latitude = 30.793556,
  longitude = 31.01063,
  location_accuracy = 19.874,
  address = COALESCE(address, 'محمد فريد مع راغب باشا'),
  location_updated_at = now()
WHERE code = 'CUS-00344';
UPDATE customers 
SET 
  latitude = 30.799738,
  longitude = 31.001595,
  location_accuracy = 15.6,
  address = COALESCE(address, 'طنطا ش-المعتصم مع سعيد'),
  location_updated_at = now()
WHERE code = 'CUS-00995';
UPDATE customers 
SET 
  latitude = 30.742432,
  longitude = 30.72389,
  location_accuracy = 55.6,
  address = COALESCE(address, 'كوم حمادة'),
  location_updated_at = now()
WHERE code = 'CUS-00589';
UPDATE customers 
SET 
  latitude = 30.506517,
  longitude = 31.34521,
  location_accuracy = 18.5,
  address = COALESCE(address, 'منيا القمح'),
  location_updated_at = now()
WHERE code = 'CUS-00580';
UPDATE customers 
SET 
  latitude = 30.477297,
  longitude = 31.180317,
  location_accuracy = 16.1,
  address = COALESCE(address, 'بنها ش 10'),
  location_updated_at = now()
WHERE code = 'CUS-01026';
UPDATE customers 
SET 
  latitude = 30.54557,
  longitude = 31.054026,
  location_accuracy = 19.84,
  address = COALESCE(address, 'المصلحه'),
  location_updated_at = now()
WHERE code = 'CUS-01624';
UPDATE customers 
SET 
  latitude = 31.111145,
  longitude = 30.97013,
  location_accuracy = 24.2,
  address = COALESCE(address, 'كفر الشيخ.دائري المحلة'),
  location_updated_at = now()
WHERE code = 'CUS-00616';
UPDATE customers 
SET 
  latitude = 31.035086,
  longitude = 30.959858,
  location_accuracy = 9.78,
  address = COALESCE(address, 'طريق كفر الشيخ قبل الكمين اتجاه طنطا'),
  location_updated_at = now()
WHERE code = 'CUS-01623';
UPDATE customers 
SET 
  latitude = 30.793015,
  longitude = 31.007824,
  location_accuracy = 20.13,
  address = COALESCE(address, 'طنطا الاستاد عند بيت المشويات'),
  location_updated_at = now()
WHERE code = 'CUS-01527';
UPDATE customers 
SET 
  latitude = 30.79917,
  longitude = 31.008991,
  location_accuracy = 35.0,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01561';
UPDATE customers 
SET 
  latitude = 30.478783,
  longitude = 31.179857,
  location_accuracy = 20.0,
  address = COALESCE(address, 'بنها ش الفلل'),
  location_updated_at = now()
WHERE code = 'CUS-01295';
UPDATE customers 
SET 
  latitude = 30.77834,
  longitude = 30.975048,
  location_accuracy = 11.52,
  address = COALESCE(address, 'طريق الملحه بجوار ملعب سيجار بعد نادى القضاه'),
  location_updated_at = now()
WHERE code = 'CUS-01622';
UPDATE customers 
SET 
  latitude = 30.794876,
  longitude = 30.9953,
  location_accuracy = 13.9,
  address = COALESCE(address, 'ش يوسف الصديق'),
  location_updated_at = now()
WHERE code = 'CUS-01442';
UPDATE customers 
SET 
  latitude = 30.797789,
  longitude = 30.997343,
  location_accuracy = 39.986,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00406';
UPDATE customers 
SET 
  latitude = 31.028208,
  longitude = 30.485138,
  location_accuracy = 8.5,
  address = COALESCE(address, 'دمنهور بعد كوبري ابو الريش'),
  location_updated_at = now()
WHERE code = 'CUS-00890';
UPDATE customers 
SET 
  latitude = 31.047396,
  longitude = 30.4708,
  location_accuracy = 19.6,
  address = COALESCE(address, 'دمنهور شارع ابو هريره'),
  location_updated_at = now()
WHERE code = 'CUS-01436';
UPDATE customers 
SET 
  latitude = 30.803516,
  longitude = 30.902487,
  location_accuracy = 4.35,
  address = COALESCE(address, 'السريع بعد بنزينه كفر الشوربجي اتجاه كفر الزيات'),
  location_updated_at = now()
WHERE code = 'CUS-01621';
UPDATE customers 
SET 
  latitude = 30.890171,
  longitude = 30.661703,
  location_accuracy = 7.3,
  address = COALESCE(address, 'ايتاي بعد الفرسان'),
  location_updated_at = now()
WHERE code = 'CUS-01620';
UPDATE customers 
SET 
  latitude = 30.882957,
  longitude = 30.661987,
  location_accuracy = 18.3,
  address = COALESCE(address, 'ايتاي تحت الكبري العلوي'),
  location_updated_at = now()
WHERE code = 'CUS-01505';
UPDATE customers 
SET 
  latitude = 30.58327,
  longitude = 31.530357,
  location_accuracy = 40.0,
  address = COALESCE(address, 'طريق الزقازيق الزراعه امام قاعة الفيروز'),
  location_updated_at = now()
WHERE code = 'CUS-01571';
UPDATE customers 
SET 
  latitude = 30.807375,
  longitude = 30.998472,
  location_accuracy = 20.1,
  address = COALESCE(address, 'قحافه بجوار الاسعاف جنب سالم البنا'),
  location_updated_at = now()
WHERE code = 'CUS-01367';
UPDATE customers 
SET 
  latitude = 30.991531,
  longitude = 31.16731,
  location_accuracy = 8.3,
  address = COALESCE(address, 'دائري المحله'),
  location_updated_at = now()
WHERE code = 'CUS-01444';
UPDATE customers 
SET 
  latitude = 30.477875,
  longitude = 31.18406,
  location_accuracy = 27.41,
  address = COALESCE(address, 'الفلل بجانب thehub'),
  location_updated_at = now()
WHERE code = 'CUS-01588';
UPDATE customers 
SET 
  latitude = 31.033237,
  longitude = 31.364136,
  location_accuracy = 15.5,
  address = COALESCE(address, 'شارع احمد ماهر'),
  location_updated_at = now()
WHERE code = 'CUS-01328';
UPDATE customers 
SET 
  latitude = 30.468187,
  longitude = 31.187351,
  location_accuracy = 24.6,
  address = COALESCE(address, 'بنها ش الاستاد'),
  location_updated_at = now()
WHERE code = 'CUS-01024';
UPDATE customers 
SET 
  latitude = 31.13929,
  longitude = 30.127548,
  location_accuracy = 70.25,
  address = COALESCE(address, 'امتداد دكتور كربون مربع الكافيهات'),
  location_updated_at = now()
WHERE code = 'CUS-01603';
UPDATE customers 
SET 
  latitude = 30.764595,
  longitude = 30.70349,
  location_accuracy = 15.1,
  address = COALESCE(address, 'عزبه الرامي'),
  location_updated_at = now()
WHERE code = 'CUS-01355';
UPDATE customers 
SET 
  latitude = 30.773237,
  longitude = 30.73519,
  location_accuracy = 16.002,
  address = COALESCE(address, 'اول مدخل كوم حمادة'),
  location_updated_at = now()
WHERE code = 'CUS-00586';
UPDATE customers 
SET 
  latitude = 30.767653,
  longitude = 30.992743,
  location_accuracy = 27.226,
  address = COALESCE(address, 'العجيزي امام الموقف'),
  location_updated_at = now()
WHERE code = 'CUS-01212';
UPDATE customers 
SET 
  latitude = 30.495699,
  longitude = 31.287638,
  location_accuracy = 42.5,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01406';
UPDATE customers 
SET 
  latitude = 30.550875,
  longitude = 31.131279,
  location_accuracy = 15.1,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01563';
UPDATE customers 
SET 
  latitude = 30.56813,
  longitude = 31.005116,
  location_accuracy = 15.3,
  address = COALESCE(address, 'شارع البحر باريس'),
  location_updated_at = now()
WHERE code = 'CUS-01364';
UPDATE customers 
SET 
  latitude = 31.053692,
  longitude = 31.401657,
  location_accuracy = 13.5,
  address = COALESCE(address, 'المنصورة'),
  location_updated_at = now()
WHERE code = 'CUS-00565';
UPDATE customers 
SET 
  latitude = 31.057129,
  longitude = 31.405504,
  location_accuracy = 26.504,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00391';
UPDATE customers 
SET 
  latitude = 31.027523,
  longitude = 31.36343,
  location_accuracy = 16.3,
  address = COALESCE(address, 'مساكن العبور'),
  location_updated_at = now()
WHERE code = 'CUS-01556';
UPDATE customers 
SET 
  latitude = 30.598604,
  longitude = 31.4897,
  location_accuracy = 24.794,
  address = COALESCE(address, 'الزقازيق ش الحناوي امام صيدلية الشيخ'),
  location_updated_at = now()
WHERE code = 'CUS-00717';
UPDATE customers 
SET 
  latitude = 30.59962,
  longitude = 31.489626,
  location_accuracy = 30.6,
  address = COALESCE(address, 'موقف المنصوره'),
  location_updated_at = now()
WHERE code = 'CUS-01340';
UPDATE customers 
SET 
  latitude = 30.577082,
  longitude = 30.70825,
  location_accuracy = 26.392,
  address = COALESCE(address, 'مركز بدر ..كوم حمادة'),
  location_updated_at = now()
WHERE code = 'CUS-00520';
UPDATE customers 
SET 
  latitude = 30.826883,
  longitude = 31.012548,
  location_accuracy = 9.648,
  address = COALESCE(address, 'سبرباي بجوار الشيمي للزيوت'),
  location_updated_at = now()
WHERE code = 'CUS-01144';
UPDATE customers 
SET 
  latitude = 30.80101,
  longitude = 31.003931,
  location_accuracy = 14.7,
  address = COALESCE(address, 'شارع الحلو جنب براديس'),
  location_updated_at = now()
WHERE code = 'CUS-01513';
UPDATE customers 
SET 
  latitude = 30.800518,
  longitude = 31.00849,
  location_accuracy = 48.0,
  address = COALESCE(address, 'كورنيش قحافه  بجوار كافتيريا الشمندوره'),
  location_updated_at = now()
WHERE code = 'CUS-01565';
UPDATE customers 
SET 
  latitude = 30.820341,
  longitude = 31.003563,
  location_accuracy = 18.5,
  address = COALESCE(address, 'سبرباي -خلف موقف سبرباى'),
  location_updated_at = now()
WHERE code = 'CUS-00856';
UPDATE customers 
SET 
  latitude = 30.964348,
  longitude = 30.961134,
  location_accuracy = 3.9,
  address = COALESCE(address, 'قطور'),
  location_updated_at = now()
WHERE code = 'CUS-01446';
UPDATE customers 
SET 
  latitude = 30.981356,
  longitude = 31.177975,
  location_accuracy = 12.14,
  address = COALESCE(address, 'منطقه ابو راضي ش سامي الكهربائي'),
  location_updated_at = now()
WHERE code = 'CUS-01599';
UPDATE customers 
SET 
  latitude = 30.63668,
  longitude = 31.096416,
  location_accuracy = 13.1,
  address = COALESCE(address, 'بركه السبع _ طريق كفر عليم'),
  location_updated_at = now()
WHERE code = 'CUS-01281';
UPDATE customers 
SET 
  latitude = 30.963629,
  longitude = 30.958773,
  location_accuracy = 24.97,
  address = COALESCE(address, 'شارع مغسله العاصى'),
  location_updated_at = now()
WHERE code = 'CUS-01617';
UPDATE customers 
SET 
  latitude = 30.803932,
  longitude = 30.991877,
  location_accuracy = 24.5,
  address = COALESCE(address, 'طريق شوبر'),
  location_updated_at = now()
WHERE code = 'CUS-01514';
UPDATE customers 
SET 
  latitude = 30.76159,
  longitude = 30.701553,
  location_accuracy = 110.0,
  address = COALESCE(address, 'شارع الحسب الوطنى'),
  location_updated_at = now()
WHERE code = 'CUS-01208';
UPDATE customers 
SET 
  latitude = 31.046955,
  longitude = 30.460245,
  location_accuracy = 15.891,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00102';
UPDATE customers 
SET 
  latitude = 30.583324,
  longitude = 31.489412,
  location_accuracy = 17.7,
  address = COALESCE(address, 'الزقازيق'),
  location_updated_at = now()
WHERE code = 'CUS-01546';
UPDATE customers 
SET 
  latitude = 31.244522,
  longitude = 29.995762,
  location_accuracy = 16.08,
  address = COALESCE(address, 'السيوف'),
  location_updated_at = now()
WHERE code = 'CUS-01431';
UPDATE customers 
SET 
  latitude = 30.938938,
  longitude = 30.817877,
  location_accuracy = 15.84,
  address = COALESCE(address, 'بسيون'),
  location_updated_at = now()
WHERE code = 'CUS-01585';
UPDATE customers 
SET 
  latitude = 30.810888,
  longitude = 30.99517,
  location_accuracy = 11.71,
  address = COALESCE(address, 'الاستاد/شارع  البنداري خلف المصرية'),
  location_updated_at = now()
WHERE code = 'CUS-00069';
UPDATE customers 
SET 
  latitude = 30.466337,
  longitude = 31.189737,
  location_accuracy = 25.6,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01006';
UPDATE customers 
SET 
  latitude = 31.428665,
  longitude = 31.803455,
  location_accuracy = 14.7,
  address = COALESCE(address, 'دمباط القديمه الكورنيش بجوار بنك ابو ظبي'),
  location_updated_at = now()
WHERE code = 'CUS-01494';
UPDATE customers 
SET 
  latitude = 30.948738,
  longitude = 31.149618,
  location_accuracy = 4.8,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01576';
UPDATE customers 
SET 
  latitude = 30.75651,
  longitude = 30.695774,
  location_accuracy = 24.9,
  address = COALESCE(address, 'كوم حماده ضارع المصنع'),
  location_updated_at = now()
WHERE code = 'CUS-01335';
UPDATE customers 
SET 
  latitude = 30.892618,
  longitude = 30.667519,
  location_accuracy = 7.83,
  address = COALESCE(address, 'أمام محطه cpc قبل مغسله ابو ياسين'),
  location_updated_at = now()
WHERE code = 'CUS-01579';
UPDATE customers 
SET 
  latitude = 31.118105,
  longitude = 30.949398,
  location_accuracy = 6.432,
  address = COALESCE(address, 'بجوار مدرسه القرآن علاء طولان الخيريه'),
  location_updated_at = now()
WHERE code = 'CUS-01345';
UPDATE customers 
SET 
  latitude = 30.98539,
  longitude = 31.17674,
  location_accuracy = 20.62,
  address = COALESCE(address, 'ش البان الكابتن'),
  location_updated_at = now()
WHERE code = 'CUS-01604';
UPDATE customers 
SET 
  latitude = 31.111597,
  longitude = 30.951565,
  location_accuracy = 18.9,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00113';
UPDATE customers 
SET 
  latitude = 30.987274,
  longitude = 31.172567,
  location_accuracy = 11.79,
  address = COALESCE(address, 'المحلة مدرسه مصطفى كامل الاعداديه فى شارع محب خلف عمارات القبطان شريف العربى'),
  location_updated_at = now()
WHERE code = 'CUS-01107';
UPDATE customers 
SET 
  latitude = 30.570585,
  longitude = 31.00382,
  location_accuracy = 20.9,
  address = COALESCE(address, 'شارع باريس'),
  location_updated_at = now()
WHERE code = 'CUS-01220';
UPDATE customers 
SET 
  latitude = 31.047796,
  longitude = 30.471085,
  location_accuracy = 92.9,
  address = COALESCE(address, 'دمنهور خلف الاورام'),
  location_updated_at = now()
WHERE code = 'CUS-00946';
UPDATE customers 
SET 
  latitude = 31.04991,
  longitude = 30.460136,
  location_accuracy = 65.0,
  address = COALESCE(address, 'دمنهور خلف مستشفى الصدر'),
  location_updated_at = now()
WHERE code = 'CUS-01313';
UPDATE customers 
SET 
  latitude = 30.838646,
  longitude = 31.053596,
  location_accuracy = 22.99,
  address = COALESCE(address, 'الرجديه بعد المزلقان التانى بجوار الاشرف للسيارات'),
  location_updated_at = now()
WHERE code = 'CUS-01611';
UPDATE customers 
SET 
  latitude = 30.796125,
  longitude = 31.011509,
  location_accuracy = 33.5,
  address = COALESCE(address, 'المرشحة امام مترو كافيه( سحب ضعيف)'),
  location_updated_at = now()
WHERE code = 'CUS-01129';
UPDATE customers 
SET 
  latitude = 30.77815,
  longitude = 31.018929,
  location_accuracy = 22.2,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00630';
UPDATE customers 
SET 
  latitude = 31.013258,
  longitude = 31.295912,
  location_accuracy = 9.0,
  address = COALESCE(address, 'طريق المنصوره سمنود'),
  location_updated_at = now()
WHERE code = 'CUS-01543';
UPDATE customers 
SET 
  latitude = 31.026281,
  longitude = 31.37026,
  location_accuracy = 18.95,
  address = COALESCE(address, 'دوران المحور ش عبد السلام علي'),
  location_updated_at = now()
WHERE code = 'CUS-01597';
UPDATE customers 
SET 
  latitude = 31.031006,
  longitude = 30.463722,
  location_accuracy = 12.57,
  address = COALESCE(address, 'ش 20 شبرا'),
  location_updated_at = now()
WHERE code = 'CUS-01104';
UPDATE customers 
SET 
  latitude = 31.026045,
  longitude = 30.457588,
  location_accuracy = 65.0,
  address = COALESCE(address, 'ش الروضه جنب الطريق الزراعى'),
  location_updated_at = now()
WHERE code = 'CUS-01329';
UPDATE customers 
SET 
  latitude = 30.71564,
  longitude = 31.242908,
  location_accuracy = 29.5,
  address = COALESCE(address, 'زفتي امام موقف المحله'),
  location_updated_at = now()
WHERE code = 'CUS-01369';
UPDATE customers 
SET 
  latitude = 30.767134,
  longitude = 30.713469,
  location_accuracy = 38.4,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01450';
UPDATE customers 
SET 
  latitude = 30.77682,
  longitude = 31.014637,
  location_accuracy = 4.1,
  address = COALESCE(address, 'الجلاء أمام الجيل المسلم الناحيه التانيه'),
  location_updated_at = now()
WHERE code = 'CUS-01590';
UPDATE customers 
SET 
  latitude = 31.044107,
  longitude = 30.476482,
  location_accuracy = 9.3,
  address = COALESCE(address, 'كوبري فلاجه ش الكورنيش'),
  location_updated_at = now()
WHERE code = 'CUS-00097';
UPDATE customers 
SET 
  latitude = 31.125862,
  longitude = 30.123663,
  location_accuracy = 58.612,
  address = COALESCE(address, 'المدخل العمومي'),
  location_updated_at = now()
WHERE code = 'CUS-01113';
UPDATE customers 
SET 
  latitude = 30.55892,
  longitude = 31.442274,
  location_accuracy = 20.9,
  address = COALESCE(address, 'الزقازيق الزنكلون'),
  location_updated_at = now()
WHERE code = 'CUS-01362';
UPDATE customers 
SET 
  latitude = 31.108482,
  longitude = 30.930243,
  location_accuracy = 25.1,
  address = COALESCE(address, 'كفر الشيخ -المدينة الصناعية'),
  location_updated_at = now()
WHERE code = 'CUS-01000';
UPDATE customers 
SET 
  latitude = 31.110699,
  longitude = 30.947893,
  location_accuracy = 21.1,
  address = COALESCE(address, 'كفر الشيخ  شارع مخزن الزين'),
  location_updated_at = now()
WHERE code = 'CUS-01360';
UPDATE customers 
SET 
  latitude = 30.728504,
  longitude = 31.1153,
  location_accuracy = 72.481,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00137';
UPDATE customers 
SET 
  latitude = 30.906597,
  longitude = 31.108545,
  location_accuracy = 34.4,
  address = COALESCE(address, 'السريع بعد وادي القمر'),
  location_updated_at = now()
WHERE code = 'CUS-01600';
UPDATE customers 
SET 
  latitude = 30.945545,
  longitude = 31.147182,
  location_accuracy = 50.096,
  address = COALESCE(address, 'منشية البكري'),
  location_updated_at = now()
WHERE code = 'CUS-01054';
UPDATE customers 
SET 
  latitude = 31.05466,
  longitude = 31.403728,
  location_accuracy = 5.0,
  address = COALESCE(address, 'دجيلة المنصورة'),
  location_updated_at = now()
WHERE code = 'CUS-01042';
UPDATE customers 
SET 
  latitude = 30.474674,
  longitude = 31.16892,
  location_accuracy = 15.248,
  address = COALESCE(address, 'كفر الجزار'),
  location_updated_at = now()
WHERE code = 'CUS-01351';
UPDATE customers 
SET 
  latitude = 30.731512,
  longitude = 31.119576,
  location_accuracy = 11.792,
  address = COALESCE(address, 'السنطه بجوار السنترال'),
  location_updated_at = now()
WHERE code = 'CUS-01236';
UPDATE customers 
SET 
  latitude = 30.792309,
  longitude = 30.981695,
  location_accuracy = 33.549,
  address = COALESCE(address, 'المعاهده ( سحبه ضعيف جدا وبيفتح قليل)'),
  location_updated_at = now()
WHERE code = 'CUS-01235';
UPDATE customers 
SET 
  latitude = 30.784716,
  longitude = 31.002346,
  location_accuracy = 13.8,
  address = COALESCE(address, 'سعيد'),
  location_updated_at = now()
WHERE code = 'CUS-01595';
UPDATE customers 
SET 
  latitude = 31.058935,
  longitude = 31.414854,
  location_accuracy = 30.0,
  address = COALESCE(address, 'جديله بعد المقابر'),
  location_updated_at = now()
WHERE code = 'CUS-01535';
UPDATE customers 
SET 
  latitude = 31.031113,
  longitude = 31.387892,
  location_accuracy = 5.1,
  address = COALESCE(address, 'منطقة الاستاد'),
  location_updated_at = now()
WHERE code = 'CUS-00764';
UPDATE customers 
SET 
  latitude = 31.043886,
  longitude = 30.476927,
  location_accuracy = 5.53,
  address = COALESCE(address, 'بعد مغسله الفريده'),
  location_updated_at = now()
WHERE code = 'CUS-01591';
UPDATE customers 
SET 
  latitude = 30.790918,
  longitude = 31.014654,
  location_accuracy = 67.0,
  address = COALESCE(address, 'الكورنيش بعد المزلقان على ناصيه الشرع كشرى ابو صلاح'),
  location_updated_at = now()
WHERE code = 'CUS-01544';
UPDATE customers 
SET 
  latitude = 30.972427,
  longitude = 31.183634,
  location_accuracy = 5.6,
  address = COALESCE(address, 'المحلة'),
  location_updated_at = now()
WHERE code = 'CUS-01106';
UPDATE customers 
SET 
  latitude = 30.567976,
  longitude = 31.001682,
  location_accuracy = 14.4,
  address = COALESCE(address, 'ش مخزن ادويه شركه ميديكال'),
  location_updated_at = now()
WHERE code = 'CUS-01291';
UPDATE customers 
SET 
  latitude = 30.964794,
  longitude = 31.163279,
  location_accuracy = 28.2,
  address = COALESCE(address, 'ميدان الشون'),
  location_updated_at = now()
WHERE code = 'CUS-01438';
UPDATE customers 
SET 
  latitude = 30.93423,
  longitude = 30.81355,
  location_accuracy = 11.186,
  address = COALESCE(address, 'بسيون ش المدراس'),
  location_updated_at = now()
WHERE code = 'CUS-01332';
UPDATE customers 
SET 
  latitude = 30.941093,
  longitude = 30.822502,
  location_accuracy = 8.5,
  address = COALESCE(address, 'بسيون ش 23يوليو'),
  location_updated_at = now()
WHERE code = 'CUS-01586';
UPDATE customers 
SET 
  latitude = 30.891672,
  longitude = 30.668295,
  location_accuracy = 110.0,
  address = COALESCE(address, 'ايتاي امام البنك الاهلي'),
  location_updated_at = now()
WHERE code = 'CUS-01120';
UPDATE customers 
SET 
  latitude = 30.98278,
  longitude = 31.173382,
  location_accuracy = 11.51,
  address = COALESCE(address, 'بيستخدم عبوات صغيرة جدا'),
  location_updated_at = now()
WHERE code = 'CUS-00317';
UPDATE customers 
SET 
  latitude = 30.983559,
  longitude = 31.179352,
  location_accuracy = 13.1,
  address = COALESCE(address, 'المحله الكبري ش مسجد الشامي'),
  location_updated_at = now()
WHERE code = 'CUS-01221';
UPDATE customers 
SET 
  latitude = 31.030815,
  longitude = 30.453312,
  location_accuracy = 13.99,
  address = COALESCE(address, 'أمام واش ان جو'),
  location_updated_at = now()
WHERE code = 'CUS-01583';
UPDATE customers 
SET 
  latitude = 30.793247,
  longitude = 30.996895,
  location_accuracy = 17.064,
  address = COALESCE(address, 'ش ابو بكر الصديق'),
  location_updated_at = now()
WHERE code = 'CUS-01515';
UPDATE customers 
SET 
  latitude = 30.801468,
  longitude = 31.008404,
  location_accuracy = 37.3,
  address = COALESCE(address, 'الكورنيش بجوار مطعم عواد'),
  location_updated_at = now()
WHERE code = 'CUS-01427';
UPDATE customers 
SET 
  latitude = 31.028294,
  longitude = 30.452204,
  location_accuracy = 1.5,
  address = COALESCE(address, 'شارع المعهد الديني امام بنزينة الدفراوي'),
  location_updated_at = now()
WHERE code = 'CUS-01419';
UPDATE customers 
SET 
  latitude = 30.791756,
  longitude = 30.973368,
  location_accuracy = 12.4,
  address = COALESCE(address, 'طريق السريع'),
  location_updated_at = now()
WHERE code = 'CUS-00535';
UPDATE customers 
SET 
  latitude = 30.607437,
  longitude = 30.99872,
  location_accuracy = 15.4,
  address = COALESCE(address, 'الكوم الاخضر _ شبين الكوم'),
  location_updated_at = now()
WHERE code = 'CUS-01278';
UPDATE customers 
SET 
  latitude = 30.729195,
  longitude = 30.971603,
  location_accuracy = 73.38,
  address = COALESCE(address, 'بعد كفر الشيخ سليم'),
  location_updated_at = now()
WHERE code = 'CUS-01578';
UPDATE customers 
SET 
  latitude = 30.81681,
  longitude = 30.837122,
  location_accuracy = 43.2,
  address = COALESCE(address, 'كفر الزيات قبل بنك اسكندريه'),
  location_updated_at = now()
WHERE code = 'CUS-01508';
UPDATE customers 
SET 
  latitude = 30.598549,
  longitude = 31.489813,
  location_accuracy = 23.881,
  address = COALESCE(address, 'ش الغشام'),
  location_updated_at = now()
WHERE code = 'CUS-00232';
UPDATE customers 
SET 
  latitude = 31.030739,
  longitude = 31.366625,
  location_accuracy = 18.936,
  address = COALESCE(address, 'المنصورة ش سامية الجمل'),
  location_updated_at = now()
WHERE code = 'CUS-00874';
UPDATE customers 
SET 
  latitude = 31.041883,
  longitude = 30.478354,
  location_accuracy = 52.0,
  address = COALESCE(address, 'الكورنيش بعد مغسله الفريده'),
  location_updated_at = now()
WHERE code = 'CUS-01574';
UPDATE customers 
SET 
  latitude = 30.80452,
  longitude = 31.002682,
  location_accuracy = 20.286,
  address = COALESCE(address, 'اخر شارع سعيد عند البوسطة'),
  location_updated_at = now()
WHERE code = 'CUS-00906';
UPDATE customers 
SET 
  latitude = 30.467516,
  longitude = 31.181936,
  location_accuracy = 10.0,
  address = COALESCE(address, 'بجوار الكينج لفرش السيارات'),
  location_updated_at = now()
WHERE code = 'CUS-01572';
UPDATE customers 
SET 
  latitude = 30.943462,
  longitude = 30.832926,
  location_accuracy = 10.4,
  address = COALESCE(address, 'التنظيم -بسيون'),
  location_updated_at = now()
WHERE code = 'CUS-00918';
UPDATE customers 
SET 
  latitude = 31.031841,
  longitude = 31.36599,
  location_accuracy = 12.7,
  address = COALESCE(address, 'المنصوره حي الجامعه'),
  location_updated_at = now()
WHERE code = 'CUS-01412';
UPDATE customers 
SET 
  latitude = 31.040733,
  longitude = 30.458696,
  location_accuracy = 9.9,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01477';
UPDATE customers 
SET 
  latitude = 31.032557,
  longitude = 30.460876,
  location_accuracy = 35.0,
  address = COALESCE(address, 'ش علي عياد تقاطع شجره الدر'),
  location_updated_at = now()
WHERE code = 'CUS-01569';
UPDATE customers 
SET 
  latitude = 30.586843,
  longitude = 30.984365,
  location_accuracy = 65.0,
  address = COALESCE(address, 'شبين طريق تلا بجوار العالمى'),
  location_updated_at = now()
WHERE code = 'CUS-01307';
UPDATE customers 
SET 
  latitude = 30.80218,
  longitude = 31.003948,
  location_accuracy = 14.8,
  address = COALESCE(address, 'اخر الحلو'),
  location_updated_at = now()
WHERE code = 'CUS-01176';
UPDATE customers 
SET 
  latitude = 30.795437,
  longitude = 30.983906,
  location_accuracy = 35.464,
  address = COALESCE(address, 'الجملة - الطريق السريع'),
  location_updated_at = now()
WHERE code = 'CUS-00831';
UPDATE customers 
SET 
  latitude = 31.048162,
  longitude = 30.463936,
  location_accuracy = 4.4,
  address = COALESCE(address, 'دمنهور ش جلال امام فيلا الحناوي'),
  location_updated_at = now()
WHERE code = 'CUS-00927';
UPDATE customers 
SET 
  latitude = 31.030329,
  longitude = 30.489738,
  location_accuracy = 33.7,
  address = COALESCE(address, 'دمنهور طريق دسوق'),
  location_updated_at = now()
WHERE code = 'CUS-01294';
UPDATE customers 
SET 
  latitude = 31.14843,
  longitude = 30.128736,
  location_accuracy = 16.5,
  address = COALESCE(address, 'منطقه التمليك بجوار كافيه سلطنه'),
  location_updated_at = now()
WHERE code = 'CUS-01285';
UPDATE customers 
SET 
  latitude = 31.126472,
  longitude = 30.123966,
  location_accuracy = 46.0,
  address = COALESCE(address, 'مدخل كفر الدوار خلف مركز ابو بكر'),
  location_updated_at = now()
WHERE code = 'CUS-01568';
UPDATE customers 
SET 
  latitude = 31.42165,
  longitude = 31.798418,
  location_accuracy = 27.2,
  address = COALESCE(address, 'دمياط القديمه امام حديقه الطفل'),
  location_updated_at = now()
WHERE code = 'CUS-01423';
UPDATE customers 
SET 
  latitude = 30.819376,
  longitude = 31.007366,
  location_accuracy = 17.7,
  address = COALESCE(address, 'سبرباي الورش التانيه خلف مسجد النور'),
  location_updated_at = now()
WHERE code = 'CUS-01222';
UPDATE customers 
SET 
  latitude = 30.771416,
  longitude = 30.718746,
  location_accuracy = 60.0,
  address = COALESCE(address, 'قناطر بولين طريق كوم حمادة'),
  location_updated_at = now()
WHERE code = 'CUS-00780';
UPDATE customers 
SET 
  latitude = 30.952576,
  longitude = 31.153816,
  location_accuracy = 4.288,
  address = COALESCE(address, 'الشعبيه'),
  location_updated_at = now()
WHERE code = 'CUS-01331';
UPDATE customers 
SET 
  latitude = 31.152466,
  longitude = 30.124664,
  location_accuracy = 37.0,
  address = COALESCE(address, 'سيدي سحاته'),
  location_updated_at = now()
WHERE code = 'CUS-01566';
UPDATE customers 
SET 
  latitude = 31.137184,
  longitude = 30.129158,
  location_accuracy = 65.0,
  address = COALESCE(address, 'ش الموقف منطقة الميزانة بجوار المحكمة'),
  location_updated_at = now()
WHERE code = 'CUS-00276';
UPDATE customers 
SET 
  latitude = 30.951235,
  longitude = 30.800089,
  location_accuracy = 10.0,
  address = COALESCE(address, 'دائرى بسيون اخر طريق العماير'),
  location_updated_at = now()
WHERE code = 'CUS-01548';
UPDATE customers 
SET 
  latitude = 30.792507,
  longitude = 30.985542,
  location_accuracy = 65.0,
  address = COALESCE(address, 'طه حسين مع الفاتح'),
  location_updated_at = now()
WHERE code = 'CUS-01306';
UPDATE customers 
SET 
  latitude = 31.044952,
  longitude = 31.37257,
  location_accuracy = 19.3,
  address = COALESCE(address, 'المنصوره متفرع من المشايه العلويه'),
  location_updated_at = now()
WHERE code = 'CUS-01413';
UPDATE customers 
SET 
  latitude = 31.04764,
  longitude = 31.407778,
  location_accuracy = 25.7,
  address = COALESCE(address, 'المنصوره'),
  location_updated_at = now()
WHERE code = 'CUS-01502';
UPDATE customers 
SET 
  latitude = 30.477371,
  longitude = 31.180363,
  location_accuracy = 10.881,
  address = COALESCE(address, 'بنها ش المدينة المنورة'),
  location_updated_at = now()
WHERE code = 'CUS-01118';
UPDATE customers 
SET 
  latitude = 30.976423,
  longitude = 30.955273,
  location_accuracy = 47.0,
  address = COALESCE(address, 'قطور شارع مستشفي قطور العام'),
  location_updated_at = now()
WHERE code = 'CUS-01560';
UPDATE customers 
SET 
  latitude = 30.982721,
  longitude = 31.182184,
  location_accuracy = 18.702,
  address = COALESCE(address, 'ش ابو راضي ش عبدالرحمن شاهين خلف الصامولي'),
  location_updated_at = now()
WHERE code = 'CUS-00031';
UPDATE customers 
SET 
  latitude = 31.047672,
  longitude = 30.460165,
  location_accuracy = 65.0,
  address = COALESCE(address, 'دمنهور الشارع اللى جنب بطيشه'),
  location_updated_at = now()
WHERE code = 'CUS-00174';
UPDATE customers 
SET 
  latitude = 30.473127,
  longitude = 31.168556,
  location_accuracy = 19.5,
  address = COALESCE(address, 'كفرالجزار'),
  location_updated_at = now()
WHERE code = 'CUS-01484';
UPDATE customers 
SET 
  latitude = 31.11469,
  longitude = 30.929485,
  location_accuracy = 73.272,
  address = COALESCE(address, 'كفر الشيخ بحوار مستشفي النخبه'),
  location_updated_at = now()
WHERE code = 'CUS-01554';
UPDATE customers 
SET 
  latitude = 30.81454,
  longitude = 31.005545,
  location_accuracy = 13.6,
  address = COALESCE(address, 'سبرباي طنطا'),
  location_updated_at = now()
WHERE code = 'CUS-01517';
UPDATE customers 
SET 
  latitude = 30.893253,
  longitude = 30.667582,
  location_accuracy = 25.9,
  address = COALESCE(address, 'ايتاي البارود طريق شبراخيت'),
  location_updated_at = now()
WHERE code = 'CUS-01259';
UPDATE customers 
SET 
  latitude = 30.807535,
  longitude = 30.988308,
  location_accuracy = 17.791,
  address = COALESCE(address, 'طريق شوبر منطقه الورش بجوار كافتريا بسام'),
  location_updated_at = now()
WHERE code = 'CUS-01523';
UPDATE customers 
SET 
  latitude = 30.790136,
  longitude = 30.978205,
  location_accuracy = 9.648,
  address = COALESCE(address, 'شارع المعاهده امام ابو حلوة'),
  location_updated_at = now()
WHERE code = 'CUS-01348';
UPDATE customers 
SET 
  latitude = 30.97992,
  longitude = 31.173548,
  location_accuracy = 12.5,
  address = COALESCE(address, 'ش احمد حسين متفرع من شكري'),
  location_updated_at = now()
WHERE code = 'CUS-00047';
UPDATE customers 
SET 
  latitude = 30.583742,
  longitude = 31.528463,
  location_accuracy = 33.4,
  address = COALESCE(address, 'الزقازيق'),
  location_updated_at = now()
WHERE code = 'CUS-01492';
UPDATE customers 
SET 
  latitude = 30.800339,
  longitude = 30.963919,
  location_accuracy = 9.3,
  address = COALESCE(address, 'محله مرحوم امام ماركت فور يو'),
  location_updated_at = now()
WHERE code = 'CUS-01377';
UPDATE customers 
SET 
  latitude = 30.95994,
  longitude = 30.958498,
  location_accuracy = 16.08,
  address = COALESCE(address, 'قطور'),
  location_updated_at = now()
WHERE code = 'CUS-00840';
UPDATE customers 
SET 
  latitude = 31.107162,
  longitude = 30.9292,
  location_accuracy = 7.5,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00701';
UPDATE customers 
SET 
  latitude = 30.788815,
  longitude = 31.010061,
  location_accuracy = 36.0,
  address = COALESCE(address, 'اخر محمد فريد قبل سكه المحله'),
  location_updated_at = now()
WHERE code = 'CUS-01547';
UPDATE customers 
SET 
  latitude = 31.050024,
  longitude = 30.467163,
  location_accuracy = 17.4,
  address = COALESCE(address, 'شارع مستشفى دار الشفاء'),
  location_updated_at = now()
WHERE code = 'CUS-01254';
UPDATE customers 
SET 
  latitude = 30.560635,
  longitude = 31.016106,
  location_accuracy = 9.0,
  address = COALESCE(address, 'اخر الكوبري العلوي امام الهنداوي وبعد مستشفي المواساه'),
  location_updated_at = now()
WHERE code = 'CUS-01440';
UPDATE customers 
SET 
  latitude = 30.963213,
  longitude = 31.164185,
  location_accuracy = 8.9,
  address = COALESCE(address, 'وابور النور'),
  location_updated_at = now()
WHERE code = 'CUS-01330';
UPDATE customers 
SET 
  latitude = 30.948666,
  longitude = 31.154331,
  location_accuracy = 17.741,
  address = COALESCE(address, 'ش مستشفي الصفوة امام مدرسة الصنايع حي الشعبية ميدان البكري'),
  location_updated_at = now()
WHERE code = 'CUS-00348';
UPDATE customers 
SET 
  latitude = 30.792688,
  longitude = 30.992186,
  location_accuracy = 35.0,
  address = COALESCE(address, 'بجوار معرض الصيرفى'),
  location_updated_at = now()
WHERE code = 'CUS-01541';
UPDATE customers 
SET 
  latitude = 30.964481,
  longitude = 30.962791,
  location_accuracy = 16.0,
  address = COALESCE(address, 'بعد مغسله يور كار'),
  location_updated_at = now()
WHERE code = 'CUS-01534';
UPDATE customers 
SET 
  latitude = 30.7651,
  longitude = 30.705044,
  location_accuracy = 13.14,
  address = COALESCE(address, 'عزبه الرامى'),
  location_updated_at = now()
WHERE code = 'CUS-01540';
UPDATE customers 
SET 
  latitude = 30.788551,
  longitude = 31.002117,
  location_accuracy = 36.9,
  address = COALESCE(address, 'ش سعيد جانب البغل'),
  location_updated_at = now()
WHERE code = 'CUS-01169';
UPDATE customers 
SET 
  latitude = 30.791704,
  longitude = 30.973946,
  location_accuracy = 16.6,
  address = COALESCE(address, 'طنطا السريع قبل مدخل محله مرحوم'),
  location_updated_at = now()
WHERE code = 'CUS-01497';
UPDATE customers 
SET 
  latitude = 30.715258,
  longitude = 31.2379,
  location_accuracy = 15.264,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00145';
UPDATE customers 
SET 
  latitude = 30.706804,
  longitude = 31.245441,
  location_accuracy = 27.2,
  address = COALESCE(address, 'شارع الجيش عند مدرسه الصنايع'),
  location_updated_at = now()
WHERE code = 'CUS-01395';
UPDATE customers 
SET 
  latitude = 30.80585,
  longitude = 31.004139,
  location_accuracy = 32.624,
  address = COALESCE(address, 'اخر الحلو'),
  location_updated_at = now()
WHERE code = 'CUS-01253';
UPDATE customers 
SET 
  latitude = 31.047659,
  longitude = 30.460144,
  location_accuracy = 65.0,
  address = COALESCE(address, 'اول ش الجديد بجوار مصنع باغيش'),
  location_updated_at = now()
WHERE code = 'CUS-00103';
UPDATE customers 
SET 
  latitude = 30.56889,
  longitude = 31.003113,
  location_accuracy = 40.342,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01066';
UPDATE customers 
SET 
  latitude = 30.88824,
  longitude = 30.671497,
  location_accuracy = 17.6,
  address = COALESCE(address, 'ايتاي البارود'),
  location_updated_at = now()
WHERE code = 'CUS-01154';
UPDATE customers 
SET 
  latitude = 30.796127,
  longitude = 30.955122,
  location_accuracy = 26.5,
  address = COALESCE(address, 'مخله مرحوم'),
  location_updated_at = now()
WHERE code = 'CUS-01500';
UPDATE customers 
SET 
  latitude = 30.510033,
  longitude = 31.341799,
  location_accuracy = 27.5,
  address = COALESCE(address, 'منيا القمح'),
  location_updated_at = now()
WHERE code = 'CUS-01537';
UPDATE customers 
SET 
  latitude = 30.608427,
  longitude = 30.99291,
  location_accuracy = 8.3,
  address = COALESCE(address, 'بعد البتانون'),
  location_updated_at = now()
WHERE code = 'CUS-01394';
UPDATE customers 
SET 
  latitude = 31.005222,
  longitude = 31.287062,
  location_accuracy = 25.7,
  address = COALESCE(address, 'طريق سمنود المنصوره بعد بهبيت الحجاره'),
  location_updated_at = now()
WHERE code = 'CUS-01389';
UPDATE customers 
SET 
  latitude = 31.147747,
  longitude = 30.127367,
  location_accuracy = 35.0,
  address = COALESCE(address, 'مساكن التمليك دفعه ١'),
  location_updated_at = now()
WHERE code = 'CUS-01532';
UPDATE customers 
SET 
  latitude = 30.576183,
  longitude = 30.711563,
  location_accuracy = 30.073,
  address = COALESCE(address, 'مركز بدر'),
  location_updated_at = now()
WHERE code = 'CUS-00650';
UPDATE customers 
SET 
  latitude = 30.8907,
  longitude = 30.85963,
  location_accuracy = 77.715,
  address = COALESCE(address, 'كفر سيلمان طريق بسيون'),
  location_updated_at = now()
WHERE code = 'CUS-01531';
UPDATE customers 
SET 
  latitude = 30.71227,
  longitude = 31.240309,
  location_accuracy = 17.937,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01177';
UPDATE customers 
SET 
  latitude = 30.714834,
  longitude = 31.236212,
  location_accuracy = 22.9,
  address = COALESCE(address, 'زفتي'),
  location_updated_at = now()
WHERE code = 'CUS-01452';
UPDATE customers 
SET 
  latitude = 30.56931,
  longitude = 31.008572,
  location_accuracy = 20.994,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00257';
UPDATE customers 
SET 
  latitude = 30.725924,
  longitude = 31.118107,
  location_accuracy = 26.7,
  address = COALESCE(address, 'السنطه عالطريق بعد مغسه شهد اول يمين'),
  location_updated_at = now()
WHERE code = 'CUS-01216';
UPDATE customers 
SET 
  latitude = 30.809938,
  longitude = 31.011555,
  location_accuracy = 59.856,
  address = COALESCE(address, 'طنطا طريق مصر اسكندريه مدخل طريق كفر الشيخ'),
  location_updated_at = now()
WHERE code = 'CUS-01528';
UPDATE customers 
SET 
  latitude = 31.419918,
  longitude = 31.79355,
  location_accuracy = 21.3,
  address = COALESCE(address, 'دمياط القديمه منطقه السنانيه امام مطحن السنانيه'),
  location_updated_at = now()
WHERE code = 'CUS-01525';
UPDATE customers 
SET 
  latitude = 31.433527,
  longitude = 31.78036,
  location_accuracy = 23.1,
  address = COALESCE(address, 'دمياط القديمه طريق رأس البر'),
  location_updated_at = now()
WHERE code = 'CUS-01526';
UPDATE customers 
SET 
  latitude = 30.789843,
  longitude = 31.015343,
  location_accuracy = 24.1,
  address = COALESCE(address, 'الكورنيش مع حسن عفيفي بجوار مصنع السرنجات'),
  location_updated_at = now()
WHERE code = 'CUS-01488';
UPDATE customers 
SET 
  latitude = 30.856037,
  longitude = 31.06582,
  location_accuracy = 23.0,
  address = COALESCE(address, 'شبشير الحصه'),
  location_updated_at = now()
WHERE code = 'CUS-01489';
UPDATE customers 
SET 
  latitude = 31.028433,
  longitude = 30.452303,
  location_accuracy = 20.2,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01524';
UPDATE customers 
SET 
  latitude = 31.03482,
  longitude = 31.372526,
  location_accuracy = 17.7,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00706';
UPDATE customers 
SET 
  latitude = 31.053255,
  longitude = 31.398716,
  location_accuracy = 15.1,
  address = COALESCE(address, 'المنصوره'),
  location_updated_at = now()
WHERE code = 'CUS-01487';
UPDATE customers 
SET 
  latitude = 30.789494,
  longitude = 30.977346,
  location_accuracy = 16.624,
  address = COALESCE(address, 'ش المعاهدة'),
  location_updated_at = now()
WHERE code = 'CUS-00737';
UPDATE customers 
SET 
  latitude = 30.730263,
  longitude = 31.118507,
  location_accuracy = 10.1,
  address = COALESCE(address, 'السنطه'),
  location_updated_at = now()
WHERE code = 'CUS-01522';
UPDATE customers 
SET 
  latitude = 31.206863,
  longitude = 29.880047,
  location_accuracy = 14.7,
  address = COALESCE(address, 'عند القلعه'),
  location_updated_at = now()
WHERE code = 'CUS-01458';
UPDATE customers 
SET 
  latitude = 31.208673,
  longitude = 29.92512,
  location_accuracy = 11.6,
  address = COALESCE(address, '37 ش احمد قمحا خلف كلية الهندسة المسمي ش المكتبات-الشاطبي'),
  location_updated_at = now()
WHERE code = 'CUS-00514';
UPDATE customers 
SET 
  latitude = 30.472319,
  longitude = 31.178394,
  location_accuracy = 16.623,
  address = COALESCE(address, 'خلف المحافظة بجوار كافيه مدحت امام مدرسة بن خلدون'),
  location_updated_at = now()
WHERE code = 'CUS-00012';
UPDATE customers 
SET 
  latitude = 30.79742,
  longitude = 30.998257,
  location_accuracy = 16.1,
  address = COALESCE(address, 'ش البحر مع ش محب'),
  location_updated_at = now()
WHERE code = 'CUS-01242';
UPDATE customers 
SET 
  latitude = 30.950804,
  longitude = 30.801025,
  location_accuracy = 50.0,
  address = COALESCE(address, 'بسيون'),
  location_updated_at = now()
WHERE code = 'CUS-01520';
UPDATE customers 
SET 
  latitude = 31.103914,
  longitude = 30.970293,
  location_accuracy = 11.7,
  address = COALESCE(address, 'دائري المحله'),
  location_updated_at = now()
WHERE code = 'CUS-01403';
UPDATE customers 
SET 
  latitude = 31.110662,
  longitude = 30.944523,
  location_accuracy = 25.2,
  address = COALESCE(address, 'كفر الشيخ شارع الخليفه'),
  location_updated_at = now()
WHERE code = 'CUS-01373';
UPDATE customers 
SET 
  latitude = 30.580711,
  longitude = 30.70811,
  location_accuracy = 19.8,
  address = COALESCE(address, 'مركز بدر ش بنزينة المديرية جانب دكتورة حمدية'),
  location_updated_at = now()
WHERE code = 'CUS-00568';
UPDATE customers 
SET 
  latitude = 30.88925,
  longitude = 30.669851,
  location_accuracy = 14.0,
  address = COALESCE(address, 'ايتاي مساكن مجلس المدينة'),
  location_updated_at = now()
WHERE code = 'CUS-01337';
UPDATE customers 
SET 
  latitude = 31.02693,
  longitude = 31.365456,
  location_accuracy = 19.6,
  address = COALESCE(address, 'مساكن العبور'),
  location_updated_at = now()
WHERE code = 'CUS-01404';
UPDATE customers 
SET 
  latitude = 30.794115,
  longitude = 30.994196,
  location_accuracy = 17.2,
  address = COALESCE(address, 'عثمان بن عفان  تقاطع شارع انور'),
  location_updated_at = now()
WHERE code = 'CUS-00743';
UPDATE customers 
SET 
  latitude = 31.21133,
  longitude = 29.914944,
  location_accuracy = 24.571,
  address = COALESCE(address, 'كورنيش الشاطبي'),
  location_updated_at = now()
WHERE code = 'CUS-01194';
UPDATE customers 
SET 
  latitude = 31.21063,
  longitude = 29.913704,
  location_accuracy = 11.1,
  address = COALESCE(address, 'الشاطبي'),
  location_updated_at = now()
WHERE code = 'CUS-01454';
UPDATE customers 
SET 
  latitude = 31.210081,
  longitude = 29.909584,
  location_accuracy = 10.1,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01455';
UPDATE customers 
SET 
  latitude = 31.200161,
  longitude = 29.895187,
  location_accuracy = 9.1,
  address = COALESCE(address, 'المنشيه'),
  location_updated_at = now()
WHERE code = 'CUS-01518';
UPDATE customers 
SET 
  latitude = 31.207655,
  longitude = 29.880392,
  location_accuracy = 14.4,
  address = COALESCE(address, 'قصر التين-الجمرك'),
  location_updated_at = now()
WHERE code = 'CUS-01456';
UPDATE customers 
SET 
  latitude = 31.207485,
  longitude = 29.883307,
  location_accuracy = 54.8,
  address = COALESCE(address, '33شارع الشيخ محمد عبده ابو العباس الانفوشي'),
  location_updated_at = now()
WHERE code = 'CUS-01519';
UPDATE customers 
SET 
  latitude = 31.207119,
  longitude = 29.882795,
  location_accuracy = 11.484,
  address = COALESCE(address, '33شارع الشيخ محمد عبده .ابوالعباسي الانفوشي'),
  location_updated_at = now()
WHERE code = 'CUS-00442';
UPDATE customers 
SET 
  latitude = 30.81839,
  longitude = 30.832085,
  location_accuracy = 12.5,
  address = COALESCE(address, 'كفر الزيات قبل النفق'),
  location_updated_at = now()
WHERE code = 'CUS-01333';
UPDATE customers 
SET 
  latitude = 30.888155,
  longitude = 30.671545,
  location_accuracy = 13.408,
  address = COALESCE(address, 'ايتاي ش مكتب العمل'),
  location_updated_at = now()
WHERE code = 'CUS-01046';
UPDATE customers 
SET 
  latitude = 30.82891,
  longitude = 31.01392,
  location_accuracy = 3.216,
  address = COALESCE(address, 'سبرباي قبل مول طنطا'),
  location_updated_at = now()
WHERE code = 'CUS-01143';
UPDATE customers 
SET 
  latitude = 30.698847,
  longitude = 31.248196,
  location_accuracy = 14.9,
  address = COALESCE(address, 'زفتي _ اخر شارع الجيش _ بجوار قاعه فيرجينيا'),
  location_updated_at = now()
WHERE code = 'CUS-01287';
UPDATE customers 
SET 
  latitude = 31.430374,
  longitude = 31.796434,
  location_accuracy = 20.1,
  address = COALESCE(address, 'دمياط القديمه'),
  location_updated_at = now()
WHERE code = 'CUS-01410';
UPDATE customers 
SET 
  latitude = 30.795097,
  longitude = 31.011574,
  location_accuracy = 13.407,
  address = COALESCE(address, 'طنطا اخر محمد فريد'),
  location_updated_at = now()
WHERE code = 'CUS-00922';
UPDATE customers 
SET 
  latitude = 30.79057,
  longitude = 31.00337,
  location_accuracy = 21.6,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01516';
UPDATE customers 
SET 
  latitude = 30.810856,
  longitude = 30.984516,
  location_accuracy = 27.3,
  address = COALESCE(address, 'طريق شوبر'),
  location_updated_at = now()
WHERE code = 'CUS-01471';
UPDATE customers 
SET 
  latitude = 31.280663,
  longitude = 30.01197,
  location_accuracy = 22.7,
  address = COALESCE(address, 'المنتزه'),
  location_updated_at = now()
WHERE code = 'CUS-01459';
UPDATE customers 
SET 
  latitude = 31.28103,
  longitude = 30.010788,
  location_accuracy = 4.029,
  address = COALESCE(address, 'امام شيراتون المنتزة'),
  location_updated_at = now()
WHERE code = 'CUS-01428';
UPDATE customers 
SET 
  latitude = 31.268269,
  longitude = 29.99853,
  location_accuracy = 20.3,
  address = COALESCE(address, 'سيدي بشر'),
  location_updated_at = now()
WHERE code = 'CUS-01429';
UPDATE customers 
SET 
  latitude = 31.246054,
  longitude = 29.989744,
  location_accuracy = 23.727,
  address = COALESCE(address, 'مصطفي كامل  السيوف امام سنتر رنين'),
  location_updated_at = now()
WHERE code = 'CUS-00632';
UPDATE customers 
SET 
  latitude = 30.95906,
  longitude = 30.95859,
  location_accuracy = 44.4,
  address = COALESCE(address, 'قطور'),
  location_updated_at = now()
WHERE code = 'CUS-01465';
UPDATE customers 
SET 
  latitude = 30.770708,
  longitude = 30.717333,
  location_accuracy = 11.5,
  address = COALESCE(address, 'اول كوم حماده'),
  location_updated_at = now()
WHERE code = 'CUS-01449';
UPDATE customers 
SET 
  latitude = 30.77059,
  longitude = 30.717466,
  location_accuracy = 4.2,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01503';
UPDATE customers 
SET 
  latitude = 30.802511,
  longitude = 31.004858,
  location_accuracy = 18.2,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01126';
UPDATE customers 
SET 
  latitude = 30.972305,
  longitude = 31.183527,
  location_accuracy = 22.0,
  address = COALESCE(address, 'ش شركة الزيت و الصابون على ناصية شارع الشروق'),
  location_updated_at = now()
WHERE code = 'CUS-00043';
UPDATE customers 
SET 
  latitude = 31.032213,
  longitude = 31.356642,
  location_accuracy = 12.4,
  address = COALESCE(address, 'حي الجامعه شارع جيهان'),
  location_updated_at = now()
WHERE code = 'CUS-01321';
UPDATE customers 
SET 
  latitude = 30.79029,
  longitude = 30.983057,
  location_accuracy = 39.454,
  address = COALESCE(address, 'ابن الفارض مع مصطفي كامل'),
  location_updated_at = now()
WHERE code = 'CUS-00110';
UPDATE customers 
SET 
  latitude = 31.031633,
  longitude = 30.458652,
  location_accuracy = 65.0,
  address = COALESCE(address, 'ش المعهد الدينى خلف الكازينو'),
  location_updated_at = now()
WHERE code = 'CUS-01305';
UPDATE customers 
SET 
  latitude = 31.139065,
  longitude = 30.126984,
  location_accuracy = 26.1,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01509';
UPDATE customers 
SET 
  latitude = 31.150524,
  longitude = 30.12522,
  location_accuracy = 24.6,
  address = COALESCE(address, 'كفر الدوار شارع الجزار'),
  location_updated_at = now()
WHERE code = 'CUS-01511';
UPDATE customers 
SET 
  latitude = 31.110863,
  longitude = 30.970175,
  location_accuracy = 9.1,
  address = COALESCE(address, 'كفر الشيخ دائري المحله'),
  location_updated_at = now()
WHERE code = 'CUS-01445';
UPDATE customers 
SET 
  latitude = 31.110237,
  longitude = 30.945906,
  location_accuracy = 11.6,
  address = COALESCE(address, 'امام بنك ناصر'),
  location_updated_at = now()
WHERE code = 'CUS-01379';
UPDATE customers 
SET 
  latitude = 30.80108,
  longitude = 31.006546,
  location_accuracy = 26.4,
  address = COALESCE(address, 'طنطا'),
  location_updated_at = now()
WHERE code = 'CUS-01375';
UPDATE customers 
SET 
  latitude = 30.842117,
  longitude = 30.904963,
  location_accuracy = 9.7,
  address = COALESCE(address, 'محطه وقود برما'),
  location_updated_at = now()
WHERE code = 'CUS-01368';
UPDATE customers 
SET 
  latitude = 30.888723,
  longitude = 30.660183,
  location_accuracy = 23.9,
  address = COALESCE(address, 'ايتاي البرد ش جمال عبد الناصر'),
  location_updated_at = now()
WHERE code = 'CUS-01400';
UPDATE customers 
SET 
  latitude = 30.890142,
  longitude = 30.66919,
  location_accuracy = 17.6,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01506';
UPDATE customers 
SET 
  latitude = 30.751072,
  longitude = 30.688911,
  location_accuracy = 7.4,
  address = COALESCE(address, 'كوم حماده بعد هنيدي'),
  location_updated_at = now()
WHERE code = 'CUS-01425';
UPDATE customers 
SET 
  latitude = 30.764389,
  longitude = 30.702473,
  location_accuracy = 28.778,
  address = COALESCE(address, 'كوم حمادة بجوار كوبري ابو دياب بعد حوالي 2 متر من داخلة الشارع'),
  location_updated_at = now()
WHERE code = 'CUS-00799';
UPDATE customers 
SET 
  latitude = 30.763252,
  longitude = 30.708307,
  location_accuracy = 5.9,
  address = COALESCE(address, 'كوم حماده امام المرور'),
  location_updated_at = now()
WHERE code = 'CUS-01387';
UPDATE customers 
SET 
  latitude = 30.769556,
  longitude = 30.71632,
  location_accuracy = 29.6,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01504';
UPDATE customers 
SET 
  latitude = 30.794527,
  longitude = 31.012547,
  location_accuracy = 12.2,
  address = COALESCE(address, 'المرشحه جامع السلام'),
  location_updated_at = now()
WHERE code = 'CUS-01507';
UPDATE customers 
SET 
  latitude = 30.588833,
  longitude = 31.497606,
  location_accuracy = 65.0,
  address = COALESCE(address, 'القومية امام مدرسة جمال عبد الناصر'),
  location_updated_at = now()
WHERE code = 'CUS-00766';
UPDATE customers 
SET 
  latitude = 30.598654,
  longitude = 31.49229,
  location_accuracy = 19.043,
  address = COALESCE(address, 'موقف المنصورة امام المستشفي التخصصي علي جانب المركز الكوري'),
  location_updated_at = now()
WHERE code = 'CUS-00765';
UPDATE customers 
SET 
  latitude = 30.82437,
  longitude = 31.008781,
  location_accuracy = 48.891,
  address = COALESCE(address, 'سبرباي امام المدينة الجامعية'),
  location_updated_at = now()
WHERE code = 'CUS-01153';
UPDATE customers 
SET 
  latitude = 30.806856,
  longitude = 30.997616,
  location_accuracy = 21.8,
  address = COALESCE(address, 'طنطا- شارع النحاس بجوار الادارة التعليمية'),
  location_updated_at = now()
WHERE code = 'CUS-00994';
UPDATE customers 
SET 
  latitude = 30.568748,
  longitude = 31.007189,
  location_accuracy = 18.159,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01173';
UPDATE customers 
SET 
  latitude = 30.64182,
  longitude = 31.08306,
  location_accuracy = 13.5,
  address = COALESCE(address, 'تحت كوبري بركه السبع'),
  location_updated_at = now()
WHERE code = 'CUS-01485';
UPDATE customers 
SET 
  latitude = 30.636978,
  longitude = 31.10028,
  location_accuracy = 77.6,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01467';
UPDATE customers 
SET 
  latitude = 30.63686,
  longitude = 31.087597,
  location_accuracy = 20.9,
  address = COALESCE(address, 'تحت كوبري بركه السبع'),
  location_updated_at = now()
WHERE code = 'CUS-01468';
UPDATE customers 
SET 
  latitude = 30.5591,
  longitude = 31.019703,
  location_accuracy = 19.9,
  address = COALESCE(address, 'شارع الكليات امام تربيه رياضيه'),
  location_updated_at = now()
WHERE code = 'CUS-01407';
UPDATE customers 
SET 
  latitude = 30.5669,
  longitude = 31.00934,
  location_accuracy = 14.3,
  address = COALESCE(address, 'شبين الكوم'),
  location_updated_at = now()
WHERE code = 'CUS-01469';
UPDATE customers 
SET 
  latitude = 30.476757,
  longitude = 31.183779,
  location_accuracy = 41.8,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01462';
UPDATE customers 
SET 
  latitude = 30.465624,
  longitude = 31.190678,
  location_accuracy = 17.4,
  address = COALESCE(address, 'بنها'),
  location_updated_at = now()
WHERE code = 'CUS-01498';
UPDATE customers 
SET 
  latitude = 30.463104,
  longitude = 31.186304,
  location_accuracy = 9.5,
  address = COALESCE(address, 'بنها كليه علوم'),
  location_updated_at = now()
WHERE code = 'CUS-01463';
UPDATE customers 
SET 
  latitude = 31.035011,
  longitude = 30.456219,
  location_accuracy = 33.9,
  address = COALESCE(address, 'المحافظه'),
  location_updated_at = now()
WHERE code = 'CUS-01479';
UPDATE customers 
SET 
  latitude = 31.110758,
  longitude = 30.969088,
  location_accuracy = 10.0,
  address = COALESCE(address, 'كفر الشيخ الكوبري الازرق'),
  location_updated_at = now()
WHERE code = 'CUS-01310';
UPDATE customers 
SET 
  latitude = 30.962578,
  longitude = 30.958054,
  location_accuracy = 6.8,
  address = COALESCE(address, 'قطوار بجوار محمد مجدي'),
  location_updated_at = now()
WHERE code = 'CUS-00908';
UPDATE customers 
SET 
  latitude = 31.20862,
  longitude = 29.92506,
  location_accuracy = 18.5,
  address = COALESCE(address, 'الازاريطه'),
  location_updated_at = now()
WHERE code = 'CUS-01453';
UPDATE customers 
SET 
  latitude = 31.200357,
  longitude = 29.895285,
  location_accuracy = 8.7,
  address = COALESCE(address, 'قبل مكتبه الاسكندريه'),
  location_updated_at = now()
WHERE code = 'CUS-01457';
UPDATE customers 
SET 
  latitude = 30.791573,
  longitude = 30.973663,
  location_accuracy = 23.4,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01470';
UPDATE customers 
SET 
  latitude = 30.517288,
  longitude = 31.297026,
  location_accuracy = 14.3,
  address = COALESCE(address, 'الولجه'),
  location_updated_at = now()
WHERE code = 'CUS-01392';
UPDATE customers 
SET 
  latitude = 31.43311,
  longitude = 31.796028,
  location_accuracy = 28.2,
  address = COALESCE(address, 'دمياط القديمه'),
  location_updated_at = now()
WHERE code = 'CUS-01493';
UPDATE customers 
SET 
  latitude = 31.42329,
  longitude = 31.803032,
  location_accuracy = 23.7,
  address = COALESCE(address, 'عند موقف دمياط القديمه'),
  location_updated_at = now()
WHERE code = 'CUS-01495';
UPDATE customers 
SET 
  latitude = 31.117697,
  longitude = 30.949724,
  location_accuracy = 13.73,
  address = COALESCE(address, 'ش ٤٧ امام معرض عادل قادومه'),
  location_updated_at = now()
WHERE code = 'CUS-01363';
UPDATE customers 
SET 
  latitude = 31.2502,
  longitude = 30.021753,
  location_accuracy = 2.0,
  address = COALESCE(address, 'الطريق الدولي'),
  location_updated_at = now()
WHERE code = 'CUS-01461';
UPDATE customers 
SET 
  latitude = 30.970257,
  longitude = 30.962273,
  location_accuracy = 28.442,
  address = COALESCE(address, 'شارع  البنك الاهلي'),
  location_updated_at = now()
WHERE code = 'CUS-00952';
UPDATE customers 
SET 
  latitude = 31.251204,
  longitude = 30.02164,
  location_accuracy = 9.648,
  address = COALESCE(address, 'مدخل ش ٤٥ من الدولي'),
  location_updated_at = now()
WHERE code = 'CUS-01435';
UPDATE customers 
SET 
  latitude = 31.136374,
  longitude = 30.135101,
  location_accuracy = 15.4,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01474';
UPDATE customers 
SET 
  latitude = 31.136646,
  longitude = 30.132437,
  location_accuracy = 13.3,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01473';
UPDATE customers 
SET 
  latitude = 30.70155,
  longitude = 31.249292,
  location_accuracy = 26.9,
  address = COALESCE(address, 'دقدوس'),
  location_updated_at = now()
WHERE code = 'CUS-00975';
UPDATE customers 
SET 
  latitude = 30.807425,
  longitude = 30.998476,
  location_accuracy = 11.3,
  address = COALESCE(address, 'طنطا الطريق السريع بجوار bm لتأجير السيارات'),
  location_updated_at = now()
WHERE code = 'CUS-01341';
UPDATE customers 
SET 
  latitude = 30.563211,
  longitude = 31.451958,
  location_accuracy = 7.7,
  address = COALESCE(address, 'الزقازيق'),
  location_updated_at = now()
WHERE code = 'CUS-01490';
UPDATE customers 
SET 
  latitude = 30.612259,
  longitude = 31.468594,
  location_accuracy = 15.6,
  address = COALESCE(address, 'مدينه القنايات الزقازيق'),
  location_updated_at = now()
WHERE code = 'CUS-01361';
UPDATE customers 
SET 
  latitude = 30.594774,
  longitude = 31.499056,
  location_accuracy = 16.1,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01491';
UPDATE customers 
SET 
  latitude = 30.950111,
  longitude = 31.15591,
  location_accuracy = 39.319,
  address = COALESCE(address, 'المحلة'),
  location_updated_at = now()
WHERE code = 'CUS-01141';
UPDATE customers 
SET 
  latitude = 30.607435,
  longitude = 30.998816,
  location_accuracy = 14.0,
  address = COALESCE(address, 'امام ماستر الوطنيه'),
  location_updated_at = now()
WHERE code = 'CUS-01486';
UPDATE customers 
SET 
  latitude = 30.48301,
  longitude = 31.18359,
  location_accuracy = 23.2,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01481';
UPDATE customers 
SET 
  latitude = 30.477537,
  longitude = 31.182756,
  location_accuracy = 24.16,
  address = COALESCE(address, 'بنها ش الفلل  جانب مسجد ابراج الزهور'),
  location_updated_at = now()
WHERE code = 'CUS-00013';
UPDATE customers 
SET 
  latitude = 30.466774,
  longitude = 31.189928,
  location_accuracy = 19.9,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01482';
UPDATE customers 
SET 
  latitude = 30.468464,
  longitude = 31.187313,
  location_accuracy = 11.7,
  address = COALESCE(address, 'الاستاد'),
  location_updated_at = now()
WHERE code = 'CUS-01483';
UPDATE customers 
SET 
  latitude = 31.030613,
  longitude = 30.457888,
  location_accuracy = 23.9,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01476';
UPDATE customers 
SET 
  latitude = 31.034468,
  longitude = 30.455116,
  location_accuracy = 30.0,
  address = COALESCE(address, 'المحافظه'),
  location_updated_at = now()
WHERE code = 'CUS-01478';
UPDATE customers 
SET 
  latitude = 31.046057,
  longitude = 30.460714,
  location_accuracy = 3.8,
  address = COALESCE(address, 'شارع الطاهر'),
  location_updated_at = now()
WHERE code = 'CUS-01480';
UPDATE customers 
SET 
  latitude = 31.126022,
  longitude = 30.124289,
  location_accuracy = 30.6,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01472';
UPDATE customers 
SET 
  latitude = 31.13001,
  longitude = 30.12502,
  location_accuracy = 22.115,
  address = COALESCE(address, 'ش الموقف'),
  location_updated_at = now()
WHERE code = 'CUS-00280';
UPDATE customers 
SET 
  latitude = 31.139381,
  longitude = 30.127714,
  location_accuracy = 23.4,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01475';
UPDATE customers 
SET 
  latitude = 30.792038,
  longitude = 30.98449,
  location_accuracy = 18.2,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00525';
UPDATE customers 
SET 
  latitude = 31.43025,
  longitude = 31.796934,
  location_accuracy = 41.0,
  address = COALESCE(address, 'ش الحربي عند مغسلة وائل عبد المنعم .. العنوان الجديد : طريق راس البر الجديد من البحر , دخلت الشيخ سليم'),
  location_updated_at = now()
WHERE code = 'CUS-00249';
UPDATE customers 
SET 
  latitude = 31.421846,
  longitude = 31.799093,
  location_accuracy = 27.3,
  address = COALESCE(address, 'دمياط القديمه امام حديقه الطفل'),
  location_updated_at = now()
WHERE code = 'CUS-01422';
UPDATE customers 
SET 
  latitude = 30.476105,
  longitude = 31.169497,
  location_accuracy = 14.7,
  address = COALESCE(address, 'بنها'),
  location_updated_at = now()
WHERE code = 'CUS-01437';
UPDATE customers 
SET 
  latitude = 30.953226,
  longitude = 30.959507,
  location_accuracy = 24.0,
  address = COALESCE(address, 'قطور'),
  location_updated_at = now()
WHERE code = 'CUS-01466';
UPDATE customers 
SET 
  latitude = 31.265688,
  longitude = 30.028542,
  location_accuracy = 19.3,
  address = COALESCE(address, 'المنتزه'),
  location_updated_at = now()
WHERE code = 'CUS-01460';
UPDATE customers 
SET 
  latitude = 31.265228,
  longitude = 30.028755,
  location_accuracy = 42.232,
  address = COALESCE(address, 'بعد قسم ثالت المتزة عاليمين'),
  location_updated_at = now()
WHERE code = 'CUS-01434';
UPDATE customers 
SET 
  latitude = 30.763203,
  longitude = 30.707233,
  location_accuracy = 14.1,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01451';
UPDATE customers 
SET 
  latitude = 30.78847,
  longitude = 30.999496,
  location_accuracy = 45.024,
  address = COALESCE(address, 'بنزينة اول احمد ماهر'),
  location_updated_at = now()
WHERE code = 'CUS-01145';
UPDATE customers 
SET 
  latitude = 30.991802,
  longitude = 31.16566,
  location_accuracy = 10.3,
  address = COALESCE(address, 'دائري المحله'),
  location_updated_at = now()
WHERE code = 'CUS-01447';
UPDATE customers 
SET 
  latitude = 31.129782,
  longitude = 30.12623,
  location_accuracy = 30.1,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01443';
UPDATE customers 
SET 
  latitude = 31.032448,
  longitude = 31.36663,
  location_accuracy = 20.8,
  address = COALESCE(address, 'المنصوره حي الجامعه'),
  location_updated_at = now()
WHERE code = 'CUS-01439';
UPDATE customers 
SET 
  latitude = 31.237352,
  longitude = 29.999464,
  location_accuracy = 12.5,
  address = COALESCE(address, 'السيوف قبلي'),
  location_updated_at = now()
WHERE code = 'CUS-01430';
UPDATE customers 
SET 
  latitude = 31.253132,
  longitude = 30.000788,
  location_accuracy = 9.648,
  address = COALESCE(address, 'ش الامام المهدي من ش ٣٠ القديم سيدي بشر قبلي'),
  location_updated_at = now()
WHERE code = 'CUS-01432';
UPDATE customers 
SET 
  latitude = 30.769142,
  longitude = 31.048082,
  location_accuracy = 20.0,
  address = COALESCE(address, 'سبطاس بعد بنزينه سبطاس'),
  location_updated_at = now()
WHERE code = 'CUS-01426';
UPDATE customers 
SET 
  latitude = 31.26569,
  longitude = 30.020462,
  location_accuracy = 11.792,
  address = COALESCE(address, 'اسكندريه ٣٠ ش المندره قبلى'),
  location_updated_at = now()
WHERE code = 'CUS-01433';
UPDATE customers 
SET 
  latitude = 31.443716,
  longitude = 31.666468,
  location_accuracy = 21.4,
  address = COALESCE(address, 'دمياط الجديده شارع 13'),
  location_updated_at = now()
WHERE code = 'CUS-01420';
UPDATE customers 
SET 
  latitude = 31.423508,
  longitude = 31.803648,
  location_accuracy = 56.1,
  address = COALESCE(address, 'محمد ابو موسي'),
  location_updated_at = now()
WHERE code = 'CUS-01421';
UPDATE customers 
SET 
  latitude = 31.111534,
  longitude = 30.951275,
  location_accuracy = 17.8,
  address = COALESCE(address, 'كفر الشيخ شارع المصنع'),
  location_updated_at = now()
WHERE code = 'CUS-00787';
UPDATE customers 
SET 
  latitude = 31.108738,
  longitude = 30.970139,
  location_accuracy = 41.7,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01009';
UPDATE customers 
SET 
  latitude = 30.578157,
  longitude = 30.709269,
  location_accuracy = 41.363,
  address = COALESCE(address, 'مركز بدر 40 ش جمال عبد الناصر بجوار بنك مصر'),
  location_updated_at = now()
WHERE code = 'CUS-00567';
UPDATE customers 
SET 
  latitude = 30.782259,
  longitude = 31.00496,
  location_accuracy = 14.2,
  address = COALESCE(address, 'شارع الجنبيه'),
  location_updated_at = now()
WHERE code = 'CUS-01415';
UPDATE customers 
SET 
  latitude = 30.790531,
  longitude = 30.982796,
  location_accuracy = 18.991,
  address = COALESCE(address, 'مصطفى كامل'),
  location_updated_at = now()
WHERE code = 'CUS-00065';
UPDATE customers 
SET 
  latitude = 30.799845,
  longitude = 31.009708,
  location_accuracy = 14.7,
  address = COALESCE(address, 'المرشحه امام كافتيريا زيزينيا _ البر الثاني'),
  location_updated_at = now()
WHERE code = 'CUS-01274';
UPDATE customers 
SET 
  latitude = 30.803558,
  longitude = 31.007782,
  location_accuracy = 9.648,
  address = COALESCE(address, 'الكورنيش امتداد الاشرف'),
  location_updated_at = now()
WHERE code = 'CUS-01168';
UPDATE customers 
SET 
  latitude = 30.796227,
  longitude = 31.013638,
  location_accuracy = 60.1,
  address = COALESCE(address, 'ش كلية الزراعة'),
  location_updated_at = now()
WHERE code = 'CUS-01001';
UPDATE customers 
SET 
  latitude = 31.425076,
  longitude = 31.796272,
  location_accuracy = 24.7,
  address = COALESCE(address, 'دمياط القديمه شارع مركز شباب امام ابو النصر للادوات الصحيه'),
  location_updated_at = now()
WHERE code = 'CUS-01411';
UPDATE customers 
SET 
  latitude = 30.477596,
  longitude = 31.183723,
  location_accuracy = 15.201,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00979';
UPDATE customers 
SET 
  latitude = 30.477623,
  longitude = 31.183672,
  location_accuracy = 15.232,
  address = COALESCE(address, 'منطقة الفلل'),
  location_updated_at = now()
WHERE code = 'CUS-00001';
UPDATE customers 
SET 
  latitude = 30.567095,
  longitude = 31.005075,
  location_accuracy = 22.1,
  address = COALESCE(address, 'ش باريس'),
  location_updated_at = now()
WHERE code = 'CUS-01238';
UPDATE customers 
SET 
  latitude = 30.787014,
  longitude = 31.001904,
  location_accuracy = 11.7,
  address = COALESCE(address, 'امام بنزينه total energies'),
  location_updated_at = now()
WHERE code = 'CUS-01405';
UPDATE customers 
SET 
  latitude = 30.572487,
  longitude = 30.706331,
  location_accuracy = 32.6,
  address = COALESCE(address, 'مركز بدر مركز الشباب'),
  location_updated_at = now()
WHERE code = 'CUS-01365';
UPDATE customers 
SET 
  latitude = 30.973469,
  longitude = 31.182497,
  location_accuracy = 13.5,
  address = COALESCE(address, 'ابو شاهين / بجوار صيديله الاهرام'),
  location_updated_at = now()
WHERE code = 'CUS-01284';
UPDATE customers 
SET 
  latitude = 30.948145,
  longitude = 31.158337,
  location_accuracy = 33.6,
  address = COALESCE(address, 'منشبه البكري'),
  location_updated_at = now()
WHERE code = 'CUS-01402';
UPDATE customers 
SET 
  latitude = 31.028011,
  longitude = 31.391273,
  location_accuracy = 21.3,
  address = COALESCE(address, 'شارع نقابه الاطباء'),
  location_updated_at = now()
WHERE code = 'CUS-01234';
UPDATE customers 
SET 
  latitude = 30.47193,
  longitude = 31.180487,
  location_accuracy = 3.8,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01397';
UPDATE customers 
SET 
  latitude = 30.477854,
  longitude = 31.184227,
  location_accuracy = 19.5,
  address = COALESCE(address, 'شارع الفلل'),
  location_updated_at = now()
WHERE code = 'CUS-01258';
UPDATE customers 
SET 
  latitude = 31.0435,
  longitude = 30.458464,
  location_accuracy = 13.4,
  address = COALESCE(address, 'دمنهور شارع الفكريه'),
  location_updated_at = now()
WHERE code = 'CUS-01396';
UPDATE customers 
SET 
  latitude = 30.724575,
  longitude = 31.257792,
  location_accuracy = 14.087,
  address = COALESCE(address, 'جسر النيل بجوار كافيه دهب'),
  location_updated_at = now()
WHERE code = 'CUS-00134';
UPDATE customers 
SET 
  latitude = 30.59214,
  longitude = 31.4996,
  location_accuracy = 13.6,
  address = COALESCE(address, 'ش جمال عبد الناصر'),
  location_updated_at = now()
WHERE code = 'CUS-01338';
UPDATE customers 
SET 
  latitude = 30.49988,
  longitude = 31.288956,
  location_accuracy = 10.3,
  address = COALESCE(address, 'العزيزية'),
  location_updated_at = now()
WHERE code = 'CUS-01133';
UPDATE customers 
SET 
  latitude = 31.424908,
  longitude = 31.661932,
  location_accuracy = 16.5,
  address = COALESCE(address, 'دمياط الجديده شارع المرور'),
  location_updated_at = now()
WHERE code = 'CUS-01388';
UPDATE customers 
SET 
  latitude = 30.79973,
  longitude = 30.875595,
  location_accuracy = 16.2,
  address = COALESCE(address, 'كفر ديما بجوار سهريج المياه'),
  location_updated_at = now()
WHERE code = 'CUS-01272';
UPDATE customers 
SET 
  latitude = 30.457073,
  longitude = 31.195375,
  location_accuracy = 9.2,
  address = COALESCE(address, 'بنها'),
  location_updated_at = now()
WHERE code = 'CUS-01370';
UPDATE customers 
SET 
  latitude = 31.029491,
  longitude = 31.37009,
  location_accuracy = 15.0,
  address = COALESCE(address, 'المنصوره حي الجامعه'),
  location_updated_at = now()
WHERE code = 'CUS-01390';
UPDATE customers 
SET 
  latitude = 30.98312,
  longitude = 30.96946,
  location_accuracy = 10.0,
  address = COALESCE(address, 'كورنيش قحافه -اول شارع الورش'),
  location_updated_at = now()
WHERE code = 'CUS-01384';
UPDATE customers 
SET 
  latitude = 31.111794,
  longitude = 30.967932,
  location_accuracy = 73.196,
  address = COALESCE(address, 'كفر الشيخ دائرى المحله'),
  location_updated_at = now()
WHERE code = 'CUS-01302';
UPDATE customers 
SET 
  latitude = 31.13721,
  longitude = 30.12939,
  location_accuracy = 3.8,
  address = COALESCE(address, 'شارع الموقف جنب موقف العوائد'),
  location_updated_at = now()
WHERE code = 'CUS-01383';
UPDATE customers 
SET 
  latitude = 31.03181,
  longitude = 30.453259,
  location_accuracy = 14.1,
  address = COALESCE(address, 'دمنهور المحافظه'),
  location_updated_at = now()
WHERE code = 'CUS-01382';
UPDATE customers 
SET 
  latitude = 31.1378,
  longitude = 30.124454,
  location_accuracy = 24.6,
  address = COALESCE(address, 'كفر الدوار اول ش الحدايق'),
  location_updated_at = now()
WHERE code = 'CUS-01378';
UPDATE customers 
SET 
  latitude = 30.571022,
  longitude = 30.71318,
  location_accuracy = 3.9,
  address = COALESCE(address, 'مركز بدر ش احمد حسنين منطقة ارض الجمعية'),
  location_updated_at = now()
WHERE code = 'CUS-00570';
UPDATE customers 
SET 
  latitude = 30.802639,
  longitude = 31.004183,
  location_accuracy = 40.378,
  address = COALESCE(address, 'طنطا - اخر سعيد بجوار شبكة المياه'),
  location_updated_at = now()
WHERE code = 'CUS-01007';
UPDATE customers 
SET 
  latitude = 31.059969,
  longitude = 31.40574,
  location_accuracy = 17.844,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01124';
UPDATE customers 
SET 
  latitude = 31.032177,
  longitude = 31.356627,
  location_accuracy = 14.7,
  address = COALESCE(address, 'حي الجامعه شارع جيهان'),
  location_updated_at = now()
WHERE code = 'CUS-01320';
UPDATE customers 
SET 
  latitude = 30.936338,
  longitude = 30.811262,
  location_accuracy = 3.216,
  address = COALESCE(address, 'بسيون خلف المرور'),
  location_updated_at = now()
WHERE code = 'CUS-01334';
UPDATE customers 
SET 
  latitude = 30.790968,
  longitude = 31.01451,
  location_accuracy = 35.5,
  address = COALESCE(address, 'الكورنيش بعد مزلقان الجميل ( شغال سجاد اكتر )'),
  location_updated_at = now()
WHERE code = 'CUS-01380';
UPDATE customers 
SET 
  latitude = 30.987686,
  longitude = 31.176416,
  location_accuracy = 19.9,
  address = COALESCE(address, 'شارع المستشار متداد البان الكابتن'),
  location_updated_at = now()
WHERE code = 'CUS-00034';
UPDATE customers 
SET 
  latitude = 30.478075,
  longitude = 31.180553,
  location_accuracy = 19.1,
  address = COALESCE(address, 'بنها الفلل'),
  location_updated_at = now()
WHERE code = 'CUS-01371';
UPDATE customers 
SET 
  latitude = 31.102886,
  longitude = 30.970589,
  location_accuracy = 20.7,
  address = COALESCE(address, 'كغر الشيخ دائري المحله'),
  location_updated_at = now()
WHERE code = 'CUS-01356';
UPDATE customers 
SET 
  latitude = 30.792871,
  longitude = 30.980356,
  location_accuracy = 12.421,
  address = COALESCE(address, 'سوق الجملة'),
  location_updated_at = now()
WHERE code = 'CUS-00858';
UPDATE customers 
SET 
  latitude = 30.795513,
  longitude = 31.00773,
  location_accuracy = 18.093,
  address = COALESCE(address, 'امتداد الاشرف مع مصطفي ماهر'),
  location_updated_at = now()
WHERE code = 'CUS-01159';
UPDATE customers 
SET 
  latitude = 31.044107,
  longitude = 30.459251,
  location_accuracy = 14.1,
  address = COALESCE(address, 'دمنهور'),
  location_updated_at = now()
WHERE code = 'CUS-01263';
UPDATE customers 
SET 
  latitude = 31.129745,
  longitude = 30.125666,
  location_accuracy = 65.0,
  address = COALESCE(address, 'شارع بولس جنب مغسلة fresh car'),
  location_updated_at = now()
WHERE code = 'CUS-01324';
UPDATE customers 
SET 
  latitude = 30.944834,
  longitude = 31.150036,
  location_accuracy = 15.1,
  address = COALESCE(address, 'منشيه البكري'),
  location_updated_at = now()
WHERE code = 'CUS-01358';
UPDATE customers 
SET 
  latitude = 30.578224,
  longitude = 30.709198,
  location_accuracy = 22.4,
  address = COALESCE(address, 'مركز بدر'),
  location_updated_at = now()
WHERE code = 'CUS-01354';
UPDATE customers 
SET 
  latitude = 30.947971,
  longitude = 31.15915,
  location_accuracy = 67.796,
  address = COALESCE(address, 'المنشيه بعد جراج حجازي'),
  location_updated_at = now()
WHERE code = 'CUS-01359';
UPDATE customers 
SET 
  latitude = 31.029337,
  longitude = 31.370659,
  location_accuracy = 15.3,
  address = COALESCE(address, 'المنصوره'),
  location_updated_at = now()
WHERE code = 'CUS-01357';
UPDATE customers 
SET 
  latitude = 31.029593,
  longitude = 30.45086,
  location_accuracy = 21.1,
  address = COALESCE(address, 'دمنهور _ شارع المحافظه'),
  location_updated_at = now()
WHERE code = 'CUS-01280';
UPDATE customers 
SET 
  latitude = 30.715322,
  longitude = 31.269108,
  location_accuracy = 30.1,
  address = COALESCE(address, 'ميت غمر  26 يوليو بجوار المحكمه'),
  location_updated_at = now()
WHERE code = 'CUS-01344';
UPDATE customers 
SET 
  latitude = 30.716215,
  longitude = 31.26973,
  location_accuracy = 32.0,
  address = COALESCE(address, 'شارع المعاهده بجوار جراند كافيه'),
  location_updated_at = now()
WHERE code = 'CUS-01343';
UPDATE customers 
SET 
  latitude = 30.88844,
  longitude = 30.675484,
  location_accuracy = 2.2,
  address = COALESCE(address, 'ايتاي البارود اول طريقه البريد'),
  location_updated_at = now()
WHERE code = 'CUS-01336';
UPDATE customers 
SET 
  latitude = 30.573145,
  longitude = 31.477896,
  location_accuracy = 32.005,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00224';
UPDATE customers 
SET 
  latitude = 30.476755,
  longitude = 31.18351,
  location_accuracy = 15.7,
  address = COALESCE(address, 'بنها ش الفلل'),
  location_updated_at = now()
WHERE code = 'CUS-01298';
UPDATE customers 
SET 
  latitude = 31.104446,
  longitude = 30.969984,
  location_accuracy = 8.6,
  address = COALESCE(address, 'دائري المحلة'),
  location_updated_at = now()
WHERE code = 'CUS-00618';
UPDATE customers 
SET 
  latitude = 31.030647,
  longitude = 30.456532,
  location_accuracy = 16.106,
  address = COALESCE(address, 'ش المعهد الديني'),
  location_updated_at = now()
WHERE code = 'CUS-01052';
UPDATE customers 
SET 
  latitude = 31.148678,
  longitude = 30.128088,
  location_accuracy = 24.993,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00341';
UPDATE customers 
SET 
  latitude = 30.386995,
  longitude = 30.930168,
  location_accuracy = 16.002,
  address = COALESCE(address, 'اشمون'),
  location_updated_at = now()
WHERE code = 'CUS-01323';
UPDATE customers 
SET 
  latitude = 30.782911,
  longitude = 31.006397,
  location_accuracy = 40.231,
  address = COALESCE(address, 'طريق الجلاء بجوار ميمي للمشويات ( مش شغال )'),
  location_updated_at = now()
WHERE code = 'CUS-00143';
UPDATE customers 
SET 
  latitude = 30.57286,
  longitude = 31.476841,
  location_accuracy = 18.9,
  address = COALESCE(address, 'الزقازيق قبل الكوبرى'),
  location_updated_at = now()
WHERE code = 'CUS-01210';
UPDATE customers 
SET 
  latitude = 30.950104,
  longitude = 31.155933,
  location_accuracy = 15.821,
  address = COALESCE(address, 'منشية البكري \ شارع 55 عمار بن ياسر امام كافيه فنيسيا'),
  location_updated_at = now()
WHERE code = 'CUS-00036';
UPDATE customers 
SET 
  latitude = 30.818804,
  longitude = 30.834524,
  location_accuracy = 24.437,
  address = COALESCE(address, 'الزراعي بعد كوبري الدلجمون اتجاه اسكندريه'),
  location_updated_at = now()
WHERE code = 'CUS-01317';
UPDATE customers 
SET 
  latitude = 30.817862,
  longitude = 30.831722,
  location_accuracy = 7.8,
  address = COALESCE(address, 'كفر الزيات قبل النفق'),
  location_updated_at = now()
WHERE code = 'CUS-01316';
UPDATE customers 
SET 
  latitude = 30.887463,
  longitude = 30.830269,
  location_accuracy = 8.4,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01315';
UPDATE customers 
SET 
  latitude = 31.150032,
  longitude = 30.126266,
  location_accuracy = 65.0,
  address = COALESCE(address, '01270897087'),
  location_updated_at = now()
WHERE code = 'CUS-01312';
UPDATE customers 
SET 
  latitude = 30.777975,
  longitude = 31.01884,
  location_accuracy = 64.692,
  address = COALESCE(address, 'ميت حبيش البحريه عالطريق'),
  location_updated_at = now()
WHERE code = 'CUS-01211';
UPDATE customers 
SET 
  latitude = 31.212576,
  longitude = 30.007708,
  location_accuracy = 8.6,
  address = COALESCE(address, 'المنتزه - منطقه المهاجرين خلف الاسعاف و مركز خدمات البيد'),
  location_updated_at = now()
WHERE code = 'CUS-01231';
UPDATE customers 
SET 
  latitude = 31.04382,
  longitude = 30.476082,
  location_accuracy = 17.395,
  address = COALESCE(address, 'دمنهور طاموس'),
  location_updated_at = now()
WHERE code = 'CUS-00170';
UPDATE customers 
SET 
  latitude = 30.807587,
  longitude = 30.996,
  location_accuracy = 18.4,
  address = COALESCE(address, 'طنطا بجوار جيفال'),
  location_updated_at = now()
WHERE code = 'CUS-01049';
UPDATE customers 
SET 
  latitude = 30.788933,
  longitude = 31.016075,
  location_accuracy = 65.0,
  address = COALESCE(address, 'السلخانة القديمة'),
  location_updated_at = now()
WHERE code = 'CUS-01247';
UPDATE customers 
SET 
  latitude = 31.03829,
  longitude = 30.47448,
  location_accuracy = 32.005,
  address = COALESCE(address, 'دمنهور ش ابو عبد الله'),
  location_updated_at = now()
WHERE code = 'CUS-01303';
UPDATE customers 
SET 
  latitude = 30.8059,
  longitude = 31.010687,
  location_accuracy = 18.973,
  address = COALESCE(address, 'طنطا عند كوبري الغفران'),
  location_updated_at = now()
WHERE code = 'CUS-01096';
UPDATE customers 
SET 
  latitude = 30.975153,
  longitude = 30.949425,
  location_accuracy = 37.361,
  address = COALESCE(address, 'قطور'),
  location_updated_at = now()
WHERE code = 'CUS-01164';
UPDATE customers 
SET 
  latitude = 31.104774,
  longitude = 30.93985,
  location_accuracy = 15.5,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00733';
UPDATE customers 
SET 
  latitude = 31.107439,
  longitude = 30.929977,
  location_accuracy = 28.6,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00651';
UPDATE customers 
SET 
  latitude = 31.111748,
  longitude = 30.968218,
  location_accuracy = 11.8,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00375';
UPDATE customers 
SET 
  latitude = 31.109877,
  longitude = 30.970009,
  location_accuracy = 65.0,
  address = COALESCE(address, 'دولى المحله ( الكوبرى الازرق)'),
  location_updated_at = now()
WHERE code = 'CUS-01301';
UPDATE customers 
SET 
  latitude = 30.478014,
  longitude = 31.180632,
  location_accuracy = 18.1,
  address = COALESCE(address, 'بنها ش الفلل ش ١٠'),
  location_updated_at = now()
WHERE code = 'CUS-01296';
UPDATE customers 
SET 
  latitude = 31.022943,
  longitude = 30.458094,
  location_accuracy = 39.6,
  address = COALESCE(address, 'مركز صيانة'),
  location_updated_at = now()
WHERE code = 'CUS-00159';
UPDATE customers 
SET 
  latitude = 30.724556,
  longitude = 31.258957,
  location_accuracy = 28.129,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00135';
UPDATE customers 
SET 
  latitude = 30.711939,
  longitude = 31.239983,
  location_accuracy = 16.3,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00146';
UPDATE customers 
SET 
  latitude = 30.71716,
  longitude = 31.025864,
  location_accuracy = 23.486,
  address = COALESCE(address, 'دفرة طرييق شبين'),
  location_updated_at = now()
WHERE code = 'CUS-01032';
UPDATE customers 
SET 
  latitude = 30.569902,
  longitude = 31.003723,
  location_accuracy = 14.72,
  address = COALESCE(address, 'ش باريس'),
  location_updated_at = now()
WHERE code = 'CUS-01174';
UPDATE customers 
SET 
  latitude = 30.58961,
  longitude = 31.492393,
  location_accuracy = 2.5,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00402';
UPDATE customers 
SET 
  latitude = 30.709036,
  longitude = 31.236217,
  location_accuracy = 22.8,
  address = COALESCE(address, 'اخر شارع المطافي'),
  location_updated_at = now()
WHERE code = 'CUS-00932';
UPDATE customers 
SET 
  latitude = 31.14863,
  longitude = 30.128359,
  location_accuracy = 29.202,
  address = COALESCE(address, 'منطقة التمليك'),
  location_updated_at = now()
WHERE code = 'CUS-00314';
UPDATE customers 
SET 
  latitude = 30.606812,
  longitude = 31.476147,
  location_accuracy = 1000.0,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00387';
UPDATE customers 
SET 
  latitude = 30.880375,
  longitude = 31.082476,
  location_accuracy = 68.397,
  address = COALESCE(address, 'محلة رووح'),
  location_updated_at = now()
WHERE code = 'CUS-00911';
UPDATE customers 
SET 
  latitude = 30.889654,
  longitude = 30.670086,
  location_accuracy = 18.4,
  address = COALESCE(address, 'ايتاي البارود بجانب وان تاتش ايتاي'),
  location_updated_at = now()
WHERE code = 'CUS-01282';
UPDATE customers 
SET 
  latitude = 30.89341,
  longitude = 30.667862,
  location_accuracy = 1.9,
  address = COALESCE(address, 'ايتاي البارود بجوار الحضانه'),
  location_updated_at = now()
WHERE code = 'CUS-01273';
UPDATE customers 
SET 
  latitude = 30.82058,
  longitude = 31.007282,
  location_accuracy = 25.17,
  address = COALESCE(address, 'سبرباي أمام ابن حميدو للاسماك قبل المرور'),
  location_updated_at = now()
WHERE code = 'CUS-01255';
UPDATE customers 
SET 
  latitude = 30.79015,
  longitude = 30.99149,
  location_accuracy = 24.2,
  address = COALESCE(address, 'علي مبارك'),
  location_updated_at = now()
WHERE code = 'CUS-00879';
UPDATE customers 
SET 
  latitude = 30.962563,
  longitude = 30.957987,
  location_accuracy = 31.601,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00455';
UPDATE customers 
SET 
  latitude = 30.778698,
  longitude = 31.023952,
  location_accuracy = 46.709,
  address = COALESCE(address, 'ميت حبيش بجوار مسجد العمدة'),
  location_updated_at = now()
WHERE code = 'CUS-01044';
UPDATE customers 
SET 
  latitude = 30.95081,
  longitude = 30.80074,
  location_accuracy = 10.0,
  address = COALESCE(address, 'بسيون 23 يوليو امام شركة الكهرباء'),
  location_updated_at = now()
WHERE code = 'CUS-01277';
UPDATE customers 
SET 
  latitude = 31.147507,
  longitude = 30.124168,
  location_accuracy = 36.824,
  address = COALESCE(address, 'كفر الدوار'),
  location_updated_at = now()
WHERE code = 'CUS-00722';
UPDATE customers 
SET 
  latitude = 30.858236,
  longitude = 31.059584,
  location_accuracy = 17.6,
  address = COALESCE(address, 'شبشير الحصه شارع داير الناحيه'),
  location_updated_at = now()
WHERE code = 'CUS-01226';
UPDATE customers 
SET 
  latitude = 30.804256,
  longitude = 31.00303,
  location_accuracy = 10.9,
  address = COALESCE(address, 'اخر شارع سعيد بجوار مغسله فايف ستار'),
  location_updated_at = now()
WHERE code = 'CUS-01275';
UPDATE customers 
SET 
  latitude = 30.476534,
  longitude = 31.180567,
  location_accuracy = 16.2,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00002';
UPDATE customers 
SET 
  latitude = 30.815964,
  longitude = 30.747227,
  location_accuracy = 57.42,
  address = COALESCE(address, 'شبرا النملة اتجاه الاسكندرية بجوار كافيه الزعيم قبل توكيل نيسان'),
  location_updated_at = now()
WHERE code = 'CUS-01271';
UPDATE customers 
SET 
  latitude = 30.975225,
  longitude = 30.953922,
  location_accuracy = 42.5,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01070';
UPDATE customers 
SET 
  latitude = 30.473269,
  longitude = 31.184103,
  location_accuracy = 15.817,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00870';
UPDATE customers 
SET 
  latitude = 30.793095,
  longitude = 31.007929,
  location_accuracy = 34.853,
  address = COALESCE(address, 'ش توت عنخ امون'),
  location_updated_at = now()
WHERE code = 'CUS-00083';
UPDATE customers 
SET 
  latitude = 30.798246,
  longitude = 31.000984,
  location_accuracy = 16.7,
  address = COALESCE(address, 'اخر ش سعيد بجوار محل Cruch'),
  location_updated_at = now()
WHERE code = 'CUS-00087';
UPDATE customers 
SET 
  latitude = 30.9628,
  longitude = 31.164366,
  location_accuracy = 16.3,
  address = COALESCE(address, 'عمارات العربي'),
  location_updated_at = now()
WHERE code = 'CUS-01039';
UPDATE customers 
SET 
  latitude = 30.795158,
  longitude = 31.011625,
  location_accuracy = 17.903,
  address = COALESCE(address, 'الكورنيش)المرشحة امام كافيه البشوات'),
  location_updated_at = now()
WHERE code = 'CUS-00086';
UPDATE customers 
SET 
  latitude = 30.789667,
  longitude = 30.977537,
  location_accuracy = 9.6,
  address = COALESCE(address, 'اخر المعاهدة'),
  location_updated_at = now()
WHERE code = 'CUS-01165';
UPDATE customers 
SET 
  latitude = 30.952005,
  longitude = 31.152676,
  location_accuracy = 25.742,
  address = COALESCE(address, 'جمال عبد الناصرعمارة الشركة'),
  location_updated_at = now()
WHERE code = 'CUS-01349';
UPDATE customers 
SET 
  latitude = 30.793806,
  longitude = 30.987839,
  location_accuracy = 16.3,
  address = COALESCE(address, 'ش انور'),
  location_updated_at = now()
WHERE code = 'CUS-01267';
UPDATE customers 
SET 
  latitude = 30.521397,
  longitude = 31.354982,
  location_accuracy = 33.937,
  address = COALESCE(address, 'منيا القمح امام مدرسة جمال عبد الناصر'),
  location_updated_at = now()
WHERE code = 'CUS-00582';
UPDATE customers 
SET 
  latitude = 31.029707,
  longitude = 30.450823,
  location_accuracy = 14.6,
  address = COALESCE(address, 'شارع المحافظة تانى شارع يمين من السريع'),
  location_updated_at = now()
WHERE code = 'CUS-01075';
UPDATE customers 
SET 
  latitude = 31.126867,
  longitude = 30.123674,
  location_accuracy = 92.9,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01180';
UPDATE customers 
SET 
  latitude = 31.13473,
  longitude = 30.133892,
  location_accuracy = 53.851,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01155';
UPDATE customers 
SET 
  latitude = 31.129559,
  longitude = 30.135931,
  location_accuracy = 28.103,
  address = COALESCE(address, 'ش الجيش جنينه شارع الجيش'),
  location_updated_at = now()
WHERE code = 'CUS-01207';
UPDATE customers 
SET 
  latitude = 30.77962,
  longitude = 31.02122,
  location_accuracy = 28.1,
  address = COALESCE(address, 'ميت حبيش بجوار مركز شباب ميت حبيش'),
  location_updated_at = now()
WHERE code = 'CUS-01266';
UPDATE customers 
SET 
  latitude = 31.059675,
  longitude = 31.404339,
  location_accuracy = 13.437,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00837';
UPDATE customers 
SET 
  latitude = 31.059433,
  longitude = 31.40635,
  location_accuracy = 31.477,
  address = COALESCE(address, 'المنصورة شارع نور الاسلام'),
  location_updated_at = now()
WHERE code = 'CUS-00926';
UPDATE customers 
SET 
  latitude = 31.028633,
  longitude = 31.361498,
  location_accuracy = 8.5,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00194';
UPDATE customers 
SET 
  latitude = 30.798082,
  longitude = 30.98684,
  location_accuracy = 89.896,
  address = COALESCE(address, 'السريع بجوار هايبر مكة'),
  location_updated_at = now()
WHERE code = 'CUS-00903';
UPDATE customers 
SET 
  latitude = 30.788933,
  longitude = 30.976028,
  location_accuracy = 17.6,
  address = COALESCE(address, 'اخر المعاهده'),
  location_updated_at = now()
WHERE code = 'CUS-01262';
UPDATE customers 
SET 
  latitude = 30.792587,
  longitude = 30.98105,
  location_accuracy = 13.857,
  address = COALESCE(address, 'المعاهدة'),
  location_updated_at = now()
WHERE code = 'CUS-00862';
UPDATE customers 
SET 
  latitude = 30.473488,
  longitude = 31.168592,
  location_accuracy = 17.002,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00016';
UPDATE customers 
SET 
  latitude = 30.888657,
  longitude = 30.663858,
  location_accuracy = 25.833,
  address = COALESCE(address, 'ايتاي'),
  location_updated_at = now()
WHERE code = 'CUS-01109';
UPDATE customers 
SET 
  latitude = 31.20928,
  longitude = 29.923721,
  location_accuracy = 5.36,
  address = COALESCE(address, '2محمدفؤاد جلال خلف كلية الهندسة'),
  location_updated_at = now()
WHERE code = 'CUS-00440';
UPDATE customers 
SET 
  latitude = 31.207075,
  longitude = 29.882786,
  location_accuracy = 17.374,
  address = COALESCE(address, 'بحري'),
  location_updated_at = now()
WHERE code = 'CUS-00940';
UPDATE customers 
SET 
  latitude = 31.03246,
  longitude = 31.358658,
  location_accuracy = 18.404,
  address = COALESCE(address, 'شارع الواحه'),
  location_updated_at = now()
WHERE code = 'CUS-01233';
UPDATE customers 
SET 
  latitude = 30.804115,
  longitude = 30.991825,
  location_accuracy = 38.191,
  address = COALESCE(address, 'اول طريق شوبر'),
  location_updated_at = now()
WHERE code = 'CUS-01202';
UPDATE customers 
SET 
  latitude = 30.782679,
  longitude = 31.00716,
  location_accuracy = 30.057,
  address = COALESCE(address, 'اول الجلاء بجوار ميمي'),
  location_updated_at = now()
WHERE code = 'CUS-01078';
UPDATE customers 
SET 
  latitude = 30.800114,
  longitude = 30.915483,
  location_accuracy = 9.5,
  address = COALESCE(address, 'شبرا النملة'),
  location_updated_at = now()
WHERE code = 'CUS-00157';
UPDATE customers 
SET 
  latitude = 30.568577,
  longitude = 31.008518,
  location_accuracy = 19.948,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01172';
UPDATE customers 
SET 
  latitude = 30.795498,
  longitude = 31.007673,
  location_accuracy = 12.423,
  address = COALESCE(address, 'الاشرف بعد عبده الكتف'),
  location_updated_at = now()
WHERE code = 'CUS-01157';
UPDATE customers 
SET 
  latitude = 30.803537,
  longitude = 31.003387,
  location_accuracy = 7.1,
  address = COALESCE(address, 'اخر نايف عماد امام المطافي'),
  location_updated_at = now()
WHERE code = 'CUS-01256';
UPDATE customers 
SET 
  latitude = 30.730715,
  longitude = 31.113834,
  location_accuracy = 20.633,
  address = COALESCE(address, 'الطريق السريع امام الوحدة الزراعية'),
  location_updated_at = now()
WHERE code = 'CUS-00131';
UPDATE customers 
SET 
  latitude = 30.56902,
  longitude = 31.00138,
  location_accuracy = 35.694,
  address = COALESCE(address, 'ميدان الشهيد خلف بشاير الخير'),
  location_updated_at = now()
WHERE code = 'CUS-01252';
UPDATE customers 
SET 
  latitude = 31.03337,
  longitude = 30.478354,
  location_accuracy = 13.101,
  address = COALESCE(address, 'ش كوبري ابو الريش -دمنهور'),
  location_updated_at = now()
WHERE code = 'CUS-01167';
UPDATE customers 
SET 
  latitude = 31.044178,
  longitude = 30.459322,
  location_accuracy = 5.5,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00106';
UPDATE customers 
SET 
  latitude = 30.895258,
  longitude = 30.662104,
  location_accuracy = 24.6,
  address = COALESCE(address, 'شارع المدارس'),
  location_updated_at = now()
WHERE code = 'CUS-01251';
UPDATE customers 
SET 
  latitude = 31.139162,
  longitude = 30.126095,
  location_accuracy = 4.4,
  address = COALESCE(address, 'ش الحدائق كفر الدوار'),
  location_updated_at = now()
WHERE code = 'CUS-00656';
UPDATE customers 
SET 
  latitude = 31.245253,
  longitude = 29.991287,
  location_accuracy = 16.08,
  address = COALESCE(address, 'امتداد ش القاسم خلف فتح الله'),
  location_updated_at = now()
WHERE code = 'CUS-01249';
UPDATE customers 
SET 
  latitude = 31.2092,
  longitude = 29.924248,
  location_accuracy = 10.72,
  address = COALESCE(address, 'سيدي جابر ش المشير عند قهوة الفيشاوي//الابراهيمية 17 ش هليوبليس عند المعهد الفني التجاري'),
  location_updated_at = now()
WHERE code = 'CUS-00912';
UPDATE customers 
SET 
  latitude = 30.8134,
  longitude = 30.9838,
  location_accuracy = 22.6,
  address = COALESCE(address, 'طريق شوبر امام مصنع كوكاكولا'),
  location_updated_at = now()
WHERE code = 'CUS-01244';
UPDATE customers 
SET 
  latitude = 31.11653,
  longitude = 30.940413,
  location_accuracy = 3.786,
  address = COALESCE(address, 'كفر الشيخ'),
  location_updated_at = now()
WHERE code = 'CUS-00678';
UPDATE customers 
SET 
  latitude = 30.968739,
  longitude = 30.957315,
  location_accuracy = 17.59,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00955';
UPDATE customers 
SET 
  latitude = 30.704224,
  longitude = 31.246012,
  location_accuracy = 15.0,
  address = COALESCE(address, 'اول شارع المصرف'),
  location_updated_at = now()
WHERE code = 'CUS-01248';
UPDATE customers 
SET 
  latitude = 30.80741,
  longitude = 30.998878,
  location_accuracy = 16.289,
  address = COALESCE(address, 'قحافة خلف الاسعاف'),
  location_updated_at = now()
WHERE code = 'CUS-01150';
UPDATE customers 
SET 
  latitude = 30.947142,
  longitude = 31.154001,
  location_accuracy = 28.6,
  address = COALESCE(address, 'منشية البكري - 55 عمار بن ياسر امام الشارع شركة سما فيوتشر'),
  location_updated_at = now()
WHERE code = 'CUS-00023';
UPDATE customers 
SET 
  latitude = 30.946846,
  longitude = 31.154877,
  location_accuracy = 15.3,
  address = COALESCE(address, 'منشيه البكري ش عمار بن ياسر'),
  location_updated_at = now()
WHERE code = 'CUS-01246';
UPDATE customers 
SET 
  latitude = 30.946476,
  longitude = 31.148182,
  location_accuracy = 17.7,
  address = COALESCE(address, 'الشعبيه تاني شارع يمين بعد مستشفي الربيع'),
  location_updated_at = now()
WHERE code = 'CUS-01240';
UPDATE customers 
SET 
  latitude = 31.030703,
  longitude = 31.392618,
  location_accuracy = 17.842,
  address = COALESCE(address, 'المنصوره شارع الاستاد بجوار كارفور'),
  location_updated_at = now()
WHERE code = 'CUS-01245';
UPDATE customers 
SET 
  latitude = 30.792145,
  longitude = 30.98429,
  location_accuracy = 16.667,
  address = COALESCE(address, 'المعاهده امام السوبر جيت'),
  location_updated_at = now()
WHERE code = 'CUS-00739';
UPDATE customers 
SET 
  latitude = 30.608067,
  longitude = 31.475075,
  location_accuracy = 800.0,
  address = COALESCE(address, 'ش الامن الغذائي امام مخبز التعاون وايضا شارع المحافظة'),
  location_updated_at = now()
WHERE code = 'CUS-00234';
UPDATE customers 
SET 
  latitude = 30.780207,
  longitude = 30.988935,
  location_accuracy = 23.5,
  address = COALESCE(address, 'اخر سيجر خف المعهد الديني'),
  location_updated_at = now()
WHERE code = 'CUS-01243';
UPDATE customers 
SET 
  latitude = 31.426971,
  longitude = 31.558262,
  location_accuracy = 20.1,
  address = COALESCE(address, 'الدولي اول طريق جمصة'),
  location_updated_at = now()
WHERE code = 'CUS-01017';
UPDATE customers 
SET 
  latitude = 30.807405,
  longitude = 30.99841,
  location_accuracy = 17.3,
  address = COALESCE(address, 'بجوار الاسعاف قحافه'),
  location_updated_at = now()
WHERE code = 'CUS-01241';
UPDATE customers 
SET 
  latitude = 30.973951,
  longitude = 31.180813,
  location_accuracy = 20.9,
  address = COALESCE(address, 'ابو شاهين بجوار مكتب التأمينات'),
  location_updated_at = now()
WHERE code = 'CUS-01228';
UPDATE customers 
SET 
  latitude = 30.803112,
  longitude = 30.990852,
  location_accuracy = 23.6,
  address = COALESCE(address, 'اخر المعاهدة'),
  location_updated_at = now()
WHERE code = 'CUS-01161';
UPDATE customers 
SET 
  latitude = 31.117056,
  longitude = 30.949968,
  location_accuracy = 12.715,
  address = COALESCE(address, 'ش الحساينه متفرع من شالمصنع'),
  location_updated_at = now()
WHERE code = 'CUS-01197';
UPDATE customers 
SET 
  latitude = 31.128305,
  longitude = 30.136478,
  location_accuracy = 20.4,
  address = COALESCE(address, 'كفر الدوار شارع الجيش علي الطريق الزراعي'),
  location_updated_at = now()
WHERE code = 'CUS-00389';
UPDATE customers 
SET 
  latitude = 30.816938,
  longitude = 30.993298,
  location_accuracy = 19.296,
  address = COALESCE(address, 'الاستاد'),
  location_updated_at = now()
WHERE code = 'CUS-01196';
UPDATE customers 
SET 
  latitude = 31.02382,
  longitude = 31.370714,
  location_accuracy = 104.1,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00631';
UPDATE customers 
SET 
  latitude = 30.793488,
  longitude = 31.013268,
  location_accuracy = 33.878,
  address = COALESCE(address, 'ش عنتر بن شداد اما فتح الله دوران الاشرف'),
  location_updated_at = now()
WHERE code = 'CUS-00985';
UPDATE customers 
SET 
  latitude = 31.12626,
  longitude = 30.1472,
  location_accuracy = 135.6,
  address = COALESCE(address, 'كفر الدوار قبل المدخل الرئيسى'),
  location_updated_at = now()
WHERE code = 'CUS-01230';
UPDATE customers 
SET 
  latitude = 30.79446,
  longitude = 30.990894,
  location_accuracy = 14.9,
  address = COALESCE(address, 'شارع النجاشي خلف امن الدوله'),
  location_updated_at = now()
WHERE code = 'CUS-01229';
UPDATE customers 
SET 
  latitude = 30.98414,
  longitude = 31.177687,
  location_accuracy = 35.623,
  address = COALESCE(address, 'ابو راضي - ش عبدالرحمن شاهين'),
  location_updated_at = now()
WHERE code = 'CUS-01227';
UPDATE customers 
SET 
  latitude = 30.771715,
  longitude = 30.992336,
  location_accuracy = 19.8,
  address = COALESCE(address, 'اخر الحكمه بجوار مسجد مكه'),
  location_updated_at = now()
WHERE code = 'CUS-01223';
UPDATE customers 
SET 
  latitude = 31.032772,
  longitude = 31.35464,
  location_accuracy = 28.417,
  address = COALESCE(address, 'ش الجامعة'),
  location_updated_at = now()
WHERE code = 'CUS-00203';
UPDATE customers 
SET 
  latitude = 31.027597,
  longitude = 31.373138,
  location_accuracy = 16.46,
  address = COALESCE(address, 'شارع المطافى'),
  location_updated_at = now()
WHERE code = 'CUS-01225';
UPDATE customers 
SET 
  latitude = 30.909378,
  longitude = 30.896046,
  location_accuracy = 25.0,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01074';
UPDATE customers 
SET 
  latitude = 30.582037,
  longitude = 31.492208,
  location_accuracy = 15.573,
  address = COALESCE(address, 'حي الزهور ش اولاد جبر امام الريف المصري'),
  location_updated_at = now()
WHERE code = 'CUS-00226';
UPDATE customers 
SET 
  latitude = 30.799887,
  longitude = 31.009695,
  location_accuracy = 23.7,
  address = COALESCE(address, 'المرشحه امام كافيه اكسبريس'),
  location_updated_at = now()
WHERE code = 'CUS-01217';
UPDATE customers 
SET 
  latitude = 30.569271,
  longitude = 31.006094,
  location_accuracy = 12.87,
  address = COALESCE(address, 'ش باريس'),
  location_updated_at = now()
WHERE code = 'CUS-00262';
UPDATE customers 
SET 
  latitude = 30.47472,
  longitude = 31.185013,
  location_accuracy = 60.3,
  address = COALESCE(address, 'الفلل ش الترعه جمب حضانه بنجو'),
  location_updated_at = now()
WHERE code = 'CUS-00022';
UPDATE customers 
SET 
  latitude = 30.776848,
  longitude = 31.015167,
  location_accuracy = 17.152,
  address = COALESCE(address, 'طنطا شارع الجلاء خلف الجيل المسلم'),
  location_updated_at = now()
WHERE code = 'CUS-00750';
UPDATE customers 
SET 
  latitude = 30.971262,
  longitude = 30.957176,
  location_accuracy = 39.059,
  address = COALESCE(address, 'شارع محطه المياة'),
  location_updated_at = now()
WHERE code = 'CUS-01219';
UPDATE customers 
SET 
  latitude = 30.79306,
  longitude = 31.00776,
  location_accuracy = 12.648,
  address = COALESCE(address, 'ش- رشدي مع بطرس امام معرض شحاتة للسيارات'),
  location_updated_at = now()
WHERE code = 'CUS-00887';
UPDATE customers 
SET 
  latitude = 30.566612,
  longitude = 31.012224,
  location_accuracy = 11.5,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00297';
UPDATE customers 
SET 
  latitude = 31.058174,
  longitude = 31.406027,
  location_accuracy = 17.97,
  address = COALESCE(address, 'المنصورة بجوار مغسلة الخولي'),
  location_updated_at = now()
WHERE code = 'CUS-00886';
UPDATE customers 
SET 
  latitude = 30.795357,
  longitude = 31.01192,
  location_accuracy = 19.314,
  address = COALESCE(address, 'المرشحة'),
  location_updated_at = now()
WHERE code = 'CUS-00395';
UPDATE customers 
SET 
  latitude = 31.050303,
  longitude = 30.463354,
  location_accuracy = 23.2,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00100';
UPDATE customers 
SET 
  latitude = 30.890223,
  longitude = 30.661083,
  location_accuracy = 19.614,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01021';
UPDATE customers 
SET 
  latitude = 30.465967,
  longitude = 31.189272,
  location_accuracy = 26.109,
  address = COALESCE(address, 'شارع نقابه المهندسين'),
  location_updated_at = now()
WHERE code = 'CUS-01213';
UPDATE customers 
SET 
  latitude = 31.027979,
  longitude = 30.467518,
  location_accuracy = 11.492,
  address = COALESCE(address, 'شبرا .شارع ساحةالحرية'),
  location_updated_at = now()
WHERE code = 'CUS-00164';
UPDATE customers 
SET 
  latitude = 31.055584,
  longitude = 31.402826,
  location_accuracy = 20.0,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00690';
UPDATE customers 
SET 
  latitude = 30.808435,
  longitude = 30.987041,
  location_accuracy = 38.761,
  address = COALESCE(address, 'طريق شوبر'),
  location_updated_at = now()
WHERE code = 'CUS-00900';
UPDATE customers 
SET 
  latitude = 31.247272,
  longitude = 29.986765,
  location_accuracy = 12.85,
  address = COALESCE(address, 'اخر شارع مصطفي كامل بعد مركز الرحمن'),
  location_updated_at = now()
WHERE code = 'CUS-01206';
UPDATE customers 
SET 
  latitude = 31.208649,
  longitude = 29.925127,
  location_accuracy = 9.648,
  address = COALESCE(address, 'خلف كليه هندسه'),
  location_updated_at = now()
WHERE code = 'CUS-00681';
UPDATE customers 
SET 
  latitude = 31.102465,
  longitude = 30.30934,
  location_accuracy = 81.861,
  address = COALESCE(address, 'حي الهندسية'),
  location_updated_at = now()
WHERE code = 'CUS-01115';
UPDATE customers 
SET 
  latitude = 31.075253,
  longitude = 30.340822,
  location_accuracy = 10.0,
  address = COALESCE(address, 'ابو حمص أمام امارات مصر'),
  location_updated_at = now()
WHERE code = 'CUS-01205';
UPDATE customers 
SET 
  latitude = 30.593388,
  longitude = 31.499805,
  location_accuracy = 19.752,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-01013';
UPDATE customers 
SET 
  latitude = 30.990194,
  longitude = 31.170792,
  location_accuracy = 3.216,
  address = COALESCE(address, 'ش جزيرة شدوان'),
  location_updated_at = now()
WHERE code = 'CUS-01204';
UPDATE customers 
SET 
  latitude = 30.466824,
  longitude = 31.18992,
  location_accuracy = 25.632,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00009';
UPDATE customers 
SET 
  latitude = 30.468449,
  longitude = 31.177301,
  location_accuracy = 57.379,
  address = COALESCE(address, 'عند موقف كلية الطب'),
  location_updated_at = now()
WHERE code = 'CUS-00877';
UPDATE customers 
SET 
  latitude = 31.04194,
  longitude = 30.476585,
  location_accuracy = 20.632,
  address = COALESCE(address, 'دمنهور'),
  location_updated_at = now()
WHERE code = 'CUS-01131';
UPDATE customers 
SET 
  latitude = 31.036062,
  longitude = 30.45775,
  location_accuracy = 17.244,
  address = COALESCE(address, 'امام كليه العلوم'),
  location_updated_at = now()
WHERE code = 'CUS-01203';
UPDATE customers 
SET 
  latitude = 31.129013,
  longitude = 30.133354,
  location_accuracy = 68.4,
  address = COALESCE(address, NULL),
  location_updated_at = now()
WHERE code = 'CUS-00892';
UPDATE customers 
SET 
  latitude = 30.793194,
  longitude = 31.009987,
  location_accuracy = 7.0,
  address = COALESCE(address, 'مرسي'),
  location_updated_at = now()
WHERE code = 'CUS-01190';
UPDATE customers 
SET 
  latitude = 30.795486,
  longitude = 31.008108,
  location_accuracy = 21.44,
  address = COALESCE(address, 'ش ثروت مع مصطفي ماهر'),
  location_updated_at = now()
WHERE code = 'CUS-01138';
UPDATE customers 
SET 
  latitude = 30.88329,
  longitude = 30.662247,
  location_accuracy = 44.114,
  address = COALESCE(address, 'عماره التامينات'),
  location_updated_at = now()
WHERE code = 'CUS-01199';
UPDATE customers 
SET 
  latitude = 30.794508,
  longitude = 30.98289,
  location_accuracy = 29.323,
  address = COALESCE(address, 'المعاهده'),
  location_updated_at = now()
WHERE code = 'CUS-01195';
UPDATE customers 
SET 
  latitude = 31.24923,
  longitude = 29.986118,
  location_accuracy = 29.998,
  address = COALESCE(address, 'اخر مصطفي كامل'),
  location_updated_at = now()
WHERE code = 'CUS-01201';

COMMIT;