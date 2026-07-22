-- Plan 6 Task 4 — check-in cron health.
--
-- private.open_checkin_windows swallows per-group failures as warnings, so a
-- group with an unparseable timezone (Plan 5 final-review Critical) -- or now
-- a raising checkin_reminder trigger -- means windows silently never open.
-- Deliberately minimal: no ops table, no alerting integration. This surfaces
-- in Supabase logs and is queryable on demand; it is the hook to wire into a
-- real alert channel when one exists.

create or replace function private.checkin_cron_health()
returns table (
  last_success_at timestamptz,
  minutes_since_success numeric,
  failed_runs_last_hour bigint,
  invalid_timezone_groups bigint
)
language sql stable security definer set search_path = public as $$
  with j as (select jobid from cron.job where jobname = 'open-checkin-windows'),
  runs as (
    select d.status, d.end_time from cron.job_run_details d
    join j on j.jobid = d.jobid
  ),
  ok as (select max(end_time) as t from runs where status = 'succeeded'),
  bad as (
    select count(*) as n from runs
    where status <> 'succeeded' and end_time > now() - interval '1 hour'
  ),
  tz as (
    select count(*) as n from public.groups g
    where g.checkin_cadence <> 'none'
      and not exists (select 1 from pg_timezone_names z where z.name = g.timezone)
  )
  select ok.t,
         round(extract(epoch from (now() - ok.t)) / 60.0, 1),
         bad.n,
         tz.n
  from ok, bad, tz;
$$;
revoke all on function private.checkin_cron_health() from public;

create or replace function private.checkin_cron_watchdog()
returns void language plpgsql security definer set search_path = public as $$
declare h record;
begin
  select * into h from private.checkin_cron_health();

  if h.last_success_at is null then
    raise warning 'checkin-cron-watchdog: open-checkin-windows has NEVER succeeded';
  elsif h.minutes_since_success > 30 then
    raise warning 'checkin-cron-watchdog: no successful run in % minutes (last %)',
      h.minutes_since_success, h.last_success_at;
  end if;

  if h.failed_runs_last_hour > 0 then
    raise warning 'checkin-cron-watchdog: % failed run(s) in the last hour',
      h.failed_runs_last_hour;
  end if;

  -- groups.timezone has no CHECK constraint -- impossible, since CHECK cannot
  -- subquery pg_timezone_names -- so create_group's validation plus this
  -- counter is the complete story.
  if h.invalid_timezone_groups > 0 then
    raise warning 'checkin-cron-watchdog: % group(s) have an unparseable timezone; their windows never open',
      h.invalid_timezone_groups;
  end if;
end;
$$;
revoke all on function private.checkin_cron_watchdog() from public;

select cron.schedule('checkin-cron-watchdog', '*/30 * * * *',
                     $$select private.checkin_cron_watchdog();$$);
