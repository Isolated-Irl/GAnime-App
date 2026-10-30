// GAnime Android — Flutter + media_kit (mpv) port.
// Android first. Web app (ganime.pages.dev) is untouched by this app.
// Phase 1: media_kit player (screens/player.dart + Settings > Player Test).
// Phase 2: Home/Search/Calendar (AniList), Details + Episodes, Continue Watching.
// Phase 3: Library (Local/AniList/Simkl/MAL), profiles, separate audio/subtitle settings.
// Phase 4: Firebase Auth + Firestore sync (one doc users/{uid}).
// Phase 5: Addons manager, Stremio user-installed addons only.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'models.dart';
import 'services/firebase_sync.dart';
import 'services/kitsu.dart';
import 'services/trackers.dart';
import 'store.dart';
import 'theme.dart';
import 'screens/app_screens.dart';
import 'screens/boot.dart';
import 'screens/settings/settings_shell.dart';
import 'widgets/logo.dart';
import 'widgets/skeletons.dart';

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

enum _BootPhase { loading, splash, gate, picker, home }

class _GAnimeAppState extends State<GAnimeApp> {
  final FirebaseSync _firebase = FirebaseSync();
  // Account namespace: 'guest' for guest sessions, 'uid:<uid>' once signed
  // in. Switched BEFORE any profile store access so profiles, watched,
  // library and sync always run under the right owner.
  String _account = 'guest';
  String _profileId = 'p1';
  AppSettings _settings = const AppSettings();
  // Tracks the last applied status-bar visibility so we only hit the
  // platform channel when the Layout > Hide Status Bar toggle changes.
  bool _lastHideStatusBar = false;

