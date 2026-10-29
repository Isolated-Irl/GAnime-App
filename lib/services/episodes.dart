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
}
