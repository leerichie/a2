# a2

A friendly, low-friction food and fitness companion built for Ashley & Ania—and private by default for everyone else.

## Product direction

- Log meals with a photo, nutrition label, or rough everyday portions.
- Show useful estimates and confidence ranges rather than fake precision.
- Combine food, movement, weight, measurements, progress photos, schedules, badges, and gentle notifications.
- Store data locally by default. An account and cloud backend are optional.
- Allow Ashley & Ania to connect to the private `aa-cloud-wp30` service for sync and a web admin console.
- Keep AI opt-in per user. Mobile clients call a server-side proxy; provider API keys must never be shipped in the app.

## Run

```sh
flutter pub get
flutter run
```

## Architecture roadmap

The current app is an interactive prototype with dashboard, meal logging, progress, journey, badges, and privacy settings. Next:

1. Local SQLite storage and an offline media queue.
2. Camera/gallery capture and image compression.
3. A versioned REST API on `aa-cloud-wp30` for opt-in auth, sync, media, and AI analysis.
4. A separately deployed Flutter web admin console, restricted to the private server's users.
5. Scheduled local notifications, with coaching preferences under user control.

The History section includes the first review workflow for ChatGPT shared conversations. Imported candidates retain their source, confidence, and whether they came from an explicit label or an AI estimate. Relative dates such as “today” are never guessed; they remain pending until confirmed.

Ashley’s private development build includes a decoded fixture from the shared “Keto Meal Plan Poland” conversation. It contains only reported consumption, activities and measurements; menu questions and general advice are excluded. The active conversation branch contains 382 messages and 83 user messages spanning 3 August–12 September 2026. The curated app dataset preserves exact values from labels, ranges for estimates, source evidence and original image asset IDs. Days without reliable reports stay blank.

The onboarding and navigation support English, Polish, German, French, Spanish, and Italian. Translation keys should move to ARB files as feature copy grows so every screen can be reviewed by native speakers.

### Accounts and storage modes

- **Local profile:** no registration; database and compressed images remain inside app-private device storage.
- **a2 account:** email/passkey or Google sign-in; enables encrypted sync through the configured a2 server.
- **Personal backup:** optional Google Drive export belonging to the user. This is backup, not the live application database.

Generate a display thumbnail plus an analysis-sized image on-device and avoid retaining full-resolution originals unless the user asks. Store only file references in the database, expose storage usage and cleanup controls, remove EXIF metadata before upload, and never silently copy health photos to a cloud provider.

### Recommended AI flow

`Flutter app → authenticated aa-cloud-wp30 endpoint → AI provider → structured nutrition estimate`

The backend should remove image metadata, enforce size/rate limits, validate structured output, return estimate ranges and confidence, and delete original analysis uploads according to a published retention setting. Public users can keep AI disabled unless they choose a hosted plan or connect a compatible server.

### brwoser testing

flutter run -d chrome --web-browser-flag="--disable-web-security"
