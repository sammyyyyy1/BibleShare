# Social Core — Plan 2: Encouragements & Feeds — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the encouragement end-to-end — compose one (title required; optional body, verses, images, links, user tags), see it on your personal timeline, and like/comment on it.

**Architecture:** One `SECURITY DEFINER` RPC (`create_encouragement`) writes the post and every attachment in a single transaction; a private `media` Storage bucket whose read policy re-uses `posts_select_visible` so image access tracks post visibility; and a PostgREST nested select for the feed so RLS remains the only source of visibility truth. Swift layers on protocol-seamed services (mirroring the existing `AuthProviding` pattern), `@Observable` ViewModels, and Serene Light views.

**Tech Stack:** Supabase (Postgres 17, Storage), Supabase MCP (`apply_migration`, `execute_sql`, `get_advisors`), Swift 6 / SwiftUI, iOS 17, `supabase-swift` (SPM, `from: 2.0.0`), PhotosUI, Swift Testing (`import Testing`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-07-16-encouragements-feeds-design.md`
**Builds on:** `docs/superpowers/plans/2026-07-15-social-core-01-schema-rls-models.md` (merged).

## Global Constraints

- This is **Plan 2 of 6** for the social-core spec. Timeline-only: **no** friends (Plan 3), **no** group targeting (Plan 4), **no** check-ins (Plan 5), **no** notification writes (Plan 6). Do not build them.
- Supabase project ref **`jstdoizgosatitptyrdy`**. Apply migrations with `mcp__supabase__apply_migration`; verify with `mcp__supabase__execute_sql`; lint with `mcp__supabase__get_advisors type:"security"`. The migration file must also be committed.
- RLS helpers live in the **`private`** schema: `private.is_friend`, `private.is_group_member`, `private.post_in_visible_group`. Any new policy calls `private.*`, **never** `public.*`.
- Every `SECURITY DEFINER` function sets `set search_path = public` (avoids the mutable-search_path advisor lint).
- **The storage read predicate must NOT be `SECURITY DEFINER`.** It relies on `posts` RLS being applied to the invoker; definer rights would bypass that and expose every image. Inline it in the policy.
- **UUID case:** Swift's `UUID.uuidString` is UPPERCASE; Postgres `auth.uid()::text` is lowercase. Every storage path built in Swift must use `.uuidString.lowercased()`, or the folder-ownership policies silently deny.
- Swift language version **6.0**; iOS deployment target **17.0**; `SWIFT_STRICT_CONCURRENCY: complete`. XcodeGen — edit `project.yml`, never the `.xcodeproj`, then `make generate`. `project.yml` already globs `App/ Models/ Views/ ViewModels/ Services/ Resources/` by path, so **new files in those directories need no `project.yml` change** — but `make generate` is still required before building.
- Build/test on `platform=iOS Simulator,name=iPhone 17`. **Never** `killall CoreSimulatorService`.
- The Swift model for a `groups` row is **`FellowshipGroup`**, never `Group`.
- snake_case DB columns map to camelCase Swift via explicit `CodingKeys`.
- TDD: test first, watch it fail, implement, watch it pass. Commit after every task.

## File Structure

**Migrations (create):**
- `supabase/migrations/20260716010000_media_bucket.sql` — private `media` bucket + `storage.objects` policies.
- `supabase/migrations/20260716010100_create_encouragement_rpc.sql` — the compose RPC.

**Swift (create):**
- `Models/FeedModels.swift` — `FeedItem`, `TaggedUser`, `CountRow`, `CommentItem` (read DTOs).
- `Models/ComposeParams.swift` — `NewVerse`, `NewMediaItem`, `CreateEncouragementParams` (write DTOs).
- `Services/SocialServicing.swift` — protocol seams + `PostError`.
- `Services/PostService.swift` — RPC + likes/comments/delete.
- `Services/FeedService.swift` — timeline query + liked-ids companion query.
- `Services/MediaUploader.swift` — upload/delete/signedURL.
- `Services/ImageProcessor.swift` — pure downscale + JPEG encode.
- `Services/BibleService.swift` — reference → WEB text, cached.
- `ViewModels/ComposeViewModel.swift`, `ViewModels/TimelineViewModel.swift`, `ViewModels/CommentsViewModel.swift`
- `Views/TimelineView.swift`, `Views/ComposeEncouragementView.swift`, `Views/CommentsView.swift`
- `Views/Components/PostCell.swift`, `Views/Components/VerseCard.swift`, `Views/Components/MediaStrip.swift`, `Views/Components/RemoteImage.swift`
- `Views/Sheets/VersePickerSheet.swift`, `Views/Sheets/UserTagSheet.swift`

**Swift (modify):**
- `Views/HomeView.swift` — placeholder body → `TimelineView`; wire the compose tab.

**Tests (create):**
- `BibleShareTests/FeedModelTests.swift`, `BibleShareTests/BibleServiceTests.swift`, `BibleShareTests/ComposeViewModelTests.swift`, `BibleShareTests/TimelineViewModelTests.swift`, `BibleShareTests/FakeSocialServices.swift`, `BibleShareTests/TestDecoder.swift`

---

## Task 1: Private `media` bucket + storage policies

**Files:**
- Create: `supabase/migrations/20260716010000_media_bucket.sql`

**Interfaces:**
- Produces (DB): bucket `media` (private); `storage.objects` policies `media_insert_own`, `media_delete_own`, `media_select_visible`.
- Consumes: `public.posts` (`posts_select_visible`), `public.post_media` from Plan 1.

- [ ] **Step 1: Write the migration file**

`supabase/migrations/20260716010000_media_bucket.sql`:

```sql
-- Private bucket for encouragement images.
-- Object key convention: {user_id}/{uuid}.jpg  (user_id lowercase, as auth.uid()::text renders it)
-- public.post_media.url stores THE OBJECT PATH, not a URL.

insert into storage.buckets (id, name, public)
values ('media', 'media', false)
on conflict (id) do nothing;

-- Write/delete: only inside your own folder.
drop policy if exists media_insert_own on storage.objects;
create policy media_insert_own on storage.objects for insert to authenticated
with check (
  bucket_id = 'media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists media_delete_own on storage.objects;
create policy media_delete_own on storage.objects for delete to authenticated
using (
  bucket_id = 'media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- Read: your own objects (needed while composing, before any post row exists),
-- OR an object referenced by a post_media row whose parent post you can see.
--
-- The nested `public.posts` select is evaluated as the INVOKER, so
-- posts_select_visible applies and image access exactly tracks post visibility.
-- DO NOT wrap this predicate in a SECURITY DEFINER helper: definer rights bypass
-- that RLS and would make every image readable by every authenticated user.
drop policy if exists media_select_visible on storage.objects;
create policy media_select_visible on storage.objects for select to authenticated
using (
  bucket_id = 'media'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1
      from public.post_media pm
      where pm.url = storage.objects.name
        and exists (select 1 from public.posts p where p.id = pm.post_id)
    )
  )
);
```

- [ ] **Step 2: Apply the migration via MCP**

Call `mcp__supabase__apply_migration` with `name:"media_bucket"`, `query` = the SQL above.
Expected: success.

- [ ] **Step 3: Verify the bucket exists and is private**

Call `mcp__supabase__execute_sql`:

```sql
select id, public from storage.buckets where id = 'media';
```

Expected: one row, `public = false`. A `true` here means images are world-readable — stop and fix.

- [ ] **Step 4: Prove image visibility tracks post visibility**

This is the security assertion for the whole task. Call `mcp__supabase__execute_sql`:

```sql
begin;
  -- Fixtures: Alice (author), Bob (Alice's friend), Carol (stranger).
  insert into auth.users (id, instance_id, aud, role, email) values
    ('aaaaaaaa-0000-0000-0000-00000000ff01','00000000-0000-0000-0000-000000000000','authenticated','authenticated','a_media@test.dev'),
    ('bbbbbbbb-0000-0000-0000-00000000ff02','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b_media@test.dev'),
    ('cccccccc-0000-0000-0000-00000000ff03','00000000-0000-0000-0000-000000000000','authenticated','authenticated','c_media@test.dev');

  insert into public.friendships (requester_id, addressee_id, status, responded_at)
  values ('aaaaaaaa-0000-0000-0000-00000000ff01','bbbbbbbb-0000-0000-0000-00000000ff02','accepted', now());

  -- Alice's timeline post with one image attachment.
  insert into public.posts (id, author_id, kind, title, shared_to_timeline)
  values ('99999990-0000-0000-0000-00000000ff01','aaaaaaaa-0000-0000-0000-00000000ff01','encouragement','Photo Post', true);

  insert into public.post_media (post_id, media_type, url, position)
  values ('99999990-0000-0000-0000-00000000ff01','image',
          'aaaaaaaa-0000-0000-0000-00000000ff01/pic.jpg', 0);

  insert into storage.objects (bucket_id, name, owner_id)
  values ('media','aaaaaaaa-0000-0000-0000-00000000ff01/pic.jpg','aaaaaaaa-0000-0000-0000-00000000ff01');

  set local role authenticated;

  select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-0000-0000-00000000ff01","role":"authenticated"}', true);
  select count(*) as alice_sees from storage.objects where name = 'aaaaaaaa-0000-0000-0000-00000000ff01/pic.jpg';  -- 1

  select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-0000-0000-00000000ff02","role":"authenticated"}', true);
  select count(*) as bob_sees from storage.objects where name = 'aaaaaaaa-0000-0000-0000-00000000ff01/pic.jpg';    -- 1 (friend sees post -> sees image)

  select set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-00000000ff03","role":"authenticated"}', true);
  select count(*) as carol_sees from storage.objects where name = 'aaaaaaaa-0000-0000-0000-00000000ff01/pic.jpg';  -- 0
rollback;
```

Expected: `alice_sees=1`, `bob_sees=1`, `carol_sees=0`. **`carol_sees` must be 0** — a non-friend must not reach the object row. The `rollback` discards every fixture.

- [ ] **Step 5: Check security advisors**

Call `mcp__supabase__get_advisors` with `type:"security"`.
Expected: no new lints attributable to this migration.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260716010000_media_bucket.sql
git commit -m "feat(db): private media bucket with visibility-tracking read policy"
```

---

## Task 2: `create_encouragement` RPC

**Files:**
- Create: `supabase/migrations/20260716010100_create_encouragement_rpc.sql`

**Interfaces:**
- Produces (DB): `public.create_encouragement(p_title text, p_body text, p_shared_to_timeline boolean, p_verses jsonb, p_media jsonb, p_tag_user_ids uuid[]) returns uuid`, executable by `authenticated`.
- Consumed by: Task 5's `PostService.createEncouragement`, whose `CreateEncouragementParams` `CodingKeys` must match these parameter names exactly.

- [ ] **Step 1: Write the migration file**

`supabase/migrations/20260716010100_create_encouragement_rpc.sql`:

```sql
-- Atomic compose: one posts row + its verses/media/tags, in a single transaction.
-- SECURITY DEFINER is safe here because author_id is derived from auth.uid() and
-- is never a parameter — a caller cannot author as anyone else.

create or replace function public.create_encouragement(
  p_title              text,
  p_body               text    default null,
  p_shared_to_timeline boolean default true,
  p_verses             jsonb   default '[]'::jsonb,
  p_media              jsonb   default '[]'::jsonb,
  p_tag_user_ids       uuid[]  default '{}'::uuid[]
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_post_id uuid;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if p_title is null or btrim(p_title) = '' then
    raise exception 'title is required' using errcode = '22023';
  end if;

  -- An image path must live under the caller's own storage folder. Without this,
  -- a caller could reference someone else's object path and make that private
  -- image readable through their own post (media_select_visible keys off post_media.url).
  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_media, '[]'::jsonb)) as m(media_type text, url text)
    where m.media_type = 'image'
      and (m.url is null or m.url not like v_uid::text || '/%')
  ) then
    raise exception 'image media must live under the caller''s own storage folder'
      using errcode = '42501';
  end if;

  insert into public.posts (author_id, kind, title, body, shared_to_timeline)
  values (
    v_uid,
    'encouragement',
    btrim(p_title),
    nullif(btrim(coalesce(p_body, '')), ''),
    coalesce(p_shared_to_timeline, true)
  )
  returning id into v_post_id;

  insert into public.post_verses
    (post_id, translation, book, chapter, verse_start, verse_end, reference_label, text_snapshot, position)
  select v_post_id, coalesce(v.translation, 'WEB'), v.book, v.chapter,
         v.verse_start, v.verse_end, v.reference_label, v.text_snapshot, coalesce(v.position, 0)
  from jsonb_to_recordset(coalesce(p_verses, '[]'::jsonb)) as v(
    translation text, book text, chapter int, verse_start int, verse_end int,
    reference_label text, text_snapshot text, position int
  );

  insert into public.post_media
    (post_id, media_type, url, thumbnail_url, title, description, position)
  select v_post_id, m.media_type, m.url, m.thumbnail_url, m.title, m.description, coalesce(m.position, 0)
  from jsonb_to_recordset(coalesce(p_media, '[]'::jsonb)) as m(
    media_type text, url text, thumbnail_url text, title text, description text, position int
  );

  insert into public.post_tags (post_id, tagged_user_id)
  select v_post_id, t
  from unnest(coalesce(p_tag_user_ids, '{}'::uuid[])) as t
  where t <> v_uid            -- tagging yourself is a no-op
  on conflict do nothing;

  return v_post_id;
end;
$$;

revoke execute on function public.create_encouragement(text,text,boolean,jsonb,jsonb,uuid[]) from public, anon;
grant  execute on function public.create_encouragement(text,text,boolean,jsonb,jsonb,uuid[]) to authenticated;
```

- [ ] **Step 2: Apply the migration via MCP**

Call `mcp__supabase__apply_migration` with `name:"create_encouragement_rpc"`, `query` = the SQL above.
Expected: success.

- [ ] **Step 3: Verify the happy path writes every child row**

Call `mcp__supabase__execute_sql`:

```sql
begin;
  insert into auth.users (id, instance_id, aud, role, email) values
    ('aaaaaaaa-0000-0000-0000-00000000ee01','00000000-0000-0000-0000-000000000000','authenticated','authenticated','a_rpc@test.dev'),
    ('bbbbbbbb-0000-0000-0000-00000000ee02','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b_rpc@test.dev');

  set local role authenticated;
  select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-0000-0000-00000000ee01","role":"authenticated"}', true);

  select public.create_encouragement(
    'Be strong',
    'Joshua reminded me today.',
    true,
    '[{"translation":"WEB","book":"Joshua","chapter":1,"verse_start":9,"verse_end":9,
       "reference_label":"Joshua 1:9","text_snapshot":"Be strong and courageous.","position":0}]'::jsonb,
    '[{"media_type":"image","url":"aaaaaaaa-0000-0000-0000-00000000ee01/pic.jpg","position":0},
      {"media_type":"link","url":"https://example.com","title":"A link","position":1}]'::jsonb,
    array['bbbbbbbb-0000-0000-0000-00000000ee02']::uuid[]
  ) as new_post_id;

  select
    (select count(*) from public.posts       where author_id='aaaaaaaa-0000-0000-0000-00000000ee01') as posts,    -- 1
    (select count(*) from public.post_verses)                                                        as verses,   -- 1
    (select count(*) from public.post_media)                                                         as media,    -- 2
    (select count(*) from public.post_tags)                                                          as tags;     -- 1
rollback;
```

Expected: `posts=1, verses=1, media=2, tags=1`.

- [ ] **Step 4: Verify a bad verse payload rolls the whole post back**

This proves the atomicity the RPC exists for. Call `mcp__supabase__execute_sql`:

```sql
begin;
  insert into auth.users (id, instance_id, aud, role, email) values
    ('aaaaaaaa-0000-0000-0000-00000000ee11','00000000-0000-0000-0000-000000000000','authenticated','authenticated','a_atomic@test.dev');

  set local role authenticated;
  select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-0000-0000-00000000ee11","role":"authenticated"}', true);

  do $$
  begin
    -- `book` is NOT NULL; this payload omits it.
    perform public.create_encouragement(
      'Orphan check', null, true,
      '[{"chapter":1,"verse_start":1,"verse_end":1,"reference_label":"X 1:1","text_snapshot":"t"}]'::jsonb,
      '[]'::jsonb, '{}'::uuid[]
    );
    raise exception 'RPC DID NOT FAIL';
  exception when not_null_violation then
    raise notice 'ok: bad verse payload rejected';
  end $$;

  select count(*) as orphan_posts from public.posts
   where author_id = 'aaaaaaaa-0000-0000-0000-00000000ee11';   -- 0
rollback;
```

Expected: `NOTICE: ok: bad verse payload rejected` and `orphan_posts=0`. **A non-zero count means the post survived its failed children — the exact bug this RPC prevents.**

- [ ] **Step 5: Verify title validation, author forcing, and the foreign-folder image guard**

Call `mcp__supabase__execute_sql`:

```sql
begin;
  insert into auth.users (id, instance_id, aud, role, email) values
    ('aaaaaaaa-0000-0000-0000-00000000ee21','00000000-0000-0000-0000-000000000000','authenticated','authenticated','a_guard@test.dev'),
    ('bbbbbbbb-0000-0000-0000-00000000ee22','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b_guard@test.dev');

  set local role authenticated;
  select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-0000-0000-00000000ee21","role":"authenticated"}', true);

  do $$
  begin
    begin
      perform public.create_encouragement('   ', null, true, '[]'::jsonb, '[]'::jsonb, '{}'::uuid[]);
      raise exception 'BLANK TITLE ACCEPTED';
    exception when others then
      if sqlerrm like '%title is required%' then raise notice 'ok: blank title rejected';
      else raise; end if;
    end;

    begin
      -- Bob's folder, Alice calling.
      perform public.create_encouragement('Steal', null, true, '[]'::jsonb,
        '[{"media_type":"image","url":"bbbbbbbb-0000-0000-0000-00000000ee22/secret.jpg","position":0}]'::jsonb,
        '{}'::uuid[]);
      raise exception 'FOREIGN FOLDER ACCEPTED';
    exception when insufficient_privilege then
      raise notice 'ok: foreign-folder image rejected';
    end;
  end $$;

  -- Author is forced to auth.uid() regardless of anything the caller supplies.
  select public.create_encouragement('Mine', null, true, '[]'::jsonb, '[]'::jsonb, '{}'::uuid[]) as pid;
  select count(*) as authored_by_caller from public.posts
   where author_id = 'aaaaaaaa-0000-0000-0000-00000000ee21' and title = 'Mine';   -- 1
rollback;
```

Expected: `ok: blank title rejected`, `ok: foreign-folder image rejected`, `authored_by_caller=1`.

- [ ] **Step 6: Check security advisors**

Call `mcp__supabase__get_advisors` with `type:"security"`.
Expected: no "function search_path mutable" lint for `create_encouragement`.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260716010100_create_encouragement_rpc.sql
git commit -m "feat(db): create_encouragement RPC (atomic post + attachments)"
```

---

## Task 3: Feed & compose DTOs

**Files:**
- Create: `Models/FeedModels.swift`
- Create: `Models/ComposeParams.swift`
- Test: `BibleShareTests/TestDecoder.swift`
- Test: `BibleShareTests/FeedModelTests.swift`

**Interfaces:**
- Consumes: `Profile`, `PostVerse`, `PostMedia`, `MediaType` from `Models/Models.swift` (Plan 1).
- Produces (Swift):
  - `struct FeedItem: Decodable, Identifiable, Hashable, Sendable` — `id, authorID, title: String?, body: String?, createdAt, author: Profile?, verses: [PostVerse], media: [PostMedia], tags: [TaggedUser], likeCount: Int, commentCount: Int, isLiked: Bool`
  - `struct TaggedUser`, `struct CountRow`, `struct CommentItem`
  - `struct NewVerse`, `struct NewMediaItem`, `struct CreateEncouragementParams` (Encodable; keys `p_title`/`p_body`/`p_shared_to_timeline`/`p_verses`/`p_media`/`p_tag_user_ids`)
  - `enum TestDecoder { static func postgrest() -> JSONDecoder }` (test target only)

- [ ] **Step 1: Write the shared test decoder**

`BibleShareTests/TestDecoder.swift`:

```swift
import Foundation

/// Decoder matching Supabase's PostgREST timestamps (ISO8601, with or without
/// fractional seconds). Mirrors the decoder used in the Plan 1 model tests.
enum TestDecoder {
    static func postgrest() -> JSONDecoder {
        let d = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "bad date \(s)"))
        }
        return d
    }
}
```

- [ ] **Step 2: Write the failing FeedItem decoding tests**

`BibleShareTests/FeedModelTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleShare

