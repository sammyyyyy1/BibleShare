# BibleShare — Notifications & Push Design (Plan 6)

**Status:** approved, ready for planning
**Date:** 2026-07-21
**Milestone:** 6 of 6 in the social layer (see `2026-07-15-groups-encouragements-checkins-design.md` §3.6, §5, §6, Milestone 6)
**Depends on:** Plans 1–5, all merged to `main` (Plan 5 merge commit `bfa7051`)

---

## 1. Goals & non-goals

### Goals

1. Close the `p_tag_user_ids` hole in both write paths before any notification fans out over tags.
2. Write notification rows for all eight declared types, from triggers, with no changes to any Plan 2–5 RPC body.
3. Ship the in-app notification list with an unread badge.
4. Register APNs device tokens and build the `push` Edge Function with a transport seam, so enabling real APNs later is a secret plus a deploy.
5. Deliver check-in reminders locally (on-device) while APNs is unavailable.
6. Tighten `notifications` and `device_tokens` to the project's RPC-only write posture.
7. Add minimal health monitoring to the `open-checkin-windows` cron.

### Non-goals

- Real APNs delivery. No Apple Developer `.p8` key is available (see §7.3). The transport seam is built and exercised; the Apple leg is not.
- Supabase Realtime subscriptions for live badge updates. Polling on tab appear and app foreground is sufficient; revisit only with evidence.
- Notification preferences / per-type mute. Not in the spec's data model; a future plan.
- Email or SMS channels.
- A general-purpose alerting system. §6 is scoped to one cron job.

### The discipline this plan ends

Plans 2–5 deliberately wrote **zero** notification rows and **zero** triggers, deferring all of it here so it lands coherently at once. This plan is where that ends.

---

## 2. Architecture

Notifications are a **pure function of the row graph**. Every notification type corresponds to a row appearing or changing state; an `AFTER` trigger on that table writes the notification. Nothing in `create_encouragement`, `check_in`, `invite_to_group`, `respond_to_invite`, `send_friend_request`, `respond_to_friend_request`, or `private.open_checkin_windows` changes — except the Task-1 tag gate, which is a validation, not a notification write.

Delivery is a separate, lagging concern. The in-app list reads `notifications` directly over PostgREST. Push drains the same table through an Edge Function whose transport is swappable and is currently a no-op.

```
                  ┌─ likes                 ──▶ post_like
                  ├─ comments              ──▶ post_comment
                  ├─ post_tags             ──▶ post_tag
row write ────────┼─ group_checkins        ──▶ member_checked_in ──▶ notifications
  (AFTER trigger) ├─ group_checkin_windows ──▶ checkin_reminder        │
                  ├─ group_invites         ──▶ group_invite            │
                  ├─ friendships INSERT    ──▶ friend_request          │
                  └─ friendships UPDATE    ──▶ friend_accepted         │
                                                                       │
                        ┌──────────────────────────────────────────────┤
                        ▼                                              ▼
              in-app list + badge                            push Edge Function
              (PostgREST, polled)                            (pg_cron, 1 min)
                                                                       │
                                                            ┌──────────┴──────────┐
                                                     NoopTransport          ApnsTransport
                                                     (today: no key)        (key present)
```

### Why triggers for all eight

Two of the eight have no RPC at all — `likes` and `comments` are direct client inserts under `likes_insert_self` / `comments_insert_self`, so those are triggers regardless. Given that, uniformity is worth more than locality:

- **No write path can forget to notify.** A notification is owed whenever the row exists, not whenever a particular function was called.
- **Zero churn on merged RPCs.** The alternative reopens five `SECURITY DEFINER` functions via drop/recreate, each a chance to regress an invariant that took a review cycle to establish.
- **Both friendship accept paths converge.** `respond_to_friend_request` accept and `send_friend_request`'s reciprocal auto-accept (including its `unique_violation` race handler) are all `UPDATE ... SET status='accepted'`. One `AFTER UPDATE` trigger covers all three sites.
- **Reminders become idempotent for free.** Hanging `checkin_reminder` off `group_checkin_windows` INSERT inherits the existing `unique(group_id, opens_at)` guard, and removes reminder logic from the cron function entirely.

---

## 3. Task 1 — the tag gate

