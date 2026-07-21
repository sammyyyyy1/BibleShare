-- Plan 5 final-review fix (Important #2): drop the posts UPDATE policy.
--
-- "Users can update their own posts" (initial schema) is column-unrestricted:
-- using/with check ((select auth.uid()) = author_id). An author could PATCH
-- their own kind='check_in' post to kind='encouragement',
-- shared_to_timeline=true, landing it on their personal timeline while its
-- group_checkins ledger row still records a check-in for that window — a
-- content/ledger split the RPC surface never intends to allow.
--
-- Verified (grep) that no client code updates posts: Services/FeedService.swift
-- and Services/PostService.swift only .from("posts") for select/delete; the
-- only .update( call in the codebase targets profiles
-- (Services/SupabaseService.swift). There is no client post-edit path.
--
-- Same principle as 20260719010150_drop_post_groups_insert_policy.sql: direct
-- client writes to the post graph are not part of the design. create_encouragement
-- and check_in (SECURITY DEFINER) are the only intended write path, and neither
-- ever performs an UPDATE on posts, so this policy served no legitimate use.

drop policy if exists "Users can update their own posts" on public.posts;