struct FeedModelTests {

    /// The full embedded payload PostgREST returns for the timeline query.
    @Test func decodesFullFeedItem() throws {
        let json = """
        {"id":"99999990-0000-0000-0000-000000000001",
         "author_id":"aaaaaaaa-0000-0000-0000-000000000001",
         "title":"Be strong","body":"Joshua reminded me.",
         "created_at":"2026-07-16T12:00:00.000Z",
         "author":{"id":"aaaaaaaa-0000-0000-0000-000000000001","username":"alice",
                   "username_set":true,"display_name":"Alice","avatar_url":null,"bio":null,
                   "created_at":"2026-07-01T12:00:00Z"},
         "post_verses":[
           {"id":"33333333-0000-0000-0000-0000000000cc","post_id":"99999990-0000-0000-0000-000000000001",
            "translation":"WEB","book":"Joshua","chapter":1,"verse_start":9,"verse_end":9,
            "reference_label":"Joshua 1:9","text_snapshot":"Be strong and courageous.","position":1},
           {"id":"33333333-0000-0000-0000-0000000000cd","post_id":"99999990-0000-0000-0000-000000000001",
            "translation":"WEB","book":"John","chapter":3,"verse_start":16,"verse_end":17,
            "reference_label":"John 3:16–17","text_snapshot":"For God so loved...","position":0}],
         "post_media":[
           {"id":"44444444-0000-0000-0000-0000000000dd","post_id":"99999990-0000-0000-0000-000000000001",
            "media_type":"image","url":"aaaaaaaa-0000-0000-0000-000000000001/pic.jpg",
            "thumbnail_url":null,"title":null,"description":null,"position":0}],
         "post_tags":[
           {"post_id":"99999990-0000-0000-0000-000000000001",
            "tagged_user_id":"bbbbbbbb-0000-0000-0000-000000000002",
            "created_at":"2026-07-16T12:00:00Z",
            "profiles":{"id":"bbbbbbbb-0000-0000-0000-000000000002","username":"bob",
                        "username_set":true,"display_name":null,"avatar_url":null,"bio":null,
                        "created_at":"2026-07-01T12:00:00Z"}}],
         "likes":[{"count":3}],
         "comments":[{"count":1}]}
        """.data(using: .utf8)!

        let item = try TestDecoder.postgrest().decode(FeedItem.self, from: json)
        #expect(item.title == "Be strong")
        #expect(item.author?.username == "alice")
        #expect(item.likeCount == 3)
        #expect(item.commentCount == 1)
        #expect(item.isLiked == false)             // client-side, defaults false
        #expect(item.media.count == 1)
        #expect(item.tags.first?.profile?.username == "bob")
        // Verses arrive out of order and must be sorted by `position`.
        #expect(item.verses.map(\.referenceLabel) == ["John 3:16–17", "Joshua 1:9"])
    }

