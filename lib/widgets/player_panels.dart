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

// ---------- glass sheet scaffold ----------
Future<T?> glassSheet<T>(BuildContext context, Widget child) {
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
              constraints:
                  BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.72),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

// ---------- sources panel ----------
Future<StreamSource?> showSourcesPanel(
  BuildContext context, {
  required List<StreamSource> streams,
  required String nowPlayingUrl,
  required String addonName,
}) {
  return glassSheet<StreamSource>(context, Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
        child: Row(children: [
          const Text('Sources',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          const Spacer(),
          GlassButton(icon: Icons.close, size: 36, iconSize: 18, circle: true,
              onTap: () => Navigator.pop(context)),
        ]),
      ),
      if (addonName.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: GlassSurface(
              radius: 10,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text('$addonName · ${streams.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ),
        ),
      Flexible(
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          itemCount: streams.length,
          itemBuilder: (_, i) {
            final s = streams[i];
            final info = parseStreamInfo(s);
            final playing = s.url == nowPlayingUrl;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassSurface(
                radius: 14,
                border: playing ? const Color(0x80FFFFFF) : const Color(0x26FFFFFF),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => Navigator.pop(context, s),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(info.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          if (info.tags.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(info.tags.join('  '),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ),
                          if (info.size.isNotEmpty || info.duration.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${info.size}'
                                '${info.size.isNotEmpty && info.duration.isNotEmpty ? ' · ' : ''}'
                                '${info.duration}'
                                '${info.flags.isNotEmpty ? '  ·  ${info.flags}' : ''}',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12),
                              ),
                            ),
                          if (playing)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text('Now playing',
                                  style: TextStyle(
                                      color: Colors.greenAccent, fontSize: 12)),
                            ),
                        ],
                      ),
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
          Text('Episodes (${episodes.length})',
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          const Spacer(),
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
