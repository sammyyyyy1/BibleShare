# BibleShare — Encouragements & Feeds (Social Plan 2) — Design

**Date:** 2026-07-16
**Status:** Approved (design), pending implementation plan
**Parent spec:** `docs/superpowers/specs/2026-07-15-groups-encouragements-checkins-design.md` (§8 Milestone 2)
**Builds on:** Social Plan 1 — `docs/superpowers/plans/2026-07-15-social-core-01-schema-rls-models.md` (schema, RLS, Swift models — merged)

---

## 1. Scope

Ship the encouragement end-to-end: compose one (title required; optional body, verses, media, user tags), see it on your personal timeline, render it in a post cell, and like/comment on it.

**In scope**
- `create_encouragement` RPC — atomic post + attachments write.
- Private `media` Storage bucket + visibility-tracking read policy; image upload from compose.
- Link attachments (`post_media.media_type = 'link'`).
- Verse attachments: structured reference entry → WEB text fetch → `text_snapshot`.
- User tags via **exact** `@username` resolution.
- Personal timeline feed (author's own `shared_to_timeline` posts), keyset-paginated.
- Post cell; likes (optimistic); comment thread screen; author post-delete.

**Non-goals (deferred by milestone)**
- Friends' posts on Home → Plan 3. Group targeting → Plan 4. Check-ins → Plan 5.
- Notification rows for like/comment/tag → Plan 6 (triggers). No notification writes here.
- Post editing beyond author delete (parent spec §1).
- Fuzzy/prefix user search of any kind (see §7).
- Orphaned-Storage-object sweeper (§5.1 avoids creating orphans instead).

---

## 2. Decisions

| Decision | Choice | Why |
|---|---|---|
| Compose write path | `create_encouragement` RPC (`SECURITY DEFINER`) | A post is 1 + N rows across 4 tables. Direct client inserts are non-atomic — a failed child insert strands a title-only post in the feed — and need hand-rolled compensating deletes. Plan 4 extends the same RPC with `p_group_ids`. |
| Feed query | PostgREST nested select | `posts_select_visible` already encodes visibility; a feed RPC would duplicate it and risk drift. Plan 3 drops one filter to surface friends' posts. |
| Media | Images + links | Parent spec §3.4 in full. |
| Bucket privacy | Private + signed URLs | Image access must track post visibility, not be a capability URL that outlives an unfriending. |
| Tag picker | Exact `@username` only | No search surface over `profiles`. Friend-scoped search arrives in Plan 3. |

---

## 3. Database

Two additive migrations, applied to project `jstdoizgosatitptyrdy` via `mcp__supabase__apply_migration` and committed.

### 3.1 `20260716010000_media_bucket.sql`

Private bucket `media`. Object key: `{user_id}/{uuid}.jpg`. `post_media.url` stores **the object path**, not a URL.

Policies on `storage.objects`, all `to authenticated`:
- **INSERT / DELETE** — `bucket_id = 'media' and (storage.foldername(name))[1] = (select auth.uid())::text`. You write only your own folder.
- **SELECT** — `bucket_id = 'media'` and either the same self-folder test, or the object is referenced by a `post_media` row whose parent post is visible:

```sql
exists (
  select 1 from public.post_media pm
  where pm.url = storage.objects.name
    and exists (select 1 from public.posts p where p.id = pm.post_id)
)
```

The nested `public.posts` select is evaluated **as the invoker**, so `posts_select_visible` applies and read access to an image equals read access to its post — for free, and it stays correct as Plans 3–4 widen visibility.

> **Constraint:** this predicate must NOT be wrapped in a `SECURITY DEFINER` helper. Definer rights bypass RLS on `posts`, which is the entire mechanism being relied on. Inline it, or use a plain (invoker) `stable` function.

### 3.2 `20260716010100_create_encouragement_rpc.sql`

```
public.create_encouragement(
  p_title              text,
  p_body               text,
  p_shared_to_timeline boolean,
  p_verses             jsonb,      -- [{translation,book,chapter,verse_start,verse_end,reference_label,text_snapshot,position}]
  p_media              jsonb,      -- [{media_type,url,thumbnail_url,title,description,position}]
  p_tag_user_ids       uuid[]
) returns uuid
```

`SECURITY DEFINER`, `set search_path = public`, `grant execute to authenticated`. Body:

1. `v_uid := auth.uid()`; raise if null.
2. Raise if `btrim(p_title)` is null/empty — belt-and-braces alongside the `posts_encouragement_title` CHECK.
3. Insert `posts (author_id => v_uid, kind => 'encouragement', title, body, shared_to_timeline)` returning id.
4. Insert children from `jsonb_to_recordset(coalesce(p_verses,'[]'))` / `(p_media)`, and `unnest(coalesce(p_tag_user_ids,'{}'))` for `post_tags`.
5. Return the post id.

`author_id` is derived from `auth.uid()`, never a parameter — a caller cannot author as someone else. The whole function is one transaction, so any child failure rolls the post back. Definer rights are safe here because every write is pinned to the caller's own id and targets only tables the caller could already write via their author-scoped policies.

**No new SQL for likes, comments, or post delete** — `likes_insert_self`, `Users can remove their own like`, `comments_insert_self`, `Users can delete their own comments`, and `Users can delete their own posts` all exist and suffice.

---

## 4. iOS

### 4.1 Services (`Services/`)

Each gets a protocol seam mirroring the existing `AuthProviding` pattern, so ViewModels test against fakes.

- **`PostService`** — `createEncouragement(_:) async throws -> UUID` (RPC), `deletePost(id:)`, `setLike(postID:liked:)`, `addComment(postID:body:)`, `fetchComments(postID:)`.
- **`FeedService`** — `fetchTimeline(before: Date?, limit: Int) async throws -> [FeedItem]`.
- **`MediaUploader`** — `upload(_ image: UIImage) async throws -> String` (downscale ≤1600px, JPEG ~0.8, key `{uid}/{uuid}.jpg`), `delete(paths:)`, `signedURL(path:) async throws -> URL`.
- **`BibleService`** — `fetch(book:chapter:verseStart:verseEnd:) async throws -> (label: String, text: String)` against a free WEB endpoint (bible-api.com), with an in-memory cache. Per parent spec §10, `text_snapshot` means render never depends on this.
- **`ProfileService.resolveUsername(_:) async throws -> Profile?`** — a single `eq` lookup. Exact match only.

### 4.2 Feed query

```
posts?select=*,author:profiles(*),post_verses(*),post_media(*),
       post_tags(*,profiles(*)),likes(count),comments(count)
     &kind=eq.encouragement&shared_to_timeline=is.true
     &author_id=eq.<me>&created_at=lt.<cursor>
     &order=created_at.desc&limit=20
```

Keyset on `created_at`. `likes(count)` gives the tally but not membership, so `is_liked` comes from one companion query — `likes?select=post_id&user_id=eq.<me>&post_id=in.(<page ids>)` — folded in client-side.

Plan 3 removes `author_id=eq.<me>` and RLS surfaces friends' timeline posts with no other change.

### 4.3 Models (`Models/`)

Additive; Plan 1's row models are untouched.
- `FeedItem` — decodes the embedded payload (post fields + `author: Profile`, `[PostVerse]`, `[PostMedia]`, tags with profiles, counts), plus client-side `isLiked`.
- `NewVerse`, `NewMediaItem`, `CreateEncouragementParams` — `Encodable` RPC params matching §3.2 exactly.

### 4.4 ViewModels (`@Observable`)

`ComposeViewModel` (validation, attachment state, submit), `TimelineViewModel` (page load, pagination, like toggle, delete), `CommentsViewModel`.

### 4.5 Views (`Views/`, Serene Light throughout)

`TimelineView` replaces HomeView's placeholder body (top bar and tab bar stay); `PostCell` (serif title, body, `VerseCard`s, `MediaStrip`, tag row, heart + comment affordances, author menu → delete); `ComposeEncouragementView`; `VersePickerSheet` (book/chapter/verse entry → fetch → preview); `UserTagSheet` (exact `@username` entry → resolve → chip); `CommentsView`. Reuse `SereneTextField` / `PrimaryButton`; add a `SereneTextEditor` only if the body field needs it.

---

## 5. Data flow & error handling

### 5.1 Compose submit (orphan-free ordering)

1. Validate: `btrim(title)` non-empty (the only hard requirement); media ≤ 4; each verse already resolved.
2. Upload picked images **now**, collecting object paths. (Uploading at pick-time would strand an object for every abandoned draft, and no sweeper is in scope.)
3. Call `create_encouragement` with the paths in `p_media`.
4. **If the RPC throws, delete the just-uploaded objects** — the client holds the paths and has a delete policy. This is the compensating action that keeps the bucket clean.
5. On success, prepend the new item to the timeline.

Images are uploaded before a post row exists, so the storage SELECT policy's self-folder clause (§3.1) is what lets the author preview them in that window.

### 5.2 Likes

Optimistic: flip `isLiked` and the count in the cell, then insert/delete the `likes` row; revert both on failure. PK `(user_id, post_id)` makes a double-tap race idempotent.

### 5.3 Errors

A `PostError` enum maps `PostgrestError` to user-facing copy, distinguishing the recoverable (network → retry) from the terminal (RLS/constraint → surface and stop). Compose shows an inline banner and **keeps the draft**. Feed shows a retry row. Verse fetch failure is non-fatal: the user may attach nothing or retry, never a silent empty `text_snapshot`.

---

## 6. Testing

**SQL** (`execute_sql`, impersonating fixture users, `rollback` at the end):
- `create_encouragement` writes post + verses + media + tags in one call; counts match.
- Bad `p_verses` payload → **whole thing rolls back**, zero `posts` rows left.
- Blank/whitespace title → rejected.
- Author is forced to `auth.uid()` regardless of caller intent.
- Storage: a user who cannot see the post cannot select the referenced `storage.objects` row; the author can.
- `get_advisors type:"security"` clean — no mutable-search_path or RLS-disabled lints.

**Swift** (Swift Testing, iPhone 17 simulator):
- `ComposeViewModel`: title required/trimmed, media cap, submit blocked while invalid, draft survives a failed submit.
- `FeedItem` decoding against a captured PostgREST payload (nulls: no body, no attachments, zero counts).
- `BibleService` reference-label formatting (single verse vs range).
- Manual simulator pass: compose → timeline → like → comment → delete.

---

## 7. Open issues / handoffs

- **`profiles` is world-readable.** The initial auth migration's `Profiles are viewable by everyone` (`SELECT using (true)`) means any signed-in client can enumerate every username via a PostgREST `like` filter, regardless of the exact-match-only tag picker. Exact match is the right product behaviour but is **not** an enumeration control. Tightening that policy touches auth/onboarding and the friends model, so it belongs to **Plan 3**, alongside friend-scoped search. Flagged, not fixed here.
- **Plan 3 inherits:** friend-list search for the tag picker; dropping the `author_id` feed filter.
- **Plan 4 inherits:** `p_group_ids uuid[]` on `create_encouragement` + a membership assert.
- **Plan 6 inherits:** like/comment/tag notification triggers. Plan 2 deliberately writes no `notifications` rows.
- Bible API is a third-party dependency at compose time only; `text_snapshot` keeps render offline-safe.
