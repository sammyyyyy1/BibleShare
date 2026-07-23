# DDD File-Structure Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize BibleShare from layer-first folders (`Models/`, `Views/`, `ViewModels/`, `Services/`) into a domain-driven tree (`App/`, `Core/`, `Features/<Domain>/`, `Shared/`) with no behavior change.

**Architecture:** Swift compiles every file in a target as one module regardless of folder, so moving files changes no symbol references and needs no `import` edits. XcodeGen derives Xcode groups from the filesystem, so each task is: `git mv` → update `project.yml` → `make generate` → `make build` → `make test` → commit. The only real code edits are splitting four multi-domain "catch-all" files, which relocate whole declarations verbatim (names unchanged, so all call sites keep compiling).

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, iOS 17+, XcodeGen, SwiftLint, supabase-swift 2.x.

**Spec:** `docs/superpowers/specs/2026-07-23-ddd-restructure-design.md`

## Global Constraints

- **Never edit `BibleShare.xcodeproj` directly** — it is generated and git-ignored. Edit `project.yml`, then run `make generate`.
- **Never run `killall CoreSimulatorService`** — it breaks this machine's Xcode 26 disk-image runtimes.
- Build/test destination is exactly `platform=iOS Simulator,name=iPhone 17`.
- **No behavior changes.** No schema, RLS, RPC, or Supabase migration changes. No test-logic changes. Declarations move verbatim — do not rename, reformat, "improve", or re-order the code you move. Doc comments move with their type.
- Use `git mv` (never `mv` + `git add`) so history shows renames.
- Every moved/created Swift file keeps its existing `import` lines; each new split file starts with `import Foundation`.
- The full existing test suite must pass unchanged after every task. No test is added, deleted, or edited except for the file moves in Task 13.
- This worktree needs `Resources/Secrets.plist` before it can build. If missing: `cp Resources/Secrets.plist.example Resources/Secrets.plist` and fill in `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
- `.swiftlint.yml` `included:` must list the new roots, or lint silently stops covering moved code.
- SwiftLint limits that apply to new files: `line_length` warning 120 / error 200, `type_name` min length 3.

## Standard verification block

Several tasks end with the same verification. Where a step says **"Run standard verification"**, run exactly this and require all four to succeed:

```bash
make generate && make build && make lint
```

then

```bash
xcodebuild -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData test 2>&1 | grep -E "Test run with|TEST SUCCEEDED|TEST FAILED"
```

Expected: `make generate` regenerates the project with no error; `make build` succeeds (this is the Swift typecheck that proves no reference broke); `make lint` reports no new violations; and the test output contains **both**:

```
✔ Test run with 141 tests in 23 suites passed
** TEST SUCCEEDED **
```

**This project uses Swift Testing, not XCTest** — the summary line is `Test run with N tests in M suites`, and there are no `Test Case ... passed` lines. The count must be exactly **141 tests in 23 suites** after every task. A dropped test file still reports `** TEST SUCCEEDED **` while the count silently falls, so always check the number, not just the status.

---

## Task 0: Baseline capture — ALREADY COMPLETE

**Do not re-run this task.** It was executed by the controller before task
dispatch began. Recorded baseline, which every later task must match:

| Measure | Baseline |
|---|---|
| Test run | **141 tests in 23 suites passed** |
| Tracked `*.swift` files | **82** |
| Final expected `*.swift` files (after Task 12) | **88** (82 − 4 deleted + 10 created) |
| `Resources/Secrets.plist` | present (copied into this worktree; git-ignored) |

Original Task 0 steps, retained for the record:

**Files:**
- Create: `build/baseline-tests.txt` (git-ignored scratch; do not commit)

**Interfaces:**
- Consumes: nothing.
- Produces: the baseline test count every later task compares against.

- [ ] **Step 1: Confirm the worktree can build**

```bash
ls Resources/Secrets.plist || cp Resources/Secrets.plist.example Resources/Secrets.plist
```

If you had to copy it, fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY` before continuing — the build will fail without them.

- [ ] **Step 2: Generate and build the current tree**

```bash
make generate && make build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Record the baseline test result**

```bash
xcodebuild -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData test 2>&1 | tee build/baseline-tests.txt | tail -5
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Record the baseline test count and type inventory**

```bash
grep -cE "^Test Case .* passed" build/baseline-tests.txt
git ls-files '*.swift' | wc -l
```

Write both numbers down:

- **Test count** — every later task must end with exactly this number. A dropped
  test file still reports `TEST SUCCEEDED`, so always check the count, not just
  the status.
- **Swift file count** — Task 12 Step 5 checks the final count against this
  baseline (expected: baseline + 6, since the four catch-all files are replaced
  by ten new per-domain files).

Do not commit anything in this task.

---

## Task 1: Core infrastructure + app shell

Moves cross-cutting infrastructure into `Core/` and the multi-feature navigation shell into `Shared/`. `AppSecrets.swift` is Supabase configuration and belongs beside `SupabaseService.swift`.

