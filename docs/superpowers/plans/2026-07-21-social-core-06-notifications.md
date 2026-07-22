# Social Core 06 — Notifications & Push Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the unvalidated-tag hole, then write notification rows for all eight declared types from triggers, surface them in an in-app list with an unread badge, and build the APNs push path behind a transport seam that is a no-op until a signing key exists.

**Architecture:** Notifications are a pure function of the row graph — eight `AFTER` triggers, one per source table, so no write path can forget to notify and no merged Plan 2–5 RPC body changes (except the Task 1 tag gate, which is a validation). Delivery is decoupled: the in-app list reads `notifications` over PostgREST, while an Edge Function drains the same table through a swappable transport.

**Tech Stack:** Postgres 15 / Supabase (`jstdoizgosatitptyrdy`), `pg_cron`, `pg_net`, Deno Edge Functions, Swift 6 / iOS 17, SwiftUI, XcodeGen, Swift Testing.

## Global Constraints

- **Spec is the source of truth:** `docs/superpowers/specs/2026-07-21-notifications-design.md`. Read the relevant section before each task.
- **Migration prefix `202607200*`.** Files are hand-numbered; `apply_migration` stamps a different wall-clock version. Both must happen — a committed file that was never applied, or an applied migration with no file, are both defects.
- **RLS helpers live in `private`, never `public`.** Policies call `private.*`.
- **All writes go through `SECURITY DEFINER` RPCs.** No broad client write policies on any table this plan touches.
- **Every definer function sets `search_path = public`.**
- **Function grant convention** (match it exactly): a `private` helper called from an **RLS policy** gets `grant execute ... to authenticated`; a `private` helper called only from definer functions, cron, or triggers gets **no grant** and an explicit `revoke all ... from public`. A new **public** RPC gets **both** `revoke execute ... from public, anon;` **and** `grant execute ... to authenticated, service_role;` — the revoke is **not optional**. Postgres grants `EXECUTE` to `PUBLIC` by default, so a bare `grant` leaves the RPC callable by `anon` and raises an extra `anon_security_definer_function_executable` advisor WARN. All five prior RPC migrations in this repo (`friend_rpcs`, `create_group_rpc`, `invite_respond_rpcs`, `checkin_rpcs`, `encouragement_group_targeting`) include the revoke.
- **After any RLS/RPC change run `get_advisors type:"security"`.** Expect only the accepted definer-executable WARN per new public RPC. Anything else new is a defect.
- **DB verification split:** the implementing subagent writes, commits, applies, and runs **read-only** checks only (`pg_get_functiondef`, policy expressions, advisor diff). Subagent `INSERT`s into `auth.users` are blocked by the permission classifier. The **controller** runs every fixture seed → assertion → teardown block.
- **Teardown assertions must be scoped to fixture ids.** The live DB holds production rows; bare `count = 0` assertions fail spuriously.
- **iOS:** Swift 6, iOS 17 target, `make generate` after any `project.yml` change, build/test on `platform=iOS Simulator,name=iPhone 17`.
- **Baseline: 101 tests / 18 suites green.** Keep it green. Changes to `BibleShareTests/FakeSocialServices.swift` are **additive only**. Never edit an existing test to make a change pass.
- **A fresh worktree lacks the git-ignored `Resources/Secrets.plist`.** Before the first `xcodebuild test`, run: `cp /Users/sam/Repos/BibleShare/Resources/Secrets.plist Resources/Secrets.plist`
- **Never run `killall CoreSimulatorService`** — it corrupts this Mac's Xcode 26 disk-image runtime mounts.

---

## File Structure

**Migrations (create):**
- `supabase/migrations/20260720010000_tag_visibility_gate.sql` — `private.can_tag`, both RPCs re-created, two dead write policies dropped
- `supabase/migrations/20260720010100_notification_plumbing.sql` — read/write lockdowns, `mark_notifications_read`, device-token RPCs, `private.invite_counterparty`, actor FK
- `supabase/migrations/20260720010200_notification_triggers.sql` — three dedupe indexes, eight trigger functions, eight triggers
- `supabase/migrations/20260720010300_checkin_cron_health.sql` — `private.checkin_cron_health`, watchdog cron job
- `supabase/migrations/20260720010400_push_cron.sql` — the per-minute `push` invocation job

**Edge Function (create):**
- `supabase/functions/push/index.ts` — drain loop, payload composition
- `supabase/functions/push/transport.ts` — `PushTransport` interface, `NoopTransport`, `ApnsTransport`

**Swift (create):**
- `Services/NotificationService.swift` — the live `NotificationServicing` implementation
- `Services/PushRegistrar.swift` — APNs registration + `UNUserNotificationCenter` authorization
- `Services/CheckinReminderScheduler.swift` — pure date math + local notification scheduling
- `ViewModels/NotificationsViewModel.swift`
- `ViewModels/AppRouter.swift` — `AppTab` + tab-level notification routing
- `Views/NotificationsView.swift`
- `Views/Components/NotificationRow.swift`

**Swift (modify):**
- `Models/FeedModels.swift` — add `PostSummary`, `NotificationItem`
- `Services/SocialServicing.swift` — add `NotificationServicing`, add notification copy to `PostError`
- `Views/RootTabView.swift` — fifth tab + badge + `TabView(selection:)`
- `App/BibleShareApp.swift` — inject `AppRouter`; `UIApplicationDelegateAdaptor` for the APNs token callback
- `project.yml` — `remote-notification` background mode
- `BibleShareTests/FakeSocialServices.swift` — add `FakeNotificationService` (**additive only**)

**Tests (create):**
- `BibleShareTests/NotificationModelTests.swift`
- `BibleShareTests/NotificationsViewModelTests.swift`
- `BibleShareTests/NotificationDestinationTests.swift`
- `BibleShareTests/AppRouterTests.swift`
- `BibleShareTests/CheckinReminderSchedulerTests.swift`

---

## Task 1: Tag visibility gate + post-graph write lockdown

Spec §3. **This is the hard gate — nothing downstream may ship before it.** Both legs must close: validating the two RPCs while leaving `pt_insert_owner` in place makes the gate bypassable with a direct `POST /post_tags`.

**Files:**
- Create: `supabase/migrations/20260720010000_tag_visibility_gate.sql`
- Modify: `Services/SocialServicing.swift` (add one `PostError` case)

**Interfaces:**
- Consumes: `private.is_friend(uuid,uuid)`, `private.is_group_member(uuid,uuid)` (Plan 1/4, unchanged)
- Produces: `private.can_tag(p_author uuid, p_tagged uuid, p_shared boolean, p_group_ids uuid[]) → boolean`. Error string `you can only tag people who can see this post` (SQLSTATE `42501`) — Task 6 and the iOS error map depend on this exact text.

- [ ] **Step 1: Capture the current function bodies verbatim**

Do **not** transcribe these by hand — Plan 5's final review added hardening clauses that must survive.

Run via `mcp__supabase__execute_sql`:
```sql
select p.proname, pg_get_functiondef(p.oid)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('check_in','create_encouragement');
```
Expected: two `CREATE OR REPLACE FUNCTION` bodies. Both signatures stay **identical**, so `create or replace` suffices — no `drop function` (which would drop the grants).

- [ ] **Step 2: Write the migration file**

Create `supabase/migrations/20260720010000_tag_visibility_gate.sql`. Start with the helper and the two policy drops:

```sql
-- Plan 6 Task 1 — the tag visibility gate.
--
-- p_tag_user_ids was unvalidated in BOTH write paths: any user id could be
-- tagged, including users who cannot see the post. Inert while nothing read
-- post_tags (pt_select_visible is RLS-filtered, so the row was an orphan) --
-- but Plan 6 fans notifications over tags, which would push a notification
-- for a post the recipient cannot open.
--
-- One rule, derived from posts_select_visible: a tag is valid iff the tagged
-- user can see the post. check_in passes p_shared := false, so it collapses
-- to members-only without needing a second rule.

create or replace function private.can_tag(
  p_author uuid, p_tagged uuid, p_shared boolean, p_group_ids uuid[]
) returns boolean
language sql stable security definer set search_path = public as $$
  select (coalesce(p_shared, false) and private.is_friend(p_author, p_tagged))
      or exists (
           select 1 from unnest(coalesce(p_group_ids, '{}'::uuid[])) as g
           where private.is_group_member(g, p_tagged)
         );
$$;

-- Called only from definer RPCs, never from an RLS policy: no authenticated
-- grant (matches private.due_slot_for, not private.is_friend).
revoke all on function private.can_tag(uuid, uuid, boolean, uuid[]) from public;

-- Second leg of the gate. pt_insert_owner validated only that the caller
-- authored the post -- the tagged user was entirely unchecked -- so a client
-- could bypass the RPC gate entirely with a direct POST /post_tags. No client
-- path writes post_tags (it appears only as a read embed in FeedService).
drop policy if exists "pt_insert_owner" on public.post_tags;

-- Carried from Plan 5's review: unconstrained on `kind`, so a client could
-- fabricate kind='check_in', shared_to_timeline=true and get a fake "Checked
-- in" capsule on their own timeline. No client path inserts posts (PostService
-- only ever calls .delete()). Same rule as above: SECURITY DEFINER RPCs are
-- the only write path into the post graph.
drop policy if exists "Users can create their own posts" on public.posts;
```

- [ ] **Step 3: Append both re-created functions to the same migration file**

Paste each body captured in Step 1, with **exactly one** block inserted into each. Change nothing else.

In `create_encouragement`, insert immediately **after** the group-membership `if exists (...) raise 'you can only post to groups you belong to' ... end if;` block and **before** the media-validation block:

```sql
  -- Tag gate: a tag is only legitimate if the tagged user can see the post.
  -- Raise rather than silently drop -- this mirrors how the group-membership
  -- check above rejects the whole call, and gives the post_tag notification
  -- trigger a hard invariant to rely on.
  if exists (
    select 1 from unnest(coalesce(p_tag_user_ids, '{}'::uuid[])) as t
    where t <> v_uid
      and not private.can_tag(v_uid, t, v_shared, p_group_ids)
  ) then
    raise exception 'you can only tag people who can see this post'
      using errcode = '42501';
  end if;
```

In `check_in`, insert immediately **after** the `if exists (...) raise 'you can only check in to groups you belong to' ... end if;` block and **before** the media-validation block. Note `false` for the shared argument and `v_groups` (the deduped, validated array), not `p_group_ids`:

```sql
  -- Tag gate. A check-in is never on the timeline, so the timeline clause is
  -- dead here and the rule collapses to members-only -- which is exactly the
  -- intended behaviour, with no check-in-specific branch.
  if exists (
    select 1 from unnest(coalesce(p_tag_user_ids, '{}'::uuid[])) as t
    where t <> v_uid
      and not private.can_tag(v_uid, t, false, v_groups)
  ) then
    raise exception 'you can only tag people who can see this post'
      using errcode = '42501';
  end if;
```

- [ ] **Step 4: Apply the migration**

Call `mcp__supabase__apply_migration` with name `tag_visibility_gate` and the full file contents.
Expected: success, no error.

- [ ] **Step 5: Read-only verification (subagent may run these)**

```sql
-- Both functions must now reference can_tag exactly once each.
select p.proname,
       (pg_get_functiondef(p.oid) like '%can_tag%') as has_gate
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('check_in','create_encouragement');

-- Both dead policies must be gone.
select policyname from pg_policies
where schemaname = 'public'
  and policyname in ('pt_insert_owner','Users can create their own posts');

-- Grants must match the convention: postgres only, no authenticated.
select proname, array_to_string(proacl, ' | ') from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'private' and p.proname = 'can_tag';
```
Expected: `has_gate` true for both; **zero** policy rows; acl `postgres=X/postgres`.

