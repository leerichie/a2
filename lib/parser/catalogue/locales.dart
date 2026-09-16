/// Every locale pack installed under `assets/parser/`. Input recognition
/// is never limited to the app's selected UI language -- catalogue/lexicon
/// loaders merge every one of these into a single shared vocabulary (one
/// parser, not one per language), so a user can type "2 eggs, kromka
/// chleba, black coffee" and have every word recognized regardless of
/// which language the UI itself is displayed in. Add a new locale here
/// (and its `assets/parser/<code>/...` files) to make it recognized
/// everywhere at once.
const installedLocales = ['en', 'pl'];