**Files:**
- Create dirs: `Core/Supabase/`, `Core/DesignSystem/`, `Core/Media/`, `Shared/`
- Move: 11 files listed below
- Modify: `project.yml` (add `Core`, `Shared` to sources), `.swiftlint.yml` (add `Core`, `Shared` to included)

**Interfaces:**
- Consumes: nothing.
- Produces: the `Core/` and `Shared/` roots that Tasks 2–12 rely on; `Core/Models/` is created later in Task 9.

- [ ] **Step 1: Create the destination directories**

```bash
mkdir -p Core/Supabase Core/DesignSystem Core/Media Shared
```

- [ ] **Step 2: Move the Core infrastructure files**

```bash
git mv Services/SupabaseService.swift  Core/Supabase/SupabaseService.swift
git mv Services/AppSecrets.swift       Core/Supabase/AppSecrets.swift
git mv Views/Theme.swift               Core/DesignSystem/Theme.swift
git mv Views/Components/SereneControls.swift Core/DesignSystem/SereneControls.swift
git mv Services/ImageProcessor.swift   Core/Media/ImageProcessor.swift
git mv Services/MediaUploader.swift    Core/Media/MediaUploader.swift
git mv Views/Components/RemoteImage.swift    Core/Media/RemoteImage.swift
git mv Views/Components/MediaStrip.swift     Core/Media/MediaStrip.swift
```

- [ ] **Step 3: Move the app-shell files**

```bash
git mv Views/RootTabView.swift    Shared/RootTabView.swift
git mv Views/HomeView.swift       Shared/HomeView.swift
git mv ViewModels/AppRouter.swift Shared/AppRouter.swift
```

- [ ] **Step 4: Add the new roots to `project.yml`**

In the `BibleShare` target's `sources:` list, add `Core` and `Shared`. Keep the old paths for now — they still hold files. The list becomes:

```yaml
    sources:
      - path: App
      - path: Core
      - path: Shared
      - path: Models
      - path: Views
      - path: ViewModels
      - path: Services
      - path: Resources
```

- [ ] **Step 5: Add the new roots to `.swiftlint.yml`**

Change the `included:` list to:

```yaml
included:
  - App
  - Core
  - Shared
  - Models
  - Views
  - ViewModels
  - Services
```

- [ ] **Step 6: Run standard verification**

See the "Standard verification block" above. All four commands must succeed and the test count must match Task 0.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(structure): move core infrastructure to Core/ and app shell to Shared/"
```

- [ ] **Step 8: Confirm the moves registered as renames**

```bash
git show --stat --find-renames HEAD | head -20
```

Expected: entries render as `{Services => Core/Supabase}/SupabaseService.swift` style renames, not add/delete pairs.

---

## Task 2: Auth and Profile features

**Files:**
- Create dirs: `Features/Auth/`, `Features/Profile/`
- Move: 7 files listed below
- Modify: `project.yml`, `.swiftlint.yml` (add `Features`)

**Interfaces:**
- Consumes: `Core/`, `Shared/` roots from Task 1.
- Produces: the `Features/` root that Tasks 3–12 rely on.

- [ ] **Step 1: Create the destination directories**

```bash
mkdir -p Features/Auth Features/Profile
```

- [ ] **Step 2: Move the Auth files**

```bash
git mv Views/AuthView.swift          Features/Auth/AuthView.swift
git mv ViewModels/AuthViewModel.swift Features/Auth/AuthViewModel.swift
git mv Services/AuthProviding.swift  Features/Auth/AuthProviding.swift
git mv Services/AuthError.swift      Features/Auth/AuthError.swift
```

- [ ] **Step 3: Move the Profile files**

```bash
git mv Views/ProfileView.swift        Features/Profile/ProfileView.swift
git mv Views/UsernameSetupView.swift  Features/Profile/UsernameSetupView.swift
git mv Models/UsernameValidator.swift Features/Profile/UsernameValidator.swift
```

- [ ] **Step 4: Add `Features` to `project.yml`**

In the `BibleShare` target's `sources:`, add `- path: Features` immediately after `- path: Core`.

- [ ] **Step 5: Add `Features` to `.swiftlint.yml`**

Add `  - Features` to the `included:` list after `  - Core`.

- [ ] **Step 6: Run standard verification**

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(structure): move Auth and Profile into Features/"
```

---

## Task 3: Feed feature

Feed is the content/posts hub. Per spec decision D1, it owns `PostService`/`PostServicing` because posts are the central content aggregate consumed by Feed, Groups, Comments, and Compose.

**Files:**
- Create dir: `Features/Feed/`
- Move: 8 files listed below

**Interfaces:**
- Consumes: `Features/` root from Task 2.
- Produces: `Features/Feed/`, the destination for `ContentModels.swift` (Task 9) and `FeedModels.swift` (Task 10).

- [ ] **Step 1: Create the destination directory**

```bash
mkdir -p Features/Feed
```

- [ ] **Step 2: Move the Feed files**

