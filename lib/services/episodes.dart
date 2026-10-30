// Episode data: the catalogue is AniList-based and AniList exposes no
// per-episode titles/stills, so Details builds a reliable numbered list
// from the AniList episode total (or the airing schedule's next episode
// for releasing titles whose total is still unknown). Never blocks.
import '../models.dart';

class EpisodesService {
  static Future<List<EpisodeInfo>> forAnime(Anime a) async {
    // For releasing titles, episode count is often unknown (null).
    // Use nextEpisode from the airing schedule if available —
    // the calendar knows EP 5 is out even if the total is unknown.
    var total = a.episodes ?? 0;
    if (total <= 0 && (a.nextEpisode ?? 0) > 0) {
      total = a.nextEpisode!;
    }
    if (total <= 0) return [];
    // Episode thumbnails from AniList streamingEpisodes (may be sparse —
    // fall back to '' and let the UI use banner/cover).
    return List.generate(
      total,
      (i) => EpisodeInfo(
        number: i + 1,
        title: 'Episode ${i + 1}',
        still: i < a.episodeThumbs.length ? a.episodeThumbs[i] : '',
      ),
    );
  }
}
