# BibleShare — Groups, Encouragements & Check-ins Design

**Date:** 2026-07-15
**Status:** Approved (design), pending implementation plan
**Scope:** The core social layer — Groups (with per-group check-in schedules), Encouragements and Check-ins (unified post model), post attachments (Bible verses, photos/links, user tags), likes & comments on all posts, Friends (request/accept), the Home feed, per-group timelines, and a notification system (in-app + APNs push driven by `pg_cron` and an Edge Function).

Builds on the shipped auth/onboarding layer (`profiles`, `posts`, `likes`, `comments`) and replaces the placeholder Home shell.

---

## 1. Goals & non-goals

**Goals**
- Users create/join multiple **groups**; the creator invites others by `@username` (invite + accept). Each group has its own timeline.
- Users post **encouragements** to their personal timeline and/or to one or more groups.
- Groups have a creator-set **check-in schedule**. At each scheduled time a check-in *window* opens and members are notified. A user can check in any time until the next scheduled window.
- **Check-in** compose is an explicit multi-select of the user's groups that currently have an unanswered active window; one submission fans out to every selected group's timeline. Check-ins never appear on the personal timeline.
- Members are notified when another member checks in.
- Posts (both kinds) support **likes** (heart) and **comments**.
- **Friends** (request/accept, symmetric). Friends see each other's personal-timeline encouragements on Home; they never see group content for groups they aren't in.
- Notifications delivered **in-app** and via **APNs push** (scheduled reminders via `pg_cron`, delivery via an Edge Function).

**Non-goals (v1)**
- Video media (photos + links only; schema leaves room).
- Public/discoverable groups, join-by-link, roles beyond creator/member.
- Per-member check-in timezones (single group-level timezone).
- Editing a check-in's group targeting after submission; post editing beyond author delete.
- Rich link-unfurl service (store user-provided title/thumbnail; best-effort client preview).
- Full-text Bible search / verse picker autocomplete beyond a reference entry + fetch.

---

## 2. Architecture

Consistent with the existing app: the iOS client talks **directly to Supabase** (PostgREST + Row Level Security) for ordinary reads/writes. Multi-row atomic operations go through **Postgres RPC functions** (`SECURITY DEFINER` where they must bypass RLS in a controlled way). Scheduling uses **`pg_cron`**; push delivery uses **one Edge Function** calling APNs. No custom API server.

```
iOS (SwiftUI, @Observable)
   │  supabase-swift
   ▼
Supabase
   ├── PostgREST + RLS         (feeds, timelines, likes, comments, invites)
   ├── RPC functions           (check_in, respond_to_invite, send/respond friend request, toggle_like)
   ├── Triggers                (create notification rows on like/comment/tag/checkin/invite/friend)
   ├── pg_cron (~15 min)       (open check-in windows, enqueue reminder notifications)
   ├── Storage bucket `media`  (post images)
   └── Edge Function `push`    (drains unpushed notifications → APNs via device_tokens)
```

**Feed strategy:** read-time fan-out (query joins), not write-time fan-out into per-user feed tables. Volumes for an accountability app are small; write-time fan-out is premature. Indexed queries + RLS suffice.

---

## 3. Data model

New/changed tables. Existing `profiles`, `posts`, `likes`, `comments` are extended; `follows` is **dropped**.

### 3.1 posts (extended)

```sql
alter table public.posts add column kind text not null default 'encouragement'
  check (kind in ('encouragement','check_in'));
alter table public.posts add column title text;
alter table public.posts add column shared_to_timeline boolean not null default false;
alter table public.posts rename column content to body;      -- now nullable
alter table public.posts alter column body drop not null;
-- media_url column retired in favor of post_media (kept nullable during migration, then dropped)

-- Integrity:
--  encouragement must have a title
alter table public.posts add constraint posts_encouragement_title
  check (kind <> 'encouragement' or title is not null);
--  check-ins never land on the personal timeline
alter table public.posts add constraint posts_checkin_not_timeline
  check (kind <> 'check_in' or shared_to_timeline = false);
```

