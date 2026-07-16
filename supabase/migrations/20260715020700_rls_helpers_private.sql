-- Move RLS helper functions into a non-exposed `private` schema so they are not
-- reachable as PostgREST RPC endpoints. Previously public.is_friend /
-- is_group_member / post_in_visible_group were callable by any authenticated user
-- via /rest/v1/rpc/... with arbitrary UUIDs, letting a signed-in user probe the
-- entire friendship/group-membership graph (profiles are world-readable, so user
-- ids are enumerable). RLS policies still call them; they just live in a schema
-- PostgREST does not expose. (Cannot revoke from `authenticated` — RLS policy
-- expressions are evaluated as the querying role.)

create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.is_group_member(g uuid, u uuid)
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (select 1 from public.group_members where group_id = g and user_id = u);
$$;

create or replace function private.is_friend(a uuid, b uuid)
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester_id = a and addressee_id = b)
        or (requester_id = b and addressee_id = a))
  );
$$;

create or replace function private.post_in_visible_group(p_post_id uuid, u uuid)
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (
    select 1 from public.post_groups pg
    where pg.post_id = p_post_id
      and private.is_group_member(pg.group_id, u)
  );
$$;

revoke execute on function private.is_group_member(uuid,uuid) from public;
revoke execute on function private.is_friend(uuid,uuid) from public;
revoke execute on function private.post_in_visible_group(uuid,uuid) from public;
grant execute on function private.is_group_member(uuid,uuid) to authenticated;
grant execute on function private.is_friend(uuid,uuid) to authenticated;
grant execute on function private.post_in_visible_group(uuid,uuid) to authenticated;

-- Repoint every policy that referenced the public.* helpers to private.*
drop policy if exists posts_select_visible on public.posts;
create policy posts_select_visible on public.posts for select using (
  author_id = (select auth.uid())
  or (shared_to_timeline and private.is_friend(author_id, (select auth.uid())))
  or private.post_in_visible_group(posts.id, (select auth.uid()))
);

drop policy if exists groups_select_member_or_invited on public.groups;
create policy groups_select_member_or_invited on public.groups for select using (
  private.is_group_member(id, (select auth.uid()))
  or exists (
    select 1 from public.group_invites gi
    where gi.group_id = groups.id
      and gi.invitee_id = (select auth.uid())
      and gi.status = 'pending'
  )
);

drop policy if exists gm_select_same_group on public.group_members;
create policy gm_select_same_group on public.group_members for select using (
  private.is_group_member(group_id, (select auth.uid()))
);

drop policy if exists gcw_select_member on public.group_checkin_windows;
create policy gcw_select_member on public.group_checkin_windows for select using (
  private.is_group_member(group_id, (select auth.uid()))
);

drop policy if exists gc_select_member on public.group_checkins;
create policy gc_select_member on public.group_checkins for select using (
  private.is_group_member(group_id, (select auth.uid()))
);

drop policy if exists pg_insert_owner_member on public.post_groups;
create policy pg_insert_owner_member on public.post_groups for insert with check (
  exists (select 1 from public.posts p where p.id = post_id and p.author_id = (select auth.uid()))
  and private.is_group_member(group_id, (select auth.uid()))
);

-- The public.* helpers are now unreferenced; drop them (removes the RPC endpoints).
drop function if exists public.post_in_visible_group(uuid,uuid);
drop function if exists public.is_friend(uuid,uuid);
drop function if exists public.is_group_member(uuid,uuid);
