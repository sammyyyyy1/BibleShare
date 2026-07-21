-- Plan 5: open check-in windows on schedule. pg_cron calls
-- private.open_checkin_windows() every 15 min; it inserts, for each scheduled
-- group, the most recent due slot in the group's timezone (catch-up after
-- downtime; never backfills older missed slots — only the latest window can be
-- active). Idempotent via unique(group_id, opens_at).

create extension if not exists pg_cron;

-- Pure slot predicate: the most recent scheduled instant <= p_now in the
-- group's timezone, or null when the cadence is 'none'. p_now is a parameter so
-- the SQL suite can pin timestamps across timezones/DST (spec §9).
create or replace function private.due_slot_for(
  p_cadence  text,
  p_time     time,
  p_weekday  int,
  p_timezone text,
  p_now      timestamptz
) returns timestamptz
language plpgsql
set search_path = public
as $$
declare
  v_local  timestamp;
  v_slot   date;
  v_result timestamptz;
begin
  if p_cadence = 'none' or p_time is null then
    return null;
  end if;

  v_local := p_now at time zone p_timezone;

  if p_cadence = 'daily' then
    v_slot := v_local::date;
    if v_slot + p_time > v_local then
      v_slot := v_slot - 1;
    end if;
  elsif p_cadence = 'weekly' then
    -- extract(dow) convention: 0 = Sunday … 6 = Saturday.
    v_slot := v_local::date
              - (((extract(dow from v_local::date)::int - p_weekday) % 7 + 7) % 7);
    if v_slot + p_time > v_local then
      v_slot := v_slot - 7;
    end if;
  else
    return null;
  end if;

  -- Local wall-clock back to UTC. On spring-forward a nonexistent local time is
  -- resolved by the zone rules; the unique(group_id, opens_at) guard absorbs
  -- fall-back duplicates (accepted per spec §10).
  v_result := (v_slot + p_time) at time zone p_timezone;

  -- DST clamp: resolving a nonexistent local time (spring-forward) can land the
  -- slot AFTER p_now, which would break this function's contract (the most
  -- recent scheduled instant <= p_now) and publish a future-dated window. Step
  -- back one cadence period so the invariant always holds. A no-op outside the
  -- transition hour, since the date arithmetic above already rolled back when
  -- the slot had not yet occurred in local time.
  if v_result > p_now then
    if p_cadence = 'daily' then
      v_result := ((v_slot - 1) + p_time) at time zone p_timezone;
    else
      v_result := ((v_slot - 7) + p_time) at time zone p_timezone;
    end if;
  end if;

  return v_result;
end;
$$;

create or replace function private.open_checkin_windows(p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  g record;
  v_slot timestamptz;
begin
  for g in
    select id, checkin_cadence, checkin_time, checkin_weekday, timezone
    from public.groups
    where checkin_cadence <> 'none'
  loop
    v_slot := private.due_slot_for(g.checkin_cadence, g.checkin_time, g.checkin_weekday, g.timezone, p_now);
    if v_slot is null then
      continue;
    end if;
    insert into public.group_checkin_windows (group_id, opens_at)
    values (g.id, v_slot)
    on conflict (group_id, opens_at) do nothing;
    if found then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

-- Cron-only: not executable by API roles at all. (Postgres grants EXECUTE to
-- PUBLIC by default; the private schema already shields PostgREST, revoke anyway.)
revoke execute on function private.due_slot_for(text,time,int,text,timestamptz) from public, anon, authenticated;
revoke execute on function private.open_checkin_windows(timestamptz) from public, anon, authenticated;

-- Idempotent (re)schedule.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'open-checkin-windows') then
    perform cron.unschedule('open-checkin-windows');
  end if;
end $$;

select cron.schedule('open-checkin-windows', '*/15 * * * *', $$select private.open_checkin_windows();$$);
