-- Friend write path. friendships has NO insert/update/delete RLS policies, so
-- these RPCs are the only write boundary; SECURITY DEFINER is safe because the
-- caller's identity comes from auth.uid(), never from a parameter.

create or replace function public.send_friend_request(p_addressee_username text)
returns public.friendships
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_them uuid;
  v_row  public.friendships;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  -- Resolve the username here (bypasses the profiles lockdown; exact match only).
  select id into v_them
  from public.profiles
  where lower(username) = lower(btrim(coalesce(p_addressee_username, '')))
  limit 1;

  if v_them is null then
    raise exception 'username not found' using errcode = '22023';
  end if;

  if v_them = v_uid then
    raise exception 'cannot send a friend request to yourself' using errcode = '22023';
  end if;

  -- Already friends (either direction)?
  if exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester_id = v_uid  and addressee_id = v_them)
        or (requester_id = v_them and addressee_id = v_uid))
  ) then
    raise exception 'already friends' using errcode = '22023';
  end if;

  -- Reciprocal pending (them -> me): auto-accept theirs, never a second row.
  select * into v_row
  from public.friendships
  where requester_id = v_them and addressee_id = v_uid and status = 'pending';

  if found then
    update public.friendships
       set status = 'accepted', responded_at = now()
     where requester_id = v_them and addressee_id = v_uid
    returning * into v_row;
    return v_row;
  end if;

  -- My own pending request (me -> them): idempotent.
  select * into v_row
  from public.friendships
  where requester_id = v_uid and addressee_id = v_them and status = 'pending';

  if found then
    return v_row;
  end if;

  begin
    insert into public.friendships (requester_id, addressee_id)
    values (v_uid, v_them)
    returning * into v_row;
    return v_row;
  exception when unique_violation then
    -- A reciprocal them->me pending row raced in between the checks above and
    -- this insert (trips friendships_unordered_uniq): accept it instead.
    update public.friendships
       set status = 'accepted', responded_at = now()
     where requester_id = v_them and addressee_id = v_uid and status = 'pending'
    returning * into v_row;
    if found then
      return v_row;
    end if;
    -- Otherwise the pair row exists in some other shape (our own duplicate
    -- raced, or the reciprocal was accepted concurrently): return it as-is.
    -- friendships_unordered_uniq guarantees at most one row for the pair.
    select * into v_row
    from public.friendships
    where (requester_id = v_uid  and addressee_id = v_them)
       or (requester_id = v_them and addressee_id = v_uid);
    return v_row;
  end;
end;
$$;

create or replace function public.respond_to_friend_request(p_requester_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if coalesce(p_accept, false) then
    update public.friendships
       set status = 'accepted', responded_at = now()
     where requester_id = p_requester_id
       and addressee_id = v_uid
       and status = 'pending';
    if not found then
      raise exception 'no pending friend request from that user' using errcode = '22023';
    end if;
  else
    -- Decline deletes the row; idempotent (already-gone is a no-op).
    delete from public.friendships
     where requester_id = p_requester_id
       and addressee_id = v_uid
       and status = 'pending';
  end if;
end;
$$;

revoke execute on function public.send_friend_request(text) from public, anon;
grant  execute on function public.send_friend_request(text) to authenticated;
revoke execute on function public.respond_to_friend_request(uuid, boolean) from public, anon;
grant  execute on function public.respond_to_friend_request(uuid, boolean) to authenticated;
