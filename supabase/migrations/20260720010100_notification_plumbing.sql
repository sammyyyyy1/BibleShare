-- Plan 6 Task 2 — notification & device-token plumbing.

-- === notifications: read-only to clients, mark-read via RPC ===
-- notif_update_read allowed a recipient to UPDATE their ENTIRE row: rewrite
-- `type`, repoint post_id at any post, forge actor_id, or clear pushed_at to
-- force a re-push. Carried from Plan 1's review.
drop policy if exists "notif_update_read" on public.notifications;
revoke update on public.notifications from authenticated;

create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  -- coalesce keeps the ORIGINAL read timestamp when a row is re-marked.
  update public.notifications
     set read_at = coalesce(read_at, now())
   where recipient_id = v_uid
     and read_at is null
     and (p_ids is null or id = any(p_ids));
end;
$$;
revoke execute on function public.mark_notifications_read(uuid[]) from public, anon;
grant execute on function public.mark_notifications_read(uuid[]) to authenticated, service_role;

-- === device_tokens: FOR ALL is the broadest possible client write grant ===
drop policy if exists "dt_all_own" on public.device_tokens;
create policy dt_select_own on public.device_tokens
  for select using (user_id = (select auth.uid()));

create or replace function public.register_device_token(
  p_token text, p_platform text default 'ios'
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if p_token is null or btrim(p_token) = '' then
    raise exception 'a device token is required' using errcode = '22023';
  end if;

  -- APNs tokens are DEVICE-scoped, but the declared PK is (user_id, token),
  -- which lets the same token exist for two users. On a shared device -- or
  -- after logout and a different login -- that pushes one person's
  -- notifications to another person's phone. Registration is authoritative:
  -- the token belongs to whoever most recently registered it.
  delete from public.device_tokens
   where token = btrim(p_token) and user_id <> v_uid;

  insert into public.device_tokens (user_id, token, platform)
  values (v_uid, btrim(p_token), coalesce(nullif(btrim(p_platform), ''), 'ios'))
  on conflict (user_id, token)
    do update set updated_at = now(), platform = excluded.platform;
end;
$$;
revoke execute on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated, service_role;

create or replace function public.unregister_device_token(p_token text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  delete from public.device_tokens
   where user_id = v_uid and token = btrim(coalesce(p_token, ''));
end;
$$;
revoke execute on function public.unregister_device_token(text) from public, anon;
grant execute on function public.unregister_device_token(text) to authenticated, service_role;

-- === profiles: the invite counterparty ===
-- private.friendship_exists is status-agnostic, so a PENDING requester's
-- profile is already visible. There is no equivalent for invites:
-- shares_group_with requires real group_members rows, so an inviter is
-- invisible until you accept -- which already renders Plan 4's invite screen
-- nameless, and would make a group_invite notification unactionable.
-- PENDING ONLY -- deliberately NOT status-agnostic, unlike friendship_exists.
-- That asymmetry is required, not an oversight: respond_to_friend_request's
-- decline path DELETES the friendship row, so a declined request stops
-- granting visibility on its own. respond_to_invite's decline path only sets
-- status='declined' and keeps the row forever, with no expiry -- so a
-- status-agnostic check here would let a declined invite grant the two parties
-- permanent access to each other's profile. Once an invite is ACCEPTED the row
-- becomes 'accepted' and private.shares_group_with takes over, in the same
-- transaction that inserts group_members, so there is no visibility gap.
create or replace function private.invite_counterparty(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.group_invites
    where status = 'pending'
      and ((inviter_id = a and invitee_id = b)
        or (inviter_id = b and invitee_id = a))
  );
$$;
-- Called FROM an RLS policy, so it needs the authenticated grant
-- (matches private.friendship_exists, not private.can_tag).
revoke all on function private.invite_counterparty(uuid, uuid) from public;
grant execute on function private.invite_counterparty(uuid, uuid) to authenticated;

drop policy if exists "profiles_select_scoped" on public.profiles;
create policy profiles_select_scoped on public.profiles for select using (
  id = (select auth.uid())
  or private.friendship_exists(id, (select auth.uid()))
  or private.shares_group_with(id, (select auth.uid()))
  or private.invite_counterparty(id, (select auth.uid()))
  or exists (select 1 from public.post_tags pt
             where pt.tagged_user_id = profiles.id
               and exists (select 1 from public.posts p where p.id = pt.post_id))
  or exists (select 1 from public.comments c
             where c.author_id = profiles.id
               and exists (select 1 from public.posts p where p.id = c.post_id))
);

-- === PostgREST embed FK ===
-- notifications.actor_id references auth.users, which PostgREST cannot embed a
-- profiles row through. Same redundant-FK technique as Plan 2's profile_fks.
alter table public.notifications
  add constraint notifications_actor_id_profiles_fkey
  foreign key (actor_id) references public.profiles(id) on delete cascade;
