// Home / Search / Calendar / Library / Settings screens.
// Library tabs: Local, AniList, Simkl, MAL. Tracker lists load only
// when the user has connected that tracker in Settings; otherwise the
// tab explains how to connect. MAL is read-only in this app.
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/anilist.dart';
import '../services/kitsu.dart';
import '../services/trackers.dart';
import '../services/firebase_sync.dart';
import '../store.dart';
import '../widgets/anime_card.dart';
import '../widgets/skeletons.dart';
import 'details.dart';
import 'settings/about_screen.dart';
import 'settings/account_screen.dart';
import 'settings/addons_screen.dart';
import 'settings/layout_screen.dart';
import 'settings/playback_screen.dart';
import 'settings/tracking_screen.dart';

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

/// Small dark badge chip used in the hero ("★ 8.4", "TV", ...),
/// like the web hero's metadata chips.
Widget _heroBadge(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white24),
    ),
    child: Text(text,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
  );
}

class HomeScreen extends StatefulWidget {  final String profileId;
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
  // Home data is fetched ONCE per profile, never on rebuild. The future used
  // to be created inline in build(), so every setState — including the one
  // from onPageChanged on each hero swipe — created a fresh future and the
  // FutureBuilder blanked the whole screen to a spinner.
  late Future<List<dynamic>> _homeFuture;