- [ ] **Step 6: Run the security advisor**

Call `mcp__supabase__get_advisors` with `type: "security"`.
Expected: no new findings. `can_tag` is in `private`, so it adds no definer-executable WARN.

- [ ] **Step 7: CONTROLLER runs the tag-gate matrix**

The subagent must **stop here and report**; the fixture seed below writes `auth.users` and will be classifier-blocked in a subagent.

**Two environment rules govern every verification block in this plan:**

1. `execute_sql` returns **only the last statement's result**, and `set local` / `set_config(...,true)` are transaction-scoped. So a seed + impersonation + assertion + `rollback` must all travel in **one** `execute_sql` call, ending in the single `select` whose output you want to read. Never split them across calls — the impersonation silently evaporates.
2. Assertions therefore return a labelled result set. Use the `case when … then 'PASS' else 'FAIL' end` shape shown below so one call yields a readable verdict.
3. **Everything after `set local role authenticated` is RLS-filtered.** A `count(*)` there measures *visibility*, not existence — seeding five profiles and counting them back as the impersonated user correctly returns 3 (self + friend + co-member). Put existence assertions **before** the impersonation lines and visibility assertions after, or the same query silently answers a different question than you meant.

This is the **canonical fixture**, referenced by Tasks 1–3. Three real errors it is written to avoid — all three were hit while validating it live:

- `g` is not a hex digit, so `'…-0000000000g1'::uuid` raises `22P02`.
- `uuid || text` has no operator; the email needs `v.id::text || '@fixture.test'`.
- **`handle_new_user` derives the username from the first 12 hex digits of the uuid** (`'user_' || substr(replace(new.id::text,'-',''), 1, 12)`), so fixture ids that differ only in their *last* characters all collide on `profiles_username_key`. These ids differ in the **first** block for that reason — do not "tidy" them into a shared prefix.

```sql
begin;
-- A = author, F = friend of A, E = stranger, D = member of G1 (not a friend),
-- C = spare member used for the multi-group dedupe case.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
select v.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       v.id::text || '@fixture.test', '', now(), now(), now()
from (values ('aaaaaaaa-0000-4000-8000-000000000001'::uuid),
             ('ffffffff-0000-4000-8000-000000000002'::uuid),
             ('eeeeeeee-0000-4000-8000-000000000003'::uuid),
             ('dddddddd-0000-4000-8000-000000000004'::uuid),
             ('cccccccc-0000-4000-8000-000000000005'::uuid)) v(id);

-- handle_new_user has already created a profiles row per auth.users insert;
-- give each a deterministic username.
update public.profiles set username = 'fx_' || left(replace(id::text, '-', ''), 4)
where id in ('aaaaaaaa-0000-4000-8000-000000000001',
             'ffffffff-0000-4000-8000-000000000002',
             'eeeeeeee-0000-4000-8000-000000000003',
             'dddddddd-0000-4000-8000-000000000004',
             'cccccccc-0000-4000-8000-000000000005');

insert into public.friendships (requester_id, addressee_id, status, responded_at)
values ('aaaaaaaa-0000-4000-8000-000000000001',
        'ffffffff-0000-4000-8000-000000000002', 'accepted', now());

insert into public.groups (id, creator_id, name, timezone, checkin_cadence)
values ('11111111-0000-4000-8000-000000000101',
        'aaaaaaaa-0000-4000-8000-000000000001', 'FX Group One', 'UTC', 'none');
insert into public.group_members (group_id, user_id, role) values
  ('11111111-0000-4000-8000-000000000101', 'aaaaaaaa-0000-4000-8000-000000000001', 'creator'),
  ('11111111-0000-4000-8000-000000000101', 'dddddddd-0000-4000-8000-000000000004', 'member');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000001"}';

-- … assertions here …

rollback;
```

`rollback` is the teardown — nothing persists, so no id-scoped delete is needed. **Never** commit a fixture; if you ever must, delete only these six ids and never write a bare `count = 0` assertion (the live DB holds production rows).

Assertion shape — each case is a `select` that yields PASS/FAIL, and a raising case is wrapped so the expected exception is the pass condition:

```sql
-- Expect-success case:
select case when public.create_encouragement('t', null, true, '{}', '[]', '[]',
              array['ffffffff-0000-4000-8000-000000000002']::uuid[]) is not null
            then 'PASS' else 'FAIL' end as case_1_friend_timeline;

-- Expect-raise case:
do $$
begin
  perform public.create_encouragement('t', null, true, '{}', '[]', '[]',
            array['eeeeeeee-0000-4000-8000-000000000003']::uuid[]);
  raise exception 'FAIL: stranger tag was accepted';
exception when sqlstate '42501' then
  raise notice 'PASS: case 2 rejected';
end $$;
```

Run each case and record pass/fail. `OK` means the call succeeds; `42501` means it must raise `you can only tag people who can see this post`.

| # | Call | Expect |
|---|---|---|
| 1 | `create_encouragement('t', null, true, '{}', '[]', '[]', array['…f'])` — friend, timeline | OK |
| 2 | `create_encouragement('t', null, true, '{}', '[]', '[]', array['…e'])` — stranger, timeline | `42501` |
| 3 | `create_encouragement('t', null, false, array['…101'], '[]', '[]', array['…d'])` — member, group-only | OK |
| 4 | `create_encouragement('t', null, false, array['…101'], '[]', '[]', array['…e'])` — stranger, group-only | `42501` |
| 5 | `create_encouragement('t', null, true, array['…101'], '[]', '[]', array['…f'])` — friend not member, mixed | OK |
| 6 | `create_encouragement('t', null, true, array['…101'], '[]', '[]', array['…d'])` — member not friend, mixed | OK |
| 7 | `create_encouragement('t', null, true, '{}', '[]', '[]', array['…a'])` — self-tag | OK, 0 tag rows |
| 8 | direct `insert into public.post_tags` on own post | RLS denial (policy dropped) |
| 9 | direct `insert into public.posts` as self | RLS denial (policy dropped) |

Ids abbreviate the canonical fixture: `…a` = author, `…f` = friend, `…e` = stranger, `…d` = group member, `…101` = group. Case 6 is the one that would regress if the rule were written as a conjunction instead of a disjunction.

For `check_in`, seed a `group_checkin_windows` row for `…101` with `opens_at = now() - interval '1 minute'` first, then assert: member `…d` → OK; stranger `…e` → `42501`.

- [ ] **Step 8: Add the iOS error copy**

In `Services/SocialServicing.swift`, inside `PostError.message(for:)`, add above the trailing `42501` catch-all (order matters — the generic RLS branch would otherwise swallow it):

```swift
        if text.contains("you can only tag people who can see this post") {
            return "You can only tag people who can see this post."
        }
```

- [ ] **Step 9: Verify the iOS suite still passes**

```bash
cp /Users/sam/Repos/BibleShare/Resources/Secrets.plist Resources/Secrets.plist
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: `TEST SUCCEEDED`, 101 tests / 18 suites.

- [ ] **Step 10: Commit**

```bash
git add supabase/migrations/20260720010000_tag_visibility_gate.sql Services/SocialServicing.swift
git commit -m "feat(notifications): gate p_tag_user_ids on post visibility

A tag is now valid only if the tagged user can see the post, derived from
posts_select_visible and applied in both create_encouragement and check_in.
Also drops pt_insert_owner (which let a client insert post_tags directly with
the tagged user unvalidated, bypassing the gate) and the unconstrained posts
INSERT policy carried from Plan 5's review."
```

---

## Task 2: Notification & device-token plumbing

Spec §5. Lockdowns plus the pieces the list needs to render.

**Files:**
- Create: `supabase/migrations/20260720010100_notification_plumbing.sql`

**Interfaces:**
- Produces: `public.mark_notifications_read(p_ids uuid[] default null) → void`; `public.register_device_token(p_token text, p_platform text default 'ios') → void`; `public.unregister_device_token(p_token text) → void`; `private.invite_counterparty(a uuid, b uuid) → boolean`. Task 6 calls all three public RPCs by these exact names and parameter names.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260720010100_notification_plumbing.sql`:

```sql
-- Plan 6 Task 2 — notification & device-token plumbing.

-- === notifications: read-only to clients, mark-read via RPC ===
-- notif_update_read allowed a recipient to UPDATE their ENTIRE row: rewrite
-- `type`, repoint post_id at any post, forge actor_id, or clear pushed_at to
-- force a re-push. Carried from Plan 1's review.
drop policy if exists "notif_update_read" on public.notifications;
revoke update on public.notifications from authenticated;

create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  -- coalesce keeps the ORIGINAL read timestamp when a row is re-marked.
  update public.notifications
     set read_at = coalesce(read_at, now())
   where recipient_id = v_uid
     and read_at is null
     and (p_ids is null or id = any(p_ids));
end;
$$;
revoke execute on function public.mark_notifications_read(uuid[]) from public, anon;
grant execute on function public.mark_notifications_read(uuid[]) to authenticated, service_role;

-- === device_tokens: FOR ALL is the broadest possible client write grant ===
drop policy if exists "dt_all_own" on public.device_tokens;
create policy dt_select_own on public.device_tokens
  for select using (user_id = (select auth.uid()));

create or replace function public.register_device_token(
  p_token text, p_platform text default 'ios'
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if p_token is null or btrim(p_token) = '' then
    raise exception 'a device token is required' using errcode = '22023';
  end if;

  -- APNs tokens are DEVICE-scoped, but the declared PK is (user_id, token),
  -- which lets the same token exist for two users. On a shared device -- or
  -- after logout and a different login -- that pushes one person's
  -- notifications to another person's phone. Registration is authoritative:
  -- the token belongs to whoever most recently registered it.
  delete from public.device_tokens
   where token = btrim(p_token) and user_id <> v_uid;

  insert into public.device_tokens (user_id, token, platform)
  values (v_uid, btrim(p_token), coalesce(nullif(btrim(p_platform), ''), 'ios'))
  on conflict (user_id, token)
    do update set updated_at = now(), platform = excluded.platform;
end;
$$;
revoke execute on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated, service_role;

create or replace function public.unregister_device_token(p_token text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  delete from public.device_tokens
   where user_id = v_uid and token = btrim(coalesce(p_token, ''));
end;
$$;
revoke execute on function public.unregister_device_token(text) from public, anon;
grant execute on function public.unregister_device_token(text) to authenticated, service_role;

-- === profiles: the invite counterparty ===
-- private.friendship_exists is deliberately status-agnostic, so a PENDING
-- requester's profile is already visible. There is no equivalent for invites:
-- shares_group_with requires real group_members rows, so an inviter is
-- invisible until you accept -- which already renders Plan 4's invite screen
-- nameless, and would make a group_invite notification unactionable.
-- PENDING ONLY -- deliberately NOT status-agnostic, unlike friendship_exists.
-- respond_to_friend_request's decline DELETES the friendship row, so a declined
-- request stops granting visibility by itself. respond_to_invite's decline only
-- sets status='declined' and keeps the row forever, so a status-agnostic check
-- would grant both parties permanent profile access after a decline. Accepted
-- invites are covered by shares_group_with, populated in the same transaction.
create or replace function private.invite_counterparty(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.group_invites
    where status = 'pending'
      and ((inviter_id = a and invitee_id = b)
        or (inviter_id = b and invitee_id = a))
  );
$$;
-- Called FROM an RLS policy, so it needs the authenticated grant
-- (matches private.friendship_exists, not private.can_tag).
revoke all on function private.invite_counterparty(uuid, uuid) from public;
grant execute on function private.invite_counterparty(uuid, uuid) to authenticated;

drop policy if exists "profiles_select_scoped" on public.profiles;
create policy profiles_select_scoped on public.profiles for select using (
  id = (select auth.uid())
  or private.friendship_exists(id, (select auth.uid()))
  or private.shares_group_with(id, (select auth.uid()))
  or private.invite_counterparty(id, (select auth.uid()))
  or exists (select 1 from public.post_tags pt
             where pt.tagged_user_id = profiles.id
               and exists (select 1 from public.posts p where p.id = pt.post_id))
  or exists (select 1 from public.comments c
             where c.author_id = profiles.id
               and exists (select 1 from public.posts p where p.id = c.post_id))
);

-- === PostgREST embed FK ===
-- notifications.actor_id references auth.users, which PostgREST cannot embed a
-- profiles row through. Same redundant-FK technique as Plan 2's profile_fks.
alter table public.notifications
  add constraint notifications_actor_id_profiles_fkey
  foreign key (actor_id) references public.profiles(id) on delete cascade;
```