  /// Applies Settings > Layout > Hide Status Bar: hides the system
  /// notification (status) bar for a fullscreen look, restores it when off.
  void _applySystemUI() {
    if (_settings.hideStatusBar == _lastHideStatusBar) return;
    _lastHideStatusBar = _settings.hideStatusBar;
    if (_settings.hideStatusBar) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }
  int _tab = 0;
  // Boot flow: loading -> splash (once, ~2.2s) -> gate (no session) or
  // picker (session/guest) -> home. Matches the website's rule: profile
  // picker when a session exists, sign-in page when there is none.
  _BootPhase _phase = _BootPhase.loading;
  List<Profile> _profiles = [];
  // Website parity: no profiles = straight to Add Profile (create-first).
  // Distinguishes "still loading" (skeleton) from "loaded, none" (add).
  bool _profilesLoaded = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _firebase.loadConfig();
    // Restored session: own the uid namespace from the first store read.
    if (_firebase.signedIn && _firebase.uid != null) {
      _account = 'uid:${_firebase.uid}';
    }
    final settings = await Store.settings();
    final profiles = await Store.profiles(_account);
    final active = await Store.activeProfile(_account);
    final guest = await Store.isGuest();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _profiles = profiles;
      _profilesLoaded = true;
      // Validate the saved active id (stale ids must not survive), and
      // never crash on an empty list — the app no longer seeds a profile.
      _profileId = (active != null && profiles.any((p) => p.id == active))
          ? active
          : (profiles.isNotEmpty ? profiles.first.id : _profileId);
      _phase = _BootPhase.splash;
    });
    // Branded beat, then route. Plays once per cold start. The splash
    // animation runs ~1.75s; hold slightly past it so it completes.
    await Future.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    setState(() {
      _phase = guest ? _BootPhase.picker : _BootPhase.gate;
    });
    // Website parity (Sync.bootSync): when signed in, do a best-effort
    // background pull/merge/push so the cloud copy is fresh. Never blocks
    // boot and never surfaces errors — Sync Now remains the explicit path.
    if (_firebase.signedIn && !guest) {
      _bootSync(_profileId, settings);
    }
  }

  Future<void> _bootSync(String profileId, AppSettings settings) async {
    try {
      final profiles = await Store.profiles(_account);
      final watched = await Store.allWatched(profileId);
      final lib = await Store.localLibrary(profileId);
      final ads = await Store.addons(profileId);
      final tombs = await Store.tombstones();
      await _firebase.push(
        account: _account,
        settings: settings,
        profiles: profiles,
        watched: watched,
        localLibrary: lib,
        addons: ads,
        tombstones: tombs,
      );
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Website parity (_pullThenRoute, 2026-10-26 fix): pull the cloud doc after
  /// sign-in (8s timeout) and union remote profiles into the local store
  /// (local wins on conflict) so routing sees the cloud's profiles. Returns
  /// true when the pull succeeded — even when the cloud simply has no
  /// profiles yet.
  Future<bool> _pullCloudProfiles() async {
    try {
      final doc = await _firebase
          .pullDocumentJson()
          .timeout(const Duration(seconds: 8));
      if (doc == null) return false;
      final remoteProfiles = (doc['profiles'] as List?) ?? [];
      if (remoteProfiles.isNotEmpty) {
        final local = await Store.profiles(_account);
        final remote = <Profile>[];
        for (final p in remoteProfiles) {
          try {
            remote.add(Profile.fromJson(Map<String, dynamic>.from(p as Map)));
          } catch (_) {}
        }
        if (local.isEmpty) {
          // Website rule: fresh login takes the cloud as-is, no merge.
          await Store.saveProfiles(_account, remote);
          final activeId = doc['activeProfileId'] as String?;
          if (activeId != null &&
              activeId.isNotEmpty &&
              remote.any((p) => p.id == activeId)) {
            await Store.setActiveProfile(_account, activeId);
          }
        } else {
          // Both sides have data: merge, remote wins on same-id conflict.
          final byId = <String, Profile>{};
          for (final p in local) {
            byId[p.id] = p;
          }
          for (final p in remote) {
            byId[p.id] = p;
          }
          await Store.saveProfiles(_account, byId.values.toList());
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Website parity (showCloudRetry, 2026-10-26 fix): when the cloud can't be
  /// reached and there are no local profiles, offer Retry / Continue on this
  /// device — never silently push toward creating a duplicate profile.
  void _showCloudRetry() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Couldn't reach your cloud"),
        content: const Text(
          "Your profiles live in the cloud, but the app couldn't reach it "
          "just now. Check your connection and try again — don't create a "
          "new profile yet, or you'll end up with a duplicate.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openAddProfile();
            },
            child: const Text('Continue on this device'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final pulled = await _pullCloudProfiles();
              await _reloadProfiles();
              if (!mounted) return;
              if (_profiles.isNotEmpty) {
                setState(() => _phase = _BootPhase.picker);
              } else if (!pulled) {
                _showCloudRetry();
              } else {
                _openAddProfile();
              }
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Refresh the profile list from the store (after add/rename/delete).
  Future<void> _reloadProfiles() async {
    final profiles = await Store.profiles(_account);
    final active = await Store.activeProfile(_account);
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _profilesLoaded = true;
      _profileId = (active != null && profiles.any((p) => p.id == active))
          ? active
          : (profiles.isNotEmpty ? profiles.first.id : _profileId);
      // If the last profile was deleted while in the app, fall back to
      // the picker (which routes to Add Profile when empty).
      if (_profiles.isEmpty && _phase == _BootPhase.home) {
        _phase = _BootPhase.picker;
      }
    });
  }

  void _goHome(String profileId) {
    setState(() {
      _profileId = profileId;
      _tab = 0;
      _phase = _BootPhase.home;
    });
    Store.setActiveProfile(_account, profileId);
  }

  Future<void> _pickProfile(String profileId) async {
    await Store.setActiveProfile(_account, profileId);
    _goHome(profileId);
  }

  void _openAddProfile() {
    _navKey.currentState?.push(MaterialPageRoute(
      builder: (_) => AddProfileScreen(
        account: _account,
        isFirst: _profiles.isEmpty,
        onCreated: () async {
          _navKey.currentState?.pop();
          await _reloadProfiles();
          // If profiles exist now, go to picker (not back to login gate).
          if (mounted && _profiles.isNotEmpty) {
            setState(() => _phase = _BootPhase.picker);
          }
        },
      ),
    ));
  }

  void _openManageProfiles() {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    showModalBottomSheet(
      context: ctx,
      // Use ctx (below MaterialApp) not root context — GaColors is
      // only available inside MaterialApp's theme.
      backgroundColor: GaColors.of(ctx).field,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => _ManageProfilesSheet(
        account: _account,
        profiles: _profiles,
        activeId: _profileId,
        onChanged: () async {
          if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
          await _reloadProfiles();
          if (mounted) _openManageProfiles();
        },
      ),
    );
  }

  /// Back on the picker: return to the current active profile if there is
  /// one, otherwise minimize the app (never a broken state).
  void _pickerBack() {
    if (_profiles.any((p) => p.id == _profileId)) {
      setState(() => _phase = _BootPhase.home);
    } else {
      SystemNavigator.pop();
    }
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

  final _navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    _applySystemUI();
    // Real theme switch: Dark (#0d0d0d family) vs AMOLED true-black.
    // GaColors carries the per-mode surfaces so scaffolds, cards, sheets,
    // dialogs and inputs all follow the mode — not just the scaffold.
    // Accent follows Settings > Layout > THEME (default white,
    // like the website).
    final accent = themeAccent(_settings.theme);
    final ga = GaColors.forMode(amoled: _settings.amoledBlack);
    final base = ThemeData.dark(useMaterial3: true);
    final theme = base.copyWith(
      textTheme:
          base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      scaffoldBackgroundColor: ga.surface,
      cardColor: ga.card,
      dialogTheme: DialogThemeData(backgroundColor: ga.card),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: ga.card),
      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: accent,
        surface: ga.surface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ga.surface,
        indicatorColor: accent.withValues(alpha: 0.2),
      ),
      extensions: <ThemeExtension<dynamic>>[ga],
    );

    late final Widget home;
    switch (_phase) {
      case _BootPhase.loading:
        // Boot skeleton: ghost of the real splash (radial gradient bg,
        // 64px mark + wordmark block side by side), so nothing jumps
        // when the splash lands.
        home = Scaffold(
          backgroundColor: Colors.black,
          body: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.1,
                colors: [Color(0xFF1E1E1E), Color(0xFF0A0A0A)],
              ),
            ),
            child: SafeArea(
              child: Skeleton(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SkeletonBlock(width: 64, height: 64, radius: 16),
                      SizedBox(width: 6),
                      SkeletonBlock(width: 110, height: 44, radius: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        break;
      case _BootPhase.splash:
        home = const SplashScreen();
        break;
      case _BootPhase.gate:
        home = WelcomeBackScreen(
          firebase: _firebase,
          onSignedIn: () async {
            setState(() => _account = 'uid:${_firebase.uid}');
            // Website parity (_pullThenRoute, 2026-10-26 fix): pull the cloud
            // doc FIRST so a fresh device doesn't get pushed to create a
            // brand-new profile when the cloud already has profiles. Never
            // route straight to create-first on a failed pull.
            final pulled = await _pullCloudProfiles();
            await _reloadProfiles();
            if (!mounted) return;
            if (_profiles.isNotEmpty) {
              setState(() => _phase = _BootPhase.picker);
            } else if (!pulled) {
              _showCloudRetry();
            } else {
              _openAddProfile();
            }
          },
          onGuest: () async {
            setState(() => _account = 'guest');
            await _reloadProfiles();
            if (mounted) setState(() => _phase = _BootPhase.picker);
          },
        );
        break;
      case _BootPhase.picker:
        // Profiles load before the splash, so this is normally instant.
        // Website parity (create-first): no profiles = straight to Add
        // Profile — the app never auto-creates one. No back button there
        // (the web hides it too when it's the first profile).
        if (!_profilesLoaded) {
          home = const Scaffold(
              backgroundColor: Colors.black, body: SkeletonPicker());
        } else if (_profiles.isEmpty) {
          home = AddProfileScreen(
            account: _account,
            isFirst: true,
            showBack: false,
            onCreated: () async => _reloadProfiles(),
          );
        } else {
          home = ProfilePickerScreen(
            account: _account,
            profiles: _profiles,
            activeId: _profileId,
            onSelect: _pickProfile,
            onAddProfile: _openAddProfile,
            onManage: _openManageProfiles,
            onBack: _pickerBack,
          );
        }
        break;
      case _BootPhase.home:
        // Builder gives the shell a context BELOW MaterialApp, so
        // GaColors.of(context) / Theme.of(context) resolve the real theme.
        // (The root context is above MaterialApp: GaColors.of is null there.)
        home = Builder(builder: (ctx) => _buildShell(ctx));
        break;
    }

    return MaterialApp(
      title: 'GAnime',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      theme: theme,
      home: home,
    );
  }

  /// The main 5-tab shell (app bar + tab body + floating pill nav).
  Widget _buildShell(BuildContext context) {
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
        // Website parity: the account tab returns to the auth gate on
        // Sign Out (signed-in) and on Sign In / Create Account (guest).
        onBackToGate: () {
          _navKey.currentState?.popUntil((r) => r.isFirst);
          setState(() => _phase = _BootPhase.gate);
        },
      ),
    ];
    // Every tab gets the top bar (website parity: the site's home has the
    // header row with the logo + profile avatar above the hero).
    return Scaffold(
        extendBody: true, // Content scrolls under the frosted nav pill
        // Web top bar on all tabs: logo mark + "nime" left, profile
        // avatar right. Tapping the avatar opens the Who's watching? picker.
        // Liquid Glass (same Settings > Layout toggle as the bottom pill):
        // iOS-style frosted bar — 28px blur, sheen, hairline bottom edge.
        appBar: AppBar(
                // Compact header (user report: the default 56px toolbar
                // felt too tall). 48px still fits the 32px logo mark and
                // 36px avatar; the status-bar / cutout inset above is
                // untouched (Scaffold SafeArea behavior preserved).
                toolbarHeight: 48,
                backgroundColor: _settings.liquidGlassTabBar
                    ? Colors.transparent
                    : GaColors.of(context).surface,
                elevation: 0,
                flexibleSpace: _settings.liquidGlassTabBar
                    ? ClipRect(
                        child: BackdropFilter(
                          filter:
                              ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                          child: Container(
                            decoration: BoxDecoration(
                              color: (_settings.amoledBlack
                                      ? Colors.black
                                      : GaColors.of(context).surface)
                                  .withValues(alpha: 0.55),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white
                                      .withValues(alpha: 0.10),
                                  Colors.white
                                      .withValues(alpha: 0.02),
                                ],
                              ),
                              border: Border(
                                bottom: BorderSide(
                                    color: Colors.white.withValues(
                                        alpha: 0.18),
                                    width: 1),
                              ),
                            ),
                          ),
                        ),
                      )
                    : null,
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
                  IconButton(
                    onPressed: () =>
                        setState(() => _phase = _BootPhase.picker),
                    icon: _profiles.isEmpty
                        ? const CircleAvatar(
                            backgroundColor: Color(0xFFF9A8D4),
                            child: Icon(Icons.person,
                                color: Colors.black87),
                          )
                        : ProfileAvatar(
                            profile: _profiles.firstWhere(
                                (p) => p.id == _profileId,
                                orElse: () => _profiles.first),
                            size: 36),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
        body: screens[_tab],
        // Web bottom nav is a floating pill, not a full-width bar.
        // Liquid Glass Tab Bar (Settings > Layout, default ON like the
        // website): iOS-style frosted pill — 28px blur, translucent fill,
        // specular top edge, vertical sheen. OFF = solid pill. Works in
        // both Dark and AMOLED modes.
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _navPill(context),
        ),
    );
  }

  /// Floating nav pill. Glass variant is iOS-style Liquid Glass: 28px
  /// BackdropFilter blur, translucent fill, specular top edge, sheen
  /// gradient; solid variant is the plain elevated pill.
  Widget _navPill(BuildContext context) {
    final glass = _settings.liquidGlassTabBar;
    final amoled = _settings.amoledBlack;
    // Website `.floating-pill-nav` proportions: pill padding 8px,
    // tabs padding 8px 14px, 22px icons, 11px/600 labels, 3px gap.
    final tabs = Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          for (int i = 0; i < 5; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => setState(() => _tab = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 2, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: i == _tab
                        ? const Color(0xFF303030)
                        : Colors.transparent,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        [
                          Icons.home,
                          Icons.search,
                          Icons.calendar_month,
                          Icons.library_books,
                          Icons.settings,
                        ][i],
                        size: 22,
                        color: i == _tab
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade400,
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          [
                            'Home',
                            'Search',
                            'Calendar',
                            'Library',
                            'Settings',
                          ][i],
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: i == _tab
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    // iOS-style Liquid Glass: strong blur + translucent fill + specular
    // top edge (light catching the glass) + vertical sheen gradient.
    // OFF = solid elevated pill.
    final decoration = BoxDecoration(
      color: glass
          ? (amoled
              ? Colors.black.withValues(alpha: 0.55)
              : GaColors.of(context).field.withValues(alpha: 0.55))
          : (amoled ? Colors.black : const Color(0xFF1E1E1E)),
      borderRadius: BorderRadius.circular(32),
      border: glass
          ? Border(
              top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.28), width: 1),
              left: BorderSide(
                  color: Colors.white.withValues(alpha: 0.10), width: 1),
              right: BorderSide(
                  color: Colors.white.withValues(alpha: 0.10), width: 1),
              bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06), width: 1),
            )
          : Border.all(color: Colors.grey.shade800),
      gradient: glass
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.10),
                Colors.white.withValues(alpha: 0.02),
              ],
            )
          : null,
      // Shadow: website parity (`.floating-pill-nav` =
      // `0 10px 32px rgba(0,0,0,0.55)`) — downward-only. The previous
      // zero-offset blur spread 16px in ALL directions, painting a dark
      // halo above the pill that read as a second strip behind it.
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.55),
          blurRadius: 32,
          offset: const Offset(0, 10),
        )
      ],
    );
    final pill = Container(decoration: decoration, child: tabs);
    if (!glass) return pill;
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: pill,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manage Profiles sheet: rename / delete profiles from the real store.
// The primary (first) profile cannot be deleted, like the website.
// ---------------------------------------------------------------------------
class _ManageProfilesSheet extends StatelessWidget {
  const _ManageProfilesSheet(
      {required this.account,
      required this.profiles,
      required this.activeId,
      required this.onChanged});
  final String account;
  final List<Profile> profiles;
  final String activeId;
  final Future<void> Function() onChanged;