### 3.1 The hole

`p_tag_user_ids` is unvalidated in **both** `create_encouragement` and `check_in`. Each filters only `t <> v_uid` before inserting `post_tags`. Any user id can be tagged, including users who cannot see the post.

Today this is inert: `pt_select_visible` is RLS-filtered, so the tagged user sees neither the post nor their own tag row — the row is an orphan. The moment a trigger fans notifications over `post_tags`, it becomes a notification (and later a push) for a post the recipient cannot open.

### 3.2 The rule

A tag is valid **iff the tagged user can see the post**, derived directly from `posts_select_visible`:

```sql
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
```

The destination-dependent behaviour the brief called for **falls out of the single rule** rather than being special-cased:

| Destination | Tagged user is… | Valid? |
|---|---|---|
| timeline (`shared_to_timeline`) | a friend of the author | ✅ |
| timeline | not a friend | ❌ |
| group only | a member of a target group | ✅ |
| group only | not a member | ❌ |
| timeline **and** group | a friend, not a member | ✅ (visible via the timeline clause) |
| timeline **and** group | a member, not a friend | ✅ (visible via the group clause) |
| check-in (always group-only, never timeline) | a member of a target group | ✅ |
| check-in | not a member | ❌ |

`check_in` passes `p_shared := false`, so its disjunction collapses to members-only. No second rule.

### 3.3 Enforcement posture

**Raise `42501` and reject the whole call.** Rationale:

- It matches the established posture — `create_encouragement` already raises when you target a group you aren't in, rather than silently dropping the group.
- The tag sheet only offers profiles the caller can already see, so a rejection means a client bug or a hostile client. Both are worth surfacing.
- It gives a hard, testable invariant for the notification trigger to rely on. A soft "drop the bad ones" rule would leave the trigger's correctness contingent on a filter elsewhere.

Accepted cost: a narrow race — being unfriended between the tag sheet loading and submission — bounces the post with an error. Acceptable; the author retries without the tag.

`t <> v_uid` self-tag stripping stays a silent filter, unchanged. It is not a visibility violation and changing it would churn existing tests for no gain.

Placement in both RPCs: **after** the existing group-membership assert (so "you can only post to groups you belong to" still wins for the more fundamental error) and **before** the `posts` insert (so a rejected call writes nothing).

### 3.4 Both legs must close

`pt_insert_owner` grants clients a direct `INSERT` on `post_tags`:

```sql
with check (exists (select 1 from posts p
                    where p.id = post_tags.post_id and p.author_id = auth.uid()))
```

It validates only that the caller authored the post — **the tagged user is entirely unchecked**. Fixing the two RPCs while leaving this policy would make the gate trivially bypassable: a client posts normally, then `POST /post_tags` with arbitrary `tagged_user_id` and gets the full notification fan-out.

Every service file was checked: no client path inserts into `post_tags` (it appears only as a read embed in `FeedService`) and no client path inserts into `posts` (only `.delete()` in `PostService`). Both policies are dead code.

**Drop `pt_insert_owner`.** Same treatment Plan 5 gave `pg_insert_owner_member`, for the same reason and under the same rule: *direct client writes to the post graph are not part of the design.*

**Drop `Users can create their own posts`** at the same time. This is the residual hole carried in memory since Plan 5's review — an unconstrained-on-`kind` INSERT policy letting a client fabricate `kind='check_in', shared_to_timeline=true` and get a fake "Checked in" capsule on their own timeline. Harmless today, but it contradicts the same rule and is one line to close while the migration is open.

---

## 4. Notification writes

### 4.1 Trigger map

| Type | Table | Event | Recipient | Actor | Also sets |
|---|---|---|---|---|---|
| `post_like` | `likes` | AFTER INSERT | `posts.author_id` | `likes.user_id` | `post_id` |
| `post_comment` | `comments` | AFTER INSERT | `posts.author_id` | `comments.author_id` | `post_id` |
| `post_tag` | `post_tags` | AFTER INSERT | `tagged_user_id` | `posts.author_id` | `post_id` |
| `member_checked_in` | `group_checkins` | AFTER INSERT | other `group_members` of `group_id` | `group_checkins.user_id` | `group_id`, `post_id` |
| `checkin_reminder` | `group_checkin_windows` | AFTER INSERT | all `group_members` of `group_id` | *null* | `group_id` |
| `group_invite` | `group_invites` | AFTER INSERT | `invitee_id` | `inviter_id` | `group_id` |
| `friend_request` | `friendships` | AFTER INSERT | `addressee_id` | `requester_id` | — |
| `friend_accepted` | `friendships` | AFTER UPDATE (→`accepted`) | `requester_id` | `addressee_id` | — |

