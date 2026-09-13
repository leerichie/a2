# a2 repository instructions

- After each major user-visible feature or substantial session change, bump the
  minor semantic version and increment the build number in `pubspec.yaml`.
- Use a patch bump for fixes and small refinements. Reserve major bumps for
  incompatible releases.
- Add the release summary to `CHANGELOG.md` in the same change.
- Run `dart run tool/bump_version.dart minor "Summary"` when appropriate, then
  run formatting, `flutter analyze`, and `flutter test`.
- Never put API keys, admin tokens, signing keys, or production secrets in Git.