A post reaches viewers through two independent channels: `shared_to_timeline=true` (personal timeline, encouragements only) and rows in `post_groups` (group timelines, both kinds). An encouragement may use either or both; a check-in uses only `post_groups`.

### 3.2 groups & membership

```sql
create table public.groups (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  description text,
  checkin_cadence text not null default 'none'
    check (checkin_cadence in ('none','daily','weekly')),
  checkin_time time,                 -- required when cadence <> 'none'
  checkin_weekday int check (checkin_weekday between 0 and 6), -- required when cadence='weekly'
  timezone text not null default 'America/New_York',
  created_at timestamptz not null default now(),
  check (checkin_cadence = 'none' or checkin_time is not null),
  check (checkin_cadence <> 'weekly' or checkin_weekday is not null)
);

create table public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('creator','member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index group_members_user_idx on public.group_members(user_id);

create table public.group_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  inviter_id uuid not null references auth.users(id) on delete cascade,
  invitee_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz
);
create unique index group_invites_unique_pending
  on public.group_invites(group_id, invitee_id) where status = 'pending';
```

### 3.3 check-in windows & ledger

```sql
create table public.group_checkin_windows (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  opens_at timestamptz not null,     -- a scheduled reminder time
  created_at timestamptz not null default now(),
  unique (group_id, opens_at)
);
create index gcw_group_opens_idx on public.group_checkin_windows(group_id, opens_at desc);
-- A group's ACTIVE window = row with greatest opens_at <= now(); it closes when the next row is created.

create table public.group_checkins (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  window_id uuid not null references public.group_checkin_windows(id) on delete cascade,
  post_id  uuid not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (group_id, user_id, window_id)   -- one check-in per user per window per group
);
```

`group_checkins` is the accountability ledger: "does user X have an active check-in for group G?" = an active window exists for G with no matching ledger row for (G, X, window). It also drives the "member checked in" fan-out and per-window participation views. Group timelines stay a single `post_groups` query.

### 3.4 post targeting & attachments

```sql
create table public.post_groups (
  post_id uuid not null references public.posts(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, group_id)
);
create index post_groups_group_idx on public.post_groups(group_id, created_at desc);

create table public.post_verses (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  translation text not null default 'WEB',
  book text not null, chapter int not null,
  verse_start int not null, verse_end int not null,
  reference_label text not null,   -- 'John 3:16–17'
  text_snapshot text not null,     -- cached passage text at compose time
  position int not null default 0
);
create index post_verses_post_idx on public.post_verses(post_id);

create table public.post_media (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  media_type text not null check (media_type in ('image','link')),
  url text not null,
  thumbnail_url text, title text, description text,
  position int not null default 0
);
create index post_media_post_idx on public.post_media(post_id);

create table public.post_tags (
  post_id uuid not null references public.posts(id) on delete cascade,
  tagged_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, tagged_user_id)
);
create index post_tags_user_idx on public.post_tags(tagged_user_id);
```

### 3.5 friends

```sql
create table public.friendships (
  requester_id uuid not null references auth.users(id) on delete cascade,
  addressee_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);
create index friendships_addressee_idx on public.friendships(addressee_id);
-- A decline deletes the row. Friendship is symmetric once 'accepted'.
-- is_friend(a,b): exists accepted row in either direction.

drop table if exists public.follows cascade;
```

### 3.6 notifications & devices

```sql
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in (
    'checkin_reminder','member_checked_in','friend_request','friend_accepted',
    'group_invite','post_like','post_comment','post_tag')),
  actor_id uuid references auth.users(id) on delete cascade,
  group_id uuid references public.groups(id) on delete cascade,
  post_id  uuid references public.posts(id) on delete cascade,
  read_at timestamptz,
  pushed_at timestamptz,             -- set by Edge Function once APNs-delivered
  created_at timestamptz not null default now()
);
create index notifications_recipient_idx on public.notifications(recipient_id, created_at desc);
create index notifications_unpushed_idx on public.notifications(created_at) where pushed_at is null;

create table public.device_tokens (
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null default 'ios',
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);
```

---

## 4. Row Level Security