`friend_accepted` fires on the transition only: `when (old.status is distinct from 'accepted' and new.status = 'accepted')`. This covers all three accept sites — `respond_to_friend_request`, `send_friend_request`'s reciprocal auto-accept, and its `unique_violation` race handler — because all three are `UPDATE ... SET status='accepted'`.

`checkin_reminder` has no actor (it is system-generated); `actor_id` is nullable, as declared in Plan 1.

Every trigger function is `SECURITY DEFINER`, `set search_path = public`, and lives in `private` (per the constraint that helper functions must not be PostgREST-reachable RPC endpoints). The triggers themselves reference `private.tg_notify_*`.

### 4.2 Self-notification guard

Every trigger skips `recipient_id = actor_id`. Liking your own post, commenting on your own post, or being the checking-in member of your own group must not notify you. Implemented as a `where` clause on the insert (not an early `return`), so the fan-out cases (`member_checked_in`, `checkin_reminder`) naturally exclude the actor while still notifying everyone else.

### 4.3 Dedupe

Three partial unique indexes, with all trigger inserts using `on conflict do nothing`:

```sql
create unique index notifications_like_uniq
  on public.notifications (recipient_id, actor_id, post_id) where type = 'post_like';
create unique index notifications_checkin_uniq
  on public.notifications (recipient_id, actor_id, post_id) where type = 'member_checked_in';
create unique index notifications_tag_uniq
  on public.notifications (recipient_id, post_id) where type = 'post_tag';
```

Reasoning per type:

- **`post_like`** — unlike then re-like is a normal gesture. Without dedupe it re-notifies each time.
- **`member_checked_in`** — a single `check_in` call fans one post to N groups, producing N `group_checkins` rows and therefore N trigger firings. A user who belongs to **two** of the targeted groups would receive two notifications for the same post. The index collapses them to one. The surviving row keeps whichever `group_id` won the race; the deep link targets the post, so this is immaterial.
- **`post_tag`** — `post_tags` has a `(post_id, tagged_user_id)` primary key, so duplicates are already structurally impossible. The index is belt-and-braces and costs nothing.
- **`post_comment`** — **deliberately not deduped.** Each comment is a distinct event; collapsing them would hide replies.
- **`checkin_reminder`** — idempotent via the pre-existing `unique(group_id, opens_at)` on `group_checkin_windows`. `on conflict do nothing` there means the trigger never fires twice for a window.
- **`group_invite`** — `invite_to_group` returns early on an existing pending invite, so no duplicate row is created. A declined-then-reinvited flow *should* produce a fresh notification, so no index.
- **`friend_request` / `friend_accepted`** — `friendships_unordered_uniq` guarantees at most one row per pair, and `friend_accepted` fires only on the transition.

### 4.4 Plan 5's handoff — verified safe, and regression-tested

Plan 5 changed `check_in` from catching `unique_violation` to `on conflict (group_id, user_id, window_id) do nothing` + `if not found`, **specifically** so that a Plan 6 `member_checked_in` trigger touching a different unique index could not be silently re-reported to the user as "already checked in".

The `member_checked_in` trigger does add exactly such an index (`notifications_checkin_uniq`, §4.3), and it will conflict in the normal two-group case. This is safe: `FOUND` is local to each plpgsql function invocation, and a trigger is a separate invocation, so the trigger's `on conflict do nothing` cannot be observed by `check_in`'s subsequent `if not found`.

Because the whole point of Plan 5's rewrite was to make this safe, it gets an **explicit regression test**, not a comment: a user checks in to two groups that share another member; assert the call succeeds, returns a post id, writes two `group_checkins` rows, and writes exactly **one** `member_checked_in` notification for the shared member — and specifically that it does **not** raise "already checked in".

### 4.5 Risk: trigger failure inside the cron swallow

