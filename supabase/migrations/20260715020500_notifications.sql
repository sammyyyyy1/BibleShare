create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in (
    'checkin_reminder','member_checked_in','friend_request','friend_accepted',
    'group_invite','post_like','post_comment','post_tag')),
  actor_id uuid references auth.users(id) on delete cascade,
  group_id uuid references public.groups(id) on delete cascade,
  post_id  uuid references public.posts(id) on delete cascade,
  read_at timestamptz,
  pushed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_recipient_idx
  on public.notifications(recipient_id, created_at desc);
create index if not exists notifications_unpushed_idx
  on public.notifications(created_at) where pushed_at is null;

create table if not exists public.device_tokens (
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null default 'ios',
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);
