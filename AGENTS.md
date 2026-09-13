# a2 repository instructions

- After each major user-visible feature or substantial session change, bump the
  minor semantic version and increment the build number in `pubspec.yaml`.
- Use a patch bump for fixes and small refinements. Reserve major bumps for
  incompatible releases.
- Add the release summary to `CHANGELOG.md` in the same change.
- Run `dart run tool/bump_version.dart minor "Summary"` when appropriate, then
  run formatting, `flutter analyze`, and `flutter test`.
- Never put API keys, admin tokens, signing keys, or production secrets in Git.
- Every user-visible UI change must ship simultaneously in English, Polish,
  German, French, Spanish and Italian. Add or update all six entries in
  `lib/l10n.dart`, translate non-Text fields with `ui(context, ...)`, and run the
  localization coverage test before considering the change complete.
- Do not leave visible account, sync, camera, scan, or storage actions as empty
  placeholder callbacks. Either implement them end to end or label them clearly
  as unavailable.
