-- Plan 6 Task 1 — the tag visibility gate.
--
-- p_tag_user_ids was unvalidated in BOTH write paths: any user id could be
-- tagged, including users who cannot see the post. Inert while nothing read
-- post_tags (pt_select_visible is RLS-filtered, so the row was an orphan) --
-- but Plan 6 fans notifications over tags, which would push a notification
-- for a post the recipient cannot open.
--
-- One rule, derived from posts_select_visible: a tag is valid iff the tagged
-- user can see the post. check_in passes p_shared := false, so it collapses
-- to members-only without needing a second rule.

create or replace function private.can_tag(
  p_author uuid, p_tagged uuid, p_shared boolean, p_group_ids uuid[]
) returns boolean
language sql stable security definer set search_path = public as $$
  select (coalesce(p_shared, false) and private.is_friend(p_author, p_tagged))
      or exists (
           select 1 from unnest(coalesce(p_group_ids, '{}'::uuid[])) as g
           where private.is_group_member(g, p_tagged)
         );
$$;

-- Called only from definer RPCs, never from an RLS policy: no authenticated
-- grant (matches private.due_slot_for, not private.is_friend).
revoke all on function private.can_tag(uuid, uuid, boolean, uuid[]) from public;

-- Second leg of the gate. pt_insert_owner validated only that the caller
-- authored the post -- the tagged user was entirely unchecked -- so a client
-- could bypass the RPC gate entirely with a direct POST /post_tags. No client
-- path writes post_tags (it appears only as a read embed in FeedService).
drop policy if exists "pt_insert_owner" on public.post_tags;

-- Carried from Plan 5's review: unconstrained on `kind`, so a client could
-- fabricate kind='check_in', shared_to_timeline=true and get a fake "Checked
-- in" capsule on their own timeline. No client path inserts posts (PostService
-- only ever calls .delete()). Same rule as above: SECURITY DEFINER RPCs are
-- the only write path into the post graph.
drop policy if exists "Users can create their own posts" on public.posts;

CREATE OR REPLACE FUNCTION public.create_encouragement(p_title text, p_body text DEFAULT NULL::text, p_shared_to_timeline boolean DEFAULT true, p_group_ids uuid[] DEFAULT '{}'::uuid[], p_verses jsonb DEFAULT '[]'::jsonb, p_media jsonb DEFAULT '[]'::jsonb, p_tag_user_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- Tag gate: a tag is only legitimate if the tagged user can see the post.
  -- Raise rather than silently drop -- this mirrors how the group-membership
  -- check above rejects the whole call, and gives the post_tag notification
  -- trigger a hard invariant to rely on.
  if exists (
    select 1 from unnest(coalesce(p_tag_user_ids, '{}'::uuid[])) as t
    where t <> v_uid
      and not private.can_tag(v_uid, t, v_shared, p_group_ids)
  ) then
    raise exception 'you can only tag people who can see this post'
      using errcode = '42501';
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
$function$
;

CREATE OR REPLACE FUNCTION public.check_in(p_group_ids uuid[], p_title text DEFAULT NULL::text, p_body text DEFAULT NULL::text, p_verses jsonb DEFAULT '[]'::jsonb, p_media jsonb DEFAULT '[]'::jsonb, p_tag_user_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  select array_agg(distinct g) into v_groups
  from unnest(coalesce(p_group_ids, '{}'::uuid[])) as g
  where g is not null;
  if v_groups is null then
    raise exception 'a check-in needs at least one group' using errcode = '22023';
  end if;

  if exists (
    select 1 from unnest(v_groups) as g
    where not private.is_group_member(g, v_uid)
  ) then
    raise exception 'you can only check in to groups you belong to' using errcode = '42501';
  end if;

  -- Tag gate. A check-in is never on the timeline, so the timeline clause is
  -- dead here and the rule collapses to members-only -- which is exactly the
  -- intended behaviour, with no check-in-specific branch.
  if exists (
    select 1 from unnest(coalesce(p_tag_user_ids, '{}'::uuid[])) as t
    where t <> v_uid
      and not private.can_tag(v_uid, t, false, v_groups)
  ) then
    raise exception 'you can only tag people who can see this post'
      using errcode = '42501';
  end if;

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
    'check_in',
    nullif(btrim(coalesce(p_title, '')), ''),
    nullif(btrim(coalesce(p_body, '')), ''),
    false
  )
  returning id into v_post_id;

  foreach v_group in array v_groups loop
    v_window := null;

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

    insert into public.group_checkins (group_id, user_id, window_id, post_id)
    values (v_group, v_uid, v_window, v_post_id)
    on conflict (group_id, user_id, window_id) do nothing;

    if not found then
      raise exception 'already checked in' using errcode = '22023';
    end if;
  end loop;

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
$function$
;
