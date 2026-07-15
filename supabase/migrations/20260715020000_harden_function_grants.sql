-- Harden SECURITY DEFINER function grants.
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
