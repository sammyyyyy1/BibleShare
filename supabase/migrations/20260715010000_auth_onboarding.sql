-- Auth onboarding: username gate support.

-- 1. Flag: has the user chosen a real username yet?
alter table public.profiles
    add column if not exists username_set boolean not null default false;

-- 2. Case-insensitive uniqueness for usernames.
create unique index if not exists profiles_username_lower_idx
    on public.profiles (lower(username));

-- 3. Format constraint: 3-20 chars, letters/numbers/underscore.
alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles
    add constraint profiles_username_format
    check (username ~ '^[A-Za-z0-9_]{3,20}$');

-- 4. Auto-create a profile row for every new auth user (email OR oauth).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username, username_set, display_name)
  values (
    new.id,
    'user_' || substr(replace(new.id::text, '-', ''), 1, 12),
    false,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 5. Availability check used by the client (does not expose the table).
create or replace function public.is_username_available(candidate text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select
    candidate ~ '^[A-Za-z0-9_]{3,20}$'
    and not exists (
      select 1 from public.profiles where lower(username) = lower(candidate)
    );
$$;

grant execute on function public.is_username_available(text) to authenticated;