    /// A bare post: no body, no attachments, zero counts. PostgREST returns []
    /// for empty embeds, so nothing may be force-unwrapped.
    @Test func decodesBareFeedItem() throws {
        let json = """
        {"id":"99999990-0000-0000-0000-000000000009",
         "author_id":"aaaaaaaa-0000-0000-0000-000000000001",
         "title":"Just a title","body":null,
         "created_at":"2026-07-16T12:00:00Z",
         "author":{"id":"aaaaaaaa-0000-0000-0000-000000000001","username":"alice",
                   "username_set":true,"display_name":null,"avatar_url":null,"bio":null,
                   "created_at":"2026-07-01T12:00:00Z"},
         "post_verses":[],"post_media":[],"post_tags":[],
         "likes":[],"comments":[]}
        """.data(using: .utf8)!

        let item = try TestDecoder.postgrest().decode(FeedItem.self, from: json)
        #expect(item.body == nil)
        #expect(item.verses.isEmpty)
        #expect(item.likeCount == 0)
        #expect(item.commentCount == 0)
    }

    @Test func decodesCommentItem() throws {
        let json = """
        {"id":"55555555-0000-0000-0000-0000000000ee",
         "post_id":"99999990-0000-0000-0000-000000000001",
         "author_id":"bbbbbbbb-0000-0000-0000-000000000002",
         "content":"Amen.","created_at":"2026-07-16T12:30:00Z",
         "author":{"id":"bbbbbbbb-0000-0000-0000-000000000002","username":"bob",
                   "username_set":true,"display_name":null,"avatar_url":null,"bio":null,
                   "created_at":"2026-07-01T12:00:00Z"}}
        """.data(using: .utf8)!

        let c = try TestDecoder.postgrest().decode(CommentItem.self, from: json)
        #expect(c.content == "Amen.")
        #expect(c.author?.username == "bob")
    }

    /// The RPC params must serialize to the exact parameter names the SQL declares.
    @Test func encodesCreateEncouragementParams() throws {
        let params = CreateEncouragementParams(
            title: "Be strong",
            body: nil,
            sharedToTimeline: true,
            verses: [NewVerse(book: "Joshua", chapter: 1, verseStart: 9, verseEnd: 9,
                              referenceLabel: "Joshua 1:9", textSnapshot: "Be strong.", position: 0)],
            media: [NewMediaItem(mediaType: .image, url: "uid/pic.jpg", position: 0)],
            tagUserIDs: [UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!]
        )
        let data = try JSONEncoder().encode(params)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(obj["p_title"] as? String == "Be strong")
        #expect(obj["p_shared_to_timeline"] as? Bool == true)
        #expect((obj["p_verses"] as? [[String: Any]])?.first?["reference_label"] as? String == "Joshua 1:9")
        #expect((obj["p_media"] as? [[String: Any]])?.first?["media_type"] as? String == "image")
        #expect((obj["p_tag_user_ids"] as? [String])?.count == 1)
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run:
```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:BibleShareTests/FeedModelTests 2>&1 | tail -20
```
Expected: FAIL — `cannot find 'FeedItem' in scope`.

- [ ] **Step 4: Write the read DTOs**

`Models/FeedModels.swift`:

```swift
import Foundation

/// Read-side DTOs decoding the PostgREST embedded payloads. Row models
/// (`Post`, `PostVerse`, …) live in Models.swift; these are the join shapes.

/// PostgREST renders `likes(count)` as `[{"count": 3}]`.
struct CountRow: Decodable, Hashable, Sendable {
    let count: Int
}

struct TaggedUser: Decodable, Identifiable, Hashable, Sendable {
    let taggedUserID: UUID
    let profile: Profile?

    var id: UUID { taggedUserID }

    enum CodingKeys: String, CodingKey {
        case taggedUserID = "tagged_user_id"
        case profile = "profiles"
    }
}

/// One timeline row: the post, its author, its attachments and its tallies.
struct FeedItem: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let authorID: UUID
    let title: String?
    let body: String?
    let createdAt: Date
    let author: Profile?
    var verses: [PostVerse]
    var media: [PostMedia]
    var tags: [TaggedUser]
    /// Mutable so the cell can update optimistically.
    var likeCount: Int
    var commentCount: Int
    /// Not part of the payload — filled from the companion liked-ids query.
    var isLiked: Bool = false

    var images: [PostMedia] { media.filter { $0.mediaType == .image } }
    var links: [PostMedia] { media.filter { $0.mediaType == .link } }

    enum CodingKeys: String, CodingKey {
        case id, title, body, author, likes, comments
        case authorID = "author_id"
        case createdAt = "created_at"
        case verses = "post_verses"
        case media = "post_media"
        case tags = "post_tags"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        authorID = try c.decode(UUID.self, forKey: .authorID)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        author = try c.decodeIfPresent(Profile.self, forKey: .author)
        verses = (try c.decodeIfPresent([PostVerse].self, forKey: .verses) ?? [])
            .sorted { $0.position < $1.position }
        media = (try c.decodeIfPresent([PostMedia].self, forKey: .media) ?? [])
            .sorted { $0.position < $1.position }
        tags = try c.decodeIfPresent([TaggedUser].self, forKey: .tags) ?? []
        likeCount = (try c.decodeIfPresent([CountRow].self, forKey: .likes))?.first?.count ?? 0
        commentCount = (try c.decodeIfPresent([CountRow].self, forKey: .comments))?.first?.count ?? 0
    }
}

/// A comment plus its author profile.
struct CommentItem: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let content: String
    let createdAt: Date
    let author: Profile?

    enum CodingKeys: String, CodingKey {
        case id, content, author
        case postID = "post_id"
        case authorID = "author_id"
        case createdAt = "created_at"
    }
}
```

- [ ] **Step 5: Write the compose params**

`Models/ComposeParams.swift`:

```swift
import Foundation

/// Write-side DTOs. Keys mirror `public.create_encouragement`'s parameter names
/// and the child tables' column names exactly — see
/// supabase/migrations/20260716010100_create_encouragement_rpc.sql

struct NewVerse: Encodable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var translation: String = "WEB"
    var book: String
    var chapter: Int
    var verseStart: Int
    var verseEnd: Int
    var referenceLabel: String
    var textSnapshot: String
    var position: Int

    enum CodingKeys: String, CodingKey {
        case translation, book, chapter, position
        case verseStart = "verse_start"
        case verseEnd = "verse_end"
        case referenceLabel = "reference_label"
        case textSnapshot = "text_snapshot"
    }
}

struct NewMediaItem: Encodable, Hashable, Sendable {
    var mediaType: MediaType
    var url: String
    var thumbnailURL: String?
    var title: String?
    var description: String?
    var position: Int

    enum CodingKeys: String, CodingKey {
        case url, title, description, position
        case mediaType = "media_type"
        case thumbnailURL = "thumbnail_url"
    }
}

struct CreateEncouragementParams: Encodable, Sendable {
    var title: String
    var body: String?
    var sharedToTimeline: Bool
    var verses: [NewVerse]
    var media: [NewMediaItem]
    var tagUserIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case title = "p_title"
        case body = "p_body"
        case sharedToTimeline = "p_shared_to_timeline"
        case verses = "p_verses"
        case media = "p_media"
        case tagUserIDs = "p_tag_user_ids"
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:BibleShareTests/FeedModelTests 2>&1 | tail -20
```
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add Models/FeedModels.swift Models/ComposeParams.swift \
        BibleShareTests/FeedModelTests.swift BibleShareTests/TestDecoder.swift
git commit -m "feat(models): feed + compose DTOs with decoding tests"
```

---

## Task 4: BibleService

**Files:**
- Create: `Services/BibleService.swift`
- Test: `BibleShareTests/BibleServiceTests.swift`

**Interfaces:**
- Produces (Swift):
  - `struct VersePassage: Hashable, Sendable { let referenceLabel: String; let text: String }`
  - `protocol BibleFetching: Sendable { func fetch(book: String, chapter: Int, verseStart: Int, verseEnd: Int) async throws -> VersePassage }`
  - `enum BibleError: Error, Equatable { case notFound, network }`
  - `actor BibleService: BibleFetching` with `static let shared`, `static func referenceLabel(book:chapter:verseStart:verseEnd:) -> String`, `static func parse(_ data: Data, label: String) throws -> VersePassage`
- Consumed by: Task 6 (`ComposeViewModel`), Task 9 (`VersePickerSheet`).

- [ ] **Step 1: Write the failing tests**

`BibleShareTests/BibleServiceTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleShare

struct BibleServiceTests {

    @Test func formatsSingleVerseLabel() {
        #expect(BibleService.referenceLabel(book: "Joshua", chapter: 1, verseStart: 9, verseEnd: 9)
                == "Joshua 1:9")
    }

    /// Ranges use an en dash (–), matching the spec's "John 3:16–17".
    @Test func formatsVerseRangeLabel() {
        #expect(BibleService.referenceLabel(book: "John", chapter: 3, verseStart: 16, verseEnd: 17)
                == "John 3:16–17")
    }

    @Test func parsesPassageResponse() throws {
        let json = """
        {"reference":"John 3:16-17","translation_name":"World English Bible",
         "verses":[{"book_name":"John","chapter":3,"verse":16,"text":"For God so loved the world.\\n"},
                   {"book_name":"John","chapter":3,"verse":17,"text":"For God didn't send his Son.\\n"}],
         "text":"For God so loved the world.\\nFor God didn't send his Son.\\n"}
        """.data(using: .utf8)!

        let passage = try BibleService.parse(json, label: "John 3:16–17")
        #expect(passage.referenceLabel == "John 3:16–17")
        // Verse texts are joined and whitespace-normalized — no stray newlines.
        #expect(passage.text == "For God so loved the world. For God didn't send his Son.")
    }

