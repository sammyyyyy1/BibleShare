create table if not exists public.post_groups (
  post_id uuid not null references public.posts(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, group_id)
);
create index if not exists post_groups_group_idx
  on public.post_groups(group_id, created_at desc);

create table if not exists public.post_verses (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  translation text not null default 'WEB',
  book text not null,
  chapter int not null,
  verse_start int not null,
  verse_end int not null,
  reference_label text not null,
  text_snapshot text not null,
  position int not null default 0
);
create index if not exists post_verses_post_idx on public.post_verses(post_id);

create table if not exists public.post_media (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  media_type text not null check (media_type in ('image','link')),
  url text not null,
  thumbnail_url text,
  title text,
  description text,
  position int not null default 0
);
create index if not exists post_media_post_idx on public.post_media(post_id);

create table if not exists public.post_tags (
  post_id uuid not null references public.posts(id) on delete cascade,
  tagged_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, tagged_user_id)
);
create index if not exists post_tags_user_idx on public.post_tags(tagged_user_id);
