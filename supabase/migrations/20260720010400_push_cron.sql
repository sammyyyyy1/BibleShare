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
-- PRECONDITION, in addition to the two secrets: the drain must be made
-- SINGLE-FLIGHT before this schedule is enabled. index.ts selects rows before
-- stamping pushed_at, so if a drain outlasts this 1-minute tick, the next run
-- selects the same rows and sends them twice. That is unreachable while nothing
-- schedules the function, and becomes reachable the instant this is applied.
-- A session advisory lock does NOT solve it (the pooler gives each request a
-- different connection); claim the batch in the database instead -- e.g. a
-- SECURITY DEFINER function doing `... for update skip locked` over the pending
-- window and returning the claimed rows.
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
