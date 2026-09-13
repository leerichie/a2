# Changelog

## 1.0.0+17 — 2026-09-13

- Synced saved diet plans, imported plan records, app language and the AI
  preference, not just body profile and the active plan.
- Added an admin console screen to view and edit an app user's stored body
  profile, active plan and daily target.
- Added a console-configured OpenAI API key and a per-user AI access toggle,
  gating new realtime AI endpoints for describing food, drink and exercise
  and for analysing meal and nutrition-label photos.
- Made the "Take photo" (renamed from "Meal photo") and "Scan label" buttons
  actually work: they capture a photo and, when AI is enabled for the
  account, prefill an estimate from it; otherwise they prompt for a manual
  description. AI now also assists the free-text food, drink and exercise
  estimates when available, falling back to the existing local estimator.
- Broadened the free-text example to cover drinks and snacks, not just food.
- Fixed modal sheets (Add menu, body/plan editors, day detail) sitting under
  the phone's gesture/navigation bar.

## 1.0.0+16 — 2026-09-13

- Refreshed account status from the server on every app launch, so a remotely
  toggled private sync, block, or account deletion takes effect immediately.
- Re-synced today's entries, history and plan after a successful launch sync
  so restarting the app shows the latest server-held data.

## 1.0.0+15 — 2026-09-13

- Added a second calorie ring for exercise-adjusted net energy.
- Replaced the hard-coded fibre card with calculated carbohydrate intake.
- Centralized calorie, protein and carbohydrate targets by active diet plan.
- Synced body and diet settings with account-owned private data.

## 1.0.0+14 — 2026-09-13

- Simplified daily cards to show time only and grouped entries by meal category.
- Removed one-time import branding and repeated estimate wording from history rows.
- Added account-owned private history sync and mandatory account onboarding.
- Added superadmin controls to enable private sync and block or delete app users.
- Added Google backup setup guidance for standard users.

## 1.0.0+13 — 2026-09-13

- Added a delete icon to each entry in today’s timeline.
- Added confirmation before deletion and immediately updates persisted daily totals.
- Added deletion text in all six supported languages.

## 1.0.0+12 — 2026-09-13

- Fixed successful console logins remaining visually stuck behind the login screen.
- Normalized the signed-in administrator response for account management.
- Preserved the password and displayed an error when dashboard loading fails.

## 1.0.0+11 — 2026-09-13

- Clarified that food and drink entries both count towards the day.
- Added quantity-aware calorie estimates for common alcoholic drinks, including whisky.
- Kept all changed interface text translated across the six supported languages.

All notable a2 releases are recorded here. The app uses semantic versions and
an always-increasing build number: `major.minor.patch+build`.

## 1.0.0+10 — 2026-09-13

- Made the web console self-contained by embedding its tested CSS and JavaScript
  into the login response, avoiding browser asset-loading failures.
- Added absolute fallback asset paths and prevented native form reloads.

## 1.0.0+9 — 2026-09-13

- Switched the default backend address to the memorable home-network URL
  `http://aa-cloud-wp30:8094` and migrated previously stored Tailscale URLs.
- Added narrowly scoped Android and iOS permissions for the local HTTP server.

## 1.0.0+8 — 2026-09-13

- Persisted food, drink and exercise entries in local device storage.
- Restored the current calendar day's timeline after app restart or emulator
  refresh while keeping records separated by day.

## 1.0.0+7 — 2026-09-13

- Fixed an apparently unresponsive web-console login caused by stale browser
  assets, with cache-busted files and explicit no-store response headers.
- Added visible login progress and browser error feedback.
- Redirected the server root and slashless `/admin` address to `/admin/` so
  browser-relative styles and scripts always load correctly.

## 1.0.0+6 — 2026-09-13

- Completed a global six-language UI audit and added an automated translation
  coverage test for future interface changes.
- Added real email registration, sign-in, persisted sessions and sign-out for
  mobile app accounts backed by the private A2 server.
- Replaced the invalid HTTPS-on-port-8094 address with the server's working
  Tailscale HTTPS endpoint and migrated the previously saved bad address.
- Added permanent repository rules requiring translations and forbidding empty
  placeholder actions in user-facing features.

## 1.0.0+5 — 2026-09-13

- Replaced the fixed demo meal result with quantity-aware nutrition estimates.
- Added a combined Add menu for food, drink and exercise entries.
- Fixed dynamic translated calorie and item counts displaying `$1`.
- Added console accounts, secure password hashing, session login, user management
  and a redesigned responsive administration interface.

## 1.0.0+4 — 2026-09-13

- Completed app-wide UI translation support for English, Polish, German,
  French, Spanish and Italian, including forms and dynamic status text.
- Added a dedicated responsive A2 console login and dashboard.
- Published the console on the server LAN at port 8094 while retaining private
  HTTPS access through Tailscale.

## 1.0.0+3 — 2026-09-13

- Added production Docker packaging for the controlled content service.
- Added persistent, restricted container storage and service health checks.
- Prepared private HTTPS delivery through the server's existing Tailscale setup.

## 1.0.0+2 — 2026-09-13

- Added personal body details and maintenance-calorie estimates.
- Added reusable diet profiles and built-in eating-style templates.
- Connected the active diet profile calorie target to Today.
- Added the controlled live-content server and browser admin console.
- Added AI-assisted research drafts, review, targeted publishing and withdrawal.
- Added HTTPS content update checks and offline caching in Flutter.

## 1.0.0+1 — 2026-09-13

- Initial a2 Flutter application.
- Added local food logging, progress views and imported diet history.
