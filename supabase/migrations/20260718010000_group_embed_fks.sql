-- Add FKs to public.profiles(id) alongside the existing auth.users FKs so the
-- group member list and invite rows can embed profiles in one PostgREST query
-- (mirrors 20260717010000_friend_embed_fks.sql). public.profiles has exactly one
-- row per auth user (handle_new_user trigger), so these are always satisfiable.

do $$ begin
  alter table public.group_members drop constraint if exists group_members_user_id_profiles_fkey;
  alter table public.group_members
    add constraint group_members_user_id_profiles_fkey
    foreign key (user_id) references public.profiles (id) on delete cascade;
end $$;

do $$ begin
  alter table public.group_invites drop constraint if exists group_invites_inviter_id_profiles_fkey;
  alter table public.group_invites
    add constraint group_invites_inviter_id_profiles_fkey
    foreign key (inviter_id) references public.profiles (id) on delete cascade;
end $$;

do $$ begin
  alter table public.group_invites drop constraint if exists group_invites_invitee_id_profiles_fkey;
  alter table public.group_invites
    add constraint group_invites_invitee_id_profiles_fkey
    foreign key (invitee_id) references public.profiles (id) on delete cascade;
end $$;

do $$ begin
  alter table public.groups drop constraint if exists groups_creator_id_profiles_fkey;
  alter table public.groups
    add constraint groups_creator_id_profiles_fkey
    foreign key (creator_id) references public.profiles (id) on delete cascade;
end $$;

notify pgrst, 'reload schema';
