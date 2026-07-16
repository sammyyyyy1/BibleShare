-- Add a second FK from posts.author_id, comments.author_id and
-- post_tags.tagged_user_id to public.profiles(id), alongside the existing
-- auth.users FKs.
--
-- Why: PostgREST resource embedding (author:profiles(*), profiles(*) under
-- post_tags) requires a literal FK between the two named tables. All three
-- columns currently only reference auth.users; profiles is a sibling table
-- with its own FK to the same parent, so PostgREST has no relationship to
-- resolve and every embed request fails with PGRST200. public.profiles has
-- exactly one row per auth user (see handle_new_user trigger in
-- 20260715010000_auth_onboarding.sql), so this FK is safe to add without
-- touching existing data or the auth.users FKs.
--
-- Not added: likes.user_id -> profiles. Nothing embeds profiles from likes.

do $$
begin
  alter table public.posts drop constraint if exists posts_author_id_profiles_fkey;
  alter table public.posts
    add constraint posts_author_id_profiles_fkey
    foreign key (author_id) references public.profiles (id) on delete cascade;
end $$;

do $$
begin
  alter table public.comments drop constraint if exists comments_author_id_profiles_fkey;
  alter table public.comments
    add constraint comments_author_id_profiles_fkey
    foreign key (author_id) references public.profiles (id) on delete cascade;
end $$;

do $$
begin
  alter table public.post_tags drop constraint if exists post_tags_tagged_user_id_profiles_fkey;
  alter table public.post_tags
    add constraint post_tags_tagged_user_id_profiles_fkey
    foreign key (tagged_user_id) references public.profiles (id) on delete cascade;
end $$;

-- Ensure PostgREST picks up the new relationships immediately.
notify pgrst, 'reload schema';