- [ ] **Step 2: Apply**

`mcp__supabase__apply_migration`, name `notification_plumbing`.
Expected: success.

- [ ] **Step 3: Read-only verification**

```sql
select policyname, cmd from pg_policies
where schemaname='public' and tablename in ('notifications','device_tokens')
order by tablename, policyname;

select has_table_privilege('authenticated','public.notifications','UPDATE') as can_update;

select conname from pg_constraint
where conrelid = 'public.notifications'::regclass
  and conname = 'notifications_actor_id_profiles_fkey';

select pg_get_expr(polqual, polrelid) like '%invite_counterparty%' as has_invite_clause
from pg_policy where polname = 'profiles_select_scoped';
```
Expected: exactly `notif_select_own` (SELECT) and `dt_select_own` (SELECT); `can_update` **false**; the FK row present; `has_invite_clause` true.

- [ ] **Step 4: Security advisor**

`get_advisors type:"security"`.
Expected: exactly **three** new definer-executable WARNs — `mark_notifications_read`, `register_device_token`, `unregister_device_token`. These are the accepted per-RPC warning. Nothing else new.

- [ ] **Step 5: CONTROLLER runs the plumbing assertions**

```sql
begin;
-- (reuse the Task 1 fixture seed block)
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
```

| Assertion | Expect |
|---|---|
| `update public.notifications set read_at = now()` | denied — no UPDATE privilege |
| seed 2 unread rows for A + 1 for F; `select mark_notifications_read(null)` | A's 2 read, F's still unread |
| re-run `mark_notifications_read(null)` | A's `read_at` values **unchanged** (coalesce) |
| `mark_notifications_read(array[<F's id>])` | F's row still unread — not the caller's |
| `register_device_token('tok1')` then as user F `register_device_token('tok1')` | exactly **one** row for `tok1`, owned by F |
| as A, `select * from public.profiles where id = <inviter>` after seeding a pending invite inviter→A | 1 row (was 0 before this migration) |
| as A, `select * from public.profiles where id = <stranger E>` — no friendship, no shared group, no invite | **0 rows** — the new clause must not widen visibility beyond invite counterparties |

```sql
rollback;
```

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260720010100_notification_plumbing.sql
git commit -m "feat(notifications): lock down notifications/device_tokens, add invite profile visibility

Drops notif_update_read (which allowed rewriting the whole row, including
pushed_at) and device_tokens' FOR ALL policy, replacing both with SECURITY
DEFINER RPCs. register_device_token claims a token away from any prior owner --
APNs tokens are device-scoped, so the (user_id, token) PK otherwise pushes one
user's notifications to another's phone. Adds private.invite_counterparty so an
inviter's profile is visible before acceptance."
```

---

## Task 3: The eight notification triggers

Spec §4. Zero RPC bodies change here.

**Files:**
- Create: `supabase/migrations/20260720010200_notification_triggers.sql`

**Interfaces:**
- Consumes: `public.notifications` (Plan 1 schema, unchanged)
- Produces: notification rows. No SQL identifier is consumed by later tasks.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260720010200_notification_triggers.sql`:

```sql
-- Plan 6 Task 3 — notification triggers.
--
-- All eight types are AFTER triggers so a notification is owed whenever the
-- row exists, not whenever a particular function was called. Two of the eight
-- (likes, comments) have no RPC at all -- they are direct client inserts --
-- so triggers were mandatory there regardless; uniformity buys the rest.

-- === Dedupe indexes ===
-- post_comment is deliberately absent: each comment is a distinct event and
-- collapsing them would hide replies.
create unique index if not exists notifications_like_uniq
  on public.notifications (recipient_id, actor_id, post_id) where type = 'post_like';
-- The load-bearing one: a single check_in fans one post to N groups, so a user
-- in TWO targeted groups would otherwise get two notifications for one post.
create unique index if not exists notifications_checkin_uniq
  on public.notifications (recipient_id, actor_id, post_id) where type = 'member_checked_in';
create unique index if not exists notifications_tag_uniq
  on public.notifications (recipient_id, post_id) where type = 'post_tag';

-- === post_like ===
create or replace function private.tg_notify_post_like()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (recipient_id, type, actor_id, post_id)
  select p.author_id, 'post_like', new.user_id, new.post_id
  from public.posts p
  where p.id = new.post_id and p.author_id <> new.user_id
  on conflict do nothing;
  return null;
end;
$$;
create trigger notify_post_like after insert on public.likes
  for each row execute function private.tg_notify_post_like();

-- === post_comment ===
create or replace function private.tg_notify_post_comment()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (recipient_id, type, actor_id, post_id)
  select p.author_id, 'post_comment', new.author_id, new.post_id
  from public.posts p
  where p.id = new.post_id and p.author_id <> new.author_id;
  return null;
end;
$$;
create trigger notify_post_comment after insert on public.comments
  for each row execute function private.tg_notify_post_comment();

-- === post_tag ===
-- Task 1's gate guarantees the tagged user can see the post, so this cannot
-- notify someone about a post they can't open.
create or replace function private.tg_notify_post_tag()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (recipient_id, type, actor_id, post_id)
  select new.tagged_user_id, 'post_tag', p.author_id, new.post_id
  from public.posts p
  where p.id = new.post_id and p.author_id <> new.tagged_user_id
  on conflict do nothing;
  return null;
end;
$$;
create trigger notify_post_tag after insert on public.post_tags
  for each row execute function private.tg_notify_post_tag();

-- === member_checked_in ===
-- Plan 5 rewrote check_in from `exception when unique_violation` to
-- `on conflict do nothing` + `if not found` SPECIFICALLY so this trigger's
-- index conflict could not be re-reported to the user as "already checked in".
-- That holds: FOUND is local to each plpgsql invocation, and a trigger is a
-- separate invocation. Regression-tested in Step 5.
create or replace function private.tg_notify_member_checked_in()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (recipient_id, type, actor_id, group_id, post_id)
  select m.user_id, 'member_checked_in', new.user_id, new.group_id, new.post_id
  from public.group_members m
  where m.group_id = new.group_id and m.user_id <> new.user_id
  on conflict do nothing;
  return null;
end;
$$;
create trigger notify_member_checked_in after insert on public.group_checkins
  for each row execute function private.tg_notify_member_checked_in();

-- === checkin_reminder ===
-- Idempotent for free: group_checkin_windows has unique(group_id, opens_at)
-- and the opener inserts with `on conflict do nothing`, so this fires at most
-- once per window. System-generated, so actor_id stays null.
--
-- MUST STAY TRIVIAL. private.open_checkin_windows wraps its insert in
-- `exception when others then raise warning`, so anything that raises here
-- rolls back that group's window and is swallowed as a warning -- the window
-- silently never opens. Task 4's watchdog exists to catch exactly that.
create or replace function private.tg_notify_checkin_reminder()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (recipient_id, type, group_id)
  select m.user_id, 'checkin_reminder', new.group_id
  from public.group_members m
  where m.group_id = new.group_id;
  return null;
end;
$$;
create trigger notify_checkin_reminder after insert on public.group_checkin_windows
  for each row execute function private.tg_notify_checkin_reminder();

-- === group_invite ===
-- No dedupe index: invite_to_group returns early on an existing pending invite,
-- and a declined-then-reinvited flow SHOULD produce a fresh notification.
create or replace function private.tg_notify_group_invite()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.invitee_id <> new.inviter_id then
    insert into public.notifications (recipient_id, type, actor_id, group_id)
    values (new.invitee_id, 'group_invite', new.inviter_id, new.group_id);
  end if;
  return null;
end;
$$;
create trigger notify_group_invite after insert on public.group_invites
  for each row execute function private.tg_notify_group_invite();

-- === friend_request ===
create or replace function private.tg_notify_friend_request()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending' and new.addressee_id <> new.requester_id then
    insert into public.notifications (recipient_id, type, actor_id)
    values (new.addressee_id, 'friend_request', new.requester_id);
  end if;
  return null;
end;
$$;
create trigger notify_friend_request after insert on public.friendships
  for each row execute function private.tg_notify_friend_request();

-- === friend_accepted ===
-- The WHEN clause fires on the transition only, which covers all three accept
-- sites -- respond_to_friend_request, send_friend_request's reciprocal
-- auto-accept, and its unique_violation race handler -- because all three are
-- UPDATE ... SET status='accepted'. The accepter is always the addressee.
create or replace function private.tg_notify_friend_accepted()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.requester_id <> new.addressee_id then
    insert into public.notifications (recipient_id, type, actor_id)
    values (new.requester_id, 'friend_accepted', new.addressee_id);
  end if;
  return null;
end;
$$;
create trigger notify_friend_accepted after update on public.friendships
  for each row
  when (old.status is distinct from 'accepted' and new.status = 'accepted')
  execute function private.tg_notify_friend_accepted();

-- Trigger functions are invoked by the executor, not by the calling user, so
-- no EXECUTE grant is needed. Revoke the PUBLIC default anyway.
revoke all on function private.tg_notify_post_like() from public;
revoke all on function private.tg_notify_post_comment() from public;
revoke all on function private.tg_notify_post_tag() from public;
revoke all on function private.tg_notify_member_checked_in() from public;
revoke all on function private.tg_notify_checkin_reminder() from public;
revoke all on function private.tg_notify_group_invite() from public;
revoke all on function private.tg_notify_friend_request() from public;
revoke all on function private.tg_notify_friend_accepted() from public;
```

- [ ] **Step 2: Apply**

`mcp__supabase__apply_migration`, name `notification_triggers`.
Expected: success.

- [ ] **Step 3: Read-only verification**

```sql
select c.relname as table_name, t.tgname
from pg_trigger t join pg_class c on c.oid = t.tgrelid
where not t.tgisinternal and t.tgname like 'notify_%'
order by c.relname;

select indexname from pg_indexes
where schemaname='public' and tablename='notifications' and indexname like '%uniq';
```
Expected: 8 triggers across `comments`, `friendships` (×2), `group_checkin_windows`, `group_checkins`, `group_invites`, `likes`, `post_tags`; 3 unique indexes.

- [ ] **Step 4: Security advisor**

`get_advisors type:"security"`.
Expected: **no** new findings — every trigger function is in `private` and adds no public RPC.

- [ ] **Step 5: CONTROLLER runs the trigger assertions**

Use the Task 1 fixture. For every case, scope counts to fixture ids.