```bash
git mv Views/TimelineView.swift            Features/Feed/TimelineView.swift
git mv ViewModels/TimelineViewModel.swift  Features/Feed/TimelineViewModel.swift
git mv Views/CommentsView.swift            Features/Feed/CommentsView.swift
git mv ViewModels/CommentsViewModel.swift  Features/Feed/CommentsViewModel.swift
git mv ViewModels/FeedLikeHandling.swift   Features/Feed/FeedLikeHandling.swift
git mv Services/FeedService.swift          Features/Feed/FeedService.swift
git mv Services/PostService.swift          Features/Feed/PostService.swift
git mv Views/Components/PostCell.swift     Features/Feed/PostCell.swift
```

- [ ] **Step 3: Run standard verification**

No `project.yml` change is needed — `Features` is already a source root and XcodeGen recurses into it.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(structure): move Feed into Features/Feed"
```

---

## Task 4: Compose and Bible features

Per spec decision D2, verse-*picking UI* lives in Compose (it exists to build a post); `BibleService` (the verse-lookup data source) is the whole of `Features/Bible/`.

**Files:**
- Create dirs: `Features/Compose/`, `Features/Bible/`
- Move: 6 files listed below

**Interfaces:**
- Consumes: `Features/` root from Task 2.
- Produces: `Features/Compose/`, destination for `ComposeParams.swift` (Task 11).

- [ ] **Step 1: Create the destination directories**

```bash
mkdir -p Features/Compose Features/Bible
```

- [ ] **Step 2: Move the Compose files**

```bash
git mv Views/ComposeEncouragementView.swift  Features/Compose/ComposeEncouragementView.swift
git mv ViewModels/ComposeViewModel.swift     Features/Compose/ComposeViewModel.swift
git mv Views/Components/VerseCard.swift      Features/Compose/VerseCard.swift
git mv Views/Sheets/VersePickerSheet.swift   Features/Compose/VersePickerSheet.swift
git mv Views/Sheets/UserTagSheet.swift       Features/Compose/UserTagSheet.swift
```

- [ ] **Step 3: Move the Bible file**

```bash
git mv Services/BibleService.swift Features/Bible/BibleService.swift
```

- [ ] **Step 4: Run standard verification**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(structure): move Compose and Bible into Features/"
```

---

## Task 5: Friends, Groups, CheckIn, and Notifications features

These four domains are each a straight file move with no shared decisions between them, so they share one task and one verification cycle.

**Files:**
- Create dirs: `Features/Friends/`, `Features/Groups/`, `Features/CheckIn/`, `Features/Notifications/`
- Move: 18 files listed below (Friends 3, Groups 7, CheckIn 3, Notifications 5)

**Interfaces:**
- Consumes: `Features/` root from Task 2.
- Produces: the four feature folders that Tasks 9–12 write split model files into.

- [ ] **Step 1: Create the destination directories**

```bash
mkdir -p Features/Friends Features/Groups Features/CheckIn Features/Notifications
```

- [ ] **Step 2: Move the Friends files**

```bash
git mv Views/FriendsView.swift           Features/Friends/FriendsView.swift
git mv ViewModels/FriendsViewModel.swift Features/Friends/FriendsViewModel.swift
git mv Services/FriendService.swift      Features/Friends/FriendService.swift
```

- [ ] **Step 3: Move the Groups files**

```bash
git mv Views/GroupsView.swift                   Features/Groups/GroupsView.swift
git mv Views/GroupTimelineView.swift            Features/Groups/GroupTimelineView.swift
git mv Views/CreateGroupView.swift              Features/Groups/CreateGroupView.swift
git mv ViewModels/GroupListViewModel.swift      Features/Groups/GroupListViewModel.swift
git mv ViewModels/GroupTimelineViewModel.swift  Features/Groups/GroupTimelineViewModel.swift
git mv ViewModels/CreateGroupViewModel.swift    Features/Groups/CreateGroupViewModel.swift
git mv Services/GroupService.swift              Features/Groups/GroupService.swift
```

- [ ] **Step 4: Move the CheckIn files**

```bash
git mv Views/CheckInView.swift                 Features/CheckIn/CheckInView.swift
git mv ViewModels/CheckInViewModel.swift       Features/CheckIn/CheckInViewModel.swift
git mv Services/CheckinReminderScheduler.swift Features/CheckIn/CheckinReminderScheduler.swift
```

- [ ] **Step 5: Move the Notifications files**

```bash
git mv Views/NotificationsView.swift             Features/Notifications/NotificationsView.swift
git mv ViewModels/NotificationsViewModel.swift   Features/Notifications/NotificationsViewModel.swift
git mv Services/NotificationService.swift        Features/Notifications/NotificationService.swift
git mv Views/Components/NotificationRow.swift    Features/Notifications/NotificationRow.swift
git mv Services/PushRegistrar.swift              Features/Notifications/PushRegistrar.swift
```

