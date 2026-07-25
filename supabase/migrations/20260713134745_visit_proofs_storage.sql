BEGIN;

-- Create private storage bucket 'visit-proofs' if not exists, raising clear exception if settings mismatch
DO $$
DECLARE
  v_bucket RECORD;
BEGIN
  SELECT name, public, file_size_limit, allowed_mime_types
  INTO v_bucket
  FROM storage.buckets
  WHERE id = 'visit-proofs';

  IF FOUND THEN
    IF v_bucket.public IS DISTINCT FROM false
       OR v_bucket.file_size_limit IS DISTINCT FROM 2097152
       OR v_bucket.name IS DISTINCT FROM 'visit-proofs'
       OR v_bucket.allowed_mime_types IS NULL
       OR NOT (v_bucket.allowed_mime_types @> ARRAY['image/jpeg', 'image/png'] AND v_bucket.allowed_mime_types <@ ARRAY['image/jpeg', 'image/png'])
    THEN
      RAISE EXCEPTION 'سلة visit-proofs موجودة بإعدادات غير مطابقة!';
    END IF;
  ELSE
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES ('visit-proofs', 'visit-proofs', false, 2097152, ARRAY['image/jpeg', 'image/png']);
  END IF;
END $$;

-- SELECT Policy: owner representative can read, supervisors can read their branch team's proofs, managers read all
CREATE POLICY "visit_proofs_select_policy" ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'visit-proofs'
    AND array_length(string_to_array(name, '/'), 1) = 5
    AND (string_to_array(name, '/'))[1] = 'plans'
    AND (string_to_array(name, '/'))[3] = 'items'
    AND (string_to_array(name, '/'))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND (string_to_array(name, '/'))[4] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND storage.filename(name) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png)$'
    AND EXISTS (
      SELECT 1 FROM public.visit_plan_items vpi
      WHERE vpi.plan_id = (
        CASE
          WHEN (string_to_array(name, '/'))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          THEN ((string_to_array(name, '/'))[2])::uuid
          ELSE NULL
        END
      )
      AND vpi.id = (
        CASE
          WHEN (string_to_array(name, '/'))[4] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          THEN ((string_to_array(name, '/'))[4])::uuid
          ELSE NULL
        END
      )
    )
    AND (
      public.check_permission(auth.uid(), 'visit_plans.read_all')
      OR (
        public.check_permission(auth.uid(), 'visit_plans.read_team')
        AND EXISTS (
          SELECT 1 FROM public.visit_plans vp
          JOIN public.hr_employees current_emp ON current_emp.user_id = auth.uid()
          WHERE vp.id = (
            CASE
              WHEN (string_to_array(name, '/'))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
              THEN ((string_to_array(name, '/'))[2])::uuid
              ELSE NULL
            END
          )
          AND current_emp.branch_id = vp.organizational_branch_id
        )
      )
      OR (
        public.check_permission(auth.uid(), 'visit_plans.read_own')
        AND EXISTS (
          SELECT 1 FROM public.visit_plans vp
          JOIN public.hr_employees e ON e.id = vp.employee_id
          WHERE e.user_id = auth.uid()
            AND vp.id = (
              CASE
                WHEN (string_to_array(name, '/'))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
                THEN ((string_to_array(name, '/'))[2])::uuid
                ELSE NULL
              END
            )
        )
      )
    )
  );

-- INSERT Policy: representative owner can insert only into their assigned visit plans and items
CREATE POLICY "visit_proofs_insert_policy" ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'visit-proofs'
    AND array_length(string_to_array(name, '/'), 1) = 5
    AND (string_to_array(name, '/'))[1] = 'plans'
    AND (string_to_array(name, '/'))[3] = 'items'
    AND (string_to_array(name, '/'))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND (string_to_array(name, '/'))[4] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND storage.filename(name) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png)$'
    AND EXISTS (
      SELECT 1 FROM public.visit_plan_items vpi
      WHERE vpi.plan_id = (
        CASE
          WHEN (string_to_array(name, '/'))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          THEN ((string_to_array(name, '/'))[2])::uuid
          ELSE NULL
        END
      )
      AND vpi.id = (
        CASE
          WHEN (string_to_array(name, '/'))[4] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          THEN ((string_to_array(name, '/'))[4])::uuid
          ELSE NULL
        END
      )
    )
    AND public.check_permission(auth.uid(), 'visit_plans.update_own')
    AND EXISTS (
      SELECT 1 FROM public.visit_plans vp
      JOIN public.hr_employees e ON e.id = vp.employee_id
      WHERE e.user_id = auth.uid()
        AND vp.id = (
          CASE
            WHEN (string_to_array(name, '/'))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
            THEN ((string_to_array(name, '/'))[2])::uuid
            ELSE NULL
          END
        )
    )
  );

COMMIT;
