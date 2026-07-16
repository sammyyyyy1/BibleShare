-- Extend posts to carry both encouragements and check-ins.

alter table public.posts add column if not exists kind text not null default 'encouragement';
alter table public.posts drop constraint if exists posts_kind_check;
alter table public.posts add constraint posts_kind_check
  check (kind in ('encouragement','check_in'));

alter table public.posts add column if not exists title text;
alter table public.posts add column if not exists shared_to_timeline boolean not null default false;

-- content -> body (nullable). Guarded so the migration is safe to re-run.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='posts' and column_name='content'
  ) then
    alter table public.posts rename column content to body;
  end if;
end $$;
alter table public.posts alter column body drop not null;

-- media_url is superseded by the post_media table (Task 4).
alter table public.posts drop column if exists media_url;

-- Integrity rules.
alter table public.posts drop constraint if exists posts_encouragement_title;
alter table public.posts add constraint posts_encouragement_title
  check (kind <> 'encouragement' or title is not null);

alter table public.posts drop constraint if exists posts_checkin_not_timeline;
alter table public.posts add constraint posts_checkin_not_timeline
  check (kind <> 'check_in' or shared_to_timeline = false);

create index if not exists posts_kind_idx on public.posts (kind);
create index if not exists posts_timeline_idx
  on public.posts (created_at desc) where shared_to_timeline;
