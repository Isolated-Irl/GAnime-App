// Shared data models for the GAnime Android port.
// Mirrors the web app's concepts, not its code: AniList metadata only,
// local watched state, tracker lists, profiles, and per-profile settings.
// Audio and subtitle preferences are ALWAYS separate settings.
class Anime {
  final int id;
  final String title;
  final String romaji;
  final String cover;
  final String banner;
  final String bannerXL; // coverImage.extraLarge — full-res hero source
  final String description;
  final String format;
  final String status;
  final int? episodes;
  final int? nextEpisode;
  final int? airingAt;
  final double? score;
  final List<String> genres;
  final int? malId;
  // AniList id. The catalogue is AniList-based, so id == anilistId
  // for catalogue entries; tracker/calendar entries carry it explicitly.
  final int? anilistId;
  final int? year;
  final String season;
  final String studio; // main studio name, '' when unknown
  final String trailerId; // YouTube video id, '' when unknown
  final List<String> episodeThumbs; // streamingEpisodes thumbnails, '' when none

  const Anime({
    required this.id,
    required this.title,
    this.romaji = '',
    this.cover = '',
    this.banner = '',
    this.bannerXL = '',
    this.description = '',
    this.format = '',
    this.status = '',
    this.episodes,
    this.nextEpisode,
    this.airingAt,
    this.score,
    this.genres = const [],
    this.malId,
    this.anilistId,
    this.year,
    this.season = '',
    this.studio = '',
    this.trailerId = '',
    this.episodeThumbs = const [],
  });

