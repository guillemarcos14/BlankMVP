-- Keep Early Access opening delivery idempotent independently for SMS and WhatsApp.
-- The legacy opening_* columns continue to represent the original WhatsApp flow.
alter table public.waitlist_users
  add column if not exists opening_sms_first_sent_at timestamptz,
  add column if not exists opening_sms_second_sent_at timestamptz;
