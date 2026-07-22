-- Harden SECURITY DEFINER function grants.
-- Applied live before the Plan-1 work (live version 20260715203115); the file was
-- stranded on an abandoned branch and is restored here so the repo's migration
-- history matches the database. Ordered between auth_onboarding and posts_extend,
-- which is where it ran. Verified against the live ACLs: handle_new_user has no
-- anon/authenticated EXECUTE, is_username_available has authenticated only.
-- Supabase's default privileges on the `public` schema auto-grant EXECUTE on every
-- new function to both `anon` and `authenticated`, which surfaces the two functions
-- from 20260715010000_auth_onboarding.sql as Supabase security-advisor WARNs. Lock
-- them down to only the roles that actually need them. (PUBLIC is revoked too for
-- hygiene, though the live grants here are the explicit anon/authenticated ones.)

-- handle_new_user() is a trigger function; it is never called directly via RPC.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- is_username_available(text) is called by the client only after sign-in, so anon
-- has no legitimate reason to probe username existence.
revoke execute on function public.is_username_available(text) from public, anon;
grant execute on function public.is_username_available(text) to authenticated;
