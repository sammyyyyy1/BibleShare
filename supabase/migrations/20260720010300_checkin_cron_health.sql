-- Plan 6 Task 4 — check-in cron health.
--
-- private.open_checkin_windows swallows per-group failures as warnings, so a
-- group with an unparseable timezone (Plan 5 final-review Critical) -- or now
-- a raising checkin_reminder trigger -- means windows silently never open.
-- Deliberately minimal: no ops table, no alerting integration. This surfaces
-- in Supabase logs and is queryable on demand; it is the hook to wire into a
-- real alert channel when one exists.

-- `missed_windows` is the only field that observes the ACTUAL OUTCOME; the other
-- three are proxies and every one of them stays green in the failure this task
-- was built to catch. When the checkin_reminder trigger raises, the opener's
-- `exception when others` swallows it inside the per-group loop, the function
-- still returns normally, and pg_cron records the run as 'succeeded'. So
-- last_success_at keeps advancing, failed_runs_last_hour stays 0, and the
-- timezone is fine -- fully green while that group's windows never open. Asking
-- "is a due window actually open?" is cause-agnostic and catches that, an
-- unparseable timezone, and anything else that makes the opener skip a group.
-- Dropped rather than replaced: `create or replace` cannot change a function's
-- return type, and this one gains the missed_windows column.
drop function if exists private.checkin_cron_health();
create or replace function private.checkin_cron_health()
returns table (
  last_success_at timestamptz,
  minutes_since_success numeric,
  failed_runs_last_hour bigint,
  invalid_timezone_groups bigint,
  missed_windows bigint
)
language plpgsql stable security definer set search_path = public as $$
declare
  g       record;
  v_slot  timestamptz;
  v_bad   bigint := 0;
  v_missed bigint := 0;
begin
  for g in
    select id, checkin_cadence, checkin_time, checkin_weekday, timezone
    from public.groups where checkin_cadence <> 'none'
  loop
    begin
      v_slot := private.due_slot_for(g.checkin_cadence, g.checkin_time,
                                     g.checkin_weekday, g.timezone, now());
      -- The opener runs every 15 minutes, so a slot due more recently than that
      -- may simply not have been reached yet. 20 minutes leaves margin without
      -- turning normal lag into a false positive.
      if v_slot is not null
         and v_slot < now() - interval '20 minutes'
         and not exists (select 1 from public.group_checkin_windows w
                         where w.group_id = g.id and w.opens_at = v_slot)
      then
        v_missed := v_missed + 1;
      end if;
    exception when others then
      -- Same per-group isolation the opener itself uses. due_slot_for raises on
      -- an unparseable timezone, which is exactly the group the opener skips --
      -- so this counts what the opener actually chokes on rather than
      -- re-deriving it from pg_timezone_names.
      v_bad := v_bad + 1;
    end;
  end loop;

  return query
  with j as (select jobid from cron.job where jobname = 'open-checkin-windows'),
  runs as (
    select d.status, d.end_time from cron.job_run_details d
    join j on j.jobid = d.jobid
  ),
  ok as (select max(end_time) as t from runs where status = 'succeeded'),
  bad as (
    select count(*) as n from runs
    where status <> 'succeeded' and end_time > now() - interval '1 hour'
  )
  -- Aggregates with no GROUP BY always yield one row, so this returns exactly
  -- one row even when the job has never run or does not exist -- the watchdog's
  -- `select ... into` must never silently no-op.
  select ok.t,
         round(extract(epoch from (now() - ok.t)) / 60.0, 1),
         bad.n,
         v_bad,
         v_missed
  from ok, bad;
end;
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
  -- subquery pg_timezone_names -- so create_group validates it on the way in
  -- and this counter catches anything already stored or changed since.
  if h.invalid_timezone_groups > 0 then
    raise warning 'checkin-cron-watchdog: % group(s) have an unparseable timezone; their windows never open',
      h.invalid_timezone_groups;
  end if;

  -- The outcome check. This is the one that fires when the opener reports
  -- success while silently skipping a group -- notably when a trigger raises
  -- inside its `exception when others` handler, which no run-status or
  -- timezone check can see.
  if h.missed_windows > 0 then
    raise warning 'checkin-cron-watchdog: % group(s) are past due with no window opened; the opener is reporting success while skipping them',
      h.missed_windows;
  end if;
end;
$$;
revoke all on function private.checkin_cron_watchdog() from public;

select cron.schedule('checkin-cron-watchdog', '*/30 * * * *',
                     $$select private.checkin_cron_watchdog();$$);
