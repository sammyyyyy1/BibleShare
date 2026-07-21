-- invite_to_group: creator-only. group_invites/group_members have NO write
-- policies, so this RPC is the only write boundary. Idempotent on a pending
-- invite; unique_violation-safe against group_invites_unique_pending.

create or replace function public.invite_to_group(p_group_id uuid, p_invitee_username text)
returns public.group_invites
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_them uuid;
  v_row  public.group_invites;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  -- Creator-only.
  if not exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = v_uid and role = 'creator'
  ) then
    raise exception 'only the group creator can invite' using errcode = '42501';
  end if;

  -- Resolve the username here (exact, case-insensitive; bypasses the lockdown).
  select id into v_them
  from public.profiles
  where lower(username) = lower(btrim(coalesce(p_invitee_username, '')))
  limit 1;

  if v_them is null then
    raise exception 'username not found' using errcode = '22023';
  end if;

  if v_them = v_uid then
    raise exception 'you are already in this group' using errcode = '22023';
  end if;

  if exists (select 1 from public.group_members where group_id = p_group_id and user_id = v_them) then
    raise exception 'that user is already a member' using errcode = '22023';
  end if;

  -- Idempotent: an existing pending invite is returned unchanged. A prior
  -- declined row does not block a fresh pending (the unique index is pending-only).
  select * into v_row
  from public.group_invites
  where group_id = p_group_id and invitee_id = v_them and status = 'pending';
  if found then
    return v_row;
  end if;

  begin
    insert into public.group_invites (group_id, inviter_id, invitee_id)
    values (p_group_id, v_uid, v_them)
    returning * into v_row;
    return v_row;
  exception when unique_violation then
    -- A concurrent pending invite raced in (trips group_invites_unique_pending):
    -- return the winner rather than erroring.
    select * into v_row
    from public.group_invites
    where group_id = p_group_id and invitee_id = v_them and status = 'pending';
    return v_row;
  end;
end;
$$;

-- respond_to_invite: invitee-only. Accept adds the member row + stamps status;
-- decline stamps status. Both idempotent (0 rows updated = no-op, no error on decline).

create or replace function public.respond_to_invite(p_invite_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_group uuid;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if coalesce(p_accept, false) then
    update public.group_invites
       set status = 'accepted', responded_at = now()
     where id = p_invite_id and invitee_id = v_uid and status = 'pending'
    returning group_id into v_group;
    if not found then
      raise exception 'no pending invite' using errcode = '22023';
    end if;
    insert into public.group_members (group_id, user_id, role)
    values (v_group, v_uid, 'member')
    on conflict (group_id, user_id) do nothing;
  else
    update public.group_invites
       set status = 'declined', responded_at = now()
     where id = p_invite_id and invitee_id = v_uid and status = 'pending';
    -- No FOUND check: declining an already-resolved invite is a silent no-op.
  end if;
end;
$$;

revoke execute on function public.invite_to_group(uuid, text) from public, anon;
grant  execute on function public.invite_to_group(uuid, text) to authenticated;
revoke execute on function public.respond_to_invite(uuid, boolean) from public, anon;
grant  execute on function public.respond_to_invite(uuid, boolean) to authenticated;
