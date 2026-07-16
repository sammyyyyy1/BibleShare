-- Private bucket for encouragement images.
-- Object key convention: {user_id}/{uuid}.jpg  (user_id lowercase, as auth.uid()::text renders it)
-- public.post_media.url stores THE OBJECT PATH, not a URL.

insert into storage.buckets (id, name, public)
values ('media', 'media', false)
on conflict (id) do nothing;

-- Write/delete: only inside your own folder.
drop policy if exists media_insert_own on storage.objects;
create policy media_insert_own on storage.objects for insert to authenticated
with check (
  bucket_id = 'media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists media_delete_own on storage.objects;
create policy media_delete_own on storage.objects for delete to authenticated
using (
  bucket_id = 'media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- Read: your own objects (needed while composing, before any post row exists),
-- OR an object referenced by a post_media row whose parent post you can see.
--
-- The nested `public.posts` select is evaluated as the INVOKER, so
-- posts_select_visible applies and image access exactly tracks post visibility.
-- DO NOT wrap this predicate in a SECURITY DEFINER helper: definer rights bypass
-- that RLS and would make every image readable by every authenticated user.
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
        and exists (select 1 from public.posts p where p.id = pm.post_id)
    )
  )
);
