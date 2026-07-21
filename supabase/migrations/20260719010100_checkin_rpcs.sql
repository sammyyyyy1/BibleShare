-- Plan 5: the check-in write path. SECURITY DEFINER bypasses RLS, so every
-- guard (auth, membership, active-window, unanswered) is asserted in-function;
-- group_checkins/post_groups keep SELECT-only policies by design.
-- NO notification writes: Plan 6 attaches member_checked_in via a trigger.

create or replace function public.check_in(
  p_group_ids    uuid[],
  p_title        text    default null,
  p_body         text    default null,
  p_verses       jsonb   default '[]'::jsonb,
  p_media        jsonb   default '[]'::jsonb,
  p_tag_user_ids uuid[]  default '{}'::uuid[]
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_post_id uuid;
  v_groups  uuid[];
  v_group   uuid;
  v_window  uuid;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  -- Distinct, non-empty targets (dedupe guards the ledger PK).
  select array_agg(distinct g) into v_groups
  from unnest(coalesce(p_group_ids, '{}'::uuid[])) as g;
  if v_groups is null then
    raise exception 'a check-in needs at least one group' using errcode = '22023';
  end if;

  -- Defense-in-depth: the caller must be a member of every target group.
  if exists (
    select 1 from unnest(v_groups) as g
    where not private.is_group_member(g, v_uid)
  ) then
    raise exception 'you can only check in to groups you belong to' using errcode = '42501';
  end if;

  -- Media guard (identical to create_encouragement): image paths live under the
  -- caller's own storage folder; links are external http(s) URLs.
  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_media, '[]'::jsonb))
      as m(media_type text, url text, thumbnail_url text)
    where (
      m.media_type = 'image'
      and (
        m.url is null or m.url !~ ('^' || v_uid::text || '/[^/]+$')
        or (m.thumbnail_url is not null and m.thumbnail_url !~ ('^' || v_uid::text || '/[^/]+$'))
      )
    ) or (
      m.media_type = 'link'
      and (m.url is null or m.url !~ '^https?://')
    )
  ) then
    raise exception 'image media (and its thumbnail) must live under the caller''s own storage folder, and link media must be an external http(s) URL'
      using errcode = '42501';
  end if;

  -- One post for the whole submission. Check-ins never touch the timeline.
  insert into public.posts (author_id, kind, title, body, shared_to_timeline)
  values (
    v_uid,
    'check_in',
    nullif(btrim(coalesce(p_title, '')), ''),
    nullif(btrim(coalesce(p_body, '')), ''),
    false
  )
  returning id into v_post_id;

  -- Per group: assert an active, unanswered window, then fan out. A raise here
  -- rolls back the whole statement — the submission is atomic.
  foreach v_group in array v_groups loop
    select w.id into v_window
    from public.group_checkin_windows w
    where w.group_id = v_group
      and w.opens_at <= now()
    order by w.opens_at desc
    limit 1;

    if v_window is null then
      raise exception 'no active check-in window' using errcode = '22023';
    end if;

    insert into public.post_groups (post_id, group_id)
    values (v_post_id, v_group)
    on conflict do nothing;

    begin
      insert into public.group_checkins (group_id, user_id, window_id, post_id)
      values (v_group, v_uid, v_window, v_post_id);
    exception
      when unique_violation then
        raise exception 'already checked in' using errcode = '22023';
    end;
  end loop;

  -- Attachments (identical to create_encouragement).
  insert into public.post_verses
    (post_id, translation, book, chapter, verse_start, verse_end, reference_label, text_snapshot, position)
  select v_post_id, coalesce(v.translation, 'WEB'), v.book, v.chapter,
         v.verse_start, v.verse_end, v.reference_label, v.text_snapshot, coalesce(v.position, 0)
  from jsonb_to_recordset(coalesce(p_verses, '[]'::jsonb)) as v(
    translation text, book text, chapter int, verse_start int, verse_end int,
    reference_label text, text_snapshot text, position int
  );

  insert into public.post_media
    (post_id, media_type, url, thumbnail_url, title, description, position)
  select v_post_id, m.media_type, m.url, m.thumbnail_url, m.title, m.description, coalesce(m.position, 0)
  from jsonb_to_recordset(coalesce(p_media, '[]'::jsonb)) as m(
    media_type text, url text, thumbnail_url text, title text, description text, position int
  );

  insert into public.post_tags (post_id, tagged_user_id)
  select v_post_id, t
  from unnest(coalesce(p_tag_user_ids, '{}'::uuid[])) as t
  where t <> v_uid
  on conflict do nothing;

  return v_post_id;
end;
$$;

-- The compose multi-select + Check-in tab source: the caller's groups with an
-- active (latest opens_at <= now()) window the caller has not answered.
create or replace function public.active_checkin_targets()
returns table(group_id uuid, name text, window_id uuid)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  return query
  with my_groups as (
    select g.id, g.name
    from public.groups g
    join public.group_members gm on gm.group_id = g.id
    where gm.user_id = auth.uid()
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
      and gc.user_id = auth.uid()
      and gc.window_id = aw.window_id
  )
  order by mg.name;
end;
$$;

revoke execute on function public.check_in(uuid[],text,text,jsonb,jsonb,uuid[]) from public, anon;
grant  execute on function public.check_in(uuid[],text,text,jsonb,jsonb,uuid[]) to authenticated;
revoke execute on function public.active_checkin_targets() from public, anon;
grant  execute on function public.active_checkin_targets() to authenticated;

notify pgrst, 'reload schema';
