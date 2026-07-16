-- Verse range sanity. Deferred to "when compose lands" by the Plan 1 final
-- review; compose is the first writer of these rows, so it lands here.
alter table public.post_verses drop constraint if exists post_verses_range_valid;
alter table public.post_verses add constraint post_verses_range_valid
  check (chapter > 0 and verse_start > 0 and verse_end >= verse_start);

-- Atomic compose: one posts row + its verses/media/tags, in a single transaction.
-- SECURITY DEFINER is safe here because author_id is derived from auth.uid() and
-- is never a parameter — a caller cannot author as anyone else.

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

  -- An image path must live under the caller's own storage folder. Without this,
  -- a caller could reference someone else's object path and make that private
  -- image readable through their own post (media_select_visible keys off post_media.url).
  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_media, '[]'::jsonb)) as m(media_type text, url text)
    where m.media_type = 'image'
      and (m.url is null or m.url not like v_uid::text || '/%')
  ) then
    raise exception 'image media must live under the caller''s own storage folder'
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