    @Test func parseThrowsNotFoundOnEmptyVerses() {
        let json = #"{"verses":[]}"#.data(using: .utf8)!
        #expect(throws: BibleError.notFound) {
            try BibleService.parse(json, label: "Nope 1:1")
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:BibleShareTests/BibleServiceTests 2>&1 | tail -20
```
Expected: FAIL — `cannot find 'BibleService' in scope`.

- [ ] **Step 3: Implement BibleService**

`Services/BibleService.swift`:

```swift
import Foundation

struct VersePassage: Hashable, Sendable {
    let referenceLabel: String
    let text: String
}

enum BibleError: Error, Equatable {
    case notFound
    case network
}

protocol BibleFetching: Sendable {
    func fetch(book: String, chapter: Int, verseStart: Int, verseEnd: Int) async throws -> VersePassage
}

/// Fetches public-domain WEB passages. Per spec §10 the text is snapshotted into
/// post_verses.text_snapshot at compose time, so rendering never depends on this.
actor BibleService: BibleFetching {
    static let shared = BibleService()

    private var cache: [String: VersePassage] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func referenceLabel(book: String, chapter: Int, verseStart: Int, verseEnd: Int) -> String {
        verseEnd > verseStart
            ? "\(book) \(chapter):\(verseStart)–\(verseEnd)"   // en dash
            : "\(book) \(chapter):\(verseStart)"
    }

    private struct APIResponse: Decodable {
        struct Verse: Decodable { let text: String }
        let verses: [Verse]
    }

    static func parse(_ data: Data, label: String) throws -> VersePassage {
        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        guard !decoded.verses.isEmpty else { throw BibleError.notFound }
        let text = decoded.verses
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return VersePassage(referenceLabel: label, text: text)
    }

    func fetch(book: String, chapter: Int, verseStart: Int, verseEnd: Int) async throws -> VersePassage {
        let label = Self.referenceLabel(book: book, chapter: chapter,
                                        verseStart: verseStart, verseEnd: verseEnd)
        if let hit = cache[label] { return hit }

        let range = verseEnd > verseStart ? "\(verseStart)-\(verseEnd)" : "\(verseStart)"
        var components = URLComponents(string: "https://bible-api.com/")!
        components.path = "/\(book) \(chapter):\(range)"
        components.queryItems = [URLQueryItem(name: "translation", value: "web")]
        guard let url = components.url else { throw BibleError.notFound }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw BibleError.network
        }
        guard let http = response as? HTTPURLResponse else { throw BibleError.network }
        guard http.statusCode == 200 else {
            throw http.statusCode == 404 ? BibleError.notFound : BibleError.network
        }

        let passage = try Self.parse(data, label: label)
        cache[label] = passage
        return passage
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:BibleShareTests/BibleServiceTests 2>&1 | tail -20
```
Expected: PASS (4 tests). Note `parse` is `static` and `nonisolated` by virtue of being static — the tests call it without `await`.

- [ ] **Step 5: Commit**

```bash
git add Services/BibleService.swift BibleShareTests/BibleServiceTests.swift
git commit -m "feat(services): BibleService — WEB passage fetch with cache"
```

---

## Task 5: Service protocols & live implementations

**Files:**
- Create: `Services/SocialServicing.swift`
- Create: `Services/PostService.swift`
- Create: `Services/FeedService.swift`
- Create: `Services/MediaUploader.swift`
- Create: `Services/ImageProcessor.swift`

**Interfaces:**
- Consumes: `SupabaseService.shared.client`; DTOs from Task 3.
- Produces (Swift):
  - `protocol PostServicing: Sendable` — `createEncouragement(_: CreateEncouragementParams) async throws -> UUID`, `deletePost(id: UUID) async throws`, `setLike(postID: UUID, userID: UUID, liked: Bool) async throws`, `fetchComments(postID: UUID) async throws -> [CommentItem]`, `addComment(postID: UUID, userID: UUID, content: String) async throws`
  - `protocol FeedServicing: Sendable` — `fetchTimeline(authorID: UUID, before: Date?, limit: Int) async throws -> [FeedItem]`, `likedPostIDs(userID: UUID, among: [UUID]) async throws -> Set<UUID>`
  - `protocol MediaUploading: Sendable` — `upload(_ jpeg: Data, userID: UUID) async throws -> String`, `delete(paths: [String]) async throws`, `signedURL(path: String) async throws -> URL`
  - `protocol UsernameResolving: Sendable` — `resolveExact(_ username: String) async throws -> Profile?`
  - `enum PostError` with `static func message(for: Error) -> String`
  - `enum ImageProcessor { static func jpegData(from: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? }`
  - Live types: `PostService`, `FeedService`, `MediaUploader`, `ProfileService` — each with `static let shared`.

- [ ] **Step 1: Confirm the resolved supabase-swift Storage API**

The Storage upload signature changed across 2.x. Before writing `MediaUploader`, check the resolved version and its actual signature:

```bash
grep -A2 '"identity" : "supabase-swift"' build/SourcePackages/workspace-state.json | head -5
grep -rn "public func upload(" build/SourcePackages/checkouts/supabase-swift/Sources/Storage/StorageFileApi.swift | head
grep -rn "public func createSignedURL(\|public func remove(" build/SourcePackages/checkouts/supabase-swift/Sources/Storage/StorageFileApi.swift | head
```

Expected: an `upload` taking a path and `data:`, a `remove(paths:)`, and a `createSignedURL(path:expiresIn:)`. **Match the code in Step 4 to what you actually find** — if `upload` is `upload(_ path: String, data: Data, options: FileOptions)`, use that; if it's `upload(path:file:options:)`, adapt. Do not guess.

- [ ] **Step 2: Write the protocol seams and error mapping**

`Services/SocialServicing.swift`:

```swift
import Foundation

/// Protocol seams for the social layer, mirroring `AuthProviding`: live types
/// talk to Supabase, tests substitute fakes.

protocol PostServicing: Sendable {
    func createEncouragement(_ params: CreateEncouragementParams) async throws -> UUID
    func deletePost(id: UUID) async throws
    func setLike(postID: UUID, userID: UUID, liked: Bool) async throws
    func fetchComments(postID: UUID) async throws -> [CommentItem]
    func addComment(postID: UUID, userID: UUID, content: String) async throws
}

protocol FeedServicing: Sendable {
    func fetchTimeline(authorID: UUID, before: Date?, limit: Int) async throws -> [FeedItem]
    func likedPostIDs(userID: UUID, among: [UUID]) async throws -> Set<UUID>
}

protocol MediaUploading: Sendable {
    /// Returns the storage object path (NOT a URL) — this is what post_media.url stores.
    func upload(_ jpeg: Data, userID: UUID) async throws -> String
    func delete(paths: [String]) async throws
    func signedURL(path: String) async throws -> URL
}

protocol UsernameResolving: Sendable {
    /// Exact match only. Plan 2 deliberately exposes no prefix/fuzzy search;
    /// friend-scoped search arrives in Plan 3.
    func resolveExact(_ username: String) async throws -> Profile?
}

enum PostError {
    /// Maps a thrown error to user-facing copy, separating the recoverable
    /// (retry) from the terminal (surface and stop).
    static func message(for error: Error) -> String {
        if error is BibleError { return "Couldn't load that passage. Check the reference and try again." }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return "You appear to be offline. Try again." }
        let text = "\(error)"
        if text.contains("title is required") { return "An encouragement needs a title." }
        if text.contains("own storage folder") { return "That image couldn't be attached. Try picking it again." }
        if text.contains("42501") || text.lowercased().contains("row-level security") {
            return "You don't have permission to do that."
        }
        return "Something went wrong. Please try again."
    }
}
```

- [ ] **Step 3: Write PostService and FeedService**

`Services/PostService.swift`:

```swift
import Foundation
import Supabase

final class PostService: PostServicing {
    static let shared = PostService()

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    func createEncouragement(_ params: CreateEncouragementParams) async throws -> UUID {
        try await client.rpc("create_encouragement", params: params).execute().value
    }

    func deletePost(id: UUID) async throws {
        try await client.from("posts").delete().eq("id", value: id.uuidString).execute()
    }

    func setLike(postID: UUID, userID: UUID, liked: Bool) async throws {
        if liked {
            // PK (user_id, post_id) makes a double-tap race idempotent.
            try await client.from("likes")
                .upsert(Like(userID: userID, postID: postID, createdAt: Date()))
                .execute()
        } else {
            try await client.from("likes").delete()
                .eq("user_id", value: userID.uuidString)
                .eq("post_id", value: postID.uuidString)
                .execute()
        }
    }

    func fetchComments(postID: UUID) async throws -> [CommentItem] {
        try await client.from("comments")
            .select("id,post_id,author_id,content,created_at,author:profiles(*)")
            .eq("post_id", value: postID.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func addComment(postID: UUID, userID: UUID, content: String) async throws {
        struct NewComment: Encodable {
            let post_id: String
            let author_id: String
            let content: String
        }
        try await client.from("comments")
            .insert(NewComment(post_id: postID.uuidString,
                               author_id: userID.uuidString,
                               content: content))
            .execute()
    }
}
```

> If `Like`'s `createdAt` is a `let` populated by the DB default, encoding it is harmless — Postgres overwrites nothing since the value is supplied. If the upsert complains about `created_at`, define a local `NewLike: Encodable { let user_id: String; let post_id: String }` and upsert that instead.

`Services/FeedService.swift`:

```swift
import Foundation
import Supabase

final class FeedService: FeedServicing {
    static let shared = FeedService()

    /// The embedded select for a timeline row. RLS (posts_select_visible) is the
    /// only visibility gate — this query adds no auth logic of its own.
    private static let feedSelect = """
    id,author_id,title,body,created_at,\
    author:profiles(*),\
    post_verses(*),\
    post_media(*),\
    post_tags(post_id,tagged_user_id,created_at,profiles(*)),\
    likes(count),\
    comments(count)
    """

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    func fetchTimeline(authorID: UUID, before: Date?, limit: Int) async throws -> [FeedItem] {
        var query = client.from("posts")
            .select(Self.feedSelect)
            .eq("kind", value: "encouragement")
            .eq("shared_to_timeline", value: true)
            // Plan 3 drops this filter and RLS surfaces friends' posts too.
            .eq("author_id", value: authorID.uuidString)

        if let before {
            query = query.lt("created_at", value: ISO8601DateFormatter().string(from: before))
        }

        return try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func likedPostIDs(userID: UUID, among ids: [UUID]) async throws -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        struct Row: Decodable { let post_id: UUID }
        let rows: [Row] = try await client.from("likes")
            .select("post_id")
            .eq("user_id", value: userID.uuidString)
            .in("post_id", values: ids.map(\.uuidString))
            .execute()
            .value
        return Set(rows.map(\.post_id))
    }
}
```

- [ ] **Step 4: Write MediaUploader, ImageProcessor and ProfileService**

`Services/ImageProcessor.swift`:

```swift
import UIKit

/// Pure image resizing/encoding, split out from MediaUploader so it is testable
/// without a network or a Supabase client.
enum ImageProcessor {
    static func jpegData(from image: UIImage,
                         maxDimension: CGFloat = 1600,
                         quality: CGFloat = 0.8) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image.jpegData(compressionQuality: quality) }

        let scale = maxDimension / longest
        let target = CGSize(width: (image.size.width * scale).rounded(),
                            height: (image.size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}
```

`Services/MediaUploader.swift` (adjust the calls to the signatures confirmed in Step 1):

```swift
import Foundation
import Supabase

final class MediaUploader: MediaUploading {
    static let shared = MediaUploader()

    private static let bucket = "media"

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    func upload(_ jpeg: Data, userID: UUID) async throws -> String {
        // LOWERCASE: the storage policy compares against auth.uid()::text, which
        // Postgres renders lowercase. UUID.uuidString is uppercase — a raw
        // uuidString here makes every upload fail the folder-ownership check.
        let path = "\(userID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await client.storage
            .from(Self.bucket)
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
        return path
    }

    func delete(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await client.storage.from(Self.bucket).remove(paths: paths)
    }

    func signedURL(path: String) async throws -> URL {
        try await client.storage.from(Self.bucket).createSignedURL(path: path, expiresIn: 3600)
    }
}

final class ProfileService: UsernameResolving {
    static let shared = ProfileService()

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
    }

    /// Exact match, one row max. No `like`/`ilike` — Plan 2 ships no search surface.
    func resolveExact(_ username: String) async throws -> Profile? {
        let cleaned = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        guard !cleaned.isEmpty else { return nil }

        let rows: [Profile] = try await client.from("profiles")
            .select()
            .eq("username", value: cleaned)
            .limit(1)
            .execute()
            .value
        return rows.first
    }
}
```

- [ ] **Step 5: Build to verify it compiles**

Run:
```bash
make generate
xcodebuild build -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`. Under `SWIFT_STRICT_CONCURRENCY: complete`, if a `Sendable` conformance is rejected on a class holding `SupabaseClient`, mark the service `final class ... : @unchecked Sendable` — the client is internally thread-safe and each service is stateless.

- [ ] **Step 6: Commit**

```bash
git add Services/SocialServicing.swift Services/PostService.swift Services/FeedService.swift \
        Services/MediaUploader.swift Services/ImageProcessor.swift
git commit -m "feat(services): post/feed/media/profile services behind protocol seams"
```

---

## Task 6: ComposeViewModel

**Files:**
- Create: `ViewModels/ComposeViewModel.swift`
- Test: `BibleShareTests/FakeSocialServices.swift`
- Test: `BibleShareTests/ComposeViewModelTests.swift`

**Interfaces:**
- Consumes: `PostServicing`, `MediaUploading`, `UsernameResolving`, `BibleFetching` (Tasks 4–5); DTOs (Task 3).
- Produces (Swift): `@MainActor @Observable final class ComposeViewModel` — `title`, `body`, `sharedToTimeline`, `verses: [NewVerse]`, `links: [NewMediaItem]`, `pendingImages: [ComposeImage]`, `taggedUsers: [Profile]`, `isSubmitting`, `errorMessage`, `canSubmit`, `canAddImage`, `static let maxImages = 4`, `addVerse(book:chapter:verseStart:verseEnd:) async`, `addTag(username:) async`, `submit(userID:) async -> UUID?`
- Produces (Swift): `struct ComposeImage: Identifiable, Hashable, Sendable { let id: UUID; let jpeg: Data }`

- [ ] **Step 1: Write the fakes**

`BibleShareTests/FakeSocialServices.swift`:

```swift
import Foundation
@testable import BibleShare

/// Records what it was asked to do; fails on demand.
final class FakePostService: PostServicing, @unchecked Sendable {
    var createError: Error?
    var deleteError: Error?
    var likeError: Error?
    private(set) var createdParams: [CreateEncouragementParams] = []
    private(set) var deletedPosts: [UUID] = []
    private(set) var likeCalls: [(postID: UUID, liked: Bool)] = []
    private(set) var addedComments: [(postID: UUID, content: String)] = []
    var comments: [CommentItem] = []
    let newPostID = UUID()

    func createEncouragement(_ params: CreateEncouragementParams) async throws -> UUID {
        createdParams.append(params)
        if let createError { throw createError }
        return newPostID
    }
    func deletePost(id: UUID) async throws {
        if let deleteError { throw deleteError }
        deletedPosts.append(id)
    }
    func setLike(postID: UUID, userID: UUID, liked: Bool) async throws {
        likeCalls.append((postID, liked))
        if let likeError { throw likeError }
    }
    func fetchComments(postID: UUID) async throws -> [CommentItem] { comments }
    func addComment(postID: UUID, userID: UUID, content: String) async throws {
        addedComments.append((postID, content))
    }
}

final class FakeMediaUploader: MediaUploading, @unchecked Sendable {
    var uploadError: Error?
    private(set) var uploadCount = 0
    private(set) var deletedPaths: [String] = []

    func upload(_ jpeg: Data, userID: UUID) async throws -> String {
        if let uploadError { throw uploadError }
        uploadCount += 1
        return "\(userID.uuidString.lowercased())/img\(uploadCount).jpg"
    }
    func delete(paths: [String]) async throws { deletedPaths.append(contentsOf: paths) }
    func signedURL(path: String) async throws -> URL { URL(string: "https://example.com/\(path)")! }
}

final class FakeUsernameResolver: UsernameResolving, @unchecked Sendable {
    var profiles: [String: Profile] = [:]
    func resolveExact(_ username: String) async throws -> Profile? {
        profiles[username.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()]
    }
}

final class FakeBibleService: BibleFetching, @unchecked Sendable {
    var error: Error?
    var passage = VersePassage(referenceLabel: "Joshua 1:9", text: "Be strong and courageous.")
    func fetch(book: String, chapter: Int, verseStart: Int, verseEnd: Int) async throws -> VersePassage {
        if let error { throw error }
        return passage
    }
}

final class FakeFeedService: FeedServicing, @unchecked Sendable {
    var pages: [[FeedItem]] = []
    var liked: Set<UUID> = []
    var error: Error?
    private(set) var fetchCount = 0

    func fetchTimeline(authorID: UUID, before: Date?, limit: Int) async throws -> [FeedItem] {
        if let error { throw error }
        defer { fetchCount += 1 }
        return fetchCount < pages.count ? pages[fetchCount] : []
    }
    func likedPostIDs(userID: UUID, among ids: [UUID]) async throws -> Set<UUID> {
        liked.intersection(ids)
    }
}

/// Builds a FeedItem without going through the network payload.
enum FeedItemFactory {
    static func make(id: UUID = UUID(),
                     authorID: UUID = UUID(),
                     title: String = "Title",
                     createdAt: Date = Date(),
                     likeCount: Int = 0,
                     isLiked: Bool = false) throws -> FeedItem {
        let json = """
        {"id":"\(id.uuidString.lowercased())","author_id":"\(authorID.uuidString.lowercased())",
         "title":"\(title)","body":null,
         "created_at":"\(ISO8601DateFormatter().string(from: createdAt))",
         "author":null,"post_verses":[],"post_media":[],"post_tags":[],
         "likes":[{"count":\(likeCount)}],"comments":[{"count":0}]}
        """.data(using: .utf8)!
        var item = try TestDecoder.postgrest().decode(FeedItem.self, from: json)
        item.isLiked = isLiked
        return item
    }
}
```

- [ ] **Step 2: Write the failing ComposeViewModel tests**

`BibleShareTests/ComposeViewModelTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleShare

@MainActor
struct ComposeViewModelTests {

    private func makeVM(posts: FakePostService = FakePostService(),
                        uploader: FakeMediaUploader = FakeMediaUploader(),
                        resolver: FakeUsernameResolver = FakeUsernameResolver(),
                        bible: FakeBibleService = FakeBibleService()) -> ComposeViewModel {
        ComposeViewModel(posts: posts, uploader: uploader, resolver: resolver, bible: bible)
    }

    @Test func requiresATitle() {
        let vm = makeVM()
        #expect(vm.canSubmit == false)
        vm.title = "   "
        #expect(vm.canSubmit == false, "whitespace is not a title")
        vm.title = "Be strong"
        #expect(vm.canSubmit == true)
    }

    @Test func trimsTitleAndDropsEmptyBody() async throws {
        let posts = FakePostService()
        let vm = makeVM(posts: posts)
        vm.title = "  Be strong  "
        vm.body = "   "
        _ = await vm.submit(userID: UUID())

        let params = try #require(posts.createdParams.first)
        #expect(params.title == "Be strong")
        #expect(params.body == nil, "a whitespace-only body must send null, not blanks")
    }

    @Test func capsImagesAtFour() {
        let vm = makeVM()
        for _ in 0..<ComposeViewModel.maxImages {
            #expect(vm.canAddImage == true)
            vm.pendingImages.append(ComposeImage(id: UUID(), jpeg: Data([0x1])))
        }
        #expect(vm.canAddImage == false)
    }

    @Test func submitUploadsImagesAndSendsTheirPaths() async throws {
        let posts = FakePostService()
        let uploader = FakeMediaUploader()
        let vm = makeVM(posts: posts, uploader: uploader)
        vm.title = "With photos"
        vm.pendingImages = [ComposeImage(id: UUID(), jpeg: Data([0x1])),
                            ComposeImage(id: UUID(), jpeg: Data([0x2]))]

        let id = await vm.submit(userID: UUID())
        #expect(id == posts.newPostID)
        #expect(uploader.uploadCount == 2)

        let params = try #require(posts.createdParams.first)
        #expect(params.media.count == 2)
        #expect(params.media.map(\.position) == [0, 1])
        #expect(params.media.allSatisfy { $0.mediaType == .image })
    }

    /// The orphan-free contract from spec §5.1: if the RPC fails after uploads
    /// succeeded, the just-uploaded objects must be deleted.
    @Test func failedSubmitDeletesUploadedImagesAndKeepsDraft() async {
        struct RPCFailure: Error {}
        let posts = FakePostService()
        posts.createError = RPCFailure()
        let uploader = FakeMediaUploader()
        let vm = makeVM(posts: posts, uploader: uploader)
        vm.title = "Doomed"
        vm.pendingImages = [ComposeImage(id: UUID(), jpeg: Data([0x1]))]

        let id = await vm.submit(userID: UUID())

        #expect(id == nil)
        #expect(uploader.deletedPaths.count == 1, "the orphaned object must be swept")
        #expect(vm.title == "Doomed", "the draft must survive a failed submit")
        #expect(vm.errorMessage != nil)
        #expect(vm.isSubmitting == false)
    }

    @Test func addVerseFetchesSnapshotAndLabel() async throws {
        let bible = FakeBibleService()
        let vm = makeVM(bible: bible)
        await vm.addVerse(book: "Joshua", chapter: 1, verseStart: 9, verseEnd: 9)

        let verse = try #require(vm.verses.first)
        #expect(verse.referenceLabel == "Joshua 1:9")
        #expect(verse.textSnapshot == "Be strong and courageous.")
        #expect(verse.position == 0)
    }

    @Test func addVerseSurfacesFetchFailureWithoutAddingAnything() async {
        let bible = FakeBibleService()
        bible.error = BibleError.notFound
        let vm = makeVM(bible: bible)
        await vm.addVerse(book: "Nope", chapter: 1, verseStart: 1, verseEnd: 1)

        #expect(vm.verses.isEmpty, "never attach a verse with an empty snapshot")
        #expect(vm.errorMessage != nil)
    }

    @Test func addTagResolvesExactUsername() async throws {
        let resolver = FakeUsernameResolver()
        let bob = try TestDecoder.postgrest().decode(Profile.self, from: """
        {"id":"bbbbbbbb-0000-0000-0000-000000000002","username":"bob","username_set":true,
         "display_name":null,"avatar_url":null,"bio":null,"created_at":"2026-07-01T12:00:00Z"}
        """.data(using: .utf8)!)
        resolver.profiles["bob"] = bob
        let vm = makeVM(resolver: resolver)

        await vm.addTag(username: "@bob")
        #expect(vm.taggedUsers.map(\.username) == ["bob"])

        await vm.addTag(username: "@bob")
        #expect(vm.taggedUsers.count == 1, "tagging the same user twice is a no-op")

        await vm.addTag(username: "@nobody")
        #expect(vm.taggedUsers.count == 1)
        #expect(vm.errorMessage != nil, "an unknown username is an error, not a silent drop")
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run:
```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:BibleShareTests/ComposeViewModelTests 2>&1 | tail -20
```
Expected: FAIL — `cannot find 'ComposeViewModel' in scope`.

- [ ] **Step 4: Implement ComposeViewModel**

`ViewModels/ComposeViewModel.swift`:

```swift
import Foundation

/// An image picked but not yet uploaded. Held as encoded JPEG bytes so the
/// ViewModel stays free of UIKit and is testable.
struct ComposeImage: Identifiable, Hashable, Sendable {
    let id: UUID
    let jpeg: Data
}

@MainActor
@Observable
final class ComposeViewModel {
    static let maxImages = 4

    var title = ""
    var body = ""
    var sharedToTimeline = true
    var verses: [NewVerse] = []
    var links: [NewMediaItem] = []
    var pendingImages: [ComposeImage] = []
    var taggedUsers: [Profile] = []
    private(set) var isSubmitting = false
    var errorMessage: String?

    private let posts: PostServicing
    private let uploader: MediaUploading
    private let resolver: UsernameResolving
    private let bible: BibleFetching

    init(posts: PostServicing = PostService.shared,
         uploader: MediaUploading = MediaUploader.shared,
         resolver: UsernameResolving = ProfileService.shared,
         bible: BibleFetching = BibleService.shared) {
        self.posts = posts
        self.uploader = uploader
        self.resolver = resolver
        self.bible = bible
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool { !trimmedTitle.isEmpty && !isSubmitting }
    var canAddImage: Bool { pendingImages.count < Self.maxImages }

    // MARK: Attachments

    func addVerse(book: String, chapter: Int, verseStart: Int, verseEnd: Int) async {
        errorMessage = nil
        do {
            let passage = try await bible.fetch(book: book, chapter: chapter,
                                                verseStart: verseStart, verseEnd: verseEnd)
            verses.append(NewVerse(book: book,
                                   chapter: chapter,
                                   verseStart: verseStart,
                                   verseEnd: max(verseEnd, verseStart),
                                   referenceLabel: passage.referenceLabel,
                                   textSnapshot: passage.text,
                                   position: verses.count))
        } catch {
            // Never attach a verse with an empty snapshot — the post would render blank forever.
            errorMessage = PostError.message(for: error)
        }
    }

    func removeVerse(id: UUID) {
        verses.removeAll { $0.id == id }
        for index in verses.indices { verses[index].position = index }
    }

    func addTag(username: String) async {
        errorMessage = nil
        do {
            guard let profile = try await resolver.resolveExact(username) else {
                errorMessage = "No user named \(username.hasPrefix("@") ? username : "@" + username)."
                return
            }
            guard !taggedUsers.contains(where: { $0.id == profile.id }) else { return }
            taggedUsers.append(profile)
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func addLink(url: String, title: String?) {
        links.append(NewMediaItem(mediaType: .link,
                                  url: url,
                                  thumbnailURL: nil,
                                  title: title,
                                  description: nil,
                                  position: 0))   // real positions assigned at submit
    }

    // MARK: Submit

    /// Uploads images, then writes the post. On failure, sweeps the objects it
    /// just uploaded and keeps the draft intact (spec §5.1).
    func submit(userID: UUID) async -> UUID? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        var uploadedPaths: [String] = []
        do {
            for image in pendingImages {
                uploadedPaths.append(try await uploader.upload(image.jpeg, userID: userID))
            }

            var media = uploadedPaths.enumerated().map { index, path in
                NewMediaItem(mediaType: .image, url: path, thumbnailURL: nil,
                             title: nil, description: nil, position: index)
            }
            media += links.enumerated().map { index, link in
                NewMediaItem(mediaType: .link, url: link.url, thumbnailURL: link.thumbnailURL,
                             title: link.title, description: link.description,
                             position: uploadedPaths.count + index)
            }

            let params = CreateEncouragementParams(
                title: trimmedTitle,
                body: {
                    let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? nil : t
                }(),
                sharedToTimeline: sharedToTimeline,
                verses: verses,
                media: media,
                tagUserIDs: taggedUsers.map(\.id)
            )
            return try await posts.createEncouragement(params)
        } catch {
            // Compensating delete: without this, every failed submit strands objects.
            try? await uploader.delete(paths: uploadedPaths)
            errorMessage = PostError.message(for: error)
            return nil
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:BibleShareTests/ComposeViewModelTests 2>&1 | tail -20
```
Expected: PASS (8 tests).

- [ ] **Step 6: Commit**

```bash
git add ViewModels/ComposeViewModel.swift BibleShareTests/ComposeViewModelTests.swift \
        BibleShareTests/FakeSocialServices.swift
git commit -m "feat(compose): ComposeViewModel with orphan-free submit"
```

---

## Task 7: TimelineViewModel

**Files:**
- Create: `ViewModels/TimelineViewModel.swift`
- Test: `BibleShareTests/TimelineViewModelTests.swift`

**Interfaces:**
- Consumes: `FeedServicing`, `PostServicing` (Task 5); `FeedItem` (Task 3); fakes + `FeedItemFactory` (Task 6).
- Produces (Swift): `@MainActor @Observable final class TimelineViewModel` — `items: [FeedItem]`, `isLoading`, `isLoadingMore`, `hasMore`, `errorMessage`, `load(userID:) async`, `loadMore(userID:) async`, `toggleLike(itemID:userID:) async`, `delete(itemID:) async`, `insert(_ item: FeedItem)`, `static let pageSize = 20`

- [ ] **Step 1: Write the failing tests**

`BibleShareTests/TimelineViewModelTests.swift`:

```swift
import Testing
import Foundation
@testable import BibleShare

@MainActor
struct TimelineViewModelTests {

    @Test func loadPopulatesItemsAndMarksLiked() async throws {
        let me = UUID()
        let liked = try FeedItemFactory.make(authorID: me, title: "Liked", likeCount: 2)
        let plain = try FeedItemFactory.make(authorID: me, title: "Plain", likeCount: 0)
        let feed = FakeFeedService()
        feed.pages = [[liked, plain]]
        feed.liked = [liked.id]

        let vm = TimelineViewModel(feed: feed, posts: FakePostService())
        await vm.load(userID: me)

        #expect(vm.items.count == 2)
        #expect(vm.items.first(where: { $0.id == liked.id })?.isLiked == true)
        #expect(vm.items.first(where: { $0.id == plain.id })?.isLiked == false)
        #expect(vm.isLoading == false)
    }

    @Test func loadSurfacesErrors() async {
        struct Boom: Error {}
        let feed = FakeFeedService()
        feed.error = Boom()
        let vm = TimelineViewModel(feed: feed, posts: FakePostService())
        await vm.load(userID: UUID())

        #expect(vm.items.isEmpty)
        #expect(vm.errorMessage != nil)
        #expect(vm.isLoading == false)
    }

    /// A short page means the end of the feed.
    @Test func shortPageClearsHasMore() async throws {
        let feed = FakeFeedService()
        feed.pages = [[try FeedItemFactory.make()]]
        let vm = TimelineViewModel(feed: feed, posts: FakePostService())
        await vm.load(userID: UUID())

        #expect(vm.hasMore == false)
    }

    @Test func toggleLikeUpdatesOptimistically() async throws {
        let item = try FeedItemFactory.make(likeCount: 2, isLiked: false)
        let feed = FakeFeedService()
        feed.pages = [[item]]
        let posts = FakePostService()
        let vm = TimelineViewModel(feed: feed, posts: posts)
        await vm.load(userID: UUID())

        await vm.toggleLike(itemID: item.id, userID: UUID())
        #expect(vm.items[0].isLiked == true)
        #expect(vm.items[0].likeCount == 3)
        #expect(posts.likeCalls.map(\.liked) == [true])

        await vm.toggleLike(itemID: item.id, userID: UUID())
        #expect(vm.items[0].isLiked == false)
        #expect(vm.items[0].likeCount == 2)
    }

    /// The optimistic update must not survive a server rejection.
    @Test func failedLikeRevertsCountAndFlag() async throws {
        struct Boom: Error {}
        let item = try FeedItemFactory.make(likeCount: 2, isLiked: false)
        let feed = FakeFeedService()
        feed.pages = [[item]]
        let posts = FakePostService()
        posts.likeError = Boom()
        let vm = TimelineViewModel(feed: feed, posts: posts)
        await vm.load(userID: UUID())

        await vm.toggleLike(itemID: item.id, userID: UUID())
        #expect(vm.items[0].isLiked == false, "the flag must revert")
        #expect(vm.items[0].likeCount == 2, "the count must revert")
        #expect(vm.errorMessage != nil)
    }

    @Test func deleteRemovesItem() async throws {
        let item = try FeedItemFactory.make()
        let feed = FakeFeedService()
        feed.pages = [[item]]
        let posts = FakePostService()
        let vm = TimelineViewModel(feed: feed, posts: posts)
        await vm.load(userID: UUID())

        await vm.delete(itemID: item.id)
        #expect(vm.items.isEmpty)
        #expect(posts.deletedPosts == [item.id])
    }

    @Test func insertPutsNewPostOnTop() async throws {
        let existing = try FeedItemFactory.make(title: "Old")
        let feed = FakeFeedService()
        feed.pages = [[existing]]
        let vm = TimelineViewModel(feed: feed, posts: FakePostService())
        await vm.load(userID: UUID())

        vm.insert(try FeedItemFactory.make(title: "New"))
        #expect(vm.items.map(\.title) == ["New", "Old"])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:BibleShareTests/TimelineViewModelTests 2>&1 | tail -20
```
Expected: FAIL — `cannot find 'TimelineViewModel' in scope`.

- [ ] **Step 3: Implement TimelineViewModel**

`ViewModels/TimelineViewModel.swift`:

```swift
import Foundation

@MainActor
@Observable
final class TimelineViewModel {
    static let pageSize = 20

    private(set) var items: [FeedItem] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    var errorMessage: String?

    private let feed: FeedServicing
    private let posts: PostServicing

    init(feed: FeedServicing = FeedService.shared,
         posts: PostServicing = PostService.shared) {
        self.feed = feed
        self.posts = posts
    }

    func load(userID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await feed.fetchTimeline(authorID: userID, before: nil, limit: Self.pageSize)
            items = try await markLiked(page, userID: userID)
            hasMore = page.count == Self.pageSize
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func loadMore(userID: UUID) async {
        guard hasMore, !isLoading, !isLoadingMore, let cursor = items.last?.createdAt else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await feed.fetchTimeline(authorID: userID, before: cursor, limit: Self.pageSize)
            items += try await markLiked(page, userID: userID)
            hasMore = page.count == Self.pageSize
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    /// `likes(count)` gives the tally but not membership, so ask which of these
    /// posts the viewer has liked.
    private func markLiked(_ page: [FeedItem], userID: UUID) async throws -> [FeedItem] {
        guard !page.isEmpty else { return page }
        let liked = try await feed.likedPostIDs(userID: userID, among: page.map(\.id))
        return page.map { item in
            var copy = item
            copy.isLiked = liked.contains(item.id)
            return copy
        }
    }

    func toggleLike(itemID: UUID, userID: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let wasLiked = items[index].isLiked
        let target = !wasLiked

        // Optimistic.
        items[index].isLiked = target
        items[index].likeCount += target ? 1 : -1

        do {
            try await posts.setLike(postID: itemID, userID: userID, liked: target)
        } catch {
            // Revert — the row index may have shifted while awaiting.
            if let current = items.firstIndex(where: { $0.id == itemID }) {
                items[current].isLiked = wasLiked
                items[current].likeCount += target ? -1 : 1
            }
            errorMessage = PostError.message(for: error)
        }
    }

    func delete(itemID: UUID) async {
        do {
            try await posts.deletePost(id: itemID)
            items.removeAll { $0.id == itemID }
        } catch {
            errorMessage = PostError.message(for: error)
        }
    }

    func insert(_ item: FeedItem) {
        items.insert(item, at: 0)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:BibleShareTests/TimelineViewModelTests 2>&1 | tail -20
```
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add ViewModels/TimelineViewModel.swift BibleShareTests/TimelineViewModelTests.swift
git commit -m "feat(feed): TimelineViewModel with optimistic likes and paging"
```

---

## Task 8: Post cell and its components

**Files:**
- Create: `Views/Components/RemoteImage.swift`
- Create: `Views/Components/VerseCard.swift`
- Create: `Views/Components/MediaStrip.swift`
- Create: `Views/Components/PostCell.swift`

**Interfaces:**
- Consumes: `FeedItem`, `PostVerse`, `PostMedia` (Task 3); `MediaUploading.signedURL` (Task 5); `Theme` (`Views/Theme.swift`).
- Produces (SwiftUI): `RemoteImage(path:)`, `VerseCard(verse:)`, `MediaStrip(media:)`, `PostCell(item:onLike:onComment:onDelete:isMine:)`.

- [ ] **Step 1: Write RemoteImage (signed-URL loader)**

`Views/Components/RemoteImage.swift`:

```swift
import SwiftUI

/// Loads a private `media` object by asking for a short-lived signed URL.
/// The bucket is private, so AsyncImage cannot hit the path directly.
struct RemoteImage: View {
    let path: String
    var uploader: MediaUploading = MediaUploader.shared

    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                placeholder.overlay(
                    Image(systemName: "photo").foregroundStyle(Theme.muted)
                )
            } else if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: placeholder
                    default: placeholder.overlay(ProgressView().tint(Theme.muted))
                    }
                }
            } else {
                placeholder.overlay(ProgressView().tint(Theme.muted))
            }
        }
        .task(id: path) {
            failed = false
            url = nil
            do { url = try await uploader.signedURL(path: path) }
            catch { failed = true }
        }
    }

    private var placeholder: some View {
        Rectangle().fill(Theme.hairline.opacity(0.5))
    }
}
```

- [ ] **Step 2: Write VerseCard and MediaStrip**

`Views/Components/VerseCard.swift`:

```swift
import SwiftUI

/// A scripture attachment. Renders `text_snapshot`, never a live fetch.
struct VerseCard: View {
    let verse: PostVerse

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verse.referenceLabel)
                .font(.system(.caption, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.indigo)
            Text(verse.textSnapshot)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.field)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline)
        )
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.indigo).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }
}
```

`Views/Components/MediaStrip.swift`:

```swift
import SwiftUI

