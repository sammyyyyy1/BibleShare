-- BibleShare initial schema
-- Tables: profiles, posts, follows, likes, comments
-- Row Level Security enabled on all tables with baseline policies:
--   * public read (any authenticated/anon user can SELECT)
--   * users may only write/edit/delete their own rows

-- =========================================================
-- profiles  (1:1 with auth.users)
-- =========================================================
create table if not exists public.profiles (
    id           uuid primary key references auth.users (id) on delete cascade,
    username     text unique not null,
    display_name text,
    avatar_url   text,
    bio          text,
    created_at   timestamptz not null default now()
);

-- =========================================================
-- posts
-- =========================================================
create table if not exists public.posts (
    id         uuid primary key default gen_random_uuid(),
    author_id  uuid not null references auth.users (id) on delete cascade,
    content    text not null,
    media_url  text,
    created_at timestamptz not null default now()
);
create index if not exists posts_author_id_idx on public.posts (author_id);
create index if not exists posts_created_at_idx on public.posts (created_at desc);

-- =========================================================
-- follows  (follower_id follows followee_id)
-- =========================================================
create table if not exists public.follows (
    follower_id uuid not null references auth.users (id) on delete cascade,
    followee_id uuid not null references auth.users (id) on delete cascade,
    created_at  timestamptz not null default now(),
    primary key (follower_id, followee_id),
    constraint follows_no_self check (follower_id <> followee_id)
);
create index if not exists follows_followee_id_idx on public.follows (followee_id);

-- =========================================================
-- likes  (a user likes a post)
-- =========================================================
create table if not exists public.likes (
    user_id    uuid not null references auth.users (id) on delete cascade,
    post_id    uuid not null references public.posts (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, post_id)
);
create index if not exists likes_post_id_idx on public.likes (post_id);

-- =========================================================
-- comments
-- =========================================================
create table if not exists public.comments (
    id         uuid primary key default gen_random_uuid(),
    post_id    uuid not null references public.posts (id) on delete cascade,
    author_id  uuid not null references auth.users (id) on delete cascade,
    content    text not null,
    created_at timestamptz not null default now()
);
create index if not exists comments_post_id_idx on public.comments (post_id);
create index if not exists comments_author_id_idx on public.comments (author_id);

-- =========================================================
-- Row Level Security
-- =========================================================
alter table public.profiles enable row level security;
alter table public.posts    enable row level security;
alter table public.follows  enable row level security;
alter table public.likes    enable row level security;
alter table public.comments enable row level security;

-- ---- profiles ----
create policy "Profiles are viewable by everyone"
    on public.profiles for select using (true);
create policy "Users can insert their own profile"
    on public.profiles for insert with check ((select auth.uid()) = id);
create policy "Users can update their own profile"
    on public.profiles for update using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

-- ---- posts ----
create policy "Posts are viewable by everyone"
    on public.posts for select using (true);
create policy "Users can create their own posts"
    on public.posts for insert with check ((select auth.uid()) = author_id);
create policy "Users can update their own posts"
    on public.posts for update using ((select auth.uid()) = author_id) with check ((select auth.uid()) = author_id);
create policy "Users can delete their own posts"
    on public.posts for delete using ((select auth.uid()) = author_id);

-- ---- follows ----
create policy "Follows are viewable by everyone"
    on public.follows for select using (true);
create policy "Users can follow (insert as themselves)"
    on public.follows for insert with check ((select auth.uid()) = follower_id);
create policy "Users can unfollow (delete their own follow)"
    on public.follows for delete using ((select auth.uid()) = follower_id);

-- ---- likes ----
create policy "Likes are viewable by everyone"
    on public.likes for select using (true);
create policy "Users can like as themselves"
    on public.likes for insert with check ((select auth.uid()) = user_id);
create policy "Users can remove their own like"
    on public.likes for delete using ((select auth.uid()) = user_id);

-- ---- comments ----
create policy "Comments are viewable by everyone"
    on public.comments for select using (true);
create policy "Users can create their own comments"
    on public.comments for insert with check ((select auth.uid()) = author_id);
create policy "Users can update their own comments"
    on public.comments for update using ((select auth.uid()) = author_id) with check ((select auth.uid()) = author_id);
create policy "Users can delete their own comments"
    on public.comments for delete using ((select auth.uid()) = author_id);
