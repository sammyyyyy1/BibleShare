# BibleShare — Friends Design (Social Core, Milestone 3)

**Date:** 2026-07-17
**Status:** Approved (design), pending implementation plan
**Parent spec:** `docs/superpowers/specs/2026-07-15-groups-encouragements-checkins-design.md` (§5, §7; this is Milestone 3 of §8)
**Builds on (merged):**
- `docs/superpowers/plans/2026-07-15-social-core-01-schema-rls-models.md` (schema/RLS/models)
- `docs/superpowers/plans/2026-07-16-social-core-02-encouragements-feeds.md` (encouragements, timeline, likes, comments, tags)

---

## 1. Goal & scope

Ship symmetric friendship end-to-end: request a friend by exact `@username`, accept/decline incoming requests, see your friends and pending requests, and see friends' personal-timeline encouragements on Home alongside your own. Tighten `profiles` visibility so the world-readable enumeration hole is closed now that a real friends model gives us a principled visibility rule.

**In scope**
- `send_friend_request(addressee_username)` and `respond_to_friend_request(requester_id, accept)` RPCs, plus a `find_profile_by_username` discovery RPC.
- A structural dedupe guarantee for reciprocal requests.
- Friends list UI (incoming requests, outgoing/sent, accepted) + an add-friend entry point.
- Home/timeline feed extended to surface friends' `shared_to_timeline` posts via RLS (drop the client-side author filter).
- `profiles` SELECT locked down from world-readable to a connection/visible-content rule; exact-username discovery routed through an RPC.

