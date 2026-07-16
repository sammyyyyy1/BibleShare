create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  description text,
  checkin_cadence text not null default 'none'
    check (checkin_cadence in ('none','daily','weekly')),
  checkin_time time,
  checkin_weekday int check (checkin_weekday between 0 and 6),
  timezone text not null default 'America/New_York',
  created_at timestamptz not null default now(),
  constraint groups_cadence_needs_time
    check (checkin_cadence = 'none' or checkin_time is not null),
  constraint groups_weekly_needs_weekday
    check (checkin_cadence <> 'weekly' or checkin_weekday is not null)
);

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('creator','member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists group_members_user_idx on public.group_members(user_id);

create table if not exists public.group_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  inviter_id uuid not null references auth.users(id) on delete cascade,
  invitee_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz
);
create unique index if not exists group_invites_unique_pending
  on public.group_invites(group_id, invitee_id) where status = 'pending';