  @override
  void initState() {
    super.initState();
    _homeFuture = _loadHome();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _homeFuture = _loadHome();
    }
  }

  Future<List<dynamic>> _loadHome() {
    return Future.wait([
      _safe(Kitsu.trending()),
      _safe(Kitsu.popularThisSeason()),
      _safe(Kitsu.upcomingNextSeason()),
      _safe(Kitsu.popular()),
      _safe(Kitsu.topRated()),
      _safe(Kitsu.topMovies()),
      Store.localLibrary(widget.profileId),
    ]);
  }

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
              child: Text('View All',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary)),
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

  Future<List<Anime>> _safe(Future<List<Anime>> f) async {
    try {
      return await f;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    // NOTE: _homeFuture is created once in initState (refreshed only when the
    // profile changes). It must NOT be recreated here: onPageChanged calls
    // setState on every hero swipe, and a fresh future would blank the whole
    // screen to a spinner on every swipe.
    return FutureBuilder<List<dynamic>>(
      future: _homeFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          // Skeleton home: hero + rail placeholders mirroring the real
          // layout (gated by the same Layout settings), not a spinner.
          final ls = widget.settings;
          final railTitles = <String>[
            if (ls.railTrending) 'Trending Now',
            if (ls.railPopularSeason) 'Popular This Season',
            if (ls.railUpcoming) 'Upcoming Next Season',
            if (ls.railAllTime) 'All Time Popular',
            if (ls.railTop100) 'Top 100 Anime',
            if (ls.railTopMovies) 'Top 100 Movies',
          ];
          return ListView(
            children: [
              if (ls.showHero) skeletonHero(),
              for (final t in railTitles) skeletonRail(title: t),
            ],
          );
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load AniList: ${snap.error}'));
        }
        final trending = snap.data![0] as List<Anime>;
        final popularThisSeason = snap.data![1] as List<Anime>;
        final upcoming = snap.data![2] as List<Anime>;
        final popular = snap.data![3] as List<Anime>;
        final topRated = snap.data![4] as List<Anime>;
        final topMovies = snap.data![5] as List<Anime>;
        final local = snap.data![6] as List<LibraryEntry>;
        final cw = local.where((e) => e.progress > 0).toList();
        final heroItems = trending.take(4).toList();
        // Layout settings (Settings > Layout) gate every Home section.
        final ls = widget.settings;
        final rails = <Widget>[
          if (ls.railTrending && trending.isNotEmpty)
            _rail('Trending Now', trending),
          if (ls.railPopularSeason && popularThisSeason.isNotEmpty)
            _rail('Popular This Season', popularThisSeason),
          if (ls.railUpcoming && upcoming.isNotEmpty)
            _rail('Upcoming Next Season', upcoming),
          if (ls.railAllTime && popular.isNotEmpty)
            _rail('All Time Popular', popular),
          if (ls.railTop100 && topRated.isNotEmpty)
            _rail('Top 100 Anime', topRated),
          if (ls.railTopMovies && topMovies.isNotEmpty)
            _rail('Top 100 Movies', topMovies),
        ];
        final showHero = ls.showHero && heroItems.isNotEmpty;
        final showCw = ls.showContinueWatching && cw.isNotEmpty;
        return ListView(
          children: [
            // Hero carousel, like the web home: rounded card (margin 14,
            // radius 20, border #333333), banner art with bottom shade,
            // title + romaji + genre chips + badge chips + Details/My List
            // pill buttons + dots. No kicker, no synopsis — web shows none.
            if (showHero)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: SizedBox(
                  height: 480,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF333333)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(19),
                      child: Stack(
                        children: [
                          PageView.builder(
                            controller: _heroPage,
                            itemCount: heroItems.length,
                            onPageChanged: (i) =>
                                setState(() => _heroIndex = i),
                            itemBuilder: (_, i) {
                              final a = heroItems[i];
                              final art =
                                  a.banner.isNotEmpty ? a.banner : a.cover;
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (art.isNotEmpty)
                                    Image.network(art,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            Container(
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
                                    bottom: 30,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
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
                                        if (a.romaji.isNotEmpty &&
                                            a.romaji != a.title) ...[
                                          const SizedBox(height: 4),
                                          Text(a.romaji,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      Color(0xFFB3B3B3))),
                                        ],
                                        const SizedBox(height: 10),
                                        // Web hero chips: first 3 genres,
                                        // translucent white pill chips.
                                        if (a.genres.isNotEmpty)
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              for (final g
                                                  in a.genres.take(3))
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            999),
                                                    border: Border.all(
                                                        color:
                                                            Colors.white24),
                                                  ),
                                                  child: Text(g,
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              Colors.white)),
                                                ),
                                            ],
                                          ),
                                        const SizedBox(height: 10),
                                        // Badge chips, like the web hero:
                                        // "★ 8.4 · FORMAT · STATUS · YEAR".
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            if (a.score != null)
                                              _heroBadge(
                                                  '★ ${(a.score! / 10).toStringAsFixed(1)}'),
                                            if (a.format.isNotEmpty)
                                              _heroBadge(a.format),
                                            if (a.status.isNotEmpty)
                                              _heroBadge(a.status),
                                            if (a.year != null)
                                              _heroBadge('${a.year}'),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton(
                                                style:
                                                    ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.white,
                                                  foregroundColor:
                                                      Colors.black,
                                                  shape:
                                                      RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            999),
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 12),
                                                ),
                                                onPressed: () => openDetails(
                                                    context,
                                                    anime: a,
                                                    profileId:
                                                        widget.profileId,
                                                    settings:
                                                        widget.settings,
                                                    onMarkWatched: widget
                                                        .onMarkWatched),
                                                child: const Text('Details',
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700)),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: OutlinedButton(
                                                style:
                                                    OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      Colors.white,
                                                  side: const BorderSide(
                                                      color:
                                                          Colors.white24),
                                                  shape:
                                                      RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            999),
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 12),
                                                ),
                                                // My List is a post-skeleton
                                                // feature: labelled
                                                // placeholder, not a silent
                                                // no-op.
                                                onPressed: () =>
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        'My List comes after the skeleton phase.'),
                                                  ),
                                                ),
                                                child: const Text('+ My List',
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 10,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (int i = 0; i < heroItems.length; i++)
                                  Container(
                                    margin: const EdgeInsets.only(right: 7),
                                    width: i == _heroIndex ? 8 : 6,
                                    height: i == _heroIndex ? 8 : 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: i == _heroIndex
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Colors.white.withValues(alpha: 0.35),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Continue Watching, only when there is local progress
                  // (web hides the section when empty, same here).
                  if (showCw) ...[
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
                                                Theme.of(context)
                                                    .colorScheme
                                                    .primary,
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
                  // Web rail order. A rail that failed to load is
                  // skipped (empty list), never filled with fake data.
                  // Each rail also has a Layout toggle in Settings.
                  ...rails,
                  if (!showHero && !showCw && rails.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          'Everything is hidden — turn sections back on in Settings > Layout.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
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
  bool _searched = false;
  String? _error;
  List<String> _allGenres = [];

  // Filters (null/empty = Any).
  final Set<String> _genres = {};
  int? _year;
  String? _subtype; // TV | movie | OVA | ONA | special
  String? _status; // current | finished | upcoming
  String? _sort; // ratingRank | -userCount | -startDate
  String? _season; // winter | spring | summer | fall (requires _year)

  @override
  void initState() {
    super.initState();
    Kitsu.genreList().then((g) {
      if (mounted) setState(() => _allGenres = g);
    });
  }

  int get _activeFilterCount =>
      _genres.length +
      (_year != null ? 1 : 0) +
      (_season != null ? 1 : 0) +
      (_subtype != null ? 1 : 0) +
      (_status != null ? 1 : 0) +
      (_sort != null ? 1 : 0);

  bool get _hasFilters => _activeFilterCount > 0;

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty && !_hasFilters) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Kitsu.search(
        q,
        genres: _genres.isEmpty ? null : _genres.toList(),
        year: _year,
        season: _season,
        subtype: _subtype,
        status: _status,
        sort: _sort,
      );
      setState(() {
        _results = r;
        _searched = true;
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
    setState(() => _loading = false);
  }

  Future<void> _openFilters() async {
    // Local mutable copies; committed to state only on Apply.
    final genres = Set<String>.of(_genres);
    int? year = _year;
    String? season = _season;
    String? subtype = _subtype;
    String? status = _status;
    String? sort = _sort;
    // Genres start collapsed (compact); expand to see the full grid.
    bool genresExpanded = false;
    // Season result counts for the picked year (null = not loaded yet).
    Map<String, int>? seasonCounts;
    // Refresh hook into the sheet's StatefulBuilder; nulled when the
    // sheet closes so late count fetches can't touch a dead sheet.
    void Function(void Function())? refresh;
    void loadSeasonCounts(int y) {
      seasonCounts = null;
      refresh?.call(() {});
      Kitsu.seasonCounts(y).then((m) {
        seasonCounts = m;
        refresh?.call(() {});
      });
    }
    if (year != null) loadSeasonCounts(year);
    String seasonLabel(String s) {
      final name = {
        'winter': 'Winter',
        'spring': 'Spring',
        'summer': 'Summer',
        'fall': 'Fall'
      }[s]!;
      final c = seasonCounts?[s];
      return (c != null && c >= 0) ? '$name $c' : name;
    }
    final years = List.generate(27, (i) => DateTime.now().year - i);
    const formatLabels = {
      'TV': 'TV',
      'movie': 'Movie',
      'OVA': 'OVA',
      'ONA': 'ONA',
      'special': 'Special',
    };
    const statusLabels = {
      'current': 'Airing',
      'finished': 'Finished',
      'upcoming': 'Upcoming',
    };
    const sortLabels = {
      'ratingRank': 'Top rated',
      '-userCount': 'Most popular',
      '-startDate': 'Newest',
    };
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          refresh = setSheet;
          return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade700,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Filters',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                // Genres: collapsible (Maximize/Minimize). Collapsed shows
                // only the selected chips so the section takes little space.
                InkWell(
                  onTap: () =>
                      setSheet(() => genresExpanded = !genresExpanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Text('Genres',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        if (genres.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${genres.length}',
                                style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                        const Spacer(),
                        Text(genresExpanded ? 'Minimize' : 'Maximize',
                            style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        Icon(
                          genresExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_allGenres.isEmpty)
                  const Text('Loading genres…',
                      style: TextStyle(color: Colors.grey))
                else if (!genresExpanded)
                  genres.isEmpty
                      ? const Text('No genres selected.',
                          style: TextStyle(
                              color: Colors.grey, fontSize: 12))
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: genres
                              .map((g) => FilterChip(
                                    label: Text(g),
                                    selected: true,
                                    onSelected: (_) =>
                                        setSheet(() => genres.remove(g)),
                                    selectedColor: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    checkmarkColor: Colors.black,
                                  ))
                              .toList(),
                        )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allGenres
                        .map((g) => FilterChip(
                              label: Text(g),
                              selected: genres.contains(g),
                              onSelected: (v) => setSheet(() {
                                if (v) {
                                  genres.add(g);
                                } else {
                                  genres.remove(g);
                                }
                              }),
                              selectedColor:
                                  Theme.of(context).colorScheme.primary,
                              checkmarkColor: Colors.black,
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 16),
                // Season: needs a year (Kitsu requires seasonYear + season
                // together), so the pills stay disabled until one is picked.
                Row(
                  children: [
                    const Text('Season',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    if (season != null && year != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                            '${{
                              'winter': 'Winter',
                              'spring': 'Spring',
                              'summer': 'Summer',
                              'fall': 'Fall'
                            }[season]!} $year',
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (year == null)
                  const Text('Select a Year below to pick a season.',
                      style: TextStyle(color: Colors.grey, fontSize: 12))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _seasonPill('Any', season == null,
                          () => setSheet(() => season = null)),
                      for (final s in const [
                        'winter',
                        'spring',
                        'summer',
                        'fall'
                      ])
                        _seasonPill(seasonLabel(s), season == s,
                            () => setSheet(() => season = s)),
                    ],
                  ),
                const SizedBox(height: 16),
                _filterDropdown<int?>(
                    'Year', year, [null, ...years], (v) => v == null ? 'Any' : '$v',
                    (v) => setSheet(() {
                          year = v;
                          if (v == null) {
                            // Season needs a year; drop it with the year.
                            season = null;
                            seasonCounts = null;
                          } else {
                            loadSeasonCounts(v);
                          }
                        })),
                _filterDropdown<String?>(
                    'Format',
                    subtype,
                    [null, ...formatLabels.keys],
                    (v) => v == null ? 'Any' : formatLabels[v]!,
                    (v) => setSheet(() => subtype = v)),
                _filterDropdown<String?>(
                    'Status',
                    status,
                    [null, ...statusLabels.keys],
                    (v) => v == null ? 'Any' : statusLabels[v]!,
                    (v) => setSheet(() => status = v)),
                _filterDropdown<String?>(
                    'Sort by',
                    sort,
                    [null, ...sortLabels.keys],
                    (v) => v == null ? 'Relevance' : sortLabels[v]!,
                    (v) => setSheet(() => sort = v)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setSheet(() {
                          genres.clear();
                          year = null;
                          season = null;
                          seasonCounts = null;
                          subtype = null;
                          status = null;
                          sort = null;
                        }),
                        child: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          setState(() {
                            _genres
                              ..clear()
                              ..addAll(genres);
                            _year = year;
                            _season = season;
                            _subtype = subtype;
                            _status = status;
                            _sort = sort;
                          });
                          _search();
                        },
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
    refresh = null;
  }

  /// Season pill for the filter sheet. Counts are honest live numbers from
  /// Kitsu (meta.count); a failed fetch just shows the season name.
  Widget _seasonPill(String label, bool selected, VoidCallback onTap) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent : const Color(0xFF222222),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? Colors.transparent : Colors.grey.shade700),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _filterDropdown<T>(
      String label, T value, List<T> options, String Function(T) labelOf,
      ValueChanged<T> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF222222),
                  items: options
                      .map((o) => DropdownMenuItem<T>(
                            value: o,
                            child: Text(labelOf(o)),
                          ))
                      .toList(),
                  onChanged: (v) => onChanged(v as T),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Web search bar: rounded dark field + filter button on the right.
        // The filter button opens a real filter sheet (genre/year/format/
        // status/sort); a badge shows the active filter count.
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                decoration: InputDecoration(
                  hintText: 'Search anime...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xFF222222),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 10),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.tune),
                    onPressed: _openFilters,
                  ),
                ),
                if (_activeFilterCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$_activeFilterCount',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.all(16),
            child: skeletonPosterGrid(count: 9),
          ),
        if (_error != null) Text('Search failed: $_error'),
        if (!_loading && _error == null && _searched && _results.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
                child: Text('No results found. Try different filters.')),
          ),
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

class CalendarScreen extends StatefulWidget {
  final String profileId;
  final AppSettings settings;
  final Future<void> Function(Anime, int)? onMarkWatched;
  const CalendarScreen(
      {super.key,
      required this.profileId,
      required this.settings,
      this.onMarkWatched});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

String _formatTime(DateTime dt) {
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $ampm';
}

String _monthName(int m) {
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return names[m - 1];
}

String _weekdayShort(int w) {
  const names = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  return names[w - 1];
}

String _weekdayLong(int w) {
  const names = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
  return names[w - 1];
}

String _monthLong(int m) {
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return names[m - 1];
}

class _CalendarScreenState extends State<CalendarScreen> {
  // Week offset from the current week (Monday-start). 0 = this week.
  int _weekOffset = 0;
  DateTime? _selectedDay;

  // Week data cache: offset -> airing items. Each week is fetched at most
  // once per screen lifetime, so switching weeks/days never blanks the
  // header, the week strip, or the whole screen to a loader.
  final Map<int, List<Anime>> _weekCache = {};
  final Set<int> _loadingWeeks = {};
  final Map<int, Object> _weekErrors = {};

  DateTime _mondayOfWeek(int offset) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return monday.add(Duration(days: 7 * offset));
  }

  // Kicks off the fetch for a week if it isn't cached or already loading.
  // Safe to call from build(): it is idempotent and only calls setState
  // when the async fetch completes.
  void _ensureWeekLoaded(int offset) {
    if (_weekCache.containsKey(offset) || _loadingWeeks.contains(offset)) {
      return;
    }
    _loadingWeeks.add(offset);
    final monday = _mondayOfWeek(offset);
    final from = monday.millisecondsSinceEpoch ~/ 1000;
    final to =
        monday.add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000;
    AniList.airing(from: from, to: to).then((items) {
      if (!mounted) return;
      setState(() {
        _weekCache[offset] = items;
        _loadingWeeks.remove(offset);
        _weekErrors.remove(offset);
      });
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() {
        _loadingWeeks.remove(offset);
        _weekErrors[offset] = e;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final monday = _mondayOfWeek(_weekOffset);
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    _selectedDay ??= days.contains(todayDate) ? todayDate : monday;
    final selected = _selectedDay!;
    final weekEnd = monday.add(const Duration(days: 6));
    final weekLabel =
        '${_monthName(monday.month)} ${monday.day} – ${_monthName(weekEnd.month)} ${weekEnd.day}, ${weekEnd.year}'
        '${_weekOffset == 0 ? ' · This week' : _weekOffset == 1 ? ' · Next week' : _weekOffset == -1 ? ' · Last week' : ''}';
    // Header, week arrows and the day strip always stay visible. Loading
    // and errors are scoped to the episode list area below; tapping a day
    // pill only filters the already-cached week data, never refetches.
    _ensureWeekLoaded(_weekOffset);
    final items = _weekCache[_weekOffset];
    final weekError = _weekErrors[_weekOffset];
    final dayItems = items == null
        ? const <Anime>[]
        : (items.where((a) {
            if (a.airingAt == null) return false;
            final d = DateTime.fromMillisecondsSinceEpoch(a.airingAt! * 1000);
            return DateTime(d.year, d.month, d.day) == selected;
          }).toList()
            ..sort((a, b) => (a.airingAt ?? 0).compareTo(b.airingAt ?? 0)));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
            const Text('Anime Release Calendar',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF222222), shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() {
                      _weekOffset--;
                      _selectedDay = null;
                    }),
                  ),
                ),
                Expanded(
                  child: Text(weekLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF222222), shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() {
                      _weekOffset++;
                      _selectedDay = null;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final d in days)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedDay = d),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF222222),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: d == selected
                                ? Colors.white
                                : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(_weekdayShort(d.weekday),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: d == selected
                                        ? Colors.white
                                        : Colors.grey.shade500)),
                            const SizedBox(height: 4),
                            Text('${d.day}',
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '${_weekdayLong(selected.weekday).toUpperCase()}, '
              '${_monthLong(selected.month).toUpperCase()} ${selected.day} '
              '· LIVE FROM ANILIST',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: Colors.grey.shade400),
            ),
            const SizedBox(height: 12),
            // Episode list area: loading / error state lives here, never
            // full-screen. Day-pill taps filter the cached week instantly.
            if (weekError != null && items == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Text('Calendar failed: $weekError',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(() {
                        _weekErrors.remove(_weekOffset);
                      }),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (items == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: skeletonCalendarRows(count: 4),
              )
            else ...[
              if (dayItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No releases on this day.'),
                ),
              for (final a in dayItems)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  // Calendar entries carry AniList ids; resolve to the Kitsu
                  // catalogue entry so episodes, stream ids and tracker
                  // pushes agree. Falls back to the AniList object.
                  onTap: () async {
                    final k = await Kitsu.fromAnilist(a.id);
                    if (!context.mounted) return;
                    openDetails(context,
                        anime: k ?? a,
                        profileId: widget.profileId,
                        settings: widget.settings,
                        onMarkWatched: widget.onMarkWatched);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: a.cover.isNotEmpty
                              ? Image.network(a.cover,
                                  width: 72,
                                  height: 100,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                      width: 72,
                                      height: 100,
                                      color: Colors.grey.shade800))
                              : Container(
                                  width: 72,
                                  height: 100,
                                  color: Colors.grey.shade800,
                                  child: const Icon(Icons.image)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(
                                'EP ${a.nextEpisode ?? '?'}'
                                '${a.airingAt != null ? ' · ${_formatTime(DateTime.fromMillisecondsSinceEpoch(a.airingAt! * 1000))}' : ''}',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade400)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: Colors.grey.shade500),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
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

class _LibraryScreenState extends State<LibraryScreen> {
  // Web tab order: Local, AniList, MAL, Simkl.
  int _tab = 0;
  String _statusFilter = 'All';
  List<LibraryEntry> _entries = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTab();
  }

  Future<void> _loadTab() async {
    final tab = _tab;
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
          final user = (t['malUsername'] as String?) ?? '';
          final client = (t['malClientId'] as String?) ?? '';
          if (user.isEmpty || client.isEmpty) {
            throw Exception(
                'MAL not connected. Go to Settings > Trackers and enter your MAL username + client id. MAL is read-only here.');
          }
          _entries = await Trackers.malLists(user, client);
        } else {
          final client = (t['simklClientId'] as String?) ?? '';
          final token = (t['simklToken'] as String?) ?? '';
          if (client.isEmpty || token.isEmpty) {
            throw Exception(
                'Simkl not connected. Go to Settings > Trackers and complete the Simkl PIN flow.');
          }
          _entries = await Trackers.simklLists(client, token);
        }
      }
    } catch (e) {
      setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    const tabNames = ['Local', 'AniList', 'MAL', 'Simkl'];
    // Status filter mapping: Watching = CURRENT or REPEATING,
    // Plan to Watch = PLANNING, On Hold = PAUSED, Dropped = DROPPED.
    bool matches(String filter, String status) {
      switch (filter) {
        case 'Watching':
          return status == 'CURRENT' || status == 'REPEATING';
        case 'Completed':
          return status == 'COMPLETED';
        case 'Plan to Watch':
          return status == 'PLANNING';
        case 'On Hold':
          return status == 'PAUSED';
        case 'Dropped':
          return status == 'DROPPED';
        default:
          return true;
      }
    }

    int count(String filter) => filter == 'All'
        ? _entries.length
        : _entries.where((e) => matches(filter, e.status)).length;

    final filtered = _entries
        .where((e) => matches(_statusFilter, e.status))
        .toList();
    const statusFilters = [
      'All',
      'Watching',
      'Completed',
      'Plan to Watch',
      'On Hold',
      'Dropped',
    ];
    Widget pill(String label, bool selected, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : const Color(0xFF222222),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.black : Colors.white)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Library',
                  style:
                      TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            ),
            Container(
              decoration: const BoxDecoration(
                  color: Color(0xFF222222), shape: BoxShape.circle),
              child: IconButton(
                icon: const Icon(Icons.sort),
                // Sort is a post-skeleton feature: labelled placeholder.
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sort comes after the skeleton phase.'),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (int i = 0; i < tabNames.length; i++) ...[
                pill(tabNames[i], i == _tab, () {
                  setState(() {
                    _tab = i;
                    _statusFilter = 'All';
                  });
                  _loadTab();
                }),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Skeleton label from the web UI. This is not a live check
        // of Firebase sync state; real sync status comes later.
        const Text('✓ Synced',
            style: TextStyle(fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (int i = 0; i < statusFilters.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                pill('${statusFilters[i]} · ${count(statusFilters[i])}',
                    _statusFilter == statusFilters[i],
                    () => setState(
                        () => _statusFilter = statusFilters[i])),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: skeletonLibraryRows(count: 5),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!),
          )
        else if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              _tab == 0
                  ? 'Nothing in your Local library yet — Add to Library on any title puts it here.'
                  : 'Nothing here yet.',
              style: const TextStyle(fontSize: 15, color: Colors.grey),
            ),
          )
        else
          for (final e in filtered)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: e.cover.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(e.cover,
                            width: 40,
                            height: 56,
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
                        // Tracker entries carry AniList ids; prefer the Kitsu
                        // catalogue entry so episodes, stream ids and tracker
                        // pushes agree, falling back to AniList details.
                        final a = await Kitsu.fromAnilist(e.anilistId!) ??
                            await AniList.details(e.anilistId!);
                        if (!context.mounted) return;
                        await openDetails(context,
                            anime: a,
                            profileId: widget.profileId,
                            settings: widget.settings,
                            onMarkWatched: widget.onMarkWatched);
                      },
              ),
            ),
      ],
    );
  }
}


// ---------- Settings: top-level menu + sub-screens ----------
// The top level is ONE container card with 6 tappable rows (like the
// web Settings). Each row pushes a sub-screen that holds ONLY that
// group's controls — nothing is expanded inline anymore.

/// One tappable row in the top-level Settings menu card.
class _SettingsMenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SettingsMenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade500, size: 20),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    void open(Widget page) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => page));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Settings',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          child: Column(
            children: [
              _SettingsMenuRow(
                icon: Icons.person,
                title: 'Account',
                subtitle: 'Profile, sign in, cloud sync',
                onTap: () => open(AccountSettingsScreen(
                  account: account,
                  profileId: profileId,
                  settings: settings,
                  onProfile: onProfile,
                  firebase: firebase,
                )),
              ),
              const Divider(height: 1, color: Color(0xFF333333)),
              _SettingsMenuRow(
                icon: Icons.sync,
                title: 'Tracking',
                subtitle: 'AniList, MyAnimeList, Simkl',
                onTap: () => open(TrackingSettingsScreen(
                    settings: settings, onSettings: onSettings)),
              ),
              const Divider(height: 1, color: Color(0xFF333333)),
              _SettingsMenuRow(
                icon: Icons.grid_view,
                title: 'Layout',
                subtitle: 'Theme, hero, rails, detail pages',
                onTap: () => open(LayoutSettingsScreen(
                    settings: settings, onSettings: onSettings)),
              ),
              const Divider(height: 1, color: Color(0xFF333333)),
              _SettingsMenuRow(
                icon: Icons.add,
                title: 'Addon',
                subtitle: 'Install and manage addons',
                onTap: () =>
                    open(AddonSettingsScreen(profileId: profileId)),
              ),
              const Divider(height: 1, color: Color(0xFF333333)),
              _SettingsMenuRow(
                icon: Icons.play_circle_outline,
                title: 'Playback',
                subtitle: 'Player, subtitles, and auto-play',
                onTap: () => open(PlaybackSettingsScreen(
                    settings: settings, onSettings: onSettings)),
              ),
              const Divider(height: 1, color: Color(0xFF333333)),
              _SettingsMenuRow(
                icon: Icons.info_outline,
                title: 'About & Credits',
                subtitle: 'Version, credits, and links',
                onTap: () => open(const AboutSettingsScreen()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        const Center(
          child: Text('Made with ♥ by Isolated\nGAnime 0.1.0',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.6)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

