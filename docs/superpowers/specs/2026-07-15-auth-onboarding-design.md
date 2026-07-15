# BibleShare — Auth & Onboarding Design

**Date:** 2026-07-15
**Status:** Approved (design), pending implementation plan
**Scope:** Sign in / sign up (email/password + Google, Apple, Discord), a mandatory username step, and the signed-in Home shell. Home content itself is out of scope — it is an empty placeholder screen.

---

## 1. Goals & non-goals

**Goals**
- Users can create an account and sign in via email/password, Google, Apple, and Discord.
- Every user has a unique username, collected through a mandatory post-auth step that is uniform across all sign-in methods.
- A polished "Serene Light" login UI (approved mockup A), a username-setup screen, and an empty Home shell.

**Non-goals**
- Any Home feed / social feature content (posts, follows, likes, comments) — tables exist but no UI this round.
- Password reset, email-change, account deletion, profile editing beyond first username set. (Structured for later, not built now.)
- Custom SMTP / production email confirmation (deferred; dev uses auto-confirm).

---

## 2. Auth states & routing

`RootView` renders exactly one of three states, derived from `AuthViewModel`:

| State | Condition | Screen |
|---|---|---|
| **Signed out** | no Supabase `session` | `AuthView` |
| **Needs username** | `session` present, profile `username_set == false` | `UsernameSetupView` |
| **Ready** | `session` present, profile `username_set == true` | `HomeView` |

The username gate is enforced on **two** layers:
- **Client**: routing sends the user to `UsernameSetupView` and nowhere else until `username_set` is true.
- **Server**: RLS lets a user read/update only their own profile; the username uniqueness constraint and validation live in the database so the client cannot bypass them.

State transitions are driven by Supabase `authStateChanges` plus a profile fetch. On `signedIn`/`initialSession`, fetch the profile; on `signedOut`, clear it.

---

## 3. Backend / data model changes

Applied as a new migration (`supabase/migrations/<ts>_auth_onboarding.sql`) and via MCP `apply_migration`.

### 3.1 `profiles` changes
- Add `username_set boolean not null default false`.
- Add a case-insensitive uniqueness guarantee: `create unique index profiles_username_lower_idx on public.profiles (lower(username))`.
- Add a `CHECK` constraint for format: `username ~ '^[A-Za-z0-9_]{3,20}$'`.
- The existing `username unique not null` stays; the placeholder written by the trigger satisfies `not null`.

### 3.2 `handle_new_user` trigger
- `after insert on auth.users` → insert into `public.profiles (id, username, username_set)`.
- Temporary placeholder username: `'user_' || substr(replace(id::text,'-',''),1,12)` (guaranteed unique, passes the format check), `username_set = false`.
- `display_name` seeded from OAuth metadata (`raw_user_meta_data->>'full_name'` / `name`) when present, else null.
- Function is `security definer` with a locked `search_path`.

### 3.3 `is_username_available(candidate text) returns boolean`
- `security definer`, `search_path = public`.
- Returns true when `candidate` passes the format regex AND no other row has `lower(username) = lower(candidate)`.
- Granted to `authenticated` (and `anon` is not required).

### 3.4 RLS
- Keep existing policies. Ensure the profiles `UPDATE` policy uses `auth.uid() = id` for both `using` and `with check` so a user can set their own username exactly once (app enforces the "once" via `username_set`, DB allows self-updates).

### 3.5 Auth config (via MCP / dashboard)
- Set `mailer_autoconfirm = true` for dev (documented as a pre-production toggle-back).
- Enable Google, Apple, Discord providers (manual — see §8).

---

## 4. Swift architecture

### 4.1 `AuthProviding` protocol (new)
Abstracts the auth surface so `AuthViewModel` is testable:
```
protocol AuthProviding {
    var authStateChanges: AsyncStream<(AuthChangeEvent, Session?)> { get }
    func signUpEmail(email:password:) async throws
    func signInEmail(email:password:) async throws
    func signInWithIdToken(provider:idToken:nonce:) async throws   // Apple
    func startWebOAuth(provider:) async throws                     // Google, Discord
    func signOut() async throws
    func fetchProfile(userID:) async throws -> Profile?
    func setUsername(_:) async throws
    func isUsernameAvailable(_:) async throws -> Bool
}
```
`SupabaseService` conforms to it (thin wrapper over `supabase-swift`). Tests use a `MockAuthProvider`.

### 4.2 `AuthViewModel` (`@MainActor @Observable`)
- State: `session: Session?`, `profile: Profile?`, `isLoading`, `errorMessage`, `usernameStatus` (`.idle/.checking/.available/.taken/.invalid`).
- Derived: `route` → `.signedOut | .needsUsername | .ready`.
- Methods: `signUpEmail`, `signInEmail`, `signInWithGoogle`, `signInWithApple`, `signInWithDiscord`, `signOut`, `checkUsername(_:)` (debounced), `submitUsername(_:)`.
- Streams `authStateChanges`; on change, refreshes `profile`.

