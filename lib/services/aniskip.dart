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
      final out = <SkipInterval>[];
      for (final item in (j['results'] as List?) ?? []) {
        final m = item as Map<String, dynamic>;
        final interval = m['interval'] as Map<String, dynamic>? ?? {};
        final start = (interval['startTime'] as num?)?.toDouble() ?? 0;
        final end = (interval['endTime'] as num?)?.toDouble() ?? 0;
        if (end <= start) continue;
        final st = (m['skipType'] as String?) ?? 'op';
        out.add(SkipInterval(
          kind: kinds[st] ?? 'op',
          label: names[st] ?? 'Skip',
          start: start,
          end: end,
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }
}
