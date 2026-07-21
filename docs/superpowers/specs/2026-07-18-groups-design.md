# BibleShare — Groups Core Design (Social Plan 4)

**Date:** 2026-07-18
**Status:** Approved (design), pending implementation plan
**Parent spec:** `docs/superpowers/specs/2026-07-15-groups-encouragements-checkins-design.md` (§3.2, §5, §7, Milestone 4). Where this doc and the parent disagree, this doc wins for Plan 4 scope.
**Builds on:** Plan 1 (schema/RLS/models, merged), Plan 2 (encouragements/feeds, merged), Plan 3 (friends, merged to `main`).

---

## 1. Goal

Ship groups end-to-end: a user creates a **group** (name, description, timezone; check-in schedule stored but dormant), invites others by exact `@username` (invite → accept/decline), sees their groups and each group's timeline, and posts an encouragement to one or more of their groups. Group posts become visible to co-members through the RLS already shipped in Plan 1; this plan adds the write path (RPCs), the compose targeting, the co-member profile-visibility clause, and the group UI.

Non-goals (later plans, do not build): check-ins firing / windows / `pg_cron` (Plan 5); notification rows/triggers/push (Plan 6); public/discoverable groups, join-by-link, roles beyond creator/member.

---

## 2. What already exists (do not rebuild)

- Tables `groups`, `group_members` (role `creator`/`member`), `group_invites` (Plan 1), with the schedule CHECK constraints (cadence≠none needs `checkin_time`; weekly needs `checkin_weekday`) and the partial unique index `group_invites_unique_pending` on `(group_id, invitee_id) where status='pending'`.
- `post_groups` targeting table with RLS: `pg_select_visible` (SELECT via a visible parent post) and `pg_insert_owner_member` (INSERT requires author owns the post AND `private.is_group_member`).
- `posts_select_visible` already includes `private.post_in_visible_group(id, uid)`, so a group post is visible to members the instant a `post_groups` row + membership exist.
- SELECT policies `groups_select_member_or_invited`, `gm_select_same_group`, `gi_select_parties`; helper `private.is_group_member(g, u)`. **No** INSERT/UPDATE/DELETE policies on `groups`/`group_members`/`group_invites` — writes go through `SECURITY DEFINER` RPCs, which do not exist yet.
- Swift models `FellowshipGroup`, `GroupMember`, `GroupInvite`, `InviteStatus`, `CheckinCadence` in `Models/Models.swift`. The `groups`-row model is `FellowshipGroup` (never `Group` — SwiftUI clash).
- `create_encouragement(p_title, p_body, p_shared_to_timeline, p_verses, p_media, p_tag_user_ids)` — timeline-only, no group param.
- `ComposeViewModel` / `ComposeEncouragementView` (Plan 2) — extend, don't rewrite.
- `ProfileService.resolveExact` → `find_profile_by_username` RPC (Plan 3) — the exact-username discovery path.
- `profiles_select_scoped` (Plan 3): SELECT to self / any-friendship-party / tagged-on-a-visible-post / commenter-on-a-visible-post. **No co-member clause yet.**

---

## 3. Resolved design decisions

1. **Compose → groups:** extend `create_encouragement` with a `p_group_ids uuid[]` parameter (one atomic write) rather than a second RPC. Because the RPC is `SECURITY DEFINER` and bypasses RLS, it **must itself** assert `private.is_group_member` for every target group before inserting `post_groups` — the `pg_insert_owner_member` table policy cannot guard the definer path. An encouragement requires **at least one destination** (personal timeline or ≥1 group), enforced both in the RPC and in `ComposeViewModel.canSubmit`.
2. **`profiles` co-member visibility:** add `private.shares_group_with(a, b)` (`SECURITY DEFINER`, `stable`, `search_path=public`; a self-join on `group_members`) and OR it into `profiles_select_scoped`. This grain covers group-post authors *and* the profiles rendered in member lists / invite screens. Re-run the Plan 3 visibility matrix with a co-member row.
3. **Notifications:** hold the no-notification-writes line (consistent with Plans 2–3). `invite_to_group` writes **no** `group_invite` notification row; incoming invites surface via a `group_invites` query. Plan 6 owns the notifications subsystem wholesale.
4. **Check-in schedule:** `create_group` accepts the full schedule signature (`p_cadence`, `p_time`, `p_weekday`, `p_timezone`), validates the CHECK invariants server-side, and stores the values **dormant** (nothing fires until Plan 5). The create-group **UI** sets `cadence='none'` and shows **no** schedule picker — that UI lands in Plan 5 where it is meaningful.
5. **Entry point / navigation:** rework the ad-hoc `HStack` tab shell in `HomeView` into a real `TabView` with three **live** tabs — **Home**, **Groups**, **Profile** (hosting the existing Friends sheet + sign-out). No inert placeholder tabs; Plans 5–6 insert Check-in and Notifications.
6. **Group compose entry:** the shared `ComposeEncouragementView` gains a group multi-select, **and** each `GroupTimelineView` has a "Post here" button that opens the same sheet pre-selecting that group.

