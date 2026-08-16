-- Work Management — command API closed value sets.
-- The canonical work_items.waiting_on_type column remains TEXT + CHECK for
-- backwards compatibility; this enum is used only by the public RPC contract.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE TYPE public.work_waiting_on_type AS ENUM (
  'user',
  'department',
  'queue',
  'external_party',
  'entity',
  'other'
);

RESET lock_timeout;
RESET statement_timeout;
