-- Backfill explicit gender eligibility for seeded/system leave types.
-- Wave X2 added eligible_gender with a safe default of 'all', but existing
-- system rows such as MATERNITY need a data migration so self-service filtering
-- reflects the real business rule immediately.

UPDATE hr_leave_types
SET eligible_gender = 'female'
WHERE code = 'MATERNITY'
  AND COALESCE(eligible_gender, 'all') = 'all';
