-- Plan 6 Task 5 — drain the notification queue once a minute.
--
-- NOT APPLIED. Activation is deliberately manual because it depends on the
-- service-role key, which an agent must never handle. To switch on:
--   1) select vault.create_secret('https://jstdoizgosatitptyrdy.supabase.co', 'project_url');
--   2) select vault.create_secret('<service role key>', 'service_role_key');  -- owner runs this
--   3) apply this migration.
-- Until then the queue simply accumulates, bounded by the Edge Function's
-- 1-day selection window. Harmless while the transport is a no-op: the
-- function short-circuits and mutates nothing.
create extension if not exists pg_net;

select cron.schedule('push-notifications', '* * * * *', $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
    ),
    body    := '{}'::jsonb
  );
$$);
