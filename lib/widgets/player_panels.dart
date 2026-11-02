// Glass panels for the player: episode list + rich source picker +
// external-player handoff. Website parity for player.js.
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import 'glass_surface.dart';

// ---------- stream info parsing (from name + description text) ----------
class StreamInfo {
  final String title;
  final List<String> tags; // [1080p, BLURAY, HEVC, FLAC]
  final String size;       // 34.36 GB
  final String duration;   // 23m:41s
  final String flags;      // JPN / multi
  const StreamInfo(this.title, this.tags, this.size, this.duration, this.flags);
}

StreamInfo parseStreamInfo(StreamSource s) {
  final text = '${s.name}\n${s.quality}'.toLowerCase();
  String? pick(String pattern) =>
      RegExp(pattern, caseSensitive: false).firstMatch(text)?.group(0);
  final tags = <String>[
    for (final p in [
      r'2160p|4k|1440p|1080p|720p|480p',
      r'blu-?ray|bdremux|remux|web-?dl|web-?rip|hdtv|dvdrip?',
      r'hevc|x265|x264|avc|av1|vp9',
      r'flac|truehd|dts-?hd|ac3|eac3|aac|opus',
      r'5\.1|7\.1|2\.0|stereo',
    ])
      if (pick(p) != null) pick(p)!.toUpperCase(),
  ];
  final size = pick(r'\d+(\.\d+)?\s?(gb|mb)') ?? '';
  final dur = RegExp(r'(\d{1,3})\s*m\s*[:.]?\s*(\d{1,2})\s*s', caseSensitive: false)
      .firstMatch(text);
  final duration =
      dur != null ? '${dur.group(1)}m:${(dur.group(2)!).padLeft(2, '0')}s' : '';
  final flags = text.contains('multi-audio')
      ? 'Multi'
      : (text.contains('japanese') || text.contains('ja-jp') ? 'JPN' : '');
  return StreamInfo(s.name, tags, size, duration, flags);
}

// ---------- external player ----------
class ExternalPlayer {
  /// VIEW intent -> system player chooser; falls back to copying the link.
  /// REQUIRES the `<queries>` manifest block (Android 11+): without it Android
  /// hides every player app and this "finds nothing" — the old bug.
  static Future<String?> launch(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (ok) return 'player';
    } catch (_) {}
    await Clipboard.setData(ClipboardData(text: url));
    return null;
  }
}

// ---------- glass dialog scaffold (centered) ----------
Future<T?> glassSheet<T>(BuildContext context, Widget child) {
  // Bottom sheet (mpvKt-style position) with the glass treatment — NOT a
  // centered dialog. The chapter list keeps its own centered dialog;
  // streams & episodes slide up from the bottom.
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: GlassSurface(
          radius: 24,
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.72),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

// ---------- sources panel (grouped by addon, horizontal tabs) ----------
Future<StreamSource?> showSourcesPanel(
  BuildContext context, {
  required Map<String, List<StreamSource>> groupedStreams,
  required String nowPlayingUrl,
}) {
  final total = groupedStreams.values.fold<int>(0, (s, l) => s + l.length);
  final addonNames = groupedStreams.keys.toList();
  var selectedTab = 0; // 0 = All, 1..n = addon index + 1
  return glassSheet<StreamSource>(
    context,
    StatefulBuilder(builder: (ctx, setState) {
        List<MapEntry<String, List<StreamSource>>> visibleEntries;
        if (selectedTab == 0) {
          visibleEntries = groupedStreams.entries.toList();
        } else {
          final name = addonNames[selectedTab - 1];
          visibleEntries = [MapEntry(name, groupedStreams[name]!)];
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(children: [
                Expanded(
                  child: Text('Sources ($total)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                ),
                GlassButton(
                    icon: Icons.close,
                    size: 36,
                    iconSize: 18,
                    circle: true,
                    onTap: () => Navigator.pop(context)),
              ]),
            ),
            // Horizontal addon tabs, like the StreamsScreen
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  _panelTabChip('All \u00b7 $total', selectedTab == 0,
                      () => setState(() => selectedTab = 0)),
                  for (var i = 0; i < addonNames.length; i++)
                    _panelTabChip(
                      '${addonNames[i]} \u00b7 ${groupedStreams[addonNames[i]]!.length}',
                      selectedTab == i + 1,
                      () => setState(() => selectedTab = i + 1),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(12),
                children: [
                  for (final entry in visibleEntries) ...[
                    if (selectedTab == 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                        child: Align(
                          alignment: Alignment.center,
                          child: GlassSurface(
                            radius: 10,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              child: Text(
                                  '${entry.key} \u00b7 ${entry.value.length}',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                            ),
                          ),
                        ),
                      ),
                    for (final s in entry.value) Builder(builder: (_) {
                      final info = parseStreamInfo(s);
                      final playing = s.url == nowPlayingUrl;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassSurface(
                          radius: 14,
                          border: playing
                              ? const Color(0x80FFFFFF)
                              : const Color(0x26FFFFFF),
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              onTap: () => Navigator.pop(context, s),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(info.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    if (info.tags.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 4),
                                        child: Text(info.tags.join('  '),
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12)),
                                      ),
                                    if (info.size.isNotEmpty ||
                                        info.duration.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 2),
                                        child: Text(
                                          '${info.size}'
                                          '${info.size.isNotEmpty && info.duration.isNotEmpty ? ' \u00b7 ' : ''}'
                                          '${info.duration}'
                                          '${info.flags.isNotEmpty ? '  \u00b7  ${info.flags}' : ''}',
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12),
                                        ),
                                      ),
                                    if (playing)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 6),
                                        child: Text('Now playing',
                                            style: TextStyle(
                                                color: Colors.greenAccent,
                                                fontSize: 12)),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        );
    }),
  );
}

Widget _panelTabChip(String label, bool active, VoidCallback onTap) {
  return Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GlassSurface(
      radius: 10,
      fill: active ? const Color(0x3300E676) : const Color(0x0DFFFFFF),
      border: active ? const Color(0x5900E676) : const Color(0x26FFFFFF),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(label,
                style: TextStyle(
                    color: active ? const Color(0xFF00E676) : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    ),
  );
}

// ---------- episodes panel ----------
Future<int?> showEpisodesPanel(
  BuildContext context, {
  required List<EpisodeInfo> episodes,
  required int current,
  required Set<int> watched,
}) {
  return glassSheet<int>(context, Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
        child: Row(children: [
          Expanded(
            child: Text('Episodes (${episodes.length})',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ),
          GlassButton(icon: Icons.close, size: 36, iconSize: 18, circle: true,
              onTap: () => Navigator.pop(context)),
        ]),
      ),
      Flexible(
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          itemCount: episodes.length,
          itemBuilder: (_, i) {
            final e = episodes[i];
            final isCur = e.number == current;
            final isWatched = watched.contains(e.number);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GlassSurface(
                radius: 12,
                fill: isCur ? const Color(0x33FFFFFF) : const Color(0x0DFFFFFF),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => Navigator.pop(context, e.number),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(children: [
                        Text('${e.number}',
                            style: TextStyle(
                                color: isCur ? Colors.white : Colors.white70,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            e.title.isEmpty ? 'Episode ${e.number}' : e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                        if (isWatched)
                          const Text('Watched ✓',
                              style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                        if (isCur)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text('▶',
                                style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  ));
}
