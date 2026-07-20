-- profiles lockdown. The old "Profiles are viewable by everyone" policy let any
-- signed-in client enumerate every username/display name/bio via a `like`
-- filter. Now that a real friends model exists, visibility is: yourself,
-- anyone you share a friendship row with (any status — the friends sheet
-- embeds pending parties), and profiles surfaced by content you can already
-- see (tagged users / comment authors on visible posts). The inner posts
-- EXISTS run as the invoker under posts_select_visible, so visibility tracks
-- the post and reopens no enumeration surface. Likes need no clause (the feed
-- shows like counts, never liker profiles).

create or replace function private.friendship_exists(a uuid, b uuid)
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (
    select 1 from public.friendships
    where (requester_id = a and addressee_id = b)
       or (requester_id = b and addressee_id = a)
  );
$$;

revoke execute on function private.friendship_exists(uuid,uuid) from public;
grant  execute on function private.friendship_exists(uuid,uuid) to authenticated;

drop policy if exists "Profiles are viewable by everyone" on public.profiles;
create policy profiles_select_scoped on public.profiles for select using (
  id = (select auth.uid())
  or private.friendship_exists(id, (select auth.uid()))
  or exists (
    select 1 from public.post_tags pt
    where pt.tagged_user_id = profiles.id
      and exists (select 1 from public.posts p where p.id = pt.post_id)
  )
  or exists (
    select 1 from public.comments c
    where c.author_id = profiles.id
      and exists (select 1 from public.posts p where p.id = c.post_id)
  )
);

-- Exact-username discovery: the ONLY path to a non-connected user's profile.
-- Exact match (no prefix/like), so nothing enumerable.
create or replace function public.find_profile_by_username(p_username text)
returns setof public.profiles
language sql
security definer
stable
set search_path = public
as $$
  select * from public.profiles
  where lower(username) = lower(btrim(coalesce(p_username, '')))
  limit 1;
$$;

revoke execute on function public.find_profile_by_username(text) from public, anon;
grant  execute on function public.find_profile_by_username(text) to authenticated;
