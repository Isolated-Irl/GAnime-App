// Home / Search / Calendar / Library / Settings screens.
// Library tabs: Local, AniList, Simkl, MAL. Tracker lists load only
// when the user has connected that tracker in Settings; otherwise the
// tab explains how to connect. MAL is read-only in this app.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../services/anilist.dart';
import '../services/trackers.dart';
import '../services/addons.dart';
import '../services/firebase_sync.dart';
import '../store.dart';
import '../widgets/anime_card.dart';
import 'details.dart';
import 'player.dart';

Future<void> openDetails(
  BuildContext context, {
  required Anime anime,
  required String profileId,
  required AppSettings settings,
  Future<void> Function(Anime, int)? onMarkWatched,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DetailsScreen(
        anime: anime,
        profileId: profileId,
        settings: settings,
        onMarkWatched: onMarkWatched,
      ),
    ),
  );
}

class AnimeGrid extends StatelessWidget {
  final List<Anime> items;
  final String profileId;
  final AppSettings settings;
  final Future<void> Function(Anime, int)? onMarkWatched;
  const AnimeGrid({
    super.key,
    required this.items,
    required this.profileId,
    required this.settings,
    this.onMarkWatched,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.62,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => AnimeCard(
        anime: items[i],
        onTap: () => openDetails(context,
            anime: items[i],
            profileId: profileId,
            settings: settings,
            onMarkWatched: onMarkWatched),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final String profileId;
  final AppSettings settings;
  final Future<void> Function(Anime, int)? onMarkWatched;
  const HomeScreen(
      {super.key,
      required this.profileId,
      required this.settings,
      this.onMarkWatched});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _heroPage = PageController();
  int _heroIndex = 0;

  @override
  void dispose() {
    _heroPage.dispose();
    super.dispose();
  }

  void _openSeeAll(String title, List<Anime> items) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              AnimeGrid(
                items: items,
                profileId: widget.profileId,
                settings: widget.settings,
                onMarkWatched: widget.onMarkWatched,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rail(String title, List<Anime> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
            TextButton(
              onPressed: () => _openSeeAll(title, items),
              child: const Text('View All',
                  style: TextStyle(color: Color(0xFF14B8A6))),
            ),
          ],
        ),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => SizedBox(
              width: 120,
              child: AnimeCard(
                anime: items[i],
                onTap: () => openDetails(context,
                    anime: items[i],
                    profileId: widget.profileId,
                    settings: widget.settings,
                    onMarkWatched: widget.onMarkWatched),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        AniList.trending(),
        AniList.popular(),
        Store.localLibrary(widget.profileId),
      ]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load AniList: ${snap.error}'));
        }
        final trending = snap.data![0] as List<Anime>;
        final popular = snap.data![1] as List<Anime>;
        final local = snap.data![2] as List<LibraryEntry>;
        final cw = local.where((e) => e.progress > 0).toList();
        final heroItems = trending.take(4).toList();
        return ListView(
          children: [
            // Hero carousel, like the web home: banner art, shade,
            // kicker + title + meta + synopsis + View Details + dots.
            if (heroItems.isNotEmpty)
              SizedBox(
                height: 340,
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _heroPage,
                      itemCount: heroItems.length,
                      onPageChanged: (i) => setState(() => _heroIndex = i),
                      itemBuilder: (_, i) {
                        final a = heroItems[i];
                        final art = a.banner.isNotEmpty ? a.banner : a.cover;
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            if (art.isNotEmpty)
                              Image.network(art,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                      color: Colors.grey.shade900))
                            else
                              Container(color: Colors.grey.shade900),
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Color(0xB8000000),
                                  ],
                                  stops: [0.45, 1.0],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 28,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('TRENDING NOW',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 2,
                                          color: Color(0xFF14B8A6))),
                                  const SizedBox(height: 8),
                                  Text(a.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          shadows: [
                                            Shadow(
                                                blurRadius: 10,
                                                color: Colors.black54)
                                          ])),
                                  const SizedBox(height: 6),
                                  Text(
                                    [
                                      if (a.format.isNotEmpty) a.format,
                                      if (a.year != null) '${a.year}',
                                      if (a.score != null)
                                        '★ ${a.score!.toStringAsFixed(0)}%',
                                    ].join(' · '),
                                    style: const TextStyle(
                                        fontSize: 13, color: Color(0xFFECECEC)),
                                  ),
                                  if (a.description.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(a.description,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFFE8E8E8))),
                                  ],
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                    ),
                                    onPressed: () => openDetails(context,
                                        anime: a,
                                        profileId: widget.profileId,
                                        settings: widget.settings,
                                        onMarkWatched: widget.onMarkWatched),
                                    child: const Text('View Details'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    Positioned(
                      left: 16,
                      bottom: 8,
                      child: Row(
                        children: [
                          for (int i = 0; i < heroItems.length; i++)
                            Container(
                              margin: const EdgeInsets.only(right: 7),
                              width: i == _heroIndex ? 18 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: i == _heroIndex
                                    ? const Color(0xFF14B8A6)
                                    : Colors.white54,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Continue Watching, only when there is local progress
                  // (web hides the section when empty, same here).
                  if (cw.isNotEmpty) ...[
                    const Text('CONTINUE WATCHING',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: cw.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final e = cw[i];
                          final total = e.total ?? 0;
                          final done = total > 0 && e.progress >= total;
                          final pct =
                              total > 0 ? e.progress / total : 0.0;
                          final anime = Anime(
                            id: e.anilistId ?? 0,
                            title: e.title,
                            cover: e.cover,
                            episodes: total,
                          );
                          return SizedBox(
                            width: 280,
                            child: InkWell(
                              onTap: () => openDetails(context,
                                  anime: anime,
                                  profileId: widget.profileId,
                                  settings: widget.settings,
                                  onMarkWatched: widget.onMarkWatched),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF222222),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: e.cover.isNotEmpty
                                          ? Image.network(e.cover,
                                              width: 64,
                                              height: 96,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  Container(
                                                      width: 64,
                                                      height: 96,
                                                      color: Colors
                                                          .grey.shade800))
                                          : Container(
                                              width: 64,
                                              height: 96,
                                              color: Colors.grey.shade800,
                                              child: const Icon(
                                                  Icons.play_arrow,
                                                  color: Colors.white)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(e.title,
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Text(
                                            done
                                                ? 'Completed ✓'
                                                : 'EP ${e.progress + 1}'
                                                    '${total > 0 ? ' · ${e.progress}/$total watched' : ''}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    Colors.grey.shade400),
                                          ),
                                          const SizedBox(height: 8),
                                          LinearProgressIndicator(
                                            value: pct,
                                            backgroundColor:
                                                Colors.grey.shade800,
                                            color:
                                                const Color(0xFF14B8A6),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  _rail('Trending Now', trending),
                  _rail('Popular', popular),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class SearchScreen extends StatefulWidget {
  final String profileId;
  final AppSettings settings;
  final Future<void> Function(Anime, int)? onMarkWatched;
  const SearchScreen(
      {super.key,
      required this.profileId,
      required this.settings,
      this.onMarkWatched});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<Anime> _results = [];
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await AniList.search(q);
      setState(() => _results = r);
    } catch (e) {
      setState(() => _error = '$e');
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: _ctrl,
          decoration: InputDecoration(
            hintText: 'Search AniList…',
            suffixIcon: IconButton(
                icon: const Icon(Icons.search), onPressed: _search),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _search(),
        ),
        if (_loading) const Padding(
            padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
        if (_error != null) Text('Search failed: $_error'),
        const SizedBox(height: 12),
        AnimeGrid(
            items: _results,
            profileId: widget.profileId,
            settings: widget.settings,
            onMarkWatched: widget.onMarkWatched),
      ],
    );
  }
}

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Anime>>(
      future: AniList.airing(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Calendar failed: ${snap.error}'));
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return const Center(child: Text('No airing titles in the next 7 days.'));
        }
        final byDay = <int, List<Anime>>{};
        for (final a in items) {
          final day = a.airingAt == null
              ? 0
              : DateTime.fromMillisecondsSinceEpoch(a.airingAt! * 1000).weekday;
          (byDay[day] ??= []).add(a);
        }
        const names = {
          1: 'Monday',
          2: 'Tuesday',
          3: 'Wednesday',
          4: 'Thursday',
          5: 'Friday',
          6: 'Saturday',
          7: 'Sunday',
          0: 'Unknown day',
        };
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final day in byDay.keys)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(names[day] ?? 'Day $day',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  for (final a in byDay[day]!)
                    ListTile(
                      leading: a.cover.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(a.cover,
                                  width: 40, height: 56, fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.image)),
                            )
                          : const Icon(Icons.image),
                      title: Text(a.title),
                      subtitle: Text(
                          'EP ${a.nextEpisode ?? '?'}'
                          '${a.airingAt != null ? ' · ${DateTime.fromMillisecondsSinceEpoch(a.airingAt! * 1000)}' : ''}'),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
          ],
        );
      },
    );
  }
}

class LibraryScreen extends StatefulWidget {
  final String profileId;
  final AppSettings settings;
  final Future<void> Function(Anime, int)? onMarkWatched;
  const LibraryScreen(
      {super.key,
      required this.profileId,
      required this.settings,
      this.onMarkWatched});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<LibraryEntry> _entries = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(_loadTab);
    _loadTab();
  }

  Future<void> _loadTab() async {
    final tab = _tabs.index;
    setState(() {
      _loading = true;
      _error = null;
      _entries = [];
    });
    try {
      if (tab == 0) {
        _entries = await Store.localLibrary(widget.profileId);
      } else {
        final t = await Store.tracker();
        if (tab == 1) {
          final token = (t['anilistToken'] as String?) ?? '';
          final userId = (t['anilistUserId'] as num?)?.toInt();
          if (token.isEmpty || userId == null) {
            throw Exception(
                'AniList not connected. Go to Settings > Trackers and paste your AniList token.');
          }
          _entries = await Trackers.anilistLists(token, userId);
        } else if (tab == 2) {
          final client = (t['simklClientId'] as String?) ?? '';
          final token = (t['simklToken'] as String?) ?? '';
          if (client.isEmpty || token.isEmpty) {
            throw Exception(
                'Simkl not connected. Go to Settings > Trackers and complete the Simkl PIN flow.');
          }
          _entries = await Trackers.simklLists(client, token);
        } else {
          final user = (t['malUsername'] as String?) ?? '';
          final client = (t['malClientId'] as String?) ?? '';
          if (user.isEmpty || client.isEmpty) {
            throw Exception(
                'MAL not connected. Go to Settings > Trackers and enter your MAL username + client id. MAL is read-only here.');
          }
          _entries = await Trackers.malLists(user, client);
        }
      }
    } catch (e) {
      setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Local'),
            Tab(text: 'AniList'),
            Tab(text: 'Simkl'),
            Tab(text: 'MAL'),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!),
                      ),
                    )
                  : _entries.isEmpty
                      ? const Center(child: Text('Nothing here yet.'))
                      : ListView(
                          children: [
                            for (final e in _entries)
                              ListTile(
                                leading: e.cover.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        child: Image.network(e.cover,
                                            width: 40, height: 56,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                const Icon(Icons.image)),
                                      )
                                    : const Icon(Icons.image),
                                title: Text(e.title),
                                subtitle: Text(
                                    '${e.status} • EP ${e.progress}${e.total != null ? '/${e.total}' : ''} • ${e.source}'),
                                onTap: e.anilistId == null
                                    ? null
                                    : () async {
                                        final a = await AniList.details(
                                            e.anilistId!);
                                        if (!context.mounted) return;
                                        await openDetails(context,
                                            anime: a,
                                            profileId: widget.profileId,
                                            settings: widget.settings,
                                            onMarkWatched:
                                                widget.onMarkWatched);
                                      },
                              ),
                          ],
                        ),
        ),
      ],
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final String account;
  final String profileId;
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettings;
  final ValueChanged<String> onProfile;
  final FirebaseSync firebase;
  const SettingsScreen({
    super.key,
    required this.account,
    required this.profileId,
    required this.settings,
    required this.onSettings,
    required this.onProfile,
    required this.firebase,
  });
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Profile> _profiles = [];
  List<AddonRecord> _addons = [];
  final _addonCtrl = TextEditingController();
  final _anilistTokenCtrl = TextEditingController();
  final _simklClientCtrl = TextEditingController();
  final _simklCodeCtrl = TextEditingController();
  final _malUserCtrl = TextEditingController();
  final _malClientCtrl = TextEditingController();
  final _fbApiCtrl = TextEditingController();
  final _fbProjectCtrl = TextEditingController();
  final _fbEmailCtrl = TextEditingController();
  final _fbPassCtrl = TextEditingController();
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final ps = await Store.profiles(widget.account);
    final ads = await Store.addons(widget.profileId);
    final t = await Store.tracker();
    final fb = await Store.firebaseConfig();
    setState(() {
      _profiles = ps;
      _addons = ads;
      _anilistTokenCtrl.text = (t['anilistToken'] as String?) ?? '';
      _simklClientCtrl.text = (t['simklClientId'] as String?) ?? '';
      _malUserCtrl.text = (t['malUsername'] as String?) ?? '';
      _malClientCtrl.text = (t['malClientId'] as String?) ?? '';
      _fbApiCtrl.text = (fb['apiKey'] as String?) ?? '';
      _fbProjectCtrl.text = (fb['projectId'] as String?) ?? '';
    });
  }

  Future<void> _saveSettings(AppSettings s) async {
    await Store.saveSettings(s);
    widget.onSettings(s);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Profiles',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        for (final p in _profiles)
          ListTile(
            title: Text(p.name),
            trailing: p.id == widget.profileId
                ? const Icon(Icons.check)
                : null,
            onTap: () async {
              await Store.setActiveProfile(widget.account, p.id);
              widget.onProfile(p.id);
              setState(() {});
            },
          ),
        TextButton(
          onPressed: () async {
            final ps = List<Profile>.from(_profiles)
              ..add(Profile(
                  id: 'p${DateTime.now().millisecondsSinceEpoch}',
                  name: 'Profile ${_profiles.length + 1}'));
            await Store.saveProfiles(widget.account, ps);
            setState(() => _profiles = ps);
          },
          child: const Text('Add profile'),
        ),
        const Divider(),
        const Text('Playback — audio and subtitle are SEPARATE settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        DropdownButtonFormField<String>(
          initialValue: s.audioLanguage,
          decoration: const InputDecoration(labelText: 'Audio language'),
          items: const [
            DropdownMenuItem(value: 'jpn', child: Text('Japanese (jpn)')),
            DropdownMenuItem(value: 'eng', child: Text('English (eng)')),
            DropdownMenuItem(value: '', child: Text('Auto / device')),
          ],
          onChanged: (v) =>
              _saveSettings(s.copyWith(audioLanguage: v ?? 'jpn')),
        ),
        DropdownButtonFormField<String>(
          initialValue: s.subtitleLanguage,
          decoration: const InputDecoration(labelText: 'Subtitle language'),
          items: const [
            DropdownMenuItem(value: 'eng', child: Text('English (eng)')),
            DropdownMenuItem(value: 'jpn', child: Text('Japanese (jpn)')),
            DropdownMenuItem(value: '', child: Text('None')),
          ],
          onChanged: (v) =>
              _saveSettings(s.copyWith(subtitleLanguage: v ?? 'eng')),
        ),
        SwitchListTile(
          title: const Text('AniSkip enabled'),
          value: s.aniskipEnabled,
          onChanged: (v) => _saveSettings(s.copyWith(aniskipEnabled: v)),
        ),
        SwitchListTile(
          title: const Text('Auto-skip opening'),
          value: s.aniskipAutoOp,
          onChanged: (v) => _saveSettings(s.copyWith(aniskipAutoOp: v)),
        ),
        SwitchListTile(
          title: const Text('Auto-skip ending'),
          value: s.aniskipAutoEd,
          onChanged: (v) => _saveSettings(s.copyWith(aniskipAutoEd: v)),
        ),
        SwitchListTile(
          title: const Text('Show skip buttons'),
          value: s.aniskipShowButton,
          onChanged: (v) => _saveSettings(s.copyWith(aniskipShowButton: v)),
        ),
        SwitchListTile(
          title: const Text('Detect recaps'),
          value: s.aniskipDetectRecap,
          onChanged: (v) =>
              _saveSettings(s.copyWith(aniskipDetectRecap: v)),
        ),
        const Divider(),
        const Text('Player Test',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Text(
            'Opens the media_kit player with a public test video (not a GAnime stream).'),
        FilledButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  anime: const Anime(id: 0, title: 'Player Test'),
                  episode: 1,
                  streams: const [
                    StreamSource(
                      name: 'Big Buck Bunny (test MP4)',
                      url:
                          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
                    ),
                  ],
                  settings: s,
                ),
              ),
            );
          },
          child: const Text('Open Player Test'),
        ),
        const Divider(),
        const Text('Addons — user-installed only',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Text(
            'This app ships with NO stream sources and recommends none. '
            'Paste a Stremio manifest URL you found yourself.'),
        TextField(
          controller: _addonCtrl,
          decoration: const InputDecoration(
              hintText: 'https://…/manifest.json',
              border: OutlineInputBorder()),
        ),
        FilledButton(
          onPressed: () async {
            try {
              final rec =
                  await AddonsService.fetchManifest(_addonCtrl.text);
              final list = List<AddonRecord>.from(_addons);
              if (list.any((a) => a.manifestUrl == rec.manifestUrl)) {
                setState(() => _msg = 'Addon already installed.');
                return;
              }
              list.add(rec);
              await Store.saveAddons(widget.profileId, list);
              setState(() {
                _addons = list;
                _msg = 'Installed: ${rec.name}';
              });
            } catch (e) {
              setState(() => _msg = 'Addon install failed: $e');
            }
          },
          child: const Text('Install addon'),
        ),
        for (final a in _addons)
          ListTile(
            title: Text(a.name),
            subtitle: Text(a.manifestUrl),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                final list =
                    _addons.where((x) => x.id != a.id).toList();
                await Store.saveAddons(widget.profileId, list);
                setState(() => _addons = list);
              },
            ),
          ),
        const Divider(),
        const Text('Trackers',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        TextField(
          controller: _anilistTokenCtrl,
          decoration: const InputDecoration(
              labelText: 'AniList token (paste from PIN page)',
              border: OutlineInputBorder()),
        ),
        TextButton(
          onPressed: () => launchUrl(
              Uri.parse('https://anilist.co/api/v2/oauth/pin'),
              mode: LaunchMode.externalApplication),
          child: const Text('Open AniList PIN page in browser'),
        ),
        FilledButton(
          onPressed: () async {
            final t = await Store.tracker();
            t['anilistToken'] = _anilistTokenCtrl.text.trim();
            try {
              final v = await Trackers.anilistViewer(t['anilistToken']);
              t['anilistUserId'] = v['id'];
              await Store.saveTracker(t);
              setState(() => _msg = 'AniList connected: ${v['name']}');
            } catch (e) {
              setState(() => _msg = 'AniList connect failed: $e');
            }
          },
          child: const Text('Save AniList token'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _simklClientCtrl,
          decoration: const InputDecoration(
              labelText: 'Simkl client id', border: OutlineInputBorder()),
        ),
        TextField(
          controller: _simklCodeCtrl,
          decoration: const InputDecoration(
              labelText: 'Simkl PIN user code (optional)',
              border: OutlineInputBorder()),
        ),
        FilledButton(
          onPressed: () async {
            try {
              if (_simklCodeCtrl.text.trim().isEmpty) {
                final pin = await Trackers.simklStartPin(
                    _simklClientCtrl.text.trim());
                setState(() => _msg =
                    'Simkl PIN: user code ${pin['user_code']}. Enter it on the Simkl site, then paste the code above and tap again.');
              } else {
                final res = await Trackers.simklCheckPin(
                    _simklClientCtrl.text.trim(),
                    _simklCodeCtrl.text.trim());
                final t = await Store.tracker();
                t['simklClientId'] = _simklClientCtrl.text.trim();
                t['simklToken'] = res['access_token'];
                await Store.saveTracker(t);
                setState(() => _msg = 'Simkl connected.');
              }
            } catch (e) {
              setState(() => _msg = 'Simkl failed: $e');
            }
          },
          child: const Text('Simkl PIN / connect'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _malUserCtrl,
          decoration: const InputDecoration(
              labelText: 'MAL username', border: OutlineInputBorder()),
        ),
        TextField(
          controller: _malClientCtrl,
          decoration: const InputDecoration(
              labelText: 'MAL client id', border: OutlineInputBorder()),
        ),
        FilledButton(
          onPressed: () async {
            final t = await Store.tracker();
            t['malUsername'] = _malUserCtrl.text.trim();
            t['malClientId'] = _malClientCtrl.text.trim();
            await Store.saveTracker(t);
            setState(() => _msg = 'MAL saved (read-only list).');
          },
          child: const Text('Save MAL (read-only)'),
        ),
        const Divider(),
        const Text('Firebase sync (optional)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Text(
            'Enter YOUR Firebase project config here on-device. It is never '
            'written into the repo. One doc: users/{uid}.'),
        TextField(
          controller: _fbApiCtrl,
          decoration: const InputDecoration(
              labelText: 'Firebase apiKey', border: OutlineInputBorder()),
        ),
        TextField(
          controller: _fbProjectCtrl,
          decoration: const InputDecoration(
              labelText: 'Firebase projectId', border: OutlineInputBorder()),
        ),
        TextField(
          controller: _fbEmailCtrl,
          decoration:
              const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
        ),
        TextField(
          controller: _fbPassCtrl,
          obscureText: true,
          decoration: const InputDecoration(
              labelText: 'Password', border: OutlineInputBorder()),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: () async {
                try {
                  await widget.firebase
                      .saveConfig(_fbApiCtrl.text.trim(), _fbProjectCtrl.text.trim());
                  await widget.firebase.signIn(
                      _fbEmailCtrl.text.trim(), _fbPassCtrl.text);
                  setState(() => _msg = 'Firebase signed in.');
                } catch (e) {
                  setState(() => _msg = 'Firebase sign-in failed: $e');
                }
              },
              child: const Text('Sign in'),
            ),
            OutlinedButton(
              onPressed: () async {
                try {
                  await widget.firebase
                      .saveConfig(_fbApiCtrl.text.trim(), _fbProjectCtrl.text.trim());
                  await widget.firebase.signUp(
                      _fbEmailCtrl.text.trim(), _fbPassCtrl.text);
                  setState(() => _msg = 'Firebase account created + signed in.');
                } catch (e) {
                  setState(() => _msg = 'Firebase sign-up failed: $e');
                }
              },
              child: const Text('Create account'),
            ),
            OutlinedButton(
              onPressed: () async {
                try {
                  final profiles = await Store.profiles(widget.account);
                  final watched = await Store.allWatched(widget.profileId);
                  final lib = await Store.localLibrary(widget.profileId);
                  final ads = await Store.addons(widget.profileId);
                  final tombs = await Store.tombstones();
                  await widget.firebase.push(
                    account: widget.account,
                    settings: s,
                    profiles: profiles,
                    watched: watched,
                    localLibrary: lib,
                    addons: ads,
                    tombstones: tombs,
                  );
                  setState(() => _msg = 'Sync Now pushed to users/{uid}.');
                } catch (e) {
                  setState(() => _msg = 'Sync failed: $e');
                }
              },
              child: const Text('Sync Now'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(_msg),
        const SizedBox(height: 24),
        const Text(
            'GAnime Android — test/full port in progress. Web app at ganime.pages.dev is untouched by this app.'),
      ],
    );
  }
}
