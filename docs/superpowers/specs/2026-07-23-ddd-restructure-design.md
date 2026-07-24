# Design: Domain-Driven File-Structure Restructure

**Date:** 2026-07-23
**Branch/worktree:** `claude/bibleshare-ddd-restructure-468223`
**Status:** Approved design — pending implementation plan

## Goal

Move BibleShare from its current **layer-first** file organization (`Models/`,
`Views/`, `ViewModels/`, `Services/`) to a **domain-driven** organization
(`Features/<Domain>/` + `Core/` + `Shared/`) so that a bug fix or new feature in
one domain (e.g. Notifications, Friends) touches a single self-contained folder
instead of four sibling trees.

Non-goals: no behavior changes, no dependency changes, no schema/RLS/RPC changes,
no test-logic changes. This is reorganization only.

## Why this is low-risk

Swift compiles every file in a target as one module regardless of folder, so
**moving files changes no symbol references and requires no `import` edits**.
XcodeGen derives Xcode groups from the filesystem (`createIntermediateGroups:
true`), so the mechanical loop per step is:

1. `git mv` files into the new tree (preserves history; shows as renames)
2. Update `sources:` in `project.yml`
3. `make generate` → `make build` → `make test`

The only genuine code edits come from splitting the four multi-domain
"catch-all" files (see §4). Those are pure *relocate-a-declaration* moves within
the same module — the moved `struct`/`enum`/`protocol` keeps its name and all
call sites keep compiling. No reference is rewritten.

## §1 — Target tree

```
App/                    (unchanged)
  BibleShareApp.swift
  RootView.swift

Core/                   (cross-cutting infrastructure + shared kernel)
  Supabase/
    SupabaseService.swift
    AppSecrets.swift             (Supabase URL/anon key from Secrets.plist)
  DesignSystem/
    Theme.swift
    SereneControls.swift
  Media/
    ImageProcessor.swift
    MediaUploader.swift          (+ MediaUploading protocol, see §4)
    RemoteImage.swift
    MediaStrip.swift
  Models/                        (shared kernel — types used by 3+ domains)
    Profile.swift                (Profile, ProfileUpdate)
    PostError.swift              (PostError — consumed by ~every ViewModel)

Features/
  Auth/
    AuthView.swift
    AuthViewModel.swift
    AuthProviding.swift
    AuthError.swift
  Profile/
    ProfileView.swift
    UsernameSetupView.swift
    UsernameValidator.swift
    UsernameResolving.swift      (UsernameResolving protocol, see §4)
  Feed/                          (content/posts bounded context — the hub)
    TimelineView.swift
    TimelineViewModel.swift
    CommentsView.swift
    CommentsViewModel.swift
    FeedLikeHandling.swift
    FeedService.swift            (+ FeedServicing protocol)
    PostService.swift            (+ PostServicing protocol — see decision D1)
    PostCell.swift
    ContentModels.swift          (Post, PostKind, Like, Comment, PostVerse,
                                  PostMedia, PostTag, MediaType)
    FeedModels.swift             (FeedItem, CommentItem, CountRow, TaggedUser)
  Compose/
    ComposeEncouragementView.swift
    ComposeViewModel.swift
    VerseCard.swift              (verse-picker UI — see decision D2)
    VersePickerSheet.swift
    UserTagSheet.swift
    ComposeParams.swift          (NewVerse, NewMediaItem, CreateEncouragementParams)
  Friends/
    FriendsView.swift
    FriendsViewModel.swift
    FriendService.swift          (+ FriendServicing protocol)
    FriendModels.swift           (Friendship, FriendStatus, FriendEdge)
  Groups/
    GroupsView.swift
    GroupTimelineView.swift
    CreateGroupView.swift
    GroupListViewModel.swift
    GroupTimelineViewModel.swift
    CreateGroupViewModel.swift
    GroupService.swift           (+ GroupServicing protocol)
    GroupModels.swift            (FellowshipGroup, GroupMember, GroupInvite,
                                  InviteStatus, CheckinCadence, CheckinWindow,
                                  GroupCheckin, GroupListItem, GroupMemberRow,
                                  GroupInviteRow, CreateGroupParams)
  CheckIn/
    CheckInView.swift
    CheckInViewModel.swift
    CheckinReminderScheduler.swift
    CheckInModels.swift          (CheckinTarget, CheckInParams)
  Notifications/
    NotificationsView.swift
    NotificationsViewModel.swift
    NotificationService.swift    (+ NotificationServicing protocol)
    NotificationRow.swift
    PushRegistrar.swift
    NotificationModels.swift     (AppNotification, NotificationType,
                                  NotificationItem, DeviceToken)
  Bible/
    BibleService.swift           (verse-lookup data source only — see decision D2)

Shared/                          (app-level composition / navigation shell)
  RootTabView.swift
  HomeView.swift
  AppRouter.swift
```