- [ ] **Step 6: Run standard verification**

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(structure): move Friends, Groups, CheckIn, Notifications into Features/"
```

- [ ] **Step 8: Confirm only the catch-all files remain in the old dirs**

```bash
find Models Views ViewModels Services -name '*.swift' | sort
```

Expected output is exactly these four files (plus nothing else):

```
Models/ComposeParams.swift
Models/FeedModels.swift
Models/Models.swift
Services/SocialServicing.swift
```

If any other file is listed, it was missed — move it to its domain before continuing.

---

## Task 6: Split `Models/Models.swift`

This is the first task with real code edits. Move each declaration **verbatim, together with its doc comment**, into the destination file. Do not rename, reformat, or reorder anything. Every new file starts with `import Foundation`.

Line numbers below locate declarations in the **original, unmodified** `Models/Models.swift` (324 lines). They shift as you cut, so work destination-by-destination and re-locate by type name rather than trusting the numbers after your first edit.

**Files:**
- Create: `Core/Models/Profile.swift`, `Features/Feed/ContentModels.swift`, `Features/Groups/GroupModels.swift`, `Features/Friends/FriendModels.swift`, `Features/Notifications/NotificationModels.swift`
- Delete: `Models/Models.swift`

**Interfaces:**
- Consumes: feature folders from Tasks 3–5.
- Produces: `Profile`, `ProfileUpdate` in `Core/Models/`; `Post`, `PostKind`, `Like`, `Comment`, `PostVerse`, `PostMedia`, `PostTag`, `MediaType` in `Features/Feed/ContentModels.swift`; group/friend/notification entities in their feature folders. All type names are unchanged, so all existing call sites keep compiling.

- [ ] **Step 1: Create `Core/Models/` and the shared-kernel file**

```bash
mkdir -p Core/Models
```

Create `Core/Models/Profile.swift` containing, in this order, cut verbatim from `Models/Models.swift`:
- `struct Profile` (orig. line 6)
- `struct ProfileUpdate` (orig. line 82)

File header:

```swift
import Foundation

/// Shared-kernel identity models. `Profile` is decoded by Auth, Profile, Feed,
/// Friends, Groups, and Notifications, so it lives in Core rather than a feature.
```

- [ ] **Step 2: Create `Features/Feed/ContentModels.swift`**

Cut verbatim, in this order: `PostKind` (28), `Post` (33), `Like` (53), `Comment` (65), `PostVerse` (189), `MediaType` (215), `PostMedia` (219), `PostTag` (241).

File header:

```swift
import Foundation

/// Post content entities mirroring the Supabase schema. Property names use
/// `CodingKeys` to map snake_case columns to Swift camelCase.
```

- [ ] **Step 3: Create `Features/Groups/GroupModels.swift`**

Cut verbatim, in this order: `CheckinCadence` (89), `FellowshipGroup` (93), `GroupMember` (117), `InviteStatus` (131), `GroupInvite` (135), `CheckinWindow` (157), `GroupCheckin` (171).

File header:

```swift
import Foundation

/// Group entities mirroring the Supabase schema. Property names use
/// `CodingKeys` to map snake_case columns to Swift camelCase.
```

- [ ] **Step 4: Create `Features/Friends/FriendModels.swift`**

Cut verbatim, in this order: `FriendStatus` (255), `Friendship` (259).

File header:

```swift
import Foundation

/// Friendship entities mirroring the Supabase schema. Property names use
/// `CodingKeys` to map snake_case columns to Swift camelCase.
```

- [ ] **Step 5: Create `Features/Notifications/NotificationModels.swift`**

Cut verbatim, in this order: `NotificationType` (277), `AppNotification` (288), `DeviceToken` (312).

File header:

```swift
import Foundation

/// Notification entities mirroring the Supabase schema. Property names use
/// `CodingKeys` to map snake_case columns to Swift camelCase.
```

- [ ] **Step 6: Verify the original is fully drained, then delete it**

```bash
grep -nE "^(struct|enum|protocol|final class|class|actor) " Models/Models.swift
```

Expected: no output (every declaration has been moved). If anything is listed, move it before continuing.

```bash
git rm Models/Models.swift
```

- [ ] **Step 7: Verify the declaration count is conserved**

```bash
grep -hcE "^(struct|enum) " Core/Models/Profile.swift Features/Feed/ContentModels.swift Features/Groups/GroupModels.swift Features/Friends/FriendModels.swift Features/Notifications/NotificationModels.swift | paste -sd+ | bc
```

Expected: `22` — the exact number of declarations that were in `Models.swift`.

- [ ] **Step 8: Run standard verification**

The build succeeding is the real proof that no declaration was dropped or altered.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor(models): split Models.swift into per-domain model files"
```

---

## Task 7: Split `Models/FeedModels.swift`

Same rules as Task 6: cut verbatim with doc comments, `import Foundation` at the top of any new file. Where the destination file already exists (created in Task 6), **append** to it rather than overwriting.

Line numbers locate declarations in the original 248-line `Models/FeedModels.swift`.

**Files:**
- Create: `Features/Feed/FeedModels.swift`, `Features/CheckIn/CheckInModels.swift`
- Modify (append): `Features/Friends/FriendModels.swift`, `Features/Groups/GroupModels.swift`, `Features/Notifications/NotificationModels.swift`
- Delete: `Models/FeedModels.swift`

