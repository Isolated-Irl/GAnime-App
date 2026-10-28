# GAnime Android — Flutter + media_kit (mpv)

Android-first port of the GAnime web app. **Not movi, not a PWA, not a
wrap of the website.** The web app at ganime.pages.dev
(Isolated-Irl/GAnime) is untouched by this repo.

- Package: `com.isolated.ganime`
- App name: GAnime
- Player: media_kit (mpv) — see `lib/screens/player.dart`
- Flutter 3.47.8 / Dart 3.13.7 (verified locally, see below)
- Android only in this repo for now. Linux later, iOS/Windows later.

## What is built (honest phase status)

### Phase 1 — Player POC: CODE COMPLETE, NOT YET RUN ON A DEVICE
`lib/screens/player.dart` + Settings > Player Test.
Play/pause, seek bar with an 85% marker and an "85% passed" indicator,
audio/subtitle track picker (language shown where mpv reports it),
AniSkip buttons + auto-skip toggles, 85% auto-mark (marks locally,
never un-marks, never for movies — movies have no episode flow here).
Player Test uses public test videos only, never GAnime streams.

### Phase 2 — Home / Search / Calendar / Details / Episodes: CODE COMPLETE, NOT YET RUN ON A DEVICE
AniList GraphQL (trending, popular, search, details, 7-day airing
schedule), episode lists via api.ani.zip with a numbered fallback,
Continue Watching from local watched state, eye-mark / hole-preserving
unmark per episode.

### Phase 3 — Library / Profiles / Settings: CODE COMPLETE, NOT YET RUN ON A DEVICE
Library tabs: Local, AniList, Simkl, MAL (MAL is read-only, matching
the web app). Profiles (local, one default "Profile 1"). Settings:
**audio language and subtitle language are separate settings, never
merged** (defaults: Japanese audio, English subtitles), plus AniSkip
toggles.

### Phase 4 — Firebase Auth + Firestore sync: PARTIAL — READ THIS
Implemented: email/password sign-up + sign-in via Identity Toolkit
REST, and a Sync Now push to one document `users/{uid}` with the web
app's merge rules (profiles + addons union with local wins, watched +
local library union by key, tombstones never resurrect a profile,
settings newer-timestamp wins).
NOT yet implemented:
- Firebase config is NOT in this repo on purpose. Enter YOUR apiKey +
  projectId in Settings > Firebase sync, on-device only.
- After sign-in, the profile namespace does NOT yet switch from
  `guest` to `uid:<uid>`. Treat sync as single-account for now.
- Push merges remote + local, but a fresh device does NOT yet
  restore profiles/watched/addons from the cloud automatically.
  Restore-on-new-device is pending.

### Phase 5 — Addons: CODE COMPLETE, NOT YET RUN ON A DEVICE
Stremio-protocol manifest fetch + `/stream/` queries, per profile.
**This app ships with NO stream sources and recommends none.**
No example addon names or URLs are in the code. Paste a manifest URL
you found yourself in Settings > Addons.
Known limitation: streams are requested as `anilist:<id>:<episode>`.
Some addons may need a series/season id form instead and will return
no streams for a title — that is per-addon behaviour to test, not a
guaranteed fix in this build.

## Verification actually done here

- Flutter SDK: official stable 3.47.8 tarball from
  `storage.googleapis.com/flutter_infra_release`, SHA-256 verified
  (`baf7dcc5…87dd2`, matched exactly). Installed in
  `~/workspace/.flutter-sdk/` on the build VM — do NOT copy that
  folder into this repo.
- `flutter pub get`: succeeded (95 dependencies).
- `flutter analyze`: **No issues found** (0 errors, 0 warnings, 0 infos).
- Local APK: **NOT produced.** This VM has no Android SDK
  (`flutter build apk` fails with "No Android SDK found"), and the
  task route is GitHub Actions instead. **Do not claim an APK exists
  until the workflow below produces one and you check its size.**

## How to test (after the APK is built)

1. Install the APK on an Android phone (allow install from your
   browser/files app when asked).
2. Home: trending + popular posters load from AniList. Tap one >
   Details > Episodes load (ani.zip, or a numbered list as fallback).
