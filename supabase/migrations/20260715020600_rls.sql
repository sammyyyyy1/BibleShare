-- ============================================================
-- Helper functions (SECURITY DEFINER bypass RLS to avoid recursion).
-- ============================================================
create or replace function public.is_group_member(g uuid, u uuid)
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (select 1 from public.group_members where group_id = g and user_id = u);
$$;

create or replace function public.is_friend(a uuid, b uuid)
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester_id = a and addressee_id = b)
        or (requester_id = b and addressee_id = a))
  );
$$;

grant execute on function public.is_group_member(uuid,uuid) to authenticated;
grant execute on function public.is_friend(uuid,uuid) to authenticated;
-- Postgres grants EXECUTE to PUBLIC by default on new functions, and Supabase's
-- default privileges additionally grant it explicitly to anon/authenticated/
-- service_role; revoke both so anon (unauthenticated) callers cannot probe
-- friendship/membership via RPC (e.g. /rest/v1/rpc/is_friend) without signing in.
revoke execute on function public.is_group_member(uuid,uuid) from public;
revoke execute on function public.is_friend(uuid,uuid) from public;
revoke execute on function public.is_group_member(uuid,uuid) from anon;
revoke execute on function public.is_friend(uuid,uuid) from anon;

-- Additional helper (SECURITY DEFINER) so that posts_select_visible never
-- issues a plain (RLS-checked) subquery against post_groups: post_groups'
-- own select policy queries posts, which would otherwise recurse back into
-- posts_select_visible -> post_groups -> posts -> ... (infinite recursion).
-- Routing the post_groups lookup through a SECURITY DEFINER function keeps
-- the read inside the function's (table-owner) privileges, bypassing RLS,
-- and breaks the cycle.
create or replace function public.post_in_visible_group(p_post_id uuid, u uuid)
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (
    select 1 from public.post_groups pg
    where pg.post_id = p_post_id
      and public.is_group_member(pg.group_id, u)
  );
$$;

grant execute on function public.post_in_visible_group(uuid,uuid) to authenticated;
revoke execute on function public.post_in_visible_group(uuid,uuid) from public;
revoke execute on function public.post_in_visible_group(uuid,uuid) from anon;

-- ============================================================
-- posts: replace public-read with visibility rule.
-- ============================================================
drop policy if exists "Posts are viewable by everyone" on public.posts;
create policy posts_select_visible on public.posts for select using (
  author_id = (select auth.uid())
  or (shared_to_timeline and public.is_friend(author_id, (select auth.uid())))
  or public.post_in_visible_group(posts.id, (select auth.uid()))
);
-- (author-scoped insert/update/delete policies from the initial migration are kept.)

-- ============================================================
-- likes / comments: gate on parent-post visibility.
-- ============================================================
drop policy if exists "Likes are viewable by everyone" on public.likes;
create policy likes_select_visible on public.likes for select using (
  exists (select 1 from public.posts p where p.id = likes.post_id)
);
drop policy if exists "Users can like as themselves" on public.likes;
create policy likes_insert_self on public.likes for insert with check (
  user_id = (select auth.uid())
  and exists (select 1 from public.posts p where p.id = post_id)
);

drop policy if exists "Comments are viewable by everyone" on public.comments;
create policy comments_select_visible on public.comments for select using (
  exists (select 1 from public.posts p where p.id = comments.post_id)
);
drop policy if exists "Users can create their own comments" on public.comments;
create policy comments_insert_self on public.comments for insert with check (
  author_id = (select auth.uid())
  and exists (select 1 from public.posts p where p.id = post_id)
);

-- ============================================================
-- groups & membership
-- ============================================================
alter table public.groups enable row level security;
create policy groups_select_member_or_invited on public.groups for select using (
  public.is_group_member(id, (select auth.uid()))
  or exists (
    select 1 from public.group_invites gi
    where gi.group_id = groups.id
      and gi.invitee_id = (select auth.uid())
      and gi.status = 'pending'
  )
);

alter table public.group_members enable row level security;
create policy gm_select_same_group on public.group_members for select using (
  public.is_group_member(group_id, (select auth.uid()))
);

alter table public.group_invites enable row level security;
create policy gi_select_parties on public.group_invites for select using (
  invitee_id = (select auth.uid()) or inviter_id = (select auth.uid())
);

-- ============================================================
-- check-in windows & ledger (members only)
-- ============================================================
alter table public.group_checkin_windows enable row level security;
create policy gcw_select_member on public.group_checkin_windows for select using (
  public.is_group_member(group_id, (select auth.uid()))
);

alter table public.group_checkins enable row level security;
create policy gc_select_member on public.group_checkins for select using (
  public.is_group_member(group_id, (select auth.uid()))
);

-- ============================================================
-- post targeting & attachments: SELECT via visible parent; INSERT via owner.
-- ============================================================
alter table public.post_groups enable row level security;
create policy pg_select_visible on public.post_groups for select using (
  exists (select 1 from public.posts p where p.id = post_groups.post_id)
);
create policy pg_insert_owner_member on public.post_groups for insert with check (
  exists (select 1 from public.posts p where p.id = post_id and p.author_id = (select auth.uid()))
  and public.is_group_member(group_id, (select auth.uid()))
);

alter table public.post_verses enable row level security;
create policy pv_select_visible on public.post_verses for select using (
  exists (select 1 from public.posts p where p.id = post_verses.post_id)
);
create policy pv_insert_owner on public.post_verses for insert with check (
  exists (select 1 from public.posts p where p.id = post_id and p.author_id = (select auth.uid()))
);

alter table public.post_media enable row level security;
create policy pm_select_visible on public.post_media for select using (
  exists (select 1 from public.posts p where p.id = post_media.post_id)
);
create policy pm_insert_owner on public.post_media for insert with check (
  exists (select 1 from public.posts p where p.id = post_id and p.author_id = (select auth.uid()))
);

alter table public.post_tags enable row level security;
create policy pt_select_visible on public.post_tags for select using (
  exists (select 1 from public.posts p where p.id = post_tags.post_id)
);
create policy pt_insert_owner on public.post_tags for insert with check (
  exists (select 1 from public.posts p where p.id = post_id and p.author_id = (select auth.uid()))
);

-- ============================================================
-- friendships (parties only; writes via RPC later)
-- ============================================================
alter table public.friendships enable row level security;
create policy fr_select_parties on public.friendships for select using (
  requester_id = (select auth.uid()) or addressee_id = (select auth.uid())
);

-- ============================================================
-- notifications & device tokens (owner only)
-- ============================================================
alter table public.notifications enable row level security;
create policy notif_select_own on public.notifications for select using (
  recipient_id = (select auth.uid())
);
create policy notif_update_read on public.notifications for update using (
  recipient_id = (select auth.uid())
) with check (recipient_id = (select auth.uid()));

alter table public.device_tokens enable row level security;
create policy dt_all_own on public.device_tokens for all using (
  user_id = (select auth.uid())
) with check (user_id = (select auth.uid()));