---

## 4. Database

Four migrations, prefix `202607180*`, mirroring Plan 3's file shape. Every function is `SECURITY DEFINER` with `set search_path = public`. RLS helpers live in `private`; policies call `private.*` only.

### 4.1 `20260718010000_group_embed_fks.sql`
Add FKs to `public.profiles(id)` (alongside the existing `auth.users` FKs) so PostgREST can embed profiles:
- `group_members.user_id → profiles(id)` (member lists)
- `group_invites.inviter_id → profiles(id)`, `group_invites.invitee_id → profiles(id)` (invite rows)
- `groups.creator_id → profiles(id)` (optional creator embed)

All 1:1-satisfiable (`handle_new_user` guarantees one profile per user). `notify pgrst, 'reload schema'`.

### 4.2 `20260718010100_group_rpcs.sql`

**`create_group(p_name text, p_description text default null, p_cadence text default 'none', p_time time default null, p_weekday int default null, p_timezone text default 'America/New_York') → public.groups`**
- Require `auth.uid()` (`28000`).
- Validate `char_length(btrim(p_name)) between 1 and 60` (`22023`).
- Re-assert schedule invariants for clear errors: cadence ∈ {none,daily,weekly}; cadence≠none ⇒ time not null; weekly ⇒ weekday not null (`22023`).
- Insert the `groups` row (`creator_id = auth.uid()`) + the creator's `group_members` row (`role='creator'`), atomic. Return the group.

**`invite_to_group(p_group_id uuid, p_invitee_username text) → public.group_invites`**
- Require `auth.uid()`.
- **Creator-only:** reject unless caller has a `group_members` row with `role='creator'` for the group (`42501`).
- Resolve username exactly, case-insensitive; not found ⇒ `22023`.
- Reject inviting self / an existing member (`22023`).
- Idempotent: if a pending invite for `(group_id, invitee_id)` exists, return it; wrap the insert in a `unique_violation` handler that returns the existing pending row (race on the partial pending index). A prior **declined** row does not block a re-invite (partial index is pending-only).

**`respond_to_invite(p_invite_id uuid, p_accept boolean) → void`**
- Require `auth.uid()`.
- **Invitee-only:** the UPDATE is scoped `id = p_invite_id and invitee_id = auth.uid() and status='pending'`.
- Accept: set `status='accepted', responded_at=now()`; if no row updated ⇒ `22023`; insert the `member` `group_members` row (`on conflict do nothing`).
- Decline: set `status='declined', responded_at=now()`; idempotent (0 rows = no-op, no error).

Grants: `revoke execute … from public, anon; grant execute … to authenticated` for all three.

### 4.3 `20260718010200_encouragement_group_targeting.sql`
Drop the 6-arg `create_encouragement` and recreate with `p_group_ids uuid[] default '{}'` inserted after `p_shared_to_timeline` (matches parent spec §5 order: title, body, shared_to_timeline, group_ids, verses, media, tag_user_ids). Preserve the existing title-required, author-forcing, and foreign-folder-image guards. Add:
- **Membership guard (defense-in-depth):** reject if any target fails `private.is_group_member(g, auth.uid())` (`42501`).
- **Destination invariant:** reject if `shared_to_timeline=false` AND `p_group_ids` empty (`22023`).
- Insert `post_groups (post_id, group_id)` for each validated group (`on conflict do nothing`).

`notify pgrst, 'reload schema'`. Re-apply grants (drop/recreate resets them).

### 4.4 `20260718010300_profiles_group_visibility.sql`
```
private.shares_group_with(a uuid, b uuid) returns boolean
  language sql security definer stable set search_path = public
  -- exists a group_members m1 (user=a) joined to m2 (user=b) on group_id
```
Grant to `authenticated`. Drop/recreate `profiles_select_scoped` adding `or private.shares_group_with(id, (select auth.uid()))` to the existing self / `friendship_exists` / tagged / commenter clauses.

### 4.5 Security advisors
Expected diff vs. the current baseline: exactly **3 new** `authenticated_security_definer_function_executable` WARNs — `create_group`, `invite_to_group`, `respond_to_invite`. `create_encouragement` keeps its single existing WARN across the drop/recreate. `private.shares_group_with` is private-schema and does not trip the advisor (same as `private.friendship_exists` in Plan 3). No `function_search_path_mutable`, no RLS lints, nothing else new.

