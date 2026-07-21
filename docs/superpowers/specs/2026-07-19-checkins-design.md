# BibleShare — Check-ins Design (Social Plan 5)

**Date:** 2026-07-19
**Status:** Approved (design), pending implementation plan
**Parent spec:** `docs/superpowers/specs/2026-07-15-groups-encouragements-checkins-design.md` (§3.3, §5, §6, Milestone 5). Where this doc and the parent disagree, this doc wins for Plan 5 scope.
**Builds on:** Plan 4 (Groups core, merged to `main` in PR #3). Branch `feat/social-core-05-checkins` off `main`.

---

## 1. Goal

Make group check-in schedules fire. A group with a cadence (`daily`/`weekly`, time, weekday, timezone — columns shipped dormant in Plan 4) gets **check-in windows** opened by a `pg_cron` job; members see which groups await a check-in (`active_checkin_targets`), and submit one check-in post that fans out to one or more groups' timelines and writes the accountability ledger (`group_checkins`). Also ships the deferred Plan-4 minors on the schedule/RPC surface and the create-group schedule picker UI.

Non-goals (later plans / never, do not build): **any notification rows** — no `checkin_reminder`, no `member_checked_in` (Plan 6 owns the notifications subsystem wholesale and will attach them via triggers, so Plan 5's RPCs stay unchanged); group schedule *editing* after creation; backfilling windows missed while cron was down; per-member timezones.

---

## 2. What already exists (do not rebuild)

- Tables `group_checkin_windows` (`unique(group_id, opens_at)`, index `gcw_group_opens_idx`) and `group_checkins` (PK `(group_id, user_id, window_id)`), with member-only SELECT RLS (`gcw_select_member`, `gc_select_member`) and **no** write policies — writes go through `SECURITY DEFINER` RPCs (Plan 1).
- `groups.checkin_cadence` / `checkin_time` / `checkin_weekday` / `timezone` columns with CHECK invariants; `create_group(p_name, p_description, p_cadence, p_time, p_weekday, p_timezone)` validates and stores them dormant (Plan 4).
- `posts.kind` (`'encouragement'|'check_in'`), CHECK `posts_checkin_not_timeline` (check-ins never on the personal timeline), `post_groups` targeting, `posts_select_visible` (group posts visible to members) (Plans 1–2).
- `create_encouragement(..., p_group_ids, ...)` with the membership guard + media-path guard (Plan 4) — the shape `check_in` mirrors.
- Swift: `PostKind.checkIn`, `CheckinWindow`, `GroupCheckin`, `CheckinCadence` models; `ComposeViewModel`/`ComposeEncouragementView` with group multi-select; `RootTabView` (Home/Groups/Profile) with a comment reserving the Check-in slot.
- `pg_cron` is available on the project (`default_version 1.6.4`) but **not yet installed**.

---

## 3. Resolved design decisions

1. **Window opener = most-recent-due-slot catch-up.** Every 15 min, for each group with `cadence<>'none'`, compute the most recent scheduled instant ≤ `now()` in the group's timezone and insert a window with `opens_at` = that exact instant, `on conflict do nothing` against `unique(group_id, opens_at)`. Self-healing after cron downtime (the next run opens the current slot); older missed slots are deliberately not backfilled — only the latest window can be active (§3.3: active = greatest `opens_at ≤ now()`), so backfill rows would be born closed. `opens_at` records the true scheduled instant, never the cron run time. (Rejected: fire-only-in-slot-window — a missed run loses the window forever; pre-generating future windows — more machinery, complicates everything downstream.)
2. **No notification writes in Plan 5** (carried constraint). The opener inserts windows only; `check_in` writes no `member_checked_in` rows. Plan 6 will add both via **triggers** on `group_checkin_windows` / `group_checkins` inserts — additive, no Plan-5 RPC changes.
3. **`check_in` asserts, then lets the PK backstop.** Per group: `private.is_group_member` (`42501`), active window exists (`22023 'no active check-in window'`), no ledger row (`22023 'already checked in'`); the ledger insert additionally wraps `unique_violation` into the same friendly `22023` (concurrent double-submit race).
4. **Check-in compose = one screen, mode-driven** (parent §7). `ComposeViewModel` gains `mode: ComposeMode { encouragement, checkIn }`; check-in mode swaps the group source to `active_checkin_targets`, makes the title optional, and drops the timeline toggle. No separate check-in compose screen.
5. **Check-in tab = pending list + compose.** A real tab between Groups and Profile showing the caller's open unanswered windows (`active_checkin_targets`) with a "Check in" button that presents the shared compose sheet in check-in mode; tab badge = pending count. Not an empty shell that only opens a sheet.
6. **Schedule picker sets the device timezone, read-only.** `CreateGroupView` gains cadence (None/Daily/Weekly segmented), time (`DatePicker`, `.hourAndMinute`) when cadence ≠ none, weekday (Sunday…Saturday → 0…6, `extract(dow)` convention) when weekly, and a read-only row showing `TimeZone.current.identifier`. The RPC accepts any IANA zone, so a future edit UI can change it.
7. **Deferred Plan-4 minors fold in here** (same RPC surface): (a) `create_group` guards `p_weekday between 0 and 6` with `22023` (currently a bad weekday hits the table CHECK `23514`); (b) `create_encouragement` normalizes `v_shared := coalesce(p_shared_to_timeline, true)` once and uses it for both the destination invariant and the insert — aligning to the declared default `true` (today the invariant coalesces to `false` while the insert coalesces to `true`; harmless only because the Swift client never sends null).
8. **Check-in posts get a "Checked in" capsule** on timelines (small visual kind marker on `PostCell` when `post.kind == .checkIn`); they already flow through `post_groups` and the existing feed embed.

---

## 4. Database

Three migrations, prefix `202607190*`. Every function is `SECURITY DEFINER` with `set search_path = public`; grants are `revoke … from public, anon; grant … to authenticated`. RLS helpers stay in `private`.

### 4.1 `20260719010000_group_schedule_guards.sql`

Both are `create or replace` (signatures unchanged, grants preserved):

- **`create_group`** — add after the existing schedule invariants:
  `if p_weekday is not null and p_weekday not between 0 and 6 then raise exception 'weekday must be between 0 and 6' using errcode = '22023'; end if;`
- **`create_encouragement`** — declare `v_shared boolean := coalesce(p_shared_to_timeline, true);` and use `v_shared` in both the destination invariant (`if not v_shared and coalesce(array_length(p_group_ids,1),0) = 0 then …`) and the `posts` insert.

### 4.2 `20260719010100_checkin_rpcs.sql`

**`check_in(p_group_ids uuid[], p_title text default null, p_body text default null, p_verses jsonb default '[]'::jsonb, p_media jsonb default '[]'::jsonb, p_tag_user_ids uuid[] default '{}'::uuid[]) returns uuid`**

- Require `auth.uid()` (`28000`).
- Distinct non-empty group ids: `v_groups := array(select distinct g from unnest(coalesce(p_group_ids,'{}')) g)`; empty ⇒ `22023 'a check-in needs at least one group'`.
- Per group `g`: `private.is_group_member(g, v_uid)` else `42501 'you can only check in to groups you belong to'`; resolve the active window (`select id from group_checkin_windows where group_id = g and opens_at <= now() order by opens_at desc limit 1`); none ⇒ `22023 'no active check-in window'`; existing ledger row `(g, v_uid, window)` ⇒ `22023 'already checked in'`. Collect `(g, window_id)` pairs.
- Media guard identical to `create_encouragement`'s (image path under `<uid>/…`, link must be `http(s)`) — `42501`.
- Insert one `posts` row: `kind='check_in'`, `title = nullif(btrim(coalesce(p_title,'')),'')` (nullable — no title CHECK on check-ins), `body` trimmed-or-null, `shared_to_timeline = false`.
- Insert `post_groups` per group (`on conflict do nothing`); insert `group_checkins (group_id, user_id, window_id, post_id)` per collected pair — wrapped in a `unique_violation` handler re-raising `22023 'already checked in'`.
- Insert `post_verses` / `post_media` / `post_tags` exactly as `create_encouragement` does (tags skip self, `on conflict do nothing`).
- Return the post id. **No notification rows.**

**`active_checkin_targets() returns table(group_id uuid, name text, window_id uuid)`**

`security definer stable set search_path = public`; requires auth (`28000`). Body: caller's groups (`group_members`) joined to each group's active window (greatest `opens_at <= now()`), `where not exists` a `group_checkins` row for `(group, caller, window)`.

Expected advisor diff: **+2** `authenticated_security_definer_function_executable` WARNs (`check_in`, `active_checkin_targets`). Nothing else new.

### 4.3 `20260719010200_window_opener_cron.sql`

- `create extension if not exists pg_cron;`
- **`private.due_slot_for(p_cadence text, p_time time, p_weekday int, p_timezone text, p_now timestamptz) returns timestamptz`** — `language plpgsql` (default volatility; deterministic in tests because `p_now` is passed explicitly):
  - `v_local := p_now at time zone p_timezone` (a `timestamp`).
  - daily: candidate = `v_local::date + p_time`; if candidate > v_local, candidate = `(v_local::date - 1) + p_time`.
  - weekly: `v_delta := (extract(dow from v_local::date)::int - p_weekday + 7) % 7`; candidate = `(v_local::date - v_delta) + p_time`; if candidate > v_local, candidate -= 7 days.
  - return `candidate at time zone p_timezone` (local timestamp → `timestamptz`).
  - DST caveat (parent §10): on spring-forward the local slot may not exist; Postgres resolves it via its zone rules, the `unique(group_id, opens_at)` guard absorbs dupes, and the next run self-corrects. Verified in the SQL suite with fixed `p_now` values across transition instants; a skipped/duplicated slot on transition night is accepted.
- **`private.open_checkin_windows(p_now timestamptz default now()) returns integer`** — for each group with `checkin_cadence <> 'none'`, insert `(group_id, opens_at = private.due_slot_for(...)) on conflict do nothing`; returns rows inserted. `p_now` is the fixed-timestamp test seam (parent §9). No grants to `authenticated` (cron-only); private schema keeps it off PostgREST.
- Schedule: unschedule-if-exists then `cron.schedule('open-checkin-windows', '*/15 * * * *', $$select private.open_checkin_windows();$$)`.

### 4.4 SQL verification discipline (carried)

Single `do $$ … raise exception 'FAIL…' $$;` assertion blocks (empty = pass); multi-user chains in one `begin;…rollback;` switching `request.jwt.claims`; fixture UUIDs differ in the first 12 hex digits; assert row counts for RLS-denied UPDATE/DELETE. The controller runs fixture-seeded suites directly (subagent `auth.users` writes were classifier-blocked in earlier plans under a different harness — confirm behavior in this harness before splitting). Suites: guards pair; `check_in` happy / multi-group fan-out / non-member `42501` / no-window / double-check-in / never-on-timeline / attachments; `active_checkin_targets` across window boundaries (before open, after open, after check-in, non-member); `due_slot_for` fixed-`p_now` matrix across timezones + DST + weekly weekday math; opener idempotency + catch-up.

---

## 5. Swift

**Models / DTOs**
- `CheckinTarget: Decodable` — `group_id`, `name`, `window_id` (the `active_checkin_targets` row).
- `CheckInParams: Encodable` — keys `p_group_ids` (lowercased UUID strings, same rationale as `CreateEncouragementParams`), `p_title`, `p_body`, `p_verses`, `p_media`, `p_tag_user_ids`.
- `CreateGroupParams` already carries `cadence`/`time`/`weekday`/`timezone` — the ViewModel now populates them; `time` encodes as `"HH:mm:ss"`.

**Service seams** (`Services/SocialServicing.swift`, additive fakes)
- `PostServicing.checkIn(_ params: CheckInParams) async throws -> UUID` → `rpc("check_in")`.
- `GroupServicing.fetchActiveCheckinTargets() async throws -> [CheckinTarget]` → `rpc("active_checkin_targets")`.
- `PostError.message(for:)` additions: `'no active check-in window'` → "That check-in window has closed."; `'already checked in'` → "You've already checked in there."; `'a check-in needs at least one group'` → "Choose at least one group."; `'weekday must be between 0 and 6'` → generic validation copy.

**ViewModels**
- `ComposeViewModel` — `enum ComposeMode { encouragement, checkIn }`; `init(mode:)` default `.encouragement`. Check-in mode: `checkinTargets: [CheckinTarget]` loaded via `loadCheckinTargets()` (non-fatal like `loadGroups`); `selectedGroupIDs` reused for target ids; `canSubmit` = `!selectedGroupIDs.isEmpty && !isSubmitting && pendingImages.count <= max` (no title requirement); `submit` routes to `posts.checkIn` with `sharedToTimeline` forced false. Encouragement mode unchanged.
- `CreateGroupViewModel` — `cadence: CheckinCadence = .none`, `checkinTime: Date`, `weekday: Int = 0`, `timezone = TimeZone.current.identifier`; `canSubmit` additionally requires a weekday only structurally (always set) — validation lives in the RPC as the backstop; builds `CreateGroupParams` mapping `checkinTime` → `"HH:mm:ss"` when cadence ≠ none (nil otherwise), weekday nil unless weekly.
- `CheckInViewModel` — `targets: [CheckinTarget]`, `isLoading`, `load()` (via `GroupServicing.fetchActiveCheckinTargets`), `pendingCount` for the tab badge; after a successful check-in, removes the submitted group ids from `targets` locally (the sheet callback also triggers a reload).

**Views** (Serene Light, existing `Theme`/`SereneControls`)
- `CheckInView` — new tab between Groups and Profile in `RootTabView` (`Label("Check-in", systemImage: "checkmark.circle")`, badge = pending count). Each pending-target row shows the group name with an "Awaiting your check-in" caption (`active_checkin_targets` deliberately doesn't return `opens_at` — no extra RPC). "Check in" button presents `ComposeEncouragementView` in check-in mode; empty state ("No open check-ins right now").
- `ComposeEncouragementView` — takes `mode`; check-in mode: title field caption "Title (optional)", placeholder "Share how you're doing…", hides the timeline toggle, lists `checkinTargets` (with an empty-targets message instead of the group picker), navigation title "New check-in".
- `CreateGroupView` — schedule section per decision 6.
- `PostCell` — "Checked in" capsule when `post.kind == .checkIn`.

**project.yml** — new files land in globbed dirs; no edit expected (verify with `make generate`).

---

## 6. Testing strategy

- **DB:** per §4.4 suites, applied via `apply_migration` to project `jstdoizgosatitptyrdy` and verified via `execute_sql`; `get_advisors type:"security"` diff = the two new accepted WARNs only.
- **iOS (TDD per task):** `CheckinTarget` decode; `CheckInParams` encoding (lowercased uuids, key names); `ComposeViewModel` check-in mode (no-title canSubmit, ≥1 target required, routes to checkIn, timeline forced off, targets load failure non-fatal); encouragement-mode regression (canSubmit still requires title+destination); `CreateGroupViewModel` schedule mapping (cadence none ⇒ nil time/weekday, weekly ⇒ weekday + `"HH:mm:ss"`, device tz); `CheckInViewModel` (load, empty state, local removal after submit). Full suite: `xcodebuild -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData test`.
- **Manual E2E recommendation:** two-account simulator pass — create a group with a daily schedule, force-run `select private.open_checkin_windows();`, confirm the second account sees the target, checks in, and the post lands on the group timeline only.

---

## 7. Constraints honored

RLS helpers in `private`; policies call `private.*` only. All writes via `SECURITY DEFINER` RPCs with `set search_path = public`; check-in tables keep SELECT-only RLS. No notification writes (Plan 6). `groups`-row model stays `FellowshipGroup`. XcodeGen via `project.yml` + `make generate`; never edit `.xcodeproj`; never `killall CoreSimulatorService`. Build/test destination `platform=iOS Simulator,name=iPhone 17`. Branch `feat/social-core-05-checkins` off `main`; never commit to `main`.
