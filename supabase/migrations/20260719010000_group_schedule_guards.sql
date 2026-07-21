-- Deferred Plan-4 minors on the schedule/RPC surface (folded into Plan 5):
-- (a) create_group: reject an out-of-range weekday with a clear 22023 from the
--     RPC instead of the table CHECK (23514).
-- (b) create_encouragement: normalize coalesce(p_shared_to_timeline, true) once
--     and use it for BOTH the destination invariant and the insert (previously
--     false vs true — harmless only because the client never sends null).
-- create or replace: signatures and grants are unchanged.

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

create or replace function public.create_encouragement(
  p_title              text,
  p_body               text    default null,
  p_shared_to_timeline boolean default true,
  p_group_ids          uuid[]  default '{}'::uuid[],
  p_verses             jsonb   default '[]'::jsonb,
  p_media              jsonb   default '[]'::jsonb,
  p_tag_user_ids       uuid[]  default '{}'::uuid[]
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_post_id uuid;
  v_shared  boolean := coalesce(p_shared_to_timeline, true);
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if p_title is null or btrim(p_title) = '' then
    raise exception 'title is required' using errcode = '22023';
  end if;

  -- Destination invariant: an encouragement must reach at least one surface.
  if not v_shared and coalesce(array_length(p_group_ids, 1), 0) = 0 then
    raise exception 'an encouragement needs at least one destination' using errcode = '22023';
  end if;

  -- Defense-in-depth: the caller must be a member of every target group. The
  -- pg_insert_owner_member table policy cannot guard this SECURITY DEFINER path.
  if exists (
    select 1 from unnest(coalesce(p_group_ids, '{}'::uuid[])) as g
    where not private.is_group_member(g, v_uid)
  ) then
    raise exception 'you can only post to groups you belong to' using errcode = '42501';
  end if;

  -- An image path (and its thumbnail, if any) must live under the caller's
  -- own storage folder, as a single path segment with no traversal. A link
  -- must be an external URL, never a storage path -- media_select_visible
  -- only trusts image rows, but we still refuse to let a link masquerade as
  -- (or point at) a storage path.
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

  insert into public.posts (author_id, kind, title, body, shared_to_timeline)
  values (
    v_uid,
    'encouragement',
    btrim(p_title),
    nullif(btrim(coalesce(p_body, '')), ''),
    v_shared
  )
  returning id into v_post_id;

  insert into public.post_groups (post_id, group_id)
  select v_post_id, g
  from unnest(coalesce(p_group_ids, '{}'::uuid[])) as g
  on conflict do nothing;

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
