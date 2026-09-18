import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n.dart';
import 'parser/catalogue/activity_catalogue.dart';
import 'parser/catalogue/local_exercise_overlay.dart';
import 'parser/catalogue/local_overlay.dart';
import 'parser/exercise_parser.dart';
import 'parser/food_parser.dart';
import 'parser/models/food_parse_item.dart';
import 'parser/models/nutrient_totals.dart';
import 'parser/models/parse_confidence.dart';
import 'parser/models/unresolved_span.dart';
import 'parser/pipeline/text_folding.dart';
import 'services/app_update_service.dart';

void main() => runApp(const A2App());

/// Disabled for now — the standalone "little nudge" card was replaced by
/// HeroCard's dynamic headline. Flip back to true to restore it.
const showNudgeCard = false;

const ink = Color(0xFF17231E),
    forest = Color(0xFF1F684B),
    mint = Color(0xFFDDF3E7),
    cream = Color(0xFFF6F4EE),
    coral = Color(0xFFFF826D),
    gold = Color(0xFFF3C66E),
    aqua = Color(0xFF4FA8D8),
    success = Color(0xFF2E9E5B);

class A2App extends StatefulWidget {
  const A2App({super.key, this.startOnboarding = true});
  final bool startOnboarding;
  @override
  State<A2App> createState() => _A2AppState();
}

class _A2AppState extends State<A2App> with WidgetsBindingObserver {
  Locale locale = const Locale('en');
  late bool onboarding = widget.startOnboarding;
  bool ready = false;
  bool signedOut = false;
  final _navigatorKey = GlobalKey<NavigatorState>();
  DateTime? _lastUpdateCheckAt;
  bool _updateCheckRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maybeCheckForUpdate();
  }

  Future<void> _maybeCheckForUpdate() async {
    if (!ready || onboarding || signedOut || _updateCheckRunning) return;
    final now = DateTime.now();
    if (_lastUpdateCheckAt != null &&
        now.difference(_lastUpdateCheckAt!) < const Duration(minutes: 5)) {
      return;
    }
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    _updateCheckRunning = true;
    _lastUpdateCheckAt = now;
    try {
      await AppUpdateService.checkForUpdate(navContext);
    } finally {
      _updateCheckRunning = false;
    }
  }

  Future<void> _restore() async {
    if (!widget.startOnboarding) {
      setState(() => ready = true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      locale = Locale(prefs.getString('language') ?? 'en');
      onboarding = !(prefs.getBool('onboarding_complete') ?? false);
      ready = true;
    });
  }

  Future<void> _setLocale(Locale value) async {
    setState(() => locale = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', value.languageCode);
    await const AccountService().uploadLocalData(defaultServerUrl);
  }

  Future<void> _finishOnboarding() async {
    setState(() => onboarding = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
  }

  void _handleSignedOut() => setState(() => signedOut = true);

  void _handleGateDismissed() => setState(() => signedOut = false);

  @override
  Widget build(BuildContext context) {
    if (ready && !onboarding && !signedOut) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeCheckForUpdate(),
      );
    }
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'a2',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLanguage.values.map((e) => Locale(e.code)),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: cream,
        colorScheme: ColorScheme.fromSeed(seedColor: forest, surface: cream),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
        ),
      ),
      home: !ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : onboarding
          ? OnboardingPage(
              locale: locale,
              onLocale: _setLocale,
              onDone: _finishOnboarding,
            )
          : signedOut
          ? Scaffold(
              body: SafeArea(
                child: AccountSheet(
                  serverUrl: defaultServerUrl,
                  accountEmail: null,
                  onDismiss: _handleGateDismissed,
                ),
              ),
            )
          : AppShell(
              locale: locale,
              onLocale: _setLocale,
              onSignedOut: _handleSignedOut,
            ),
    );
  }
}

enum AppLanguage {
  english('en', 'English', 'English'),
  polish('pl', 'Polski', 'Polish'),
  german('de', 'Deutsch', 'German'),
  french('fr', 'Français', 'French'),
  spanish('es', 'Español', 'Spanish'),
  italian('it', 'Italiano', 'Italian');

  const AppLanguage(this.code, this.nativeName, this.englishName);
  final String code, nativeName, englishName;
}

const copy = <String, Map<String, String>>{
  'en': {
    'welcome': 'Health tracking that fits real life',
    'intro': 'Photos, spoonfuls and rough portions are enough. a2 turns them into useful trends without pretending every estimate is exact.',
    'next': 'Continue',
    'privacy': 'Private by default',
    'privacyBody': 'Start without an account. Your records and compressed photos stay on this phone unless you choose backup or sync.',
    'account': 'Your choice of account',
    'accountBody': 'Use a2 locally, sign in for cross-device sync, or connect your own storage. You stay in control.',
    'start': 'Start using a2',
    'today': 'Today',
    'progress': 'Progress',
    'journey': 'Journey',
    'you': 'You',
  },
  'pl': {
    'welcome': 'Zdrowie dopasowane do życia',
    'intro': 'Zdjęcia, łyżki i przybliżone porcje wystarczą. a2 pokazuje użyteczne trendy bez udawanej precyzji.',
    'next': 'Dalej',
    'privacy': 'Prywatność od początku',
    'privacyBody': 'Zacznij bez konta. Dane i skompresowane zdjęcia zostają w telefonie, dopóki nie wybierzesz kopii lub synchronizacji.',
    'account': 'Konto na twoich zasadach',
    'accountBody': 'Używaj lokalnie, zaloguj się do synchronizacji albo podłącz własne miejsce.',
    'start': 'Zacznij korzystać',
    'today': 'Dzisiaj',
    'progress': 'Postępy',
    'journey': 'Historia',
    'you': 'Ty',
  },
  'de': {
    'welcome': 'Gesundheit, die ins Leben passt',
    'intro': 'Fotos, Löffel und grobe Portionen reichen. a2 macht daraus hilfreiche Trends ohne falsche Genauigkeit.',
    'next': 'Weiter',
    'privacy': 'Standardmäßig privat',
    'privacyBody': 'Starte ohne Konto. Daten und komprimierte Fotos bleiben auf diesem Gerät, bis du Backup oder Sync wählst.',
    'account': 'Deine Kontoentscheidung',
    'accountBody': 'Lokal nutzen, für Synchronisierung anmelden oder eigenen Speicher verbinden.',
    'start': 'a2 starten',
    'today': 'Heute',
    'progress': 'Fortschritt',
    'journey': 'Verlauf',
    'you': 'Du',
  },
  'fr': {
    'welcome': 'Le suivi santé adapté à la vraie vie',
    'intro': 'Photos, cuillerées et portions approximatives suffisent. a2 crée des tendances utiles sans fausse précision.',
    'next': 'Continuer',
    'privacy': 'Privé par défaut',
    'privacyBody': 'Commencez sans compte. Données et photos compressées restent sur ce téléphone sans sauvegarde choisie.',
    'account': 'Votre choix de compte',
    'accountBody': 'Utilisez a2 localement, connectez-vous pour synchroniser ou utilisez votre stockage.',
    'start': 'Commencer avec a2',
    'today': "Aujourd’hui",
    'progress': 'Progrès',
    'journey': 'Parcours',
    'you': 'Vous',
  },
  'es': {
    'welcome': 'Salud que encaja en la vida real',
    'intro': 'Fotos, cucharadas y porciones aproximadas bastan. a2 crea tendencias útiles sin fingir precisión.',
    'next': 'Continuar',
    'privacy': 'Privado por defecto',
    'privacyBody': 'Empieza sin cuenta. Tus datos y fotos comprimidas quedan en el teléfono salvo que elijas copia o sincronización.',
    'account': 'Tú eliges la cuenta',
    'accountBody': 'Usa a2 localmente, inicia sesión para sincronizar o conecta tu almacenamiento.',
    'start': 'Empezar con a2',
    'today': 'Hoy',
    'progress': 'Progreso',
    'journey': 'Recorrido',
    'you': 'Tú',
  },
  'it': {
    'welcome': 'Salute adatta alla vita reale',
    'intro': 'Foto, cucchiai e porzioni approssimative bastano. a2 crea tendenze utili senza falsa precisione.',
    'next': 'Continua',
    'privacy': 'Privato per impostazione',
    'privacyBody': 'Inizia senza account. Dati e foto compresse restano sul telefono finché non scegli backup o sincronizzazione.',
    'account': 'Scegli tu l’account',
    'accountBody':
        'Usa a2 in locale, accedi per sincronizzare o collega il tuo spazio.',
    'start': 'Inizia con a2',
    'today': 'Oggi',
    'progress': 'Progressi',
    'journey': 'Percorso',
    'you': 'Tu',
  },
};
String tr(Locale locale, String key) =>
    copy[locale.languageCode]?[key] ?? copy['en']![key] ?? key;

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.locale,
    required this.onLocale,
    required this.onDone,
  });
  final Locale locale;
  final ValueChanged<Locale> onLocale;
  final VoidCallback onDone;
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final controller = PageController();
  int page = 0;
  static const icons = [
    Icons.auto_awesome,
    Icons.shield_outlined,
    Icons.person_outline,
  ];
  static const keys = [
    ('welcome', 'intro'),
    ('privacy', 'privacyBody'),
    ('account', 'accountBody'),
  ];
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          children: [
            Row(
              children: [
                const LText(
                  'a²',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: forest,
                  ),
                ),
                const Spacer(),
                PopupMenuButton<AppLanguage>(
                  initialValue: AppLanguage.values.firstWhere(
                    (e) => e.code == widget.locale.languageCode,
                  ),
                  onSelected: (v) => widget.onLocale(Locale(v.code)),
                  itemBuilder: (_) => AppLanguage.values
                      .map(
                        (e) => PopupMenuItem(
                          value: e,
                          child: LText('${e.nativeName} · ${e.englishName}'),
                        ),
                      )
                      .toList(),
                  child: Chip(
                    avatar: const Icon(Icons.language, size: 18),
                    label: LText(
                      AppLanguage.values
                          .firstWhere(
                            (e) => e.code == widget.locale.languageCode,
                          )
                          .nativeName,
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: PageView(
                controller: controller,
                onPageChanged: (v) => setState(() => page = v),
                children: List.generate(
                  3,
                  (i) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          color: [
                            mint,
                            const Color(0xFFFFE5DD),
                            const Color(0xFFFFF0CE),
                          ][i],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icons[i],
                          size: 68,
                          color: i == 1 ? coral : forest,
                        ),
                      ),
                      const SizedBox(height: 42),
                      LText(
                        tr(widget.locale, keys[i].$1),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          height: 1.08,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LText(
                        tr(widget.locale, keys[i].$2),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(4),
                  width: i == page ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == page ? forest : Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ink,
                  padding: const EdgeInsets.all(18),
                ),
                onPressed: () async {
                  if (page < 2) {
                    controller.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  } else {
                    final created = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const AccountSheet(
                        serverUrl: defaultServerUrl,
                        accountEmail: null,
                        initialRegister: true,
                        accountRequired: true,
                      ),
                    );
                    if (created == true) widget.onDone();
                  }
                },
                child: LText(
                  tr(widget.locale, page == 2 ? 'start' : 'next'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const DevBadge(),
          ],
        ),
      ),
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.locale,
    required this.onLocale,
    required this.onSignedOut,
  });
  final Locale locale;
  final ValueChanged<Locale> onLocale;
  final VoidCallback onSignedOut;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int index = 0;
  int importedCount = 0;
  int dailyTarget = 2100;
  String dietStyle = 'Balanced';
  double? bodyWeightKg;
  int waterMl = 0;
  int waterTargetMl = 2000;
  bool entrySyncAvailable = false;
  String accountName = '';
  bool accountAiEnabled = false;
  // Real MET for a brisk walk, read once from the shared activity catalogue
  // (never invented) for the daily nudge's exercise-duration suggestion.
  double walkMet = 4.8;
  final entries = <FoodEntry>[];
  List<DayPhoto> photos = [];
  List<HistoryRecord> history = [];
  int get calories => entries
      .where((entry) => !entry.isExercise)
      .fold(0, (sum, entry) => sum + entry.calories);
  int get protein => entries.fold(0, (s, e) => s + e.protein);
  int get carbs => entries.fold(0, (s, e) => s + e.carbs);
  int get exerciseCalories => entries
      .where((entry) => entry.isExercise)
      .fold(0, (sum, entry) => sum + entry.calories);
  List<HistoryRecord> get combinedHistory {
    final today = dayOnly(DateTime.now());
    final withoutToday = history.where((r) => dayOnly(r.at) != today).toList();
    final todayRecords = entries
        .map((e) => HistoryRecord.fromFoodEntry(e, today))
        .toList();
    return [...todayRecords, ...withoutToday]
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  // Foreground-only, bounded-interval re-check for anything shared into
  // this account while the app is already open -- deliberately NOT a
  // 1-second poll (see corrective-pass notes): the actual delay users hit
  // is "nothing re-checks at all while Today is already open", not the
  // backend write itself, which is near-instant. 20s keeps the wait to
  // "seconds, not minutes" without hammering the server.
  Timer? _syncTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreAndSync();
    _loadWalkMet();
    _syncTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _restoreAndSync(),
    );
  }

  Future<void> _loadWalkMet() async {
    final catalogue = await ActivityCatalogue.load();
    for (final entry in catalogue.entries) {
      if (entry.id == 'brisk_walking') {
        if (mounted) setState(() => walkMet = entry.met);
        return;
      }
    }
  }

  // Fires a brief, tasteful celebration the first time a daily target is
  // crossed—never for going over the calorie target—persisting a per-day
  // flag so it never repeats on rebuild/navigation.
  Future<void> _checkAchievements() async {
    final targets = NutritionTargets.forPlan(
      calories: dailyTarget,
      style: dietStyle,
      weightKg: bodyWeightKg,
    );
    final netCalories = math.max(0, calories - exerciseCalories);
    final hasExercise = entries.any((e) => e.isExercise);
    final waterDone = waterTargetMl > 0 && waterMl >= waterTargetMl;
    final proteinDone = targets.protein > 0 && protein >= targets.protein;
    final achievements = <String, bool>{
      'protein': proteinDone,
      'water': waterDone,
      'activity': hasExercise,
      'strong_day':
          targets.calories > 0 &&
          netCalories <= targets.calories &&
          netCalories >= targets.calories * 0.85 &&
          proteinDone &&
          (waterDone || hasExercise),
    };
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final dateKey = '${now.year}-${now.month}-${now.day}';
    for (final achievement in achievements.entries) {
      if (!achievement.value) continue;
      final flagKey = 'celebrated_${achievement.key}_$dateKey';
      if (prefs.getBool(flagKey) == true) continue;
      await prefs.setBool(flagKey, true);
      if (mounted) _celebrate(achievement.key);
    }
  }

  void _celebrate(String achievementId) {
    final icon = switch (achievementId) {
      'water' => Icons.water_drop,
      'activity' => Icons.local_fire_department,
      'strong_day' => Icons.emoji_events,
      _ => Icons.check_circle,
    };
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) =>
          _CelebrationBadge(icon: icon, onDone: () => entry.remove()),
    );
    overlay.insert(entry);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restoreAndSync();
      _syncTimer?.cancel();
      _syncTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _restoreAndSync(),
      );
    } else {
      // Never poll while backgrounded -- resume picks up immediately above.
      _syncTimer?.cancel();
    }
  }

  Future<void> _restoreAndSync() async {
    await Future.wait([
      _loadTodayEntries(),
      _loadTodayPhotos(),
      _loadImports(),
      _loadHistory(),
      _loadPlan(),
      _loadWater(),
      _loadEntrySyncAvailability(),
      _loadAccountName(),
    ]);
    // Fire-and-forget: the app already has a working local catalogue, this
    // just quietly picks up whatever's new since last time.
    unawaited(const CatalogueSyncService().sync(defaultServerUrl));
    unawaited(const ExerciseCatalogueSyncService().sync(defaultServerUrl));
    try {
      final enabled = await const AccountService().refreshAccount(
        defaultServerUrl,
      );
      await _loadAccountName();
      if (!enabled) return;
      await const AccountService().synchronise(defaultServerUrl);
      await Future.wait([
        _loadTodayEntries(),
        _loadHistory(),
        _loadPlan(),
        _loadWater(),
        _loadEntrySyncAvailability(),
      ]);
    } catch (_) {
      // The local app remains usable when the server is offline or signed out.
    }
  }

  Future<void> _loadEntrySyncAvailability() async {
    final available = await const EntrySyncService().isAvailable();
    if (mounted) setState(() => entrySyncAvailable = available);
  }

  Future<void> _loadAccountName() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('account_user');
    final user = raw == null
        ? const <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    final name = (user['name'] as String? ?? '').trim();
    final aiEnabled = user['aiEnabled'] == true;
    if (mounted) {
      setState(() {
        accountName = name;
        accountAiEnabled = aiEnabled;
      });
    }
  }

  // Any attached photo must reach the backend BEFORE the entry itself is
  // shared -- a local filesystem path is meaningless on the recipient's
  // device (see MediaService/FoodEntry.forSharing). A failed upload throws
  // here and surfaces as an error to the sender (see FoodTile._handleSync)
  // rather than silently sharing an entry with a dangling photo reference.
  Future<void> _shareEntry(FoodEntry entry) async {
    var toShare = entry;
    if (entry.photoPaths.isNotEmpty) {
      final mediaIds = <String>[];
      for (final path in entry.photoPaths) {
        final file = File(path);
        if (!await file.exists()) continue;
        mediaIds.add(await const MediaService().upload(defaultServerUrl, file));
      }
      toShare = entry.forSharing(mediaIds: mediaIds);
    }
    await const EntrySyncService().shareEntry(
      defaultServerUrl,
      toShare,
      DateTime.now(),
    );
  }

  Future<void> _loadTodayEntries() async {
    final restored = await const DailyEntryRepository().load(DateTime.now());
    if (mounted) {
      setState(() {
        entries
          ..clear()
          ..addAll(restored);
      });
    }
  }

  Future<void> _saveTodayEntries() async {
    await const DailyEntryRepository().save(DateTime.now(), entries);
    await const AccountService().uploadLocalData(defaultServerUrl);
  }

  Future<void> _loadTodayPhotos() async {
    final restored = await const DayPhotoRepository().load(DateTime.now());
    if (mounted) setState(() => photos = restored);
  }

  Future<void> _loadWater() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = await const WaterRepository().load(DateTime.now());
    if (mounted) {
      setState(() {
        waterMl = loaded;
        waterTargetMl =
            prefs.getInt('water_target_ml') ?? recommendedWaterMl(bodyWeightKg);
      });
    }
  }

  Future<void> _addWater(int ml) async {
    final updated = math.max(0, waterMl + ml);
    setState(() => waterMl = updated);
    await const WaterRepository().save(DateTime.now(), updated);
    await const AccountService().uploadLocalData(defaultServerUrl);
    _checkAchievements();
  }

  Future<void> _loadPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final planRaw = prefs.getString('active_diet_plan');
    final bodyRaw = prefs.getString('body_profile');
    final loadedBody = bodyRaw == null
        ? const BodyProfile()
        : BodyProfile.fromJson(jsonDecode(bodyRaw) as Map<String, dynamic>);
    final storedTarget = prefs.getInt('daily_target') ?? 2100;
    final loadedTarget = resolvedDailyTarget(
      loadedBody,
      storedTarget: storedTarget,
      customized: prefs.getBool('daily_target_custom') == true,
    );
    if (loadedTarget != storedTarget) {
      await prefs.setInt('daily_target', loadedTarget);
      if (planRaw != null) {
        final loadedPlan = DietPlan.fromJson(
          jsonDecode(planRaw) as Map<String, dynamic>,
        );
        await prefs.setString(
          'active_diet_plan',
          jsonEncode(loadedPlan.copyWith(target: loadedTarget).toJson()),
        );
      }
    }
    if (mounted) {
      setState(() {
        dailyTarget = loadedTarget;
        if (planRaw != null) {
          final loadedPlan = DietPlan.fromJson(
            jsonDecode(planRaw) as Map<String, dynamic>,
          );
          dietStyle = loadedPlan.style;
        }
        bodyWeightKg = loadedBody.weightKg;
      });
    }
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('personal_history_cache');
    final raw = jsonDecode(stored ?? '{"records":[]}') as Map<String, dynamic>;
    final loaded =
        (raw['records'] as List)
            .map((e) => HistoryRecord.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));
    if (mounted) {
      setState(() {
        history = loaded;
        importedCount = loaded.length;
      });
    }
  }

  Future<void> _loadImports() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
        () => importedCount = math.max(
          importedCount,
          (prefs.getStringList('imported_record_ids') ?? []).length,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = NutritionTargets.forPlan(
      calories: dailyTarget,
      style: dietStyle,
      weightKg: bodyWeightKg,
    );
    final pages = [
      TodayPage(
        accountName: accountName,
        entries: entries,
        photos: photos,
        calories: calories,
        protein: protein,
        carbs: carbs,
        exerciseCalories: exerciseCalories,
        targets: targets,
        waterMl: waterMl,
        waterTargetMl: waterTargetMl,
        onAddWater: _addWater,
        bodyWeightKg: bodyWeightKg,
        locale: widget.locale.languageCode,
        entrySyncAvailable: entrySyncAvailable,
        onSyncEntry: _shareEntry,
        onRefresh: _restoreAndSync,
        walkMet: walkMet,
        onDelete: (entry) async {
          await const AccountService().recordDeletedEntry(
            entry,
            DateTime.now(),
          );
          setState(() => entries.remove(entry));
          await _saveTodayEntries();
        },
        onEditEntry: (oldEntry, newEntry) {
          final index = entries.indexOf(oldEntry);
          if (index == -1) return;
          setState(() => entries[index] = newEntry);
          _saveTodayEntries();
          _checkAchievements();
        },
      ),
      ProgressPage(importedCount: importedCount, history: combinedHistory),
      JourneyPage(history: combinedHistory),
      ProfilePage(
        locale: widget.locale,
        onLocale: widget.onLocale,
        onImported: _loadImports,
        dailyTarget: dailyTarget,
        dietStyle: dietStyle,
        aiEnabled: accountAiEnabled,
        onPlanChanged: (value) => setState(() {
          dailyTarget = value.target;
          dietStyle = value.style;
        }),
        onBodyChanged: (value) => setState(() {
          bodyWeightKg = value.weightKg;
        }),
        onSignedOut: widget.onSignedOut,
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) {
          setState(() => index = v);
          if (v == 0) _restoreAndSync();
        },
        indicatorColor: mint,
        backgroundColor: Colors.white,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: tr(widget.locale, 'today'),
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: tr(widget.locale, 'progress'),
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: tr(widget.locale, 'journey'),
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: tr(widget.locale, 'you'),
          ),
        ],
      ),
      floatingActionButton: index == 0
          ? FloatingActionButton.extended(
              backgroundColor: forest,
              foregroundColor: Colors.white,
              elevation: 2,
              highlightElevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              icon: const Icon(Icons.add_rounded, size: 26),
              label: const LText(
                'Add',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              onPressed: () async {
                final result = await showModalBottomSheet<Object>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => AddItemSheet(
                    onAddWater: _addWater,
                    entries: entries,
                    bodyWeightKg: bodyWeightKg,
                    locale: widget.locale.languageCode,
                  ),
                );
                if (result case final PhotoAttachOutcome outcome) {
                  final index = entries.indexOf(outcome.original);
                  if (index != -1) {
                    setState(() => entries[index] = outcome.updated);
                    await _saveTodayEntries();
                  }
                } else if (result case final FoodEntry e) {
                  setState(() => entries.add(e));
                  await _saveTodayEntries();
                  _checkAchievements();
                } else if (result is DayPhotoSaved) {
                  await _loadTodayPhotos();
                }
              },
            )
          : null,
    );
  }
}

// A brief, tasteful "achievement" pop shown once when a daily target is
// first crossed—scales and fades in, holds, then fades out and removes
// itself. Deliberately dependency-free (no confetti package) to keep this
// small.
class _CelebrationBadge extends StatefulWidget {
  const _CelebrationBadge({required this.icon, required this.onDone});
  final IconData icon;
  final VoidCallback onDone;
  @override
  State<_CelebrationBadge> createState() => _CelebrationBadgeState();
}

class _CelebrationBadgeState extends State<_CelebrationBadge>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..forward();

  @override
  void initState() {
    super.initState();
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.4, end: 1.1), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 20),
    ]).animate(controller);
    final opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(controller);
    return Positioned(
      top: 90,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: opacity,
            child: ScaleTransition(
              scale: scale,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [success, gold],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .18),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: Colors.white, size: 40),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Picks a stable index into [variants] for the given day, so the coaching
// message reads differently from day to day but never changes mid-day on a
// rebuild/navigation (no real randomness, no per-frame flicker).
int _dailyVariant(DateTime day, int variantCount) =>
    (day.year * 10000 + day.month * 100 + day.day) % variantCount;

// MET-based walk suggestion (calories = MET × bodyWeightKg × hours, the same
// formula the exercise parser already uses), rounded to a natural-sounding
// 5-minute figure. Returns null rather than a fixed number whenever body
// weight isn't known or the result would fall outside a sensible, non-extreme
// range — never invents a calorie burn and never nudges toward over-exercising.
int? _suggestedWalkMinutes(int overKcal, double? bodyWeightKg, double walkMet) {
  if (bodyWeightKg == null || bodyWeightKg <= 0 || overKcal <= 0) return null;
  final minutes = (overKcal / (walkMet * bodyWeightKg) * 60).round();
  if (minutes < 10 || minutes > 75) return null;
  return (minutes / 5).round() * 5;
}

class DailyNudge {
  const DailyNudge(this.title, this.body, this.icon);
  final String title;
  final String body;
  final IconData icon;

