// Shared data models for the GAnime Android port.
// Mirrors the web app's concepts, not its code: AniList metadata only,
// local watched state, tracker lists, profiles, and per-profile settings.
// Audio and subtitle preferences are ALWAYS separate settings.
class Anime {
  final int id;
  final String title;
  final String cover;
  final String banner;
  final String description;
  final String format;
  final String status;
  final int? episodes;
  final int? nextEpisode;
  final int? airingAt;
  final double? score;
  final List<String> genres;
  final int? malId;
  final int? year;
  final String season;

  const Anime({
    required this.id,
    required this.title,
    this.cover = '',
    this.banner = '',
    this.description = '',
    this.format = '',
    this.status = '',
    this.episodes,
    this.nextEpisode,
    this.airingAt,
    this.score,
    this.genres = const [],
    this.malId,
    this.year,
    this.season = '',
  });

  factory Anime.fromJson(Map<String, dynamic> j) {
    final t = j['title'] as Map<String, dynamic>? ?? {};
    final img = j['coverImage'] as Map<String, dynamic>? ?? {};
    final next = j['nextAiringEpisode'] as Map<String, dynamic>?;
    String clean(String? s) =>
        (s ?? '').replaceAll(RegExp(r'<[^>]*>'), '').trim();
    return Anime(
      id: (j['id'] as num?)?.toInt() ?? 0,
      title: (t['english'] as String?)?.isNotEmpty == true
          ? t['english'] as String
          : ((t['romaji'] as String?) ?? (t['userPreferred'] as String?) ?? ''),
      cover: (img['large'] as String?) ?? (img['medium'] as String?) ?? '',
      banner: (j['bannerImage'] as String?) ?? '',
      description: clean(j['description'] as String?),
      format: (j['format'] as String?) ?? '',
      status: (j['status'] as String?) ?? '',
      episodes: (j['episodes'] as num?)?.toInt(),
      nextEpisode: (next?['episode'] as num?)?.toInt(),
      airingAt: (next?['airingAt'] as num?)?.toInt(),
      score: (j['averageScore'] as num?)?.toDouble(),
      genres: ((j['genres'] as List?) ?? []).map((e) => '$e').toList(),
      malId: (j['idMal'] as num?)?.toInt(),
      year: (j['seasonYear'] as num?)?.toInt(),
      season: (j['season'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'cover': cover,
        'banner': banner,
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
      };

  factory Anime.fromStored(Map<String, dynamic> j) => Anime(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        cover: (j['cover'] as String?) ?? '',
        banner: (j['banner'] as String?) ?? '',
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
      );
}

class EpisodeInfo {
  final int number;
  final String title;
  final String still;
  final String overview;
  final int? runtime;
  const EpisodeInfo({
    required this.number,
    this.title = '',
    this.still = '',
    this.overview = '',
    this.runtime,
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
  });
}

class Profile {
  final String id;
  final String name;
  final int color;
  const Profile({required this.id, required this.name, this.color = 0xFF22C55E});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};
  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: '${j['id']}',
        name: (j['name'] as String?) ?? 'Profile',
        color: (j['color'] as num?)?.toInt() ?? 0xFF22C55E,
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
  const AppSettings({
    this.audioLanguage = 'jpn',
    this.subtitleLanguage = 'eng',
    this.aniskipEnabled = true,
    this.aniskipAutoOp = false,
    this.aniskipAutoEd = false,
    this.aniskipShowButton = true,
    this.aniskipDetectRecap = true,
  });
  Map<String, dynamic> toJson() => {
        'audioLanguage': audioLanguage,
        'subtitleLanguage': subtitleLanguage,
        'aniskipEnabled': aniskipEnabled,
        'aniskipAutoOp': aniskipAutoOp,
        'aniskipAutoEd': aniskipAutoEd,
        'aniskipShowButton': aniskipShowButton,
        'aniskipDetectRecap': aniskipDetectRecap,
      };
  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        audioLanguage: (j['audioLanguage'] as String?) ?? 'jpn',
        subtitleLanguage: (j['subtitleLanguage'] as String?) ?? 'eng',
        aniskipEnabled: (j['aniskipEnabled'] as bool?) ?? true,
        aniskipAutoOp: (j['aniskipAutoOp'] as bool?) ?? false,
        aniskipAutoEd: (j['aniskipAutoEd'] as bool?) ?? false,
        aniskipShowButton: (j['aniskipShowButton'] as bool?) ?? true,
        aniskipDetectRecap: (j['aniskipDetectRecap'] as bool?) ?? true,
      );
  AppSettings copyWith({
    String? audioLanguage,
    String? subtitleLanguage,
    bool? aniskipEnabled,
    bool? aniskipAutoOp,
    bool? aniskipAutoEd,
    bool? aniskipShowButton,
    bool? aniskipDetectRecap,
  }) =>
      AppSettings(
        audioLanguage: audioLanguage ?? this.audioLanguage,
        subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
        aniskipEnabled: aniskipEnabled ?? this.aniskipEnabled,
        aniskipAutoOp: aniskipAutoOp ?? this.aniskipAutoOp,
        aniskipAutoEd: aniskipAutoEd ?? this.aniskipAutoEd,
        aniskipShowButton: aniskipShowButton ?? this.aniskipShowButton,
        aniskipDetectRecap: aniskipDetectRecap ?? this.aniskipDetectRecap,
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
  const AddonRecord({
    required this.manifestUrl,
    required this.baseUrl,
    required this.id,
    required this.name,
    this.version = '',
    required this.addedAt,
  });
  Map<String, dynamic> toJson() => {
        'manifestUrl': manifestUrl,
        'baseUrl': baseUrl,
        'id': id,
        'name': name,
        'version': version,
        'addedAt': addedAt.toIso8601String(),
      };
  factory AddonRecord.fromJson(Map<String, dynamic> j) => AddonRecord(
        manifestUrl: (j['manifestUrl'] as String?) ?? '',
        baseUrl: (j['baseUrl'] as String?) ?? '',
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        version: (j['version'] as String?) ?? '',
        addedAt: DateTime.tryParse((j['addedAt'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
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