`private.open_checkin_windows` wraps each group's window insert in `exception when others then raise warning`. A `checkin_reminder` trigger that raises would therefore roll back that group's window and be swallowed as a warning — the window silently never opens.

This is the same failure mode as the invalid-timezone Critical from Plan 5's final review, but §4.1 adds a **new way to reach it**. Two mitigations:

1. The `checkin_reminder` trigger is kept trivial — one `insert ... select` from `group_members`, no lookups that can fail, no dependency on the caller's identity.
2. §6 adds health monitoring, which is what makes the swallow tolerable rather than dangerous.

---

## 5. Lockdowns

Applying the project's RPC-only write posture to the two tables this plan activates.

### 5.1 `notifications` — read-only + a mark-read RPC

`notif_update_read` currently allows a recipient to `UPDATE` their **entire** notification row: they can rewrite `type`, repoint `post_id` at any post, forge `actor_id`, or clear `pushed_at` to force a re-push. Carried from Plan 1's review and deferred ever since.

- **Drop** `notif_update_read`.
- **Add** `mark_notifications_read(p_ids uuid[] default null)` — `SECURITY DEFINER`, sets `read_at = coalesce(read_at, now())` for `recipient_id = auth.uid()` and (`p_ids is null` **or** `id = any(p_ids)`). Null means mark-all-read, which the UI wants anyway. `coalesce` preserves the original read timestamp on re-marking.
- **Also** `revoke update on public.notifications from authenticated`, as defence in depth against a future policy being added carelessly.
- `notif_select_own` is unchanged and remains the only client read path.

Chosen over column-level grants (`grant update (read_at)`) because the RPC matches the posture used everywhere else in this codebase, gives bulk mark-all-read for free, and does not depend on a column grant that a later blanket `grant` would silently widen.

### 5.2 `device_tokens` — RPC-only, with cross-user token theft closed

`dt_all_own` is a `FOR ALL` policy — the broadest possible client write grant, exactly what the carried constraint forbids for this table.

- **Drop** `dt_all_own`; **add** `dt_select_own` (SELECT only).
- **Add** `register_device_token(p_token text, p_platform text default 'ios')` and `unregister_device_token(p_token text)`.

`register_device_token` must **first delete the token from any other user**:

```sql
delete from public.device_tokens where token = p_token and user_id <> v_uid;
insert into public.device_tokens (user_id, token, platform)
values (v_uid, p_token, coalesce(p_platform, 'ios'))
on conflict (user_id, token) do update set updated_at = now(), platform = excluded.platform;
```

APNs tokens are **device**-scoped, not user-scoped. The declared primary key `(user_id, token)` permits the same token to exist for two users — so on a shared device, or after logout and a different login, one person's notifications would push to another person's phone. The delete-first makes registration authoritative: a token belongs to whoever most recently registered it.

`unregister_device_token` is called on sign-out and deletes only `(auth.uid(), p_token)`.

### 5.3 `profiles_select_scoped` — the invite counterparty

`private.friendship_exists` is deliberately **status-agnostic** (any row, pending or accepted), which is why a pending requester's profile is already visible and `friend_request` notifications will render a name.

There is no equivalent for invites. `private.shares_group_with` requires actual `group_members` rows, so **an inviter's profile is invisible until the invite is accepted**. Consequences:

- Plan 4's existing incoming-invite screen renders a nameless row (`GroupInviteRow.inviter` decodes to `nil`) — a latent blemish this plan surfaces.
- A `group_invite` notification would say nothing at all about who invited you, making it unactionable.

Add a symmetric helper and a clause to the policy — scoped to **pending** invites only:

```sql
create or replace function private.invite_counterparty(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.group_invites
    where status = 'pending'
      and ((inviter_id = a and invitee_id = b) or (inviter_id = b and invitee_id = a))
  );
$$;
```

**The `pending` filter is required, and this is where the analogy to `friendship_exists` breaks.** `friendship_exists` can afford to be status-agnostic because `respond_to_friend_request`'s decline path **deletes** the row — a declined request stops granting visibility on its own. `respond_to_invite`'s decline path only sets `status='declined'` and **keeps the row forever**, with no expiry. A status-agnostic check would therefore let a single declined invite grant both parties permanent access to each other's profile.