3. Settings > Player Test: tap Open, press Play. Success = video
   plays, seek bar moves, position/duration count up, the 85% chip
   flips to "85% passed" after 85% of the video.
4. Player: tap "Audio / Subtitle tracks" — success = the picker lists
   the tracks mpv reports (a plain MP4 may list 1 audio track and
   0 subtitles; that is the sample, not a bug).
5. AniSkip TEST: in Player Test there is no MAL id, so no real
   AniSkip intervals load there. Real intervals load only in a
   Details episode player for a title with a MAL id.
6. Addons: Settings > Addons, paste a manifest URL you found
   yourself, install, then open an episode in Details. If streams
   appear, tap one to play in media_kit. If none appear, see the
   Phase 5 limitation above.

## Carry steps for Isolated (he pushes — nothing was pushed by the agent)

Target repo (already created, Public, main): `Isolated-Irl/GAnime-App`.
The web repo `Isolated-Irl/GAnime` is NOT touched by this project.

```bash
# 1. Clone the app repo (or cd into it if you already cloned it)
git clone https://github.com/Isolated-Irl/GAnime-App.git
cd GAnime-App

# 2. Copy THIS project folder into the repo root, including dotfiles.
#    From the workspace folder that holds ganime-android-test/:
cp -r ganime-android-test/. GAnime-App/
#    Do NOT copy: ~/workspace/.flutter-sdk/ , ~/workspace/ganime-scaffold/
#    .gitignore already excludes local.properties, build/, .dart_tool/.

# 3. Commit + push (this triggers the workflow)
git add .
git status        # check: no keystore, no firebase config, no tokens
git commit -m "GAnime Android: Flutter + media_kit, Phases 1-5"
git push origin main
```

4. GitHub > repo > Actions > `android-test-apk` — wait for green.
   (Also runs on "Run workflow" manually.)
5. Actions > the green run > Artifacts > `ganime-test-apk` >
   download `app-release.apk`. Check its size is non-zero, then
   install it with the test steps above.
6. If the workflow fails, paste the failing step's log — do not
   guess at a fix from the summary line alone.

## Files in this project

- `pubspec.yaml`, `pubspec.lock` — Flutter 3.47.8, media_kit,
  media_kit_video, media_kit_libs_video, http, shared_preferences,
  url_launcher.
- `lib/main.dart` — app shell, bottom nav (Home/Search/Calendar/
  Library/Settings), tracker push on mark-watched.
- `lib/models.dart` — Anime, EpisodeInfo, LibraryEntry, Profile,
  AppSettings (separate audio/subtitle), StreamSource, AddonRecord,
  SkipInterval.
- `lib/store.dart` — local SharedPreferences store, profiles
  namespaced per account, hole-preserving watched, tombstones.
- `lib/services/anilist.dart` — AniList GraphQL.
- `lib/services/episodes.dart` — ani.zip episode lists.
- `lib/services/aniskip.dart` — api.aniskip.com skip intervals.
- `lib/services/trackers.dart` — AniList (PIN token), Simkl (PIN),
  MAL public list (read-only).
- `lib/services/firebase_sync.dart` — Firebase REST auth + Firestore
  `users/{uid}` push with merge rules (see Phase 4 gaps above).
- `lib/services/addons.dart` — Stremio manifest + streams, no bundled
  or recommended sources.
- `lib/screens/player.dart` — media_kit player (Phase 1).
- `lib/screens/details.dart` — Details + Episodes + stream picker.
- `lib/screens/app_screens.dart` — Home, Search, Calendar, Library,
  Settings (profiles, separate audio/subtitle, AniSkip, Player Test,
  Addons, Trackers, Firebase).
- `lib/widgets/anime_card.dart` — poster card.
- `android/` — Flutter Android scaffold, package
  `com.isolated.ganime`, INTERNET permission, app label GAnime.
- `.github/workflows/android-test.yml` — GitHub Actions: Java 17,
  Flutter stable, `flutter pub get`, `flutter analyze`,
  `flutter build apk --release`, upload `app-release.apk` as artifact
  `ganime-test-apk` (30-day retention).
