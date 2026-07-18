-- Add FKs from friendships.requester_id / addressee_id to public.profiles(id),
-- alongside the existing auth.users FKs, so the friends list can embed both
-- parties' profiles in one query (mirrors 20260716010400_profile_fks.sql).
-- public.profiles has exactly one row per auth user (handle_new_user trigger),
-- so these are always satisfiable.

do $$
begin
  alter table public.friendships drop constraint if exists friendships_requester_id_profiles_fkey;
  alter table public.friendships
    add constraint friendships_requester_id_profiles_fkey
    foreign key (requester_id) references public.profiles (id) on delete cascade;
end $$;

do $$
begin
  alter table public.friendships drop constraint if exists friendships_addressee_id_profiles_fkey;
  alter table public.friendships
    add constraint friendships_addressee_id_profiles_fkey
    foreign key (addressee_id) references public.profiles (id) on delete cascade;
end $$;

-- Ensure PostgREST picks up the new relationships immediately.
notify pgrst, 'reload schema';
