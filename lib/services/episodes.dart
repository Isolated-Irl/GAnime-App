// Episode data via Kitsu (catalogue ids are Kitsu ids now).
// Falls back to a plain numbered list when Kitsu is down or has no
// episodes for the title, so Details never blocks on it.
import '../models.dart';
import 'kitsu.dart';

class EpisodesService {
  static Future<List<EpisodeInfo>> forAnime(Anime a) async {
    try {
      final eps = await Kitsu.episodes(a.id);
      if (eps.isNotEmpty) return eps;
    } catch (_) {
      // Fall through to the numbered fallback below.
    }
    final total = a.episodes ?? 0;
    if (total <= 0) return [];
    return List.generate(
      total,
      (i) => EpisodeInfo(number: i + 1, title: 'Episode ${i + 1}'),
    );
  }

  /// Stremio-style ids used by addons: `anilist:<id>:<episode>`.
  /// Catalogue ids are Kitsu ids, so the AniList id is resolved first;
  /// throws when the title has no AniList mapping.
  static Future<String> streamIdFor(Anime a, int episode) async {
    final al = await Kitsu.resolveAnilistId(a.id);
    if (al == null) throw Exception('No AniList mapping for this title');
    return 'anilist:$al:$episode';
  }
}