Helper functions (both `SECURITY DEFINER`, `stable`, `search_path=public`):

- `is_friend(a uuid, b uuid) returns boolean` — exists `accepted` friendship in either direction.
- `is_group_member(g uuid, u uuid) returns boolean` — exists row in `group_members`.

**posts SELECT** (replaces "viewable by everyone"):
```sql
create policy posts_select_visible on public.posts for select using (
  author_id = (select auth.uid())
  or (shared_to_timeline and is_friend(author_id, (select auth.uid())))
  or exists (select 1 from public.post_groups pg
             where pg.post_id = posts.id
               and is_group_member(pg.group_id, (select auth.uid())))
);
```
INSERT/UPDATE/DELETE on posts stay author-scoped. (Creating group/timeline targeting is validated inside RPCs so a user can't post to a group they aren't in.)

**Child tables** (`post_verses`, `post_media`, `post_tags`, `likes`, `comments`) — SELECT allowed iff the parent post is visible:
```sql
using (exists (select 1 from public.posts p where p.id = <child>.post_id))
```
(The `posts` RLS makes that subselect return only visible posts.) Likes/comments INSERT/DELETE remain self-scoped **and** require the post be visible.

**groups / group_members** — SELECT visible to members (and to a user with a pending invite, for the invite screen). **group_invites** — visible to inviter and invitee. **friendships** — visible to the two parties. **notifications / device_tokens** — `recipient_id`/`user_id = auth.uid()` only.

`group_checkin_windows` — SELECT to group members. `group_checkins` — SELECT to group members (drives the "who checked in" view).

---

## 5. RPC functions (`SECURITY DEFINER`, validate caller)

- `create_group(name, description, cadence, time, weekday, timezone) → group` — inserts group + creator `group_members` row (role `creator`).
- `invite_to_group(group_id, invitee_username)` — creator-only; resolves username → id; inserts `group_invites`; creates `group_invite` notification.
- `respond_to_invite(invite_id, accept boolean)` — invitee-only; on accept inserts `group_members`; sets status/responded_at.
- `send_friend_request(addressee_username)` — inserts pending `friendships`; `friend_request` notification. (Auto-accept if a reciprocal pending request exists.)
- `respond_to_friend_request(requester_id, accept boolean)` — addressee-only; accept sets status + `friend_accepted` notification; decline deletes row.
- `create_encouragement(title, body, shared_to_timeline, group_ids[], verses[], media[], tag_user_ids[]) → post` — validates membership for each group_id; inserts `posts`(kind=encouragement) + children; `post_tag` notifications.
- `check_in(group_ids[], title, body, verses[], media[], tag_user_ids[]) → post` — for each group_id: assert active unanswered window, insert `post_groups` + `group_checkins`(window). One `posts`(kind=check_in). Fans out `member_checked_in` notifications to other members of each targeted group.
- `toggle_like(post_id)` / comments use plain RLS inserts; a trigger creates `post_like`/`post_comment` notifications.
- `active_checkin_targets() → [{group_id,name,window_id}]` — the compose multi-select source: caller's groups with an active window and no ledger row for it.

Notification rows for like/comment/tag are created by **triggers** on `likes`/`comments`/`post_tags`; reminder and check-in notifications are created by cron / the `check_in` RPC.

---

## 6. Scheduling & push

**`pg_cron` job** (every 15 min): for each group with `cadence<>'none'` whose scheduled slot matches the current time in the group's `timezone` (and no window already exists for that slot), insert a `group_checkin_windows` row and one `checkin_reminder` notification per member. Idempotent via `unique(group_id, opens_at)`.

**Edge Function `push`** (invoked by a second short-interval cron, or via `pg_net` after inserts): selects `notifications where pushed_at is null`, groups by recipient, looks up `device_tokens`, sends APNs (JWT-auth, `.p8` key in Edge secrets), stamps `pushed_at`. Failed/unregistered tokens are pruned.

**iOS:** registers for remote notifications post-login, upserts the APNs token into `device_tokens`, handles taps to deep-link (group timeline / post / invites).

---

