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

  Future<List<Anime>> _safe(Future<List<Anime>> f) async {
    try {
      return await f;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _safe(AniList.trending()),
        _safe(AniList.popularThisSeason()),
        _safe(AniList.upcomingNextSeason()),
        _safe(AniList.popular()),
        _safe(AniList.topRated()),
        _safe(AniList.topMovies()),
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
        final popularThisSeason = snap.data![1] as List<Anime>;
        final upcoming = snap.data![2] as List<Anime>;
        final popular = snap.data![3] as List<Anime>;
        final topRated = snap.data![4] as List<Anime>;
        final topMovies = snap.data![5] as List<Anime>;
        final local = snap.data![6] as List<LibraryEntry>;
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
                                  // Web hero chips: first genres, small
                                  // dark chips, exactly like the web.
                                  if (a.genres.isNotEmpty)
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        for (final g in a.genres.take(3))
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.black45,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: Colors.white24),
                                            ),
                                            child: Text(g,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.white)),
                                          ),
                                      ],
                                    ),
                                  const SizedBox(height: 6),
                                  Text(
                                    [
                                      if (a.score != null)
                                        '★ ${(a.score! / 10).toStringAsFixed(1)}',
                                      if (a.format.isNotEmpty) a.format,
                                      if (a.status.isNotEmpty) a.status,
                                      if (a.year != null) '${a.year}',
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
                                  Row(
                                    children: [
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: Colors.black,
                                        ),
                                        onPressed: () => openDetails(context,
                                            anime: a,
                                            profileId: widget.profileId,
                                            settings: widget.settings,
                                            onMarkWatched:
                                                widget.onMarkWatched),
                                        child: const Text('Details'),
                                      ),
                                      const SizedBox(width: 10),
                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          side: const BorderSide(
                                              color: Colors.white38),
                                          backgroundColor:
                                              const Color(0x24FFFFFF),
                                        ),
                                        // My List is a post-skeleton
                                        // feature: labelled placeholder,
                                        // not a silent no-op.
                                        onPressed: () =>
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'My List comes after the skeleton phase.'),
                                          ),
                                        ),
                                        child: const Text('+ My List'),
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
                  // Web rail order. A rail that failed to load is
                  // skipped (empty list), never filled with fake data.
                  if (trending.isNotEmpty)
                    _rail('Trending Now', trending),
                  if (popularThisSeason.isNotEmpty)
                    _rail('Popular This Season', popularThisSeason),
                  if (upcoming.isNotEmpty)
                    _rail('Upcoming Next Season', upcoming),
                  if (popular.isNotEmpty)
                    _rail('All Time Popular', popular),
                  if (topRated.isNotEmpty)
                    _rail('Top 100 Anime', topRated),
                  if (topMovies.isNotEmpty)
                    _rail('Top 100 Movies', topMovies),
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
        // Web search bar: rounded dark field + filter button on the
        // right. Filter is a skeleton placeholder in this phase.
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
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(16),
              ),
              child: IconButton(
                icon: const Icon(Icons.tune),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Filter comes after the skeleton phase.'),
                  ),
                ),
              ),
            ),
          ],
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

  DateTime _mondayOfWeek(int offset) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return monday.add(Duration(days: 7 * offset));
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
    final from = monday.millisecondsSinceEpoch ~/ 1000;
    final to = monday.add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000;
    return FutureBuilder<List<Anime>>(
      future: AniList.airing(from: from, to: to),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Calendar failed: ${snap.error}'));
        }
        final items = snap.data!;
        final dayItems = items.where((a) {
          if (a.airingAt == null) return false;
          final d = DateTime.fromMillisecondsSinceEpoch(a.airingAt! * 1000);
          return DateTime(d.year, d.month, d.day) == selected;
        }).toList()
          ..sort((a, b) => (a.airingAt ?? 0).compareTo(b.airingAt ?? 0));
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
                  onTap: () => openDetails(context,
                      anime: a,
                      profileId: widget.profileId,
                      settings: widget.settings,
                      onMarkWatched: widget.onMarkWatched),
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
            const SizedBox(height: 16),
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
    final watching =
        _entries.where((e) => e.status == 'CURRENT' || e.status == 'REPEATING').length;
    final completed = _entries.where((e) => e.status == 'COMPLETED').length;
    final filtered = _statusFilter == 'All'
        ? _entries
        : _statusFilter == 'Watching'
            ? _entries
                .where((e) =>
                    e.status == 'CURRENT' || e.status == 'REPEATING')
                .toList()
            : _entries.where((e) => e.status == 'COMPLETED').toList();
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
        const Text('Library',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
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
            ),
            const SizedBox(width: 8),
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
              pill('All · ${_entries.length}', _statusFilter == 'All',
                  () => setState(() => _statusFilter = 'All')),
              const SizedBox(width: 8),
              pill('Watching · $watching', _statusFilter == 'Watching',
                  () => setState(() => _statusFilter = 'Watching')),
              const SizedBox(width: 8),
              pill('Completed · $completed', _statusFilter == 'Completed',
                  () => setState(() => _statusFilter = 'Completed')),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
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
                        final a = await AniList.details(e.anilistId!);
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


Widget _settingGroup({
  required IconData icon,
  required String title,
  required String subtitle,
  required List<Widget> children,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF222222),
      borderRadius: BorderRadius.circular(16),
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade400)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
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
        const Text('Settings',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _settingGroup(
          icon: Icons.person,
          title: 'Account',
          subtitle: 'Profile, sign in, cloud sync',
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
          ],
        ),
        _settingGroup(
          icon: Icons.sync,
          title: 'Tracking',
          subtitle: 'AniList, MyAnimeList, Simkl',
          children: [
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
          ],
        ),
        _settingGroup(
          icon: Icons.grid_view,
          title: 'Layout',
          subtitle: 'Theme, hero, rails, detail pages',
          children: const [
            Text(
              'Layout options come after the skeleton phase. '
              'This card is a placeholder, not a setting yet.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        _settingGroup(
          icon: Icons.add,
          title: 'Addon',
          subtitle: 'Install and manage addons',
          children: [
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
          ],
        ),
        _settingGroup(
          icon: Icons.play_circle,
          title: 'Playback',
          subtitle: 'Player, subtitles, and auto-play',
          children: [
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
          ],
        ),
        _settingGroup(
          icon: Icons.info,
          title: 'About & Credits',
          subtitle: 'Version, credits, and links',
          children: const [
            Text(
              'GAnime Android — test/full port in progress. '
              'Web app at ganime.pages.dev is untouched by this app.',
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 12),
            Text('Made with ♥ by Isolated',
                style: TextStyle(fontSize: 15)),
            SizedBox(height: 4),
            Text('GAnime 0.1.0',
                style: TextStyle(fontSize: 15, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 12),
        Text(_msg),
        const SizedBox(height: 24),
      ],
    );
  }
}
