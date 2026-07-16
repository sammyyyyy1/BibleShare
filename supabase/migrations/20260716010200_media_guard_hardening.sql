-- Defence in depth for the media guard bypass:
-- create_encouragement's foreign-folder guard only checked media_type='image',
-- but media_select_visible does not filter on media_type at all -- so a
-- link-typed post_media row pointing at another user's storage object path
-- made that private object readable through the caller's own (visible) post.
--
-- (a) Tighten the storage read policy itself to only honour post_media rows
--     of media_type='image'. The nested `public.posts` select stays inline
--     and invoker-rights (do NOT wrap in a SECURITY DEFINER helper -- definer
--     rights would bypass the posts RLS the whole design depends on).
drop policy if exists media_select_visible on storage.objects;
create policy media_select_visible on storage.objects for select to authenticated
using (
  bucket_id = 'media'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1
      from public.post_media pm
      where pm.url = storage.objects.name
        and pm.media_type = 'image'
        and exists (select 1 from public.posts p where p.id = pm.post_id)
    )
  )
);

-- (b) Re-create create_encouragement with a stricter media guard:
--     - image rows must have a url matching exactly ^<caller_uid>/[^/]+$
--       (own folder, one path segment, no traversal shapes).
--     - link rows must have a url matching ^https?:// (external URL only,
--       never a storage path).
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

  -- An image path must live under the caller's own storage folder, as a
  -- single path segment with no traversal. A link must be an external URL,
  -- never a storage path -- media_select_visible only trusts image rows, but
  -- we still refuse to let a link masquerade as (or point at) a storage path.
  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_media, '[]'::jsonb)) as m(media_type text, url text)
    where (
      m.media_type = 'image'
      and (m.url is null or m.url !~ ('^' || v_uid::text || '/[^/]+$'))
    ) or (
      m.media_type = 'link'
      and (m.url is null or m.url !~ '^https?://')
    )
  ) then
    raise exception 'image media must live under the caller''s own storage folder, and link media must be an external http(s) URL'
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
