// AniSkip — community OP/ED/recap intervals, keyed by MAL id.
// API: api.aniskip.com/v2/skip-times/{malId}/{episode}?types[]=...
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

class AniSkip {
  static Future<List<SkipInterval>> fetch(
    int? malId,
    int episode, {
    int episodeLength = 1440,
    bool detectRecap = true,
  }) async {
    if (malId == null || episode <= 0) return [];
    final types = ['op', 'mixed-op', 'ed', 'mixed-ed'];
    if (detectRecap) types.add('recap');
    final qs = types.map((t) => 'types[]=$t').join('&');
    try {
      final r = await http.get(Uri.parse(
          'https://api.aniskip.com/v2/skip-times/$malId/$episode?$qs&episodeLength=$episodeLength'));
      if (r.statusCode != 200) return [];
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      const names = {
        'op': 'Skip Intro',
        'mixed-op': 'Skip Intro',
        'ed': 'Skip Outro',
        'mixed-ed': 'Skip Outro',
        'recap': 'Skip Recap',
      };
      const kinds = {
        'op': 'op',
        'mixed-op': 'op',
        'ed': 'ed',
        'mixed-ed': 'ed',
        'recap': 'recap',
      };
      // The API returns EVERY community submission for the episode — for
      // popular shows that's 2+ intros and 2+ outros. Keep only the
      // best-voted interval per kind (op/ed/recap).
      final best = <String, SkipInterval>{};
      final bestVotes = <String, int>{};
      for (final item in (j['results'] as List?) ?? []) {
        final m = item as Map<String, dynamic>;
        final interval = m['interval'] as Map<String, dynamic>? ?? {};
        final start = (interval['startTime'] as num?)?.toDouble() ?? 0;
        final end = (interval['endTime'] as num?)?.toDouble() ?? 0;
        if (end <= start) continue;
        final st = (m['skipType'] as String?) ?? 'op';
        final kind = kinds[st] ?? 'op';
        final votes = (m['votes'] as num?)?.toInt() ?? 0;
        if (best.containsKey(kind) && votes <= (bestVotes[kind] ?? 0)) {
          continue;
        }
        best[kind] = SkipInterval(
          kind: kind,
          label: names[st] ?? 'Skip',
          start: start,
          end: end,
        );
        bestVotes[kind] = votes;
      }
      return best.values.toList();
    } catch (_) {
      return [];
    }
  }
}