struct MediaStrip: View {
    let media: [PostMedia]

    private var images: [PostMedia] { media.filter { $0.mediaType == .image } }
    private var links: [PostMedia] { media.filter { $0.mediaType == .link } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(images) { item in
                            RemoteImage(path: item.url)
                                .frame(width: 200, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                        }
                    }
                }
            }
            ForEach(links) { link in
                if let url = URL(string: link.url) {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "link").foregroundStyle(Theme.indigo)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.title ?? link.url)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text(url.host() ?? link.url)
                                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Theme.field)
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Write PostCell**

`Views/Components/PostCell.swift`:

```swift
import SwiftUI

struct PostCell: View {
    let item: FeedItem
    let isMine: Bool
    let onLike: () -> Void
    let onComment: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let title = item.title {
                Text(title)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Theme.ink)
            }
            if let body = item.body, !body.isEmpty {
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(item.verses) { VerseCard(verse: $0) }

            if !item.media.isEmpty { MediaStrip(media: item.media) }

            if !item.tags.isEmpty {
                Text("with " + item.tags.compactMap { $0.profile?.username }.map { "@\($0)" }
                        .joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            actions
        }
        .padding(16)
        .background(Theme.field)
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.indigo).frame(width: 28, height: 28)
                .overlay(
                    Text(String(item.author?.username.prefix(1) ?? "?").uppercased())
                        .font(.caption2).foregroundStyle(.white)
                )
            Text("@\(item.author?.username ?? "unknown")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(item.createdAt, format: .relative(presentation: .named))
                .font(.caption).foregroundStyle(Theme.muted)
            Spacer()
            if isMine {
                Menu {
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.muted)
                        .frame(width: 28, height: 28)     // tap target
                        .contentShape(Rectangle())
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 20) {
            Button(action: onLike) {
                HStack(spacing: 5) {
                    Image(systemName: item.isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(item.isLiked ? Theme.danger : Theme.muted)
                    Text("\(item.likeCount)").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isLiked ? "Unlike" : "Like")

            Button(action: onComment) {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.right").foregroundStyle(Theme.muted)
                    Text("\(item.commentCount)").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comments")

            Spacer()
        }
        .padding(.top, 2)
    }
}
```

