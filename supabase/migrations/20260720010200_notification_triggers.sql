-- Plan 6 Task 3 — notification triggers.
--
-- All eight types are AFTER triggers so a notification is owed whenever the
-- row exists, not whenever a particular function was called. Two of the eight
-- (likes, comments) have no RPC at all -- they are direct client inserts --
-- so triggers were mandatory there regardless; uniformity buys the rest.

-- === Dedupe indexes ===
-- post_comment is deliberately absent: each comment is a distinct event and
-- collapsing them would hide replies.
create unique index if not exists notifications_like_uniq
  on public.notifications (recipient_id, actor_id, post_id) where type = 'post_like';
-- The load-bearing one: a single check_in fans one post to N groups, so a user
-- in TWO targeted groups would otherwise get two notifications for one post.
create unique index if not exists notifications_checkin_uniq
  on public.notifications (recipient_id, actor_id, post_id) where type = 'member_checked_in';
create unique index if not exists notifications_tag_uniq
  on public.notifications (recipient_id, post_id) where type = 'post_tag';

-- === post_like ===
create or replace function private.tg_notify_post_like()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (recipient_id, type, actor_id, post_id)
  select p.author_id, 'post_like', new.user_id, new.post_id
  from public.posts p
  where p.id = new.post_id and p.author_id <> new.user_id
  on conflict do nothing;
  return null;
end;
$$;
create trigger notify_post_like after insert on public.likes
  for each row execute function private.tg_notify_post_like();

-- === post_comment ===
create or replace function private.tg_notify_post_comment()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (recipient_id, type, actor_id, post_id)
  select p.author_id, 'post_comment', new.author_id, new.post_id
  from public.posts p
  where p.id = new.post_id and p.author_id <> new.author_id;
  return null;
end;
$$;
create trigger notify_post_comment after insert on public.comments
  for each row execute function private.tg_notify_post_comment();

-- === post_tag ===
-- Task 1's gate guarantees the tagged user can see the post, so this cannot
-- notify someone about a post they can't open.
create or replace function private.tg_notify_post_tag()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (recipient_id, type, actor_id, post_id)
  select new.tagged_user_id, 'post_tag', p.author_id, new.post_id
  from public.posts p
  where p.id = new.post_id and p.author_id <> new.tagged_user_id
  on conflict do nothing;
  return null;
end;
$$;
create trigger notify_post_tag after insert on public.post_tags
  for each row execute function private.tg_notify_post_tag();

-- === member_checked_in ===
-- Plan 5 rewrote check_in from `exception when unique_violation` to
-- `on conflict do nothing` + `if not found` SPECIFICALLY so this trigger's
-- index conflict could not be re-reported to the user as "already checked in".
-- That holds: FOUND is local to each plpgsql invocation, and a trigger is a
-- separate invocation. Regression-tested in Step 5.
create or replace function private.tg_notify_member_checked_in()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (recipient_id, type, actor_id, group_id, post_id)
  select m.user_id, 'member_checked_in', new.user_id, new.group_id, new.post_id
  from public.group_members m
  where m.group_id = new.group_id and m.user_id <> new.user_id
  on conflict do nothing;
  return null;
end;
$$;
create trigger notify_member_checked_in after insert on public.group_checkins
  for each row execute function private.tg_notify_member_checked_in();

-- === checkin_reminder ===
-- Idempotent for free: group_checkin_windows has unique(group_id, opens_at)
-- and the opener inserts with `on conflict do nothing`, so this fires at most
-- once per window. System-generated, so actor_id stays null.
--
-- MUST STAY TRIVIAL. private.open_checkin_windows wraps its insert in
-- `exception when others then raise warning`, so anything that raises here
-- rolls back that group's window and is swallowed as a warning -- the window
-- silently never opens. Task 4's watchdog exists to catch exactly that.
create or replace function private.tg_notify_checkin_reminder()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (recipient_id, type, group_id)
  select m.user_id, 'checkin_reminder', new.group_id
  from public.group_members m
  where m.group_id = new.group_id;
  return null;
end;
$$;
create trigger notify_checkin_reminder after insert on public.group_checkin_windows
  for each row execute function private.tg_notify_checkin_reminder();

-- === group_invite ===
-- No dedupe index: invite_to_group returns early on an existing pending invite,
-- and a declined-then-reinvited flow SHOULD produce a fresh notification.
create or replace function private.tg_notify_group_invite()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.invitee_id <> new.inviter_id then
    insert into public.notifications (recipient_id, type, actor_id, group_id)
    values (new.invitee_id, 'group_invite', new.inviter_id, new.group_id);
  end if;
  return null;
end;
$$;
create trigger notify_group_invite after insert on public.group_invites
  for each row execute function private.tg_notify_group_invite();

-- === friend_request ===
create or replace function private.tg_notify_friend_request()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending' and new.addressee_id <> new.requester_id then
    insert into public.notifications (recipient_id, type, actor_id)
    values (new.addressee_id, 'friend_request', new.requester_id);
  end if;
  return null;
end;
$$;
create trigger notify_friend_request after insert on public.friendships
  for each row execute function private.tg_notify_friend_request();

-- === friend_accepted ===
-- The WHEN clause fires on the transition only, which covers all three accept
-- sites -- respond_to_friend_request, send_friend_request's reciprocal
-- auto-accept, and its unique_violation race handler -- because all three are
-- UPDATE ... SET status='accepted'. The accepter is always the addressee.
create or replace function private.tg_notify_friend_accepted()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.requester_id <> new.addressee_id then
    insert into public.notifications (recipient_id, type, actor_id)
    values (new.requester_id, 'friend_accepted', new.addressee_id);
  end if;
  return null;
end;
$$;
create trigger notify_friend_accepted after update on public.friendships
  for each row
  when (old.status is distinct from 'accepted' and new.status = 'accepted')
  execute function private.tg_notify_friend_accepted();

-- Trigger functions are invoked by the executor, not by the calling user, so
-- no EXECUTE grant is needed. Revoke the PUBLIC default anyway.
revoke all on function private.tg_notify_post_like() from public;
revoke all on function private.tg_notify_post_comment() from public;
revoke all on function private.tg_notify_post_tag() from public;
revoke all on function private.tg_notify_member_checked_in() from public;
revoke all on function private.tg_notify_checkin_reminder() from public;
revoke all on function private.tg_notify_group_invite() from public;
revoke all on function private.tg_notify_friend_request() from public;
revoke all on function private.tg_notify_friend_accepted() from public;
