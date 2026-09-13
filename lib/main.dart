import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';

void main() => runApp(const A2App());

const ink = Color(0xFF17231E),
    forest = Color(0xFF1F684B),
    mint = Color(0xFFDDF3E7),
    cream = Color(0xFFF6F4EE),
    coral = Color(0xFFFF826D),
    gold = Color(0xFFF3C66E);

class A2App extends StatefulWidget {
  const A2App({super.key, this.startOnboarding = true});
  final bool startOnboarding;
  @override
  State<A2App> createState() => _A2AppState();
}

class _A2AppState extends State<A2App> {
  Locale locale = const Locale('en');
  late bool onboarding = widget.startOnboarding;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    _restore();
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
  }

  Future<void> _finishOnboarding() async {
    setState(() => onboarding = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
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
        : AppShell(locale: locale, onLocale: _setLocale),
  );
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
                onPressed: () {
                  if (page < 2) {
                    controller.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  } else {
                    widget.onDone();
                  }
                },
                child: LText(
                  tr(widget.locale, page == 2 ? 'start' : 'next'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.locale, required this.onLocale});
  final Locale locale;
  final ValueChanged<Locale> onLocale;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  int importedCount = 0;
  int dailyTarget = 2100;
  final entries = <FoodEntry>[];
  List<HistoryRecord> history = [];
  int get calories => entries
      .where((entry) => !entry.isExercise)
      .fold(0, (sum, entry) => sum + entry.calories);
  int get protein => entries.fold(0, (s, e) => s + e.protein);
  @override
  void initState() {
    super.initState();
    _loadImports();
    _loadHistory();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => dailyTarget = prefs.getInt('daily_target') ?? 2100);
    }
  }

  Future<void> _loadHistory() async {
    final raw = jsonDecode(
      await rootBundle.loadString('assets/data/ashley_history.json'),
    ) as Map<String, dynamic>;
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
    final pages = [
      TodayPage(
        entries: entries,
        calories: calories,
        protein: protein,
        dailyTarget: dailyTarget,
      ),
      ProgressPage(importedCount: importedCount, history: history),
      JourneyPage(history: history),
      ProfilePage(
        locale: widget.locale,
        onLocale: widget.onLocale,
        onImported: _loadImports,
        dailyTarget: dailyTarget,
        onTargetChanged: (value) => setState(() => dailyTarget = value),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
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
              backgroundColor: ink,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const LText('Add'),
              onPressed: () async {
                final e = await showModalBottomSheet<FoodEntry>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const AddItemSheet(),
                );
                if (e != null) setState(() => entries.add(e));
              },
            )
          : null,
    );
  }
}

class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.entries,
    required this.calories,
    required this.protein,
    required this.dailyTarget,
  });
  final List<FoodEntry> entries;
  final int calories, protein;
  final int dailyTarget;
  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
        sliver: SliverList.list(
          children: [
            const TopBar('Good afternoon, Ashley', 'Sunday, 13 September'),
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
            ] else ...[
              HeroCard(calories: calories, target: dailyTarget),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      'Protein',
                      '$protein g',
                      'of 145 g',
                      protein / 145,
                      coral,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: MetricCard('Fibre', '21 g', 'of 30 g', .7, gold),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const SectionHeader('A little nudge', 'WHY?'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: mint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      foregroundColor: forest,
                      child: Icon(Icons.eco_outlined),
                    ),
                    SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LText(
                            'Add some colour at dinner',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 3),
                          LText(
                            'One handful of vegetables gets you closer to today’s fibre goal.',
                            style: TextStyle(
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
              const SizedBox(height: 24),
              SectionHeader('Today’s timeline', '${entries.length} ITEMS'),
              const SizedBox(height: 8),
              ...entries.map((e) => FoodTile(e)),
            ],
          ],
        ),
      ),
    ],
  );
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
      Badge(
        backgroundColor: coral,
        smallSize: 9,
        child: IconButton.filledTonal(
          onPressed: () {},
          icon: const Icon(Icons.notifications_none),
        ),
      ),
    ],
  );
}