- [ ] **Step 4: Build to verify it compiles**

Run:
```bash
make generate
xcodebuild build -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Views/Components/RemoteImage.swift Views/Components/VerseCard.swift \
        Views/Components/MediaStrip.swift Views/Components/PostCell.swift
git commit -m "feat(ui): post cell with verse cards, media strip and signed-URL images"
```

---

## Task 9: Compose screen, verse picker and tag sheet

**Files:**
- Create: `Views/Sheets/VersePickerSheet.swift`
- Create: `Views/Sheets/UserTagSheet.swift`
- Create: `Views/ComposeEncouragementView.swift`

**Interfaces:**
- Consumes: `ComposeViewModel` (Task 6), `ImageProcessor` (Task 5), `Theme`, `SereneTextField`, `PrimaryButton`.
- Produces (SwiftUI): `VersePickerSheet(onAdd:)`, `UserTagSheet(onAdd:)`, `ComposeEncouragementView(userID:onPosted:)`.

- [ ] **Step 1: Write VersePickerSheet**

`Views/Sheets/VersePickerSheet.swift`:

```swift
import SwiftUI

/// Structured reference entry (spec §10: no fuzzy search in v1).
struct VersePickerSheet: View {
    let onAdd: (String, Int, Int, Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var book = ""
    @State private var chapter = ""
    @State private var verseStart = ""
    @State private var verseEnd = ""
    @State private var isAdding = false

    private var parsed: (String, Int, Int, Int)? {
        let b = book.trimmingCharacters(in: .whitespaces)
        guard !b.isEmpty,
              let c = Int(chapter), c > 0,
              let s = Int(verseStart), s > 0 else { return nil }
        let e = Int(verseEnd) ?? s
        return (b, c, s, max(e, s))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                SereneTextField(title: "Book (e.g. John)", text: $book)
                    .textInputAutocapitalization(.words)
                HStack(spacing: 10) {
                    SereneTextField(title: "Chapter", text: $chapter, keyboard: .numberPad)
                    SereneTextField(title: "Verse", text: $verseStart, keyboard: .numberPad)
                    SereneTextField(title: "To (optional)", text: $verseEnd, keyboard: .numberPad)
                }
                Text("Passages come from the World English Bible.")
                    .font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                PrimaryButton(title: "Add verse", isLoading: isAdding) {
                    guard let (b, c, s, e) = parsed else { return }
                    Task {
                        isAdding = true
                        await onAdd(b, c, s, e)
                        isAdding = false
                        dismiss()
                    }
                }
                .disabled(parsed == nil || isAdding)
                .opacity(parsed == nil ? 0.5 : 1)
            }
            .padding(20)
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Add a verse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Write UserTagSheet**

`Views/Sheets/UserTagSheet.swift`:

```swift
import SwiftUI