## 7. iOS app changes

**Models** (`Models/Models.swift`): extend `Post` (kind, title, body, sharedToTimeline); add `Group`, `GroupMember`, `GroupInvite`, `CheckinWindow`, `PostVerse`, `PostMedia`, `PostTag`, `Friendship`, `Notification`, `DeviceToken`, and feed-row DTOs that decode the join payloads (author profile + counts + attachments).

**Services** (`Services/SupabaseService.swift` + new files): `GroupService`, `PostService`, `FeedService`, `FriendService`, `NotificationService`, plus RPC wrappers. `MediaUploader` for Storage. A small `BibleService` (verse reference → cached text via public-domain API).

**ViewModels** (`@Observable`): `HomeFeedViewModel`, `GroupListViewModel`, `GroupTimelineViewModel`, `ComposeViewModel` (shared by encouragement + check-in modes), `NotificationsViewModel`, `FriendsViewModel`.

**Views:** Tab bar — **Home** (own + friends' timeline encouragements), **Groups** (list → group timeline, invite, schedule), **Check-in** (entry that opens compose in check-in mode), **Notifications**, **Profile/Friends**. Compose screen is one screen with an encouragement/check-in mode (mode picks required-title vs optional-title and timeline-vs-group targeting). Post cell renders title, body, verses (styled), media, tags, heart + comment affordances. Comment thread screen.

---

## 8. Milestones (each independently shippable/testable)

1. **Schema & RLS foundation** — migration: extend posts, add all tables, helper fns, RLS, drop follows. Regenerate Swift models. (No UI.)
2. **Encouragements + Home/timeline feeds** — compose encouragement, personal timeline, post cell, likes, comments. (No groups yet: timeline-only.)
3. **Friends** — request/accept/decline, friends list, Home shows friends' timeline posts. RLS friend visibility verified.
4. **Groups core** — create group, invite/accept, membership, group timeline, post encouragement to group(s).
5. **Check-ins** — schedule fields, `pg_cron` window opener, `check_in` RPC + compose multi-select, ledger, group-timeline rendering of check-ins.
6. **Notifications + push** — notifications table/triggers, in-app list + badge, `device_tokens`, Edge Function + APNs, deep links.

---

## 9. Testing strategy

- **DB/RLS**: pgTAP-style or SQL fixtures asserting visibility (author, friend, non-friend, group member, non-member) and RPC invariants (can't post to a non-member group, can't double check-in a window, invite/accept transitions). Run against a Supabase branch.
- **RPC unit tests**: `check_in` fan-out counts, `active_checkin_targets` correctness across window boundaries, friend auto-accept on reciprocal request.
- **iOS**: model decoding tests against captured PostgREST payloads; ViewModel logic tests (compose validation: encouragement requires title; check-in target selection). Manual pass per milestone on simulator.
- **Cron**: unit-test the "does this slot fire now" predicate with fixed timestamps across timezones/DST.

---

## 10. Risks & open questions

- **RLS performance**: `posts` SELECT does per-row `EXISTS` over `post_groups` + friendship. Mitigate with indexes on `post_groups(group_id)`, `group_members(user_id)`, `friendships(addressee_id)`; helper fns are `stable`. Revisit with materialized feed tables only if measured slow.
- **Timezone/DST**: single group timezone; cron predicate must use `timezone(group.timezone, now())`. DST transitions may skip/duplicate a slot — the `unique(group_id, opens_at)` guard and a small look-back window handle duplicates.
- **APNs setup**: requires an Apple Developer account + `.p8` key (auth/onboarding spec noted Apple sign-in deferred pending paid account). If unavailable at build time, Milestone 6 ships in-app notifications + **local** check-in reminders, with APNs slotted in when the key exists.
- **Bible text source**: v1 uses a public-domain translation (WEB) via a free API with client-side caching; `text_snapshot` means posts never depend on it at render time. Copyrighted translations (ESV/NIV) are out of scope (licensing).
- **Verse entry UX**: v1 is structured reference entry (book/chapter/verse) + fetch/preview; no fuzzy search autocomplete.