  factory Anime.fromJson(Map<String, dynamic> j) {
    final t = j['title'] as Map<String, dynamic>? ?? {};
    final img = j['coverImage'] as Map<String, dynamic>? ?? {};
    final next = j['nextAiringEpisode'] as Map<String, dynamic>?;
    String clean(String? s) {
      var t = (s ?? '').replaceAll(RegExp(r'<[^>]*>'), '').trim();
      const entities = {
        '&amp;': '&', '&quot;': '"', '&#039;': "'", '&#39;': "'",
        '&lt;': '<', '&gt;': '>', '&mdash;': '—', '&ndash;': '–',
        '&nbsp;': ' ',
      };
      entities.forEach((k, v) => t = t.replaceAll(k, v));
      return t;
    }
    final tr = j['trailer'] as Map<String, dynamic>?;
    // Main studio only (website parity: edges.find(isMain) || edges[0]).
    String studio = '';
    final edges =
        (j['studios'] as Map<String, dynamic>?)?['edges'] as List?;
    final main = edges
        ?.cast<Map<String, dynamic>?>()
        .firstWhere(
          (e) => e?['isMain'] == true,
          orElse: () =>
              edges.isNotEmpty ? edges.first as Map<String, dynamic>? : null,
        );
    final studioNode = main?['node'] as Map<String, dynamic>?;
    if (studioNode != null) studio = (studioNode['name'] as String?) ?? '';
    return Anime(
      id: (j['id'] as num?)?.toInt() ?? 0,
      title: (t['english'] as String?)?.isNotEmpty == true
          ? t['english'] as String
          : ((t['romaji'] as String?) ?? (t['userPreferred'] as String?) ?? ''),
      romaji: (t['romaji'] as String?) ?? '',
      cover: (img['extraLarge'] as String?) ??
          (img['large'] as String?) ??
          (img['medium'] as String?) ??
          '',
      banner: (j['bannerImage'] as String?) ?? '',
      bannerXL: (img['extraLarge'] as String?) ?? '',
      description: clean(j['description'] as String?),
      format: (j['format'] as String?) ?? '',
      status: (j['status'] as String?) ?? '',
      episodes: (j['episodes'] as num?)?.toInt(),
      nextEpisode: (next?['episode'] as num?)?.toInt(),
      airingAt: (next?['airingAt'] as num?)?.toInt(),
      score: (j['averageScore'] as num?)?.toDouble(),
      genres: ((j['genres'] as List?) ?? []).map((e) => '$e').toList(),
      malId: (j['idMal'] as num?)?.toInt(),
      anilistId: (j['id'] as num?)?.toInt(),
      year: (j['seasonYear'] as num?)?.toInt(),
      season: (j['season'] as String?) ?? '',
      studio: studio,
      episodeThumbs: ((j['streamingEpisodes'] as List?) ?? [])
          .map((e) => (e as Map?)?['thumbnail'] as String? ?? '')
          .toList(),
      trailerId: (tr != null && (tr['site'] as String?) == 'youtube')
          ? (tr['id'] as String?) ?? ''
          : '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'romaji': romaji,
        'cover': cover,
        'banner': banner,
        'bannerXL': bannerXL,
        'description': description,
        'format': format,
        'status': status,
        'episodes': episodes,
        'nextEpisode': nextEpisode,
        'airingAt': airingAt,
        'score': score,
        'genres': genres,
        'malId': malId,
        'year': year,
        'season': season,
        'studio': studio,
        'trailerId': trailerId,
      };

  factory Anime.fromStored(Map<String, dynamic> j) => Anime(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        romaji: (j['romaji'] as String?) ?? '',
        cover: (j['cover'] as String?) ?? '',
        banner: (j['banner'] as String?) ?? '',
        bannerXL: (j['bannerXL'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        format: (j['format'] as String?) ?? '',
        status: (j['status'] as String?) ?? '',
        episodes: (j['episodes'] as num?)?.toInt(),
        nextEpisode: (j['nextEpisode'] as num?)?.toInt(),
        airingAt: (j['airingAt'] as num?)?.toInt(),
        score: (j['score'] as num?)?.toDouble(),
        genres: ((j['genres'] as List?) ?? []).map((e) => '$e').toList(),
        malId: (j['malId'] as num?)?.toInt(),
        year: (j['year'] as num?)?.toInt(),
        season: (j['season'] as String?) ?? '',
        studio: (j['studio'] as String?) ?? '',
        trailerId: (j['trailerId'] as String?) ?? '',
      );

  Anime copyWith({
    int? id,
    String? title,
    String? romaji,
    String? cover,
    String? banner,
    String? bannerXL,
    String? description,
    String? format,
    String? status,
    int? episodes,
    int? nextEpisode,
    int? airingAt,
    double? score,
    List<String>? genres,
    int? malId,
    int? anilistId,
    int? year,
    String? season,
    String? studio,
    String? trailerId,
  }) =>
      Anime(
        id: id ?? this.id,
        title: title ?? this.title,
        romaji: romaji ?? this.romaji,
        cover: cover ?? this.cover,
        banner: banner ?? this.banner,
        bannerXL: bannerXL ?? this.bannerXL,
        description: description ?? this.description,
        format: format ?? this.format,
        status: status ?? this.status,
        episodes: episodes ?? this.episodes,
        nextEpisode: nextEpisode ?? this.nextEpisode,
        airingAt: airingAt ?? this.airingAt,
        score: score ?? this.score,
        genres: genres ?? this.genres,
        malId: malId ?? this.malId,
        anilistId: anilistId ?? this.anilistId,
        year: year ?? this.year,
        season: season ?? this.season,
        studio: studio ?? this.studio,
        trailerId: trailerId ?? this.trailerId,
      );
}

class EpisodeInfo {
  final int number;
  final String title;
  final String still;
  final String overview;
  final int? runtime;
  final String airdate; // ISO date from Kitsu, '' when unknown
  const EpisodeInfo({
    required this.number,
    this.title = '',
    this.still = '',
    this.overview = '',
    this.runtime,
    this.airdate = '',
  });
}

class LibraryEntry {
  final String key; // anilist_<id> / simkl_<id> / mal_<id>
  final String source; // anilist | simkl | mal | local
  final int? anilistId;
  final String title;
  final String cover;
  final String status; // CURRENT | COMPLETED | PAUSED | DROPPED | PLANNING
  final int progress;
  final int? total;
  final double? score;
  /// Seconds-since-epoch of the last list update (AniList MediaList.updatedAt).
  /// Drives the website-parity library sort (default UPDATED_DESC).
  final int updatedAt;
  const LibraryEntry({
    required this.key,
    required this.source,
    required this.title,
    this.cover = '',
    this.status = 'CURRENT',
    this.progress = 0,
    this.total,
    this.score,
    this.anilistId,
    this.updatedAt = 0,
  });
}

class Profile {
  final String id;
  final String name;
  final int color;
  // Avatar: built-in catalog name (e.g. 'Bram') or custom URL.
  // Migration-safe: old profiles default to the catalog's first avatar.
  final String avatarName;
  final String avatarUrl;
  const Profile(
      {required this.id,
      required this.name,
      this.color = 0xFF22C55E,
      this.avatarName = 'Bram',
      this.avatarUrl = ''});
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'avatarName': avatarName,
        'avatarUrl': avatarUrl,
      };
  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: '${j['id']}',
        name: (j['name'] as String?) ?? 'Profile',
        color: (j['color'] as num?)?.toInt() ?? 0xFF22C55E,
        avatarName: (j['avatarName'] as String?) ?? 'Bram',
        avatarUrl: (j['avatarUrl'] as String?) ?? '',
      );
}

/// App settings. NOTE: audio and subtitle are separate, never merged.
class AppSettings {
  final String audioLanguage; // e.g. 'jpn' — empty = device / auto
  final String subtitleLanguage; // e.g. 'eng' — empty = none
  final bool aniskipEnabled;
  final bool aniskipAutoOp;
  final bool aniskipAutoEd;
  final bool aniskipShowButton;
  final bool aniskipDetectRecap;
  // Layout toggles (Settings > Layout). All default true.
  final bool showHero;
  final bool showContinueWatching;
  final bool railTrending;
  final bool railPopularSeason;
  final bool railUpcoming;
  final bool railAllTime;
  final bool railTop100;
  final bool railTopMovies;
  final bool gridView; // Search/Filter results view: true = grid, false = list
  // --- Playback (Settings > Playback) ---
  final bool autoFullscreenOnPlay;
  final bool swipeToSeek;
  final bool privateViewing;
  final double seekInterval; // seconds
  final String secondaryAudioLanguage; // '' = none
  final bool showOnlyPreferredLanguages;
  final double subtitleSize; // sp
  final double subtitleBackgroundTint; // 0..1
  final bool hardwareDecoding;
  // --- Tracking: continue-watching data source ('cloud' | 'tracked') ---
  final String continueWatchingSource;
  // --- Layout (Settings > Layout), website parity ---
  final String theme; // white|crimson|ocean|violet|emerald|amber|rose
  final bool amoledBlack;
  final String navBarPosition; // 'bottom'
  final bool liquidGlassTabBar;
  final bool hideStatusBar;
  final String heroStyle; // 'full_bleed'
  final bool heroTrailerAutoplay;
  final bool heroTrailerSound;
  final String heroTrailerDelay; // 'Instant'
  final bool dynamicBackground;
  final bool catalogAccentUnderline;
  final bool budgetRevenueOnDetails;
  final bool iconActionRowOnDetails;
  // --- Details: episode list layout ('detailed' | 'minimum') ---
  final String episodeLayout;
  const AppSettings({
    this.audioLanguage = 'jpn',
    this.subtitleLanguage = 'eng',
    this.aniskipEnabled = true,
    this.aniskipAutoOp = false,
    this.aniskipAutoEd = false,
    this.aniskipShowButton = true,
    this.aniskipDetectRecap = true,
    this.showHero = true,
    this.showContinueWatching = true,
    this.railTrending = true,
    this.railPopularSeason = true,
    this.railUpcoming = true,
    this.railAllTime = true,
    this.railTop100 = true,
    this.railTopMovies = true,
    this.gridView = true,
    this.autoFullscreenOnPlay = true,
    this.swipeToSeek = true,
    this.privateViewing = false,
    this.seekInterval = 5,
    this.secondaryAudioLanguage = '',
    this.showOnlyPreferredLanguages = false,
    this.subtitleSize = 18,
    this.subtitleBackgroundTint = 0.5,
    this.hardwareDecoding = true,
    this.continueWatchingSource = 'cloud',
    this.theme = 'white',
    this.amoledBlack = false,
    this.navBarPosition = 'bottom',
    this.liquidGlassTabBar = true,
    this.hideStatusBar = false,
    this.heroStyle = 'full_bleed',
    this.heroTrailerAutoplay = true,
    this.heroTrailerSound = false,
    this.heroTrailerDelay = 'Instant',
    this.dynamicBackground = false,
    this.catalogAccentUnderline = false,
    this.budgetRevenueOnDetails = true,
    this.iconActionRowOnDetails = true,
    this.episodeLayout = 'detailed',
  });
  Map<String, dynamic> toJson() => {
        'audioLanguage': audioLanguage,
        'subtitleLanguage': subtitleLanguage,
        'aniskipEnabled': aniskipEnabled,
        'aniskipAutoOp': aniskipAutoOp,
        'aniskipAutoEd': aniskipAutoEd,
        'aniskipShowButton': aniskipShowButton,
        'aniskipDetectRecap': aniskipDetectRecap,
        'showHero': showHero,
        'showContinueWatching': showContinueWatching,
        'railTrending': railTrending,
        'railPopularSeason': railPopularSeason,
        'railUpcoming': railUpcoming,
        'railAllTime': railAllTime,
        'railTop100': railTop100,
        'railTopMovies': railTopMovies,
        'gridView': gridView,
        'autoFullscreenOnPlay': autoFullscreenOnPlay,
        'swipeToSeek': swipeToSeek,
        'privateViewing': privateViewing,
        'seekInterval': seekInterval,
        'secondaryAudioLanguage': secondaryAudioLanguage,
        'showOnlyPreferredLanguages': showOnlyPreferredLanguages,
        'subtitleSize': subtitleSize,
        'subtitleBackgroundTint': subtitleBackgroundTint,
        'hardwareDecoding': hardwareDecoding,
        'continueWatchingSource': continueWatchingSource,
        'theme': theme,
        'amoledBlack': amoledBlack,
        'navBarPosition': navBarPosition,
        'liquidGlassTabBar': liquidGlassTabBar,
        'hideStatusBar': hideStatusBar,
        'heroStyle': heroStyle,
        'heroTrailerAutoplay': heroTrailerAutoplay,
        'heroTrailerSound': heroTrailerSound,
        'heroTrailerDelay': heroTrailerDelay,
        'dynamicBackground': dynamicBackground,
        'catalogAccentUnderline': catalogAccentUnderline,
        'budgetRevenueOnDetails': budgetRevenueOnDetails,
        'iconActionRowOnDetails': iconActionRowOnDetails,
        'episodeLayout': episodeLayout,
      };
  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        audioLanguage: (j['audioLanguage'] as String?) ?? 'jpn',
        subtitleLanguage: (j['subtitleLanguage'] as String?) ?? 'eng',
        aniskipEnabled: (j['aniskipEnabled'] as bool?) ?? true,
        aniskipAutoOp: (j['aniskipAutoOp'] as bool?) ?? false,
        aniskipAutoEd: (j['aniskipAutoEd'] as bool?) ?? false,
        aniskipShowButton: (j['aniskipShowButton'] as bool?) ?? true,
        aniskipDetectRecap: (j['aniskipDetectRecap'] as bool?) ?? true,
        showHero: (j['showHero'] as bool?) ?? true,
        showContinueWatching: (j['showContinueWatching'] as bool?) ?? true,
        railTrending: (j['railTrending'] as bool?) ?? true,
        railPopularSeason: (j['railPopularSeason'] as bool?) ?? true,
        railUpcoming: (j['railUpcoming'] as bool?) ?? true,
        railAllTime: (j['railAllTime'] as bool?) ?? true,
        railTop100: (j['railTop100'] as bool?) ?? true,
        railTopMovies: (j['railTopMovies'] as bool?) ?? true,
        gridView: (j['gridView'] as bool?) ?? true,
        autoFullscreenOnPlay: (j['autoFullscreenOnPlay'] as bool?) ?? true,
        swipeToSeek: (j['swipeToSeek'] as bool?) ?? true,
        privateViewing: (j['privateViewing'] as bool?) ?? false,
        seekInterval: (j['seekInterval'] as num?)?.toDouble() ?? 5,
        secondaryAudioLanguage: (j['secondaryAudioLanguage'] as String?) ?? '',
        showOnlyPreferredLanguages:
            (j['showOnlyPreferredLanguages'] as bool?) ?? false,
        subtitleSize: (j['subtitleSize'] as num?)?.toDouble() ?? 18,
        subtitleBackgroundTint:
            (j['subtitleBackgroundTint'] as num?)?.toDouble() ?? 0.5,
        hardwareDecoding: (j['hardwareDecoding'] as bool?) ?? true,
        continueWatchingSource:
            (j['continueWatchingSource'] as String?) ?? 'cloud',
        theme: (j['theme'] as String?) ?? 'white',
        amoledBlack: (j['amoledBlack'] as bool?) ?? false,
        navBarPosition: (j['navBarPosition'] as String?) ?? 'bottom',
        liquidGlassTabBar: (j['liquidGlassTabBar'] as bool?) ?? true,
        hideStatusBar: (j['hideStatusBar'] as bool?) ?? false,
        heroStyle: (j['heroStyle'] as String?) ?? 'full_bleed',
        heroTrailerAutoplay: (j['heroTrailerAutoplay'] as bool?) ?? true,
        heroTrailerSound: (j['heroTrailerSound'] as bool?) ?? false,
        heroTrailerDelay: (j['heroTrailerDelay'] as String?) ?? 'Instant',
        dynamicBackground: (j['dynamicBackground'] as bool?) ?? false,
        catalogAccentUnderline:
            (j['catalogAccentUnderline'] as bool?) ?? false,
        budgetRevenueOnDetails:
            (j['budgetRevenueOnDetails'] as bool?) ?? true,
        iconActionRowOnDetails:
            (j['iconActionRowOnDetails'] as bool?) ?? true,
        episodeLayout: (j['episodeLayout'] as String?) ?? 'detailed',
      );
  AppSettings copyWith({
    String? audioLanguage,
    String? subtitleLanguage,
    bool? aniskipEnabled,
    bool? aniskipAutoOp,
    bool? aniskipAutoEd,
    bool? aniskipShowButton,
    bool? aniskipDetectRecap,
    bool? showHero,
    bool? showContinueWatching,
    bool? railTrending,
    bool? railPopularSeason,
    bool? railUpcoming,
    bool? railAllTime,
    bool? railTop100,
    bool? railTopMovies,
    bool? gridView,
    bool? autoFullscreenOnPlay,
    bool? swipeToSeek,
    bool? privateViewing,
    double? seekInterval,
    String? secondaryAudioLanguage,
    bool? showOnlyPreferredLanguages,
    double? subtitleSize,
    double? subtitleBackgroundTint,
    bool? hardwareDecoding,
    String? continueWatchingSource,
    String? theme,
    bool? amoledBlack,
    String? navBarPosition,
    bool? liquidGlassTabBar,
    bool? hideStatusBar,
    String? heroStyle,
    bool? heroTrailerAutoplay,
    bool? heroTrailerSound,
    String? heroTrailerDelay,
    bool? dynamicBackground,
    bool? catalogAccentUnderline,
    bool? budgetRevenueOnDetails,
    bool? iconActionRowOnDetails,
    String? episodeLayout,
  }) =>
      AppSettings(
        audioLanguage: audioLanguage ?? this.audioLanguage,
        subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
        aniskipEnabled: aniskipEnabled ?? this.aniskipEnabled,
        aniskipAutoOp: aniskipAutoOp ?? this.aniskipAutoOp,
        aniskipAutoEd: aniskipAutoEd ?? this.aniskipAutoEd,
        aniskipShowButton: aniskipShowButton ?? this.aniskipShowButton,
        aniskipDetectRecap: aniskipDetectRecap ?? this.aniskipDetectRecap,
        showHero: showHero ?? this.showHero,
        showContinueWatching:
            showContinueWatching ?? this.showContinueWatching,
        railTrending: railTrending ?? this.railTrending,
        railPopularSeason: railPopularSeason ?? this.railPopularSeason,
        railUpcoming: railUpcoming ?? this.railUpcoming,
        railAllTime: railAllTime ?? this.railAllTime,
        railTop100: railTop100 ?? this.railTop100,
        railTopMovies: railTopMovies ?? this.railTopMovies,
        gridView: gridView ?? this.gridView,
        autoFullscreenOnPlay:
            autoFullscreenOnPlay ?? this.autoFullscreenOnPlay,
        swipeToSeek: swipeToSeek ?? this.swipeToSeek,
        privateViewing: privateViewing ?? this.privateViewing,
        seekInterval: seekInterval ?? this.seekInterval,
        secondaryAudioLanguage:
            secondaryAudioLanguage ?? this.secondaryAudioLanguage,
        showOnlyPreferredLanguages:
            showOnlyPreferredLanguages ?? this.showOnlyPreferredLanguages,
        subtitleSize: subtitleSize ?? this.subtitleSize,
        subtitleBackgroundTint:
            subtitleBackgroundTint ?? this.subtitleBackgroundTint,
        hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
        continueWatchingSource:
            continueWatchingSource ?? this.continueWatchingSource,
        theme: theme ?? this.theme,
        amoledBlack: amoledBlack ?? this.amoledBlack,
        navBarPosition: navBarPosition ?? this.navBarPosition,
        liquidGlassTabBar: liquidGlassTabBar ?? this.liquidGlassTabBar,
        hideStatusBar: hideStatusBar ?? this.hideStatusBar,
        heroStyle: heroStyle ?? this.heroStyle,
        heroTrailerAutoplay:
            heroTrailerAutoplay ?? this.heroTrailerAutoplay,
        heroTrailerSound: heroTrailerSound ?? this.heroTrailerSound,
        heroTrailerDelay: heroTrailerDelay ?? this.heroTrailerDelay,
        dynamicBackground: dynamicBackground ?? this.dynamicBackground,
        catalogAccentUnderline:
            catalogAccentUnderline ?? this.catalogAccentUnderline,
        budgetRevenueOnDetails:
            budgetRevenueOnDetails ?? this.budgetRevenueOnDetails,
        iconActionRowOnDetails:
            iconActionRowOnDetails ?? this.iconActionRowOnDetails,
        episodeLayout: episodeLayout ?? this.episodeLayout,
      );
}

