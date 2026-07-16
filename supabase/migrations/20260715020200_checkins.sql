create table if not exists public.group_checkin_windows (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  opens_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (group_id, opens_at)
);
create index if not exists gcw_group_opens_idx
  on public.group_checkin_windows(group_id, opens_at desc);

create table if not exists public.group_checkins (
  group_id  uuid not null references public.groups(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  window_id uuid not null references public.group_checkin_windows(id) on delete cascade,
  post_id   uuid not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (group_id, user_id, window_id)
);
create index if not exists group_checkins_user_idx on public.group_checkins(user_id);
create index if not exists group_checkins_post_idx on public.group_checkins(post_id);
