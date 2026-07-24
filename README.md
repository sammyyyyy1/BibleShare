# BibleShare

A native iOS (Swift / SwiftUI) social app with a Supabase backend.

## Requirements

- **Xcode** (latest — Xcode 26+ / iOS 26 SDK required for App Store submission as of April 2026). Deployment target is iOS 17.
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- (optional) [`swiftlint`](https://github.com/realm/SwiftLint) — `brew install swiftlint`

## Project layout

```
App/         App entry point (@main) and root view
Core/        Cross-cutting infrastructure: Supabase/ (client + secrets),
             DesignSystem/ (Serene Light theme + controls), Media/ (image
             processing, upload, remote images), Models/ (shared kernel:
             Profile, PostError)
Features/    One folder per domain (Auth, Profile, Feed, Compose, Bible,
             Friends, Groups, CheckIn, Notifications), each co-locating
             its views, view models, services, protocol seams, and models
Shared/      App-level composition shell (RootTabView, HomeView, AppRouter)
Resources/   Info.plist, Assets.xcassets, Secrets.plist(.example)
project.yml  XcodeGen project definition (edit this, not the .xcodeproj)
Makefile     build / run / lint workflow
```

The `.xcodeproj` is **generated** and git-ignored. Never hand-edit it — edit
`project.yml` and run `make generate` (or `xcodegen generate`).

## First-time setup

1. Install Xcode and the tools above.
2. Copy the secrets template and fill in your Supabase values:
   ```sh
   cp Resources/Secrets.plist.example Resources/Secrets.plist
   ```
   Find `SUPABASE_URL` and `SUPABASE_ANON_KEY` in the Supabase dashboard
   under **Project Settings → API**. `Secrets.plist` is git-ignored.
3. Generate and build:
   ```sh
   make run          # builds, boots the simulator, installs & launches
   ```

## Common commands

```sh
make generate   # regenerate the Xcode project from project.yml
make build      # build for the simulator
make run        # build + boot + install + launch
make lint       # SwiftLint (if installed)
make clean      # remove build artifacts
```

Override the simulator device: `make run DEVICE="iPhone 16 Pro"`.
