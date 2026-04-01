-- Migration: Add eligible_gender to hr_leave_types
-- Description: HR Inferential Closure Pack - Wave X2 (Leave Eligibility Filtering)

ALTER TABLE hr_leave_types 
ADD COLUMN IF NOT EXISTS eligible_gender TEXT DEFAULT 'all' CHECK (eligible_gender IN ('all', 'male', 'female'));

COMMENT ON COLUMN hr_leave_types.eligible_gender IS 'All, Male only, or Female only eligibility context';
