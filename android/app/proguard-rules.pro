# The Flutter ML Kit wrapper supports optional recognizer scripts. a2 only
# requests the bundled Latin recognizer, so these absent optional modules are
# expected and must not make R8 fail the release build.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# R8 was stripping google_mlkit_commons.InputImageConverter entirely as
# "unreachable" -- it's only called via the plugin's own platform-channel
# dispatch, which R8's static analysis can't trace. That made every
# "Scan label" attempt throw immediately in release builds (confirmed
# 2026-09-24 via build/app/outputs/mapping/release/mapping.txt showing
# `com.google_mlkit_commons.InputImageConverter -> R8$$REMOVED$$CLASS$$`),
# while debug builds (no R8) were always unaffected -- hence "works after
# flutter run, breaks again on the real release APK".
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