### 4.6 SQL verification discipline (carried from Plan 3)
- Encode assertions as a single `do $$ … if <bad> then raise exception 'FAIL…'; end if; $$;` block (empty result = pass; `execute_sql` returns only the last statement's result).
- Any check chaining dependent writes across users (invite → accept) runs in **one** `begin;…rollback;`, switching `request.jwt.claims` via `perform set_config(...)` between users.
- Fixture UUIDs differ in their first 12 hex digits (`handle_new_user` derives the auto-username from that prefix).
- A direct UPDATE/DELETE denied by RLS affects 0 rows without error (only INSERT raises `42501`) — assert row counts for UPDATE/DELETE.
- Full profile visibility matrix re-run: self, friend, pending-friendship party, tagged-on-visible-post, commenter-on-visible-post, **co-member (new)**, stranger.

---

## 5. Swift

**Models** — read DTOs appended to `Models/FeedModels.swift`:
- `GroupListItem` — a `FellowshipGroup`'s fields plus the caller's `role` and a member count (from `group_members(count)`).
- `GroupMemberRow` — `user_id`, `role`, embedded `profile` (member list).
- `GroupInviteRow` — the invite row plus embedded `group`, `inviter`, `invitee` profiles (incoming/outgoing invites).

Write DTOs in `Models/ComposeParams.swift`:
- `CreateGroupParams` (Encodable; keys `p_name`/`p_description`/`p_cadence`/`p_time`/`p_weekday`/`p_timezone`).
- Add `groupIDs → "p_group_ids"` to `CreateEncouragementParams`.

**Service seam** — `Services/GroupService.swift` (live) behind a `GroupServicing` protocol in `Services/SocialServicing.swift`:
```
createGroup(_:) async throws -> FellowshipGroup
fetchMyGroups(userID:) async throws -> [GroupListItem]
fetchMembers(groupID:) async throws -> [GroupMemberRow]
fetchGroupTimeline(groupID:before:limit:) async throws -> [FeedItem]   // via post_groups -> posts, reusing the feed embed shape
invite(groupID:username:) async throws -> GroupInvite
fetchIncomingInvites(userID:) async throws -> [GroupInviteRow]
respondToInvite(inviteID:accept:) async throws
```
Add group error copy to `PostError.message(for:)` (username not found, already a member, only the group creator can invite, post needs a destination). `FakeGroupService` added **additively** to `BibleShareTests/FakeSocialServices.swift`.

**ViewModels** (`@Observable`):
- `GroupListViewModel` — `myGroups`, `incomingInvites`, `load`, `createGroup`, `respondToInvite`.
- `GroupTimelineViewModel` — group feed (reusing `PostService.setLike` + `FeedService.likedPostIDs` for like handling), `members`, creator-only `invite`.
- `CreateGroupViewModel` — name (1–60) / description validation, submit.
- `ComposeViewModel` — add `myGroups: [GroupListItem]` + `selectedGroupIDs: Set<UUID>`, load groups on appear, thread `p_group_ids`, and make `canSubmit` require title AND ≥1 destination (timeline or a group).

**Views** — Serene Light via existing `Theme` / `SereneControls`:
- `RootTabView` — real `TabView`: **Home** (existing timeline + compose sheet + header), **Groups**, **Profile** (hosts `FriendsView` + the sign-out menu, which moves out of the Home header). `HomeView`'s current body becomes the Home tab content.
- `GroupsView` — my groups list + incoming invites + "Create group"; `NavigationStack` → `GroupTimelineView`.
- `GroupTimelineView` — the group's post feed (reusing `PostCell`), member list, creator-only invite entry (`@username`), and a "Post here" button opening `ComposeEncouragementView` pre-selecting the group.
- `CreateGroupView` — name (`SereneTextField(autocapitalization: .sentences)`), description, timezone; **no** schedule picker.
- Invite entry + incoming-invite accept/decline UI.
- `ComposeEncouragementView` — add a group multi-select section; keep the "Show on my timeline" toggle.

---

## 6. Testing strategy

- **DB/RLS:** per-migration SQL assertion suites (impersonation + `do $$…$$` blocks): `create_group` creates group + creator membership; `invite_to_group` creator-only, self/member/idempotent/re-invite-after-decline; `respond_to_invite` invitee-only accept adds membership, decline sets status, both idempotent (invite→accept in one transaction); `create_encouragement` group-membership guard + destination invariant + `post_groups` fan-out + non-member rejection; `profiles_select_scoped` co-member visibility matrix; defense-in-depth direct-write denial on the group tables; advisor diff.
- **Swift:** `CreateGroupParams` + group-DTO decoding tests; `GroupListViewModel` (load, create, respond); `GroupTimelineViewModel` (feed + like handling); `CreateGroupViewModel` (validation); `ComposeViewModel` (destination invariant, group targeting in params). TDD, commit per task, build/test on `platform=iOS Simulator,name=iPhone 17`.

---

## 7. Constraints honored

RLS helpers in `private`; policies call `private.*` only. Supabase project `jstdoizgosatitptyrdy`; migrations via `apply_migration` (committed first) + `execute_sql` verification + `get_advisors type:"security"`. Every definer function sets `search_path = public`. XcodeGen — edit `project.yml`, `make generate` after; never edit `.xcodeproj`, never `killall CoreSimulatorService`. Protocol-seam pattern for `GroupService`; `FakeSocialServices` changes additive. Branch `feat/social-core-04-groups` off `main`; never commit to `main`.