  factory DailyNudge.forToday({
    required List<FoodEntry> entries,
    required int calories,
    required int targetCalories,
    required int protein,
    required int targetProtein,
    int exerciseCalories = 0,
    int waterMl = 0,
    int waterTargetMl = 0,
    double? bodyWeightKg,
    double walkMet = 4.8,
    String locale = 'en',
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final hour = today.hour;
    final pl = locale == 'pl';
    final hasFood = entries.any((e) => !e.isExercise);
    final hasExercise = entries.any((e) => e.isExercise);

    String pick(List<String> en, List<String> plVariants) {
      final variants = pl ? plVariants : en;
      return variants[_dailyVariant(today, variants.length)];
    }

    if (!hasFood) {
      if (hour < 11) {
        return DailyNudge(
          pl ? 'Dobra pora na śniadanie' : 'Good time for breakfast',
          pick(
            [
              'Nothing logged yet—add your first meal whenever you’re ready.',
              'A fresh day ahead—log breakfast whenever suits you.',
            ],
            [
              'Nic jeszcze nie dodano — dodaj pierwszy posiłek, kiedy będziesz gotowy(a).',
              'Nowy dzień przed Tobą — dodaj śniadanie, kiedy Ci pasuje.',
            ],
          ),
          Icons.wb_sunny_outlined,
        );
      }
      if (hour < 15) {
        return DailyNudge(
          pl ? 'Nic jeszcze nie dodano' : 'Nothing logged yet',
          pick(
            [
              'Add lunch to keep today on track.',
              'Nothing logged so far—lunch is a good place to start.',
            ],
            [
              'Dodaj obiad, aby utrzymać dzisiejszy plan.',
              'Jak dotąd nic nie dodano — obiad to dobry początek.',
            ],
          ),
          Icons.restaurant_outlined,
        );
      }
      return DailyNudge(
        pl ? 'Spokojny dzień jak dotąd' : 'Quiet day so far',
        pick(
          [
            'No meals logged today—that’s okay, add one whenever suits you.',
            'Still nothing logged—no pressure, add your first meal when ready.',
          ],
          [
            'Brak posiłków dzisiaj — to nic, dodaj jeden, kiedy Ci pasuje.',
            'Wciąż nic nie dodano — bez presji, dodaj pierwszy posiłek, kiedy będziesz gotowy(a).',
          ],
        ),
        Icons.nightlight_outlined,
      );
    }

    final netCalories = math.max(0, calories - exerciseCalories);
    final netRatio = targetCalories == 0 ? 0.0 : netCalories / targetCalories;
    final grossRatio = targetCalories == 0 ? 0.0 : calories / targetCalories;
    final proteinRatio = targetProtein == 0 ? 1.0 : protein / targetProtein;
    final proteinDone = targetProtein > 0 && protein >= targetProtein;
    final waterDone = waterTargetMl > 0 && waterMl >= waterTargetMl;
    final overKcal = netCalories - targetCalories;

    // A "strong overall day": calories comfortably in range plus another
    // target already met—surfaced ahead of the single-metric states below.
    if (netRatio >= 0.85 &&
        netRatio <= 1.05 &&
        proteinDone &&
        (waterDone || hasExercise)) {
      return DailyNudge(
        pl ? 'Świetny dzień' : 'Strong overall day',
        pick(
          [
            'Calories, protein and today’s activity are all lining up nicely.',
            'A well-rounded day so far—keep this up tomorrow.',
          ],
          [
            'Kalorie, białko i dzisiejsza aktywność świetnie się układają.',
            'Bardzo dobrze zbalansowany dzień jak dotąd — tak trzymaj jutro.',
          ],
        ),
        Icons.emoji_events,
      );
    }

    // Ate more than target but exercise brought net calories back in
    // range—celebrate the save instead of flagging the raw intake number.
    if (hasExercise &&
        exerciseCalories > 0 &&
        calories > targetCalories &&
        netRatio <= 1.05) {
      return DailyNudge(
        pl
            ? 'Powrót do celu po ćwiczeniach'
            : 'Back near target after exercise',
        pick(
          [
            'You ate above target, but exercise brought your net calories back in range.',
            'Today’s activity balanced out a bigger-than-usual intake—nice recovery.',
          ],
          [
            'Zjadłeś więcej niż cel, ale ćwiczenia przywróciły kalorie netto do normy.',
            'Dzisiejsza aktywność zrównoważyła większe niż zwykle spożycie — dobra korekta.',
          ],
        ),
        Icons.directions_run,
      );
    }

    if (netRatio >= 1.15) {
      final minutes = _suggestedWalkMinutes(overKcal, bodyWeightKg, walkMet);
      final suggestion = minutes != null
          ? pick(
              ['A brisk walk (about $minutes min) could help close some of the gap.'],
              ['Szybki marsz (ok. $minutes min) mógłby zmniejszyć różnicę.'],
            )
          : pick(
              [
                'Keep your next meal lighter and you’re still in control.',
                'No need to react—just ease off a little at your next meal.',
              ],
              [
                'Zrób następny posiłek lżejszym — wciąż masz kontrolę.',
                'Nie musisz nic nadrabiać — po prostu zjedz nieco mniej przy następnym posiłku.',
              ],
            );
      return DailyNudge(
        pl ? 'Znacznie powyżej celu' : 'Substantially over target',
        pl
            ? 'Jesteś dziś $overKcal kcal powyżej celu. $suggestion'
            : 'You’re $overKcal kcal over today. $suggestion',
        Icons.info_outline,
      );
    }
    if (netRatio > 1.0) {
      final suggestion = pick(
        [
          'Keep your next meal lighter and you’re still in control.',
          'A short walk or a lighter next meal can even this out.',
        ],
        [
          'Zrób następny posiłek lżejszym — wciąż masz kontrolę.',
          'Krótki spacer lub lżejszy posiłek wyrówna dzisiejszy bilans.',
        ],
      );
      return DailyNudge(
        pl ? 'Nieco powyżej celu' : 'Slightly over target',
        pl
            ? 'Jesteś dziś $overKcal kcal powyżej celu. $suggestion'
            : 'You’re $overKcal kcal over today. $suggestion',
        Icons.info_outline,
      );
    }

    if (proteinDone && netRatio < 1.0) {
      return DailyNudge(
        pl ? 'Cel białkowy osiągnięty' : 'Protein target reached',
        pick(
          [
            'Nice work—today’s protein target is done.',
            'Protein goal reached for today. Keep it up.',
          ],
          [
            'Świetnie — dzisiejszy cel białkowy jest zrealizowany.',
            'Cel białkowy na dziś osiągnięty. Tak trzymaj.',
          ],
        ),
        Icons.check_circle,
      );
    }
    if (waterDone) {
      return DailyNudge(
        pl ? 'Cel nawodnienia osiągnięty' : 'Water target reached',
        pick(
          [
            'You’ve hit today’s water target already.',
            'Hydration goal reached for today—nice consistency.',
          ],
          [
            'Osiągnąłeś już dzisiejszy cel nawodnienia.',
            'Cel nawodnienia na dziś zrealizowany — świetna regularność.',
          ],
        ),
        Icons.water_drop,
      );
    }

    if (netRatio >= 0.85) {
      return DailyNudge(
        pl ? 'Dobrze na kursie' : 'Comfortably on track',
        pick(
          [
            'You’re within reach of today’s calorie goal. Nice work.',
            'Right where you want to be today—keep going.',
          ],
          [
            'Jesteś blisko dzisiejszego celu kalorycznego. Świetna robota.',
            'Jesteś dokładnie tam, gdzie chcesz być — tak dalej.',
          ],
        ),
        Icons.check_circle_outline,
      );
    }
    if (netRatio >= 0.6) {
      return DailyNudge(
        pl ? 'Blisko celu' : 'Getting close to target',
        pick(
          [
            'Getting closer to today’s calorie goal—keep logging as you go.',
            'You’re making steady progress toward today’s target.',
          ],
          [
            'Coraz bliżej dzisiejszego celu kalorycznego — dodawaj posiłki dalej.',
            'Robisz stały postęp w kierunku dzisiejszego celu.',
          ],
        ),
        Icons.trending_up,
      );
    }
    if (hour >= 18 && netRatio < 0.5) {
      return DailyNudge(
        pl ? 'Lekki dzień jak dotąd' : 'Light day so far',
        pick(
          [
            'You’re well under target this evening—make sure you’re eating enough.',
            'Quite light today so far—don’t skip a proper meal tonight.',
          ],
          [
            'Jesteś dziś wyraźnie poniżej celu — upewnij się, że jesz wystarczająco dużo.',
            'Dziś dość lekko jak dotąd — nie pomijaj dziś porządnego posiłku.',
          ],
        ),
        Icons.eco_outlined,
      );
    }
    if (hasExercise) {
      // The headline alone already says it -- today's timeline right below
      // makes "food and exercise both logged" obvious, so no body text is
      // worth the space here.
      return DailyNudge(
        pl ? 'Dobry balans dzisiaj' : 'Nice balance today',
        '',
        Icons.directions_run,
      );
    }
    if (proteinRatio < 0.5 && grossRatio > 0.3) {
      return DailyNudge(
        pl ? 'Białko mogłoby być wyższe' : 'Protein could use a boost',
        pick(
          [
            'Add a protein-rich snack to help hit your target.',
            'A bit more protein today would help you reach your goal.',
          ],
          [
            'Dodaj przekąskę bogatą w białko, aby osiągnąć cel.',
            'Odrobina więcej białka pomoże Ci dziś osiągnąć cel.',
          ],
        ),
        Icons.fitness_center,
      );
    }
    return DailyNudge(
      pl ? 'Jesteś na dobrej drodze' : 'You’re on track',
      pick(
        [
          'Keep logging meals to stay on top of today’s goals.',
          'Steady so far—keep logging to stay on top of today.',
        ],
        [
          'Kontynuuj dodawanie posiłków, aby realizować dzisiejsze cele.',
          'Stabilnie jak dotąd — dalej dodawaj posiłki, by kontrolować dzisiejszy dzień.',
        ],
      ),
      Icons.trending_up,
    );
  }
}

class NutritionTargets {
  const NutritionTargets({
    required this.calories,
    required this.protein,
    required this.carbs,
  });
  final int calories, protein, carbs;

  factory NutritionTargets.forPlan({
    required int calories,
    required String style,
    double? weightKg,
  }) {
    final proteinRatio = style == 'High protein' ? .30 : .25;
    final proteinFromCalories = (calories * proteinRatio / 4).round();
    final protein = weightKg == null
        ? proteinFromCalories
        : math.max(proteinFromCalories, (weightKg * 1.2).round());
    final carbRatio = switch (style) {
      'Keto' => 30 / calories * 4,
      'Lower carbohydrate' => .25,
      'High protein' => .35,
      'Mediterranean' => .45,
      _ => .50,
    };
    final carbs = style == 'Keto' ? 30 : (calories * carbRatio / 4).round();
    return NutritionTargets(calories: calories, protein: protein, carbs: carbs);
  }
}

class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.accountName,
    required this.entries,
    this.photos = const [],
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.exerciseCalories,
    required this.targets,
    required this.onDelete,
    required this.onEditEntry,
    required this.waterMl,
    required this.waterTargetMl,
    required this.onAddWater,
    this.bodyWeightKg,
    this.locale = 'en',
    this.entrySyncAvailable = false,
    this.onSyncEntry,
    this.walkMet = 4.8,
    this.onRefresh,
  });
  // Manual fallback for anything shared into this account -- normal sync
  // is the periodic/tab-switch/resume checks in _AppShellState, not this.
  final Future<void> Function()? onRefresh;
  final String accountName;
  final List<FoodEntry> entries;
  final List<DayPhoto> photos;
  final int calories, protein, carbs, exerciseCalories;
  final NutritionTargets targets;
  final ValueChanged<FoodEntry> onDelete;
  final void Function(FoodEntry oldEntry, FoodEntry newEntry) onEditEntry;
  final int waterMl, waterTargetMl;
  final ValueChanged<int> onAddWater;
  final double? bodyWeightKg;
  final String locale;
  final bool entrySyncAvailable;
  final Future<void> Function(FoodEntry entry)? onSyncEntry;
  // MET for a brisk walk, sourced from the shared activity catalogue at app
  // startup (see _AppShellState._loadWalkMet) — 4.8 is that same catalogue
  // value, kept here only as the default before the async load completes.
  final double walkMet;

  List<Widget> _timeline(BuildContext context) {
    final grouped = <String, List<FoodEntry>>{};
    for (final entry in entries) {
      (grouped[entry.dayCategory] ??= []).add(entry);
    }
    for (final list in grouped.values) {
      list.sort(
        (a, b) => _entryMinutesOfDay(a).compareTo(_entryMinutesOfDay(b)),
      );
    }
    return [
      for (final category in MealCategory.order)
        if (grouped[category]?.isNotEmpty ?? false) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 7),
            child: LText(
              category,
              style: const TextStyle(
                color: forest,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
              ),
            ),
          ),
          ...grouped[category]!.map(
            (entry) => FoodTile(
              entry,
              onDelete: () => _confirmDelete(context, entry),
              onEdit: () => _editEntry(context, entry),
              onSync: entrySyncAvailable ? () => onSyncEntry!(entry) : null,
            ),
          ),
        ],
    ];
  }

  Future<void> _editEntry(BuildContext context, FoodEntry entry) async {
    final result = await showModalBottomSheet<EditEntryResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditEntrySheet(
        entry: entry,
        bodyWeightKg: bodyWeightKg,
        locale: locale,
      ),
    );
    if (!context.mounted || result == null) return;
    // Water is the one field not derivable by simply replacing the entry
    // (the day's food/exercise totals are computed live from `entries`,
    // but the water total is its own separately-persisted running
    // counter) -- reconcile it by the amount this edit actually changed,
    // never by re-adding the new total on top of the old one.
    if (result.waterDeltaMl != 0) onAddWater(result.waterDeltaMl);
    if (result.delete) {
      onDelete(entry);
    } else if (result.entry != null) {
      onEditEntry(entry, result.entry!);
    }
  }

  Future<void> _confirmDelete(BuildContext context, FoodEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LText('Delete entry?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LText(
              'This will remove it from today’s totals and timeline.',
            ),
            const SizedBox(height: 10),
            Text(
              entry.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LText('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: coral),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const LText('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) onDelete(entry);
  }

  @override
  Widget build(BuildContext context) {
    final nudge = DailyNudge.forToday(
      entries: entries,
      calories: calories,
      targetCalories: targets.calories,
      protein: protein,
      targetProtein: targets.protein,
      exerciseCalories: exerciseCalories,
      waterMl: waterMl,
      waterTargetMl: waterTargetMl,
      bodyWeightKg: bodyWeightKg,
      walkMet: walkMet,
      locale: locale,
    );
    final proteinComplete = targets.protein > 0 && protein >= targets.protein;
    final scrollView = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
          sliver: SliverList.list(
            children: [
              TopBar(
                '${greetingFor(DateTime.now())}${accountName.isEmpty ? '' : ', $accountName'}',
                fullDate(DateTime.now()),
              ),
              const SizedBox(height: 22),
              if (entries.isEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: mint,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add_a_photo_outlined,
                            color: forest,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const LText(
                          'Nothing logged today',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 7),
                        const LText(
                          'Your imported history is under Journey. Start today when you have your next meal.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const SectionHeader('Today’s timeline', '0 ITEMS'),
                if (photos.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _StandalonePhotoStrip(photos: photos),
                ],
              ] else ...[
                HeroCard(
                  foodCalories: calories,
                  exerciseCalories: exerciseCalories,
                  target: targets.calories,
                  headline: nudge.title,
                  subtitle: nudge.body,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        'Protein',
                        '$protein',
                        'g',
                        '',
                        protein / targets.protein,
                        coral,
                        complete: proteinComplete,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        'Carbs',
                        '$carbs',
                        'g',
                        '',
                        carbs / targets.carbs,
                        gold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: WaterCard(
                        waterMl: waterMl,
                        waterTargetMl: waterTargetMl,
                      ),
                    ),
                  ],
                ),
                // The standalone nudge card is folded into HeroCard's headline
                // instead (see `nudge` above) — disabled here for now rather
                // than removed, in case it comes back as a separate section.
                if (showNudgeCard) ...[
                  const SizedBox(height: 22),
                  const SectionHeader('A little nudge', 'WHY?'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: mint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.white,
                          foregroundColor: forest,
                          child: Icon(nudge.icon),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LText(
                                nudge.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              LText(
                                nudge.body,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SectionHeader('Today’s timeline', '${entries.length} ITEMS'),
                const SizedBox(height: 8),
                if (photos.isNotEmpty) ...[
                  _StandalonePhotoStrip(photos: photos),
                  const SizedBox(height: 8),
                ],
                ..._timeline(context),
              ],
            ],
          ),
        ),
      ],
    );
    return onRefresh == null
        ? scrollView
        : RefreshIndicator(onRefresh: onRefresh!, child: scrollView);
  }
}

// Parses the leading "HH:MM" off an entry's display time (exercise
// entries append " · 30 min"/" · 2 hr" after it) so the timeline can sort
// by when something actually happened, not the order it was typed in.
int _entryMinutesOfDay(FoodEntry entry) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(entry.time);
  if (match == null) return 0;
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

class EditEntryResult {
  const EditEntryResult({
    this.entry,
    this.delete = false,
    this.waterDeltaMl = 0,
  });
  final FoodEntry? entry;
  final bool delete;
  final int waterDeltaMl;
}

class TopBar extends StatelessWidget {
  const TopBar(this.title, this.subtitle, {super.key});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText(
              subtitle.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: forest,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            LText(
              title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -.7,
              ),
            ),
          ],
        ),
      ),
      ClipOval(
        child: Image.asset(
          'assets/branding/app_icon.png',
          width: 44,
          height: 44,
          fit: BoxFit.cover,
        ),
      ),
    ],
  );
}

class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.foodCalories,
    required this.exerciseCalories,
    required this.target,
    required this.headline,
    this.subtitle,
  });
  final int foodCalories, exerciseCalories, target;
  final String headline;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final netCalories = math.max(0, foodCalories - exerciseCalories);
    final over = netCalories > target;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF173B2E), ink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: (foodCalories / target).clamp(0, 1),
                    strokeWidth: 12,
                    color: const Color(0xFF7AE0AC),
                    backgroundColor: Colors.white12,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                if (exerciseCalories > 0)
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (netCalories / target).clamp(0, 1),
                        strokeWidth: 6,
                        color: gold,
                        backgroundColor: Colors.white10,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                  ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LText(
                      '$foodCalories',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const LText(
                      'KCAL EATEN',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText(
                  headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  LText(
                    subtitle!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                LText(
                  over
                      ? '${netCalories - target} kcal over today'
                      : '${target - netCalories} kcal left for today',
                  style: TextStyle(
                    color: over ? const Color(0xFFFFB3A0) : Colors.white70,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                if (exerciseCalories > 0) ...[
                  LText(
                    '$netCalories net kcal after exercise',
                    style: const TextStyle(
                      color: Color(0xFFF3C66E),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Icon(
                      Icons.local_fire_department_outlined,
                      color: Color(0xFF7AE0AC),
                      size: 18,
                    ),
                    SizedBox(width: 6),
                    LText(
                      '$target daily target',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WaterCard extends StatelessWidget {
  const WaterCard({
    super.key,
    required this.waterMl,
    required this.waterTargetMl,
  });
  final int waterMl, waterTargetMl;

  @override
  Widget build(BuildContext context) {
    final progress = (waterTargetMl == 0 ? 0.0 : waterMl / waterTargetMl).clamp(
      0.0,
      1.0,
    );
    final complete = waterTargetMl > 0 && waterMl >= waterTargetMl;
    return MetricCard(
      'Water',
      '$waterMl',
      'ml',
      '',
      progress,
      aqua,
      trailing: WaterGlass(progress: progress, width: 14, height: 20),
      complete: complete,
    );
  }
}

class WaterGlass extends StatelessWidget {
  const WaterGlass({
    super.key,
    required this.progress,
    this.width = 22,
    this.height = 30,
  });
  final double progress;
  final double width, height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: ClipPath(
      clipper: _GlassClipper(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: aqua.withValues(alpha: .14)),
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: progress,
              child: Container(color: aqua),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: aqua, width: 1.4),
            ),
          ),
        ],
      ),
    ),
  );
}

class _GlassClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final inset = size.width * 0.14;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - inset, size.height)
      ..lineTo(inset, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class MetricCard extends StatelessWidget {
  const MetricCard(
    this.label,
    this.value,
    this.unit,
    this.detail,
    this.progress,
    this.color, {
    super.key,
    this.trailing,
    this.onTap,
    this.complete = false,
  });
  final String label, value, unit, detail;
  final double progress;
  final Color color;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool complete;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (complete) ...[
                  const Icon(Icons.check_circle, color: success, size: 14),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: LText(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: LText(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (unit.isNotEmpty) ...[
                        const SizedBox(width: 2),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: LText(
                            unit,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.black45,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (complete || detail.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: LText(
                        complete ? 'Complete' : detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: complete ? FontWeight.w700 : null,
                          color: complete ? success : Colors.black45,
                        ),
                      ),
                    ),
                  ),
                ],
                if (trailing != null) ...[const SizedBox(width: 6), trailing!],
              ],
            ),
            const SizedBox(height: 13),
            LinearProgressIndicator(
              value: progress.clamp(0, 1),
              color: complete ? success : color,
              backgroundColor: (complete ? success : color).withValues(
                alpha: .16,
              ),
              borderRadius: BorderRadius.circular(8),
              minHeight: 7,
            ),
          ],
        ),
      ),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, this.action, {super.key});
  final String title, action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: LText(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
      ),
      LText(
        action,
        style: const TextStyle(
          color: forest,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: .8,
        ),
      ),
    ],
  );
}

class DevBadge extends StatelessWidget {
  const DevBadge({super.key, this.padding = const EdgeInsets.only(top: 24)});
  final EdgeInsetsGeometry padding;

  Future<void> _open() => launchUrl(Uri.parse('https://ashleyrichards.tech'));

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Center(
      child: Semantics(
        button: true,
        label: ui(
          context,
          'App built by Ashley Richards — visit ashleyrichards.tech',
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _open,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Image.asset('assets/branding/dev_logo.png', height: 26),
          ),
        ),
      ),
    ),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class FoodEntry {
  const FoodEntry(
    this.name,
    this.time,
    this.calories,
    this.protein,
    this.icon, {
    this.isExercise = false,
    this.category,
    this.carbs = 0,
    this.sharedFrom,
    this.sharedEntryId,
    this.exerciseActivityId,
    this.exerciseDurationMinutes,
    this.exerciseMet,
    this.exerciseBodyWeightKg,
    this.exerciseApproximate = false,
    this.waterMl = 0,
    this.photoPaths = const [],
    this.photoMediaIds = const [],
    this.weightGrams,
    this.fat,
    this.saturatedFat,
    this.sugar,
    this.fibre,
    this.salt,
  });
  final String name, time;
  final int calories, protein;
  final IconData icon;
  final bool isExercise;
  final String? category;
  final int carbs;
  final String? sharedFrom, sharedEntryId;
  // Optional label/dataset detail beyond the headline macros -- weight and
  // fat/fibre are filled in automatically when the local dataset or a
  // scanned label actually has them; sugar/salt/saturated fat only ever
  // come from a scanned label or direct manual entry, since the local
  // dataset has no columns for those three and nothing here is ever
  // guessed to fill them in.
  final double? weightGrams;
  final double? fat, saturatedFat, sugar, fibre, salt;
  // Local filesystem paths under the app's own documents directory (see
  // PhotoStore) -- never image bytes embedded in the entry itself, and
  // NEVER meaningful on any device other than the one that wrote them (a
  // path from another device must never be dereferenced -- see FoodTile).
  final List<String> photoPaths;
  // Backend media ids (see MediaService/`/api/v1/media`) for photos that
  // have crossed -- or are about to cross -- a device boundary (an
  // entry synced to a linked account). The wire representation of a
  // shared entry carries only these small ids, never photoPaths or image
  // bytes; each receiving device downloads and caches the bytes once.
  final List<String> photoMediaIds;
  int get photoCount => math.max(photoPaths.length, photoMediaIds.length);
  String? photoPathAt(int index) =>
      index < photoPaths.length ? photoPaths[index] : null;
  String? photoMediaIdAt(int index) =>
      index < photoMediaIds.length ? photoMediaIds[index] : null;
  // Water contribution recognized as part of a wider food/drink entry
  // (e.g. "glass water" inside a longer meal sentence) -- consumed once,
  // immediately, to top up the day's water total; not persisted on the
  // entry itself since that total already lives durably in
  // WaterRepository, and the entry's own text still shows what was said.
  final int waterMl;
  // Calculation evidence for a parser-estimated exercise entry (MET x body
  // weight x duration) -- null when the entry predates this, was AI-derived,
  // or isn't exercise at all. Kept separate from `calories` so the number
  // used for daily totals never depends on this being present.
  final String? exerciseActivityId;
  final double? exerciseDurationMinutes;
  final double? exerciseMet;
  final double? exerciseBodyWeightKg;
  final bool exerciseApproximate;

  String get dayCategory => category ?? MealCategory.detect(name, isExercise);
  // `icon` is fixed at construction (exercise vs. food) and stays that way
  // for other callers; the timeline itself should show a drink glass for
  // anything detected as Drinks rather than a knife and fork.
  IconData get displayIcon =>
      isExercise ? icon : (dayCategory == 'Drinks' ? Icons.local_drink : icon);

  // Value equality, not identity -- `entries.indexOf(oldEntry)` (edit/delete)
  // has to keep matching after `_loadTodayEntries` swaps the whole `entries`
  // list for freshly-deserialized objects (the 20s background sync timer can
  // fire while an edit sheet is open), or the edit/delete silently no-ops
  // because the object instance captured when the sheet opened no longer
  // exists in the reloaded list.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FoodEntry &&
          name == other.name &&
          time == other.time &&
          calories == other.calories &&
          protein == other.protein &&
          isExercise == other.isExercise &&
          category == other.category &&
          carbs == other.carbs &&
          sharedFrom == other.sharedFrom &&
          sharedEntryId == other.sharedEntryId &&
          exerciseActivityId == other.exerciseActivityId &&
          exerciseDurationMinutes == other.exerciseDurationMinutes &&
          exerciseMet == other.exerciseMet &&
          exerciseBodyWeightKg == other.exerciseBodyWeightKg &&
          exerciseApproximate == other.exerciseApproximate &&
          waterMl == other.waterMl &&
          weightGrams == other.weightGrams &&
          fat == other.fat &&
          saturatedFat == other.saturatedFat &&
          sugar == other.sugar &&
          fibre == other.fibre &&
          salt == other.salt &&
          _listEquals(photoPaths, other.photoPaths) &&
          _listEquals(photoMediaIds, other.photoMediaIds));

  @override
  int get hashCode => Object.hash(
    name,
    time,
    calories,
    protein,
    isExercise,
    category,
    carbs,
    exerciseActivityId,
    exerciseDurationMinutes,
    weightGrams,
  );

  Map<String, Object> toJson() => {
    'name': name,
    'time': time,
    'calories': calories,
    'protein': protein,
    'isExercise': isExercise,
    'category': dayCategory,
    'carbs': carbs,
    'sharedFrom': ?sharedFrom,
    'sharedEntryId': ?sharedEntryId,
    'exerciseActivityId': ?exerciseActivityId,
    'exerciseDurationMinutes': ?exerciseDurationMinutes,
    'exerciseMet': ?exerciseMet,
    'exerciseBodyWeightKg': ?exerciseBodyWeightKg,
    'exerciseApproximate': exerciseApproximate,
    'photoPaths': ?(photoPaths.isEmpty ? null : photoPaths),
    'photoMediaIds': ?(photoMediaIds.isEmpty ? null : photoMediaIds),
    'weightGrams': ?weightGrams,
    'fat': ?fat,
    'saturatedFat': ?saturatedFat,
    'sugar': ?sugar,
    'fibre': ?fibre,
    'salt': ?salt,
  };

  // Deliberately tolerant of a malformed/old-schema/partially-synced entry:
  // a missing optional field gets a safe default rather than throwing, so
  // one odd entry degrades (e.g. blank name) instead of taking the whole
  // day's timeline down with it. Only a fundamentally undecodable row
  // (e.g. `json` itself not even a map) still throws, and the caller
  // (DailyEntryRepository.load) already quarantines that one row.
  factory FoodEntry.fromJson(Map<String, dynamic> json) {
    final isExercise = json['isExercise'] as bool? ?? false;
    final name = json['name'] as String? ?? 'Untitled entry';
    return FoodEntry(
      name,
      json['time'] as String? ?? '',
      (json['calories'] as num?)?.round() ?? 0,
      (json['protein'] as num?)?.round() ?? 0,
      isExercise ? Icons.directions_run : Icons.restaurant,
      isExercise: isExercise,
      category: json['category'] as String?,
      sharedFrom: json['sharedFrom'] as String?,
      sharedEntryId: json['sharedEntryId'] as String?,
      carbs:
          (json['carbs'] as num?)?.round() ??
          (isExercise ? 0 : FoodEstimator.estimate(name).carbs),
      exerciseActivityId: json['exerciseActivityId'] as String?,
      exerciseDurationMinutes: (json['exerciseDurationMinutes'] as num?)
          ?.toDouble(),
      exerciseMet: (json['exerciseMet'] as num?)?.toDouble(),
      exerciseBodyWeightKg: (json['exerciseBodyWeightKg'] as num?)?.toDouble(),
      exerciseApproximate: json['exerciseApproximate'] as bool? ?? false,
      // photoPaths from another device is never usable here (see FoodTile) --
      // kept only so THIS device's own writes still round-trip; a foreign
      // path just fails the existsSync() check at render time.
      photoPaths:
          (json['photoPaths'] as List?)?.whereType<String>().toList() ??
          const [],
      photoMediaIds:
          (json['photoMediaIds'] as List?)?.whereType<String>().toList() ??
          const [],
      weightGrams: (json['weightGrams'] as num?)?.toDouble(),
      fat: (json['fat'] as num?)?.toDouble(),
      saturatedFat: (json['saturatedFat'] as num?)?.toDouble(),
      sugar: (json['sugar'] as num?)?.toDouble(),
      fibre: (json['fibre'] as num?)?.toDouble(),
      salt: (json['salt'] as num?)?.toDouble(),
    );
  }

  FoodEntry copyWithPhoto(String photoPath) => FoodEntry(
    name,
    time,
    calories,
    protein,
    icon,
    isExercise: isExercise,
    category: category,
    carbs: carbs,
    sharedFrom: sharedFrom,
    sharedEntryId: sharedEntryId,
    exerciseActivityId: exerciseActivityId,
    exerciseDurationMinutes: exerciseDurationMinutes,
    exerciseMet: exerciseMet,
    exerciseBodyWeightKg: exerciseBodyWeightKg,
    exerciseApproximate: exerciseApproximate,
    photoPaths: [...photoPaths, photoPath],
    photoMediaIds: photoMediaIds,
    weightGrams: weightGrams,
    fat: fat,
    saturatedFat: saturatedFat,
    sugar: sugar,
    fibre: fibre,
    salt: salt,
  );

  // The wire form of an entry that's about to cross a device boundary
  // (see EntrySyncService.shareEntry) -- local photoPaths are dropped
  // (meaningless on another device) once each has been uploaded to backend
  // media storage and replaced with its media id.
  FoodEntry forSharing({required List<String> mediaIds}) => FoodEntry(
    name,
    time,
    calories,
    protein,
    icon,
    isExercise: isExercise,
    category: category,
    carbs: carbs,
    sharedFrom: sharedFrom,
    sharedEntryId: sharedEntryId,
    exerciseActivityId: exerciseActivityId,
    exerciseDurationMinutes: exerciseDurationMinutes,
    exerciseMet: exerciseMet,
    exerciseBodyWeightKg: exerciseBodyWeightKg,
    exerciseApproximate: exerciseApproximate,
    photoMediaIds: mediaIds,
    weightGrams: weightGrams,
    fat: fat,
    saturatedFat: saturatedFat,
    sugar: sugar,
    fibre: fibre,
    salt: salt,
  );
}

class MealCategory {
  static const order = [
    'Breakfast',
    'Brunch',
    'Lunch',
    'Snack',
    'Dinner',
    'Supper',
    'Meal',
    'Drinks',
    'Other',
    'Exercise',
  ];

