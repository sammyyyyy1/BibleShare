-- create_group: insert the group + the creator's membership row atomically.
-- SECURITY DEFINER is safe because creator_id is derived from auth.uid(), never
-- a parameter. Schedule columns are stored dormant; Plan 5 owns windows/cron.

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
