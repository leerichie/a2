# a2 repository instructions

- Keep the app version fixed at `1.0.0` and increment only the build number in
  `pubspec.yaml` after each substantial session change (`1.0.0+5`,
  `1.0.0+6`, and so on). Never bump the major, minor, or patch digits unless the
  user explicitly changes this policy.
- Add the release summary to `CHANGELOG.md` under the matching `1.0.0+build`
  heading, then run formatting, `flutter analyze`, and `flutter test`.
- Never put API keys, admin tokens, signing keys, or production secrets in Git.
- Every user-visible UI change must ship simultaneously in English, Polish,
  German, French, Spanish and Italian. Add or update all six entries in
  `lib/l10n.dart`, translate non-Text fields with `ui(context, ...)`, and run the
  localization coverage test before considering the change complete.
- Do not leave visible account, sync, camera, scan, or storage actions as empty
  placeholder callbacks. Either implement them end to end or label them clearly
  as unavailable.