**Non-goals (later plans, same discipline held as Plan 2)**
- Groups (Plan 4), check-ins (Plan 5), notifications/push (Plan 6). **No notification writes** in this plan — no `friend_request` / `friend_accepted` rows or triggers, even though the `notifications` type CHECK already allows them.
- Friend-profile / friend-timeline browsing screens.
- Tab-bar rework (spec §7's full tab set arrives with later milestones); Friends is reached from the existing shell.
- Server-side friend search (the friends-list filter is client-side only).

---

## 2. Carried-forward constraints resolved here

Two items prior reviews explicitly deferred to Plan 3, and the decisions taken:

1. **Reciprocal-duplicate friendship rows.** The PK `(requester_id, addressee_id)` does not prevent `A→B` and `B→A` existing as two separate pending rows. **Decision:** add a unique index on the *unordered* pair, so the database structurally guarantees at most one friendship row per pair of users, in either direction; the RPC additionally auto-accepts a reciprocal pending request. (§4.2, §4.3)

2. **`profiles` world-readable.** `SELECT using (true)` lets any signed-in client enumerate every username/display-name/bio via a `like` filter. **Decision:** lock the table down to a connection/visible-content rule and move exact-username discovery to a `SECURITY DEFINER` RPC — no enumeration surface remains. (§4.5)

---

## 3. Current-state grounding (verified against the live DB & shipped code)

- RLS helpers live in the **`private`** schema: `private.is_friend(a,b)`, `private.is_group_member(g,u)`, `private.post_in_visible_group(...)`.
- `friendships` has exactly one policy — `fr_select_parties` (SELECT, visible to the two parties). **No** INSERT/UPDATE/DELETE policy, so RLS default-deny blocks all direct writes; RPCs are the only write path.
- `profiles` policies: `Profiles are viewable by everyone` (SELECT `using (true)`), self-scoped INSERT/UPDATE. Onboarding does **not** depend on world-read: `is_username_available` is already an RPC; `fetchProfile` / `setUsername` are self-scoped. The only readers of *other* users' profile rows are `ProfileService.resolveExact` (tag picker) and the feed's `post_tags(...profiles(*))` / `comments(...author:profiles(*))` embeds.
- Embed-enabling FKs to `profiles` exist only for `posts`, `post_tags`, `comments` (added by Plan 2). `friendships` references `auth.users`, so embedding profiles from it requires new FKs.
- `FeedService.fetchTimeline` still carries `.eq("author_id", authorID)` with a `// Plan 3 drops this filter` comment; `FeedServicing` has a single consumer, `TimelineViewModel`.
- UI shell: `HomeView` is the whole app — an inline bottom bar with `house` (active), `magnifyingglass` (dead), `square.and.pencil` (compose), `person` (dead). No `NavigationStack` in Home. The `person` icon is the Friends entry point.

---

## 4. Database design (migrations prefixed `202607170*`, applied via Supabase MCP `apply_migration`)

### 4.1 Embed FKs (additive)

Add, mirroring Plan 2's pattern, so the friends-list query can embed both parties:

```sql
alter table public.friendships
  add constraint friendships_requester_id_profiles_fkey
  foreign key (requester_id) references public.profiles(id) on delete cascade;
alter table public.friendships
  add constraint friendships_addressee_id_profiles_fkey
  foreign key (addressee_id) references public.profiles(id) on delete cascade;
```

`profiles.id` is 1:1 with `auth.users.id`, so both FKs are always satisfiable. These are *additional* to the existing `auth.users` FKs.

### 4.2 Dedupe guard (unordered unique index)

```sql
create unique index friendships_unordered_uniq on public.friendships
  (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
```

At most one friendship row per pair of users, regardless of direction. The directional PK `(requester_id, addressee_id)` is retained — it carries the who-requested-whom semantics the incoming/outgoing UI and accept/decline direction need. (Prod `friendships` is empty, so the index builds without violations.)

### 4.3 `send_friend_request`

`SECURITY DEFINER`, `set search_path = public`. Resolves the username internally (bypassing the profiles lockdown), then:

- reject if unauthenticated / self / username not found;
- reject if an `accepted` row already exists in either direction ("already friends");
- **reciprocal auto-accept:** if a `them→me` `pending` row exists, `UPDATE` it to `accepted` (`responded_at = now()`) and return it — never creating a second row;
- **idempotent:** if my own `me→them` `pending` row already exists, return it unchanged;
- else `INSERT` a fresh `me→them` `pending` row.

Concurrency: if a reciprocal `them→me` row is inserted between the reciprocal check and the fresh insert, the insert trips `friendships_unordered_uniq`; the RPC catches `unique_violation` and retries the reciprocal-accept path, so the outcome is still a single accepted row. Returns the resulting `friendships` row (status distinguishes "request sent" from "auto-accepted").

### 4.4 `respond_to_friend_request`

`SECURITY DEFINER`, `set search_path = public`. Scoped by `addressee_id = auth.uid()` so only the recipient can act:

- `accept = true`: `UPDATE … set status='accepted', responded_at=now() where requester_id=$1 and addressee_id=auth.uid() and status='pending'`; raise if no row matched.
- `accept = false`: `DELETE … where requester_id=$1 and addressee_id=auth.uid() and status='pending'` (idempotent — declining an already-gone request is a no-op).

### 4.5 `profiles` lockdown + discovery RPC

New definer helper and replacement policy:

```sql
create or replace function private.friendship_exists(a uuid, b uuid)
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (
    select 1 from public.friendships
    where (requester_id = a and addressee_id = b)
       or (requester_id = b and addressee_id = a)
  );
$$;  -- any status, either direction: covers accepted friends AND pending parties

drop policy if exists "Profiles are viewable by everyone" on public.profiles;
create policy profiles_select_scoped on public.profiles for select using (
  id = (select auth.uid())
  or private.friendship_exists(id, (select auth.uid()))
  or exists (select 1 from public.post_tags pt
             where pt.tagged_user_id = profiles.id
               and exists (select 1 from public.posts p where p.id = pt.post_id))
  or exists (select 1 from public.comments c
             where c.author_id = profiles.id
               and exists (select 1 from public.posts p where p.id = c.post_id))
);
```

Rationale for the two content clauses: without them, locking down `profiles` would regress Plan 2 rendering. A post's author is always self or a friend (covered), but **tagged users** and **comment authors** on a post I can legitimately see may be the *post author's* friends rather than mine (e.g. another friend of the author comments on a shared-to-timeline post I can see). The `post_tags` and `comments` clauses expose exactly those profiles and no more — each inner `posts` EXISTS runs as the invoker under `posts_select_visible`, so visibility tracks the post, reopening no enumeration surface. `friendship_exists` is `SECURITY DEFINER` to avoid RLS-on-RLS recursion against `friendships`. Likes need no clause — the feed shows like *counts*, not liker profiles.

Discovery RPC (the only path to a non-connected user's profile; exact match, no enumeration):

```sql
create or replace function public.find_profile_by_username(p_username text)
returns setof public.profiles language sql security definer stable
set search_path = public as $$
  select * from public.profiles
  where lower(username) = lower(btrim(p_username))
  limit 1;
$$;
```

All three public RPCs: `revoke execute … from public, anon; grant execute … to authenticated;`.

### 4.6 Defense-in-depth

`friendships` remains without any write policy, so every direct client `INSERT`/`UPDATE`/`DELETE` is denied by RLS default-deny — the `SECURITY DEFINER` RPCs cannot be bypassed by reaching the table directly. This is asserted by a test that attempts direct writes as an authenticated role and expects failure. (The class of bug Plan 2 fixed twice: an RPC guard must not be the *only* enforcement.)

---

## 5. Feed change

Drop `.eq("author_id", …)` from `FeedService.fetchTimeline`. With the filter gone, `posts_select_visible` (`author_id = me OR (shared_to_timeline AND private.is_friend(author, me)) OR visible-group`) surfaces my own timeline posts **and** friends' `shared_to_timeline` encouragements — exactly the Home feed. The remaining `.eq("kind","encouragement").eq("shared_to_timeline", true)` filters are content filters, not visibility filters.

`fetchTimeline`'s signature becomes `fetchTimeline(before:limit:)` (the `authorID` argument no longer filters anything). This ripples only to `FeedServicing`, `TimelineViewModel`, and the `FakeFeedService`/`TimelineViewModelTests` pair — `FeedServicing` has a single consumer. `TimelineViewModel` keeps `userID` for `isMine` (delete affordance) and the `likedPostIDs` companion query. A test asserts a friend's post appears and a stranger's does not, proving **RLS** — not a client filter — gates visibility.

---

## 6. iOS design

### 6.1 DTO

`FriendEdge: Decodable` — decodes a `friendships` row plus both embedded profiles:
`requesterID, addresseeID, status: FriendStatus, createdAt, respondedAt?, requester: Profile?, addressee: Profile?`, with `func otherParty(myID: UUID) -> Profile?`. (`FriendStatus` already exists from Plan 1.) Fetched via
`friendships?select=requester_id,addressee_id,status,created_at,responded_at,requester:profiles!friendships_requester_id_profiles_fkey(*),addressee:profiles!friendships_addressee_id_profiles_fkey(*)` — `fr_select_parties` already limits rows to mine.

### 6.2 Services (protocol-seamed, mirroring existing conventions)

- New `FriendServicing: Sendable`:
  - `sendRequest(username: String) async throws -> Friendship`
  - `respond(requesterID: UUID, accept: Bool) async throws`
  - `fetchEdges(userID: UUID) async throws -> [FriendEdge]`
  - Live `FriendService` (with `static let shared`) over `SupabaseService.shared.client` (`rpc` + `from("friendships").select(...)`).
- `ProfileService.resolveExact` live impl swaps its direct `.from("profiles")` query for the `find_profile_by_username` RPC — **signature unchanged**, so `UsernameResolving` consumers (the tag picker) and fakes are untouched.
- Error copy: extend the existing `PostError.message(for:)` mapping with friend cases — "We couldn't find that username.", "You're already friends.", "You can't add yourself." (string-matched on the RPC error messages, consistent with the existing approach).

### 6.3 ViewModel

`FriendsViewModel` (`@MainActor @Observable`):
- Loads `[FriendEdge]`, classifies against `myID` into `incoming` (pending, I'm addressee), `outgoing` (pending, I'm requester), `friends` (accepted).
- `searchText` drives a **client-side similarity filter** over the accepted `friends` list — case-insensitive substring across `username` and `displayName` (like mainstream social apps). No server call.
- `addFriend(username:)` → maps the returned `Friendship`: `pending` → "Request sent", `accepted` → "You're now friends" (auto-accept); surfaces not-found / already-friends / self errors.
- `respond(requesterID:accept:)` → accept/decline, then refresh.

### 6.4 View

`FriendsView` in its own `NavigationStack`, presented as a `.sheet` from `HomeView`'s currently-dead `person` tab (consistent with the compose sheet; no tab-bar rework):
- **Add friend**: a `SereneTextField` (exact `@username`, `autocapitalization: .never`) + Add button; inline status/error message.
- **Requests** section: incoming pending, each with Accept / Decline.
- **Sent** section: outgoing pending (awaiting response).
- **Friends** section: accepted friends with a search field filtering the list by similarity.

Reuses Serene Light theme + `SereneControls`. No unread badge / notification wiring (Plan 6). No friend-profile view (deferred).

---

## 7. Testing strategy

**SQL / RLS (Supabase MCP `execute_sql`, transactional with `rollback`):**
- `send_friend_request`: fresh → one `pending` row; reciprocal → auto-accept with exactly one `accepted` row (not two); duplicate own request idempotent; already-friends / self / not-found each raise; `friendships_unordered_uniq` rejects a manual reciprocal insert.
- `respond_to_friend_request`: accept sets `accepted` + `responded_at` and only the addressee can; decline deletes; a non-addressee accept matches no row.
- profiles lockdown matrix: self, accepted-friend, pending-party (either direction), tagged-in-visible-post, commenter-on-visible-post all visible; an unrelated stranger not visible; `find_profile_by_username` returns a stranger's row by exact match only.
- defense-in-depth: authenticated direct `INSERT`/`UPDATE`/`DELETE` on `friendships` denied.
- feed: with A⇄B accepted, A's timeline query returns B's `shared_to_timeline` post; a stranger's query does not.
- `get_advisors type:"security"` clean — no new lints; every definer function sets `search_path`.

**Swift (Swift Testing):**
- `FriendEdge` decoding (accepted + pending shapes; `otherParty` classification).
- `FriendsViewModel`: edge→section classification; similarity filter; `addFriend` success / auto-accept / not-found / already-friends; `respond` accept & decline — against a new `FakeFriendService` (additive to `FakeSocialServices.swift`).
- `TimelineViewModel` updated for the new `fetchTimeline(before:limit:)` signature (fake updated in lockstep).

---

## 8. Risks & notes

- **profiles RLS cost**: the new policy runs per-row EXISTS subqueries. Profile reads per query are few (author + a handful of tag/comment authors) and the subqueries hit existing indexes (`post_tags_user_idx`, comments' post index, `friendships` PK/addressee index). Revisit only if measured slow.
- **Group-member profile visibility** (Plan 4) will add one more clause (`private.is_group_member`-style) to `profiles_select_scoped` — additive; noted so Plan 4 expects it.
- **Auto-accept race**: covered by the unordered unique index + `unique_violation` retry; the index is the structural backstop, the RPC logic is the happy path.
- **No notifications**: friend request/accept produce no `notifications` rows in this plan (Plan 6 owns triggers + push), holding the discipline Plan 2 kept for likes/comments/tags.