| # | Action | Expect |
|---|---|---|
| 1 | F likes A's post | 1 `post_like` → A, actor F |
| 2 | F unlikes then re-likes | still exactly **1** `post_like` (dedupe) |
| 3 | A likes A's own post | **0** notifications (self-guard) |
| 4 | F comments twice on A's post | **2** `post_comment` rows (no dedupe — deliberate) |
| 5 | A comments on A's own post | 0 |
| 6 | A tags F on a timeline post | 1 `post_tag` → F, actor A |
| 7 | invite A→D | 1 `group_invite` → D, actor A, group set |
| 8 | `send_friend_request` A→E | 1 `friend_request` → E, actor A |
| 9 | E accepts | 1 `friend_accepted` → A, actor E |
| 10 | reciprocal auto-accept path (E requests A, then A requests E) | 1 `friend_accepted` → E (fires on the UPDATE) |
| 11 | insert a `group_checkin_windows` row for G | `checkin_reminder` to **every** member, `actor_id` null |

- [ ] **Step 6: CONTROLLER runs the Plan 5 regression**

This is the specific failure Plan 5's `on conflict` / `if not found` rewrite pre-empted. Seed two groups `G1`, `G2`, both containing A **and** M, both with an open window, then as A:

```sql
select public.check_in(array['<G1>','<G2>']::uuid[], 'hi', null, '[]', '[]', '{}');
```

| Assertion | Expect |
|---|---|
| the call | **succeeds**, returns a post id — must NOT raise `already checked in` |
| `group_checkins` rows for A | **2** (one per group) |
| `member_checked_in` notifications for M | exactly **1** (deduped across the two groups) |

If this raises `already checked in`, the trigger has broken `check_in`'s `if not found` — stop and report; do not work around it.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260720010200_notification_triggers.sql
git commit -m "feat(notifications): write all eight notification types from triggers

Every type becomes a function of a row appearing or changing, so no write path
can forget to notify and no Plan 2-5 RPC body changes. Three partial unique
indexes dedupe relikes and the multi-group check-in fan-out; comments are
deliberately not deduped. Verified that the member_checked_in index conflict
cannot resurface as check_in's 'already checked in' -- the case Plan 5's
on-conflict rewrite was written to protect."
```

---

## Task 4: Check-in cron health + watchdog

Spec §6. In scope because Task 3 put a trigger **inside** `open_checkin_windows`' swallow-and-warn path, adding a new way to silently lose windows.

**Files:**
- Create: `supabase/migrations/20260720010300_checkin_cron_health.sql`

**Interfaces:**
- Produces: `private.checkin_cron_health() → table(last_success_at timestamptz, minutes_since_success numeric, failed_runs_last_hour bigint, invalid_timezone_groups bigint, missed_windows bigint)`

- [ ] **Step 1: Confirm the job name**

```sql
select jobid, jobname, schedule from cron.job;
```
Expected: a job named `open-checkin-windows`. If the name differs, use the actual name below.

- [ ] **Step 2: Write the migration**

Create `supabase/migrations/20260720010300_checkin_cron_health.sql`:

```sql
-- Plan 6 Task 4 — check-in cron health.
--
-- private.open_checkin_windows swallows per-group failures as warnings, so a
-- group with an unparseable timezone (Plan 5 final-review Critical) -- or now
-- a raising checkin_reminder trigger -- means windows silently never open.
-- Deliberately minimal: no ops table, no alerting integration. This surfaces
-- in Supabase logs and is queryable on demand; it is the hook to wire into a
-- real alert channel when one exists.

-- missed_windows is the only field that observes the ACTUAL OUTCOME. The other
-- three are proxies, and every one of them stays green in the failure this task
-- exists to catch: when the checkin_reminder trigger raises, the opener's
-- `exception when others` swallows it inside the per-group loop, the function
-- still returns normally, and pg_cron records 'succeeded'. Asking "is a due
-- window actually open?" is cause-agnostic and catches that, a bad timezone,
-- and anything else that makes the opener skip a group.
-- Dropped, not replaced: create or replace cannot change a return type.
drop function if exists private.checkin_cron_health();
create or replace function private.checkin_cron_health()
returns table (
  last_success_at timestamptz,
  minutes_since_success numeric,
  failed_runs_last_hour bigint,
  invalid_timezone_groups bigint,
  missed_windows bigint
)
language plpgsql stable security definer set search_path = public as $$
declare
  g record; v_slot timestamptz; v_bad bigint := 0; v_missed bigint := 0;
begin
  for g in
    select id, checkin_cadence, checkin_time, checkin_weekday, timezone
    from public.groups where checkin_cadence <> 'none'
  loop
    begin
      v_slot := private.due_slot_for(g.checkin_cadence, g.checkin_time,
                                     g.checkin_weekday, g.timezone, now());
      -- The opener runs every 15 min, so a more recent slot may simply not have
      -- been reached yet. 20 min leaves margin without flagging normal lag.
      if v_slot is not null
         and v_slot < now() - interval '20 minutes'
         and not exists (select 1 from public.group_checkin_windows w
                         where w.group_id = g.id and w.opens_at = v_slot)
      then
        v_missed := v_missed + 1;
      end if;
    exception when others then
      -- Same per-group isolation the opener uses; due_slot_for raises on an
      -- unparseable timezone, i.e. exactly the group the opener skips.
      v_bad := v_bad + 1;
    end;
  end loop;

  return query
  with j as (select jobid from cron.job where jobname = 'open-checkin-windows'),
  runs as (select d.status, d.end_time from cron.job_run_details d join j on j.jobid = d.jobid),
  ok as (select max(end_time) as t from runs where status = 'succeeded'),
  bad as (select count(*) as n from runs
          where status <> 'succeeded' and end_time > now() - interval '1 hour')
  -- Aggregates with no GROUP BY always yield a row, so this returns exactly one
  -- row even if the job never ran -- the watchdog must never silently no-op.
  select ok.t, round(extract(epoch from (now() - ok.t)) / 60.0, 1), bad.n, v_bad, v_missed
  from ok, bad;
end;
$$;
revoke all on function private.checkin_cron_health() from public;

create or replace function private.checkin_cron_watchdog()
returns void language plpgsql security definer set search_path = public as $$
declare h record;
begin
  select * into h from private.checkin_cron_health();

  if h.last_success_at is null then
    raise warning 'checkin-cron-watchdog: open-checkin-windows has NEVER succeeded';
  elsif h.minutes_since_success > 30 then
    raise warning 'checkin-cron-watchdog: no successful run in % minutes (last %)',
      h.minutes_since_success, h.last_success_at;
  end if;

  if h.failed_runs_last_hour > 0 then
    raise warning 'checkin-cron-watchdog: % failed run(s) in the last hour',
      h.failed_runs_last_hour;
  end if;

  -- groups.timezone has no CHECK constraint -- impossible, since CHECK cannot
  -- subquery pg_timezone_names -- so create_group validates it on the way in
  -- and this counter catches anything already stored or changed since.
  if h.invalid_timezone_groups > 0 then
    raise warning 'checkin-cron-watchdog: % group(s) have an unparseable timezone; their windows never open',
      h.invalid_timezone_groups;
  end if;

  -- The outcome check: fires when the opener reports success while silently
  -- skipping a group -- notably a trigger raising inside its `exception when
  -- others` handler, which no run-status or timezone check can see.
  if h.missed_windows > 0 then
    raise warning 'checkin-cron-watchdog: % group(s) are past due with no window opened; the opener is reporting success while skipping them',
      h.missed_windows;
  end if;
end;
$$;
revoke all on function private.checkin_cron_watchdog() from public;

select cron.schedule('checkin-cron-watchdog', '*/30 * * * *',
                     $$select private.checkin_cron_watchdog();$$);
```

- [ ] **Step 3: Apply**

`mcp__supabase__apply_migration`, name `checkin_cron_health`.
Expected: success; the `cron.schedule` call returns a jobid.

- [ ] **Step 4: Verify**

```sql
select * from private.checkin_cron_health();
select jobname, schedule, active from cron.job where jobname = 'checkin-cron-watchdog';
```
Expected: one health row (`invalid_timezone_groups` should be `0`); the watchdog job present and active.

- [ ] **Step 5: Prove the watchdog actually fires**

```sql
select private.checkin_cron_watchdog();
```
Expected: completes. If `open-checkin-windows` has succeeded within 30 min and no groups are broken, **no** warnings — that is the healthy case. To prove the unhealthy path, temporarily point a fixture group at a bogus timezone inside a transaction and re-run, expecting the `unparseable timezone` warning, then `rollback`.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260720010300_checkin_cron_health.sql
git commit -m "feat(checkins): health check + watchdog for the window-opener cron

open_checkin_windows swallows per-group failures as warnings, and Plan 6 adds a
trigger inside that swallow -- a new way for windows to silently never open.
Deliberately minimal: a queryable health function plus a 30-minute watchdog that
raises warnings. No ops table, no alerting integration."
```

---

## Task 5: `push` Edge Function + transport seam

Spec §7.1–7.3.

**Files:**
- Create: `supabase/functions/push/transport.ts`, `supabase/functions/push/index.ts`
- Create: `supabase/migrations/20260720010400_push_cron.sql`

**Interfaces:**
- Produces: HTTP `POST /functions/v1/push` → `{ transport: string, pending: number, sent: number, failed: number, pruned: number }`

- [ ] **Step 1: Write the transport seam**

Create `supabase/functions/push/transport.ts`:

```ts
export interface ApnsPayload {
  title: string;
  body: string;
  data: Record<string, string | null>;
}

export type SendResult =
  | { ok: true }
  | { ok: false; retryable: boolean; unregistered: boolean; detail: string };

export interface PushTransport {
  readonly name: string;
  send(token: string, payload: ApnsPayload): Promise<SendResult>;
}

/** Today's transport: no Apple Developer .p8 key exists. */
export class NoopTransport implements PushTransport {
  readonly name = "noop";
  send(): Promise<SendResult> {
    return Promise.resolve({
      ok: false,
      retryable: true,
      unregistered: false,
      detail: "no APNs key configured",
    });
  }
}

export class ApnsTransport implements PushTransport {
  readonly name = "apns";
  private jwt: string | null = null;
  private jwtIssuedAt = 0;

  constructor(
    private readonly keyP8: string,
    private readonly keyId: string,
    private readonly teamId: string,
    private readonly topic: string,
    private readonly host = "https://api.push.apple.com",
  ) {}

  /** APNs rejects tokens older than 1h; refresh at 50m. */
  private async authToken(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (this.jwt && now - this.jwtIssuedAt < 3000) return this.jwt;

    const header = { alg: "ES256", kid: this.keyId };
    const claims = { iss: this.teamId, iat: now };
    const b64 = (o: unknown) =>
      btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const signingInput = `${b64(header)}.${b64(claims)}`;

    const pem = this.keyP8.replace(/-----[A-Z ]+-----/g, "").replace(/\s/g, "");
    const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
    const key = await crypto.subtle.importKey(
      "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
    );
    const sig = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput),
    );
    const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

    this.jwt = `${signingInput}.${sigB64}`;
    this.jwtIssuedAt = now;
    return this.jwt;
  }

  async send(token: string, payload: ApnsPayload): Promise<SendResult> {
    const jwt = await this.authToken();
    const res = await fetch(`${this.host}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": this.topic,
        "apns-push-type": "alert",
      },
      body: JSON.stringify({
        aps: { alert: { title: payload.title, body: payload.body }, sound: "default" },
        ...payload.data,
      }),
    });

    if (res.ok) return { ok: true };
    const detail = await res.text();
    // 410 Unregistered / 400 BadDeviceToken: the token is dead, prune it.
    const unregistered = res.status === 410 || detail.includes("BadDeviceToken");
    return {
      ok: false,
      unregistered,
      retryable: res.status === 429 || res.status >= 500,
      detail,
    };
  }
}