**Interfaces:**
- Consumes: the per-domain model files created in Task 6.
- Produces: read-side DTOs `FeedItem`, `CommentItem`, `CountRow`, `TaggedUser`, `PostSummary` in `Features/Feed/FeedModels.swift`; `FriendEdge` appended to Friends; `GroupListItem`, `GroupMemberRow`, `GroupInviteRow` appended to Groups; `CheckinTarget` in `Features/CheckIn/CheckInModels.swift`; `NotificationItem` appended to Notifications.

- [ ] **Step 1: Create `Features/Feed/FeedModels.swift`**

Cut verbatim, in this order: `CountRow` (7), `TaggedUser` (11), `FeedItem` (24), `CommentItem` (73), `PostSummary` (204).

Keep the original file-level doc comment, updated for its new home:

```swift
import Foundation

/// Read-side DTOs decoding the PostgREST embedded payloads. Row models
/// (`Post`, `PostVerse`, …) live in ContentModels.swift; these are the join shapes.
```

- [ ] **Step 2: Append `FriendEdge` to `Features/Friends/FriendModels.swift`**

Cut `FriendEdge` (92) verbatim and append it to the end of the existing file. Do not add a second `import Foundation`.

- [ ] **Step 3: Append the group row DTOs to `Features/Groups/GroupModels.swift`**

Cut verbatim and append, in this order: `GroupListItem` (122), `GroupMemberRow` (148), `GroupInviteRow` (163).

- [ ] **Step 4: Create `Features/CheckIn/CheckInModels.swift`**

Cut `CheckinTarget` (187) verbatim.

File header:

```swift
import Foundation

/// Check-in DTOs. `CheckinTarget` decodes the `active_checkin_targets` payload.
```

- [ ] **Step 5: Append `NotificationItem` to `Features/Notifications/NotificationModels.swift`**

Cut `NotificationItem` (212) verbatim and append it to the end of the existing file.

- [ ] **Step 6: Verify the original is fully drained, then delete it**

```bash
grep -nE "^(struct|enum|protocol|final class|class|actor) " Models/FeedModels.swift
```

Expected: no output.

```bash
git rm Models/FeedModels.swift
```

- [ ] **Step 7: Run standard verification**

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(models): split FeedModels.swift into per-domain DTO files"
```

---

## Task 8: Split `Models/ComposeParams.swift`

Line numbers locate declarations in the original 127-line `Models/ComposeParams.swift`.

**Files:**
- Create: `Features/Compose/ComposeParams.swift`
- Modify (append): `Features/Groups/GroupModels.swift`, `Features/CheckIn/CheckInModels.swift`
- Delete: `Models/ComposeParams.swift`

**Interfaces:**
- Consumes: `Features/Compose/` (Task 4), `Features/Groups/GroupModels.swift` (Task 6), `Features/CheckIn/CheckInModels.swift` (Task 7).
- Produces: `NewVerse`, `NewMediaItem`, `CreateEncouragementParams` in Compose; `CreateGroupParams` in Groups; `CheckInParams` in CheckIn.

- [ ] **Step 1: Create `Features/Compose/ComposeParams.swift`**

Cut verbatim, in this order: `NewVerse` (7), `NewMediaItem` (27), `CreateEncouragementParams` (42).

Keep the original file-level doc comment verbatim — it points at the migration that defines the RPC parameter names:

```swift
import Foundation

/// Write-side DTOs. Keys mirror `public.create_encouragement`'s parameter names
/// and the child tables' column names exactly — see
/// supabase/migrations/20260716010100_create_encouragement_rpc.sql
```

- [ ] **Step 2: Append `CreateGroupParams` to `Features/Groups/GroupModels.swift`**

Cut `CreateGroupParams` (79) verbatim and append it to the end of the existing file.

- [ ] **Step 3: Append `CheckInParams` to `Features/CheckIn/CheckInModels.swift`**

Cut `CheckInParams` (100) verbatim and append it to the end of the existing file.

- [ ] **Step 4: Verify the original is fully drained, then delete it**

```bash
grep -nE "^(struct|enum|protocol|final class|class|actor) " Models/ComposeParams.swift
```

Expected: no output.

```bash
git rm Models/ComposeParams.swift
```

- [ ] **Step 5: Run standard verification**

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(models): split ComposeParams.swift into per-domain param files"
```

---

## Task 9: Split `Services/SocialServicing.swift`

Each protocol moves to sit **beside its implementation**, appended to the top of the existing service file (after its `import` lines, before the concrete type). `PostError` is the exception: per spec decision D3 it is a shared error enum used by nearly every ViewModel, so it becomes its own Core file.

Line numbers locate declarations in the original 117-line `Services/SocialServicing.swift`.

**Files:**
- Create: `Core/Models/PostError.swift`, `Features/Profile/UsernameResolving.swift`
- Modify (insert protocol): `Features/Feed/PostService.swift`, `Features/Feed/FeedService.swift`, `Core/Media/MediaUploader.swift`, `Features/Friends/FriendService.swift`, `Features/Groups/GroupService.swift`, `Features/Notifications/NotificationService.swift`
- Delete: `Services/SocialServicing.swift`

