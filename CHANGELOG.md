# Changelog

All notable a2 releases are recorded here. The app uses semantic versions and
an always-increasing build number: `major.minor.patch+build`.

## 1.5.0+6 — 2026-09-13

- Completed a global six-language UI audit and added an automated translation
  coverage test for future interface changes.
- Added real email registration, sign-in, persisted sessions and sign-out for
  mobile app accounts backed by the private A2 server.
- Replaced the invalid HTTPS-on-port-8094 address with the server's working
  Tailscale HTTPS endpoint and migrated the previously saved bad address.
- Added permanent repository rules requiring translations and forbidding empty
  placeholder actions in user-facing features.

## 1.4.0+5 — 2026-09-13

- Replaced the fixed demo meal result with quantity-aware nutrition estimates.
- Added a combined Add menu for food, drink and exercise entries.
- Fixed dynamic translated calorie and item counts displaying `$1`.
- Added console accounts, secure password hashing, session login, user management
  and a redesigned responsive administration interface.

## 1.3.0+4 — 2026-09-13

- Completed app-wide UI translation support for English, Polish, German,
  French, Spanish and Italian, including forms and dynamic status text.
- Added a dedicated responsive A2 console login and dashboard.
- Published the console on the server LAN at port 8094 while retaining private
  HTTPS access through Tailscale.

## 1.2.0+3 — 2026-09-13

- Added production Docker packaging for the controlled content service.
- Added persistent, restricted container storage and service health checks.
- Prepared private HTTPS delivery through the server's existing Tailscale setup.

## 1.1.0+2 — 2026-09-13

- Added personal body details and maintenance-calorie estimates.
- Added reusable diet profiles and built-in eating-style templates.
- Connected the active diet profile calorie target to Today.
- Added the controlled live-content server and browser admin console.
- Added AI-assisted research drafts, review, targeted publishing and withdrawal.
- Added HTTPS content update checks and offline caching in Flutter.

## 1.0.0+1 — 2026-09-13

- Initial a2 Flutter application.
- Added local food logging, progress views and imported diet history.
