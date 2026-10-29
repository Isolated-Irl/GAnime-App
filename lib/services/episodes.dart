// Episode data via Kitsu (catalogue ids are Kitsu ids now).
// Falls back to a plain numbered list when Kitsu is down or has no
// episodes for the title, so Details never blocks on it.
import '../models.dart';
import 'kitsu.dart';
import 'addon_ids.dart';

class EpisodesService {
  static Future<List<EpisodeInfo>> forAnime(Anime a) async {
    try {
      // Calendar/Tracker items carry AniList IDs, not Kitsu IDs.
      // Resolve to Kitsu first so we get real episodes (titles, stills)
      // instead of hanging on a wrong ID.
      int kitsuId = a.id;
      try {
        final resolved = await AddonIdResolver.resolve(a);
        if (resolved.kitsu != null) {
          kitsuId = int.tryParse(resolved.kitsu!) ?? a.id;
        }
      } catch (_) {}
      final eps = await Kitsu.episodes(kitsuId);
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
}