class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.calories, required this.target});
  final int calories, target;
  @override
  Widget build(BuildContext context) => Container(
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
                  value: (calories / target).clamp(0, 1),
                  strokeWidth: 12,
                  color: const Color(0xFF7AE0AC),
                  backgroundColor: Colors.white12,
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LText(
                    '$calories',
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
              const LText(
                'Looking steady',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              LText(
                '${math.max(0, target - calories)} kcal left for today',
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 18),
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
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
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

class MetricCard extends StatelessWidget {
  const MetricCard(
    this.label,
    this.value,
    this.detail,
    this.progress,
    this.color, {
    super.key,
  });
  final String label, value, detail;
  final double progress;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            label,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              LText(
                value,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: LText(
                  detail,
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          LinearProgressIndicator(
            value: progress.clamp(0, 1),
            color: color,
            backgroundColor: color.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(8),
            minHeight: 7,
          ),
        ],
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

class FoodEntry {
  const FoodEntry(
    this.name,
    this.time,
    this.calories,
    this.protein,
    this.icon, {
    this.isExercise = false,
  });
  final String name, time;
  final int calories, protein;
  final IconData icon;
  final bool isExercise;
}

class FoodTile extends StatelessWidget {
  const FoodTile(this.entry, {super.key});
  final FoodEntry entry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: mint,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(entry.icon, color: forest),
        ),
        title: LText(
          entry.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: LText(
          entry.isExercise
              ? entry.time
              : '${entry.time}  ·  ${entry.protein} g protein',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            LText(
              '${entry.isExercise ? '−' : ''}${entry.calories}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const LText(
              'kcal',
              style: TextStyle(fontSize: 10, color: Colors.black45),
            ),
          ],
        ),
      ),
    ),
  );
}

class FoodEstimate {
  const FoodEstimate(this.calories, this.protein);
  final int calories, protein;
}

class FoodEstimator {
  static FoodEstimate estimate(String description) {
    final text = description.toLowerCase();
    var kcal = 0.0, protein = 0.0;
    final foods = <String, (double, double, double)>{
      'oat': (389, 16.9, 40),
      'porridge': (389, 16.9, 40),
      'yoghurt': (80, 5, 100),
      'yogurt': (80, 5, 100),
      'milk': (50, 3.5, 150),
      'peach': (39, .9, 100),
      'plum': (46, .7, 80),
      'crisp': (520, 6, 25),
      'chips': (520, 6, 25),
      'chocolate raisin': (400, 5, 30),
      'raisin': (300, 3.1, 30),
      'cottage cheese': (98, 11, 60),
      'ham': (145, 21, 60),
      'egg': (143, 13, 60),
      'bread': (265, 9, 40),
      'banana': (89, 1.1, 120),
      'apple': (52, .3, 150),
      'chicken': (165, 31, 150),
      'rice': (130, 2.7, 180),
      'pasta': (158, 5.8, 180),
      'potato': (87, 1.9, 180),
      'cheese': (350, 25, 30),
    };
    final usedRanges = <String>[];
    for (final item in foods.entries) {
      final matches = item.key.allMatches(text).toList();
      if (matches.isEmpty || usedRanges.any((key) => key.contains(item.key))) {
        continue;
      }
      final match = matches.first;
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
          : item.value.$3;
      kcal += item.value.$1 * grams / 100;
      protein += item.value.$2 * grams / 100;
      usedRanges.add(item.key);
    }
    if (kcal == 0) return const FoodEstimate(0, 0);
    return FoodEstimate(kcal.round(), protein.round());
  }
}

class AddItemSheet extends StatelessWidget {
  const AddItemSheet({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 28,
    ),
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
              final result = await showModalBottomSheet<FoodEntry>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const AddMealSheet(),
              );
              if (context.mounted && result != null) {
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
                builder: (_) => const AddExerciseSheet(),
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
  const AddExerciseSheet({super.key});
  @override
  State<AddExerciseSheet> createState() => _AddExerciseSheetState();
}

class _AddExerciseSheetState extends State<AddExerciseSheet> {
  final activity = TextEditingController();
  final minutes = TextEditingController(text: '30');
  @override
  void dispose() {
    activity.dispose();
    minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      20,
      18,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
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
          controller: activity,
          decoration: InputDecoration(
            labelText: ui(context, 'Activity'),
            hintText: ui(context, 'Walking, running, cycling…'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: minutes,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: ui(context, 'Duration'),
            suffixText: 'minutes',
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              final name = activity.text.trim();
              final mins = int.tryParse(minutes.text) ?? 0;
              if (name.isEmpty || mins <= 0) return;
              final lower = name.toLowerCase();
              final perMinute = lower.contains('run')
                  ? 10
                  : lower.contains('cycl') || lower.contains('swim')
                  ? 8
                  : lower.contains('gym') || lower.contains('weight')
                  ? 6
                  : 4;
              Navigator.pop(
                context,
                FoodEntry(
                  name,
                  'Now · $mins min',
                  mins * perMinute,
                  0,
                  Icons.directions_run,
                  isExercise: true,
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const LText('Add exercise'),
          ),
        ),
      ],
    ),
  );
}

class AddMealSheet extends StatefulWidget {
  const AddMealSheet({super.key});
  @override
  State<AddMealSheet> createState() => _AddMealSheetState();
}

class _AddMealSheetState extends State<AddMealSheet> {
  final description = TextEditingController();
  int mode = 0;
  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
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
            'What did you have?',
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
                  'Meal photo',
                  mode == 1,
                  () => setState(() => mode = 1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CaptureChoice(
                  Icons.document_scanner_outlined,
                  'Scan label',
                  mode == 2,
                  () => setState(() => mode = 2),
                ),
              ),
            ],
          ),
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
                'e.g. 2 spoons cottage cheese, 4 slices ham, handful of slaw…',
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
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: ink,
                padding: const EdgeInsets.all(17),
              ),
              onPressed: () {
                final text = description.text.trim();
                final estimate = FoodEstimator.estimate(text);
                if (estimate.calories == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: LText(
                        'Not enough nutrition information. Add quantities or scan the product label.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  FoodEntry(
                    text.isEmpty ? 'Photo meal estimate' : text,
                    'Now',
                    estimate.calories,
                    estimate.protein,
                    Icons.restaurant,
                  ),
                );
              },
              icon: const Icon(Icons.auto_awesome),
              label: const LText(
                'Estimate & add',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

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
  final VoidCallback onTap;
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
String recordDetail(HistoryRecord r) {
  final bits = <String>[];
  if (r.weight != null) bits.add('${r.weight!.toStringAsFixed(1)} kg');
  if (r.kcal != null) {
    bits.add('${r.kcal!.round()} kcal');
  } else if (r.kcalMin != null) {
    bits.add('${r.kcalMin!.round()}–${r.kcalMax!.round()} kcal estimate');
  }
  if (r.detail.isNotEmpty) bits.add(r.detail);
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
                    height: 150,
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
  @override
  Widget build(BuildContext context) {
    final count = end.difference(start).inDays;
    final values = List<double>.filled(count, 0);
    for (final r in records) {
      if (!['meal', 'snack', 'drink'].contains(r.kind)) continue;
      final i = DateTime(
        r.at.year,
        r.at.month,
        r.at.day,
      ).difference(start).inDays;
      if (i >= 0 && i < count) {
        values[i] +=
            r.kcal ?? (r.kcalMin != null ? (r.kcalMin! + r.kcalMax!) / 2 : 0);
      }
    }
    return Row(
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
                    builder: (_, box) => Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: values[i] == 0
                            ? 3
                            : math.max(
                                8,
                                box.maxHeight * (values[i] / 2800).clamp(0, 1),
                              ),
                        decoration: BoxDecoration(
                          color: values[i] == 0 ? Colors.black12 : forest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
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
    );
  }
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
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: Container(width: 42, height: 4, color: Colors.black12)),
          const SizedBox(height: 20),
          LText(
            '${shortDate(date)} ${date.year}',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const LText(
            'Only information recorded in ChatGPT',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          ...records.map(
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
                  subtitle: LText(
                    '${recordDetail(r)}${r.images.isNotEmpty ? '\n${r.images.length} original image reference${r.images.length == 1 ? '' : 's'}' : ''}',
                  ),
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

class DietPlan {
  const DietPlan({
    required this.name,
    required this.style,
    required this.target,
  });
  final String name, style;
  final int target;
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

const defaultServerUrl = 'https://aa-cloud-wp30.tail52a6fb.ts.net';

class AccountService {
  const AccountService();
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
    return body['user'] as Map<String, dynamic>;
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

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.locale,
    required this.onLocale,
    required this.onImported,
    required this.dailyTarget,
    required this.onTargetChanged,
  });
  final Locale locale;
  final ValueChanged<Locale> onLocale;
  final VoidCallback onImported;
  final int dailyTarget;
  final ValueChanged<int> onTargetChanged;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool ai = true, sync = false, nudges = true;
  BodyProfile body = const BodyProfile();
  late DietPlan plan = DietPlan(
    name: 'Current plan',
    style: 'Balanced',
    target: widget.dailyTarget,
  );
  List<DietPlan> savedPlans = [];
  String contentServerUrl = '';
  String deviceId = '';
  String? contentCheckedAt;
  int publishedUpdates = 0;
  bool checkingContent = false;
  String installedVersion = '1.0.0+6';
  String? accountEmail;

  @override
  void initState() {
    super.initState();
    _restoreHealthSettings();
    _loadInstalledVersion();
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
      final storedServer = prefs.getString('content_server_url') ?? '';
      contentServerUrl = storedServer == 'https://aa-cloud-wp30:8094'
          ? defaultServerUrl
          : storedServer.isEmpty
          ? defaultServerUrl
          : storedServer;
      final accountRaw = prefs.getString('account_user');
      accountEmail = accountRaw == null
          ? null
          : (jsonDecode(accountRaw) as Map<String, dynamic>)['email']
                as String?;
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
            const LText('Use the secure A2 server address below.'),
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
    if (value.isNotEmpty && (uri == null || uri.scheme != 'https')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LText('Use an HTTPS server address.')),
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
    if (mounted) setState(() => body = value);
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
    widget.onTargetChanged(value.target);
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
    widget.onTargetChanged(value.target);
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
          trailing: const Icon(Icons.chevron_right),
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
      const SizedBox(height: 22),
      const SectionHeader('History', 'PRIVATE'),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          onTap: null,
          leading: const Icon(Icons.chat_bubble_outline, color: forest),
          title: const LText(
            'ChatGPT history imported',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const LText(
            '3 Aug – 12 Sep · meals, activity, weights and image references',
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
      const SizedBox(height: 22),
      const SectionHeader('Smart features', 'OPTIONAL'),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            SwitchListTile(
              value: ai,
              onChanged: (v) => setState(() => ai = v),
              secondary: const Icon(Icons.auto_awesome, color: forest),
              title: const LText(
                'AI meal estimates',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const LText(
                'Photos and descriptions are analysed only when you ask.',
              ),
            ),
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
        ),
      ),
      const SizedBox(height: 22),
      const SectionHeader('Data', 'YOU’RE IN CONTROL'),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            SwitchListTile(
              value: sync,
              onChanged: (v) => setState(() => sync = v),
              secondary: const Icon(Icons.cloud_outlined, color: forest),
              title: const LText(
                'Private server sync',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const LText('Off · your data stays on this device'),
            ),
            const Divider(height: 1, indent: 55),
            ListTile(
              onTap: () => showModalBottomSheet(
                context: context,
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
            const Divider(height: 1, indent: 55),
            const ListTile(
              leading: Icon(Icons.file_download_outlined, color: forest),
              title: LText(
                'Export my data',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: Icon(Icons.chevron_right),
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
    padding: EdgeInsets.fromLTRB(
      20,
      14,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
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
    padding: EdgeInsets.fromLTRB(
      20,
      14,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
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
  String idFor(int index) => 'chatgpt:6aa678f0:$index';
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
                          'a2 found candidate records in “Keto Meal Plan Poland”. Check them first—ChatGPT estimates remain marked as estimates.',
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
  });
  final String serverUrl;
  final String? accountEmail;
  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  bool register = false, busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
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
      if (mounted) Navigator.pop(context, true);
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
              children: [
                const Icon(Icons.verified_user, color: forest, size: 52),
                const SizedBox(height: 12),
                const LText(
                  'You are signed in',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                LText(widget.accountEmail!),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      await const AccountService().logout(widget.serverUrl);
                      if (context.mounted) Navigator.pop(context, true);
                    },
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
                const LText(
                  'An account is optional. Sign in to prepare for secure backup and access on another device.',
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
                const Divider(height: 28),
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
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const LText('Keep using a2 locally'),
                  ),
                ),
                const Center(
                  child: LText(
                    'Never upload health data without clear consent.',
                    style: TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ),
              ],
            ),
    ),
  );
}

class StorageSheet extends StatelessWidget {
  const StorageSheet({super.key});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
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