With the filter, all three states behave: **pending** → visible (which is what the invite screen and the `group_invite` notification need); **declined** → hidden; **accepted** → still visible, now via `shares_group_with`, which `respond_to_invite` populates in the same transaction, so there is no gap.

### 5.4 PostgREST embed FK

`notifications.actor_id` references `auth.users(id)`, which PostgREST cannot embed a `profiles` row through. Add a redundant FK `notifications.actor_id → profiles(id)`, the same technique as Plan 2's `20260716010400_profile_fks.sql`. `group_id → groups` and `post_id → posts` are already real FKs and embed directly.

---

## 6. Cron monitoring — in scope

**Decision: in scope, deliberately minimal.** Stated explicitly rather than left to drift.

The rationale is not that the gap is new — it is that §4.1 makes it **worse**. `private.open_checkin_windows` swallows per-group failures as warnings, and this plan adds a trigger inside that swallow (§4.5). Adding a new silent-failure path to an unmonitored job while making check-ins load-bearing for notifications is not defensible.

Scope, tightly bounded:

- `private.checkin_cron_health()` returns one row: `last_success_at`, `minutes_since_success`, `failed_runs_last_hour`, `invalid_timezone_groups`, and **`missed_windows`**.
- A second `pg_cron` job, `checkin-cron-watchdog`, runs every 30 minutes and `raise warning`s with the specifics when `minutes_since_success > 30` or any count is non-zero.

**`missed_windows` is the field that actually closes the loop, and the other three cannot substitute for it.** The first three are *proxies* for health, and every one of them stays green in precisely the failure this section exists to catch: when the `checkin_reminder` trigger raises, `open_checkin_windows` swallows it inside its per-group loop and still returns normally, so pg_cron records the run as `succeeded`, `last_success_at` keeps advancing, `failed_runs_last_hour` stays 0, and the timezone is valid. That is a **permanent** false negative, not a delayed one — no amount of waiting surfaces it.

`missed_windows` instead asks the outcome question: for each active group, is a slot due and still un-opened? It is cause-agnostic, so it catches the swallowed trigger, an unparseable timezone, and any future skip path. A slot is only counted once it is more than 20 minutes overdue, since the opener runs every 15 and normal lag must not read as failure.

By contrast, a *total* opener outage is caught by `minutes_since_success` with a worst case of roughly 60 minutes' latency (up to 15 minutes of staleness before failure begins, plus one full 30-minute watchdog cycle). That latency is acceptable at this scale; a permanent blind spot would not have been.

**Explicitly not** in scope: a new `ops_alerts` table, an email/Slack integration, or generalising beyond this one job. The warning surfaces in Supabase logs and the health function is queryable on demand; it is documented as the hook to wire into a real alert channel when one exists. `groups.timezone` still has no `CHECK` constraint — impossible, since `CHECK` cannot subquery `pg_timezone_names` — so `create_group`'s validation plus this counter is the complete story.

---

## 7. Push

### 7.1 Edge Function `push`

Selects notifications where `pushed_at is null` **and** `created_at > now() - interval '1 day'` (served by the existing partial index `notifications_unpushed_idx`), groups by `recipient_id`, joins `device_tokens`, and dispatches through a transport.

Invoked by a `pg_cron` job every minute via `net.http_post`, authenticating with the service-role key read from Vault. `verify_jwt` stays **on**.

Payload per notification: an APNs `alert` with title/body composed server-side from the type + actor username + group name, plus a `data` object carrying `{type, notification_id, post_id, group_id}` for deep-link routing.

### 7.2 The transport seam

```ts
interface PushTransport {
  readonly name: string;
  send(token: string, payload: ApnsPayload): Promise<SendResult>;
}
type SendResult = { ok: true } | { ok: false; retryable: boolean; unregistered: boolean };
```

Selected at boot by the presence of `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`:

- **`ApnsTransport`** — ES256-signs a JWT from the `.p8`, HTTP/2 to `api.push.apple.com`, caches the JWT for its ~50 min validity. `410 Unregistered` and `400 BadDeviceToken` delete the token row; `429`/`5xx` are retryable and leave `pushed_at` null.
- **`NoopTransport`** — today's transport.