class StreamSource {
  final String name;
  final String url;
  final String quality;
  const StreamSource({required this.name, required this.url, this.quality = ''});
}

class AddonRecord {
  final String manifestUrl;
  final String baseUrl;
  final String id;
  final String name;
  final String version;
  final DateTime addedAt;
  final bool enabled;
  final String description;
  final String logoUrl;
  final List<String> resources; // manifest "resources" (e.g. stream)
  /// Manifest "types" (e.g. ["movie","series"] or ["anime"]) — decides the
  /// `/stream/<type>/` path per addon (website parity: general addons want
  /// "series", anime-only addons want "anime").
  final List<String> types;
  /// Per-resource id prefixes (e.g. ["tt"]) — decides which id forms
  /// (kitsu:/tt:/anilist:/mal:) an addon understands.
  final List<String> idPrefixes;
  /// Website parity: manifest behaviorHints.configurationRequired (or
  /// configurable) — only these addons get a Configure button, which
  /// opens baseUrl + '/configure' (Stremio convention).
  final bool configurable;
  const AddonRecord({
    required this.manifestUrl,
    required this.baseUrl,
    required this.id,
    required this.name,
    this.version = '',
    required this.addedAt,
    this.enabled = true,
    this.description = '',
    this.logoUrl = '',
    this.resources = const [],
    this.types = const [],
    this.idPrefixes = const [],
    this.configurable = false,
  });
  AddonRecord copyWith({
    bool? enabled,
    String? description,
    String? logoUrl,
    List<String>? types,
    List<String>? idPrefixes,
    bool? configurable,
  }) =>
      AddonRecord(
        manifestUrl: manifestUrl,
        baseUrl: baseUrl,
        id: id,
        name: name,
        version: version,
        addedAt: addedAt,
        enabled: enabled ?? this.enabled,
        description: description ?? this.description,
        logoUrl: logoUrl ?? this.logoUrl,
        resources: resources,
        types: types ?? this.types,
        idPrefixes: idPrefixes ?? this.idPrefixes,
        configurable: configurable ?? this.configurable,
      );
  Map<String, dynamic> toJson() => {
        'manifestUrl': manifestUrl,
        'baseUrl': baseUrl,
        'id': id,
        'name': name,
        'version': version,
        'addedAt': addedAt.toIso8601String(),
        'enabled': enabled,
        'description': description,
        'logoUrl': logoUrl,
        'resources': resources,
        'types': types,
        'idPrefixes': idPrefixes,
        'configurable': configurable,
      };
  factory AddonRecord.fromJson(Map<String, dynamic> j) => AddonRecord(
        manifestUrl: (j['manifestUrl'] as String?) ?? '',
        baseUrl: (j['baseUrl'] as String?) ?? '',
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        version: (j['version'] as String?) ?? '',
        addedAt: DateTime.tryParse((j['addedAt'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        // Migration-safe: old records (pre-enabled) default to enabled.
        enabled: (j['enabled'] as bool?) ?? true,
        description: (j['description'] as String?) ?? '',
        logoUrl: (j['logoUrl'] as String?) ?? '',
        resources: ((j['resources'] as List?) ?? []).map((e) => '$e').toList(),
        // Migration-safe: records saved before types/idPrefixes existed
        // get empty lists; the stream flow refetches the manifest then.
        types: ((j['types'] as List?) ?? []).map((e) => '$e').toList(),
        idPrefixes:
            ((j['idPrefixes'] as List?) ?? []).map((e) => '$e').toList(),
        // Migration-safe: old records default to not configurable.
        configurable: (j['configurable'] as bool?) ?? false,
      );
}

class SkipInterval {
  final String kind; // op | ed | recap
  final String label;
  final double start;
  final double end;
  const SkipInterval({
    required this.kind,
    required this.label,
    required this.start,
    required this.end,
  });
}
