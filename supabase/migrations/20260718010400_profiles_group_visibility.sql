-- Co-members must see each other's profiles: group-post authors, and the
-- members/invitees rendered in group UI. shares_group_with is SECURITY DEFINER
-- so it can read group_members regardless of the invoker's own row visibility;
-- it exposes only a boolean. Added as a new OR clause on profiles_select_scoped
-- (the Plan 3 self / friendship / tagged / commenter clauses are preserved).

create or replace function private.shares_group_with(a uuid, b uuid)
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (
    select 1
    from public.group_members m1
    join public.group_members m2 on m1.group_id = m2.group_id
    where m1.user_id = a and m2.user_id = b
  );
$$;

revoke execute on function private.shares_group_with(uuid,uuid) from public;
grant  execute on function private.shares_group_with(uuid,uuid) to authenticated;

drop policy if exists profiles_select_scoped on public.profiles;
create policy profiles_select_scoped on public.profiles for select using (
  id = (select auth.uid())
  or private.friendship_exists(id, (select auth.uid()))
  or private.shares_group_with(id, (select auth.uid()))
  or exists (
    select 1 from public.post_tags pt
    where pt.tagged_user_id = profiles.id
      and exists (select 1 from public.posts p where p.id = pt.post_id)
  )
  or exists (
    select 1 from public.comments c
    where c.author_id = profiles.id
      and exists (select 1 from public.posts p where p.id = c.post_id)
  )
);