### 7.3 `NoopTransport` must not stamp `pushed_at`

This is the correctness point of the whole deferral. `NoopTransport` short-circuits before any per-notification work and returns `{transport: "noop", pending: N}`, leaving rows **genuinely unpushed**.

If it stamped `pushed_at`, then on the day an APNs key arrives every accumulated notification would already be marked delivered, and the first real push would be for whatever happened next — with no way to tell what was silently dropped. Leaving them unpushed means enabling APNs is one secret plus one deploy, with no backlog reconciliation and no schema or Swift change.

The unbounded-backlog concern is handled by the 1-day selection window: rows age out of the query naturally rather than being mutated.

### 7.4 Local check-in reminders

While APNs is unavailable, check-in reminders are delivered on-device via `UNUserNotificationCenter`. `FellowshipGroup` already carries `checkinCadence`, `checkinTime`, `checkinWeekday`, and `timezone`, so the next occurrences are computable client-side with `UNCalendarNotificationTrigger`.

- Scheduling is refreshed whenever the group list loads, and is idempotent by request identifier (`checkin-<groupID>`).
- Groups with `cadence == .none` are skipped and any stale request removed.
- Capped at iOS's 64-pending-request limit, prioritising soonest-first.
- The date computation is a **pure function** (`cadence, time, weekday, timezone, now → [Date]`), unit-tested across timezones and DST, mirroring how Plan 5 tested `due_slot_for`.

Authorization is requested at the point of value — the first time the Notifications tab or a check-in target is shown — not at launch.

---

## 8. iOS layer

### 8.1 Seam

Following the per-service protocol convention in `Services/SocialServicing.swift`:

```swift
protocol NotificationServicing: Sendable {
    func fetchNotifications(before: Date?, limit: Int) async throws -> [NotificationItem]
    func unreadCount() async throws -> Int
    func markRead(ids: [UUID]?) async throws          // nil = mark all
    func registerDeviceToken(_ token: String) async throws
    func unregisterDeviceToken(_ token: String) async throws
}
```

`FakeSocialServices.swift` gains a `FakeNotificationService` — **additive only**, per the standing constraint.

### 8.2 DTO

`NotificationItem` decodes the row plus embedded `actor: Profile?`, `group: FellowshipGroup?`, `post: PostSummary?`. `PostSummary` is a **new** lightweight DTO introduced here (`id`, `kind`, `title`) — deliberately not `FeedItem`, which carries attachments, counts, and an author embed that a notification row neither needs nor can always see. **The actor profile is optional and must degrade gracefully** — RLS can legitimately hide it (a group co-member who left, an actor whose only link was a since-deleted post). Rendering falls back to type-appropriate neutral copy ("Someone liked your post") rather than a blank row.

`AppNotification` and `DeviceToken` already exist in `Models/Models.swift` from Plan 1 and are reused, not redefined.

### 8.3 Views

A fifth **Notifications** tab in `RootTabView` with `.badge(vm.unreadCount)` — five tabs still fit before SwiftUI collapses to "More". `RootTabView`'s existing comment already anticipates this ("Plan 6 adds Notifications").

Rows are grouped by day, show actor avatar + composed copy + relative timestamp, and unread rows carry a tint. Opening the tab marks visible rows read via `markRead(ids:)`; a toolbar action marks all read via `markRead(nil)`.

### 8.4 Deep links

A `NotificationDestination` enum (`.post(UUID)`, `.group(UUID)`, `.invites`, `.friends`) resolved from `(type, post_id, group_id)` by a **pure mapping function**, unit-tested independently of navigation. When APNs lands, the remote-tap handler resolves the same enum from the payload's `data` object — no new routing logic.

**Routing is tab-level, deliberately.** Tapping a row selects the owning tab via a `TabView(selection:)` binding. Screen-level deep links are **out of scope for this plan**, because the current navigation cannot express them:

- there is **no post-detail screen** at all — posts render as cells inside `TimelineView` / `GroupTimelineView`, so `.post` has no destination to push;
- `FriendsView` is a **sheet** driven by private `@State` in `ProfileView`, and `GroupTimelineView` is a `NavigationLink` inside `GroupsView`'s list, so neither is reachable without hoisting that state.