**Interfaces:**
- Consumes: the service files moved in Tasks 1–5.
- Produces: `PostServicing`, `FeedServicing`, `MediaUploading`, `UsernameResolving`, `FriendServicing`, `GroupServicing`, `NotificationServicing` each beside their implementation, and `PostError` in `Core/Models/PostError.swift`. `BibleShareTests/FakeSocialServices.swift` conforms to all of these and must keep compiling untouched.

- [ ] **Step 1: Create `Core/Models/PostError.swift`**

Cut `PostError` (81) verbatim.

File header:

```swift
import Foundation

/// Shared error type for social write/read paths. Consumed by nearly every
/// ViewModel, so it is shared kernel rather than owned by one feature.
```

- [ ] **Step 2: Move `PostServicing` into `Features/Feed/PostService.swift`**

Cut `protocol PostServicing` (6) verbatim and insert it after the `import` lines of `Features/Feed/PostService.swift`, above the concrete implementation.

- [ ] **Step 3: Move `FeedServicing` into `Features/Feed/FeedService.swift`**

Cut `protocol FeedServicing` (17) verbatim and insert it after the `import` lines of `Features/Feed/FeedService.swift`.

- [ ] **Step 4: Move `MediaUploading` into `Core/Media/MediaUploader.swift`**

Cut `protocol MediaUploading` (24) verbatim and insert it after the `import` lines of `Core/Media/MediaUploader.swift`.

- [ ] **Step 5: Create `Features/Profile/UsernameResolving.swift`**

Cut `protocol UsernameResolving` (31) verbatim into a new file. It has no single service implementation file of its own, so it gets one.

File header:

```swift
import Foundation

/// Protocol seam for username → profile resolution. Backed by the
/// `find_profile_by_username` RPC (exact match only — never a prefix query).
```

- [ ] **Step 6: Move `FriendServicing` into `Features/Friends/FriendService.swift`**

Cut `protocol FriendServicing` (39) verbatim and insert it after the `import` lines of `Features/Friends/FriendService.swift`.

- [ ] **Step 7: Move `GroupServicing` into `Features/Groups/GroupService.swift`**

Cut `protocol GroupServicing` (51) verbatim and insert it after the `import` lines of `Features/Groups/GroupService.swift`.

- [ ] **Step 8: Move `NotificationServicing` into `Features/Notifications/NotificationService.swift`**

Cut `protocol NotificationServicing` (70) verbatim and insert it after the `import` lines of `Features/Notifications/NotificationService.swift`.

- [ ] **Step 9: Verify the original is fully drained, then delete it**

```bash
grep -nE "^(struct|enum|protocol|final class|class|actor) " Services/SocialServicing.swift
```

Expected: no output.

```bash
git rm Services/SocialServicing.swift
```

- [ ] **Step 10: Confirm every protocol survives exactly once**

```bash
grep -rhoE "^protocol (PostServicing|FeedServicing|MediaUploading|UsernameResolving|FriendServicing|GroupServicing|NotificationServicing)" Core Features | sort
```

Expected: seven lines, one per protocol, no duplicates.

- [ ] **Step 11: Run standard verification**

`FakeSocialServices.swift` conforming to all seven protocols is the strongest check here — if a protocol were dropped or altered, the test target would fail to compile.

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "refactor(services): move protocol seams beside their implementations"
```

---

## Task 10: Remove the empty legacy directories

**Files:**
- Delete dirs: `Models/`, `Views/`, `ViewModels/`, `Services/`
- Modify: `project.yml`, `.swiftlint.yml`

**Interfaces:**
- Consumes: Tasks 1–9 having emptied the legacy tree.
- Produces: the final source-root list that Task 12 documents in `AGENTS.md`.

- [ ] **Step 1: Confirm the legacy directories hold no Swift files**

```bash
find Models Views ViewModels Services -name '*.swift' 2>/dev/null
```

Expected: no output. If anything is listed, move it to its domain first — do not delete it.

- [ ] **Step 2: Confirm they hold no other tracked files**

```bash
git ls-files Models Views ViewModels Services
```

Expected: no output. If a non-Swift tracked file is listed, move it to the matching new location instead of deleting it.

- [ ] **Step 3: Remove the now-empty directories**

```bash
rmdir Views/Components Views/Sheets 2>/dev/null
rmdir Models Views ViewModels Services 2>/dev/null
find Models Views ViewModels Services -maxdepth 0 2>/dev/null
```

Expected: the final `find` prints nothing — all four are gone. `rmdir` refuses to delete a non-empty directory, so a failure here means Step 1 or 2 was not actually clean.

- [ ] **Step 4: Drop the legacy paths from `project.yml`**

The `BibleShare` target's `sources:` becomes exactly:

```yaml
    sources:
      - path: App
      - path: Core
      - path: Features
      - path: Shared
      - path: Resources
```

- [ ] **Step 5: Drop the legacy paths from `.swiftlint.yml`**

The `included:` list becomes exactly:

```yaml
included:
  - App
  - Core
  - Features
  - Shared
```

- [ ] **Step 6: Run standard verification**

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(structure): drop empty legacy layer directories"
```

