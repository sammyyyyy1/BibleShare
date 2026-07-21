-- Plan 5 Task 2 review fix (Important #2): drop the post_groups INSERT policy.
--
-- pg_insert_owner_member (Plan 1) allowed a direct client insert when the caller
-- owned the post AND was a member of the target group — but it never constrained
-- posts.kind. Once check-ins exist, that lets an author fan their own check_in
-- post into another group they belong to with NO active-window assertion and NO
-- group_checkins ledger row, while active_checkin_targets still reports that
-- group unanswered (so they can also check in properly => two check-in posts for
-- one window).
--
-- Safe to drop: no client path inserts post_groups (the only client use is the
-- group-timeline SELECT in Services/GroupService.swift). Every post_groups write
-- happens inside create_encouragement / check_in, which are SECURITY DEFINER and
-- bypass RLS entirely — they never relied on this policy. post_groups keeps its
-- SELECT policy (pg_select_visible), so the RPCs remain the only write path,
-- matching group_checkins and the group tables.

drop policy if exists pg_insert_owner_member on public.post_groups;