  Future<void> _rename(BuildContext context, Profile p) async {
    final c = TextEditingController(text: p.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: GaColors.of(context).field,
        title: const Text('Rename profile'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 20,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Profile name',
            hintStyle: TextStyle(color: Color(0xFF6B7280)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.of(dCtx).pop(c.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != p.name) {
      final updated = profiles
          .map((e) => e.id == p.id
              ? Profile(
                  id: e.id,
                  name: result,
                  color: e.color,
                  avatarName: e.avatarName,
                  avatarUrl: e.avatarUrl)
              : e)
          .toList();
      await Store.saveProfiles(account, updated);
      await onChanged();
    }
  }

  Future<void> _delete(BuildContext context, Profile p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: GaColors.of(context).field,
        title: Text('Delete "${p.name}"?'),
        content: const Text(
            'Its local library, watch history and settings will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dCtx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dCtx).pop(true),
              child: const Text('Delete',
                  style: TextStyle(color: Color(0xFFF87171)))),
        ],
      ),
    );
    if (confirm == true) {
      final updated = profiles.where((e) => e.id != p.id).toList();
      await Store.saveProfiles(account, updated);
      final active = await Store.activeProfile(account);
      if (active == p.id) {
        await Store.setActiveProfile(
            account, updated.isNotEmpty ? updated.first.id : '');
      }
      await onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
                child: SizedBox(
                    width: 40,
                    height: 4,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: Color(0xFF444444),
                            borderRadius: BorderRadius.all(
                                Radius.circular(2)))))),
            const SizedBox(height: 12),
            const Text('Manage Profiles',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: profiles.length,
                itemBuilder: (_, i) {
                  final p = profiles[i];
                  final isPrimary = i == 0;
                  final isActive = p.id == activeId;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: GaColors.of(context).card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        ProfileAvatar(profile: p, size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(p.name,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              if (isPrimary || isActive)
                                Text(
                                    [
                                      if (isPrimary) 'Primary',
                                      if (isActive) 'Active'
                                    ].join(' · '),
                                    style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit,
                              color: Colors.white70, size: 20),
                          onPressed: () => _rename(context, p),
                        ),
                        if (!isPrimary)
                          IconButton(
                            icon: const Icon(Icons.delete,
                                color: Color(0xFFF87171), size: 20),
                            onPressed: () => _delete(context, p),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