## §2 — Judgment calls (flagged for review)

These are the non-mechanical placement decisions. Each is resolved; flag any you
want changed.

- **D1 — `PostService`/`PostServicing` live in `Features/Feed/`.** Posts are the
  central content aggregate; `PostServicing` is consumed by Feed, Groups,
  Comments, and Compose ViewModels. Feed is the natural "content hub" owner. (This
  supersedes the initial sketch that placed `PostService` under Compose.) In Swift
  this cross-feature use needs no import, so it is organizational only.
- **D2 — Bible vs Compose verse UI.** `BibleService` (the verse-lookup data
  source) goes to `Features/Bible/`. The verse-*picking UI* (`VerseCard`,
  `VersePickerSheet`) goes to `Features/Compose/`, since it exists to build a
  post. Alternative: fold all verse UI into `Bible/`.
- **D3 — `PostError` → `Core/Models/`.** It is a trivial shared error enum used by
  nearly every ViewModel, so it is shared kernel, not Compose/Feed-owned.
- **D4 — `Profile`/`ProfileUpdate` → `Core/Models/`.** Identity entity decoded by
  Auth, Profile, Feed, Friends, Groups, Notifications. Shared kernel. The
  `Profile` *feature* folder holds only profile UI + username logic.
- **D5 — `Shared/` for the app shell.** `RootTabView`, `HomeView`, `AppRouter`
  compose multiple features and belong to no single domain; they sit in `Shared/`
  rather than `App/` (which stays limited to the `@main` entry + auth-gate root).

## §3 — Catch-all file split table

Each source file below is split by moving whole declarations into the destination
file, then deleting the emptied original. Names are unchanged, so all call sites
keep compiling.

### `Models/Models.swift` → dissolved into:

| Type | Destination |
|------|-------------|
| `Profile`, `ProfileUpdate` | `Core/Models/Profile.swift` |
| `Post`, `PostKind`, `Like`, `Comment`, `PostVerse`, `PostMedia`, `PostTag`, `MediaType` | `Features/Feed/ContentModels.swift` |
| `FellowshipGroup`, `GroupMember`, `GroupInvite`, `InviteStatus`, `CheckinCadence`, `CheckinWindow`, `GroupCheckin` | `Features/Groups/GroupModels.swift` |
| `Friendship`, `FriendStatus` | `Features/Friends/FriendModels.swift` |
| `AppNotification`, `NotificationType`, `DeviceToken` | `Features/Notifications/NotificationModels.swift` |

### `Models/FeedModels.swift` → dissolved into:

| Type | Destination |
|------|-------------|
| `FeedItem`, `CommentItem`, `CountRow`, `TaggedUser` | `Features/Feed/FeedModels.swift` |
| `PostSummary` | `Features/Notifications/NotificationModels.swift` (its only consumer is `NotificationItem`) |
| `FriendEdge` | `Features/Friends/FriendModels.swift` |
| `GroupListItem`, `GroupMemberRow`, `GroupInviteRow` | `Features/Groups/GroupModels.swift` |
| `CheckinTarget` | `Features/CheckIn/CheckInModels.swift` |
| `NotificationItem` | `Features/Notifications/NotificationModels.swift` |

### `Models/ComposeParams.swift` → dissolved into:

| Type | Destination |
|------|-------------|
| `NewVerse`, `NewMediaItem`, `CreateEncouragementParams` | `Features/Compose/ComposeParams.swift` |
| `CreateGroupParams` | `Features/Groups/GroupModels.swift` |
| `CheckInParams` | `Features/CheckIn/CheckInModels.swift` |

### `Services/SocialServicing.swift` → dissolved into (protocol lives beside its impl):