Delivering screen-level routing would mean refactoring three existing views' navigation — unrelated work that this milestone should not absorb. The enum is the seam: when a post-detail screen and hoisted navigation paths exist, only the router changes.

A destination that cannot be resolved at all (a check-in whose post was deleted and which carries no group) surfaces a non-fatal "That's no longer available" rather than selecting a tab that will show nothing.

### 8.5 Push registration

`registerForRemoteNotifications()` runs post-login; the delegate callback calls `registerDeviceToken`. Sign-out calls `unregisterDeviceToken`. Both are best-effort — a failure is logged and never blocks auth. Without a provisioning profile the simulator's registration callback fails; that is expected and must not surface an error to the user.

---

## 9. Testing

### 9.1 SQL

Per the carried DB-verification split: the subagent writes, commits, applies, and runs read-only checks; the controller runs `auth.users` fixture seed → assertions → teardown, with **all teardown assertions scoped to fixture ids** (the live DB holds production rows, so bare `count = 0` fails spuriously).

- **Tag gate matrix** — the eight rows of §3.2's table, against both `create_encouragement` and `check_in`.
- **Direct-insert lockdown** — a client `INSERT` into `post_tags` and into `posts` is rejected after the policies are dropped.
- **One test per trigger** — correct recipient, actor, and ancillary ids.
- **Self-notification** — liking/commenting on your own post, and checking in to your own group, notify nobody (and still notify the *other* members).
- **Dedupe** — relike produces one row; two comments produce two rows.
- **Plan 5 regression (§4.4)** — check in to two groups sharing a member: succeeds, two ledger rows, exactly one `member_checked_in`, no "already checked in".
- **`mark_notifications_read`** — scoped to the caller, null marks all, re-marking preserves the original timestamp, and a direct `UPDATE` is now refused.
- **`register_device_token`** — re-registering the same token under a second user moves it rather than duplicating.
- **`profiles_select_scoped`** — an invitee can read the inviter's profile; an unrelated third party still cannot.
- **`get_advisors type:"security"`** after every RLS/RPC migration — expect only the accepted definer-executable WARN per new public RPC, nothing else new.

### 9.2 Swift

Baseline is **101 tests / 18 suites green**. All additions are additive; no existing test is edited to make a change pass.

- `NotificationItem` decoding against captured PostgREST payloads, including the null-actor case.
- `NotificationsViewModel`: unread count, optimistic mark-read with rollback on failure, pagination.
- The local-reminder date computation across timezones and DST boundaries.
- The `NotificationDestination` mapping function over all eight types.

### 9.3 Manual

Automation cannot reach push delivery. A manual multi-device / multi-account E2E pass is recommended at the end: two accounts, one group, exercising like / comment / tag / check-in / invite / friend and confirming each lands in the other's list with correct copy and a working deep link. Real APNs delivery is untestable until a key exists — the simulator cannot receive remote push at all.

---

## 10. Migrations

Prefix `202607200*`, per the established sequence (P1 `202607150*` … P5 `202607190*`).

Migrations must be **applied** to project `jstdoizgosatitptyrdy`, not merely committed. Per the carried gotcha, `apply_migration` stamps wall-clock versions that differ from the hand-numbered filenames — so after the plan completes, diff the file list against `list_migrations` and confirm every live version has a committed file.

---

## 11. Risks

| Risk | Mitigation |
|---|---|
| A `checkin_reminder` trigger failure is swallowed by `open_checkin_windows`, silently losing windows (§4.5) | Trigger kept trivial; §6 watchdog detects the resulting gap |
| Notification volume in a large group — one check-in fans to every member | Acceptable at current scale; `notifications_recipient_idx` covers the read path. Revisit with per-type preferences if it bites |
| A tag-gate false rejection from a mid-compose unfriend bounces the post | Narrow race, clear error copy, author retries. Preferred over a soft invariant (§3.3) |
| Enabling APNs later reveals an untested transport | The seam is exercised by `NoopTransport` in the same code path; `ApnsTransport` is written now and reviewed, just never selected. Flagged for manual E2E when a key exists |
| Dropping `pt_insert_owner` / the `posts` INSERT policy breaks an unnoticed client path | Every service file was grepped; neither table is written directly. Covered by the full suite plus §9.1's lockdown tests |
