-- Explain the temporary Early Access scope after the first real reply.
-- Delivery is idempotent independently by channel.
alter table public.waitlist_users
  add column if not exists availability_notice_whatsapp_sent_at timestamptz,
  add column if not exists availability_notice_sms_sent_at timestamptz;
