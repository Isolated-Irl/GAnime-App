// Playback settings sub-screen (Settings > Playback) — website parity.
// Audio and subtitle languages are SEPARATE settings, never merged.
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../store.dart';
import '../player.dart';
import 'settings_shell.dart';

class PlaybackSettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettings;
  const PlaybackSettingsScreen(
      {super.key, required this.settings, required this.onSettings});

  @override
  State<PlaybackSettingsScreen> createState() =>
      _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  late AppSettings _s;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
  }

  Future<void> _save(AppSettings s) async {
    await Store.saveSettings(s);
    if (!mounted) return;
    setState(() => _s = s);
    widget.onSettings(s);
  }

  @override
  Widget build(BuildContext context) {
    return GASubPage(
      title: 'Playback',
      children: [
        gaSectionLabel('Player'),
        gaToggleRow(
          title: 'Auto Fullscreen on Play',
          value: _s.autoFullscreenOnPlay,
          onChanged: (v) => _save(_s.copyWith(autoFullscreenOnPlay: v)),
        ),
        gaToggleRow(
          title: 'Swipe to Seek',
          value: _s.swipeToSeek,
          onChanged: (v) => _save(_s.copyWith(swipeToSeek: v)),
        ),
        gaToggleRow(
          title: 'Private Viewing',
          value: _s.privateViewing,
          onChanged: (v) => _save(_s.copyWith(privateViewing: v)),
        ),
        gaSliderRow(
          title: 'Seek Interval',
          value: _s.seekInterval,
          min: 1,
          max: 30,
          divisions: 29,
          label: (v) => '${v.round()}s',
          onChanged: (v) => _save(_s.copyWith(seekInterval: v)),
        ),
        gaSectionLabel('Anime Skipping'),
        gaChevronRow(
          title: 'AniSkip Service',
          subtitle: _s.aniskipEnabled ? 'Enabled' : 'Disabled',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  _AniskipPage(settings: _s, onSettings: (s) => _save(s)),
            ),
          ),
        ),
        // Subtitle & audio rendered ONCE (the website screenshot duplicates
        // this block; do not copy that mistake).
        gaSectionLabel('Subtitle and Audio'),
        gaDropdownRow(
          context: context,
          title: 'Preferred Audio Language',
          value: _s.audioLanguage,
          options: const {
            '': 'Device language',
            'jpn': 'Japanese',
            'eng': 'English',
          },
          onChanged: (v) => _save(_s.copyWith(audioLanguage: v)),
        ),
        gaDropdownRow(
          context: context,
          title: 'Secondary Audio Language',
          value: _s.secondaryAudioLanguage,
          options: const {
            '': 'None',
            'jpn': 'Japanese',
            'eng': 'English',
          },
          onChanged: (v) => _save(_s.copyWith(secondaryAudioLanguage: v)),
        ),
        gaDropdownRow(
          context: context,
          title: 'Preferred Subtitle Language',
          value: _s.subtitleLanguage,
          options: const {
            'eng': 'English',
            'jpn': 'Japanese',
            '': 'None',
          },
          onChanged: (v) => _save(_s.copyWith(subtitleLanguage: v)),
        ),
        gaToggleRow(
          title: 'Show Only Preferred Languages',
          value: _s.showOnlyPreferredLanguages,
          onChanged: (v) => _save(_s.copyWith(showOnlyPreferredLanguages: v)),
        ),
        gaSectionLabel('Subtitle Rendering'),
        gaSliderRow(
          title: 'Subtitle Size',
          value: _s.subtitleSize,
          min: 10,
          max: 30,
          divisions: 20,
          label: (v) => '${v.round()}sp',
          onChanged: (v) => _save(_s.copyWith(subtitleSize: v)),
        ),
        gaSliderRow(
          title: 'Subtitle Background Tint',
          value: _s.subtitleBackgroundTint,
          min: 0,
          max: 1,
          divisions: 20,
          label: (v) => '${(v * 100).round()}%',
          onChanged: (v) => _save(_s.copyWith(subtitleBackgroundTint: v)),
        ),
        gaSectionLabel('Player Test'),
        const GACard(
          child: Text(
            'Opens the media_kit player with a public test video (not a GAnime stream).',
            style: TextStyle(color: gaGrey, fontSize: 13),
          ),
        ),
        gaGreenButton(
          label: 'Open Player Test',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  anime: const Anime(id: 0, title: 'Player Test'),
                  episode: 1,
                  streams: const [
                    StreamSource(
                      name: 'Big Buck Bunny (test MP4)',
                      url:
                          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
                    ),
                  ],
                  settings: _s,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// AniSkip Service sub-page: all five AniSkip toggles.
class _AniskipPage extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettings;
  const _AniskipPage({required this.settings, required this.onSettings});

  @override
  State<_AniskipPage> createState() => _AniskipPageState();
}

class _AniskipPageState extends State<_AniskipPage> {
  late AppSettings _s;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
  }

  Future<void> _save(AppSettings s) async {
    await Store.saveSettings(s);
    if (!mounted) return;
    setState(() => _s = s);
    widget.onSettings(s);
  }

  @override
  Widget build(BuildContext context) {
    return GASubPage(
      title: 'AniSkip Service',
      children: [
        gaToggleRow(
          title: 'AniSkip enabled',
          value: _s.aniskipEnabled,
          onChanged: (v) => _save(_s.copyWith(aniskipEnabled: v)),
        ),
        gaToggleRow(
          title: 'Auto-skip opening',
          value: _s.aniskipAutoOp,
          onChanged: (v) => _save(_s.copyWith(aniskipAutoOp: v)),
        ),
        gaToggleRow(
          title: 'Auto-skip ending',
          value: _s.aniskipAutoEd,
          onChanged: (v) => _save(_s.copyWith(aniskipAutoEd: v)),
        ),
        gaToggleRow(
          title: 'Show skip buttons',
          value: _s.aniskipShowButton,
          onChanged: (v) => _save(_s.copyWith(aniskipShowButton: v)),
        ),
        gaToggleRow(
          title: 'Detect recaps',
          value: _s.aniskipDetectRecap,
          onChanged: (v) => _save(_s.copyWith(aniskipDetectRecap: v)),
        ),
      ],
    );
  }
}