/** Picks the transport from the environment. Absent secrets ⇒ no-op. */
export function resolveTransport(): PushTransport {
  const p8 = Deno.env.get("APNS_KEY_P8");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const topic = Deno.env.get("APNS_TOPIC");
  if (p8 && keyId && teamId && topic) {
    return new ApnsTransport(p8, keyId, teamId, topic);
  }
  return new NoopTransport();
}
```

- [ ] **Step 2: Write the drain loop**

Create `supabase/functions/push/index.ts`:

```ts
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { type ApnsPayload, resolveTransport } from "./transport.ts";

const COPY: Record<string, (actor: string, group: string | null) => [string, string]> = {
  post_like: (a) => ["New like", `${a} liked your post`],
  post_comment: (a) => ["New comment", `${a} commented on your post`],
  post_tag: (a) => ["You were tagged", `${a} tagged you in a post`],
  member_checked_in: (a, g) => ["Check-in", `${a} checked in${g ? ` in ${g}` : ""}`],
  checkin_reminder: (_a, g) => ["Time to check in", g ? `${g} is waiting on you` : "Your group is waiting on you"],
  group_invite: (a, g) => ["Group invite", `${a} invited you to ${g ?? "a group"}`],
  friend_request: (a) => ["Friend request", `${a} sent you a friend request`],
  friend_accepted: (a) => ["Friend request accepted", `${a} accepted your friend request`],
};

Deno.serve(async () => {
  const transport = resolveTransport();
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // The 1-day window is what keeps the backlog bounded while NoopTransport
  // leaves rows unpushed. Served by notifications_unpushed_idx.
  const since = new Date(Date.now() - 86_400_000).toISOString();
  const { data: pending, error } = await db
    .from("notifications")
    .select("id,recipient_id,type,post_id,group_id,actor:profiles(username),group:groups(name)")
    .is("pushed_at", null)
    .gt("created_at", since)
    .order("created_at", { ascending: true })
    .limit(500);

  if (error) return Response.json({ error: error.message }, { status: 500 });

  // CRITICAL: the no-op transport must NOT stamp pushed_at. If it did, then on
  // the day an APNs key arrives every accumulated notification would already be
  // marked delivered and the first real push would be for whatever happened
  // next, with no way to tell what was silently dropped. Leaving them unpushed
  // makes enabling APNs one secret plus one deploy.
  if (transport.name === "noop") {
    return Response.json({ transport: "noop", pending: pending?.length ?? 0, sent: 0, failed: 0, pruned: 0 });
  }

  let sent = 0, failed = 0, pruned = 0;
  for (const n of pending ?? []) {
    const { data: tokens } = await db
      .from("device_tokens").select("token").eq("user_id", n.recipient_id);
    if (!tokens?.length) continue;

    const build = COPY[n.type];
    if (!build) { failed++; continue; }
    // deno-lint-ignore no-explicit-any
    const actorName = (n as any).actor?.username ?? "Someone";
    // deno-lint-ignore no-explicit-any
    const groupName = (n as any).group?.name ?? null;
    const [title, body] = build(actorName, groupName);
    const payload: ApnsPayload = {
      title, body,
      data: { type: n.type, notification_id: n.id, post_id: n.post_id, group_id: n.group_id },
    };

    let delivered = false;
    for (const { token } of tokens) {
      const r = await transport.send(token, payload);
      if (r.ok) { delivered = true; continue; }
      if (r.unregistered) {
        await db.from("device_tokens").delete().eq("token", token);
        pruned++;
      }
    }

    if (delivered) {
      await db.from("notifications").update({ pushed_at: new Date().toISOString() }).eq("id", n.id);
      sent++;
    } else {
      failed++;  // retryable: pushed_at stays null, next run picks it up
    }
  }

  return Response.json({ transport: transport.name, pending: pending?.length ?? 0, sent, failed, pruned });
});
```

- [ ] **Step 3: Deploy**

Call `mcp__supabase__deploy_edge_function` with name `push`, entrypoint `index.ts`, `verify_jwt: true`, and both files.
Expected: success.

- [ ] **Step 4: Invoke it once and confirm the no-op contract**

Invoke with the service-role key as bearer.
Expected body: `{"transport":"noop","pending":N,"sent":0,"failed":0,"pruned":0}`.

Then assert the rows were **not** touched:
```sql
select count(*) from public.notifications where pushed_at is not null;
```
Expected: `0`. **If this is non-zero the no-op contract is broken — stop and fix before continuing.**

- [ ] **Step 5: Schedule the drain**

Create `supabase/migrations/20260720010400_push_cron.sql`:

```sql
-- Plan 6 Task 5 — drain the notification queue once a minute.
-- Harmless while the transport is a no-op: the function short-circuits and
-- mutates nothing.
select cron.schedule('push-notifications', '* * * * *', $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
    ),
    body    := '{}'::jsonb
  );
$$);
```

Both vault secrets must exist first. Check, and create them if missing:
```sql
select name from vault.secrets where name in ('project_url','service_role_key');
-- if absent:
-- select vault.create_secret('https://jstdoizgosatitptyrdy.supabase.co', 'project_url');
-- select vault.create_secret('<service role key>', 'service_role_key');
```

- [ ] **Step 6: Apply and verify**

`apply_migration`, name `push_cron`. Then after ~2 minutes:
```sql
select jobname, status, return_message, end_time from cron.job_run_details d
join cron.job j using (jobid) where j.jobname = 'push-notifications'
order by end_time desc limit 3;
```
Expected: `succeeded` rows.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/push supabase/migrations/20260720010400_push_cron.sql
git commit -m "feat(push): push Edge Function behind a swappable transport

ApnsTransport is written and reviewed but never selected -- resolveTransport
falls back to NoopTransport until the four APNS_* secrets exist. NoopTransport
deliberately does not stamp pushed_at, so enabling APNs later is one secret plus
one deploy with no backlog to reconcile. A 1-day selection window keeps the
unpushed queue bounded meanwhile."
```

---

## Task 6: Swift models + `NotificationServicing`

Spec §8.1–8.2.

**Files:**
- Modify: `Models/FeedModels.swift`, `Services/SocialServicing.swift`, `BibleShareTests/FakeSocialServices.swift`
- Create: `Services/NotificationService.swift`, `BibleShareTests/NotificationModelTests.swift`

**Interfaces:**
- Consumes: Task 2's RPCs (`mark_notifications_read`, `register_device_token`, `unregister_device_token`); `AppNotification`, `NotificationType`, `Profile`, `FellowshipGroup` (existing)
- Produces: `PostSummary`, `NotificationItem`, `protocol NotificationServicing`, `NotificationService.shared`, `FakeNotificationService`

- [ ] **Step 1: Write the failing decode tests**

Create `BibleShareTests/NotificationModelTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleShare

struct NotificationModelTests {
    @Test func decodesRowWithEmbeddedActorGroupAndPost() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "recipient_id":"22222222-2222-2222-2222-222222222222",
         "type":"post_like","actor_id":"33333333-3333-3333-3333-333333333333",
         "group_id":null,"post_id":"44444444-4444-4444-4444-444444444444",
         "read_at":null,"pushed_at":null,"created_at":"2026-07-21T10:00:00Z",
         "actor":{"id":"33333333-3333-3333-3333-333333333333","username":"ruth",
                  "username_set":true,"display_name":"Ruth","avatar_url":null,
                  "bio":null,"created_at":"2026-07-01T00:00:00Z"},
         "group":null,
         "post":{"id":"44444444-4444-4444-4444-444444444444",
                 "kind":"encouragement","title":"Morning"}}
        """
        let item = try TestDecoder.make().decode(NotificationItem.self, from: Data(json.utf8))
        #expect(item.type == .postLike)
        #expect(item.actor?.username == "ruth")
        #expect(item.post?.title == "Morning")
        #expect(item.isUnread)
    }

    /// RLS can legitimately hide the actor (a co-member who left, an actor whose
    /// only link was a deleted post). The row must still decode and render.
    @Test func decodesWithNullActorAndFallsBackToNeutralCopy() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "recipient_id":"22222222-2222-2222-2222-222222222222",
         "type":"post_like","actor_id":null,"group_id":null,
         "post_id":"44444444-4444-4444-4444-444444444444",
         "read_at":"2026-07-21T11:00:00Z","pushed_at":null,
         "created_at":"2026-07-21T10:00:00Z",
         "actor":null,"group":null,"post":null}
        """
        let item = try TestDecoder.make().decode(NotificationItem.self, from: Data(json.utf8))
        #expect(item.actor == nil)
        #expect(item.actorName == "Someone")
        #expect(item.isUnread == false)
    }

    @Test func checkinReminderHasNoActorByDesign() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "recipient_id":"22222222-2222-2222-2222-222222222222",
         "type":"checkin_reminder","actor_id":null,
         "group_id":"55555555-5555-5555-5555-555555555555","post_id":null,
         "read_at":null,"pushed_at":null,"created_at":"2026-07-21T10:00:00Z",
         "actor":null,
         "group":{"id":"55555555-5555-5555-5555-555555555555",
                  "creator_id":"22222222-2222-2222-2222-222222222222",
                  "name":"Daily Crew","description":null,
                  "checkin_cadence":"daily","checkin_time":"08:00:00",
                  "checkin_weekday":null,"timezone":"UTC",
                  "created_at":"2026-07-01T00:00:00Z"},
         "post":null}
        """
        let item = try TestDecoder.make().decode(NotificationItem.self, from: Data(json.utf8))
        #expect(item.type == .checkinReminder)
        #expect(item.group?.name == "Daily Crew")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cp /Users/sam/Repos/BibleShare/Resources/Secrets.plist Resources/Secrets.plist
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: compile failure — `cannot find 'NotificationItem' in scope`.

- [ ] **Step 3: Add the DTOs**

Append to `Models/FeedModels.swift`:

```swift
/// A notification's post, kept deliberately thinner than `FeedItem` — a
/// notification row needs a label, not attachments, counts, or an author
/// embed it may not even be allowed to see.
struct PostSummary: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: PostKind
    let title: String?
}

/// One notification row with its PostgREST embeds. `actor` is optional
/// because RLS can legitimately hide it; rendering must degrade, never blank.
struct NotificationItem: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let recipientID: UUID
    let type: NotificationType
    let actorID: UUID?
    let groupID: UUID?
    let postID: UUID?
    var readAt: Date?
    let createdAt: Date
    let actor: Profile?
    let group: FellowshipGroup?
    let post: PostSummary?

    var isUnread: Bool { readAt == nil }

    /// Neutral fallback so a hidden actor reads as "Someone liked your post"
    /// rather than an empty row.
    var actorName: String {
        actor?.displayName ?? actor?.username ?? "Someone"
    }

    enum CodingKeys: String, CodingKey {
        case id, type, actor, group, post
        case recipientID = "recipient_id"
        case actorID = "actor_id"
        case groupID = "group_id"
        case postID = "post_id"
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}
```

> `Profile.displayName` is `String?` and `username` is non-optional (`Models/Models.swift:6-13`), so both `??` rungs are load-bearing. Note that `Profile` also requires `username_set` and `bio` — any hand-written test JSON must include them or the decode fails.

- [ ] **Step 4: Run to verify the tests pass**

```bash
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: `TEST SUCCEEDED`, 104 tests / 19 suites.

- [ ] **Step 5: Add the protocol**

Append to `Services/SocialServicing.swift`:

```swift
protocol NotificationServicing: Sendable {
    /// Newest first, keyset-paginated on `created_at`.
    func fetchNotifications(before: Date?, limit: Int) async throws -> [NotificationItem]
    func unreadCount() async throws -> Int
    /// `nil` marks every unread notification read.
    func markRead(ids: [UUID]?) async throws
    /// Best-effort: a failure must never block sign-in or sign-out.
    func registerDeviceToken(_ token: String) async throws
    func unregisterDeviceToken(_ token: String) async throws
}
```

- [ ] **Step 6: Implement the live service**

Create `Services/NotificationService.swift`:

```swift
import Foundation
import Supabase

final class NotificationService: NotificationServicing {
    static let shared = NotificationService()

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    /// notifications.actor_id -> profiles is the redundant FK added in Task 2;
    /// without it PostgREST cannot embed a profile through auth.users.
    private static let select = """
    id,recipient_id,type,actor_id,group_id,post_id,read_at,created_at,\
    actor:profiles(*),group:groups(*),post:posts(id,kind,title)
    """

    func fetchNotifications(before: Date?, limit: Int) async throws -> [NotificationItem] {
        var query = client.from("notifications").select(Self.select)
        if let before {
            query = query.lt("created_at", value: ISO8601DateFormatter().string(from: before))
        }
        return try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func unreadCount() async throws -> Int {
        // RLS (notif_select_own) already scopes this to the caller.
        let response = try await client.from("notifications")
            .select("id", head: true, count: .exact)
            .is("read_at", value: nil)
            .execute()
        return response.count ?? 0
    }

    func markRead(ids: [UUID]?) async throws {
        struct Params: Encodable { let p_ids: [String]? }
        try await client
            .rpc("mark_notifications_read", params: Params(p_ids: ids?.map(\.uuidString)))
            .execute()
    }

    func registerDeviceToken(_ token: String) async throws {
        struct Params: Encodable { let p_token: String; let p_platform: String }
        try await client
            .rpc("register_device_token", params: Params(p_token: token, p_platform: "ios"))
            .execute()
    }

    func unregisterDeviceToken(_ token: String) async throws {
        struct Params: Encodable { let p_token: String }
        try await client
            .rpc("unregister_device_token", params: Params(p_token: token))
            .execute()
    }
}
```

- [ ] **Step 7: Add the fake (additive only)**

Append to `BibleShareTests/FakeSocialServices.swift` — do not modify any existing type in this file:

```swift
final class FakeNotificationService: NotificationServicing, @unchecked Sendable {
    var items: [NotificationItem] = []
    var unread = 0
    var fetchError: Error?
    var markReadError: Error?
    private(set) var markReadCalls: [[UUID]?] = []
    private(set) var registeredTokens: [String] = []
    private(set) var unregisteredTokens: [String] = []

    func fetchNotifications(before: Date?, limit: Int) async throws -> [NotificationItem] {
        if let fetchError { throw fetchError }
        return items
    }
    func unreadCount() async throws -> Int {
        if let fetchError { throw fetchError }
        return unread
    }
    func markRead(ids: [UUID]?) async throws {
        markReadCalls.append(ids)
        if let markReadError { throw markReadError }
    }
    func registerDeviceToken(_ token: String) async throws { registeredTokens.append(token) }
    func unregisterDeviceToken(_ token: String) async throws { unregisteredTokens.append(token) }
}
```

- [ ] **Step 8: Regenerate, build, test**

```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: `TEST SUCCEEDED`, 104 tests / 19 suites.

- [ ] **Step 9: Commit**

```bash
git add Models/FeedModels.swift Services/SocialServicing.swift Services/NotificationService.swift BibleShareTests/
git commit -m "feat(notifications): NotificationItem DTO and NotificationServicing seam

The actor embed is optional throughout -- RLS can legitimately hide it -- so
NotificationItem.actorName falls back to neutral copy instead of a blank row.
PostSummary is deliberately thinner than FeedItem."
```

---

## Task 7: `NotificationsViewModel` + destination mapping

Spec §8.4.

**Files:**
- Create: `ViewModels/NotificationsViewModel.swift`, `BibleShareTests/NotificationsViewModelTests.swift`, `BibleShareTests/NotificationDestinationTests.swift`

**Interfaces:**
- Consumes: `NotificationServicing`, `NotificationItem` (Task 6)
- Produces: `enum NotificationDestination`, `NotificationDestination.from(_:)`, `@Observable NotificationsViewModel` with `items`, `unreadCount`, `load()`, `markAllRead()`, `markRead(_:)`

- [ ] **Step 1: Write the failing destination tests**

Create `BibleShareTests/NotificationDestinationTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleShare

struct NotificationDestinationTests {
    private func item(_ type: NotificationType, post: UUID? = nil, group: UUID? = nil) -> NotificationItem {
        let json = """
        {"id":"\(UUID().uuidString)","recipient_id":"\(UUID().uuidString)",
         "type":"\(type.rawValue)","actor_id":null,
         "group_id":\(group.map { "\"\($0.uuidString)\"" } ?? "null"),
         "post_id":\(post.map { "\"\($0.uuidString)\"" } ?? "null"),
         "read_at":null,"pushed_at":null,"created_at":"2026-07-21T10:00:00Z",
         "actor":null,"group":null,"post":null}
        """
        return try! TestDecoder.make().decode(NotificationItem.self, from: Data(json.utf8))
    }

    @Test func postTypesRouteToThePost() {
        let p = UUID()
        for t in [NotificationType.postLike, .postComment, .postTag, .memberCheckedIn] {
            #expect(NotificationDestination.from(item(t, post: p)) == .post(p))
        }
    }

    @Test func reminderRoutesToItsGroup() {
        let g = UUID()
        #expect(NotificationDestination.from(item(.checkinReminder, group: g)) == .group(g))
    }

    @Test func inviteRoutesToTheInvitesScreenNotTheGroup() {
        // You are not a member yet, so the group timeline would be empty.
        #expect(NotificationDestination.from(item(.groupInvite, group: UUID())) == .invites)
    }

    @Test func friendTypesRouteToFriends() {
        #expect(NotificationDestination.from(item(.friendRequest)) == .friends)
        #expect(NotificationDestination.from(item(.friendAccepted)) == .friends)
    }

    /// A check-in whose post was deleted: group_checkins.post_id is ON DELETE
    /// SET NULL by design, so the ledger row survives with a null post.
    @Test func postTypeWithoutAPostFallsBackToItsGroup() {
        let g = UUID()
        #expect(NotificationDestination.from(item(.memberCheckedIn, group: g)) == .group(g))
    }

    @Test func postTypeWithNeitherIsUnroutable() {
        #expect(NotificationDestination.from(item(.postLike)) == nil)
    }
}
```

- [ ] **Step 2: Write the failing view-model tests**

Create `BibleShareTests/NotificationsViewModelTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleShare

@MainActor
struct NotificationsViewModelTests {
    private func unreadItem() -> NotificationItem {
        let json = """
        {"id":"\(UUID().uuidString)","recipient_id":"\(UUID().uuidString)",
         "type":"post_like","actor_id":null,"group_id":null,
         "post_id":"\(UUID().uuidString)","read_at":null,"pushed_at":null,
         "created_at":"2026-07-21T10:00:00Z","actor":null,"group":null,"post":null}
        """
        return try! TestDecoder.make().decode(NotificationItem.self, from: Data(json.utf8))
    }

    @Test func loadPopulatesItemsAndUnreadCount() async {
        let fake = FakeNotificationService()
        fake.items = [unreadItem(), unreadItem()]
        fake.unread = 2
        let vm = NotificationsViewModel(service: fake)

        await vm.load()

        #expect(vm.items.count == 2)
        #expect(vm.unreadCount == 2)
        #expect(vm.errorMessage == nil)
    }

    @Test func loadFailureSurfacesAnErrorAndKeepsListEmpty() async {
        let fake = FakeNotificationService()
        fake.fetchError = PostErrorStub.boom
        let vm = NotificationsViewModel(service: fake)

        await vm.load()

        #expect(vm.items.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test func markAllReadClearsBadgeOptimistically() async {
        let fake = FakeNotificationService()
        fake.items = [unreadItem(), unreadItem()]
        fake.unread = 2
        let vm = NotificationsViewModel(service: fake)
        await vm.load()

        await vm.markAllRead()

        #expect(vm.unreadCount == 0)
        #expect(vm.items.allSatisfy { !$0.isUnread })
        #expect(fake.markReadCalls == [nil])
    }

    /// The badge is the whole point of the tab — a failed write must not leave
    /// it lying about unread state.
    @Test func markAllReadRollsBackWhenTheWriteFails() async {
        let fake = FakeNotificationService()
        fake.items = [unreadItem(), unreadItem()]
        fake.unread = 2
        let vm = NotificationsViewModel(service: fake)
        await vm.load()
        fake.markReadError = PostErrorStub.boom

        await vm.markAllRead()

        #expect(vm.unreadCount == 2)
        #expect(vm.items.allSatisfy { $0.isUnread })
        #expect(vm.errorMessage != nil)
    }
}
```

- [ ] **Step 3: Run to verify both fail**

```bash
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: compile failure — `cannot find 'NotificationDestination'` / `'NotificationsViewModel'`.

- [ ] **Step 4: Implement**

Create `ViewModels/NotificationsViewModel.swift`:

```swift
import Foundation

/// Where tapping a notification goes. A pure mapping so it can be unit-tested
/// away from navigation, and so the APNs tap handler can reuse it verbatim.
enum NotificationDestination: Equatable, Hashable, Sendable {
    case post(UUID)
    case group(UUID)
    case invites
    case friends

    static func from(_ item: NotificationItem) -> NotificationDestination? {
        switch item.type {
        case .postLike, .postComment, .postTag, .memberCheckedIn:
            // group_checkins.post_id is ON DELETE SET NULL by design, so a
            // check-in notification can outlive its post. Fall back to the group.
            if let postID = item.postID { return .post(postID) }
            if let groupID = item.groupID { return .group(groupID) }
            return nil
        case .checkinReminder:
            return item.groupID.map { .group($0) }
        case .groupInvite:
            // Not a member yet — the group timeline would be empty.
            return .invites
        case .friendRequest, .friendAccepted:
            return .friends
        }
    }
}

@MainActor
@Observable
final class NotificationsViewModel {
    private(set) var items: [NotificationItem] = []
    private(set) var unreadCount = 0
    private(set) var isLoading = false
    var errorMessage: String?

    private let service: NotificationServicing
    private let pageSize = 40

    init(service: NotificationServicing = NotificationService.shared) {
        self.service = service
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await service.fetchNotifications(before: nil, limit: pageSize)
            unreadCount = try await service.unreadCount()
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func loadMore() async {
        guard let oldest = items.last?.createdAt, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items += try await service.fetchNotifications(before: oldest, limit: pageSize)
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func markAllRead() async {
        // Optimistic: the badge is the point of the tab, so it clears now and
        // rolls back wholesale if the write fails.
        let snapshotItems = items
        let snapshotCount = unreadCount
        let now = Date()
        for index in items.indices where items[index].isUnread { items[index].readAt = now }
        unreadCount = 0
        do {
            try await service.markRead(ids: nil)
        } catch {
            items = snapshotItems
            unreadCount = snapshotCount
            errorMessage = PostError.message(for: error)
        }
    }

    func markRead(_ item: NotificationItem) async {
        guard item.isUnread, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let snapshotItems = items
        let snapshotCount = unreadCount
        items[index].readAt = Date()
        unreadCount = max(0, unreadCount - 1)
        do {
            try await service.markRead(ids: [item.id])
        } catch {
            items = snapshotItems
            unreadCount = snapshotCount
            errorMessage = PostError.message(for: error)
        }
    }
}
```

