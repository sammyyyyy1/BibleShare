-- Plan 5 final-review hardening (Critical #1 + carried minors):
--
-- (a) create_group validated no timezone at all. `private.due_slot_for` runs
--     `p_now at time zone p_timezone`, which RAISES on an unrecognized zone
--     name. Combined with (c) not existing yet, ONE group created with a
--     bogus timezone would abort the whole cron transaction on every run —
--     silently disabling check-in windows for every group, forever. Reject
--     unknown zones at creation time via pg_timezone_names.
--
-- (b) A defense-in-depth CHECK on groups.timezone was considered, but CHECK
--     constraints cannot contain subqueries (pg_timezone_names is a catalog
--     view, not an immutable expression), so no subquery-free equivalent
--     exists. Omitted; (a) + (c) are the load-bearing guards — (a) stops bad
--     data from being written, (c) stops any bad data that exists (e.g. a
--     zone that is later removed from tzdata) from ever taking the whole
--     opener down again.
--
-- (c) THE MOST IMPORTANT PART: private.open_checkin_windows now isolates
--     each group's slot computation + insert in its own sub-transaction via a
--     nested BEGIN/EXCEPTION block. One poisoned or otherwise-erroring group
--     is skipped (with a WARNING naming the group) instead of aborting every
--     other group's window for that run.
--
-- Also folds in two small carried items from review:
--   * active_checkin_targets: hoist auth.uid() into v_uid (codebase idiom;
--     was called three times bare) and add an (mg.name, mg.id) tiebreaker so
--     same-named groups stop reordering between refreshes.
--   * due_slot_for: mark STABLE. It is a pure function of its arguments
--     (previously left at the default VOLATILE by oversight); body and DST
--     clamp logic are unchanged.

-- ---------------------------------------------------------------------------
-- (a) create_group: add timezone validation alongside the existing guards.
-- ---------------------------------------------------------------------------
create or replace function public.create_group(
  p_name        text,
  p_description text    default null,
  p_cadence     text    default 'none',
  p_time        time    default null,
  p_weekday     int     default null,
  p_timezone    text    default 'America/New_York'
) returns public.groups
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_group public.groups;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if p_name is null or char_length(btrim(p_name)) not between 1 and 60 then
    raise exception 'group name must be 1 to 60 characters' using errcode = '22023';
  end if;

  -- Mirror the table CHECK constraints for clearer errors (defense-in-depth).
  if p_cadence is null or p_cadence not in ('none','daily','weekly') then
    raise exception 'invalid check-in cadence' using errcode = '22023';
  end if;
  if p_cadence <> 'none' and p_time is null then
    raise exception 'a check-in schedule needs a time' using errcode = '22023';
  end if;
  if p_cadence = 'weekly' and p_weekday is null then
    raise exception 'a weekly schedule needs a weekday' using errcode = '22023';
  end if;
  if p_weekday is not null and p_weekday not between 0 and 6 then
    raise exception 'weekday must be between 0 and 6' using errcode = '22023';
  end if;
  if p_timezone is not null and not exists (select 1 from pg_timezone_names where name = p_timezone) then
    raise exception 'unknown timezone' using errcode = '22023';
  end if;

  insert into public.groups
    (creator_id, name, description, checkin_cadence, checkin_time, checkin_weekday, timezone)
  values (
    v_uid,
    btrim(p_name),
    nullif(btrim(coalesce(p_description, '')), ''),
    p_cadence,
    p_time,
    p_weekday,
    coalesce(p_timezone, 'America/New_York')
  )
  returning * into v_group;

  insert into public.group_members (group_id, user_id, role)
  values (v_group.id, v_uid, 'creator');

  return v_group;
end;
$$;

revoke execute on function public.create_group(text,text,text,time,int,text) from public, anon;
grant  execute on function public.create_group(text,text,text,time,int,text) to authenticated;

-- ---------------------------------------------------------------------------
-- (c) open_checkin_windows: isolate each group so one failure can't abort
--     the whole run.
-- ---------------------------------------------------------------------------
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
    begin
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
    exception when others then
      raise warning 'open_checkin_windows: group % skipped: %', g.id, sqlerrm;
    end;
  end loop;
  return v_count;
end;
$$;

revoke execute on function private.open_checkin_windows(timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- due_slot_for: mark STABLE (pure function of its arguments). Body and DST
-- clamp logic unchanged.
-- ---------------------------------------------------------------------------
create or replace function private.due_slot_for(
  p_cadence  text,
  p_time     time,
  p_weekday  int,
  p_timezone text,
  p_now      timestamptz
) returns timestamptz
language plpgsql
stable
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

revoke execute on function private.due_slot_for(text,time,int,text,timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Fix 5: active_checkin_targets — hoist auth.uid(), add a tiebreaker.
-- ---------------------------------------------------------------------------
create or replace function public.active_checkin_targets()
returns table(group_id uuid, name text, window_id uuid)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  return query
  with my_groups as (
    select g.id, g.name
    from public.groups g
    join public.group_members gm on gm.group_id = g.id
    where gm.user_id = v_uid
  ),
  active_windows as (
    select distinct on (w.group_id) w.group_id, w.id as window_id
    from public.group_checkin_windows w
    where w.opens_at <= now()
    order by w.group_id, w.opens_at desc
  )
  select mg.id, mg.name, aw.window_id
  from my_groups mg
  join active_windows aw on aw.group_id = mg.id
  where not exists (
    select 1 from public.group_checkins gc
    where gc.group_id = mg.id
      and gc.user_id = v_uid
      and gc.window_id = aw.window_id
  )
  order by mg.name, mg.id;
end;
$$;

revoke execute on function public.active_checkin_targets() from public, anon;
grant  execute on function public.active_checkin_targets() to authenticated;

notify pgrst, 'reload schema';