### 4.3 Providers
- **Email/password** — GoTrue `signUp` / `signIn`. With auto-confirm, sign-up yields an active session immediately → lands on username gate.
- **Google / Discord** — `ASWebAuthenticationSession` driven by `supabase-swift` `signInWithOAuth`, redirect `bibleshare://auth-callback`. The presentation-context provider is supplied from the app.
- **Apple** — native `ASAuthorizationController` (`SignInWithAppleButton`); take the returned identity token + raw nonce → `auth.signInWithIdToken(provider: .apple, ...)`. A cryptographic nonce (SHA256) is generated per attempt.
- **Deep linking** — register URL scheme `bibleshare` under `CFBundleURLTypes` in `project.yml`; `RootView`/App uses `.onOpenURL` to hand the callback URL to Supabase (`supabase.auth.session(from:)`).

### 4.4 Configuration
- `bibleshare://` scheme added to Info.plist additions in `project.yml`.
- The OAuth redirect URL is a constant in code, mirrored in the Supabase dashboard redirect allow-list.

---

## 5. UI — Serene Light design system

### 5.1 Theme
A `Theme` enum/namespace with the approved palette and type:
- Colors: `cream #FAF6EF`, `ink #1E1B4B`, `indigo #312E81`, `mutedText #78716C`, `field #FFFFFF`, `hairline #E7E0D5`, plus semantic success/danger.
- Wordmark uses a serif (system `.serif` design); body uses system sans.
- Shared radii/spacing constants.

### 5.2 Reusable components
- `SereneTextField` (rounded, hairline border), `SecureSereneField`.
- `PrimaryButton` (indigo fill, loading spinner state).
- `SocialButton(provider:)` (white, hairline, provider mark + label).
- `OrDivider(text:)`.

### 5.3 Screens
- **`AuthView`** — wordmark + tagline, email + password fields, primary Sign In, `OrDivider`, three `SocialButton`s, sign-in⇄sign-up toggle, inline error text, per-action loading. Sign-up mode uses the same fields (no username here — that's the gate).
- **`UsernameSetupView`** — title, `@`-prefixed field, **debounced** live availability via `checkUsername` (spinner → green ✓ "available" / red "taken" / "invalid characters"), format hint, `Continue` enabled only when `.available`, footer "Signed in as <email>" + Sign out.
- **`HomeView`** — top bar (serif wordmark + avatar circle with initial), centered empty state ("Welcome, @username" + "coming soon"), and a **minimal non-functional bottom tab-bar stub** (Home active; Search / Post / Profile placeholders, dimmed). Matches approved mockup.

---

## 6. Error handling

- One `mapAuthError(_:) -> String` used by all flows: invalid credentials, email already registered, weak password, network/offline, generic fallback.
- **OAuth cancellation** (user dismisses sheet / `ASWebAuthenticationSessionError.canceledLogin`) → silent no-op, not an error banner.
- **Username race**: if `submitUsername` fails on the DB unique index despite a prior "available" check, surface inline "that username was just taken."
- All thrown errors set `errorMessage`; success clears it.

---

## 7. Testing

- **Unit (view-model, mocked `AuthProviding`)**: route derivation for all three states; `usernameStatus` transitions (valid/invalid/taken/available); error mapping; OAuth-cancel is not an error.
- **Unit (pure)**: client-side username format validation matches the DB regex.
- **Backend (MCP `execute_sql`)**: inserting an `auth.users` row creates a `profiles` row with `username_set=false`; `is_username_available` returns correct results; RLS forbids updating another user's profile; `lower(username)` uniqueness rejects case-variant duplicates.
- **Manual smoke**: build + launch in iPhone 17 sim; email sign-up → username gate → Home; sign out → sign in; each OAuth provider once its credentials are configured.

---

## 8. Manual setup required (cannot be done by the agent)

1. **Apple Developer** (paid): enable "Sign in with Apple" capability on the app ID; create a Services ID + key for the token flow.
2. **Google Cloud**: OAuth 2.0 client; authorized redirect to the Supabase callback; copy client ID/secret.
3. **Discord Developer Portal**: application + OAuth2 redirect to the Supabase callback; copy client ID/secret.
4. **Supabase dashboard → Authentication → Providers**: enable Google, Apple, Discord; paste each client ID/secret.
5. **Supabase dashboard → URL Configuration**: add `bibleshare://auth-callback` to redirect allow-list.

The agent will: apply the DB migration, flip `mailer_autoconfirm` on, add the URL scheme to `project.yml`, and write all Swift/UI code. OAuth providers can be developed and merged before credentials exist; they light up once §8 is done. Email/password works end-to-end immediately.

---

## 9. Open items / future

- `handle_new_user` display-name seeding depends on each provider's metadata shape; verify per provider.
- Before production: set `mailer_autoconfirm = false`, add custom SMTP, and build the "check your inbox" + deep-link confirmation screen (path already accommodated by the state model).
- Username change flow (rate-limited) is a later feature.