- [ ] **Step 5: Run to verify they pass**

```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: `TEST SUCCEEDED`, 114 tests / 21 suites.

- [ ] **Step 6: Commit**

```bash
git add ViewModels/NotificationsViewModel.swift BibleShareTests/NotificationsViewModelTests.swift BibleShareTests/NotificationDestinationTests.swift
git commit -m "feat(notifications): NotificationsViewModel with optimistic mark-read

NotificationDestination is a pure mapping, unit-tested away from navigation so
the APNs tap handler can reuse it verbatim. Mark-read rolls back wholesale on
failure -- a stale badge is the one thing this tab must never show."
```

---

## Task 8: Notifications tab, rows, and deep links

Spec §8.3–8.4.

**Files:**
- Create: `Views/NotificationsView.swift`, `Views/Components/NotificationRow.swift`, `ViewModels/AppRouter.swift`, `BibleShareTests/AppRouterTests.swift`
- Modify: `Views/RootTabView.swift`, `App/BibleShareApp.swift`

**Interfaces:**
- Consumes: `NotificationsViewModel`, `NotificationDestination`, `NotificationItem`
- Produces: `enum AppTab`, `@Observable AppRouter` with `selectedTab` and `select(_:)`

**Routing scope:** tab-level only, per spec §8.4. There is **no post-detail screen** in this app, `FriendsView` is a sheet driven by private `@State` in `ProfileView`, and `GroupTimelineView` is a `NavigationLink` inside `GroupsView`'s list — screen-level deep links would mean refactoring three unrelated views' navigation. The enum is the seam for that later work.

- [ ] **Step 1: Write the failing router test**

Create `BibleShareTests/AppRouterTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleShare

@MainActor
struct AppRouterTests {
    @Test func postDestinationSelectsHome() {
        let router = AppRouter()
        router.selectedTab = .alerts
        router.select(.post(UUID()))
        #expect(router.selectedTab == .home)
    }

    @Test func groupAndInviteDestinationsSelectGroups() {
        let router = AppRouter()
        router.select(.group(UUID()))
        #expect(router.selectedTab == .groups)
        router.selectedTab = .alerts
        router.select(.invites)
        #expect(router.selectedTab == .groups)
    }

    /// FriendsView is a sheet inside ProfileView, so Profile is as deep as
    /// tab-level routing can go.
    @Test func friendsDestinationSelectsProfile() {
        let router = AppRouter()
        router.select(.friends)
        #expect(router.selectedTab == .profile)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: `cannot find 'AppRouter' in scope`.

- [ ] **Step 3: Implement the router**

Create `ViewModels/AppRouter.swift`:

```swift
import Foundation

enum AppTab: Hashable, Sendable {
    case home, groups, checkIn, alerts, profile
}

/// Tab-level routing for notification taps. Screen-level deep links need a
/// navigation refactor this milestone does not absorb (spec §8.4) — this is
/// the seam that refactor will plug into.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home

    func select(_ destination: NotificationDestination) {
        switch destination {
        case .post:               selectedTab = .home
        case .group, .invites:    selectedTab = .groups
        case .friends:            selectedTab = .profile
        }
    }
}
```

- [ ] **Step 4: Build the row**

Create `Views/Components/NotificationRow.swift`:

```swift
import SwiftUI

struct NotificationRow: View {
    let item: NotificationItem

    /// Composed here rather than server-side so a hidden actor degrades to
    /// neutral copy instead of a blank row.
    private var message: String {
        let who = item.actorName
        let group = item.group?.name
        switch item.type {
        case .postLike:         return "\(who) liked your post"
        case .postComment:      return "\(who) commented on your post"
        case .postTag:          return "\(who) tagged you in a post"
        case .memberCheckedIn:  return group.map { "\(who) checked in in \($0)" } ?? "\(who) checked in"
        case .checkinReminder:  return group.map { "\($0) is waiting on you" } ?? "Time to check in"
        case .groupInvite:      return "\(who) invited you to \(group ?? "a group")"
        case .friendRequest:    return "\(who) sent you a friend request"
        case .friendAccepted:   return "\(who) accepted your friend request"
        }
    }

    private var icon: String {
        switch item.type {
        case .postLike:        return "heart.fill"
        case .postComment:     return "bubble.left.fill"
        case .postTag:         return "at"
        case .memberCheckedIn: return "checkmark.circle.fill"
        case .checkinReminder: return "bell.fill"
        case .groupInvite:     return "envelope.fill"
        case .friendRequest,
             .friendAccepted:  return "person.2.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.indigo)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.subheadline)
                Text(item.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if item.isUnread {
                Circle().fill(Theme.indigo).frame(width: 8, height: 8)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 5: Build the list**

Create `Views/NotificationsView.swift`:

```swift
import SwiftUI

struct NotificationsView: View {
    @Bindable var vm: NotificationsViewModel
    @State private var unavailableMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if vm.items.isEmpty && !vm.isLoading {
                    ContentUnavailableView("Nothing yet",
                                           systemImage: "bell",
                                           description: Text("Likes, comments and check-ins will show up here."))
                } else {
                    List {
                        ForEach(vm.items) { item in
                            Button { Task { await open(item) } } label: { NotificationRow(item: item) }
                                .buttonStyle(.plain)
                        }
                        if !vm.items.isEmpty {
                            Color.clear.frame(height: 1)
                                .onAppear { Task { await vm.loadMore() } }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                if vm.unreadCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark all read") { Task { await vm.markAllRead() } }
                    }
                }
            }
            .refreshable { await vm.load() }
            .task { await vm.load() }
            .alert("That's no longer available",
                   isPresented: .constant(unavailableMessage != nil),
                   presenting: unavailableMessage) { _ in
                Button("OK") { unavailableMessage = nil }
            } message: { Text($0) }
            .alert("Something went wrong",
                   isPresented: .constant(vm.errorMessage != nil),
                   presenting: vm.errorMessage) { _ in
                Button("OK") { vm.errorMessage = nil }
            } message: { Text($0) }
        }
    }

    private func open(_ item: NotificationItem) async {
        await vm.markRead(item)
        guard let destination = NotificationDestination.from(item) else {
            // Unresolvable: a check-in whose post was deleted and which carries
            // no group. Say so rather than selecting a tab that shows nothing.
            unavailableMessage = "That post or group isn't around anymore."
            return
        }
        router.select(destination)
    }
}
```

`NotificationsView` needs the router injected. Add to its properties:

```swift
    @Environment(AppRouter.self) private var router
```

- [ ] **Step 6: Add the tab and the selection binding**

Replace the body of `Views/RootTabView.swift`. The `TabView` gains a `selection:` binding and every tab a `.tag(...)` — without both, `AppRouter.select` changes state that nothing observes.

```swift
import SwiftUI

/// The signed-in shell. Home / Groups / Check-in / Alerts / Profile.
struct RootTabView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppRouter.self) private var router
    /// Hoisted so the Check-in tab's badge count and its list share one fetch.
    @State private var checkInVM = CheckInViewModel()
    /// Hoisted so the Alerts badge and its list share one fetch.
    @State private var notificationsVM = NotificationsViewModel()

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            if let userID = auth.profile?.id {
                GroupsView(myID: userID)
                    .tabItem { Label("Groups", systemImage: "person.3.fill") }
                    .tag(AppTab.groups)

                CheckInView(userID: userID, vm: checkInVM)
                    .tabItem { Label("Check-in", systemImage: "checkmark.circle") }
                    .badge(checkInVM.pendingCount)
                    .tag(AppTab.checkIn)

                NotificationsView(vm: notificationsVM)
                    .tabItem { Label("Alerts", systemImage: "bell.fill") }
                    .badge(notificationsVM.unreadCount)
                    .tag(AppTab.alerts)
            }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(Theme.indigo)
        .task {
            await checkInVM.load()
            await notificationsVM.load()
        }
    }
}

#Preview {
    RootTabView()
        .environment(AuthViewModel(provider: SupabaseService.shared))
        .environment(AppRouter())
}
```

> Five tabs is the maximum before SwiftUI collapses into a "More" list. The label is "Alerts", not "Notifications", so it fits without truncating.

- [ ] **Step 7: Inject the router at the app root**

In `App/BibleShareApp.swift`, add the state and the environment injection:

```swift
    @State private var router = AppRouter()
```
```swift
            RootView()
                .environment(authViewModel)
                .environment(router)
```

- [ ] **Step 8: Build and test**

```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: `TEST SUCCEEDED`, 117 tests / 22 suites.

- [ ] **Step 9: Commit**

```bash
git add Views/NotificationsView.swift Views/Components/NotificationRow.swift Views/RootTabView.swift ViewModels/AppRouter.swift App/BibleShareApp.swift BibleShareTests/AppRouterTests.swift
git commit -m "feat(notifications): Alerts tab with unread badge, row copy, and tab routing

Copy is composed client-side so a hidden actor degrades to 'Someone' instead of
a blank row. Routing is tab-level by design: there is no post-detail screen and
FriendsView is a sheet inside ProfileView, so screen-level deep links would mean
refactoring three unrelated views. NotificationDestination is the seam for that."
```

---

## Task 9: Local check-in reminders

Spec §7.4. APNs is unavailable, so reminders are delivered on-device.

**Files:**
- Create: `Services/CheckinReminderScheduler.swift`, `BibleShareTests/CheckinReminderSchedulerTests.swift`

**Interfaces:**
- Consumes: `FellowshipGroup` (`checkinCadence`, `checkinTime`, `checkinWeekday`, `timezone`), `GroupListItem`
- Produces: `CheckinReminderScheduler.nextOccurrences(for:after:count:) -> [Date]` (pure, static), `CheckinReminderScheduler.sync(groups:)`

- [ ] **Step 1: Write the failing date-math tests**

The scheduling side needs a real notification centre, so only the pure function is unit-tested — mirroring how Plan 5 tested `due_slot_for` rather than the cron.

Create `BibleShareTests/CheckinReminderSchedulerTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleShare

struct CheckinReminderSchedulerTests {
    private func group(cadence: CheckinCadence, time: String?, weekday: Int?, tz: String) -> FellowshipGroup {
        FellowshipGroup(id: UUID(), creatorID: UUID(), name: "G", description: nil,
                        checkinCadence: cadence, checkinTime: time, checkinWeekday: weekday,
                        timezone: tz, createdAt: Date())
    }

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    @Test func dailyProducesConsecutiveDaysAtTheGroupsLocalTime() {
        let g = group(cadence: .daily, time: "08:00:00", weekday: nil, tz: "America/New_York")
        let dates = CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T18:00:00Z"), count: 3)

        #expect(dates.count == 3)
        // 08:00 New York on 22 Jul = 12:00Z (EDT, UTC-4)
        #expect(dates[0] == iso("2026-07-22T12:00:00Z"))
        #expect(dates[1] == iso("2026-07-23T12:00:00Z"))
    }

    @Test func dailyLaterTodayStillCountsAsTheNextOccurrence() {
        let g = group(cadence: .daily, time: "20:00:00", weekday: nil, tz: "UTC")
        let dates = CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 1)
        #expect(dates[0] == iso("2026-07-21T20:00:00Z"))
    }

    @Test func weeklyLandsOnTheRequestedWeekday() {
        // weekday 0 = Sunday, matching the Postgres convention used by due_slot_for.
        let g = group(cadence: .weekly, time: "09:00:00", weekday: 0, tz: "UTC")
        let dates = CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 2)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        #expect(cal.component(.weekday, from: dates[0]) == 1)  // Foundation: 1 = Sunday
        #expect(dates[1].timeIntervalSince(dates[0]) == 7 * 86_400)
    }

    /// The group's own timezone governs, not the device's — a traveller must
    /// not get reminders shifted by wherever they happen to be.
    @Test func springForwardKeepsTheGroupsWallClockTime() {
        let g = group(cadence: .daily, time: "08:00:00", weekday: nil, tz: "America/New_York")
        let dates = CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-03-07T18:00:00Z"), count: 3)
        // 8 Mar 2026 is the US spring-forward. 08:00 local is 13:00Z before and
        // 12:00Z after, and the wall-clock time must stay 08:00 either way.
        #expect(dates[0] == iso("2026-03-08T12:00:00Z"))
    }

    @Test func cadenceNoneProducesNothing() {
        let g = group(cadence: .none, time: nil, weekday: nil, tz: "UTC")
        #expect(CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 3).isEmpty)
    }

    @Test func aMissingTimeProducesNothingRatherThanGuessing() {
        let g = group(cadence: .daily, time: nil, weekday: nil, tz: "UTC")
        #expect(CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 3).isEmpty)
    }

    @Test func anUnknownTimezoneProducesNothingRatherThanFallingBackToDeviceLocal() {
        let g = group(cadence: .daily, time: "08:00:00", weekday: nil, tz: "Mars/Olympus")
        #expect(CheckinReminderScheduler.nextOccurrences(
            for: g, after: iso("2026-07-21T10:00:00Z"), count: 3).isEmpty)
    }
}
```

