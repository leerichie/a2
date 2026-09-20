# Changelog

## 1.0.0+55 — 2026-09-20

- Added the Firebase project and SDK wiring for the shared A² identity
  layer (a new, dedicated `a2-platform` Firebase project — kept separate
  from HorseVibe's own Firebase project). Firebase Core, Auth, and Sign
  in with Apple are now integrated and confirmed initializing correctly
  on a real iOS build. No sign-in UI yet — this is the plumbing only; the
  existing email/password + linked-Google account system is completely
  untouched and still the only way to sign in for now. Firebase never
  decides what anyone can access — that stays with this app's own server
  (see the 1.0.0+54 entitlements work).

## 1.0.0+54 — 2026-09-20

- Foundation for A² becoming a shared platform shell, not just the Health
  app. Signed-in accounts now land on a new A² dashboard that shows only
  the modules that account is entitled to (never a locked/greyed-out
  card for something it can't use) — Health is the first and currently
  only module, reached by tapping its card, with all of its existing
  functionality and data completely unchanged. A purely local (no
  account) user's experience is untouched — straight into Health, no
  dashboard, exactly as before.
  Server: new per-user `moduleAccess`/`membership` fields (existing users
  default to Health enabled, so nobody loses access), a module registry
  with a global on/off switch per module, and `GET
  /api/v1/auth/entitlements` returning exactly the modules an account can
  use. Admin console gained module toggle buttons and a membership
  selector per user, with membership deliberately kept independent of
  module access — Platinum does not imply every module. AI access stays
  its own separate toggle, unaffected by any of this.

## 1.0.0+53 — 2026-09-20

- Fixed private sync silently failing to retry: `uploadLocalData` never
  checked whether its upload actually succeeded (a rejected/failed upload
  looked identical to a successful one), and syncing on app resume only
  ever pulled from the server, never re-pushed — so a failed upload was
  never retried, and a later pull could silently overwrite not-yet-synced
  local changes with the server's stale copy. Syncing now always pushes
  first and only pulls once that push is confirmed to have succeeded, so
  a temporary offline moment retries automatically next time the app
  gets a chance to sync, instead of quietly losing data.

## 1.0.0+52 — 2026-09-20

- The app's default server address is no longer a Tailscale-only IP
  (`http://100.105.169.100:8094`) — it's now `https://api.ashleyrichards.tech`,
  a real public HTTPS endpoint reaching the same backend via a Cloudflare
  Tunnel from `aa-cloud-wp30`. Customer devices no longer need to be on the
  Tailscale tailnet to use the app; verified end-to-end from a phone on
  mobile data with Tailscale switched off. No server code changed — the
  existing Node backend and its data are untouched, Cloudflare just
  terminates TLS and tunnels to the same `localhost:8094` it always had.
  Tailscale stays installed on the server for private SSH/admin access.
  Override with `--dart-define=A2_SERVER_URL=...` for local/dev work.

## 1.0.0+51 — 2026-09-19

- Fixed a real overcounting bug found while testing the new "Ask AI" recipe
  flow: a "bowl of cornflakes with milk, toast with strawberry jam" entry
  came out ~150 kcal too high because neither "cornflakes" nor "jam" existed
  in the local food catalogue at all, so a bare "strawberry jam" mention
  fell through to a per-fragment AI guess with no context that it was a
  thin spread on toast — AI assumed something like a third of a jar
  (400g/250 kcal). Added real, local catalogue entries (nutrition + typical
  portion sizes) for cornflakes, muesli, granola, honey, peanut butter,
  chocolate spread/Nutella, marmalade, and jam, in both English and Polish
  — these now resolve instantly and correctly offline, no AI needed.
- Found and fixed a much bigger latent gap while auditing Polish food
  coverage: 15 common Polish dishes (pierogi, bigos, barszcz, żurek, rosół,
  gołąbki, flaki, kotlet schabowy, and others) were already "recognized" by
  the parser but had ZERO nutrition or portion data behind them — every
  single mention silently needed an AI call, forever, and could never
  resolve locally. All 15 now have real nutrition data and portion sizes.
  Also added kopytka, fermented pickled cucumber (ogórek kiszony, distinct
  from vinegar gherkins), and a generic "yellow cheese" (żółty ser) entry.
- Fixed a segmenter bug that could split a known compound dish name (e.g.
  "cottage cheese with chives") into two unrelated foods whenever an exact
  gram amount was typed in front of it (e.g. "100g cottage cheese with
  chives" wrongly became "100g cottage cheese" + a bare mention of
  "chives"). Found via the parser's own coverage tests once this dish
  finally had real nutrition data to check against.
- "Mashed" now joins "boiled" as a recognized preparation word, so "mashed
  potato" resolves the same way "boiled potato" already did.

## 1.0.0+50 — 2026-09-19

- Added an explicit "Ask AI to work this out" option to Add food/drink and
  Add exercise, for text neither the offline parser nor the normal AI
  fallback can handle — specifically a recipe or batch that yields several
  portions (e.g. "I ate 1 of the 6 waffles from this batter: 250g twaróg,
  3 eggs, ...") or a workout made of repeated rounds/sets. The AI now
  computes the batch's total nutrition/calories and divides by how many
  portions/rounds it makes, then a confirmation screen lets you edit the
  result and pick exactly how many portions you actually had before
  anything is logged — recomputing the totals live. What gets remembered
  for next time is always a single portion's nutrition (via the existing
  food catalogue), never multiplied by how many were eaten this time.
  Works in English and Polish (and the app's other languages), for any
  food, drink, or exercise description, not just this one example.

## 1.0.0+49 — 2026-09-18

- Extended beer's new default-serving behaviour to every other alcoholic
  drink: wine now defaults to a standard glass (150ml), whisky/vodka/gin/
  rum to a standard single measure (25ml) — a bare mention or plain count
  ("wine", "1 whisky") resolves immediately instead of asking for a
  measure, in both English and Polish. An explicit ml amount still always
  overrides the default.

## 1.0.0+48 — 2026-09-18

- Added generic Polish "surówka"/"surówki"/"surówkę" (a raw vegetable side
  salad/slaw — previously only the specific compound "surówka coleslaw"
  matched anything) resolving to the existing coleslaw data.
- Beer/piwo now resolves to a standard bottle/can serving even with no
  measure given ("piwo", "1 piwo"), matching how cola already behaves —
  an explicit exception to the "no default for alcohol" rule, which still
  applies to wine and spirits (their container sizes vary too widely to
  guess safely).

## 1.0.0+47 — 2026-09-18

- Fixed AI food/exercise/photo estimates never actually working: the code
  read a field (`output_text`) that only the official OpenAI SDK computes
  client-side, not something the API itself returns — every AI call has
  silently failed since this was built, always falling through to "please
  clarify" instead. Also switched the default model from `gpt-5` to
  `gpt-4o-mini`: this exact endpoint (a strict-JSON-schema structured
  extraction, no need for deep reasoning) reliably had `gpt-5` reason
  indefinitely without ever producing an answer, regardless of reasoning
  effort or output-token budget, whereas `gpt-4o-mini` answers correctly
  in 1-2 seconds — a large speed win on top of fixing the real bug.
  Verified end to end against the live server: English and Polish food
  descriptions and an exercise description all now resolve correctly and
  fast.

## 1.0.0+46 — 2026-09-18

- Fixed AI food/exercise estimates being very slow: the model was running
  at its default (extended) reasoning effort for a simple structured
  extraction task, and a description with two unrecognized items made two
  such slow calls back to back. Reasoning effort is now set explicitly low
  for both text estimates and photo/label reading, and multiple
  unrecognized components in one description now resolve concurrently
  instead of one after another.

## 1.0.0+45 — 2026-09-18

- Fixed six-a-side-style football aliases ("5 a side", "five a side")
  failing to resolve — generic filler-word stripping ("a", "an", "of") ran
  unconditionally before alias matching, so it could turn a real alias
  containing one of those words into one that no longer existed. The
  untouched phrase is now tried first.
- Added the 51 newly-added exercise activities' categories (combat_sport,
  water_sport, athletics, indoor_game) to the known-category list, and
  updated the catalogue-size regression guard (56 → 107) to match —
  dataset validation and exercise coverage tests are green again.
- Added the 7 missing translations (Meal weight, Optional, Salt, Saturated
  fat, Sugar, the units-understood hint, Whole pack weight) from the label
  editing screens across all six languages.

## 1.0.0+42 — 2026-09-18

- Fixed a silent edit/delete failure: editing or deleting a diary entry
  matched it back into the live list by object identity, so a background
  sync reload firing while the edit sheet was open (every 20s) made the
  save quietly no-op with no error shown. `FoodEntry` now has real value
  equality.
- Prepared/composite dishes mentioned with no quantity ("egg paste",
  "chicken curry", "carbonara", ...) now get a real standard-portion
  estimate instead of asking for manual calories every time: either
  borrowed from an already-real close relative (chicken/beef curry from
  curry, gyros/shawarma from kebab) or composed from real ingredient data
  via a new recipe mechanism (egg salad = 1 boiled egg + 1 tsp mayonnaise +
  a sprinkle of chives). Nothing at the dish level is invented -- every
  number traces back to an ingredient the app already trusted, or a
  dedicated real reference value for carbonara following the same
  convention already used for the other prepared dishes in this dataset.
- Added standalone "chives" (previously only reachable inside "cottage
  cheese with chives") with real nutrition data, and a "slice" portion rule
  for generic "cheese" (previously only the no-unit default worked).

## 1.0.0+41 — 2026-09-17

- Fixed `pubspec.yaml`'s package name field having been corrupted to
  `fluttername:` instead of `name:`, which blocked `flutter analyze` and any
  fresh dependency resolution (`flutter pub get` alone didn't surface it,
  since it can succeed off a stale lockfile) from working at all on a clean
  checkout. Verified clean afterwards: `flutter analyze` (0 issues) and the
  full test suite (503 tests) both pass.

## 1.0.0+40 — 2026-09-16

- Fixed Android release builds failing during R8 shrinking because the ML Kit
  Flutter wrapper references optional Chinese, Devanagari, Japanese and Korean
  text-recognition modules that a2 does not use. The release rules now suppress
  only those expected optional-module warnings; Latin label scanning remains
  included.

## 1.0.0+38 — 2026-09-15

- Made plain `flutter run` use the a2 server's direct private Tailscale address,
  avoiding emulator failures caused by the short server name not resolving.
- Allowed only local Flutter web pages (`localhost` and `127.0.0.1`) to call
  the private API, including Chrome's private-network check, so Chrome debug
  runs work without disabling browser security.
- Added an optional `A2_SERVER_URL` compile-time override for testing another
  server without editing source code.

## 1.0.0+37 — 2026-09-14

- Added the foundation for a centralized, canonical food/exercise text parser
  (`lib/parser/`, `assets/parser/`) to eventually replace the hardcoded
  `FoodEstimator`: quantity/fraction/measurement/portion/size/modifier
  parsing, a merged and de-duplicated 508-food + 55-activity catalogue, and
  dataset validation tooling. Not yet wired into the food add-flow.
- Replaced exercise's fixed kcal-per-minute guess with a real MET-based
  calculation (`activity MET × body weight × duration`), using the new
  activity catalogue and the user's own body weight from their profile.
  Calculation evidence (activity, MET, weight, duration) is now stored with
  each exercise entry.
- Made AI strictly local-first and non-authoritative for both food and
  exercise: the offline parser/estimator always runs first, AI is only
  consulted when it finds nothing at all, and if AI's answer can itself be
  resolved locally, the local deterministic numbers are kept over AI's.
  Fixed the Settings AI toggle showing "on" by default when the underlying
  setting actually defaulted to off.

## 1.0.0+36 — 2026-09-14

- Fixed simple water descriptions such as `glass water`, `half glass water`
  and `half bottle water` being rejected as incomplete nutrition information.
- Added glass, bottle and half-portion wording for water across English,
  Polish, German, French, Spanish and Italian. A glass is treated as 250 ml
  and a bottle as 500 ml unless an explicit volume is supplied.

## 1.0.0+35 — 2026-09-14

- Fixed deleted shared diary entries returning after restarting or syncing.
  Deletions now create persistent local markers that are sent to the server,
  including when the deletion happened while offline.
- Added stable IDs to newly shared entries and retained compatibility with
  existing shared entries, so intentional deletion is distinguished from a
  phone that has simply not downloaded a newly shared entry yet.

## 1.0.0+34 — 2026-09-14

- Removed the separate Add → Water option and shortened the remaining chooser
  label to simply "Food or drink".
- Made the normal food-or-drink description recognize water amounts in ml,
  litres, glasses and bottles and update the dashboard Water card directly.
- Added offline estimates and automatic Drinks categorization for common drinks
  including juice, coffee, tea, lemonade and soda. Caloric drinks contribute to
  the dashboard nutrition totals; plain water contributes only to hydration.

## 1.0.0+33 — 2026-09-14

- Aligned the dashboard calorie target with the body calculation in Settings.
  Completed body profiles now use their calculated maintenance as the default,
  so a 70 kg woman and a 90 kg man no longer both receive 2,100 kcal.
- Preserved deliberate plan limits: once someone edits or selects a diet-plan
  calorie target, that custom value remains instead of being overwritten by
  later body-profile calculations.
- Synced whether the calorie target is calculated or custom so the mobile app
  and console use the same source of truth.

## 1.0.0+32 — 2026-09-14

- Fixed the dashboard greeting using the hard-coded name Ashley for every
  account. It now uses the authenticated app user's name and refreshes after
  the name changes on the server.
- Added app-user name editing to the console's Details panel. The same account
  record is used whether registration happened in the app or the console.
- Stopped new accounts from inheriting or uploading Ashley's bundled private
  history when they have no history of their own. Local entries remain usable
  when the private server or Tailscale connection is unavailable.

## 1.0.0+31 — 2026-09-14

- Fixed the offline food estimator silently discarding coleslaw, bell pepper,
  pickle and fruit smoothie from a multi-item breakfast. The exact reported
  meal now produces a realistic typical-portion estimate instead of 145 kcal
  with only 2 g carbohydrate.
- Added regression coverage for that complete breakfast description so these
  components cannot disappear unnoticed again.

## 1.0.0+30 — 2026-09-13

- Console: added a way to create a real app account (with email, the way
  the mobile app actually signs in) directly from the console, instead of
  only being able to add console-login (username/password) accounts.
  Useful for setting someone up to link diary entries with before they've
  self-registered in the app.
- Corrected two already-logged entries on the live server that were caught
  by the old estimator bug (a coleslaw and a McDonald's order) to their
  accurate values.
- Verified the sign-out fix from 1.0.0+27 with an automated test — it
  works correctly in code; if it still doesn't take effect on a device, a
  full rebuild/reinstall of the app is needed, since deploying only updates
  the server.

## 1.0.0+29 — 2026-09-13

- Added diary entry sync between linked accounts: turn it on in Settings,
  choose which other registered accounts to link with, then tap the sync
  icon on any Today entry to copy it straight into their day.
- Made the Protein, Carbs and Water cards the same size, with the unit (g/ml)
  set smaller and right next to the number instead of a separate truncated
  "of X" line.
- Fixed today's entries not appearing in Progress or Journey — they only
  ever showed imported history, so anything logged today was invisible
  until it synced. The "Recorded energy" chart now also splits each day into
  separate coloured bars for food, drink and exercise.
- Rebuilt the free-text nutrition estimator: it now recognises whole
  fast-food and composite items (a Big Mac, fries, a cheeseburger, etc. by
  name, not just raw ingredients), correctly counts plain quantities like
  "2 whiskies" or "2x cheeseburgers", and no longer under-counts a composite
  item by only matching a short ingredient hiding inside its name (e.g.
  "cheese" inside "cheeseburgers"). Added trout, salmon, cod, salad and
  several other common ingredients that were previously ignored entirely.
- Console: added full control over other console accounts — promote to
  administrator, demote to view-only, or reset their password, matching the
  control already available for app users. The earlier view-only role was
  about console access only; app users are unaffected by it.

## 1.0.0+28 — 2026-09-13

- Added a restricted, view-only console access level: can see every user,
  their data and settings, but can't change, block, delete or reset
  anything — enforced server-side, not just hidden in the UI. Choose it
  when adding a console user under Users & security.
- Added an Activity view to the console showing a human-readable, most
  recent-first log of console actions (who blocked/unblocked, reset a
  password, changed sync/AI/role, edited data, updated AI settings, added
  or removed a console user, or signed in).

## 1.0.0+27 — 2026-09-13

- Fixed sign-out only clearing the account locally while leaving the app
  usable as if nothing happened — it now returns to a sign-in/onboarding
  screen for every sign-out path, with "keep using a2 locally" still
  available for anyone who prefers no account.
- Redesigned the Water card to sit on the same row as Protein and Carbs, as
  a compact glass that visually fills toward today's target. Dropped the
  "of target" text on all three cards to make room. Removed the separate
  "+ Add" button on the card — water is now logged from the same "Add"
  sheet as food, drink and exercise, and stays in sync the same way.

## 1.0.0+26 — 2026-09-13

- Added water intake tracking: a dedicated Water card on Today with a quick
  "+ Add" action (common amounts or a custom ml), a Water target in Settings
  (defaults to a recommendation based on your weight, editable), and full
  sync of both to the server and the console's per-user data editor.
- Fixed the free-text meal box always showing "not enough nutrition
  information" for water with no explanation — it now points at the new
  Water card instead.
- Disabled the "little nudge" card and its Settings toggle for now (the
  toggle never actually worked); the same dynamic message now lives in the
  calorie ring's headline instead.
- Fixed iOS Simulator builds failing on Apple Silicon Macs — Google ML
  Kit's pods ship no arm64 simulator slice, so simulator builds now use
  x86_64 for those pods (via Rosetta) instead of erroring out.

## 1.0.0+25 — 2026-09-13

- Fixed the dashboard greeting always saying "Good afternoon" and showing a
  fixed date, regardless of the actual time or day.
- Replaced the dead notification bell (it didn't do anything) with the a2
  logo.
- The "little nudge" card now actually responds to today's progress —
  encouraging a first meal, flagging an empty afternoon, celebrating hitting
  target, noting a day well over or well under, recognising a balanced day
  of food and exercise, and prompting more protein when it's low.

## 1.0.0+24 — 2026-09-13

- Fixed the iOS build failing to install pods after adding on-device label
  scanning — raised the iOS deployment target to 15.5, which the OCR
  library requires.

## 1.0.0+23 — 2026-09-13

- "Scan label" now reads nutrition labels on-device with no AI call and no
  cost: it recognises the printed text, finds the per-100g values and the
  pack weight (or serving size × servings per container), and calculates
  the total for the whole pack. Falls back to the AI photo reader (only
  when enabled) if the label can't be read confidently, then to manual
  entry.
- Fixed the console's Sync/AI buttons always showing green regardless of
  state, which read as "on" even when off — they now show the current
  state and turn red when off.

## 1.0.0+22 — 2026-09-13

- Fixed a layout crash opening Photo storage in Settings.
- Added an admin role for app users, set from the console (Users &
  security → "Make admin"). Regular accounts no longer see the Server,
  Content updates, or manual Private server sync controls in Settings —
  only an account promoted to admin does.

## 1.0.0+21 — 2026-09-13

- Replaced the default Flutter app icon and launch screen with the a2 mark
  on both Android and iOS.
- Added a small "built by Ashley Richards" badge, linking to
  ashleyrichards.tech, to onboarding, sign-in and Settings.
- Fixed the Add-meal sheet's error and notice messages appearing hidden
  behind the sheet until it closed — they now show inline, immediately.
- Fixed "Take photo"/"Scan label" doing nothing on a device or emulator
  with no usable camera — they now fall back to picking an existing photo.
- Added a direct sign-out button in Settings.
- The app now re-checks account status (private sync, AI access) with the
  server whenever it's resumed from the background, not only when opening
  a specific screen, so console changes reach the app sooner.

## 1.0.0+20 — 2026-09-13

- Fixed every server restart silently signing everyone out — sessions were
  only ever kept in memory, so a routine console deploy invalidated every
  signed-in device. Sessions now survive a graceful restart.
- Added the ability for a superadmin to reset any app user's password from
  the console. Resetting signs that device out (so it must sign back in
  with the new password) without touching any of their synced data.

## 1.0.0+19 — 2026-09-13

- Console user "Details" now shows and lets a superadmin edit everything
  synced for that account — daily entries for every logged day and the
  full history log, not just body profile and diet plan.

## 1.0.0+18 — 2026-09-13

- Removed the AI content-research/drafts/publish screen from the console —
  it wasn't used and left a button stuck "Researching…"; the console now
  opens straight to Users & security, with AI settings alongside it. The
  app's own content-update check is unaffected.
- Made per-user AI access reflect in the app as soon as it's used: opening
  Settings or the Add-food/exercise sheets now re-checks the account's AI
  access from the server first, instead of only at app launch.
- Taking a meal/drink photo now requires a description before it can be
  added, so an AI-estimated (or manually corrected) description is never
  skipped. Scanning a label can be added without a description, but a
  photo without one now assumes the whole label's contents were consumed.

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