  // True meal-NAME words only (unlike the broader heuristic word lists in
  // `detect` below, which also lean on incidental food-type hints like
  // "porridge" or "crisps") -- these are the words `extractExplicitCategory`
  // treats as an explicit, authoritative category choice that overrides
  // whatever the food composition looks like, and strips out of the text
  // before it ever reaches the food parser (a category word is not a food
  // fragment). Locale-aware: includes the diacritic and no-diacritic forms
  // for languages that need it (e.g. Polish "przekąska"/"przekaska"),
  // reusing the same fold-based tolerance the parser itself uses.
  static const explicitMealWords = <String, List<String>>{
    'Breakfast': [
      'breakfast',
      'śniadanie',
      'sniadanie',
      'frühstück',
      'petit-déjeuner',
      'desayuno',
      'colazione',
    ],
    'Brunch': [
      'brunch',
      'drugie śniadanie',
      'drugie sniadanie',
      'zweites frühstück',
    ],
    'Lunch': [
      'lunch',
      'obiad',
      'mittagessen',
      'déjeuner',
      'almuerzo',
      'pranzo',
    ],
    'Snack': [
      'snack',
      'przekąska',
      'przekaska',
      'imbiss',
      'goûter',
      'tentempié',
      'spuntino',
    ],
    'Dinner': ['dinner', 'kolacja', 'abendessen', 'dîner', 'cena'],
    'Supper': ['supper', 'wieczerza', 'abendbrot', 'souper'],
  };

  /// If [description] names an explicit meal (breakfast/lunch/dinner/...,
  /// in any supported language, with or without diacritics), returns that
  /// category plus the description with the meal word -- and a leading
  /// "for "/trailing ":" it was joined to -- removed, so it never reaches
  /// the food parser as an unresolved fragment. Returns null when no
  /// explicit meal word is present, leaving [description] untouched.
  static (String category, String cleaned)? extractExplicitCategory(
    String description,
  ) {
    final folded = foldDiacritics(description.toLowerCase());
    for (final entry in explicitMealWords.entries) {
      for (final word in entry.value) {
        final foldedWord = foldDiacritics(word);
        final boundary = RegExp(
          '(?<![a-z])${RegExp.escape(foldedWord)}(?![a-z])',
        );
        if (!boundary.hasMatch(folded)) continue;
        var cleaned = folded.replaceFirst(
          RegExp('for\\s+${RegExp.escape(foldedWord)}(?![a-z])'),
          '',
        );
        cleaned = cleaned.replaceFirst(boundary, '');
        // Whatever separator the category word was hanging off of ("avocado
        // - snack", "avocado (snack)", "snack: avocado") must go with it --
        // left dangling (e.g. "avocado -"), it reads as one unresolvable
        // food fragment to the parser instead of the plain food name.
        cleaned = cleaned.replaceAll(RegExp(r'\(\s*\)'), '');
        cleaned = cleaned.replaceFirst(RegExp(r'^[\s,;:\-()]+'), '');
        cleaned = cleaned.replaceFirst(RegExp(r'[\s,;:\-()]+$'), '');
        cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
        return (entry.key, cleaned);
      }
    }
    return null;
  }

  static String detect(String description, bool isExercise) {
    if (isExercise) return 'Exercise';
    final text = description.toLowerCase();
    const terms = <String, List<String>>{
      'Breakfast': [
        'breakfast',
        'śniadanie',
        'frühstück',
        'petit-déjeuner',
        'desayuno',
        'colazione',
        'porridge',
        'oats',
      ],
      'Brunch': ['brunch', 'drugie śniadanie', 'zweites frühstück'],
      'Lunch': [
        'lunch',
        'obiad',
        'mittagessen',
        'déjeuner',
        'almuerzo',
        'pranzo',
      ],
      'Snack': [
        'snack',
        'przekąska',
        'imbiss',
        'goûter',
        'tentempié',
        'spuntino',
        'crisps',
        'chocolate',
      ],
      'Dinner': ['dinner', 'kolacja', 'abendessen', 'dîner', 'cena'],
      'Supper': ['supper', 'wieczerza', 'abendbrot', 'souper'],
      'Drinks': [
        'drink',
        'napój',
        'getränk',
        'boisson',
        'bebida',
        'bevanda',
        'whisky',
        'whiskey',
        'beer',
        'wine',
        'vodka',
        'gin',
        'rum',
        'coffee',
        'tea',
        'juice',
        'cola',
        'lemonade',
        'smoothie',
      ],
    };
    for (final entry in terms.entries) {
      if (entry.value.any(text.contains)) return entry.key;
    }
    return 'Meal';
  }
}

class ExtractedTime {
  const ExtractedTime(this.hour, this.minute);
  final int hour;
  final int minute;
}

// Optional "10am"/"13:30"/"o 14" (Polish "at 14") anywhere in a free-text
// description -- a time word is a category choice like a meal word, not
// food content, so it's found and removed the same way
// `MealCategory.extractExplicitCategory` handles meal words. Digits and
// am/pm/at/o are plain ASCII, so matching against the lowercased text and
// slicing the *original* string at the same offsets is safe here (no
// diacritics involved).
final _hhmmTime = RegExp(
  r'(?<![\d:])([01]?\d|2[0-3]):([0-5]\d)\s*(am|pm)?(?![\d:])',
);
final _hourAmPm = RegExp(r'(?<![\d.:])\b([01]?\d)\s*(am|pm)\b');
final _atHour = RegExp(
  r'(?<![a-z\d])(?:at|o)\s+([01]?\d|2[0-3])(?::([0-5]\d))?(?!\s*(?:am|pm))\b',
);

(ExtractedTime, String)? extractExplicitTime(String description) {
  final lower = description.toLowerCase();
  for (final pattern in [_hhmmTime, _hourAmPm, _atHour]) {
    final match = pattern.firstMatch(lower);
    if (match == null) continue;
    int hour;
    int minute = 0;
    String? ampm;
    if (pattern == _hhmmTime) {
      hour = int.parse(match.group(1)!);
      minute = int.parse(match.group(2)!);
      ampm = match.group(3);
    } else if (pattern == _hourAmPm) {
      hour = int.parse(match.group(1)!);
      ampm = match.group(2);
    } else {
      hour = int.parse(match.group(1)!);
      minute = match.group(2) != null ? int.parse(match.group(2)!) : 0;
    }
    if (ampm == 'pm' && hour < 12) hour += 12;
    if (ampm == 'am' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) continue;
    final cleaned =
        '${description.substring(0, match.start)} ${description.substring(match.end)}'
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    return (ExtractedTime(hour, minute), cleaned);
  }
  return null;
}

/// Runs both the meal-category and explicit-time extraction (in either
/// order they don't interfere -- each only removes its own matched
/// span) and returns the text left over for actual food/exercise
/// parsing, with stray leading/trailing punctuation from the removals
/// cleaned up.
(String? category, ExtractedTime? time, String cleaned) extractMealContext(
  String text,
) {
  final categoryResult = MealCategory.extractExplicitCategory(text);
  var working = categoryResult?.$2 ?? text;
  final timeResult = extractExplicitTime(working);
  if (timeResult != null) working = timeResult.$2;
  working = working
      .replaceFirst(RegExp(r'^[\s,:.;]+'), '')
      .replaceFirst(RegExp(r'[\s,:.;]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return (categoryResult?.$1, timeResult?.$1, working);
}

class DailyEntryRepository {
  const DailyEntryRepository();

  String keyFor(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return 'daily_entries_${date.year}-$month-$day';
  }

  Future<void> save(DateTime date, List<FoodEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      keyFor(date),
      entries.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  Future<List<FoodEntry>> load(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final restored = <FoodEntry>[];
    for (final raw in prefs.getStringList(keyFor(date)) ?? const []) {
      try {
        restored.add(
          FoodEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // A damaged entry must not prevent other local records from loading.
      }
    }
    return restored;
  }
}

int recommendedWaterMl(double? weightKg) =>
    weightKg == null ? 2000 : (weightKg * 35).round();

class WaterRepository {
  const WaterRepository();

  String keyFor(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return 'daily_water_${date.year}-$month-$day';
  }

  Future<void> save(DateTime date, int ml) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyFor(date), ml);
  }

  Future<int> load(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyFor(date)) ?? 0;
  }
}

// A standalone photo is MEDIA, not a FoodEntry -- it never has calories,
// macros, a meal category or a food icon, so it gets its own small,
// separate day-keyed store rather than being shoehorned into the entries
// list as a fake zero-kcal item.
class DayPhoto {
  const DayPhoto({required this.path, this.caption, required this.time});
  final String path;
  final String? caption;
  final String time;

  Map<String, Object?> toJson() => {
    'path': path,
    'caption': caption,
    'time': time,
  };

  factory DayPhoto.fromJson(Map<String, dynamic> json) => DayPhoto(
    path: json['path'] as String,
    caption: json['caption'] as String?,
    time: json['time'] as String? ?? '',
  );
}

class DayPhotoRepository {
  const DayPhotoRepository();

  String keyFor(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return 'daily_photos_${date.year}-$month-$day';
  }

  Future<List<DayPhoto>> load(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(keyFor(date)) ?? const [];
    return raw
        .map((s) => DayPhoto.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> add(DateTime date, DayPhoto photo) async {
    final prefs = await SharedPreferences.getInstance();
    final key = keyFor(date);
    final existing = prefs.getStringList(key) ?? const [];
    await prefs.setStringList(key, [...existing, jsonEncode(photo.toJson())]);
  }
}

class WaterIntake {
  const WaterIntake(this.millilitres);
  final int millilitres;
}

class WaterIntakeParser {
  static WaterIntake? parse(String description) {
    final text = description
        .toLowerCase()
        .replaceAll(',', '.')
        .replaceAll(RegExp("[’']"), ' ')
        .replaceAll('pół', 'pol')
        .replaceAll('poł', 'pol')
        .replaceAll('moitié', 'moitie');
    if (!RegExp(r'\b(water|wod(?:a|y|ę)|wasser|eau|agua|acqua)\b')
        .hasMatch(text)) {
      return null;
    }
    final remainder = text
        .replaceAll(
          RegExp(r'\b(water|wod(?:a|y|ę)|wasser|eau|agua|acqua)\b'),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b\d+(?:\.\d+)?\s*(?:ml|millilit(?:er|re)s?|l|lit(?:er|re)s?)\b',
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(?:a|an|one|two|three|four|five|six|half|full|of|d|de|du|le|la|un|une|demi|moitie|der|das|ein|eine|halb\w*|di|del|della|una|medio|media|mezzo|mezza|pol\w*|glass(?:es)?|bottle(?:s)?|sparkling|still|szklank\w*|butelk\w*|glas(?:es|s)?|flasche\w*|verre\w*|bouteille\w*|vaso\w*|botella\w*|bicchier\w*|bottiglia\w*)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[^a-zà-ż]+'), ' ')
        .trim();
    if (remainder.isNotEmpty) return null;
    final measured = RegExp(
      r'(\d+(?:\.\d+)?)\s*(ml|millilit(?:er|re)s?|l|lit(?:er|re)s?)\b',
    ).firstMatch(text);
    if (measured != null) {
      final amount = double.parse(measured.group(1)!);
      final unit = measured.group(2)!;
      return WaterIntake(
        (unit == 'l' || unit.startsWith('lit') ? amount * 1000 : amount)
            .round(),
      );
    }
    final numericCount = double.tryParse(
      RegExp(r'\b(\d+(?:\.\d+)?)\s+').firstMatch(text)?.group(1) ?? '',
    );
    final isHalf = RegExp(
      r'\b(half|demi|moitie|halb\w*|medio|media|mezzo|mezza|pol\w*)\b',
    ).hasMatch(text);
    final count = numericCount ?? (isHalf ? 0.5 : 1.0);
    if (RegExp(r'\b(bottle|butelk|flasche|bouteille|botella|bottiglia)')
        .hasMatch(text)) {
      return WaterIntake((500 * count).round());
    }
    return WaterIntake((250 * count).round());
  }
}

class FoodTile extends StatelessWidget {
  const FoodTile(
    this.entry, {
    super.key,
    required this.onDelete,
    this.onEdit,
    this.onSync,
  });
  final FoodEntry entry;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  final Future<void> Function()? onSync;

  void _openPhoto(BuildContext context, String path) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PhotoViewerScreen(path: path)),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: Column(
        children: [
          InkWell(
            onTap: onEdit,
            onLongPress: onEdit,
            borderRadius: BorderRadius.circular(15),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _EntryThumbnail(
                    localPath: entry.photoPathAt(0),
                    mediaId: entry.photoMediaIdAt(0),
                    size: 48,
                    icon: entry.displayIcon,
                    onTapPath: entry.photoCount == 0
                        ? null
                        : (path) => _openPhoto(context, path),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LText(
                          entry.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        LText(
                          entry.time,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      LText(
                        '${entry.isExercise ? '−' : ''}${entry.calories}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const LText(
                        'kcal',
                        style: TextStyle(fontSize: 10, color: Colors.black45),
                      ),
                    ],
                  ),
                  if (onSync != null)
                    _SyncButton(onSync: onSync!, entryName: entry.name),
                  IconButton(
                    onPressed: onDelete,
                    tooltip: ui(context, 'Delete entry'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: coral,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (entry.photoCount > 1)
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
                scrollDirection: Axis.horizontal,
                itemCount: entry.photoCount,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) => _EntryThumbnail(
                  localPath: entry.photoPathAt(index),
                  mediaId: entry.photoMediaIdAt(index),
                  size: 44,
                  icon: entry.displayIcon,
                  onTapPath: (path) => _openPhoto(context, path),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

// Sender-side sync state: shows a spinner while the request is in flight
// (previously there was no feedback at all between tap and the
// success/error snackbar) and disables itself meanwhile so a slow request
// can't be retapped into a duplicate share.
class _SyncButton extends StatefulWidget {
  const _SyncButton({required this.onSync, required this.entryName});
  final Future<void> Function() onSync;
  final String entryName;
  @override
  State<_SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<_SyncButton> {
  bool _busy = false;

  Future<void> _handleTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LText('Synced "${widget.entryName}"')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LText(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: _busy ? null : _handleTap,
    tooltip: ui(context, 'Sync entry with linked people'),
    visualDensity: VisualDensity.compact,
    icon: _busy
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: aqua),
          )
        : const Icon(Icons.sync, color: aqua, size: 20),
  );
}

// The single choke point every FoodTile/standalone-photo thumbnail goes
// through. A local filesystem path is only ever meaningful on the device
// that wrote it -- one arriving from another device via sync (or an old/
// partially-synced entry) must never be handed to Image.file as-is, so
// this checks existence first. When there's no usable local file but a
// backend media id is present (a received/synced photo), it downloads and
// caches the bytes once via MediaService and shows a brief loading state
// meanwhile; a failed/offline download just leaves the harmless
// placeholder in place -- rebuilding (reopening Today, pull-to-refresh)
// retries automatically since nothing gets cached on failure.
class _EntryThumbnail extends StatefulWidget {
  const _EntryThumbnail({
    required this.localPath,
    required this.mediaId,
    required this.size,
    this.icon = Icons.restaurant,
    this.onTapPath,
  });
  final String? localPath;
  final String? mediaId;
  final double size;
  final IconData icon;
  final ValueChanged<String>? onTapPath;

  @override
  State<_EntryThumbnail> createState() => _EntryThumbnailState();
}

class _EntryThumbnailState extends State<_EntryThumbnail> {
  String? _resolvedPath;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_EntryThumbnail old) {
    super.didUpdateWidget(old);
    if (old.localPath != widget.localPath || old.mediaId != widget.mediaId)
      _resolve();
  }

  void _resolve() {
    final local = widget.localPath;
    if (local != null && File(local).existsSync()) {
      setState(() {
        _resolvedPath = local;
        _loading = false;
      });
      return;
    }
    final mediaId = widget.mediaId;
    if (mediaId == null) {
      setState(() {
        _resolvedPath = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    const MediaService().download(defaultServerUrl, mediaId).then((path) {
      if (!mounted) return;
      setState(() {
        _resolvedPath = path;
        _loading = false;
      });
    });
  }

  Widget _placeholder() => Container(
    width: widget.size,
    height: widget.size,
    decoration: BoxDecoration(
      color: mint,
      borderRadius: BorderRadius.circular(widget.size >= 48 ? 15 : 10),
    ),
    child: Icon(widget.icon, color: forest, size: widget.size * 0.5),
  );

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.size >= 48 ? 15 : 10);
    final resolved = _resolvedPath;
    final Widget child;
    if (resolved != null) {
      child = Image.file(
        File(resolved),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    } else if (_loading) {
      child = Container(
        width: widget.size,
        height: widget.size,
        color: mint,
        child: Center(
          child: SizedBox.square(
            dimension: widget.size * 0.35,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else {
      child = _placeholder();
    }
    final clipped = ClipRRect(borderRadius: radius, child: child);
    if (resolved == null || widget.onTapPath == null) return clipped;
    return InkWell(
      borderRadius: radius,
      onTap: () => widget.onTapPath!(resolved),
      child: clipped,
    );
  }
}

// Item 9: tap a thumbnail -> full image; back/close -> return to the
// timeline. Deliberately minimal (no zoom/gallery library) to keep this
// small.
class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.path, this.caption});
  final String path;
  final String? caption;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    body: Stack(
      children: [
        Center(
          child: File(path).existsSync()
              ? InteractiveViewer(
                  child: Image.file(
                    File(path),
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white38,
                      size: 64,
                    ),
                  ),
                )
              : const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white38,
                  size: 64,
                ),
        ),
        if ((caption ?? '').trim().isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  caption!.trim(),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

// Item 3: a thin horizontal strip of standalone-photo thumbnails, shown
// directly under "Today's timeline" and above the grouped meal categories.
// Deliberately bare (no caption/calories/time/category) -- these are media,
// not FoodEntry rows.
class _StandalonePhotoStrip extends StatelessWidget {
  const _StandalonePhotoStrip({required this.photos});
  final List<DayPhoto> photos;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: photos.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final photo = photos[index];
        final exists = File(photo.path).existsSync();
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  PhotoViewerScreen(path: photo.path, caption: photo.caption),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: exists
                ? Image.file(
                    File(photo.path),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 56,
                      height: 56,
                      color: mint,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: forest,
                      ),
                    ),
                  )
                : Container(
                    width: 56,
                    height: 56,
                    color: mint,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: forest,
                    ),
                  ),
          ),
        );
      },
    ),
  );
}

class FoodEstimate {
  const FoodEstimate(
    this.calories,
    this.protein,
    this.carbs, {
    this.fat,
    this.fibre,
    this.weightGrams,
  });
  final int calories, protein, carbs;
  // Only ever set from the local dataset's own fat/fibre-per-100g columns
  // (see NutrientRecord) -- never invented for a food the dataset doesn't
  // cover. Sugar/salt/saturated fat have no such column, so they can't be
  // derived here at all; they only ever come from a scanned label.
  final int? fat;
  final int? fibre;
  final double? weightGrams;
}

class FoodEstimator {
  static const _numberWords = {
    'a': 1,
    'an': 1,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
  };

  // How many of an item precede a match, from either a bare/×-suffixed digit
  // ("2x", "2 ") or a spelled-out number ("two") right before it. Defaults to
  // one so a plain mention (no explicit quantity) still counts as itself.
  static int _countBefore(String before) {
    final digit = RegExp(r'(\d+)\s*x?\s*$').firstMatch(before);
    if (digit != null) return int.parse(digit.group(1)!);
    final word = RegExp(
      r'\b(a|an|one|two|three|four|five|six|seven|eight|nine|ten)\s*$',
      caseSensitive: false,
    ).firstMatch(before);
    if (word != null) {
      return _numberWords[word.group(1)!.toLowerCase()] ?? 1;
    }
    return 1;
  }

  static bool _overlaps(List<(int, int)> claimed, int start, int end) =>
      claimed.any((r) => start < r.$2 && end > r.$1);

  static FoodEstimate estimate(String description) {
    final text = description.toLowerCase();
    var kcal = 0.0, protein = 0.0, carbs = 0.0;
    // Positions already accounted for, so a composite item (e.g.
    // "cheeseburger") isn't also counted again for a shorter word it
    // happens to contain (e.g. "cheese").
    final claimed = <(int, int)>[];

    // Whole-item fast-food/composite foods: values are per typical single
    // serving, not per 100g — a bare or "Nx" quantity right before the
    // match multiplies the whole serving.
    final wholeItems = <String, (double, double, double)>{
      'quarter pounder with cheese': (520, 30, 41),
      'quarter pounder': (480, 28, 38),
      'big mac': (550, 25, 45),
      'mcchicken': (400, 14, 39),
      'fillet-o-fish': (390, 15, 39),
      'filet-o-fish': (390, 15, 39),
      'chicken nuggets': (250, 14, 15),
      'mcnuggets': (250, 14, 15),
      'cheeseburger': (300, 15, 31),
      'hamburger': (250, 12, 30),
      'large fries': (444, 5, 58),
      'medium fries': (340, 4, 44),
      'small fries': (230, 3, 30),
      'fries': (340, 4, 44),
      'large coke': (210, 0, 58),
      'medium coke': (170, 0, 46),
      'small coke': (140, 0, 39),
      'coke': (170, 0, 46),
      'cola': (170, 0, 46),
      'milkshake': (350, 8, 60),
      'fruit smoothie': (170, 3, 35),
      'orange juice': (110, 2, 24),
      'apple juice': (115, 0, 28),
      'fruit juice': (115, 1, 27),
      'juice': (115, 1, 27),
      'coffee': (3, 0, 0),
      'tea': (2, 0, 0),
      'lemonade': (100, 0, 25),
      'soda': (140, 0, 35),
      'apple pie': (240, 2, 33),
      'side salad': (25, 1, 4),
    };
    for (final item in wholeItems.entries) {
      for (final match in item.key.allMatches(text)) {
        if (_overlaps(claimed, match.start, match.end)) continue;
        final before = text.substring(
          math.max(0, match.start - 20),
          match.start,
        );
        final count = _countBefore(before);
        kcal += item.value.$1 * count;
        protein += item.value.$2 * count;
        carbs += item.value.$3 * count;
        claimed.add((match.start, match.end));
        break;
      }
    }

    // Ingredients measured by weight: values per 100g plus a sensible
    // default portion when no gram amount is given in the text.
    final foods = <String, (double, double, double, double)>{
      'oat': (389, 16.9, 66.3, 40),
      'porridge': (389, 16.9, 66.3, 40),
      'yoghurt': (80, 5, 7, 100),
      'yogurt': (80, 5, 7, 100),
      'milk': (50, 3.5, 4.8, 150),
      'peach': (39, .9, 9.5, 100),
      'plum': (46, .7, 11.4, 80),
      'crisp': (520, 6, 53, 25),
      'chips': (520, 6, 53, 25),
      'chocolate raisin': (400, 5, 72, 30),
      'raisin': (300, 3.1, 79, 30),
      'cottage cheese': (98, 11, 3.4, 60),
      'coleslaw': (150, 1.5, 12, 70),
      'ham': (145, 21, 1.5, 60),
      'bacon': (450, 37, 1.3, 40),
      'sausage': (300, 13, 3, 100),
      'egg': (143, 13, .7, 60),
      'toast': (265, 9, 49, 35),
      'bread': (265, 9, 49, 40),
      'banana': (89, 1.1, 23, 120),
      'apple': (52, .3, 14, 150),
      'chicken': (165, 31, 0, 150),
      'salmon': (208, 20, 0, 150),
      'trout': (148, 20.8, 0, 150),
      'tuna': (132, 28, 0, 120),
      'cod': (105, 23, 0, 150),
      'rice': (130, 2.7, 28, 180),
      'pasta': (158, 5.8, 31, 180),
      'potato': (87, 1.9, 20, 180),
      'cheese': (350, 25, 1.3, 30),
      'avocado': (160, 2, 8.5, 100),
      'mushroom': (22, 3.1, 3.3, 60),
      'tomato': (18, .9, 3.9, 100),
      'onion': (40, 1.1, 9.3, 50),
      'carrot': (41, .9, 10, 80),
      'bell pepper': (31, 1, 6, 60),
      'capsicum': (31, 1, 6, 60),
      'pickle': (12, .5, 2.4, 50),
      'cabbage': (25, 1.3, 5.8, 100),
      'lettuce': (15, 1.4, 2.9, 60),
      'salad': (60, 2, 5, 100),
      'vinegar': (18, 0, .4, 15),
      'beans': (127, 6.6, 21, 150),
      'soup': (55, 2.5, 7, 250),
    };
    for (final item in foods.entries) {
      final matches = item.key.allMatches(text).toList();
      if (matches.isEmpty) continue;
      final match = matches.first;
      if (_overlaps(claimed, match.start, match.end)) continue;
      final before = text.substring(math.max(0, match.start - 32), match.start);
      final gramMatch = RegExp(r'(\d+(?:\.\d+)?)\s*g(?:\s+\w+){0,2}\s*$')
          .firstMatch(before);
      final multiplied = RegExp(
        r'(\d+)\s*x\s*(\d+(?:\.\d+)?)\s*g(?:\s+\w+){0,2}\s*$',
      ).firstMatch(before);
      final grams = multiplied != null
          ? int.parse(multiplied.group(1)!) * double.parse(multiplied.group(2)!)
          : gramMatch != null
          ? double.parse(gramMatch.group(1)!)
          : item.value.$4 * _countBefore(before);
      kcal += item.value.$1 * grams / 100;
      protein += item.value.$2 * grams / 100;
      carbs += item.value.$3 * grams / 100;
      claimed.add((match.start, match.end));
    }

    // Drinks measured by volume: values per 100ml plus a default single
    // measure/glass when no ml amount is given in the text.
    final drinks = <String, (double, double, double)>{
      'whisky': (220, 0, 0),
      'whiskies': (220, 0, 0),
      'whiskey': (220, 0, 0),
      'vodka': (220, 0, 0),
      'gin': (220, 0, 0),
      'rum': (220, 0, 0),
      'wine': (83, 0.1, 2.6),
      'beer': (43, 0.5, 3.6),
    };
    for (final item in drinks.entries) {
      final matches = item.key.allMatches(text).toList();
      if (matches.isEmpty) continue;
      final match = matches.first;
      if (_overlaps(claimed, match.start, match.end)) continue;
      final around = text.substring(
        math.max(0, match.start - 40),
        math.min(text.length, match.end + 40),
      );
      final mlMatch = RegExp(r'(\d+(?:\.\d+)?)\s*ml').firstMatch(around);
      final before = text.substring(math.max(0, match.start - 20), match.start);
      final millilitres = mlMatch != null
          ? double.parse(mlMatch.group(1)!)
          : 25.0 * _countBefore(before);
      kcal += item.value.$1 * millilitres / 100;
      protein += item.value.$2 * millilitres / 100;
      carbs += item.value.$3 * millilitres / 100;
      claimed.add((match.start, match.end));
    }
    if (kcal == 0) return const FoodEstimate(0, 0, 0);
    return FoodEstimate(kcal.round(), protein.round(), carbs.round());
  }
}

// Structured nutrition-label extraction (item 4) -- separate from
// FoodParser's sentence grammar entirely. This reads a nutrition TABLE
// (product packaging), not a natural-language description, and every
// value is either a real recognized number or left null; nothing here
// ever invents a figure to fill a gap.
class LabelReading {
  const LabelReading({
    this.productName,
    this.caloriesPer100,
    this.proteinPer100,
    this.carbsPer100,
    this.sugarsPer100,
    this.fatPer100,
    this.saturatedFatPer100,
    this.fibrePer100,
    this.saltPer100,
    this.basis,
    this.servingSizeGrams,
    this.totalGrams,
  });
  final String? productName;
  final double? caloriesPer100;
  final double? proteinPer100;
  final double? carbsPer100;
  final double? sugarsPer100;
  final double? fatPer100;
  final double? saturatedFatPer100;
  final double? fibrePer100;
  final double? saltPer100;
  // 'per100g' | 'per100ml' | 'perServing' -- which basis the numbers above
  // were actually printed under, when it could be told apart.
  final String? basis;
  final double? servingSizeGrams;
  final double? totalGrams;
  bool get hasNutrition => caloriesPer100 != null;
  bool get isConfident => caloriesPer100 != null && totalGrams != null;
  bool get isEmpty =>
      productName == null &&
      caloriesPer100 == null &&
      proteinPer100 == null &&
      carbsPer100 == null &&
      fatPer100 == null;
}

class LabelParser {
  static double? _parseNumber(String raw) =>
      double.tryParse(raw.replaceAll(',', '.'));

  // Tries each EN/PL keyword alternative in turn against the SAME
  // diacritic-folded text every alternative was folded against, so
  // "Białko"/"BIALKO"/"bialka" all still match "białko".
  static double? _firstNumberNearAny(
    String foldedText,
    List<String> keywordPatterns,
    String unitPattern,
  ) {
    for (final keyword in keywordPatterns) {
      final match = RegExp(
        '$keyword.{0,40}?(\\d+(?:[.,]\\d+)?)\\s*$unitPattern',
        caseSensitive: false,
      ).firstMatch(foldedText);
      if (match != null) return _parseNumber(match.group(1)!);
    }
    return null;
  }

  // A plain, honest guess at a product name from raw OCR text: the first
  // non-empty line that isn't itself a number/measurement -- no rigid
  // phrase or word-count requirement.
  static String? guessProductName(String rawText) {
    for (final line in rawText.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (RegExp(r'^[\d.,%\s]+[a-zA-Z]{0,4}$').hasMatch(trimmed)) continue;
      return trimmed;
    }
    return null;
  }

  static LabelReading parse(String rawText) {
    final collapsed = rawText.replaceAll(RegExp(r'\s+'), ' ');
    // Folded for keyword matching only -- diacritics must not matter for
    // recognizing "Energia"/"Tłuszcz"/"Węglowodany"/etc, but the raw text
    // (for the product-name guess) keeps its real spelling.
    final folded = foldDiacritics(collapsed);
    const g = 'g';

    final calories = _firstNumberNearAny(folded, [
      '(?:energy|calories|energia|wartosc energetyczna)',
    ], 'kcal');
    final protein = _firstNumberNearAny(folded, ['(?:protein|bialko)'], g);
    final carbs = _firstNumberNearAny(folded, [
      '(?:carbohydrate|carbs|weglowodany)',
    ], g);
    final sugars = _firstNumberNearAny(folded, [
      '(?:of which sugars|sugars|w tym cukry|cukry)',
    ], g);
    final fat = _firstNumberNearAny(folded, ['(?:total fat|fat|tluszcz)'], g);
    final saturatedFat = _firstNumberNearAny(folded, [
      '(?:of which saturates|saturates|saturated fat|w tym nasycone|nasycone)',
    ], g);
    final fibre = _firstNumberNearAny(folded, ['(?:fibre|fiber|blonnik)'], g);
    final salt = _firstNumberNearAny(folded, ['(?:salt|sol)'], g);

    String? basis;
    if (RegExp(
      r'(?:per|na|w)\s*100\s*ml',
      caseSensitive: false,
    ).hasMatch(folded)) {
      basis = 'per100ml';
    } else if (RegExp(
      r'(?:per|na|w)\s*100\s*g',
      caseSensitive: false,
    ).hasMatch(folded)) {
      basis = 'per100g';
    } else if (RegExp(
      r'(?:per serving|na porcje|porcja)',
      caseSensitive: false,
    ).hasMatch(folded)) {
      basis = 'perServing';
    }

    final servingSize = _firstNumberNearAny(folded, [
      '(?:serving size|wielkosc porcji)',
    ], g);

    double? totalGrams;
    final netWeight = RegExp(
      r'(?:℮|net\s*(?:weight|wt)\.?:?|masa\s*netto|zawartosc\s*netto)\s*(\d+(?:[.,]\d+)?)\s*(kg|g|l|ml)\b',
      caseSensitive: false,
    ).firstMatch(folded);
    if (netWeight != null) {
      final value = _parseNumber(netWeight.group(1)!);
      final unit = netWeight.group(2)!.toLowerCase();
      if (value != null) {
        totalGrams = (unit == 'kg' || unit == 'l') ? value * 1000 : value;
      }
    } else {
      final servingsMatch = RegExp(
        r'servings?\s*per\s*container[^0-9]{0,10}(\d+(?:[.,]\d+)?)',
        caseSensitive: false,
      ).firstMatch(folded);
      final servings = servingsMatch == null
          ? null
          : _parseNumber(servingsMatch.group(1)!);
      if (servingSize != null && servings != null) {
        totalGrams = servingSize * servings;
      }
    }

    return LabelReading(
      productName: guessProductName(rawText),
      caloriesPer100: calories,
      proteinPer100: protein,
      carbsPer100: carbs,
      sugarsPer100: sugars,
      fatPer100: fat,
      saturatedFatPer100: saturatedFat,
      fibrePer100: fibre,
      saltPer100: salt,
      basis: basis,
      servingSizeGrams: servingSize,
      totalGrams: totalGrams,
    );
  }
}

// Returned from AddItemSheet when a photo was attached to an EXISTING
// entry rather than saved as a new one -- the caller looks the entry up by
// identity and replaces it with `updated` (see FoodEntry.copyWithPhoto).
class PhotoAttachOutcome {
  const PhotoAttachOutcome({required this.original, required this.updated});
  final FoodEntry original;
  final FoodEntry updated;
}

// Returned when a standalone photo (see DayPhotoRepository) was saved
// directly from inside AddMealSheet's "Take photo" flow -- the caller has
// nothing to merge into `entries` (it isn't a FoodEntry at all), it just
// needs to reload today's photo strip.
class DayPhotoSaved {
  const DayPhotoSaved();
}

class AddItemSheet extends StatelessWidget {
  const AddItemSheet({
    super.key,
    required this.onAddWater,
    required this.entries,
    this.bodyWeightKg,
    this.locale = 'en',
  });
  final ValueChanged<int> onAddWater;
  final List<FoodEntry> entries;
  final double? bodyWeightKg;
  final String locale;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(20, 12, 20, sheetBottomInset(context, 28)),
    decoration: const BoxDecoration(
      color: cream,
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    child: Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: SizedBox(width: 42, child: Divider(thickness: 4)),
          ),
          const SizedBox(height: 18),
          const LText(
            'What would you like to add?',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: mint,
              child: Icon(Icons.restaurant, color: forest),
            ),
            title: const LText(
              'Food or drink',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const LText('Describe it, photograph it or scan a label'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final result = await showModalBottomSheet<Object>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => AddMealSheet(locale: locale, entries: entries),
              );
              if (!context.mounted || result == null) return;
              if (result case final WaterIntake water) {
                onAddWater(water.millilitres);
                Navigator.pop(context);
              } else if (result case final FoodEntry entry) {
                if (entry.waterMl > 0) onAddWater(entry.waterMl);
                Navigator.pop(context, entry);
              } else if (result case final PhotoAttachOutcome outcome) {
                Navigator.pop(context, outcome);
              } else if (result is DayPhotoSaved) {
                Navigator.pop(context, result);
              }
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFFE9DF),
              child: Icon(Icons.directions_run, color: coral),
            ),
            title: const LText(
              'Exercise',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const LText('Record an activity and duration'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final result = await showModalBottomSheet<FoodEntry>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => AddExerciseSheet(
                  bodyWeightKg: bodyWeightKg,
                  locale: locale,
                ),
              );
              if (context.mounted && result != null) {
                Navigator.pop(context, result);
              }
            },
          ),
        ],
      ),
    ),
  );
}