---

## Task 11: Reorganize the test suite by domain

Pure file movement — no test logic changes. Same single test target, so no `@testable import` or target-membership edits. `BibleShareTests` is already a recursive source root in `project.yml`, so that file needs no change.

Per the spec, a test file that genuinely spans domains stays whole and is filed under its dominant domain: `SocialModelTests.swift` and `PostModelTests.swift` go to `Feed/` (post content is their dominant subject).

**Files:**
- Create dirs: `BibleShareTests/{Support,Auth,Profile,Feed,Compose,Friends,Groups,CheckIn,Notifications,Bible,Shared}/`
- Move: all 26 test files

**Interfaces:**
- Consumes: nothing from earlier tasks (tests are independent of the app-side folder layout).
- Produces: `BibleShareTests/Support/FakeSocialServices.swift` — still shared and **additive-only**; multiple suites depend on it.

- [ ] **Step 1: Create the destination directories**

```bash
mkdir -p BibleShareTests/{Support,Auth,Profile,Feed,Compose,Friends,Groups,CheckIn,Notifications,Bible,Shared}
```

- [ ] **Step 2: Move the shared support files**

```bash
git mv BibleShareTests/FakeSocialServices.swift BibleShareTests/Support/FakeSocialServices.swift
git mv BibleShareTests/MockAuthProvider.swift   BibleShareTests/Support/MockAuthProvider.swift
git mv BibleShareTests/TestDecoder.swift        BibleShareTests/Support/TestDecoder.swift
```

- [ ] **Step 3: Move the Auth and Profile tests**

```bash
git mv BibleShareTests/AuthViewModelTests.swift    BibleShareTests/Auth/AuthViewModelTests.swift
git mv BibleShareTests/AuthErrorTests.swift        BibleShareTests/Auth/AuthErrorTests.swift
git mv BibleShareTests/UsernameValidatorTests.swift BibleShareTests/Profile/UsernameValidatorTests.swift
```

- [ ] **Step 4: Move the Feed and Compose tests**

```bash
git mv BibleShareTests/TimelineViewModelTests.swift BibleShareTests/Feed/TimelineViewModelTests.swift
git mv BibleShareTests/FeedModelTests.swift         BibleShareTests/Feed/FeedModelTests.swift
git mv BibleShareTests/PostModelTests.swift         BibleShareTests/Feed/PostModelTests.swift
git mv BibleShareTests/PostServiceTests.swift       BibleShareTests/Feed/PostServiceTests.swift
git mv BibleShareTests/SocialModelTests.swift       BibleShareTests/Feed/SocialModelTests.swift
git mv BibleShareTests/ComposeViewModelTests.swift  BibleShareTests/Compose/ComposeViewModelTests.swift
```

- [ ] **Step 5: Move the Friends and Groups tests**

```bash
git mv BibleShareTests/FriendsViewModelTests.swift      BibleShareTests/Friends/FriendsViewModelTests.swift
git mv BibleShareTests/FriendEdgeTests.swift            BibleShareTests/Friends/FriendEdgeTests.swift
git mv BibleShareTests/GroupListViewModelTests.swift    BibleShareTests/Groups/GroupListViewModelTests.swift
git mv BibleShareTests/GroupTimelineViewModelTests.swift BibleShareTests/Groups/GroupTimelineViewModelTests.swift
git mv BibleShareTests/CreateGroupViewModelTests.swift  BibleShareTests/Groups/CreateGroupViewModelTests.swift
git mv BibleShareTests/GroupModelTests.swift            BibleShareTests/Groups/GroupModelTests.swift
```

- [ ] **Step 6: Move the CheckIn, Notifications, Bible, and Shared tests**

```bash
git mv BibleShareTests/CheckInViewModelTests.swift        BibleShareTests/CheckIn/CheckInViewModelTests.swift
git mv BibleShareTests/CheckinModelTests.swift            BibleShareTests/CheckIn/CheckinModelTests.swift
git mv BibleShareTests/CheckinReminderSchedulerTests.swift BibleShareTests/CheckIn/CheckinReminderSchedulerTests.swift
git mv BibleShareTests/NotificationsViewModelTests.swift  BibleShareTests/Notifications/NotificationsViewModelTests.swift
git mv BibleShareTests/NotificationModelTests.swift       BibleShareTests/Notifications/NotificationModelTests.swift
git mv BibleShareTests/NotificationDestinationTests.swift BibleShareTests/Notifications/NotificationDestinationTests.swift
git mv BibleShareTests/BibleServiceTests.swift            BibleShareTests/Bible/BibleServiceTests.swift
git mv BibleShareTests/AppRouterTests.swift               BibleShareTests/Shared/AppRouterTests.swift
```

- [ ] **Step 7: Confirm no test file was left behind**

```bash
find BibleShareTests -maxdepth 1 -name '*.swift'
```

Expected: no output — every test file now sits in a domain subfolder.

- [ ] **Step 8: Run standard verification**

The test count must match the Task 0 baseline exactly. A dropped test file would show as a lower count while still reporting `TEST SUCCEEDED`, so check the number, not just the status:

```bash
xcodebuild -scheme BibleShare -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData test 2>&1 | grep -E "Test run with"
```

Expected exactly: `✔ Test run with 141 tests in 23 suites passed`. This is the
task most likely to silently drop tests, so treat any other number as a failure
and find the missing file before committing.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "test(structure): reorganize test suite by domain"
```

---

## Task 12: Update documentation and run final verification

**Files:**
- Modify: `AGENTS.md` (Repo layout + Known Entry Points sections)

**Interfaces:**
- Consumes: the final tree from Tasks 1–11.
- Produces: documentation matching the shipped structure.

- [ ] **Step 1: Update the "Repo layout" section of `AGENTS.md`**

Replace the existing `- **Repo layout:**` bullet list with:

```markdown
- **Repo layout:**
  - `App/` — `@main` entry point + root view
  - `Core/` — cross-cutting infrastructure: `Supabase/` (client + secrets), `DesignSystem/`
    (Serene Light theme + controls), `Media/` (image processing, upload, remote images),
    `Models/` (shared kernel: `Profile`, `PostError`)
  - `Features/<Domain>/` — one self-contained folder per domain (Auth, Profile, Feed,
    Compose, Bible, Friends, Groups, CheckIn, Notifications), each co-locating its
    views, view models, services, protocol seams, and models
  - `Shared/` — app-level composition shell (`RootTabView`, `HomeView`, `AppRouter`)
  - `BibleShareTests/` — mirrors the feature domains; shared fakes in `Support/`
  - `supabase/` — migration SQL (applied via Supabase MCP, not CLI)
  - `docs/superpowers/` — specs (`specs/`) and implementation plans (`plans/`)
```

- [ ] **Step 2: Update the "Known Entry Points / Hot Spots" section of `AGENTS.md`**

Rewrite the path in each bullet to its new location. The mapping:

| Old path | New path |
|---|---|
| `App/BibleShareApp.swift` | unchanged |
| `App/RootView.swift` | unchanged |
| `Services/SupabaseService.swift` | `Core/Supabase/SupabaseService.swift` |
| `Services/SocialServicing.swift` | *(deleted — protocols now sit beside their implementations; say so)* |
| `Services/FriendService.swift` | `Features/Friends/FriendService.swift` (protocol `FriendServicing` now in the same file) |
| `Views/FriendsView.swift` | `Features/Friends/FriendsView.swift` |
| `Services/PostService.swift` | `Features/Feed/PostService.swift` |
| `ViewModels/CheckInViewModel.swift` + `Views/CheckInView.swift` | `Features/CheckIn/CheckInViewModel.swift` + `Features/CheckIn/CheckInView.swift` |
| `Views/Theme.swift` | `Core/DesignSystem/Theme.swift` |

Also update the `Services/SocialServicing.swift` mention in the **Gotchas / Conventions** section's "Protocol-seam pattern" bullet: the seams now live beside each service, and the shared fakes moved to `BibleShareTests/Support/FakeSocialServices.swift` (still additive-only).

- [ ] **Step 3: Confirm no stale paths remain in the docs**

```bash
grep -nE "(Models|Views|ViewModels|Services)/" AGENTS.md README.md
```

Expected: no hits pointing at the deleted top-level dirs. Matches like `Core/Models/` or `Features/Feed/` are fine — check each hit rather than assuming. Update `README.md` too if it describes the layout.

- [ ] **Step 4: Run standard verification one final time**

- [ ] **Step 5: Confirm the whole restructure preserved history and content**

```bash
git diff --stat --find-renames main...HEAD | tail -5
git ls-files '*.swift' | wc -l
```

Expected: the Swift file count equals the Task 0 baseline plus the net new files created by splitting (Task 6 turns 1 file into 5, Task 7 turns 1 into 2 new + 3 appends, Task 8 turns 1 into 1 new + 2 appends, Task 9 turns 1 into 2 new + 6 inserts) — that is, **baseline − 4 deleted + 10 created = baseline + 6**.

- [ ] **Step 6: Confirm no source file was orphaned from the build**

```bash
comm -23 <(git ls-files '*.swift' | grep -v '^BibleShareTests/' | sort) \
         <(git ls-files '*.swift' | grep -E '^(App|Core|Features|Shared)/' | sort)
```

Expected: no output — every non-test Swift file lives under a directory that `project.yml` actually compiles. A file listed here would still be in git but silently excluded from the target.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "docs(structure): update AGENTS.md for the domain-driven layout"
```

---

## Done criteria

All of the following hold:

1. `make generate`, `make build`, `make lint` all succeed.
2. The full suite reports exactly `Test run with 141 tests in 23 suites passed`.
3. `Models/`, `Views/`, `ViewModels/`, `Services/` no longer exist.
4. `project.yml` sources are exactly `App`, `Core`, `Features`, `Shared`, `Resources`.
5. `.swiftlint.yml` included is exactly `App`, `Core`, `Features`, `Shared`.
6. `git log` shows the moves as renames (`--find-renames`), preserving history.
7. `AGENTS.md` describes the new layout with no stale paths.