/// Exact `@username` entry. Plan 2 ships no user search; Plan 3 adds
/// search scoped to the viewer's accepted friends.
struct UserTagSheet: View {
    let onAdd: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                SereneTextField(title: "username", text: $username)
                Text("Enter the exact username of the person you want to tag.")
                    .font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                PrimaryButton(title: "Tag", isLoading: isAdding) {
                    Task {
                        isAdding = true
                        await onAdd(username)
                        isAdding = false
                        dismiss()
                    }
                }
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
            }
            .padding(20)
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Tag someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
```

- [ ] **Step 3: Write ComposeEncouragementView**

`Views/ComposeEncouragementView.swift`:

```swift
import SwiftUI
import PhotosUI

struct ComposeEncouragementView: View {
    let userID: UUID
    /// Called with the new post's id after a successful write.
    let onPosted: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vm = ComposeViewModel()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showVersePicker = false
    @State private var showTagSheet = false
    @State private var linkURL = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Theme.danger.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                    }

                    SereneTextField(title: "Title (required)", text: $vm.title)
                        .textInputAutocapitalization(.sentences)

                    TextEditor(text: $vm.body)
                        .frame(minHeight: 110)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Theme.field)
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                        .overlay(alignment: .topLeading) {
                            if vm.body.isEmpty {
                                Text("Share an encouragement…")
                                    .font(.body).foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 13).padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }

                    attachmentBar

                    ForEach(vm.verses) { verse in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verse.referenceLabel)
                                    .font(.system(.caption, design: .serif).weight(.semibold))
                                    .foregroundStyle(Theme.indigo)
                                Text(verse.textSnapshot)
                                    .font(.system(.caption, design: .serif))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(3)
                            }
                            Spacer()
                            Button { vm.removeVerse(id: verse.id) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(10)
                        .background(Theme.field)
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                    }

                    if !vm.pendingImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(vm.pendingImages) { image in
                                    if let ui = UIImage(data: image.jpeg) {
                                        Image(uiImage: ui)
                                            .resizable().scaledToFill()
                                            .frame(width: 90, height: 90)
                                            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                                            .overlay(alignment: .topTrailing) {
                                                Button {
                                                    vm.pendingImages.removeAll { $0.id == image.id }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundStyle(.white)
                                                        .shadow(radius: 2)
                                                }
                                                .padding(4)
                                            }
                                    }
                                }
                            }
                        }
                    }

                    if !vm.taggedUsers.isEmpty {
                        HStack {
                            ForEach(vm.taggedUsers) { user in
                                Text("@\(user.username)")
                                    .font(.caption)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Theme.hairline.opacity(0.5))
                                    .clipShape(Capsule())
                                    .onTapGesture { vm.taggedUsers.removeAll { $0.id == user.id } }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        SereneTextField(title: "Add a link (optional)", text: $linkURL, keyboard: .URL)
                        Button("Add") {
                            let trimmed = linkURL.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            vm.addLink(url: trimmed, title: nil)
                            linkURL = ""
                        }
                        .foregroundStyle(Theme.indigo)
                    }

                    ForEach(Array(vm.links.enumerated()), id: \.offset) { index, link in
                        HStack {
                            Image(systemName: "link").foregroundStyle(Theme.indigo)
                            Text(link.url).font(.caption).lineLimit(1).foregroundStyle(Theme.ink)
                            Spacer()
                            Button { vm.links.remove(at: index) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                            }
                        }
                    }

                    Toggle("Show on my timeline", isOn: $vm.sharedToTimeline)
                        .font(.subheadline)
                        .tint(Theme.indigo)

                    PrimaryButton(title: "Post", isLoading: vm.isSubmitting) {
                        Task {
                            if let id = await vm.submit(userID: userID) {
                                onPosted(id)
                                dismiss()
                            }
                            // On failure the draft stays put and vm.errorMessage shows.
                        }
                    }
                    .disabled(!vm.canSubmit)
                    .opacity(vm.canSubmit ? 1 : 0.5)
                }
                .padding(20)
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("New encouragement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showVersePicker) {
                VersePickerSheet { book, chapter, start, end in
                    await vm.addVerse(book: book, chapter: chapter, verseStart: start, verseEnd: end)
                }
            }
            .sheet(isPresented: $showTagSheet) {
                UserTagSheet { username in await vm.addTag(username: username) }
            }
            .onChange(of: photoItems) { _, items in
                Task { await loadPhotos(items) }
            }
        }
    }

    private var attachmentBar: some View {
        HStack(spacing: 12) {
            Button { showVersePicker = true } label: {
                Label("Verse", systemImage: "book.closed")
            }
            PhotosPicker(selection: $photoItems,
                         maxSelectionCount: ComposeViewModel.maxImages,
                         matching: .images) {
                Label("Photo", systemImage: "photo")
            }
            .disabled(!vm.canAddImage)
            Button { showTagSheet = true } label: {
                Label("Tag", systemImage: "person")
            }
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(Theme.indigo)
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard vm.canAddImage else { break }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data),
                  let jpeg = ImageProcessor.jpegData(from: ui) else { continue }
            vm.pendingImages.append(ComposeImage(id: UUID(), jpeg: jpeg))
        }
        photoItems = []
    }
}
```

- [ ] **Step 4: Build to verify it compiles**

Run:
```bash
make generate
xcodebuild build -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Views/ComposeEncouragementView.swift Views/Sheets/VersePickerSheet.swift \
        Views/Sheets/UserTagSheet.swift
git commit -m "feat(ui): compose encouragement screen with verse/photo/tag/link attachments"
```

---

## Task 10: Comments

**Files:**
- Create: `ViewModels/CommentsViewModel.swift`
- Create: `Views/CommentsView.swift`

**Interfaces:**
- Consumes: `PostServicing.fetchComments` / `.addComment` (Task 5), `CommentItem` (Task 3).
- Produces (Swift): `@MainActor @Observable final class CommentsViewModel` — `comments: [CommentItem]`, `draft: String`, `isLoading`, `isSending`, `errorMessage`, `canSend`, `load(postID:) async`, `send(postID:userID:) async`.
- Produces (SwiftUI): `CommentsView(postID:userID:)` — consumed by Task 11's `TimelineView`.

- [ ] **Step 1: Implement CommentsViewModel**

`ViewModels/CommentsViewModel.swift`:

```swift
import Foundation

@MainActor
@Observable
final class CommentsViewModel {
    private(set) var comments: [CommentItem] = []
    private(set) var isLoading = false
    private(set) var isSending = false
    var draft = ""
    var errorMessage: String?

    private let posts: PostServicing

    init(posts: PostServicing = PostService.shared) {
        self.posts = posts
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    func load(postID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { comments = try await posts.fetchComments(postID: postID) }
        catch { errorMessage = PostError.message(for: error) }
    }

    func send(postID: UUID, userID: UUID) async {
        guard canSend else { return }
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await posts.addComment(postID: postID, userID: userID, content: content)
            draft = ""
            // Refetch so the new comment arrives with its author profile attached.
            await load(postID: postID)
        } catch {
            errorMessage = PostError.message(for: error)   // draft is kept
        }
    }
}
```

- [ ] **Step 2: Implement CommentsView**

`Views/CommentsView.swift`:

```swift
import SwiftUI

