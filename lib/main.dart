// GAnime Android — Flutter + media_kit (mpv) port.
// Android first. Web app (ganime.pages.dev) is untouched by this app.
// Phase 1: media_kit player (screens/player.dart + Settings > Player Test).
// Phase 2: Home/Search/Calendar (AniList), Details + Episodes, Continue Watching.
// Phase 3: Library (Local/AniList/Simkl/MAL), profiles, separate audio/subtitle settings.
// Phase 4: Firebase Auth + Firestore sync (one doc users/{uid}).
// Phase 5: Addons manager, Stremio user-installed addons only.
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'models.dart';
import 'services/firebase_sync.dart';
import 'services/kitsu.dart';
import 'services/trackers.dart';
import 'store.dart';
import 'screens/app_screens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const GAnimeApp());
}

/// Web logo mark, drawn (no asset, no SVG package): the folded-G path
/// from the web top bar, gradient #064E3B → #059669 → #10B981 → #A3E635.
/// Used with the text "nime" beside it, exactly like the web brand.
class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoMarkPainter()),
    );
  }
}

class _LogoMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 512;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 50 * s
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          Color(0xFF064E3B),
          Color(0xFF059669),
          Color(0xFF10B981),
          Color(0xFFA3E635),
        ],
        stops: [0.0, 0.45, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final path = Path()
      ..moveTo(300 * s, 300 * s)
      ..lineTo(105 * s, 430 * s)
      ..lineTo(265 * s, 95 * s)
      ..lineTo(415 * s, 415 * s);
    canvas.drawPath(path, paint);
    final diamond = Path()
      ..moveTo(448 * s, 398 * s)
      ..lineTo(465 * s, 415 * s)
      ..lineTo(448 * s, 432 * s)
      ..lineTo(431 * s, 415 * s)
      ..close();
    canvas.drawPath(
        diamond,
        Paint()
          ..style = PaintingStyle.fill
          ..shader = paint.shader);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GAnimeApp extends StatefulWidget {
  const GAnimeApp({super.key});
  @override
  State<GAnimeApp> createState() => _GAnimeAppState();
}

class _GAnimeAppState extends State<GAnimeApp> {
  final FirebaseSync _firebase = FirebaseSync();
  // NOTE: account namespace stays 'guest' in this build. Firebase sign-in
  // does not yet switch the profile namespace to uid:<uid> — see README
  // "Known gaps". That is why this field is final for now.
  final String _account = 'guest';
  String _profileId = 'p1';
  AppSettings _settings = const AppSettings();
  int _tab = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _firebase.loadConfig();
    final settings = await Store.settings();
    final profiles = await Store.profiles(_account);
    final active = await Store.activeProfile(_account);
    setState(() {
      _settings = settings;
      _profileId = active ?? profiles.first.id;
      _ready = true;
    });
  }

  Future<void> _onMarkWatched(Anime anime, int episode) async {
    // Push progress to trackers, best-effort, never blocks the UI.
    // Catalogue ids are Kitsu ids; the AniList id is resolved first.
    int? anilistId;
    try {
      final t = await Store.tracker();
      final anilistToken = (t['anilistToken'] as String?) ?? '';
      if (anilistToken.isNotEmpty) {
        anilistId = await Kitsu.resolveAnilistId(anime.id);
        if (anilistId != null) {
          await Trackers.anilistSave(anilistToken, anilistId, episode);
        }
      }
      final simklClient = (t['simklClientId'] as String?) ?? '';
      final simklToken = (t['simklToken'] as String?) ?? '';
      final simklId = (t['simklIdFor_${anime.id}'] as num?)?.toInt();
      if (simklClient.isNotEmpty &&
          simklToken.isNotEmpty &&
          simklId != null) {
        await Trackers.simklSave(simklClient, simklToken, simklId, episode);
      }
    } catch (_) {}
    // Also record in the local library.
    try {
      final lib = await Store.localLibrary(_profileId);
      var progress = episode;
      // Drop a stale pre-Kitsu entry for the same title (keyed by the old
      // AniList id), keeping the higher progress of the two.
      if (anilistId != null && anilistId != anime.id) {
        for (final s in lib.where((e) => e.key == 'local_$anilistId')) {
          if (s.progress > progress) progress = s.progress;
        }
        lib.removeWhere((e) => e.key == 'local_$anilistId');
      }
      final idx = lib.indexWhere((e) => e.anilistId == anime.id);
      final entry = LibraryEntry(
        key: 'local_${anime.id}',
        source: 'local',
        title: anime.title,
        cover: anime.cover,
        status: 'CURRENT',
        progress: progress,
        total: anime.episodes,
        anilistId: anime.id,
      );
      if (idx >= 0) {
        lib[idx] = entry;
      } else {
        lib.add(entry);
      }
      await Store.saveLocalLibrary(_profileId, lib);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    final screens = [
      HomeScreen(
          profileId: _profileId,
          settings: _settings,
          onMarkWatched: _onMarkWatched),
      SearchScreen(
          profileId: _profileId,
          settings: _settings,
          onMarkWatched: _onMarkWatched),
      CalendarScreen(
          profileId: _profileId,
          settings: _settings,
          onMarkWatched: _onMarkWatched),
      LibraryScreen(
          profileId: _profileId,
          settings: _settings,
          onMarkWatched: _onMarkWatched),
      SettingsScreen(
        account: _account,
        profileId: _profileId,
        settings: _settings,
        firebase: _firebase,
        onSettings: (s) => setState(() => _settings = s),
        onProfile: (id) => setState(() => _profileId = id),
      ),
    ];
    // Web parity theme: bg #0d0d0d, cards #222222, accent teal #14b8a6
    // (web --bg-surface / --bg-card / --accent). Home has no top bar
    // because the hero sits at the very top, like the web home.
    return MaterialApp(
      title: 'GAnime',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        cardColor: const Color(0xFF222222),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF14B8A6),
          secondary: Color(0xFF14B8A6),
          surface: Color(0xFF0D0D0D),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF0D0D0D),
          indicatorColor: Color(0x3314B8A6),
        ),
      ),
      home: Scaffold(
        // Web top bar (all tabs except Home, where the hero sits at
        // the top): logo mark + "nime" left, profile avatar right.
        // Avatar is a skeleton placeholder: profile switch comes
        // after the skeleton phase, it does not silently do nothing.
        appBar: _tab == 0
            ? null
            : AppBar(
                backgroundColor: const Color(0xFF0D0D0D),
                elevation: 0,
                titleSpacing: 16,
                title: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LogoMark(size: 32),
                    Text('nime',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ],
                ),
                actions: [
                  Builder(
                    builder: (ctx) => IconButton(
                      onPressed: () =>
                          ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Profile switch comes after the skeleton phase.'),
                        ),
                      ),
                      icon: const CircleAvatar(
                        backgroundColor: Color(0xFFF9A8D4),
                        child: Icon(Icons.person, color: Colors.black87),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
        body: screens[_tab],
        // Web bottom nav is a floating pill, not a full-width bar.
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.grey.shade800),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 16)
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                for (int i = 0; i < 5; i++)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => setState(() => _tab = i),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == _tab
                                  ? const Color(0xFF2A2A2A)
                                  : Colors.transparent,
                            ),
                            child: Icon(
                              [
                                Icons.home,
                                Icons.search,
                                Icons.calendar_month,
                                Icons.library_books,
                                Icons.settings,
                              ][i],
                              color: i == _tab
                                  ? Colors.white
                                  : Colors.grey.shade400,
                            ),
                          ),
                          Text(
                            [
                              'Home',
                              'Search',
                              'Calendar',
                              'Library',
                              'Settings',
                            ][i],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: i == _tab
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              color: i == _tab
                                  ? Colors.white
                                  : Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
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
