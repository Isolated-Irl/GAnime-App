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
import 'services/trackers.dart';
import 'store.dart';
import 'screens/app_screens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const GAnimeApp());
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
    try {
      final t = await Store.tracker();
      final anilistToken = (t['anilistToken'] as String?) ?? '';
      if (anilistToken.isNotEmpty) {
        await Trackers.anilistSave(anilistToken, anime.id, episode);
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
      final idx = lib.indexWhere((e) => e.anilistId == anime.id);
      final entry = LibraryEntry(
        key: 'local_${anime.id}',
        source: 'local',
        title: anime.title,
        cover: anime.cover,
        status: 'CURRENT',
        progress: episode,
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
      const CalendarScreen(),
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
    return MaterialApp(
      title: 'GAnime',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('GAnime')),
        body: screens[_tab],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(
                icon: Icon(Icons.calendar_month), label: 'Calendar'),
            NavigationDestination(
                icon: Icon(Icons.library_books), label: 'Library'),
            NavigationDestination(
                icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