> Check `FellowshipGroup`'s memberwise initializer parameter order in `Models/Models.swift:93` before writing — it must match exactly.

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: `cannot find 'CheckinReminderScheduler' in scope`.

- [ ] **Step 3: Implement**

Create `Services/CheckinReminderScheduler.swift`:

```swift
import Foundation
import UserNotifications

/// Local check-in reminders. APNs has no signing key yet (spec §7.3), so the
/// reminder that would arrive as a push is scheduled on-device instead.
enum CheckinReminderScheduler {
    /// iOS keeps at most 64 pending requests per app; leave headroom.
    static let maxPending = 48
    private static let prefix = "checkin-"

    /// The next `count` reminder instants for a group, in the GROUP's timezone.
    /// Pure and total: an unusable schedule yields `[]` rather than a guess.
    static func nextOccurrences(for group: FellowshipGroup,
                                after now: Date,
                                count: Int) -> [Date] {
        guard group.checkinCadence != .none,
              let hhmmss = group.checkinTime,
              let zone = TimeZone(identifier: group.timezone)
        else { return [] }

        let parts = hhmmss.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        var components = DateComponents()
        components.hour = parts[0]
        components.minute = parts[1]
        components.second = parts.count > 2 ? parts[2] : 0

        if group.checkinCadence == .weekly {
            guard let weekday = group.checkinWeekday, (0...6).contains(weekday) else { return [] }
            // Postgres uses 0 = Sunday; Foundation uses 1 = Sunday.
            components.weekday = weekday + 1
        }

        var results: [Date] = []
        var cursor = now
        for _ in 0..<count {
            // matchingPolicy .nextTime resolves a wall-clock time that a DST
            // spring-forward skipped, instead of returning nil.
            guard let next = calendar.nextDate(after: cursor,
                                               matching: components,
                                               matchingPolicy: .nextTime) else { break }
            results.append(next)
            cursor = next
        }
        return results
    }

    /// Idempotent: replaces this app's check-in requests wholesale, so groups
    /// whose schedule changed (or that were left) cannot leave a stale reminder.
    static func sync(groups: [FellowshipGroup],
                     center: UNUserNotificationCenter = .current(),
                     now: Date = Date()) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        let existing = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: existing.map(\.identifier).filter { $0.hasPrefix(prefix) })

        // Soonest-first across all groups, so the 64-request ceiling truncates
        // the far future rather than dropping a whole group.
        let upcoming = groups
            .flatMap { group in
                nextOccurrences(for: group, after: now, count: 8).map { (group, $0) }
            }
            .sorted { $0.1 < $1.1 }
            .prefix(maxPending)

        for (group, date) in upcoming {
            let content = UNMutableNotificationContent()
            content.title = "Time to check in"
            content.body = "\(group.name) is waiting on you"
            content.sound = .default
            content.userInfo = ["type": "checkin_reminder", "group_id": group.id.uuidString]

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: group.timezone) ?? .current
            let fields = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

            let request = UNNotificationRequest(
                identifier: "\(prefix)\(group.id.uuidString)-\(Int(date.timeIntervalSince1970))",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: fields, repeats: false))
            try? await center.add(request)
        }
    }

    /// Asked at the point of value, not at launch.
    @discardableResult
    static func requestAuthorization(
        center: UNUserNotificationCenter = .current()
    ) async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: `TEST SUCCEEDED`, 124 tests / 23 suites.

- [ ] **Step 5: Commit**

```bash
git add Services/CheckinReminderScheduler.swift BibleShareTests/CheckinReminderSchedulerTests.swift
git commit -m "feat(checkins): local check-in reminders while APNs is unavailable

The date math is a pure, total function tested across timezones and a DST
spring-forward -- an unusable schedule yields no reminders rather than a guess
in device-local time. Scheduling replaces this app's requests wholesale so a
changed or left group cannot strand a reminder."
```

---

## Task 10: APNs registration wiring

Spec §8.5. Completes the seam so enabling APNs needs no Swift change.

**Files:**
- Create: `Services/PushRegistrar.swift`
- Modify: `App/BibleShareApp.swift`, `project.yml`

**Interfaces:**
- Consumes: `NotificationServicing` (Task 6), `CheckinReminderScheduler.requestAuthorization` (Task 9)
- Produces: `PushRegistrar.shared`, `AppDelegate`

- [ ] **Step 1: Add the background mode**

In `project.yml`, under `targets.BibleShare.settings.base`, add:

```yaml
        INFOPLIST_KEY_UIBackgroundModes: remote-notification
```

> `GENERATE_INFOPLIST_FILE` is `NO` and `INFOPLIST_FILE` is `Resources/Info.plist`, so `INFOPLIST_KEY_*` build settings are ignored. Add the key to `Resources/Info.plist` instead:
> ```xml
> <key>UIBackgroundModes</key>
> <array><string>remote-notification</string></array>
> ```

- [ ] **Step 2: Write the registrar**

Create `Services/PushRegistrar.swift`:

```swift
import Foundation
import UIKit

/// Bridges the APNs device-token callback to `device_tokens`. Everything here
/// is best-effort: without a provisioning profile the simulator's registration
/// simply fails, and that must never surface to the user or block auth.
@MainActor
final class PushRegistrar {
    static let shared = PushRegistrar()

    private let service: NotificationServicing
    private var currentToken: String?

    init(service: NotificationServicing = NotificationService.shared) {
        self.service = service
    }

    /// Called after sign-in. Authorization is requested here — the point of
    /// value — rather than at launch.
    func registerAfterLogin() async {
        guard await CheckinReminderScheduler.requestAuthorization() else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        currentToken = token
        do { try await service.registerDeviceToken(token) } catch {
            // A dead token is recoverable on the next launch; never surface it.
            print("[push] token registration failed: \(error)")
        }
    }

    func didFailToRegister(error: Error) {
        // Expected on the simulator and without a provisioning profile.
        print("[push] remote notification registration unavailable: \(error)")
    }

    /// Called before sign-out, while the session can still authorize the RPC.
    func unregisterBeforeLogout() async {
        guard let token = currentToken else { return }
        try? await service.unregisterDeviceToken(token)
        currentToken = nil
    }
}
```

- [ ] **Step 3: Wire the app delegate**

Replace `App/BibleShareApp.swift`:

```swift
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushRegistrar.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushRegistrar.shared.didFailToRegister(error: error) }
    }
}

@main
struct BibleShareApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// App-wide auth state, injected into the view hierarchy.
    @State private var authViewModel = AuthViewModel()
    /// Added in Task 8 — keep it; RootTabView's selection binding depends on it.
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authViewModel)
                .environment(router)
        }
    }
}
```

- [ ] **Step 4: Trigger registration once signed in**

In `Views/RootTabView.swift`, extend the existing `.task`:

```swift
        .task {
            await checkInVM.load()
            await notificationsVM.load()
            await PushRegistrar.shared.registerAfterLogin()
        }
```

- [ ] **Step 5: Build and test**

```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: `TEST SUCCEEDED`, 124 tests / 23 suites. The simulator logs `[push] remote notification registration unavailable` — that is the expected, correct path with no key.

- [ ] **Step 6: Commit**

```bash
git add Services/PushRegistrar.swift App/BibleShareApp.swift project.yml Resources/Info.plist Views/RootTabView.swift
git commit -m "feat(push): register APNs device tokens after sign-in

Registration is entirely best-effort -- the simulator has no provisioning
profile, so failure is the expected path today and must never surface or block
auth. With this the seam is complete: enabling APNs needs Edge secrets and a
deploy, and no Swift change."
```

---

## Task 11: Migration reconciliation + final whole-branch review

- [ ] **Step 1: Reconcile migration files against live versions**

Filenames are hand-numbered while `apply_migration` stamps wall-clock versions, so a migration can be applied live and its file silently never committed — that happened to `harden_function_grants` and was only caught during a later cleanup.

```bash
ls supabase/migrations/
```
Then call `mcp__supabase__list_migrations` and confirm **every** live version added by this plan has a committed file, and every new file was applied. Five migrations are expected: `tag_visibility_gate`, `notification_plumbing`, `notification_triggers`, `checkin_cron_health`, `push_cron`.

- [ ] **Step 2: Final security advisor sweep**

`get_advisors type:"security"`.
Expected total new findings for the whole plan: exactly **three** definer-executable WARNs (`mark_notifications_read`, `register_device_token`, `unregister_device_token`). Anything else is a defect to fix before review.

- [ ] **Step 3: Full suite**

```bash
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: `TEST SUCCEEDED`, 124 tests / 23 suites, zero failures.

- [ ] **Step 4: Whole-branch review on the most capable model**

Dispatch a final review over the complete branch diff (`git diff main...HEAD`). **Do not skip this** — in Plan 5 it caught a Critical that per-task reviews structurally could not see. Direct the reviewer specifically at:

- the tag gate closing **both** legs (RPCs *and* the dropped `pt_insert_owner`);
- whether any trigger can raise inside `open_checkin_windows`' `exception when others` and silently lose a window;
- the `NoopTransport` no-stamp contract (§7.3) — a regression here is invisible until the day APNs is switched on;
- notification fan-out that could reach a user who cannot see the referenced post or group;
- the `member_checked_in` dedupe index versus `check_in`'s `if not found`.

- [ ] **Step 5: Fix every finding, re-run the suite, then open the PR against `main`**

---

## Manual E2E (cannot be automated)

Real APNs delivery is untestable without a key, and the simulator cannot receive remote push at all. Before merge, run a two-account / one-group pass on device or simulator:

1. Account A likes, comments on, and tags B in a post → three rows in B's Alerts tab with correct copy and a working relative timestamp.
2. A invites B to a group → B sees `group_invite` **with A's name** (this is what `private.invite_counterparty` fixes).
3. A checks in to a group containing B and C → exactly one `member_checked_in` each, none for A.
4. B sends A a friend request; A accepts → `friend_request` for A, then `friend_accepted` for B.
5. Badge clears on "Mark all read" and stays cleared after a relaunch.
6. Confirm `select count(*) from notifications where pushed_at is not null` is still **0** — the no-op transport must not have stamped anything.