struct CommentsView: View {
    let postID: UUID
    let userID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var vm = CommentsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption).foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if vm.isLoading && vm.comments.isEmpty {
                            ProgressView().tint(Theme.indigo).padding(.top, 30)
                        } else if vm.comments.isEmpty {
                            Text("No comments yet.")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity).padding(.top, 30)
                        }
                        ForEach(vm.comments) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("@\(comment.author?.username ?? "unknown")")
                                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
                                    Text(comment.createdAt, format: .relative(presentation: .named))
                                        .font(.caption2).foregroundStyle(Theme.muted)
                                }
                                Text(comment.content)
                                    .font(.subheadline).foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }

                Divider().overlay(Theme.hairline)
                HStack(spacing: 8) {
                    SereneTextField(title: "Add a comment", text: $vm.draft)
                        .textInputAutocapitalization(.sentences)
                    Button {
                        Task { await vm.send(postID: postID, userID: userID) }
                    } label: {
                        if vm.isSending {
                            ProgressView().tint(Theme.indigo)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundStyle(vm.canSend ? Theme.indigo : Theme.muted.opacity(0.5))
                        }
                    }
                    .disabled(!vm.canSend)
                }
                .padding(12)
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await vm.load(postID: postID) }
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
make generate
xcodebuild build -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add ViewModels/CommentsViewModel.swift Views/CommentsView.swift
git commit -m "feat(ui): comment thread screen"
```

---

## Task 11: Timeline screen + HomeView wiring

**Files:**
- Create: `Views/TimelineView.swift`
- Modify: `Views/HomeView.swift`

**Interfaces:**
- Consumes: `TimelineViewModel` (Task 7), `PostCell` (Task 8), `ComposeEncouragementView` (Task 9), `CommentsView` (Task 10), `AuthViewModel` (existing).
- Produces (SwiftUI): `TimelineView(userID:)`; `HomeView` renders it and presents compose.
- Note: `AuthViewModel` exposes `session` (private(set)) and `profile`. The signed-in user id is `auth.profile?.id` — use that, it is non-nil on the `.ready` route.

- [ ] **Step 1: Write TimelineView**

`Views/TimelineView.swift`:

```swift
import SwiftUI

struct TimelineView: View {
    let userID: UUID

    @State private var vm = TimelineViewModel()
    @State private var commentingOn: FeedItem?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let error = vm.errorMessage {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(Theme.danger)
                        Spacer()
                        Button("Retry") { Task { await vm.load(userID: userID) } }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.indigo)
                    }
                    .padding(12)
                    .background(Theme.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                }

                if vm.isLoading && vm.items.isEmpty {
                    ProgressView().tint(Theme.indigo).padding(.top, 40)
                } else if vm.items.isEmpty && vm.errorMessage == nil {
                    emptyState
                }

                ForEach(vm.items) { item in
                    PostCell(
                        item: item,
                        isMine: item.authorID == userID,
                        onLike: { Task { await vm.toggleLike(itemID: item.id, userID: userID) } },
                        onComment: { commentingOn = item },
                        onDelete: { Task { await vm.delete(itemID: item.id) } }
                    )
                    .onAppear {
                        if item.id == vm.items.last?.id {
                            Task { await vm.loadMore(userID: userID) }
                        }
                    }
                }

                if vm.isLoadingMore {
                    ProgressView().tint(Theme.indigo).padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.cream)
        .refreshable { await vm.load(userID: userID) }
        .task { await vm.load(userID: userID) }
        .sheet(item: $commentingOn) { item in
            CommentsView(postID: item.id, userID: userID)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 20).fill(Theme.hairline.opacity(0.6))
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: "bird").font(.system(size: 28)).foregroundStyle(Theme.indigo))
            Text("No encouragements yet")
                .font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
            Text("Share something that lifted you up today.")
                .font(.subheadline).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
}
```

- [ ] **Step 2: Rewrite HomeView around the timeline**

Replace the entire contents of `Views/HomeView.swift`:

```swift
import SwiftUI

struct HomeView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var showCompose = false
    /// Bumped after a successful post to force TimelineView to reload.
    @State private var reloadToken = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("BibleShare")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Menu {
                    Button("Sign out", role: .destructive) { Task { await auth.signOut() } }
                } label: {
                    Circle().fill(Theme.indigo).frame(width: 30, height: 30)
                        .overlay(Text(String(auth.currentUsername?.prefix(1) ?? "?").uppercased())
                            .font(.caption).foregroundStyle(.white))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider().overlay(Theme.hairline)

            if let userID = auth.profile?.id {
                TimelineView(userID: userID)
                    .id(reloadToken)
            } else {
                Spacer()
                ProgressView().tint(Theme.indigo)
                Spacer()
            }

            HStack {
                tabIcon("house.fill", active: true) {}
                tabIcon("magnifyingglass", active: false) {}
                tabIcon("square.and.pencil", active: false) { showCompose = true }
                tabIcon("person", active: false) {}
            }
            .padding(.top, 10).padding(.bottom, 4)
            .overlay(Divider().overlay(Theme.hairline), alignment: .top)
        }
        .background(Theme.cream.ignoresSafeArea())
        .sheet(isPresented: $showCompose) {
            if let userID = auth.profile?.id {
                ComposeEncouragementView(userID: userID) { _ in
                    reloadToken = UUID()   // refetch so the new post appears with its author + counts
                }
            }
        }
    }

    private func tabIcon(_ name: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 20))
                .foregroundStyle(active ? Theme.indigo : Theme.muted.opacity(0.5))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView().environment(AuthViewModel(provider: SupabaseService.shared))
}
```

> Reloading via `.id(reloadToken)` refetches the page rather than optimistically inserting a locally-built `FeedItem`. The RPC returns only a post id — the author profile and counts come from the server, so a refetch is the honest way to render the new row. `TimelineViewModel.insert` stays available for a future optimistic path.

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
make generate
xcodebuild build -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`. `CommentsView` comes from Task 10, so it already exists.

- [ ] **Step 4: Commit**

```bash
git add Views/TimelineView.swift Views/HomeView.swift
git commit -m "feat(ui): personal timeline replaces the Home placeholder"
```

---

## Task 12: Full verification pass

**Files:** none (verification only).

- [ ] **Step 1: Run the entire test suite**

Run:
```bash
make generate
xcodebuild test -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -30
```
Expected: **all** suites pass — `FeedModelTests` (4), `BibleServiceTests` (4), `ComposeViewModelTests` (8), `TimelineViewModelTests` (7), plus the pre-existing `PostModelTests` (2), `SocialModelTests` (4), `UsernameValidatorTests`, `AuthErrorTests`, `AuthViewModelTests`. Report the actual counts; do not claim a pass you did not observe.

- [ ] **Step 2: Re-check security advisors**

Call `mcp__supabase__get_advisors` with `type:"security"`.
Expected: no new lints from `create_encouragement` or the storage policies.

- [ ] **Step 3: Manual pass on the simulator**

Run `make run`, then sign in and walk the loop:

1. Compose with a title only → posts; appears on the timeline.
2. Compose with title + body + a verse (`John 3:16` to `17`) + a photo + a link + a tag of a real second username → all render in the cell; the photo loads (proving signed URLs and the storage read policy work end-to-end).
3. Tap the heart → fills, count increments; pull-to-refresh → still liked (proving it persisted, not just optimism).
4. Add a comment → appears with your username; the cell's comment count rises after refresh.
5. Post menu → Delete → the row disappears.
6. Try posting with an empty title → the Post button stays disabled.

Record what you actually observed for each step.

- [ ] **Step 4: Confirm no stray objects in the bucket**

Call `mcp__supabase__execute_sql`:

```sql
select count(*) as objects, count(*) filter (
  where not exists (select 1 from public.post_media pm where pm.url = o.name)
) as orphans
from storage.objects o
where o.bucket_id = 'media';
```

Expected: `orphans = 0` after a clean manual pass. A non-zero count means the compensating delete in `ComposeViewModel.submit` did not fire — investigate before shipping.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "test: full-suite and manual verification for encouragements + feeds"
```

---

## Post-plan: what Plans 3–6 pick up

- **Plan 3 — Friends:** drop the `author_id` filter in `FeedService.fetchTimeline` (RLS already surfaces friends' timeline posts); friend-scoped search for the tag picker; **and tighten `profiles`' `SELECT using (true)` policy**, which today lets any signed-in client enumerate every username via a `like` filter (spec §7).
- **Plan 4 — Groups core:** add `p_group_ids uuid[]` to `create_encouragement` plus a membership assert; group timeline filters through `post_groups`.
- **Plan 5 — Check-ins:** `check_in` / `active_checkin_targets` RPCs; compose gains a check-in mode.
- **Plan 6 — Notifications + push:** triggers on `likes` / `comments` / `post_tags`. Plan 2 writes no `notifications` rows.

---

## Self-Review

**Spec coverage** (spec = `2026-07-16-encouragements-feeds-design.md`):
- §3.1 media bucket + 3 storage policies + non-definer warning → Task 1 (Step 4 proves visibility tracking). ✅
- §3.2 `create_encouragement` RPC, forced author, title check, atomicity → Task 2 (Steps 3–5). Foreign-folder image guard added during planning — it closes a hole the spec's design implies but does not state. ✅
- §4.1 services (Post/Feed/MediaUploader/Bible/ProfileService) → Tasks 4, 5. ✅
- §4.2 feed nested select + keyset + `is_liked` companion query → Task 5 (`FeedService`), Task 7 (`markLiked`). ✅
- §4.3 `FeedItem` / `NewVerse` / `NewMediaItem` / `CreateEncouragementParams` → Task 3. ✅
- §4.4 ViewModels → Tasks 6, 7, 10. §4.5 views → Tasks 8, 9, 10, 11. ✅
- §5.1 orphan-free ordering + compensating delete → Task 6 (`failedSubmitDeletesUploadedImagesAndKeepsDraft`), Task 12 Step 4. ✅
- §5.2 optimistic likes + revert → Task 7 (`failedLikeRevertsCountAndFlag`). ✅
- §5.3 `PostError`, draft retention, non-fatal verse failure → Task 5, Task 6. ✅
- §6 testing (SQL atomicity/title/author/storage, Swift validation/decoding/label, manual pass) → Tasks 1, 2, 3, 4, 6, 7, 12. ✅
- §7 handoffs (incl. the `profiles` enumeration issue) → Post-plan section. ✅
- Non-goals (friends, groups, check-ins, notification writes) → excluded; stated in Global Constraints. ✅

**Placeholder scan:** No TBD/TODO. Every code step carries complete code; every command has expected output. Task 5 Step 1 is a genuine verification step (the supabase-swift Storage signature varies by 2.x version) rather than a placeholder — it names the exact greps and what to do with the result. ✅

**Type consistency:**
- RPC params `p_title/p_body/p_shared_to_timeline/p_verses/p_media/p_tag_user_ids` (Task 2) ≡ `CreateEncouragementParams.CodingKeys` (Task 3), asserted by `encodesCreateEncouragementParams`.
- `setLike(postID:userID:liked:)` — same argument order in the protocol (Task 5), `FakePostService` (Task 6), and both call sites in `TimelineViewModel` (Task 7).
- `fetchTimeline(authorID:before:limit:)` and `likedPostIDs(userID:among:)` — identical in `FeedServicing`, `FeedService`, `FakeFeedService`, `TimelineViewModel`.
- `MediaUploading.upload(_:userID:)` returns a **path**, consumed as `post_media.url` in Tasks 6/8 and matched by the RPC's folder guard (Task 2).
- `ComposeImage(id:jpeg:)` — same shape in Task 6's tests, VM, and Task 9's picker.
- `ComposeViewModel.maxImages` referenced from Task 9's `PhotosPicker`. `TimelineViewModel.pageSize` used only internally.
- UUID lowercasing is applied in `MediaUploader.upload`, `FakeMediaUploader.upload`, and `FeedItemFactory` — consistent with `auth.uid()::text`. ✅

**Task-boundary check:** Dependencies flow strictly forward. Comments (Task 10) precedes the timeline wiring (Task 11) that presents `CommentsView`, so no task references a type that does not yet exist. Tasks 1–2 (SQL) are independent of Tasks 3–11 (Swift) and could run in parallel, but the Task 12 manual pass needs both. ✅