| Type | Destination |
|------|-------------|
| `PostServicing`, `PostError` | `PostServicing` → `Features/Feed/PostService.swift`; `PostError` → `Core/Models/PostError.swift` |
| `FeedServicing` | `Features/Feed/FeedService.swift` |
| `MediaUploading` | `Core/Media/MediaUploader.swift` |
| `UsernameResolving` | `Features/Profile/UsernameResolving.swift` |
| `FriendServicing` | `Features/Friends/FriendService.swift` |
| `GroupServicing` | `Features/Groups/GroupService.swift` |
| `NotificationServicing` | `Features/Notifications/NotificationService.swift` |

After distribution, `Models/Models.swift`, `Models/FeedModels.swift`,
`Models/ComposeParams.swift`, and `Services/SocialServicing.swift` are deleted,
and the now-empty `Models/`, `Services/`, `ViewModels/`, and `Views/` top-level
directories are removed.

## §4 — Test reorganization

Mirror the app domains under `BibleShareTests/`. Same single test target, so this
is pure movement (no `@testable import` or target-membership changes).

```
BibleShareTests/
  Support/            FakeSocialServices.swift, MockAuthProvider.swift, TestDecoder.swift
  Auth/               AuthViewModelTests.swift, AuthErrorTests.swift
  Profile/            UsernameValidatorTests.swift
  Feed/               TimelineViewModelTests.swift, FeedModelTests.swift,
                      PostModelTests.swift, PostServiceTests.swift, SocialModelTests.swift
  Compose/            ComposeViewModelTests.swift
  Friends/            FriendsViewModelTests.swift, FriendEdgeTests.swift
  Groups/             GroupListViewModelTests.swift, GroupTimelineViewModelTests.swift,
                      CreateGroupViewModelTests.swift, GroupModelTests.swift
  CheckIn/            CheckInViewModelTests.swift, CheckinModelTests.swift,
                      CheckinReminderSchedulerTests.swift
  Notifications/      NotificationsViewModelTests.swift, NotificationModelTests.swift,
                      NotificationDestinationTests.swift
  Shared/             AppRouterTests.swift
  (BibleServiceTests.swift → Bible/)
```

`FakeSocialServices.swift` stays **additive-only** and shared — its move to
`Support/` is a relocation, not a split. Exact per-file test placement (a few
tests, e.g. `SocialModelTests`, span domains) is finalized in the implementation
plan; when a test file genuinely spans domains it stays whole and is filed under
its dominant domain.

## §5 — `project.yml` changes

Replace the current `sources:` list:

```yaml
    sources:
      - path: App
      - path: Models
      - path: Views
      - path: ViewModels
      - path: Services
      - path: Resources
```

with:

```yaml
    sources:
      - path: App
      - path: Core
      - path: Features
      - path: Shared
      - path: Resources
```

`Resources` is unchanged. The `BibleShareTests` target still points at
`BibleShareTests` (folder-recursive), so its `sources:` needs no change even
after the internal test subfolders are added.

## §6 — Verification

Definition of done:

1. `make generate` succeeds (xcodegen regenerates the project from the new tree).
2. `make build` succeeds (Swift typecheck passes — proves no reference broke).
3. `make test` passes the **same** suite it passes on `main`
   (`platform=iOS Simulator,name=iPhone 17`).
4. `make lint` is clean.
5. `git diff --stat` on moved files shows renames (history preserved); for split
   files, lines removed from the catch-all equal lines added across destinations
   (net type count unchanged — spot-check the type inventory).
6. No file remains under the old `Models/`, `Views/`, `ViewModels/`, `Services/`
   top-level dirs; those dirs are gone.
7. `AGENTS.md` "Repo layout" and "Known Entry Points" sections updated to the new
   paths.

## §7 — Sequencing (for the implementation plan)

Restructure is safest done as **one commit per domain**, each independently
building, in dependency-friendly order so shared kernel exists before consumers:

1. `Core/` (Supabase, DesignSystem, Media, Models shared kernel) + `Shared/` app shell
2. `Auth/`, `Profile/`
3. `Feed/` (owns content models + PostService)
4. `Compose/`, `Bible/`
5. `Friends/`, `Groups/`, `CheckIn/`, `Notifications/`
6. Catch-all file splits (can interleave with the domain each type lands in)
7. Test reorg
8. `project.yml` + `AGENTS.md` + final full-suite verification

Because Swift has no cross-folder import barrier, an alternative is a single
big move commit; the phased approach is preferred purely for reviewability and
so `make build` can be run as a checkpoint after each phase.