class AddExerciseSheet extends StatefulWidget {
  const AddExerciseSheet({super.key, this.bodyWeightKg, this.locale = 'en'});
  final double? bodyWeightKg;
  final String locale;
  @override
  State<AddExerciseSheet> createState() => _AddExerciseSheetState();
}

class _AddExerciseSheetState extends State<AddExerciseSheet> {
  // A few natural phrasings the field actually understands, rotated in
  // the hint text so users see they can type freely instead of filling
  // in separate activity/duration boxes.
  static const _hintExamplesEn = [
    '30 min jogging',
    '1hr cycling',
    'squash for 45 min',
    '1000 steps',
    'walked 5km for 40 min',
  ];
  static const _hintExamplesPl = [
    '30 min spacer',
    '20 min jazda konna',
    '10 min tenis stołowy',
    '1000 kroków',
  ];

  final description = TextEditingController();
  bool aiAvailable = false;
  bool busy = false;
  String? notice;
  ExerciseParser? parser;
  int hintIndex = 0;
  Timer? _hintTimer;

  List<String> get _hintExamples =>
      widget.locale == 'pl' ? _hintExamplesPl : _hintExamplesEn;

  @override
  void initState() {
    super.initState();
    const AiService().isAvailable().then((value) {
      if (mounted) setState(() => aiAvailable = value);
    });
    ExerciseParser.load(locale: widget.locale).then((value) {
      if (mounted) setState(() => parser = value);
    });
    _hintTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted)
        setState(() => hintIndex = (hintIndex + 1) % _hintExamples.length);
    });
  }

  @override
  void dispose() {
    description.dispose();
    _hintTimer?.cancel();
    super.dispose();
  }

  String _activityLabel(ExerciseParser p, String id) =>
      p.catalogue.entries.firstWhere((e) => e.id == id).canonical;

  // Writes an AI-derived MET for an activity local truly didn't recognize
  // into the SAME shared catalogue ExerciseCatalogueSyncService pulls from
  // -- mirrors _AddMealSheetState._contributeAiFood. Best-effort: a
  // failure here just means this one activity stays AI-only a bit longer,
  // never blocks logging the entry.
  Future<void> _contributeAiActivity(String name, double met) async {
    try {
      final overlay = await LocalExerciseCatalogueOverlay.load();
      await overlay.upsert(
        OverlayExerciseEntry(
          id: OverlayExerciseEntry.idFor(name),
          canonical: name,
          met: met,
          source: 'ai',
        ),
      );
      await const ExerciseCatalogueSyncService().contribute(
        defaultServerUrl,
        name: name,
        met: met,
        locale: widget.locale,
      );
    } catch (_) {
      // Offline or the server is unreachable -- stays AI-only for now.
    }
  }

  Future<void> _addExercise() async {
    final text = description.text.trim();
    if (text.isEmpty) return;
    setState(() => notice = null);

    // Local-first: run the offline MET parser before ever considering AI.
    final localParser =
        parser ?? await ExerciseParser.load(locale: widget.locale);
    final result = localParser.parse(text, bodyWeightKg: widget.bodyWeightKg);

    // Only reach for AI when the local parser found nothing to suggest at
    // all -- an ambiguous activity ("tennis", "swimming") always gets the
    // local clarification instead, never a silent AI guess; and a
    // recognized activity with no body weight/duration on file stays
    // blocked rather than spending a network call whose answer would just
    // be discarded (canonical MET math is authoritative below).
    int? aiCalories;
    if (result.activityId == null &&
        result.suggestions.isEmpty &&
        aiAvailable) {
      setState(() => busy = true);
      try {
        final aiResult = await const AiService().describe(
          serverUrl: defaultServerUrl,
          kind: 'exercise',
          text: text,
        );
        aiCalories = aiResult.calories;
        // Teach the global activity catalogue about this one, the same way
        // the food AI-fallback does (see _AddMealSheetState._addToDay) --
        // but only when a real MET can be derived from AI's own calorie
        // figure divided by a KNOWN duration and body weight. Without both,
        // there is no honest way to turn "N kcal for this session" into a
        // duration/weight-independent MET, so it's left AI-only rather
        // than guessing one.
        final minutes = result.durationMinutes;
        final weightKg = widget.bodyWeightKg;
        if (minutes != null &&
            minutes > 0 &&
            weightKg != null &&
            weightKg > 0 &&
            aiResult.calories > 0) {
          final met = aiResult.calories / (weightKg * (minutes / 60));
          if (met > 0 && met <= 25) {
            unawaited(_contributeAiActivity(aiResult.name, met));
          }
        }
      } catch (_) {
        // Falls through to the "unresolved" notice below.
      } finally {
        if (mounted) setState(() => busy = false);
      }
      if (!mounted) return;
    }
    // Canonical MET math always wins once the activity is recognized -- AI
    // only ever supplies the number when there's no canonical activity at
    // all, so a saved entry never carries MET/activity evidence that
    // mathematically contradicts its own calorie total.
    final calories = result.activityId != null
        ? result.calorieEstimateKcal?.round()
        : aiCalories;

    if (calories == null) {
      setState(() {
        notice = result.activityId == null
            ? (result.suggestions.isNotEmpty
                  ? 'Did you mean "${_activityLabel(localParser, result.suggestions.first)}"?'
                  : 'We don\'t recognize "$text" yet, so we can\'t estimate calories for it.')
            : result.durationMinutes == null
            ? 'How long did you do this for? Try adding something like "30 min" or "2 hours".'
            : 'Add your weight in your profile to estimate calories for this activity.';
      });
      return;
    }
    if (!mounted) return;

    final durationLabel = result.durationMinutes == null
        ? ''
        : result.durationMinutes! >= 60 && result.durationMinutes! % 60 == 0
        ? ' · ${(result.durationMinutes! / 60).round()} hr'
        : ' · ${result.durationMinutes!.round()} min';
    Navigator.pop(
      context,
      FoodEntry(
        text,
        '${_clockTime()}$durationLabel',
        calories,
        0,
        Icons.directions_run,
        isExercise: true,
        exerciseActivityId: result.activityId,
        exerciseDurationMinutes: result.durationMinutes,
        exerciseMet: result.met,
        exerciseBodyWeightKg: widget.bodyWeightKg,
        exerciseApproximate: result.approximate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(20, 18, 20, sheetBottomInset(context, 24)),
    decoration: const BoxDecoration(
      color: cream,
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LText(
          'Add exercise',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: description,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: ui(context, 'What did you do?'),
            hintText: _hintExamples[hintIndex % _hintExamples.length],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: LText(
            'Calories are an estimate based on your weight, activity and duration.',
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                LText(
                  'Estimating with AI…',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        if (notice != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE5DD),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: coral, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: LText(
                    notice!,
                    style: const TextStyle(fontSize: 12, color: ink),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy ? null : () => _addExercise(),
            icon: const Icon(Icons.add),
            label: const LText('Add exercise'),
          ),
        ),
      ],
    ),
  );
}

// Parses the leading "HH:MM" off a saved entry's display time back into
// an [ExtractedTime] -- used so editing a description that doesn't
// itself retype a time keeps the entry's existing time instead of
// silently jumping it to "now".
ExtractedTime? _parseEntryTime(String time) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(time);
  if (match == null) return null;
  return ExtractedTime(int.parse(match.group(1)!), int.parse(match.group(2)!));
}

// Item 7: when a food genuinely can't be resolved locally, this offers a
// simple way to add it instead of just blocking the user. Saved to the
// SAME local overlay CatalogueSyncService downloads into (see
// lib/parser/catalogue/local_overlay.dart) -- immediately usable on this
// device, and contributed to the backend's global catalogue in the
// background so it can eventually reach other users too, without ever
// overwriting existing trusted data (see food_catalogue.mjs's merge rules).
// What AddFoodSheet actually confirms, regardless of who's using it (the
// "add this unknown food" flow or the scan-label confirmation flow): the
// nutrition values the user reviewed and approved, plus whether they also
// chose to keep it as a reusable food. Missing values stay null -- never
// filled with an invented number.
class AddFoodResult {
  const AddFoodResult({
    required this.name,
    required this.kcal,
    this.protein,
    this.carbs,
    this.fat,
    this.saturatedFat,
    this.sugar,
    this.fibre,
    this.salt,
    required this.servingAmount,
    required this.servingUnit,
    this.weightGrams,
    required this.savedToCatalogue,
  });
  final String name;
  final double kcal;
  final double? protein, carbs, fat, saturatedFat, sugar, fibre, salt;
  final double servingAmount;
  final String servingUnit;
  // The actual total weight this result represents -- the portion above,
  // scaled up to the whole pack when a pack weight was given; null when
  // neither this sheet nor the label had any weight to go on at all.
  final double? weightGrams;
  final bool savedToCatalogue;
}

class AddFoodSheet extends StatefulWidget {
  const AddFoodSheet({
    super.key,
    required this.suggestedName,
    this.locale = 'en',
    this.title = 'Add this food',
    this.subtitle,
    this.initialCalories,
    this.initialProtein,
    this.initialCarbs,
    this.initialFat,
    this.initialSaturatedFat,
    this.initialSugar,
    this.initialFibre,
    this.initialSalt,
    this.initialServingAmount,
    this.initialServingUnit,
    this.defaultSaveToCatalogue = true,
    this.showPackWeightField = false,
    this.initialPackWeightGrams,
  });
  final String suggestedName;
  final String locale;
  final String title;
  final String? subtitle;
  final double? initialCalories, initialProtein, initialCarbs, initialFat;
  final double? initialSaturatedFat, initialSugar, initialFibre, initialSalt;
  final double? initialServingAmount;
  final String? initialServingUnit;
  // Whether "save to my food list" starts checked -- off by default for a
  // scanned label (often a specific branded product), on by default for
  // an unresolved food the user is naming from scratch. Either way it's
  // just a checkbox the user controls, per "optionally offer".
  final bool defaultSaveToCatalogue;
  // A scanned nutrition label reports per-100g/ml figures, but a whole
  // pack is usually eaten as one entry -- when true, an extra "whole pack
  // weight" field scales calories/protein/carbs/fat up from the
  // calories/portion row above rather than requiring the user to do that
  // multiplication by hand. Pre-filled from the label's printed net
  // weight ("Masa netto"/"Net weight") when OCR found one; left blank
  // (typed in manually from the label) otherwise.
  final bool showPackWeightField;
  final double? initialPackWeightGrams;
  @override
  State<AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends State<AddFoodSheet> {
  late final name = TextEditingController(text: widget.suggestedName);
  late final calories = TextEditingController(
    text: widget.initialCalories == null
        ? ''
        : _formatNum(widget.initialCalories!),
  );
  late final servingAmount = TextEditingController(
    text: _formatNum(widget.initialServingAmount ?? 100),
  );
  late final servingUnit = TextEditingController(
    text: widget.initialServingUnit ?? 'g',
  );
  late final protein = TextEditingController(
    text: widget.initialProtein == null
        ? ''
        : _formatNum(widget.initialProtein!),
  );
  late final carbs = TextEditingController(
    text: widget.initialCarbs == null ? '' : _formatNum(widget.initialCarbs!),
  );
  late final fat = TextEditingController(
    text: widget.initialFat == null ? '' : _formatNum(widget.initialFat!),
  );
  late final saturatedFat = TextEditingController(
    text: widget.initialSaturatedFat == null
        ? ''
        : _formatNum(widget.initialSaturatedFat!),
  );
  late final sugar = TextEditingController(
    text: widget.initialSugar == null ? '' : _formatNum(widget.initialSugar!),
  );
  late final fibre = TextEditingController(
    text: widget.initialFibre == null ? '' : _formatNum(widget.initialFibre!),
  );
  late final salt = TextEditingController(
    text: widget.initialSalt == null ? '' : _formatNum(widget.initialSalt!),
  );
  late final packWeight = TextEditingController(
    text: widget.initialPackWeightGrams == null
        ? ''
        : _formatNum(widget.initialPackWeightGrams!),
  );
  late bool saveToCatalogue = widget.defaultSaveToCatalogue;
  String? error;
  bool saving = false;

  static String _formatNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    name.dispose();
    calories.dispose();
    servingAmount.dispose();
    servingUnit.dispose();
    protein.dispose();
    carbs.dispose();
    fat.dispose();
    saturatedFat.dispose();
    sugar.dispose();
    fibre.dispose();
    salt.dispose();
    packWeight.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  // Mass/volume units the portion amount could be given in, each as a
  // multiple of the pack weight field's own unit (always grams) -- so
  // switching "Unit" between these keeps the pack-weight scaling correct
  // instead of silently assuming everything is already in grams.
  static const _gramsPerUnit = {
    'g': 1.0,
    'gram': 1.0,
    'grams': 1.0,
    'ml': 1.0,
    'millilitre': 1.0,
    'millilitres': 1.0,
    'milliliter': 1.0,
    'milliliters': 1.0,
    'kg': 1000.0,
    'kilogram': 1000.0,
    'kilograms': 1000.0,
    'l': 1000.0,
    'litre': 1000.0,
    'litres': 1000.0,
    'liter': 1000.0,
    'liters': 1000.0,
  };

  // How much bigger the whole pack is than the calories/portion row above,
  // when the user has given a whole-pack weight -- 1.0 (no scaling) until
  // both a valid portion size and a valid pack weight are present. A unit
  // like "pc"/"slice" has no fixed weight, so it's treated as already
  // matching the pack weight's own unit (grams) rather than guessed at.
  double get _packScaleFactor {
    if (!widget.showPackWeightField) return 1;
    final amount = _num(servingAmount);
    final pack = _num(packWeight);
    if (amount == null || amount <= 0 || pack == null || pack <= 0) return 1;
    final unitGrams =
        _gramsPerUnit[servingUnit.text.trim().toLowerCase()] ?? 1.0;
    return pack / (amount * unitGrams);
  }

  Future<void> _save() async {
    final foodName = name.text.trim();
    final kcal = _num(calories);
    final amount = _num(servingAmount);
    if (foodName.isEmpty) {
      setState(() => error = 'Give the food a name.');
      return;
    }
    if (kcal == null || kcal < 0) {
      setState(() => error = 'Enter the calories for that portion.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => error = 'Enter the portion size those calories are for.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final unit = servingUnit.text.trim().isEmpty
        ? 'g'
        : servingUnit.text.trim();
    if (saveToCatalogue) {
      final entry = OverlayFoodEntry(
        id: OverlayFoodEntry.idFor(foodName),
        canonical: foodName,
        kcalPer100g: kcal * 100 / amount,
        proteinPer100g: () {
          final v = _num(protein);
          return v == null ? null : v * 100 / amount;
        }(),
        carbsPer100g: () {
          final v = _num(carbs);
          return v == null ? null : v * 100 / amount;
        }(),
        fatPer100g: () {
          final v = _num(fat);
          return v == null ? null : v * 100 / amount;
        }(),
        servingAmount: amount,
        servingUnit: unit,
        source: 'user',
      );
      final overlay = await LocalCatalogueOverlay.load();
      await overlay.upsert(entry);
      unawaited(
        const CatalogueSyncService().contribute(
          defaultServerUrl,
          name: foodName,
          kcal: kcal,
          protein: _num(protein),
          carbs: _num(carbs),
          fat: _num(fat),
          servingAmount: amount,
          servingUnit: unit,
          locale: widget.locale,
        ),
      );
    }
    if (mounted) {
      final scale = _packScaleFactor;
      double? scaled(TextEditingController c) {
        final v = _num(c);
        return v == null ? null : v * scale;
      }

      Navigator.pop(
        context,
        AddFoodResult(
          name: foodName,
          kcal: kcal * scale,
          protein: scaled(protein),
          carbs: scaled(carbs),
          fat: scaled(fat),
          saturatedFat: scaled(saturatedFat),
          sugar: scaled(sugar),
          fibre: scaled(fibre),
          salt: scaled(salt),
          servingAmount: amount,
          servingUnit: unit,
          weightGrams: amount * scale,
          savedToCatalogue: saveToCatalogue,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      decoration: const BoxDecoration(
        color: cream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 18, 20, sheetBottomInset(context, 24)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: SizedBox(width: 42, child: Divider(thickness: 4)),
            ),
            const SizedBox(height: 10),
            LText(
              widget.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            LText(
              widget.subtitle ?? 'Calories and a portion are enough — the rest is optional. Correct anything that’s wrong before confirming.',
              style: const TextStyle(color: Colors.black54, height: 1.35),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: ui(context, 'Food name')),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: calories,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: widget.showPackWeightField
                        ? (_) => setState(() {})
                        : null,
                    decoration: InputDecoration(
                      labelText: ui(context, 'Calories'),
                      suffixText: 'kcal',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: servingAmount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: widget.showPackWeightField
                        ? (_) => setState(() {})
                        : null,
                    decoration: InputDecoration(
                      labelText: ui(context, 'Portion amount'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: servingUnit,
                    onChanged: widget.showPackWeightField
                        ? (_) => setState(() {})
                        : null,
                    decoration: InputDecoration(labelText: ui(context, 'Unit')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const LText(
              'Units understood: g, kg, ml, l, pc, slice.',
              style: TextStyle(fontSize: 11, color: Colors.black45),
            ),
            if (widget.showPackWeightField) ...[
              const SizedBox(height: 14),
              TextField(
                controller: packWeight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: ui(context, 'Whole pack weight'),
                  suffixText: 'g',
                ),
              ),
              if (_packScaleFactor != 1) ...[
                const SizedBox(height: 6),
                LText(
                  '= ${_formatNum((_num(calories) ?? 0) * _packScaleFactor)} kcal for the whole pack',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: forest,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 14),
            const LText(
              'Optional',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: protein,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: ui(context, 'Protein'),
                      suffixText: 'g',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: carbs,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: ui(context, 'Carbs'),
                      suffixText: 'g',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: fat,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: ui(context, 'Fat'),
                      suffixText: 'g',
                    ),
                  ),
                ),
              ],
            ),
            // The rest of a nutrition label's usual rows -- only worth
            // showing when there's a real label behind this sheet to have
            // read them from (see showPackWeightField).
            if (widget.showPackWeightField) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: saturatedFat,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: ui(context, 'Saturated fat'),
                        suffixText: 'g',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: sugar,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: ui(context, 'Sugar'),
                        suffixText: 'g',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: fibre,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: ui(context, 'Fibre'),
                        suffixText: 'g',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: salt,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: ui(context, 'Salt'),
                  suffixText: 'g',
                ),
              ),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              value: saveToCatalogue,
              onChanged: (v) => setState(() => saveToCatalogue = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: const LText(
                'Save to my food list for reuse',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: const LText(
                'Also shared so others can benefit',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: LText(error!, style: const TextStyle(color: coral)),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving ? null : _save,
                child: saving
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const LText('Confirm'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class EditEntrySheet extends StatefulWidget {
  const EditEntrySheet({
    super.key,
    required this.entry,
    this.bodyWeightKg,
    this.locale = 'en',
  });
  final FoodEntry entry;
  final double? bodyWeightKg;
  final String locale;
  @override
  State<EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends State<EditEntrySheet> {
  late final description = TextEditingController(text: widget.entry.name);
  // Manual fallback numbers for when the retyped description doesn't fully
  // match the local food dataset (e.g. a home-cooked dish with too many
  // possible wordings to ever teach the parser) -- prefilled from the
  // entry's current totals so editing text alone still saves fine, and
  // directly editable so correcting a mismatch never requires resolving
  // through the dataset at all.
  late final calories = TextEditingController(text: '${widget.entry.calories}');
  late final protein = TextEditingController(text: '${widget.entry.protein}');
  late final carbs = TextEditingController(text: '${widget.entry.carbs}');
  // Weight and the rest of the label-style detail -- optional, blank when
  // the entry has never had a value for them.
  late final weightGrams = TextEditingController(
    text: _fmt(widget.entry.weightGrams),
  );
  late final fat = TextEditingController(text: _fmt(widget.entry.fat));
  late final saturatedFat = TextEditingController(
    text: _fmt(widget.entry.saturatedFat),
  );
  late final sugar = TextEditingController(text: _fmt(widget.entry.sugar));
  late final fibre = TextEditingController(text: _fmt(widget.entry.fibre));
  late final salt = TextEditingController(text: _fmt(widget.entry.salt));
  String? notice;
  bool busy = false;
  FoodParser? foodParser;
  ExerciseParser? exerciseParser;
  double _oldWaterMl = 0;
  // True the moment any number field below is touched directly (typing or
  // the weight-triggered rescale) -- once that happens, Save trusts those
  // numbers over a fresh re-parse of the description, even if the text
  // still happens to fully resolve against the dataset. Without this, a
  // manual correction to e.g. a home-cooked dish's calories kept getting
  // silently overwritten back to the dataset's own (wrong) total on every
  // save, because the text hadn't changed and still "resolved".
  bool _macrosDirty = false;
  void _markDirty() => _macrosDirty = true;

  @override
  void initState() {
    super.initState();
    if (!widget.entry.isExercise) weightGrams.addListener(_rescaleFromWeight);
    if (widget.entry.isExercise) {
      ExerciseParser.load(locale: widget.locale).then((value) {
        if (mounted) setState(() => exerciseParser = value);
      });
    } else {
      FoodParser.load(locale: widget.locale).then((value) {
        if (!mounted) return;
        // Water isn't persisted on the entry itself (its own running
        // total already lives durably in WaterRepository), so recover
        // what this entry originally contributed by re-parsing its
        // saved text the same way it was computed the first time --
        // needed to reconcile the day's water total by the actual
        // change, not the edited entry's new total on its own.
        final oldParsed = value.parse(extractMealContext(widget.entry.name).$3);
        final oldWater = oldParsed.items
            .where((item) => item.canonicalId == 'water')
            .fold(0.0, (sum, item) => sum + (item.grams ?? 0));
        setState(() {
          foodParser = value;
          _oldWaterMl = oldWater;
        });
      });
    }
  }

  @override
  void dispose() {
    weightGrams.removeListener(_rescaleFromWeight);
    description.dispose();
    calories.dispose();
    protein.dispose();
    carbs.dispose();
    weightGrams.dispose();
    fat.dispose();
    saturatedFat.dispose();
    sugar.dispose();
    fibre.dispose();
    salt.dispose();
    super.dispose();
  }

  // Every other number field is scaled proportionally the moment "Meal
  // weight" changes, against the weight this entry's numbers already
  // corresponded to when the sheet opened -- so lowering 390g to 200g
  // halves calories/protein/carbs/fat/etc together instead of leaving
  // them stuck at the old total. Only possible once a weight was already
  // recorded (e.g. from a scanned label); a brand-new weight with nothing
  // to scale from is just saved as typed, same as before.
  void _rescaleFromWeight() {
    _macrosDirty = true;
    final baseline = widget.entry.weightGrams;
    final newWeight = _dbl(weightGrams);
    if (baseline == null ||
        baseline <= 0 ||
        newWeight == null ||
        newWeight <= 0) {
      return;
    }
    final factor = newWeight / baseline;
    setState(() {
      calories.text = (widget.entry.calories * factor).round().toString();
      protein.text = (widget.entry.protein * factor).round().toString();
      carbs.text = (widget.entry.carbs * factor).round().toString();
      if (widget.entry.fat != null) fat.text = _fmt(widget.entry.fat! * factor);
      if (widget.entry.saturatedFat != null) {
        saturatedFat.text = _fmt(widget.entry.saturatedFat! * factor);
      }
      if (widget.entry.sugar != null) {
        sugar.text = _fmt(widget.entry.sugar! * factor);
      }
      if (widget.entry.fibre != null) {
        fibre.text = _fmt(widget.entry.fibre! * factor);
      }
      if (widget.entry.salt != null) {
        salt.text = _fmt(widget.entry.salt! * factor);
      }
    });
  }

  static String _fmt(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  int? _int(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return v?.round();
  }

  double? _dbl(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  String _activityLabel(ExerciseParser p, String id) =>
      p.catalogue.entries.firstWhere((e) => e.id == id).canonical;

  Future<void> _save() async {
    final text = description.text.trim();
    if (text.isEmpty) return;
    setState(() => notice = null);

    if (widget.entry.isExercise) {
      final parser =
          exerciseParser ?? await ExerciseParser.load(locale: widget.locale);
      final result = parser.parse(text, bodyWeightKg: widget.bodyWeightKg);
      final calories = result.calorieEstimateKcal?.round();
      if (calories == null) {
        setState(() {
          notice = result.activityId == null
              ? (result.suggestions.isNotEmpty
                    ? 'Did you mean "${_activityLabel(parser, result.suggestions.first)}"?'
                    : 'We don\'t recognize "$text" yet, so we can\'t estimate calories for it.')
              : result.durationMinutes == null
              ? 'How long did you do this for? Try adding something like "30 min" or "2 hours".'
              : 'Add your weight in your profile to estimate calories for this activity.';
        });
        return;
      }
      if (!mounted) return;
      final durationLabel = result.durationMinutes == null
          ? ''
          : result.durationMinutes! >= 60 && result.durationMinutes! % 60 == 0
          ? ' · ${(result.durationMinutes! / 60).round()} hr'
          : ' · ${result.durationMinutes!.round()} min';
      final existing = _parseEntryTime(widget.entry.time);
      Navigator.pop(
        context,
        EditEntryResult(
          entry: FoodEntry(
            text,
            '${existing == null ? _clockTime() : _clockTime(DateTime(2000, 1, 1, existing.hour, existing.minute))}$durationLabel',
            calories,
            0,
            Icons.directions_run,
            isExercise: true,
            exerciseActivityId: result.activityId,
            exerciseDurationMinutes: result.durationMinutes,
            exerciseMet: result.met,
            exerciseBodyWeightKg: widget.bodyWeightKg,
            exerciseApproximate: result.approximate,
          ),
        ),
      );
      return;
    }

    final parser = foodParser ?? await FoodParser.load(locale: widget.locale);
    final (explicitCategory, explicitTime, textToParse) = extractMealContext(
      text,
    );
    final result = parser.parse(textToParse);
    // Once the user has directly touched any number field, that's always
    // trusted over a fresh re-parse -- even if the (unchanged) text still
    // happens to fully resolve against the dataset -- so a manual
    // correction never gets silently discarded on save.
    final resolved = !_macrosDirty && _isFullyResolvedFood(result);
    if (!resolved) {
      final manualCalories = _int(calories);
      if (manualCalories == null || manualCalories < 0) {
        setState(
          () => notice =
              '${_describeIncompleteFood(result)} Enter the calories directly below to save it anyway.',
        );
        return;
      }
    }
    if (!mounted) return;

    // A description the local dataset fully understands (e.g. "3 eggs and
    // toast") gets its numbers recalculated from that -- most accurate,
    // and keeps quantity edits ("2 eggs" -> "3 eggs") working. Anything
    // else (a home-cooked dish worded in a way no dataset could ever
    // fully cover) falls back to whatever is typed in the number fields
    // below, so editing the text never gets blocked by the dataset check.
    final estimate = resolved
        ? _sumFoodParseResult(result)
        : FoodEstimate(
            _int(calories) ?? widget.entry.calories,
            _int(protein) ?? widget.entry.protein,
            _int(carbs) ?? widget.entry.carbs,
          );
    // Weight and fat/fibre come from the dataset when it was able to
    // resolve the food and actually has that column; otherwise (or for
    // sugar/salt/saturated fat, which the dataset never has at all) keep
    // whatever is in the field -- typically the entry's original value,
    // a scanned label's real number, or a manual correction.
    final finalWeightGrams = resolved
        ? (estimate.weightGrams ?? _dbl(weightGrams))
        : (_dbl(weightGrams) ?? widget.entry.weightGrams);
    final finalFat = resolved
        ? (estimate.fat?.toDouble() ?? _dbl(fat))
        : (_dbl(fat) ?? widget.entry.fat);
    final finalFibre = resolved
        ? (estimate.fibre?.toDouble() ?? _dbl(fibre))
        : (_dbl(fibre) ?? widget.entry.fibre);
    final finalSaturatedFat = _dbl(saturatedFat) ?? widget.entry.saturatedFat;
    final finalSugar = _dbl(sugar) ?? widget.entry.sugar;
    final finalSalt = _dbl(salt) ?? widget.entry.salt;
    final newWaterMl = resolved
        ? result.items
              .where((item) => item.canonicalId == 'water')
              .fold(0.0, (sum, item) => sum + (item.grams ?? 0))
        : _oldWaterMl;
    final category =
        explicitCategory ??
        (resolved &&
                result.items.isNotEmpty &&
                result.items.every((item) => item.category == 'drink')
            ? 'Drinks'
            : (widget.entry.category ?? 'Meal'));
    // A retyped explicit time always wins; otherwise this edit keeps the
    // entry's existing time rather than silently jumping it to now.
    final effectiveTime = explicitTime ?? _parseEntryTime(widget.entry.time);
    final entryTime = effectiveTime == null
        ? DateTime.now()
        : DateTime(2000, 1, 1, effectiveTime.hour, effectiveTime.minute);

    Navigator.pop(
      context,
      EditEntryResult(
        entry: FoodEntry(
          text,
          _clockTime(entryTime),
          estimate.calories,
          estimate.protein,
          Icons.restaurant,
          carbs: estimate.carbs,
          waterMl: newWaterMl.round(),
          category: category,
          weightGrams: finalWeightGrams,
          fat: finalFat,
          saturatedFat: finalSaturatedFat,
          sugar: finalSugar,
          fibre: finalFibre,
          salt: finalSalt,
        ),
        waterDeltaMl: (newWaterMl - _oldWaterMl).round(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(20, 18, 20, sheetBottomInset(context, 24)),
    decoration: const BoxDecoration(
      color: cream,
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LText(
            'Edit entry',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.entry.dayCategory} · ${widget.entry.time}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: description,
            minLines: 1,
            maxLines: 4,
            autofocus: true,
          ),
          if (!widget.entry.isExercise) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: calories,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _markDirty(),
                    decoration: InputDecoration(
                      labelText: ui(context, 'Calories'),
                      suffixText: 'kcal',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: protein,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _markDirty(),
                    decoration: InputDecoration(
                      labelText: ui(context, 'Protein'),
                      suffixText: 'g',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: carbs,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _markDirty(),
                    decoration: InputDecoration(
                      labelText: ui(context, 'Carbs'),
                      suffixText: 'g',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: weightGrams,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: ui(context, 'Meal weight'),
                suffixText: 'g',
              ),
            ),
            const SizedBox(height: 14),
            const LText(
              'Optional',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: fat,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _markDirty(),
                    decoration: InputDecoration(
                      labelText: ui(context, 'Fat'),
                      suffixText: 'g',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: saturatedFat,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _markDirty(),
                    decoration: InputDecoration(
                      labelText: ui(context, 'Saturated fat'),
                      suffixText: 'g',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: sugar,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _markDirty(),
                    decoration: InputDecoration(
                      labelText: ui(context, 'Sugar'),
                      suffixText: 'g',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: fibre,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _markDirty(),
                    decoration: InputDecoration(
                      labelText: ui(context, 'Fibre'),
                      suffixText: 'g',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: salt,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _markDirty(),
                    decoration: InputDecoration(
                      labelText: ui(context, 'Salt'),
                      suffixText: 'g',
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (notice != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE5DD),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: coral, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LText(
                      notice!,
                      style: const TextStyle(fontSize: 12, color: ink),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => Navigator.pop(
                          context,
                          const EditEntryResult(delete: true),
                        ),
                  icon: const Icon(Icons.delete_outline, color: coral),
                  label: const LText('Delete', style: TextStyle(color: coral)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : () => _save(),
                  icon: const Icon(Icons.check),
                  label: const LText('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

bool _isFullyResolvedFood(FoodParseResult result) =>
    result.items.isNotEmpty &&
    result.unresolved.isEmpty &&
    result.items.every((item) => item.confidence != ParseConfidence.incomplete);

FoodEstimate _sumFoodParseResult(FoodParseResult result) {
  var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0, fibre = 0.0;
  var hasFat = false, hasFibre = false;
  var grams = 0.0;
  var hasGrams = false;
  for (final item in result.items) {
    if (item.grams != null) {
      grams += item.grams!;
      hasGrams = true;
    }
    final nutrition = item.nutrition;
    if (nutrition == null) continue;
    kcal += nutrition.kcal;
    protein += nutrition.proteinG;
    carbs += nutrition.carbsG;
    if (nutrition.fatG != null) {
      fat += nutrition.fatG!;
      hasFat = true;
    }
    if (nutrition.fibreG != null) {
      fibre += nutrition.fibreG!;
      hasFibre = true;
    }
  }
  return FoodEstimate(
    kcal.round(),
    protein.round(),
    carbs.round(),
    fat: hasFat ? fat.round() : null,
    fibre: hasFibre ? fibre.round() : null,
    weightGrams: hasGrams ? grams : null,
  );
}

// Natural "X, Y and Z" phrasing for a short list of names.
String _naturalJoin(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  if (items.length == 2) return '${items[0]} and ${items[1]}';
  return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

// User-facing: short and non-technical. Never lists items that were
// already understood (that's just noise to the user); clearly flags what
// still needs attention (the exact silent-drop bug this migration started
// from) without exposing internal terms like canonical id/confidence/
// parser. Full diagnostics stay in debug logging (see the kDebugMode
// block in _addToDay) and tests.
String _describeIncompleteFood(FoodParseResult result) {
  final noNutrientData = result.items
      .where((item) => item.confidence == ParseConfidence.incomplete)
      .map((item) => item.canonicalName ?? item.canonicalId ?? '?')
      .toList();
  final notUnderstood = result.unresolved.map((u) => u.text).toList();

  final parts = <String>[];
  if (noNutrientData.isNotEmpty) {
    parts.add(
      "I don't have nutrition data for ${_naturalJoin(noNutrientData)} yet.",
    );
  }
  if (notUnderstood.isNotEmpty) {
    parts.add('Please clarify: ${_naturalJoin(notUnderstood)}.');
  }
  if (parts.isEmpty) {
    return 'Not enough nutrition information. Add quantities or scan the product label.';
  }
  return parts.join(' ');
}

class AddMealSheet extends StatefulWidget {
  const AddMealSheet({super.key, this.locale = 'en', required this.entries});
  final String locale;
  // Today's existing entries, so "Take photo" can offer attaching to one
  // of them instead of always creating something new.
  final List<FoodEntry> entries;
  @override
  State<AddMealSheet> createState() => _AddMealSheetState();
}

class _AddMealSheetState extends State<AddMealSheet> {
  final description = TextEditingController();
  final photoCaption = TextEditingController();
  int mode = 0;
  bool aiAvailable = false;
  bool busy = false;
  String? notice;
  FoodParser? foodParser;
  // Take-photo state (item 8): a photo was picked but not yet resolved
  // into either "attach to an existing entry" or "standalone". Never
  // requires a description, calories or a successful FoodParser result.
  XFile? takenPhoto;
  bool choosingAttachEntry = false;
  bool savingPhoto = false;

  @override
  void initState() {
    super.initState();
    const AiService().isAvailable().then((value) {
      if (mounted) setState(() => aiAvailable = value);
    });
    FoodParser.load(locale: widget.locale).then((value) {
      if (mounted) setState(() => foodParser = value);
    });
    description.addListener(() {
      if (notice != null) setState(() => notice = null);
    });
  }

  @override
  void dispose() {
    description.dispose();
    photoCaption.dispose();
    super.dispose();
  }

  Future<XFile?> _pickPhoto() async {
    try {
      final fromCamera = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      if (fromCamera != null) return fromCamera;
    } catch (_) {
      // No usable camera (common on emulators/desktops) — fall back below.
    }
    try {
      return await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
    } catch (_) {
      return null;
    }
  }

  Future<LabelReading?> _readLabel(XFile photo) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );
      return LabelParser.parse(result.text);
    } catch (_) {
      return null;
    } finally {
      recognizer.close();
    }
  }

  // "Take photo" (mode 1) never analyses the image at all -- it's just
  // evidence/memory (item 8/11), resolved below into attach-to-entry or
  // standalone. "Scan label" (mode 2) is structured nutrition-table
  // extraction (item 4/10), completely separate from FoodParser, and
  // ALWAYS ends in an editable confirmation sheet rather than guessing.
  Future<void> _capture(int newMode) async {
    setState(() {
      mode = newMode;
      notice = null;
    });
    final photo = await _pickPhoto();
    if (!mounted) return;
    if (photo == null) {
      setState(() => mode = 0);
      return;
    }
    if (newMode == 1) {
      setState(() => takenPhoto = photo);
      return;
    }
    setState(() => busy = true);
    final reading = await _readLabel(photo);
    if (!mounted) return;
    setState(() {
      busy = false;
      mode = 0;
    });
    final confirmed = await showModalBottomSheet<AddFoodResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddFoodSheet(
        title: 'Confirm scanned label',
        suggestedName: reading?.productName ?? '',
        initialCalories: reading?.caloriesPer100,
        initialProtein: reading?.proteinPer100,
        initialCarbs: reading?.carbsPer100,
        initialFat: reading?.fatPer100,
        initialSaturatedFat: reading?.saturatedFatPer100,
        initialSugar: reading?.sugarsPer100,
        initialFibre: reading?.fibrePer100,
        initialSalt: reading?.saltPer100,
        initialServingAmount: reading?.basis == 'perServing'
            ? (reading?.servingSizeGrams ?? 100)
            : 100,
        initialServingUnit: reading?.basis == 'per100ml' ? 'ml' : 'g',
        defaultSaveToCatalogue: false,
        showPackWeightField: true,
        initialPackWeightGrams: reading?.totalGrams,
        locale: widget.locale,
      ),
    );
    if (confirmed == null || !mounted) return;
    Navigator.pop(
      context,
      FoodEntry(
        confirmed.name,
        _clockTime(),
        confirmed.kcal.round(),
        (confirmed.protein ?? 0).round(),
        Icons.restaurant,
        carbs: (confirmed.carbs ?? 0).round(),
        weightGrams: confirmed.weightGrams,
        fat: confirmed.fat,
        saturatedFat: confirmed.saturatedFat,
        sugar: confirmed.sugar,
        fibre: confirmed.fibre,
        salt: confirmed.salt,
      ),
    );
  }

  Future<void> _finishStandalonePhoto() async {
    if (takenPhoto == null || savingPhoto) return;
    setState(() => savingPhoto = true);
    final path = await const PhotoStore().save(takenPhoto!);
    await const DayPhotoRepository().add(
      DateTime.now(),
      DayPhoto(
        path: path,
        caption: photoCaption.text.trim().isEmpty
            ? null
            : photoCaption.text.trim(),
        time: _clockTime(),
      ),
    );
    if (mounted) Navigator.pop(context, const DayPhotoSaved());
  }

  Future<void> _finishAttachPhoto(FoodEntry target) async {
    if (takenPhoto == null || savingPhoto) return;
    setState(() => savingPhoto = true);
    final path = await const PhotoStore().save(takenPhoto!);
    if (!mounted) return;
    Navigator.pop(
      context,
      PhotoAttachOutcome(original: target, updated: target.copyWithPhoto(path)),
    );
  }

  // Reconstructs a natural phrase for a locally-recognized-but-incomplete
  // item (e.g. "4 slice smoked salmon") so a component-level AI fallback
  // call gets the same context a person typed, not just the bare
  // canonical name.
  String _phraseForItem(FoodParseItem item) {
    final words = <String>[];
    if (item.quantity != 1) {
      final q = item.quantity;
      words.add(q == q.roundToDouble() ? q.toInt().toString() : q.toString());
    }
    if (item.unit != null) words.add(item.unit!);
    words.addAll(item.modifiers);
    words.addAll(item.preparations);
    final name = item.canonicalName ?? item.canonicalId;
    if (name != null) words.add(name);
    return words.join(' ');
  }

  // The first food this sheet's own local parser genuinely couldn't find
  // nutrition data for, or the first stretch of text it couldn't recognize
  // as food at all -- either way, the thing the "Add this food" offer
  // should suggest a name for. Recomputed on demand (not cached) so it
  // always reflects the current description text.
  String? _unresolvedFoodName() {
    final parser = foodParser;
    final text = description.text.trim();
    if (parser == null || text.isEmpty) return null;
    final (_, _, textToParse) = extractMealContext(text);
    final result = parser.parse(textToParse);
    final incomplete = result.items.firstWhere(
      (item) => item.confidence == ParseConfidence.incomplete,
      orElse: () => const FoodParseItem(
        quantity: 1,
        confidence: ParseConfidence.incomplete,
      ),
    );
    if (incomplete.canonicalName != null) return incomplete.canonicalName;
    if (incomplete.canonicalId != null) return incomplete.canonicalId;
    if (result.unresolved.isNotEmpty) return result.unresolved.first.text;
    return null;
  }

  Future<void> _offerAddFood(String suggestedName) async {
    final result = await showModalBottomSheet<AddFoodResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          AddFoodSheet(suggestedName: suggestedName, locale: widget.locale),
    );
    if (result != null && mounted) {
      // Reload so the parser picks up the food just added to the local
      // overlay (see FoodParser.load), then retry the same description.
      final reloaded = await FoodParser.load(locale: widget.locale);
      if (!mounted) return;
      setState(() {
        foodParser = reloaded;
        notice = null;
      });
      await _addToDay();
    }
  }

  // Writes an AI-resolved item local truly didn't know into the SAME
  // shared catalogue the manual "Add new food" sheet contributes to (see
  // CatalogueSyncService.contribute), on AI's own real servingGrams basis
  // -- never a guessed weight. Best-effort: a failure here just means this
  // one item stays AI-only a bit longer, never blocks logging the entry.
  Future<void> _contributeAiFood(NutritionEstimate aiResult) async {
    try {
      final overlay = await LocalCatalogueOverlay.load();
      await overlay.upsert(
        OverlayFoodEntry(
          id: OverlayFoodEntry.idFor(aiResult.name),
          canonical: aiResult.name,
          kcalPer100g: aiResult.calories * 100 / aiResult.servingGrams,
          proteinPer100g: aiResult.protein * 100 / aiResult.servingGrams,
          carbsPer100g: aiResult.carbs * 100 / aiResult.servingGrams,
          servingAmount: aiResult.servingGrams,
          servingUnit: 'g',
          source: 'ai',
        ),
      );
      await const CatalogueSyncService().contribute(
        defaultServerUrl,
        name: aiResult.name,
        kcal: aiResult.calories.toDouble(),
        protein: aiResult.protein.toDouble(),
        carbs: aiResult.carbs.toDouble(),
        servingAmount: aiResult.servingGrams,
        servingUnit: 'g',
        locale: widget.locale,
      );
    } catch (_) {
      // Offline or the server is unreachable -- stays AI-only for now.
    }
  }

  Future<void> _addToDay() async {
    final text = description.text.trim();
    final water = WaterIntakeParser.parse(text);
    if (water != null) {
      Navigator.pop(context, water);
      return;
    }
    // Local-first, component-level: resolve everything possible locally
    // first, and keep every successfully-resolved local component
    // untouched. AI is only ever asked about the specific parts local
    // could NOT resolve (an incomplete item or an unresolved span) --
    // never the whole sentence -- so a component local already understood
    // (e.g. local "egg" in "egg and dragonfruit powder") is never at risk
    // of being silently re-decided by AI just because a sibling component
    // failed. If AI's own answer for a component resolves locally too,
    // our deterministic catalogue numbers stay authoritative over AI's.
    final localParser =
        foodParser ?? await FoodParser.load(locale: widget.locale);
    // An explicit meal word ("lunch", "obiad", ...) or time ("10am",
    // "13:30", "o 14") is a category/time choice, not food content --
    // pull both out (and whatever "for "/":" joined them to the rest of
    // the sentence) before parsing, so neither can surface as an
    // unresolved fragment, and remember what they named.
    final (explicitCategory, explicitTime, textToParse) = extractMealContext(
      text,
    );
    final localResult = localParser.parse(textToParse);
    final canCallAi = aiAvailable && text.isNotEmpty;
    final needsAi =
        canCallAi &&
        (localResult.items.any(
              (item) => item.confidence == ParseConfidence.incomplete,
            ) ||
            localResult.unresolved.isNotEmpty);

    Future<List<FoodParseItem>?> aiResolveComponent(String phrase) async {
      if (!canCallAi || phrase.trim().isEmpty) return null;
      try {
        final aiResult = await const AiService().describe(
          serverUrl: defaultServerUrl,
          kind: 'food',
          text: phrase,
        );
        final reResolved = localParser.parse(aiResult.name);
        if (_isFullyResolvedFood(reResolved)) return reResolved.items;
        // Local truly has no entry for this one (re-parsing AI's own
        // canonical name still didn't resolve it) -- teach the global
        // catalogue about it now, using AI's own servingGrams so the
        // per-100g figures are real, not a guessed weight. Every other
        // phone picks this up next time CatalogueSyncService.sync() runs,
        // the same path the manual "Add new food" entry uses.
        if (aiResult.servingGrams > 0) {
          unawaited(_contributeAiFood(aiResult));
        }
        return [
          FoodParseItem(
            quantity: 1,
            canonicalName: aiResult.name,
            nutrition: NutrientTotals(
              kcal: aiResult.calories.toDouble(),
              proteinG: aiResult.protein.toDouble(),
              carbsG: aiResult.carbs.toDouble(),
            ),
            confidence: ParseConfidence.medium,
          ),
        ];
      } catch (_) {
        return null;
      }
    }

    if (needsAi) setState(() => busy = true);
    final items = <FoodParseItem>[];
    final unresolvedTexts = <String>[];
    try {
      // Every incomplete item/unresolved span local couldn't handle is
      // independent of every other one, so their AI calls run concurrently
      // (Future.wait) rather than one after another -- a sentence with two
      // unrecognized dishes previously meant two AI round trips back to
      // back, doubling the wait for no reason.
      final itemResolutions = await Future.wait(
        localResult.items.map(
          (item) => item.confidence == ParseConfidence.incomplete
              ? aiResolveComponent(_phraseForItem(item))
              : Future<List<FoodParseItem>?>.value(null),
        ),
      );
      for (var i = 0; i < localResult.items.length; i++) {
        final item = localResult.items[i];
        if (item.confidence != ParseConfidence.incomplete) {
          items.add(item);
        } else if (itemResolutions[i] != null) {
          items.addAll(itemResolutions[i]!);
        } else {
          items.add(item);
        }
      }
      final spanResolutions = await Future.wait(
        localResult.unresolved.map((span) => aiResolveComponent(span.text)),
      );
      for (var i = 0; i < localResult.unresolved.length; i++) {
        final resolved = spanResolutions[i];
        if (resolved != null) {
          items.addAll(resolved);
        } else {
          unresolvedTexts.add(localResult.unresolved[i].text);
        }
      }
    } finally {
      if (needsAi && mounted) setState(() => busy = false);
    }
    if (!mounted) return;

    // Combine only once every component has a usable result: if anything
    // is still stuck, this stays reflected below rather than silently
    // dropped -- _isFullyResolvedFood blocks saving until it's resolved.
    final result = FoodParseResult(items, [
      for (final t in unresolvedTexts) UnresolvedSpan(t, 0, t.length),
    ]);

    // FoodEstimator is kept only as a transitional comparison signal --
    // never as the saved result, even if AI is unavailable or fails.
    if (kDebugMode) {
      final legacy = FoodEstimator.estimate(text);
      final current = _sumFoodParseResult(result);
      if (legacy.calories != current.calories) {
        debugPrint(
          '[FoodParser migration] "$text" -> FoodParser=${current.calories}kcal '
          '(resolved=${_isFullyResolvedFood(result)}) vs legacy FoodEstimator='
          '${legacy.calories}kcal (legacy not used)',
        );
      }
    }

    if (!_isFullyResolvedFood(result)) {
      setState(() => notice = _describeIncompleteFood(result));
      return;
    }
    if (!mounted) return;

    final estimate = _sumFoodParseResult(result);
    // Water recognized as one component of a wider sentence ("glass water"
    // inside a longer meal) doesn't go through WaterIntakeParser (that only
    // matches a description that's *entirely* about water) -- so it must
    // also be counted here, using the same grams-as-ml the parser already
    // computed (e.g. "half glass water" -> 125ml), or it silently never
    // reaches the day's water total.
    final waterMl = result.items
        .where((item) => item.canonicalId == 'water')
        .fold(0.0, (sum, item) => sum + (item.grams ?? 0));
    // An explicit meal word always wins. Otherwise: every resolved item
    // being a drink is a drink-only entry ("black coffee" alone); any mix
    // of food (with or without a drink alongside it, e.g. water/coffee
    // inside a bigger meal) is just "Meal" -- never falls back to
    // "Drinks" purely because a drink happened to be one of several
    // components.
    final category =
        explicitCategory ??
        (result.items.isNotEmpty &&
                result.items.every((item) => item.category == 'drink')
            ? 'Drinks'
            : 'Meal');
    // An explicit time ("10am", "13:30", "o 14") becomes the entry's own
    // time instead of "now" -- today's date, that clock time.
    final now = DateTime.now();
    final entryTime = explicitTime == null
        ? now
        : DateTime(
            now.year,
            now.month,
            now.day,
            explicitTime.hour,
            explicitTime.minute,
          );
    Navigator.pop(
      context,
      FoodEntry(
        text,
        _clockTime(entryTime),
        estimate.calories,
        estimate.protein,
        Icons.restaurant,
        carbs: estimate.carbs,
        waterMl: waterMl.round(),
        category: category,
        weightGrams: estimate.weightGrams,
        fat: estimate.fat?.toDouble(),
        fibre: estimate.fibre?.toDouble(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(20, 12, 20, sheetBottomInset(context, 24)),
    decoration: const BoxDecoration(
      color: cream,
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const LText(
            'What did you eat or drink?',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          const LText(
            'A rough description is plenty. You can adjust it later.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: CaptureChoice(
                  Icons.camera_alt_outlined,
                  'Take photo',
                  mode == 1,
                  busy ? null : () => _capture(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CaptureChoice(
                  Icons.document_scanner_outlined,
                  'Scan label',
                  mode == 2,
                  busy ? null : () => _capture(2),
                ),
              ),
            ],
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  LText(
                    'Analysing your photo…',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          if (mode == 1 && takenPhoto != null)
            _buildPhotoResolutionSection(context)
          else ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: LText(
                      'or describe it',
                      style: TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
            ),
            TextField(
              controller: description,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: ui(
                  context,
                  'e.g. 2 spoons cottage cheese, a can of cola, a bag of crisps, glass of wine…',
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: forest),
                SizedBox(width: 7),
                Expanded(
                  child: LText(
                    'AI estimates include a confidence range—never fake precision.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
              ],
            ),
            if (notice != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE5DD),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: coral, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LText(
                            notice!,
                            style: const TextStyle(fontSize: 12, color: ink),
                          ),
                        ),
                      ],
                    ),
                    if (_unresolvedFoodName() != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () =>
                              _offerAddFood(_unresolvedFoodName()!),
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const LText('Add this food'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: ink,
                  padding: const EdgeInsets.all(17),
                ),
                onPressed: busy ? null : () => _addToDay(),
                icon: const Icon(Icons.auto_awesome),
                label: const LText(
                  'Add to day',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  // "Take photo" (item 8): a photo with no description/calorie requirement
  // at all -- just attach it to something today, or keep it on its own.
  Widget _buildPhotoResolutionSection(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          File(takenPhoto!.path),
          height: 160,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      ),
      const SizedBox(height: 14),
      if (!choosingAttachEntry) ...[
        TextField(
          controller: photoCaption,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: ui(context, 'Caption'),
            hintText: ui(context, 'e.g. breakfast, pizza, meal with Ania…'),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.entries.isEmpty || savingPhoto
                ? null
                : () => setState(() => choosingAttachEntry = true),
            icon: const Icon(Icons.link),
            label: const LText('Attach to existing entry'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: savingPhoto ? null : _finishStandalonePhoto,
            icon: savingPhoto
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_library_outlined),
            label: const LText('Keep as standalone photo'),
          ),
        ),
      ] else ...[
        const LText(
          'Attach to which entry?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final entry in widget.entries) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(entry.displayIcon, color: forest),
            title: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('${entry.dayCategory} · ${entry.time}'),
            onTap: savingPhoto ? null : () => _finishAttachPhoto(entry),
          ),
          const Divider(height: 1),
        ],
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => setState(() => choosingAttachEntry = false),
          child: const LText('Back'),
        ),
      ],
    ],
  );
}

String _clockTime([DateTime? value]) {
  final time = value ?? DateTime.now();
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

double sheetBottomInset(BuildContext context, double extra) =>
    MediaQuery.viewInsetsOf(context).bottom +
    MediaQuery.viewPaddingOf(context).bottom +
    extra;

class CaptureChoice extends StatelessWidget {
  const CaptureChoice(
    this.icon,
    this.label,
    this.selected,
    this.onTap, {
    super.key,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: selected ? mint : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? forest : Colors.transparent),
      ),
      child: Column(
        children: [
          Icon(icon, color: forest, size: 29),
          const SizedBox(height: 7),
          LText(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );
}

class HistoryRecord {
  factory HistoryRecord.fromFoodEntry(FoodEntry e, DateTime day) {
    final parts = e.time.split(RegExp(r'[:\s]')).take(2).toList();
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    final category = e.dayCategory;
    final kind = e.isExercise
        ? 'activity'
        : category == 'Drinks'
        ? 'drink'
        : category == 'Snack'
        ? 'snack'
        : 'meal';
    return HistoryRecord.fromJson({
      'id': 'today_${day.toIso8601String()}_${e.name.hashCode}_${e.time}',
      'at': DateTime(
        day.year,
        day.month,
        day.day,
        hour,
        minute,
      ).toIso8601String(),
      'kind': kind,
      'title': e.name,
      'detail': '',
      'kcal': e.calories,
      'evidence': '',
    });
  }

  HistoryRecord.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      at = DateTime.parse(j['at']),
      kind = j['kind'],
      title = j['title'],
      detail = j['detail'] ?? j['kcal_note'] ?? '',
      kcal = (j['kcal'] as num?)?.toDouble(),
      kcalMin = (j['kcal_min'] as num?)?.toDouble(),
      kcalMax = (j['kcal_max'] as num?)?.toDouble(),
      weight = (j['weight'] as num?)?.toDouble(),
      images = ((j['images'] as List?) ?? const []).cast<String>(),
      evidence = j['evidence'];
  final String id, kind, title, detail, evidence;
  final DateTime at;
  final double? kcal, kcalMin, kcalMax, weight;
  final List<String> images;
  String get dayCategory => kind == 'activity'
      ? 'Exercise'
      : kind == 'measurement'
      ? 'Other'
      : MealCategory.detect('$title $detail', false);
  IconData get icon => kind == 'activity'
      ? Icons.directions_run
      : kind == 'measurement'
      ? Icons.monitor_weight_outlined
      : kind == 'drink'
      ? Icons.local_bar_outlined
      : kind == 'snack'
      ? Icons.cookie_outlined
      : Icons.restaurant;
}

String shortDate(DateTime d) =>
    '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';

String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour < 5) return 'Good night';
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  if (hour < 21) return 'Good evening';
  return 'Good night';
}

String fullDate(DateTime d) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

String recordDetail(HistoryRecord r) {
  final bits = <String>[];
  if (r.weight != null) bits.add('${r.weight!.toStringAsFixed(1)} kg');
  if (r.kcal != null) {
    bits.add('${r.kcal!.round()} kcal');
  } else if (r.kcalMin != null) {
    bits.add('${r.kcalMin!.round()}–${r.kcalMax!.round()} kcal');
  }
  final detail = r.detail
      .replaceAll(RegExp(r'\s*also reported\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bestimated?\b\s*', caseSensitive: false), '')
      .trim();
  if (detail.isNotEmpty) bits.add(detail);
  return bits.join(' · ');
}

class ProgressPage extends StatefulWidget {
  const ProgressPage({
    super.key,
    required this.importedCount,
    required this.history,
  });
  final int importedCount;
  final List<HistoryRecord> history;
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  int view = 1;
  DateTime? anchor;
  DateTime get selected =>
      anchor ??
      (widget.history.isEmpty ? DateTime.now() : widget.history.first.at);
  DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime get start {
    final d = dayOnly(selected);
    if (view == 0) return d;
    if (view == 1) return d.subtract(Duration(days: d.weekday - 1));
    return DateTime(d.year, d.month);
  }

  DateTime get end => view == 0
      ? start.add(const Duration(days: 1))
      : view == 1
      ? start.add(const Duration(days: 7))
      : DateTime(start.year, start.month + 1);
  List<HistoryRecord> get visible => widget.history
      .where((r) => !r.at.isBefore(start) && r.at.isBefore(end))
      .toList();
  void move(int direction) {
    setState(() {
      anchor = view == 0
          ? selected.add(Duration(days: direction))
          : view == 1
          ? selected.add(Duration(days: 7 * direction))
          : DateTime(selected.year, selected.month + direction, 1);
    });
  }

  String get periodLabel => view == 0
      ? '${shortDate(start)} ${start.year}'
      : view == 1
      ? '${shortDate(start)} – ${shortDate(end.subtract(const Duration(days: 1)))}'
      : '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][start.month - 1]} ${start.year}';

  @override
  Widget build(BuildContext context) {
    final foods = visible
        .where((r) => ['meal', 'snack', 'drink'].contains(r.kind))
        .toList();
    final known = foods
        .where((r) => r.kcal != null || r.kcalMin != null)
        .toList();
    final total = known.fold<double>(
      0,
      (s, r) => s + (r.kcal ?? ((r.kcalMin! + r.kcalMax!) / 2)),
    );
    final days = <DateTime, List<HistoryRecord>>{};
    for (final r in visible) {
      (days[dayOnly(r.at)] ??= []).add(r);
    }
    final orderedDays = days.keys.toList()..sort((a, b) => b.compareTo(a));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        const TopBar('Your progress', 'Explore your real history'),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: LText('Day')),
              ButtonSegment(value: 1, label: LText('Week')),
              ButtonSegment(value: 2, label: LText('Month')),
            ],
            selected: {view},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() {
              view = v.first;
              anchor = selected;
            }),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: () => move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: LText(
                periodLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton.filledTonal(
              onPressed: () => move(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  const Icon(
                    Icons.event_busy_outlined,
                    size: 42,
                    color: forest,
                  ),
                  const SizedBox(height: 12),
                  const LText(
                    'No records for this period',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  LText(
                    'This is intentionally blank—nothing was reported in the conversation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: .55),
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: LText(
                          'Recorded energy',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: mint,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: LText(
                          '${known.length}/${foods.length} valued',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: forest,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  LText(
                    known.isEmpty
                        ? 'No calorie values reported'
                        : '${total.round()} kcal across valued entries',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 178,
                    child: HistoryBars(
                      records: visible,
                      start: start,
                      end: end,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const LText(
                    'Bars show recorded intake only—not complete daily totals unless every meal was logged.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black45,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  '${foods.length}',
                  'food & drink',
                  Icons.restaurant_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  '${visible.where((r) => r.kind == 'activity').length}',
                  'activities',
                  Icons.directions_run,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SectionHeader(
            view == 0 ? 'Entries' : 'Recorded days',
            '${visible.length} RECORDS',
          ),
          const SizedBox(height: 8),
          ...orderedDays.map((d) => DayPreview(date: d, records: days[d]!)),
        ],
      ],
    );
  }
}

class HistoryBars extends StatelessWidget {
  const HistoryBars({
    super.key,
    required this.records,
    required this.start,
    required this.end,
  });
  final List<HistoryRecord> records;
  final DateTime start, end;

  static const foodColor = forest;
  static const drinkColor = aqua;
  static const exerciseColor = gold;

  @override
  Widget build(BuildContext context) {
    final count = end.difference(start).inDays;
    final food = List<double>.filled(count, 0);
    final drink = List<double>.filled(count, 0);
    final exercise = List<double>.filled(count, 0);
    for (final r in records) {
      final i = DateTime(
        r.at.year,
        r.at.month,
        r.at.day,
      ).difference(start).inDays;
      if (i < 0 || i >= count) continue;
      final kcal =
          r.kcal ?? (r.kcalMin != null ? (r.kcalMin! + r.kcalMax!) / 2 : 0);
      if (r.kind == 'drink') {
        drink[i] += kcal;
      } else if (r.kind == 'activity') {
        exercise[i] += kcal;
      } else if (r.kind == 'meal' || r.kind == 'snack') {
        food[i] += kcal;
      }
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(
              count,
              (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: count > 10 ? 1 : 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (_, box) {
                            final total = food[i] + drink[i] + exercise[i];
                            if (total == 0) {
                              return Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: Colors.black12,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              );
                            }
                            final scale =
                                box.maxHeight *
                                (total / 2800).clamp(0.05, 1) /
                                total;
                            Widget segment(double v, Color color) => Container(
                              height: math.max(0, v * scale),
                              color: color,
                            );
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (exercise[i] > 0)
                                    segment(exercise[i], exerciseColor),
                                  if (drink[i] > 0)
                                    segment(drink[i], drinkColor),
                                  if (food[i] > 0) segment(food[i], foodColor),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (count <= 7)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: LText(
                            '${start.add(Duration(days: i)).day}',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          children: const [
            _BarLegendDot(color: foodColor, label: 'Food'),
            _BarLegendDot(color: drinkColor, label: 'Drink'),
            _BarLegendDot(color: exerciseColor, label: 'Exercise'),
          ],
        ),
      ],
    );
  }
}

class _BarLegendDot extends StatelessWidget {
  const _BarLegendDot({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      LText(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
    ],
  );
}

class DayPreview extends StatelessWidget {
  const DayPreview({super.key, required this.date, required this.records});
  final DateTime date;
  final List<HistoryRecord> records;
  @override
  Widget build(BuildContext context) {
    final food = records.where(
      (r) => ['meal', 'snack', 'drink'].contains(r.kind),
    );
    final valued = food.where((r) => r.kcal != null || r.kcalMin != null);
    final total = valued.fold<double>(
      0,
      (s, r) => s + (r.kcal ?? (r.kcalMin! + r.kcalMax!) / 2),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => DayDetailSheet(date: date, records: records),
          ),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: mint,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Center(
                    child: LText(
                      '${date.day}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: forest,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LText(
                        '${shortDate(date)} · ${records.length} records',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      LText(
                        valued.isEmpty
                            ? 'No calorie values'
                            : '${total.round()} recorded kcal · ${valued.length}/${food.length} valued',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DayDetailSheet extends StatelessWidget {
  const DayDetailSheet({super.key, required this.date, required this.records});
  final DateTime date;
  final List<HistoryRecord> records;
  List<HistoryRecord> get orderedRecords => [...records]
    ..sort((a, b) {
      final byCategory = MealCategory.order
          .indexOf(a.dayCategory)
          .compareTo(MealCategory.order.indexOf(b.dayCategory));
      return byCategory == 0 ? a.at.compareTo(b.at) : byCategory;
    });
  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .75,
    maxChildSize: .95,
    builder: (_, controller) => Material(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      color: cream,
      child: ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(20, 20, 20, sheetBottomInset(context, 20)),
        children: [
          Center(child: Container(width: 42, height: 4, color: Colors.black12)),
          const SizedBox(height: 20),
          LText(
            '${shortDate(date)} ${date.year}',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const LText(
            'Estimated values',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          ...orderedRecords.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  isThreeLine: r.detail.isNotEmpty,
                  leading: CircleAvatar(
                    backgroundColor: mint,
                    foregroundColor: forest,
                    child: Icon(r.icon),
                  ),
                  title: LText(
                    r.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: LText(recordDetail(r)),
                  trailing: r.images.isNotEmpty
                      ? const Icon(Icons.photo_outlined, color: forest)
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class LegacyProgressPage extends StatelessWidget {
  const LegacyProgressPage({
    super.key,
    required this.importedCount,
    required this.history,
  });
  final int importedCount;
  final List<HistoryRecord> history;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
    children: [
      const TopBar('Your progress', 'Imported history'),
      if (importedCount > 0) ...[
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: mint,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(Icons.history, color: forest),
              const SizedBox(width: 10),
              Expanded(
                child: LText(
                  '$importedCount historical records saved',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.check_circle, color: forest),
            ],
          ),
        ),
      ],
      const SizedBox(height: 18),
      if (history.isNotEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LText(
                  'What we actually know',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                LText(
                  '${shortDate(history.last.at)} – ${shortDate(history.first.at)}',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: LText(
                        '${history.where((e) => ['meal', 'snack', 'drink'].contains(e.kind)).length}\nfood & drink',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(
                      child: LText(
                        '${history.where((e) => e.kind == 'activity').length}\nactivities',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(
                      child: LText(
                        '${history.where((e) => e.kind == 'measurement').length}\nweights',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const LText(
                  'No daily average is shown because several days are incomplete. Missing days remain blank.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LText(
                'Recorded weights',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ...history
                  .where((e) => e.weight != null)
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          LText(shortDate(e.at)),
                          const Spacer(),
                          LText(
                            '${e.weight!.toStringAsFixed(1)} kg',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    ],
  );
}

class TrendPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final grid = Paint()..color = Colors.black.withValues(alpha: .07);
    for (var i = 0; i < 4; i++) {
      final y = s.height * i / 4;
      c.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    final v = [.68, .43, .58, .28, .52, .36, .46];
    final p = Path();
    for (var i = 0; i < v.length; i++) {
      final o = Offset(s.width * i / 6, s.height * v[i]);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    c.drawPath(
      p,
      Paint()
        ..color = forest
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < v.length; i++) {
      c.drawCircle(
        Offset(s.width * i / 6, s.height * v[i]),
        5,
        Paint()..color = forest,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StatTile extends StatelessWidget {
  const StatTile(this.value, this.label, this.icon, {super.key});
  final String value, label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: forest),
          const SizedBox(height: 13),
          LText(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          LText(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    ),
  );
}

class Award extends StatelessWidget {
  const Award(this.icon, this.color, this.label, {super.key});
  final IconData icon;
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .16),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 32),
      ),
      const SizedBox(height: 8),
      LText(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class JourneyPage extends StatelessWidget {
  const JourneyPage({super.key, required this.history});
  final List<HistoryRecord> history;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const TopBar('Your journey', 'Real imported history'),
      const SizedBox(height: 24),
      if (history.isEmpty) const Center(child: CircularProgressIndicator()),
      ...history.map(
        (r) => JourneyItem(
          shortDate(r.at),
          r.title,
          r.icon,
          r.kind == 'activity'
              ? coral
              : r.kind == 'measurement'
              ? gold
              : forest,
          detail: recordDetail(r),
          hasImage: r.images.isNotEmpty,
        ),
      ),
    ],
  );
}

class JourneyItem extends StatelessWidget {
  const JourneyItem(
    this.date,
    this.label,
    this.icon,
    this.color, {
    super.key,
    this.detail = '',
    this.hasImage = false,
  });
  final String date, label;
  final IconData icon;
  final Color color;
  final String detail;
  final bool hasImage;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          Container(width: 2, height: 45, color: Colors.black12),
        ],
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LText(
                date.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: forest,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              LText(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: LText(
                    detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      height: 1.35,
                    ),
                  ),
                ),
              if (hasImage)
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: Row(
                    children: [
                      Icon(Icons.photo_outlined, size: 14, color: forest),
                      SizedBox(width: 4),
                      LText(
                        'Original image referenced',
                        style: TextStyle(fontSize: 11, color: forest),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class BodyProfile {
  const BodyProfile({
    this.age,
    this.heightCm,
    this.weightKg,
    this.sex,
    this.activity = 'Lightly active',
  });
  final int? age;
  final double? heightCm, weightKg;
  final String? sex;
  final String activity;

  double? get restingCalories {
    if (age == null || heightCm == null || weightKg == null || sex == null) {
      return null;
    }
    return 10 * weightKg! +
        6.25 * heightCm! -
        5 * age! +
        (sex == 'Male' ? 5 : -161);
  }

  double? get maintenanceCalories {
    const factors = {
      'Mostly seated': 1.2,
      'Lightly active': 1.375,
      'Moderately active': 1.55,
      'Very active': 1.725,
    };
    return restingCalories == null
        ? null
        : restingCalories! * (factors[activity] ?? 1.375);
  }

  Map<String, Object?> toJson() => {
    'age': age,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'sex': sex,
    'activity': activity,
  };
  factory BodyProfile.fromJson(Map<String, dynamic> json) => BodyProfile(
    age: json['age'] as int?,
    heightCm: (json['heightCm'] as num?)?.toDouble(),
    weightKg: (json['weightKg'] as num?)?.toDouble(),
    sex: json['sex'] as String?,
    activity: json['activity'] as String? ?? 'Lightly active',
  );
}

int resolvedDailyTarget(
  BodyProfile body, {
  required int storedTarget,
  required bool customized,
}) => customized
    ? storedTarget
    : body.maintenanceCalories?.round() ?? storedTarget;

class DietPlan {
  const DietPlan({
    required this.name,
    required this.style,
    required this.target,
  });
  final String name, style;
  final int target;
  DietPlan copyWith({int? target, String? style}) => DietPlan(
    name: name,
    style: style ?? this.style,
    target: target ?? this.target,
  );
  Map<String, Object> toJson() => {
    'name': name,
    'style': style,
    'target': target,
  };
  factory DietPlan.fromJson(Map<String, dynamic> json) => DietPlan(
    name: json['name'] as String,
    style: json['style'] as String,
    target: json['target'] as int,
  );
}

class ContentUpdateService {
  const ContentUpdateService();

  Future<int> pull({
    required String serverUrl,
    required String deviceId,
  }) async {
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1/content')
        .replace(queryParameters: {'deviceId': deviceId});
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['schemaVersion'] != 1 || decoded['releases'] is! List) {
      throw const FormatException('Unsupported content response');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('published_content_cache', response.body);
    await prefs.setString(
      'content_last_checked',
      DateTime.now().toIso8601String(),
    );
    return (decoded['releases'] as List).length;
  }
}

const defaultServerUrl = String.fromEnvironment(
  'A2_SERVER_URL',
  defaultValue: 'http://100.105.169.100:8094',
);

// Set via --dart-define=A2_GOOGLE_CLIENT_ID=... at build time, once a Google
// Cloud OAuth client has been registered for this app (package name/SHA-1 on
// Android, bundle ID on iOS) -- that registration has to happen outside this
// codebase. The server needs the same client ID as GOOGLE_CLIENT_ID.
const googleClientId = String.fromEnvironment('A2_GOOGLE_CLIENT_ID');

class AccountService {
  const AccountService();

  Future<void> recordDeletedEntry(FoodEntry entry, DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final tombstone = jsonEncode({
      'dateKey': 'daily_entries_${date.year}-$month-$day',
      'entry': entry.toJson(),
    });
    final existing = prefs.getStringList('deleted_daily_entries') ?? [];
    await prefs.setStringList(
      'deleted_daily_entries',
      [
        ...existing.where((item) => item != tombstone),
        tombstone,
      ].reversed.take(500).toList().reversed.toList(),
    );
  }

  Future<Map<String, dynamic>> authenticate({
    required String serverUrl,
    required String email,
    required String password,
    required bool register,
    String name = '',
  }) async {
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .post(
          Uri.parse('$base/api/v1/auth/${register ? 'register' : 'login'}'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            if (register) 'name': name,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error'] ?? 'Account request failed');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account_token', body['token'] as String);
    await prefs.setString('account_user', jsonEncode(body['user']));
    if ((body['user'] as Map<String, dynamic>)['privateSync'] == true) {
      await synchronise(serverUrl);
    }
    return body['user'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> authenticateWithGoogle({
    required String serverUrl,
    required String idToken,
  }) async {
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .post(
          Uri.parse('$base/api/v1/auth/google'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'idToken': idToken}),
        )
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error'] ?? 'Google sign-in failed');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account_token', body['token'] as String);
    await prefs.setString('account_user', jsonEncode(body['user']));
    if ((body['user'] as Map<String, dynamic>)['privateSync'] == true) {
      await synchronise(serverUrl);
    }
    return body['user'] as Map<String, dynamic>;
  }

  Future<void> changePassword({
    required String serverUrl,
    required String currentPassword,
    required String newPassword,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) throw Exception('Sign in to change your password');
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .post(
          Uri.parse('$base/api/v1/auth/password'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'currentPassword': currentPassword,
            'newPassword': newPassword,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Could not change password');
    }
  }

  Future<bool> refreshAccount(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) return false;
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .get(
          Uri.parse('$base/api/v1/auth/me'),
          headers: {'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401) {
      await prefs.remove('account_token');
      await prefs.remove('account_user');
      return false;
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] ?? 'Account refresh failed');
    }
    final user = body['user'] as Map<String, dynamic>;
    if (user['blocked'] == true) {
      await prefs.remove('account_token');
      await prefs.remove('account_user');
      return false;
    }
    await prefs.setString('account_user', jsonEncode(user));
    return user['privateSync'] == true;
  }

  Future<Map<String, dynamic>> _localPayload() async {
    final prefs = await SharedPreferences.getInstance();
    final daily = <String, dynamic>{};
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith('daily_entries_'),
    )) {
      daily[key] = (prefs.getStringList(key) ?? const [])
          .map((raw) => jsonDecode(raw))
          .toList();
    }
    final dailyWater = <String, dynamic>{};
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith('daily_water_'),
    )) {
      dailyWater[key] = prefs.getInt(key);
    }
    final historyRaw =
        prefs.getString('personal_history_cache') ?? '{"records":[]}';
    return {
      'history': jsonDecode(historyRaw),
      'dailyEntries': daily,
      'dailyWater': dailyWater,
      'deletedDailyEntries':
          (prefs.getStringList('deleted_daily_entries') ?? const [])
              .map((raw) => jsonDecode(raw))
              .toList(),
      'settings': {
        'bodyProfile': prefs.getString('body_profile'),
        'activeDietPlan': prefs.getString('active_diet_plan'),
        'dailyTarget': prefs.getInt('daily_target'),
        'dailyTargetCustom': prefs.getBool('daily_target_custom'),
        'savedDietPlans': prefs.getStringList('saved_diet_plans'),
        'importedRecordIds': prefs.getStringList('imported_record_ids'),
        'importedRecords': prefs.getStringList('imported_records'),
        'lastImportSource': prefs.getString('last_import_source'),
        'lastImportedAt': prefs.getString('last_imported_at'),
        'language': prefs.getString('language'),
        'aiEnabled': prefs.getBool('ai_enabled'),
        'waterTargetMl': prefs.getInt('water_target_ml'),
      },
    };
  }

  // A CSV opens directly in Excel, Google Sheets, Numbers, LibreOffice --
  // there's no single "universal Excel format" without a heavy XLSX writer
  // dependency, and CSV is the format every one of those already reads
  // natively, so it covers "used globally" without that extra weight.
  Future<String> exportDataAsCsv() async {
    final payload = await _localPayload();
    final daily = payload['dailyEntries'] as Map<String, dynamic>;
    final rows = <List<String>>[
      [
        'Date',
        'Category',
        'Name',
        'Time',
        'Type',
        'Calories',
        'Protein (g)',
        'Carbs (g)',
      ],
    ];
    final dateKeys = daily.keys.toList()..sort();
    for (final key in dateKeys) {
      final date = key.replaceFirst('daily_entries_', '');
      final entries = daily[key] as List<dynamic>;
      for (final raw in entries) {
        final entry = raw as Map<String, dynamic>;
        rows.add([
          date,
          (entry['category'] as String?) ?? '',
          (entry['name'] as String?) ?? '',
          (entry['time'] as String?) ?? '',
          entry['isExercise'] == true ? 'Exercise' : 'Food',
          '${entry['calories'] ?? 0}',
          '${entry['protein'] ?? 0}',
          '${entry['carbs'] ?? 0}',
        ]);
      }
    }
    String csvField(String value) {
      final escaped = value.replaceAll('"', '""');
      return value.contains(RegExp('[",\n]')) ? '"$escaped"' : escaped;
    }

    return rows.map((row) => row.map(csvField).join(',')).join('\r\n');
  }

  Future<void> uploadLocalData(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    final userRaw = prefs.getString('account_user');
    if (token == null || userRaw == null) return;
    final user = jsonDecode(userRaw) as Map<String, dynamic>;
    if (user['privateSync'] != true) return;
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    try {
      await http
          .put(
            Uri.parse('$base/api/v1/auth/sync'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
            },
            body: jsonEncode({'payload': await _localPayload()}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Local saving remains reliable when the private server is unavailable.
    }
  }

  Future<void> synchronise(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) return;
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .get(
          Uri.parse('$base/api/v1/auth/sync'),
          headers: {'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] ?? 'Sync failed');
    }
    final saved = body['data'] as Map<String, dynamic>?;
    if (saved == null) {
      await uploadLocalData(serverUrl);
      return;
    }
    final payload = saved['payload'] as Map<String, dynamic>? ?? const {};
    if (payload['history'] != null) {
      await prefs.setString(
        'personal_history_cache',
        jsonEncode(payload['history']),
      );
    }
    final daily = payload['dailyEntries'] as Map<String, dynamic>? ?? const {};
    for (final entry in daily.entries) {
      await prefs.setStringList(
        entry.key,
        (entry.value as List).map((item) => jsonEncode(item)).toList(),
      );
    }
    final dailyWater =
        payload['dailyWater'] as Map<String, dynamic>? ?? const {};
    for (final entry in dailyWater.entries) {
      if (entry.value case final int ml) {
        await prefs.setInt(entry.key, ml);
      }
    }
    if (payload['deletedDailyEntries'] case final List value) {
      await prefs.setStringList(
        'deleted_daily_entries',
        value.map((item) => jsonEncode(item)).toList(),
      );
    }
    final settings = payload['settings'] as Map<String, dynamic>? ?? const {};
    if (settings['bodyProfile'] case final String value) {
      await prefs.setString('body_profile', value);
    }
    if (settings['activeDietPlan'] case final String value) {
      await prefs.setString('active_diet_plan', value);
    }
    if (settings['dailyTarget'] case final int value) {
      await prefs.setInt('daily_target', value);
    }
    if (settings['dailyTargetCustom'] case final bool value) {
      await prefs.setBool('daily_target_custom', value);
    }
    if (settings['savedDietPlans'] case final List value) {
      await prefs.setStringList(
        'saved_diet_plans',
        value.map((item) => item as String).toList(),
      );
    }
    if (settings['importedRecordIds'] case final List value) {
      await prefs.setStringList(
        'imported_record_ids',
        value.map((item) => item as String).toList(),
      );
    }
    if (settings['importedRecords'] case final List value) {
      await prefs.setStringList(
        'imported_records',
        value.map((item) => item as String).toList(),
      );
    }
    if (settings['lastImportSource'] case final String value) {
      await prefs.setString('last_import_source', value);
    }
    if (settings['lastImportedAt'] case final String value) {
      await prefs.setString('last_imported_at', value);
    }
    if (settings['language'] case final String value) {
      await prefs.setString('language', value);
    }
    if (settings['aiEnabled'] case final bool value) {
      await prefs.setBool('ai_enabled', value);
    }
    if (settings['waterTargetMl'] case final int value) {
      await prefs.setInt('water_target_ml', value);
    }
  }

  Future<void> logout(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token != null) {
      final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      try {
        await http.post(
          Uri.parse('$base/api/v1/auth/logout'),
          headers: {'authorization': 'Bearer $token'},
        );
      } catch (_) {}
    }
    await prefs.remove('account_token');
    await prefs.remove('account_user');
  }
}

// Copies a picked photo into the app's own documents directory (under
// photos/) and returns that permanent path -- image_picker's own path is
// often a transient cache file the OS can clear at any time. FoodEntry only
// ever stores this path (see photoPaths), never the image bytes.
class PhotoStore {
  const PhotoStore();

  Future<String> save(XFile photo) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${docsDir.path}/photos');
    await photosDir.create(recursive: true);
    final extension = photo.path.contains('.')
        ? photo.path.split('.').last
        : 'jpg';
    final fileName = '${DateTime.now().microsecondsSinceEpoch}.$extension';
    final destination = '${photosDir.path}/$fileName';
    await File(photo.path).copy(destination);
    return destination;
  }
}

// Backend-held photo storage for anything that crosses a device boundary
// (see /api/v1/media on the server). A synced entry's wire form never
// carries a raw filesystem path or embedded bytes -- only the small id
// this returns; each receiving device downloads and caches the bytes
// itself, once, under its own documents directory.
class MediaService {
  const MediaService();

  String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _extensionFor(String mimeType) =>
      switch (mimeType.split(';').first.trim()) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };

  Future<String> upload(String serverUrl, File file) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) throw Exception('Sign in to sync photos');
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final bytes = await file.readAsBytes();
    final response = await http
        .post(
          Uri.parse('$base/api/v1/media'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'mimeType': _mimeTypeFor(file.path),
            'dataBase64': base64Encode(bytes),
          }),
        )
        .timeout(const Duration(seconds: 30));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] ?? 'Could not upload photo');
    }
    return body['id'] as String;
  }

  Future<Directory> _cacheDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/photos/remote');
    await dir.create(recursive: true);
    return dir;
  }

  /// Returns a local cache path for [mediaId], downloading it once if not
  /// already cached. Returns null (never throws) on any failure -- offline,
  /// signed out, 404 -- so callers can fall back to a placeholder and simply
  /// try again next time this is rebuilt (e.g. next app open, pull-to-refresh).
  Future<String?> download(String serverUrl, String mediaId) async {
    final cacheDir = await _cacheDir();
    for (final ext in const ['jpg', 'png', 'webp']) {
      final cached = File('${cacheDir.path}/$mediaId.$ext');
      if (await cached.exists()) return cached.path;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('account_token');
      if (token == null) return null;
      final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      final response = await http
          .get(
            Uri.parse('$base/api/v1/media/$mediaId'),
            headers: {'authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final ext = _extensionFor(
        response.headers['content-type'] ?? 'image/jpeg',
      );
      final file = File('${cacheDir.path}/$mediaId.$ext');
      await file.writeAsBytes(response.bodyBytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}

class GoogleAuthService {
  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: googleClientId.isEmpty ? null : googleClientId,
    );
    _initialized = true;
  }

  /// Runs the interactive Google sign-in flow and returns the ID token to
  /// send to the server for verification (see /api/v1/auth/google). Needs
  /// [googleClientId] configured at build time AND a matching OAuth client
  /// registered in Google Cloud Console (package name + SHA-1 on Android,
  /// bundle ID on iOS) -- neither of those can be done from inside the app.
  static Future<String> signIn() async {
    if (googleClientId.isEmpty) {
      throw Exception(
        'Google sign-in needs a client ID configured for this build.',
      );
    }
    await _ensureInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw Exception('Google did not return a sign-in token.');
    }
    return idToken;
  }

  static Future<void> signOut() async {
    if (!_initialized) return;
    await GoogleSignIn.instance.signOut();
  }
}

class NutritionEstimate {
  const NutritionEstimate(
    this.name,
    this.calories,
    this.protein,
    this.carbs,
    this.servingGrams,
  );
  final String name;
  final int calories, protein, carbs;
  final double servingGrams;
}

class LinkedUser {
  const LinkedUser({required this.id, required this.name, required this.email});
  final String id, name, email;
  String get label => name.isNotEmpty ? name : email;
  factory LinkedUser.fromJson(Map<String, dynamic> j) => LinkedUser(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '',
    email: (j['email'] as String?) ?? '',
  );
}

// A pending sync request between two accounts, by email — nothing links (and
// nobody's email becomes visible to the other person) until the recipient
// explicitly accepts it.
class SyncInvite {
  const SyncInvite({
    required this.id,
    required this.fromName,
    required this.fromEmail,
    required this.toName,
    required this.toEmail,
  });
  final String id, fromName, fromEmail, toName, toEmail;
  String get fromLabel => fromName.isNotEmpty ? fromName : fromEmail;
  String get toLabel => toName.isNotEmpty ? toName : toEmail;
  factory SyncInvite.fromJson(Map<String, dynamic> j) => SyncInvite(
    id: j['id'] as String,
    fromName: (j['fromName'] as String?) ?? '',
    fromEmail: (j['fromEmail'] as String?) ?? '',
    toName: (j['toName'] as String?) ?? '',
    toEmail: (j['toEmail'] as String?) ?? '',
  );
}

class SyncInvites {
  const SyncInvites({required this.incoming, required this.outgoing});
  final List<SyncInvite> incoming, outgoing;
}

// Pulls new/changed foods from the backend's global catalogue into the
// SAME local overlay "add this food" writes to (see
// lib/parser/catalogue/local_overlay.dart) -- one shared canonical system,
// not a second sync path. Best-effort and safe to call often: a failed or
// unreachable sync just leaves the existing local catalogue untouched.
class CatalogueSyncService {
  const CatalogueSyncService();

  Future<void> sync(String serverUrl) async {
    try {
      final localVersion = await LocalCatalogueOverlay.loadVersion();
      final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      final versionResponse = await http
          .get(Uri.parse('$base/api/v1/catalogue/version'))
          .timeout(const Duration(seconds: 10));
      if (versionResponse.statusCode != 200) return;
      final remoteVersion =
          (jsonDecode(versionResponse.body) as Map<String, dynamic>)['version']
              as int;
      if (remoteVersion <= localVersion) return;
      final changesResponse = await http
          .get(Uri.parse('$base/api/v1/catalogue/changes?since=$localVersion'))
          .timeout(const Duration(seconds: 20));
      if (changesResponse.statusCode != 200) return;
      final body = jsonDecode(changesResponse.body) as Map<String, dynamic>;
      final foods = (body['foods'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      var overlay = await LocalCatalogueOverlay.load();
      for (final food in foods) {
        final entry = _validate(food);
        // A record that fails basic sanity checks is simply skipped, never
        // accepted as-is -- one bad record from the network can't corrupt
        // the working local catalogue.
        if (entry != null) overlay = await overlay.upsert(entry);
      }
      await LocalCatalogueOverlay.saveVersion(remoteVersion);
    } catch (_) {
      // Offline or the server is unreachable -- the app keeps working with
      // whatever catalogue it already has.
    }
  }

  OverlayFoodEntry? _validate(Map<String, dynamic> food) {
    final id = food['id'] as String?;
    final names = food['names'] as Map<String, dynamic>?;
    final name = (names?['en'] as String?) ?? (names?['pl'] as String?);
    final kcal = (food['kcalPer100g'] as num?)?.toDouble();
    if (id == null || name == null || name.trim().isEmpty) return null;
    if (kcal == null || kcal < 0 || kcal > 900) return null;
    final aliases = food['aliases'] as Map<String, dynamic>?;
    return OverlayFoodEntry(
      id: 'global_$id',
      canonical: name.trim(),
      category: food['category'] as String?,
      aliasesEn: (aliases?['en'] as List?)?.cast<String>() ?? const [],
      aliasesPl: (aliases?['pl'] as List?)?.cast<String>() ?? const [],
      kcalPer100g: kcal,
      proteinPer100g: (food['proteinPer100g'] as num?)?.toDouble(),
      carbsPer100g: (food['carbsPer100g'] as num?)?.toDouble(),
      fatPer100g: (food['fatPer100g'] as num?)?.toDouble(),
      fibrePer100g: (food['fibrePer100g'] as num?)?.toDouble(),
      servingAmount: (food['servingAmount'] as num?)?.toDouble(),
      servingUnit: food['servingUnit'] as String?,
      source: (food['source'] as String?) ?? 'global catalogue',
    );
  }

  // Sends a locally-added food to the backend as a global catalogue
  // contribution. Best-effort, fire-and-forget from the caller's point of
  // view -- the food is already usable locally regardless of whether this
  // succeeds (see AddFoodSheet).
  Future<void> contribute(
    String serverUrl, {
    required String name,
    String? category,
    required double kcal,
    double? protein,
    double? carbs,
    double? fat,
    double? fibre,
    required double servingAmount,
    String? servingUnit,
    String locale = 'en',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('account_token');
      if (token == null) return;
      final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      await http
          .post(
            Uri.parse('$base/api/v1/catalogue/contribute'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'name': name,
              'category': category,
              'kcal': kcal,
              'protein': protein,
              'carbs': carbs,
              'fat': fat,
              'fibre': fibre,
              'servingAmount': servingAmount,
              'servingUnit': servingUnit,
              'basis': 'perServing',
              'locale': locale,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Stays a local-only food until the next successful sync attempt.
    }
  }
}

// Exercise counterpart of CatalogueSyncService: pulls new/changed
// activities from the backend's global exercise catalogue into the SAME
// local overlay AI-resolved activities write to (see
// lib/parser/catalogue/local_exercise_overlay.dart). Best-effort and safe
// to call often, mirroring the food sync exactly.
class ExerciseCatalogueSyncService {
  const ExerciseCatalogueSyncService();

  Future<void> sync(String serverUrl) async {
    try {
      final localVersion = await LocalExerciseCatalogueOverlay.loadVersion();
      final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      final versionResponse = await http
          .get(Uri.parse('$base/api/v1/exercise-catalogue/version'))
          .timeout(const Duration(seconds: 10));
      if (versionResponse.statusCode != 200) return;
      final remoteVersion =
          (jsonDecode(versionResponse.body) as Map<String, dynamic>)['version']
              as int;
      if (remoteVersion <= localVersion) return;
      final changesResponse = await http
          .get(
            Uri.parse(
              '$base/api/v1/exercise-catalogue/changes?since=$localVersion',
            ),
          )
          .timeout(const Duration(seconds: 20));
      if (changesResponse.statusCode != 200) return;
      final body = jsonDecode(changesResponse.body) as Map<String, dynamic>;
      final activities = (body['activities'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      var overlay = await LocalExerciseCatalogueOverlay.load();
      for (final activity in activities) {
        final entry = _validate(activity);
        // A record that fails basic sanity checks is simply skipped, never
        // accepted as-is -- one bad record from the network can't corrupt
        // the working local catalogue.
        if (entry != null) overlay = await overlay.upsert(entry);
      }
      await LocalExerciseCatalogueOverlay.saveVersion(remoteVersion);
    } catch (_) {
      // Offline or the server is unreachable -- the app keeps working with
      // whatever catalogue it already has.
    }
  }

  OverlayExerciseEntry? _validate(Map<String, dynamic> activity) {
    final id = activity['id'] as String?;
    final names = activity['names'] as Map<String, dynamic>?;
    final name = (names?['en'] as String?) ?? (names?['pl'] as String?);
    final met = (activity['met'] as num?)?.toDouble();
    if (id == null || name == null || name.trim().isEmpty) return null;
    if (met == null || met <= 0 || met > 25) return null;
    final aliases = activity['aliases'] as Map<String, dynamic>?;
    return OverlayExerciseEntry(
      id: 'global_$id',
      canonical: name.trim(),
      category: activity['category'] as String?,
      aliasesEn: (aliases?['en'] as List?)?.cast<String>() ?? const [],
      aliasesPl: (aliases?['pl'] as List?)?.cast<String>() ?? const [],
      met: met,
      source: (activity['source'] as String?) ?? 'global catalogue',
    );
  }

  // Sends a locally AI-identified activity to the backend as a global
  // catalogue contribution. Best-effort, fire-and-forget from the caller's
  // point of view -- the activity is already usable locally regardless of
  // whether this succeeds (see _AddExerciseSheetState._contributeAiActivity).
  Future<void> contribute(
    String serverUrl, {
    required String name,
    String? category,
    required double met,
    String locale = 'en',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('account_token');
      if (token == null) return;
      final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      await http
          .post(
            Uri.parse('$base/api/v1/exercise-catalogue/contribute'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'name': name,
              'category': category,
              'met': met,
              'locale': locale,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Stays a local-only activity until the next successful sync attempt.
    }
  }
}

class EntrySyncService {
  const EntrySyncService();

  Future<bool> isAvailable() async {
    final prefs = await SharedPreferences.getInstance();
    final userRaw = prefs.getString('account_user');
    if (userRaw == null) return false;
    final user = jsonDecode(userRaw) as Map<String, dynamic>;
    return user['entrySyncEnabled'] == true &&
        ((user['linkedUserIds'] as List?)?.isNotEmpty ?? false);
  }

  // Only people who have mutually confirmed a sync invite — never a
  // directory of every registered account.
  Future<List<LinkedUser>> fetchPartners(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) return [];
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .get(
          Uri.parse('$base/api/v1/auth/link/partners'),
          headers: {'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return [];
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ((body['partners'] as List?) ?? [])
        .map((e) => LinkedUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SyncInvites> fetchInvites(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) return const SyncInvites(incoming: [], outgoing: []);
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .get(
          Uri.parse('$base/api/v1/auth/link/invites'),
          headers: {'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      return const SyncInvites(incoming: [], outgoing: []);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    List<SyncInvite> parse(String key) => ((body[key] as List?) ?? [])
        .map((e) => SyncInvite.fromJson(e as Map<String, dynamic>))
        .toList();
    return SyncInvites(
      incoming: parse('incoming'),
      outgoing: parse('outgoing'),
    );
  }

  // Sends a sync request by email. The recipient must explicitly accept it
  // (see acceptInvite) before either person appears in the other's diary
  // sync list — nobody is linked just by one side asking.
  Future<void> sendInvite(String serverUrl, String email) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) throw Exception('Sign in to send a sync invite');
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .post(
          Uri.parse('$base/api/v1/auth/link/invites'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 10));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(body['error'] ?? 'Could not send sync invite');
    }
  }

  Future<void> respondToInvite(
    String serverUrl,
    String inviteId, {
    required bool accept,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) throw Exception('Sign in to respond to sync invites');
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .post(
          Uri.parse(
            '$base/api/v1/auth/link/invites/$inviteId/${accept ? 'accept' : 'decline'}',
          ),
          headers: {'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Could not respond to invite');
    }
    if (accept) await const AccountService().refreshAccount(serverUrl);
  }

  Future<void> cancelInvite(String serverUrl, String inviteId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) throw Exception('Sign in to manage sync invites');
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .delete(
          Uri.parse('$base/api/v1/auth/link/invites/$inviteId'),
          headers: {'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Could not cancel invite');
    }
  }

  Future<void> unlink(String serverUrl, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) throw Exception('Sign in to manage sync partners');
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .delete(
          Uri.parse('$base/api/v1/auth/link/$userId'),
          headers: {'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] ?? 'Could not remove sync partner');
    }
    await prefs.setString('account_user', jsonEncode(body['user']));
  }

  Future<void> setEntrySyncEnabled(String serverUrl, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) throw Exception('Sign in to sync entries');
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .patch(
          Uri.parse('$base/api/v1/auth/link'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({'entrySyncEnabled': value}),
        )
        .timeout(const Duration(seconds: 10));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] ?? 'Could not update sync settings');
    }
    await prefs.setString('account_user', jsonEncode(body['user']));
  }

  Future<void> shareEntry(
    String serverUrl,
    FoodEntry entry,
    DateTime date,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) throw Exception('Sign in to sync entries');
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final response = await http
        .post(
          Uri.parse('$base/api/v1/entries/share'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({'date': dateKey, 'entry': entry.toJson()}),
        )
        .timeout(const Duration(seconds: 10));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] ?? 'Could not share entry');
    }
  }
}

class AiService {
  const AiService();

  Future<bool> isAvailable() async {
    try {
      await const AccountService().refreshAccount(defaultServerUrl);
    } catch (_) {
      // Falls back to the last-known cached account status when offline.
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('ai_enabled') != true) return false;
    final userRaw = prefs.getString('account_user');
    if (userRaw == null) return false;
    final user = jsonDecode(userRaw) as Map<String, dynamic>;
    return user['aiEnabled'] == true;
  }

  Future<NutritionEstimate> describe({
    required String serverUrl,
    required String kind,
    required String text,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) throw Exception('Sign in to use AI features');
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .post(
          Uri.parse('$base/api/v1/ai/describe'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({'kind': kind, 'text': text}),
        )
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] ?? 'AI request failed');
    }
    return _estimateFrom(body, fallbackName: text);
  }

  Future<NutritionEstimate> analyzeImage({
    required String serverUrl,
    required String kind,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('account_token');
    if (token == null) throw Exception('Sign in to use AI features');
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http
        .post(
          Uri.parse('$base/api/v1/ai/vision'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'kind': kind,
            'imageBase64': base64Encode(bytes),
            'mimeType': mimeType,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] ?? 'AI request failed');
    }
    return _estimateFrom(body, fallbackName: 'Photo entry');
  }

  NutritionEstimate _estimateFrom(
    Map<String, dynamic> body, {
    required String fallbackName,
  }) => NutritionEstimate(
    (body['name'] as String?)?.trim().isNotEmpty == true
        ? body['name'] as String
        : fallbackName,
    ((body['calories'] as num?) ?? 0).round(),
    ((body['protein'] as num?) ?? 0).round(),
    ((body['carbs'] as num?) ?? 0).round(),
    ((body['servingGrams'] as num?) ?? 0).toDouble(),
  );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.locale,
    required this.onLocale,
    required this.onImported,
    required this.dailyTarget,
    required this.dietStyle,
    required this.aiEnabled,
    required this.onPlanChanged,
    required this.onBodyChanged,
    required this.onSignedOut,
  });
  final Locale locale;
  final ValueChanged<Locale> onLocale;
  final VoidCallback onImported;
  final int dailyTarget;
  final String dietStyle;
  final bool aiEnabled;
  final ValueChanged<DietPlan> onPlanChanged;
  final ValueChanged<BodyProfile> onBodyChanged;
  final VoidCallback onSignedOut;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool ai = false, sync = false, nudges = true;
  BodyProfile body = const BodyProfile();
  late DietPlan plan = DietPlan(
    name: 'Current plan',
    style: widget.dietStyle,
    target: widget.dailyTarget,
  );
  List<DietPlan> savedPlans = [];
  int waterTarget = 2000;
  String contentServerUrl = '';
  String deviceId = '';
  String? contentCheckedAt;
  int publishedUpdates = 0;
  bool checkingContent = false;
  String installedVersion = '1.0.0+46';
  String? accountEmail;
  bool accountPrivateSync = false;
  late bool accountAiEnabled = widget.aiEnabled;
  bool accountIsAdmin = false;
  bool accountGoogleLinked = false;
  bool entrySyncEnabled = false;
  List<LinkedUser> syncPartners = [];
  List<SyncInvite> incomingInvites = [];
  List<SyncInvite> outgoingInvites = [];
  bool loadingSyncPartners = false;
  Timer? _syncPollTimer;

  @override
  void initState() {
    super.initState();
    _restoreHealthSettings();
    _loadInstalledVersion();
    // Sending/cancelling/accepting an invite is the OTHER person's action
    // just as often as it's yours -- without some kind of live refresh,
    // this list only ever reflects reality right after YOUR last tap, and
    // looks "stuck" the moment they act on their end instead. Simple
    // polling while this page is alive, not a full push/websocket system.
    _syncPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (accountEmail != null && !loadingSyncPartners) _loadSyncPartners();
    });
  }

  @override
  void dispose() {
    _syncPollTimer?.cancel();
    super.dispose();
  }

  // AppShell is the single owner of the live calorie target (it can change
  // it independently — e.g. the maintenance-based realignment in its own
  // _loadPlan finishing after this page already built with a stale value).
  // Without this, the Settings plan card could show a different number than
  // the dashboard until this page happened to reload from prefs itself.
  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dailyTarget != oldWidget.dailyTarget ||
        widget.dietStyle != oldWidget.dietStyle) {
      setState(
        () => plan = plan.copyWith(
          target: widget.dailyTarget,
          style: widget.dietStyle,
        ),
      );
    }
    if (widget.aiEnabled != oldWidget.aiEnabled) {
      setState(() => accountAiEnabled = widget.aiEnabled);
    }
  }

  Future<void> _loadInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(
          () => installedVersion = '${info.version}+${info.buildNumber}',
        );
      }
    } catch (_) {
      // The fallback keeps widget tests and unsupported platforms informative.
    }
  }

  Future<void> _restoreHealthSettings() async {
    try {
      await const AccountService().refreshAccount(defaultServerUrl);
    } catch (_) {
      // Falls back to the last-known cached account status when offline.
    }
    final prefs = await SharedPreferences.getInstance();
    final bodyRaw = prefs.getString('body_profile');
    final planRaw = prefs.getString('active_diet_plan');
    final savedRaw = prefs.getStringList('saved_diet_plans') ?? const [];
    final cached = prefs.getString('published_content_cache');
    var storedDeviceId = prefs.getString('content_device_id');
    if (storedDeviceId == null) {
      storedDeviceId =
          'a2-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
      await prefs.setString('content_device_id', storedDeviceId);
    }
    if (!mounted) return;
    setState(() {
      if (bodyRaw != null) {
        body = BodyProfile.fromJson(
          jsonDecode(bodyRaw) as Map<String, dynamic>,
        );
      }
      if (planRaw != null) {
        plan = DietPlan.fromJson(jsonDecode(planRaw) as Map<String, dynamic>);
      }
      savedPlans = savedRaw
          .map(
            (raw) => DietPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>),
          )
          .toList();
      if (savedPlans.isEmpty) savedPlans = [plan];
      waterTarget =
          prefs.getInt('water_target_ml') ?? recommendedWaterMl(body.weightKg);
      final storedServer = prefs.getString('content_server_url') ?? '';
      contentServerUrl =
          {
            'https://aa-cloud-wp30:8094',
            'https://aa-cloud-wp30.tail52a6fb.ts.net',
          }.contains(storedServer)
          ? defaultServerUrl
          : storedServer.isEmpty
          ? defaultServerUrl
          : storedServer;
      final accountRaw = prefs.getString('account_user');
      accountEmail = accountRaw == null
          ? null
          : (jsonDecode(accountRaw) as Map<String, dynamic>)['email']
                as String?;
      accountPrivateSync =
          accountRaw != null &&
          (jsonDecode(accountRaw) as Map<String, dynamic>)['privateSync'] ==
              true;
      accountAiEnabled =
          accountRaw != null &&
          (jsonDecode(accountRaw) as Map<String, dynamic>)['aiEnabled'] == true;
      accountIsAdmin =
          accountRaw != null &&
          (jsonDecode(accountRaw) as Map<String, dynamic>)['role'] == 'admin';
      accountGoogleLinked =
          accountRaw != null &&
          (jsonDecode(accountRaw) as Map<String, dynamic>)['googleLinked'] ==
              true;
      entrySyncEnabled =
          accountRaw != null &&
          (jsonDecode(accountRaw)
                  as Map<String, dynamic>)['entrySyncEnabled'] ==
              true;
      ai = prefs.getBool('ai_enabled') ?? false;
      deviceId = storedDeviceId!;
      contentCheckedAt = prefs.getString('content_last_checked');
      if (cached != null) {
        publishedUpdates =
            ((jsonDecode(cached) as Map<String, dynamic>)['releases']
                        as List? ??
                    const [])
                .length;
      }
    });
    if (prefs.getBool('daily_target_custom') != true &&
        body.maintenanceCalories != null) {
      final calculated = body.maintenanceCalories!.round();
      final alignedPlan = plan.copyWith(target: calculated);
      await prefs.setInt('daily_target', calculated);
      await prefs.setString(
        'active_diet_plan',
        jsonEncode(alignedPlan.toJson()),
      );
      widget.onPlanChanged(alignedPlan);
      if (mounted) setState(() => plan = alignedPlan);
    }
    if (accountEmail != null) _loadSyncPartners();
  }

  Future<void> _loadSyncPartners() async {
    setState(() => loadingSyncPartners = true);
    try {
      const service = EntrySyncService();
      final results = await Future.wait([
        service.fetchPartners(defaultServerUrl),
        service.fetchInvites(defaultServerUrl),
      ]);
      final partners = results[0] as List<LinkedUser>;
      final invites = results[1] as SyncInvites;
      if (mounted) {
        setState(() {
          syncPartners = partners;
          incomingInvites = invites.incoming;
          outgoingInvites = invites.outgoing;
        });
      }
    } catch (_) {
      // Keep whatever was last loaded when offline.
    } finally {
      if (mounted) setState(() => loadingSyncPartners = false);
    }
  }

  Future<void> _setEntrySyncEnabled(bool value) async {
    setState(() => entrySyncEnabled = value);
    try {
      await const EntrySyncService().setEntrySyncEnabled(
        defaultServerUrl,
        value,
      );
    } catch (error) {
      if (mounted) {
        setState(() => entrySyncEnabled = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LText(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  void _showSyncError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: LText(error.toString().replaceFirst('Exception: ', '')),
      ),
    );
  }

  Future<void> _sendSyncInvite() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LText('Invite someone to sync'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LText(
              'Enter their registered account email. They’ll need to confirm before you’re linked.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: ui(context, 'Email address'),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.pop(dialogContext, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const LText('Send invite'),
          ),
        ],
      ),
    );
    if (email == null || email.trim().isEmpty || !mounted) return;
    try {
      await const EntrySyncService().sendInvite(defaultServerUrl, email.trim());
      await _loadSyncPartners();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: LText('Sync invite sent.')));
      }
    } catch (error) {
      _showSyncError(error);
    }
  }

  // "Not found" here almost always means the OTHER person just acted on
  // this same invite (accepted/declined/it was cancelled from their side)
  // between this list last refreshing and this tap -- not a real failure.
  // Refresh and say so plainly instead of surfacing a confusing raw error
  // for something that's already resolved.
  Future<void> _handleInviteActionError(Object error) async {
    await _loadSyncPartners();
    if (!mounted) return;
    final message = error.toString().replaceFirst('Exception: ', '');
    if (message.toLowerCase().contains('not found')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LText('That invite was already handled — refreshed.'),
        ),
      );
    } else {
      _showSyncError(error);
    }
  }

  Future<void> _respondToInvite(SyncInvite invite, bool accept) async {
    try {
      await const EntrySyncService().respondToInvite(
        defaultServerUrl,
        invite.id,
        accept: accept,
      );
      await _loadSyncPartners();
    } catch (error) {
      await _handleInviteActionError(error);
    }
  }

  Future<void> _cancelInvite(SyncInvite invite) async {
    try {
      await const EntrySyncService().cancelInvite(defaultServerUrl, invite.id);
      await _loadSyncPartners();
    } catch (error) {
      await _handleInviteActionError(error);
    }
  }

  Future<void> _unlinkPartner(LinkedUser partner) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LText('Stop syncing?'),
        content: LText(
          '${partner.label} will no longer sync diaries with you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LText('Stop syncing'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await const EntrySyncService().unlink(defaultServerUrl, partner.id);
      await _loadSyncPartners();
    } catch (error) {
      _showSyncError(error);
    }
  }

  Future<void> _exportData() async {
    try {
      final csv = await const AccountService().exportDataAsCsv();
      final dir = await getTemporaryDirectory();
      final date = DateTime.now();
      final fileName =
          'a2-export-${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csv);
      if (!mounted) return;
      // The OS share sheet covers both "download" (save to Files/Drive) and
      // "email" (share directly into Gmail/Mail) with the same action --
      // whichever the person picks, no separate export paths to maintain.
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'a2 data export',
          text:
              'Your a2 data export ($fileName), opens in Excel, Sheets or Numbers.',
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LText(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _configureContentServer() async {
    final controller = TextEditingController(text: contentServerUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('Content update server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LText(
              'Use the A2 server address below. This local address works while you are on your home network.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: ui(context, 'Server URL'),
                hintText: defaultServerUrl,
              ),
            ),
            const SizedBox(height: 8),
            LText(
              'This device: $deviceId',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const LText('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    final uri = Uri.tryParse(value);
    final allowedLocalHttp =
        uri?.scheme == 'http' &&
        uri?.host.toLowerCase() == 'aa-cloud-wp30' &&
        uri?.port == 8094;
    if (value.isNotEmpty &&
        (uri == null || (uri.scheme != 'https' && !allowedLocalHttp))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LText(
              'Use HTTPS or the local address http://aa-cloud-wp30:8094.',
            ),
          ),
        );
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('content_server_url', value);
    if (mounted) setState(() => contentServerUrl = value);
  }

  Future<void> _checkContent() async {
    if (contentServerUrl.isEmpty) {
      await _configureContentServer();
      if (contentServerUrl.isEmpty) return;
    }
    setState(() => checkingContent = true);
    try {
      final count = await const ContentUpdateService().pull(
        serverUrl: contentServerUrl,
        deviceId: deviceId,
      );
      if (mounted) {
        setState(() {
          publishedUpdates = count;
          contentCheckedAt = DateTime.now().toIso8601String();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LText('Update check failed: $error')));
      }
    } finally {
      if (mounted) setState(() => checkingContent = false);
    }
  }

  Future<void> _editBody() async {
    final value = await showModalBottomSheet<BodyProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BodyProfileSheet(initial: body),
    );
    if (value == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('body_profile', jsonEncode(value.toJson()));
    widget.onBodyChanged(value);
    var updatedPlan = plan;
    if (prefs.getBool('daily_target_custom') != true &&
        value.maintenanceCalories != null) {
      updatedPlan = plan.copyWith(target: value.maintenanceCalories!.round());
      await prefs.setInt('daily_target', updatedPlan.target);
      await prefs.setString(
        'active_diet_plan',
        jsonEncode(updatedPlan.toJson()),
      );
      widget.onPlanChanged(updatedPlan);
    }
    await const AccountService().uploadLocalData(contentServerUrl);
    if (mounted) {
      setState(() {
        body = value;
        plan = updatedPlan;
      });
    }
  }

  Future<void> _editWaterTarget() async {
    final recommended = recommendedWaterMl(body.weightKg);
    final controller = TextEditingController(text: waterTarget.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LText('Water target'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: ui(dialogContext, 'Daily target (ml)'),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => controller.text = recommended.toString(),
              child: LText('Use recommended ($recommended ml)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const LText('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(controller.text)),
            child: const LText('Save'),
          ),
        ],
      ),
    );
    if (value == null || value <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('water_target_ml', value);
    await const AccountService().uploadLocalData(contentServerUrl);
    if (mounted) setState(() => waterTarget = value);
  }

  Future<void> _editPlan() async {
    final value = await showModalBottomSheet<DietPlan>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          DietPlanSheet(initial: plan, maintenance: body.maintenanceCalories),
    );
    if (value == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_diet_plan', jsonEncode(value.toJson()));
    await prefs.setInt('daily_target', value.target);
    await prefs.setBool('daily_target_custom', true);
    final updated = [...savedPlans];
    final existing = updated.indexWhere((item) => item.name == value.name);
    if (existing < 0) {
      updated.add(value);
    } else {
      updated[existing] = value;
    }
    await prefs.setStringList(
      'saved_diet_plans',
      updated.map((item) => jsonEncode(item.toJson())).toList(),
    );
    widget.onPlanChanged(value);
    await const AccountService().uploadLocalData(contentServerUrl);
    if (mounted) {
      setState(() {
        plan = value;
        savedPlans = updated;
      });
    }
  }

  Future<void> _activatePlan(DietPlan value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_diet_plan', jsonEncode(value.toJson()));
    await prefs.setInt('daily_target', value.target);
    await prefs.setBool('daily_target_custom', true);
    widget.onPlanChanged(value);
    await const AccountService().uploadLocalData(contentServerUrl);
    if (mounted) setState(() => plan = value);
  }

  String get bodySummary {
    final parts = <String>[];
    if (body.age != null) parts.add('${body.age} years');
    if (body.heightCm != null) {
      parts.add('${body.heightCm!.toStringAsFixed(0)} cm');
    }
    if (body.weightKg != null) {
      parts.add('${body.weightKg!.toStringAsFixed(1)} kg');
    }
    return parts.isEmpty
        ? 'Add age, height, weight, sex and activity'
        : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const TopBar('Your a2', 'Settings & privacy'),
      const SizedBox(height: 22),
      Card(
        child: ListTile(
          onTap: () async {
            final changed = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AccountSheet(
                serverUrl: contentServerUrl,
                accountEmail: accountEmail,
                googleLinked: accountGoogleLinked,
                onSignedOut: widget.onSignedOut,
              ),
            );
            if (changed == true) await _restoreHealthSettings();
          },
          contentPadding: EdgeInsets.all(16),
          leading: const CircleAvatar(
            radius: 27,
            backgroundColor: mint,
            child: LText(
              'A',
              style: TextStyle(
                color: forest,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          title: LText(
            accountEmail ?? 'Local profile',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: LText(
            accountEmail == null
                ? 'No account required · tap to sign in'
                : 'Signed in · tap to manage account',
          ),
          trailing: accountEmail == null
              ? const Icon(Icons.chevron_right)
              : IconButton(
                  icon: const Icon(Icons.logout, color: coral),
                  tooltip: ui(context, 'Sign out'),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const LText('Sign out?'),
                        content: const LText(
                          'You can sign back in any time. Your data stays safe on the server.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const LText('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const LText('Sign out'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await const AccountService().logout(contentServerUrl);
                      widget.onSignedOut();
                    }
                  },
                ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          onTap: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const LText('App language'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: AppLanguage.values
                    .map(
                      (e) => ListTile(
                        title: LText(e.nativeName),
                        subtitle: LText(e.englishName),
                        trailing: e.code == widget.locale.languageCode
                            ? const Icon(Icons.check_circle, color: forest)
                            : null,
                        onTap: () {
                          widget.onLocale(Locale(e.code));
                          Navigator.pop(context);
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          leading: const Icon(Icons.language, color: forest),
          title: const LText(
            'Language',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: LText(
            AppLanguage.values
                .firstWhere((e) => e.code == widget.locale.languageCode)
                .nativeName,
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
      const SizedBox(height: 22),
      const SectionHeader('Body & calculation', 'PERSONAL'),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            ListTile(
              onTap: _editBody,
              leading: const Icon(Icons.accessibility_new, color: forest),
              title: const LText(
                'Your details',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: LText(bodySummary),
              trailing: const Icon(Icons.chevron_right),
            ),
            if (body.maintenanceCalories != null) ...[
              const Divider(height: 1, indent: 55),
              ListTile(
                leading: const Icon(Icons.calculate_outlined, color: forest),
                title: LText(
                  'About ${body.maintenanceCalories!.round()} kcal maintenance',
                ),
                subtitle: LText(
                  'Resting estimate ${body.restingCalories!.round()} kcal · ${body.activity.toLowerCase()}',
                ),
              ),
            ],
            const Divider(height: 1, indent: 55),
            ListTile(
              onTap: _editWaterTarget,
              leading: const Icon(Icons.water_drop_outlined, color: forest),
              title: const LText(
                'Water target',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: LText('$waterTarget ml/day · tap to change'),
              trailing: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      const SectionHeader('Diet plans', 'ACTIVE'),
      const SizedBox(height: 8),
      Card(
        color: mint,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.restaurant_menu, color: forest),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LText(
                      plan.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  LText(
                    '${plan.target} kcal',
                    style: const TextStyle(
                      color: forest,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              LText(
                '${plan.style} · active daily limit',
                style: const TextStyle(color: Colors.black54),
              ),
              if (savedPlans.length > 1) ...[
                const SizedBox(height: 12),
                const LText(
                  'SAVED PLANS',
                  style: TextStyle(
                    fontSize: 10,
                    color: forest,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 7,
                  children: savedPlans
                      .map(
                        (item) => ChoiceChip(
                          label: LText(item.name),
                          selected: item.name == plan.name,
                          onSelected: (_) => _activatePlan(item),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _editPlan,
                  icon: const Icon(Icons.tune),
                  label: const LText('Change or create plan'),
                ),
              ),
            ],
          ),
        ),
      ),
      if (accountEmail != null) ...[
        const SizedBox(height: 22),
        const SectionHeader('Sync diary with', 'SHARED'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: entrySyncEnabled && syncPartners.isNotEmpty,
                onChanged: syncPartners.isEmpty ? null : _setEntrySyncEnabled,
                secondary: const Icon(Icons.sync, color: forest),
                title: const LText(
                  'Sync entries with linked people',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: LText(
                  syncPartners.isEmpty
                      ? 'Invite someone below and wait for them to accept to turn this on'
                      : 'Tap the sync icon on an entry to copy it into a linked person’s day',
                ),
              ),
              if (loadingSyncPartners) ...[
                const Divider(height: 1, indent: 55),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ] else ...[
                for (final invite in incomingInvites) ...[
                  const Divider(height: 1, indent: 55),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: gold,
                      child: Icon(Icons.mail_outline, color: ink),
                    ),
                    title: LText(invite.fromLabel),
                    subtitle: const LText('Wants to sync diaries with you'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.black45),
                          tooltip: ui(context, 'Decline'),
                          onPressed: () => _respondToInvite(invite, false),
                        ),
                        IconButton(
                          icon: const Icon(Icons.check_circle, color: success),
                          tooltip: ui(context, 'Accept'),
                          onPressed: () => _respondToInvite(invite, true),
                        ),
                      ],
                    ),
                  ),
                ],
                for (final partner in syncPartners) ...[
                  const Divider(height: 1, indent: 55),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: mint,
                      child: Text(
                        partner.label.isEmpty
                            ? '?'
                            : partner.label[0].toUpperCase(),
                        style: const TextStyle(color: forest),
                      ),
                    ),
                    title: LText(partner.label),
                    subtitle:
                        partner.email.isNotEmpty && partner.name.isNotEmpty
                        ? LText(partner.email)
                        : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.link_off, color: Colors.black45),
                      tooltip: ui(context, 'Stop syncing'),
                      onPressed: () => _unlinkPartner(partner),
                    ),
                  ),
                ],
                for (final invite in outgoingInvites) ...[
                  const Divider(height: 1, indent: 55),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: cream,
                      child: Icon(Icons.hourglass_empty, color: Colors.black45),
                    ),
                    title: LText(invite.toLabel),
                    subtitle: const LText(
                      'Invite sent — waiting for confirmation',
                      style: TextStyle(color: Colors.black54),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.black45),
                      tooltip: ui(context, 'Cancel'),
                      onPressed: () => _cancelInvite(invite),
                    ),
                  ),
                ],
                if (syncPartners.isEmpty &&
                    incomingInvites.isEmpty &&
                    outgoingInvites.isEmpty) ...[
                  const Divider(height: 1, indent: 55),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: LText(
                      'No one linked yet — invite someone by their registered email below.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ],
                const Divider(height: 1, indent: 55),
                ListTile(
                  onTap: _sendSyncInvite,
                  leading: const Icon(Icons.person_add_alt, color: forest),
                  title: const LText(
                    'Invite someone by email',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
      const SizedBox(height: 22),
      const SectionHeader('Smart features', 'OPTIONAL'),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            SwitchListTile(
              value: ai && accountAiEnabled,
              onChanged: !accountAiEnabled
                  ? null
                  : (v) async {
                      setState(() => ai = v);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('ai_enabled', v);
                      await const AccountService().uploadLocalData(
                        contentServerUrl,
                      );
                    },
              secondary: const Icon(Icons.auto_awesome, color: forest),
              title: const LText(
                'AI meal estimates',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: LText(
                accountAiEnabled
                    ? 'Photos and descriptions are analysed only when you ask.'
                    : 'Ask your administrator to enable AI for your account.',
              ),
            ),
            // Disabled alongside the nudge card (see showNudgeCard) — this
            // toggle didn't actually gate anything yet.
            if (showNudgeCard) ...[
              const Divider(height: 1, indent: 55),
              SwitchListTile(
                value: nudges,
                onChanged: (v) => setState(() => nudges = v),
                secondary: const Icon(
                  Icons.notifications_active_outlined,
                  color: forest,
                ),
                title: const LText(
                  'Helpful nudges',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const LText('Gentle, useful reminders—not guilt.'),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 22),
      const SectionHeader('Data', 'YOU’RE IN CONTROL'),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            if (accountIsAdmin && accountPrivateSync) ...[
              SwitchListTile(
                value: sync,
                onChanged: (v) async {
                  setState(() => sync = v);
                  if (v) {
                    await const AccountService().synchronise(contentServerUrl);
                  }
                },
                secondary: const Icon(Icons.cloud_outlined, color: forest),
                title: const LText(
                  'Private server sync',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const LText('Off · your data stays on this device'),
              ),
              const Divider(height: 1, indent: 55),
            ],
            if (!accountPrivateSync)
              ListTile(
                onTap: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const LText('Google Drive backup'),
                    content: const LText(
                      'Google backup will use your own Google account. Add the Google client ID in the app build, then return here to connect and choose a backup folder.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const LText('Close'),
                      ),
                    ],
                  ),
                ),
                leading: const Icon(Icons.add_to_drive_outlined, color: forest),
                title: const LText('Google Drive backup'),
                subtitle: const LText(
                  'Connect your own Google account · optional',
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            if (!accountPrivateSync) const Divider(height: 1, indent: 55),
            ListTile(
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const StorageSheet(),
              ),
              leading: const Icon(Icons.photo_library_outlined, color: forest),
              title: const LText(
                'Photo storage',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const LText('Device · compressed copies · 184 MB'),
              trailing: const Icon(Icons.chevron_right),
            ),
            if (accountIsAdmin && accountPrivateSync) ...[
              const Divider(height: 1, indent: 55),
              ListTile(
                onTap: _configureContentServer,
                leading: const Icon(Icons.dns_outlined, color: forest),
                title: const LText(
                  'Server',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: LText(
                  contentServerUrl.isEmpty
                      ? 'aa-cloud-wp30 · tap to configure'
                      : contentServerUrl,
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            ],
            if (accountIsAdmin) ...[
              const Divider(height: 1, indent: 55),
              ListTile(
                onTap: checkingContent ? null : _checkContent,
                leading: checkingContent
                    ? const Padding(
                        padding: EdgeInsets.all(3),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.system_update_alt, color: forest),
                title: const LText(
                  'Content updates',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: LText(
                  contentCheckedAt == null
                      ? 'Tap to check · controlled by your admin console'
                      : '$publishedUpdates published · last checked ${contentCheckedAt!.substring(0, 16).replaceFirst('T', ' ')}',
                ),
                trailing: const Icon(Icons.refresh),
              ),
            ],
            const Divider(height: 1, indent: 55),
            ListTile(
              onTap: _exportData,
              leading: const Icon(Icons.file_download_outlined, color: forest),
              title: const LText(
                'Export my data',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const LText('CSV · opens in Excel, Sheets or Numbers'),
              trailing: const Icon(Icons.ios_share),
            ),
            const Divider(height: 1, indent: 55),
            ListTile(
              leading: const Icon(Icons.info_outline, color: forest),
              title: const LText(
                'App version',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: LText(installedVersion),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Center(
        child: LText(
          'Private by default · Estimates, not medical advice',
          style: TextStyle(fontSize: 11, color: Colors.black45),
        ),
      ),
      const DevBadge(),
    ],
  );
}

class BodyProfileSheet extends StatefulWidget {
  const BodyProfileSheet({super.key, required this.initial});
  final BodyProfile initial;
  @override
  State<BodyProfileSheet> createState() => _BodyProfileSheetState();
}

class _BodyProfileSheetState extends State<BodyProfileSheet> {
  final formKey = GlobalKey<FormState>();
  late final age = TextEditingController(
    text: widget.initial.age?.toString() ?? '',
  );
  late final height = TextEditingController(
    text: widget.initial.heightCm?.toStringAsFixed(0) ?? '',
  );
  late final weight = TextEditingController(
    text: widget.initial.weightKg?.toStringAsFixed(1) ?? '',
  );
  late String? sex = widget.initial.sex;
  late String activity = widget.initial.activity;

  String? numberCheck(String? value, double low, double high) {
    final number = double.tryParse((value ?? '').replaceAll(',', '.'));
    if (number == null) return 'Enter a number';
    if (number < low || number > high) return 'Check this value';
    return null;
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: cream,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    padding: EdgeInsets.fromLTRB(20, 14, 20, sheetBottomInset(context, 24)),
    child: Form(
      key: formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Center(
              child: SizedBox(width: 42, child: Divider(thickness: 4)),
            ),
            const SizedBox(height: 10),
            const LText(
              'Your body details',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const LText(
              'Used only to estimate resting and maintenance energy. You stay in control of the calorie target.',
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: age,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: ui(context, 'Age'),
                      suffixText: 'years',
                    ),
                    validator: (v) => numberCheck(v, 18, 120),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: height,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: ui(context, 'Height'),
                      suffixText: 'cm',
                    ),
                    validator: (v) => numberCheck(v, 100, 250),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: weight,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: ui(context, 'Current weight'),
                suffixText: 'kg',
              ),
              validator: (v) => numberCheck(v, 30, 350),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: sex,
              decoration: InputDecoration(
                labelText: ui(context, 'Sex used by the equation'),
              ),
              hint: const LText('Choose one'),
              items: const [
                DropdownMenuItem(value: 'Male', child: LText('Male')),
                DropdownMenuItem(value: 'Female', child: LText('Female')),
              ],
              onChanged: (v) => setState(() => sex = v),
              validator: (v) => v == null ? 'Needed for this equation' : null,
            ),
            const SizedBox(height: 6),
            const LText(
              'This is a calculation input, not your gender identity.',
              style: TextStyle(fontSize: 11, color: Colors.black45),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: activity,
              decoration: InputDecoration(
                labelText: ui(context, 'Typical activity'),
              ),
              items:
                  const [
                        'Mostly seated',
                        'Lightly active',
                        'Moderately active',
                        'Very active',
                      ]
                      .map((v) => DropdownMenuItem(value: v, child: LText(v)))
                      .toList(),
              onChanged: (v) => setState(() => activity = v!),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(
                    context,
                    BodyProfile(
                      age: int.parse(age.text),
                      heightCm: double.parse(height.text.replaceAll(',', '.')),
                      weightKg: double.parse(weight.text.replaceAll(',', '.')),
                      sex: sex,
                      activity: activity,
                    ),
                  );
                },
                child: const LText('Save details'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class DietPlanSheet extends StatefulWidget {
  const DietPlanSheet({super.key, required this.initial, this.maintenance});
  final DietPlan initial;
  final double? maintenance;
  @override
  State<DietPlanSheet> createState() => _DietPlanSheetState();
}

class _DietPlanSheetState extends State<DietPlanSheet> {
  static const styles = <String, String>{
    'Balanced': 'Flexible mix of all food groups',
    'Mediterranean': 'Plants, whole grains, fish and olive oil',
    'Lower carbohydrate': 'A lower-carb starting structure',
    'Keto': 'Very low carbohydrate eating pattern',
    'High protein': 'Protein-forward meals and snacks',
  };
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.initial.name);
  late final target = TextEditingController(
    text: widget.initial.target.toString(),
  );
  late String style = widget.initial.style;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: cream,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    padding: EdgeInsets.fromLTRB(20, 14, 20, sheetBottomInset(context, 24)),
    child: Form(
      key: formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Center(
              child: SizedBox(width: 42, child: Divider(thickness: 4)),
            ),
            const SizedBox(height: 10),
            const LText(
              'Choose your diet plan',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const LText(
              'Start from a familiar eating style, then make it yours. The style does not set your calorie limit.',
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 16),
            ...styles.entries.map(
              (entry) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: style == entry.key ? mint : Colors.white,
                child: ListTile(
                  onTap: () => setState(() => style = entry.key),
                  leading: Icon(
                    style == entry.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: forest,
                  ),
                  title: LText(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: LText(entry.value),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: name,
              decoration: InputDecoration(labelText: ui(context, 'Plan name')),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Give your plan a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: target,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: ui(context, 'Daily calorie limit'),
                suffixText: 'kcal',
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return n == null || n < 800 || n > 6000
                    ? 'Enter 800–6000 kcal'
                    : null;
              },
            ),
            if (widget.maintenance != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LText(
                  'Your estimated maintenance is about ${widget.maintenance!.round()} kcal. This is an estimate, not a prescription.',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(
                    context,
                    DietPlan(
                      name: name.text.trim(),
                      style: style,
                      target: int.parse(target.text),
                    ),
                  );
                },
                child: const LText('Use this plan'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ImportCandidate {
  const ImportCandidate(
    this.date,
    this.title,
    this.detail,
    this.kind,
    this.confidence,
  );
  final String date, title, detail, kind, confidence;
  Map<String, String> toJson(String id) => {
    'id': id,
    'date': date,
    'title': title,
    'detail': detail,
    'kind': kind,
    'confidence': confidence,
    'source': 'Keto Meal Plan Poland',
  };
}

class ChatImportPage extends StatefulWidget {
  const ChatImportPage({super.key});
  @override
  State<ChatImportPage> createState() => _ChatImportPageState();
}

class _ChatImportPageState extends State<ChatImportPage> {
  final candidates = const [
    ImportCandidate(
      '11 Sep',
      'Weight · 89.4 kg',
      'Explicitly reported measurement',
      'MEASUREMENT',
      'High',
    ),
    ImportCandidate(
      '11 Sep',
      'Greek turkey lunch · 500 kcal',
      '410 g label · 26 g protein · 53 g carbs · 19 g fat',
      'MEAL',
      'High',
    ),
    ImportCandidate(
      '11 Sep',
      'Yoghurt, granola & honey · 406 kcal',
      'Whole serving; calculated from reported packaging',
      'MEAL',
      'Medium',
    ),
    ImportCandidate(
      'Recent',
      'Cod with leek sauce · 538 kcal',
      '420 g label · 28.1 g protein · 7.1 g fibre · 4.2 g salt',
      'MEAL',
      'High',
    ),
    ImportCandidate(
      'Recent',
      'Beef ‘N’ Bacon burger · 975 kcal',
      '359 g product value · 45.5 g protein',
      'MEAL',
      'High',
    ),
    ImportCandidate(
      'Recent',
      'High-intensity tennis · 60 min',
      'Exercise noted; calories deliberately not assumed',
      'ACTIVITY',
      'Medium',
    ),
  ];
  late final selected = List<bool>.filled(candidates.length, true);
  final imported = <String>{};
  String idFor(int index) => 'personal-import:$index';
  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final prefs = await SharedPreferences.getInstance();
    imported.addAll(prefs.getStringList('imported_record_ids') ?? const []);
    for (var i = 0; i < selected.length; i++) {
      if (imported.contains(idFor(i))) selected[i] = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final records = <String>[];
    for (var i = 0; i < selected.length; i++) {
      if (selected[i]) imported.add(idFor(i));
    }
    final prefs = await SharedPreferences.getInstance();
    records.addAll(prefs.getStringList('imported_records') ?? const []);
    final existingIds = records
        .map((e) => (jsonDecode(e) as Map<String, dynamic>)['id'])
        .toSet();
    for (var i = 0; i < selected.length; i++) {
      if (selected[i] && !existingIds.contains(idFor(i))) {
        records.add(jsonEncode(candidates[i].toJson(idFor(i))));
      }
    }
    await prefs.setStringList('imported_record_ids', imported.toList()..sort());
    await prefs.setStringList('imported_records', records);
    await prefs.setString('last_import_source', 'Keto Meal Plan Poland');
    await prefs.setString(
      'last_imported_at',
      DateTime.now().toUtc().toIso8601String(),
    );
    await const AccountService().uploadLocalData(defaultServerUrl);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final count = selected.where((v) => v).length;
    return Scaffold(
      appBar: AppBar(title: const LText('Review import')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: mint,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.verified_user_outlined, color: forest),
                            SizedBox(width: 8),
                            LText(
                              'Nothing is saved yet',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        SizedBox(height: 7),
                        LText(
                          'a2 found personal history records. Review them before importing.',
                          style: TextStyle(color: Colors.black54, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      LText(
                        '${candidates.length} RECORDS FOUND',
                        style: const TextStyle(
                          fontSize: 11,
                          color: forest,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() {
                          final value = selected.any((v) => !v);
                          for (var i = 0; i < selected.length; i++) {
                            selected[i] = value;
                          }
                        }),
                        child: const LText('Select all'),
                      ),
                    ],
                  ),
                  ...List.generate(
                    candidates.length,
                    (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: CheckboxListTile(
                          value: selected[i],
                          onChanged: (v) =>
                              setState(() => selected[i] = v ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          title: LText(
                            candidates[i].title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: LText(
                              '${candidates[i].date} · ${candidates[i].detail}\n${candidates[i].kind} · ${candidates[i].confidence} confidence',
                              style: const TextStyle(height: 1.35),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.warning_amber_rounded, color: coral),
                      title: LText(
                        'Dates need a final check',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: LText(
                        'Some messages say “today” or “recently”. a2 will not invent dates for those records.',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: ink,
                    padding: const EdgeInsets.all(17),
                  ),
                  onPressed: count == 0 ? null : _save,
                  icon: const Icon(Icons.download_done),
                  label: LText('Import $count records'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountSheet extends StatefulWidget {
  const AccountSheet({
    super.key,
    required this.serverUrl,
    required this.accountEmail,
    this.googleLinked = false,
    this.initialRegister = false,
    this.accountRequired = false,
    this.onDismiss,
    this.onSignedOut,
  });
  final String serverUrl;
  final String? accountEmail;
  final bool googleLinked;
  final bool initialRegister;
  final bool accountRequired;

  /// Called when the sheet is "done" for reasons other than signing out —
  /// signed in, created an account, or chose to keep using a2 locally.
  /// Falls back to `Navigator.pop` when shown as a modal (the default).
  final VoidCallback? onDismiss;

  /// Called after a successful sign-out. Falls back to `Navigator.pop` when
  /// shown as a modal (the default).
  final VoidCallback? onSignedOut;
  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  late bool register = widget.initialRegister;
  bool busy = false;
  String? error;

  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  bool changingPassword = false;
  String? passwordError;
  bool passwordChanged = false;

  late bool googleLinked = widget.googleLinked;
  bool linkingGoogle = false;
  String? googleError;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    currentPassword.dispose();
    newPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await const AccountService().authenticate(
        serverUrl: widget.serverUrl,
        email: email.text.trim(),
        password: password.text,
        register: register,
        name: name.text.trim(),
      );
      if (mounted) {
        if (widget.onDismiss != null) {
          widget.onDismiss!();
        } else {
          Navigator.pop(context, true);
        }
      }
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final idToken = await GoogleAuthService.signIn();
      await const AccountService().authenticateWithGoogle(
        serverUrl: widget.serverUrl,
        idToken: idToken,
      );
      if (mounted) {
        if (widget.onDismiss != null) {
          widget.onDismiss!();
        } else {
          Navigator.pop(context, true);
        }
      }
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _changePassword() async {
    if (currentPassword.text.isEmpty || newPassword.text.length < 8) {
      setState(
        () => passwordError = newPassword.text.length < 8
            ? 'New password must be at least 8 characters'
            : 'Enter your current password',
      );
      return;
    }
    setState(() {
      changingPassword = true;
      passwordError = null;
      passwordChanged = false;
    });
    try {
      await const AccountService().changePassword(
        serverUrl: widget.serverUrl,
        currentPassword: currentPassword.text,
        newPassword: newPassword.text,
      );
      if (mounted) {
        setState(() => passwordChanged = true);
        currentPassword.clear();
        newPassword.clear();
      }
    } catch (exception) {
      if (mounted) {
        setState(
          () => passwordError = exception.toString().replaceFirst(
            'Exception: ',
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => changingPassword = false);
    }
  }

  Future<void> _linkGoogle() async {
    setState(() {
      linkingGoogle = true;
      googleError = null;
    });
    try {
      final idToken = await GoogleAuthService.signIn();
      await const AccountService().authenticateWithGoogle(
        serverUrl: widget.serverUrl,
        idToken: idToken,
      );
      if (mounted) setState(() => googleLinked = true);
    } catch (exception) {
      if (mounted) {
        setState(
          () => googleError = exception.toString().replaceFirst(
            'Exception: ',
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => linkingGoogle = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: widget.accountEmail != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 24,
                      backgroundColor: mint,
                      child: Icon(Icons.verified_user, color: forest),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const LText(
                            'Manage account',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          LText(
                            widget.accountEmail!,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const LText(
                  'Change password',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: currentPassword,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: ui(context, 'Current password'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPassword,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: ui(context, 'New password'),
                    helperText: ui(context, 'At least 8 characters'),
                  ),
                ),
                if (passwordError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LText(
                      passwordError!,
                      style: const TextStyle(color: coral),
                    ),
                  ),
                if (passwordChanged)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LText(
                      'Password changed.',
                      style: const TextStyle(color: success),
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: changingPassword ? null : _changePassword,
                    child: changingPassword
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const LText('Change password'),
                  ),
                ),
                const Divider(height: 32),
                const LText(
                  'Linked accounts',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (googleLinked)
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: success, size: 20),
                      const SizedBox(width: 8),
                      const LText('Google account linked'),
                    ],
                  )
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: linkingGoogle || googleClientId.isEmpty
                          ? null
                          : _linkGoogle,
                      icon: linkingGoogle
                          ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.g_mobiledata, size: 22),
                      label: const LText('Link Google account'),
                    ),
                  ),
                  if (googleClientId.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LText(
                        'Google sign-in needs your Google client ID before it can be enabled.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                  if (googleError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LText(
                        googleError!,
                        style: const TextStyle(color: coral),
                      ),
                    ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      await const AccountService().logout(widget.serverUrl);
                      if (!context.mounted) return;
                      if (widget.onSignedOut != null) {
                        Navigator.pop(context);
                        widget.onSignedOut!();
                      } else {
                        Navigator.pop(context, true);
                      }
                    },
                    style: OutlinedButton.styleFrom(foregroundColor: coral),
                    child: const LText('Sign out'),
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText(
                  register ? 'Create your account' : 'Save your progress',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                LText(
                  widget.accountRequired
                      ? 'Create an account to protect your records and use them on another device.'
                      : 'Sign in for secure backup and access on another device.',
                  style: TextStyle(color: Colors.black54, height: 1.4),
                ),
                const SizedBox(height: 22),
                if (register)
                  TextField(
                    controller: name,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: ui(context, 'Name')),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: ui(context, 'Email address'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: password,
                  obscureText: true,
                  autofillHints: [
                    register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: InputDecoration(
                    labelText: ui(context, 'Password'),
                    helperText: register
                        ? ui(context, 'At least 8 characters')
                        : null,
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: LText(error!, style: const TextStyle(color: coral)),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy ? null : _submit,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.email_outlined),
                    label: LText(
                      register ? 'Create account' : 'Sign in with email',
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            register = !register;
                            error = null;
                          }),
                    child: LText(
                      register
                          ? 'Already have an account? Sign in'
                          : 'New to a2? Create an account',
                    ),
                  ),
                ),
                if (!widget.accountRequired) const Divider(height: 28),
                if (googleClientId.isEmpty)
                  const Row(
                    children: [
                      Icon(Icons.g_mobiledata, size: 28, color: Colors.black38),
                      SizedBox(width: 8),
                      Expanded(
                        child: LText(
                          'Google sign-in needs your Google client ID before it can be enabled.',
                          style: TextStyle(fontSize: 12, color: Colors.black45),
                        ),
                      ),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : _googleSignIn,
                      icon: const Icon(Icons.g_mobiledata, size: 22),
                      label: const LText('Continue with Google'),
                    ),
                  ),
                if (!widget.accountRequired)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => widget.onDismiss != null
                          ? widget.onDismiss!()
                          : Navigator.pop(context),
                      child: const LText('Keep using a2 locally'),
                    ),
                  ),
                const Center(
                  child: LText(
                    'Never upload health data without clear consent.',
                    style: TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ),
                const DevBadge(padding: EdgeInsets.only(top: 18)),
              ],
            ),
    ),
  );
}

class StorageSheet extends StatelessWidget {
  const StorageSheet({super.key});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LText(
            'Photo storage',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const LText(
            'Keep a small, useful visual history without filling your phone.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.phone_iphone, color: forest),
            title: LText(
              'Optimised on this device',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: LText(
              'Recommended · compressed copy, originals removed after analysis',
            ),
            trailing: Icon(Icons.check_circle, color: forest),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_outlined),
            title: LText('a2 private sync'),
            subtitle: LText(
              'Sign in to use aa-cloud-wp30 or an a2 hosted account',
            ),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.add_to_drive_outlined),
            title: LText('Google Drive backup'),
            subtitle: LText('Connect your own Google account · optional'),
          ),
          const Divider(),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.auto_delete_outlined, color: coral),
            title: LText(
              'Automatic cleanup',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: LText(
              'Keep thumbnails; remove meal originals after 30 days',
            ),
          ),
        ],
      ),
    ),
  );
}
