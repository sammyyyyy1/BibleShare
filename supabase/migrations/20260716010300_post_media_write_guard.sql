-- The RPC-level media guard (20260716010200) is not a security boundary on
-- its own: create_encouragement is SECURITY DEFINER and therefore bypasses
-- RLS on post_media entirely, but post_media's own INSERT policy
-- (pm_insert_owner, from 20260715020600) only checked that the parent post
-- belongs to the caller -- it never validated `url`. Any authenticated user
-- could call POST /rest/v1/post_media directly and attach an arbitrary
-- storage path (e.g. another user's private image) to their own post, which
-- media_select_visible would then happily serve up to everyone who can see
-- that post. Reproduced live: VICTIM_OBJECT_READABLE_BY_ATTACKER = 1.
--
-- This migration closes that path at the table (RLS) level, adds the same
-- thumbnail_url validation the RPC guard was missing on both paths, and adds
-- defence in depth to media_select_visible so the leak is structurally
-- impossible regardless of which write path was used.

-- (1) CRITICAL: pm_insert_owner must itself enforce url shape, not just
--     parent-post ownership. Same regexes as the RPC guard: an image url
--     must live under the caller's own storage folder as a single path
--     segment; a link url must be an external http(s) URL.
--     (2) MINOR: also validate thumbnail_url with the same own-folder regex
--     when present on an image row.
drop policy if exists pm_insert_owner on public.post_media;
create policy pm_insert_owner on public.post_media for insert with check (
  exists (select 1 from public.posts p where p.id = post_id and p.author_id = (select auth.uid()))
  and (media_type <> 'image' or url ~ ('^' || (select auth.uid())::text || '/[^/]+$'))
  and (media_type <> 'link' or url ~ '^https?://')
  and (
    media_type <> 'image'
    or thumbnail_url is null
    or thumbnail_url ~ ('^' || (select auth.uid())::text || '/[^/]+$')
  )
);

-- (2) Re-create create_encouragement with thumbnail_url validated alongside
--     url, using the same own-folder regex, for image rows. Everything else
--     (auth.uid() null check, title check, author forcing, jsonb_to_recordset
--     inserts, tag self-filter, return, security definer, search_path, and
--     the revoke/grant lines) is unchanged.
create or replace function public.create_encouragement(
  p_title              text,
  p_body               text    default null,
  p_shared_to_timeline boolean default true,
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
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if p_title is null or btrim(p_title) = '' then
    raise exception 'title is required' using errcode = '22023';
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
    coalesce(p_shared_to_timeline, true)
  )
  returning id into v_post_id;

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
  where t <> v_uid            -- tagging yourself is a no-op
  on conflict do nothing;

  return v_post_id;
end;
$$;

revoke execute on function public.create_encouragement(text,text,boolean,jsonb,jsonb,uuid[]) from public, anon;
grant  execute on function public.create_encouragement(text,text,boolean,jsonb,jsonb,uuid[]) to authenticated;

-- (3) DEFENCE IN DEPTH: media_select_visible must not just check that *some*
--     visible post_media row references this object -- it must require that
--     the referencing post's AUTHOR owns the object's folder. This makes the
--     disclosure structurally impossible regardless of write path (RPC,
--     direct REST insert, or any future path), independent of fixes (1)/(2).
--     The nested `public.posts` join stays inline and invoker-rights so
--     posts_select_visible still applies and gates visibility -- do NOT wrap
--     this in a SECURITY DEFINER helper.
drop policy if exists media_select_visible on storage.objects;
create policy media_select_visible on storage.objects for select to authenticated
using (
  bucket_id = 'media'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1
      from public.post_media pm
      join public.posts p on p.id = pm.post_id
      where pm.url = storage.objects.name
        and pm.media_type = 'image'
        and (storage.foldername(storage.objects.name))[1] = p.author_id::text
    )
  )
);
