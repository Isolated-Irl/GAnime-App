# GAnime 📱

A free, open-source anime client for Android — sleek, fast, and engineered with care.

[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)](#tech)
[![Framework](https://img.shields.io/badge/Built%20with-Flutter-02569B?logo=flutter&logoColor=white)](#tech)
[![Engine](https://img.shields.io/badge/Playback-mpv%20%2F%20media__kit-8B0000)](#built-in-player)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

> ⚠️ **Active Development** — GAnime is in its early stages. You might spot a few rough edges or minor quirks between releases, but stability and polish improve with every build. Feedback and issue reports are always welcome 🛠️

---

## Highlights

### 🎬 Built-in Hardware-Accelerated Player
* **REX-Style Glass UI** — Liquid-smooth, hardware-accelerated frosted glass controls (`GlassSurface`) with automatic idle hiding and screen lock.
* **Smart Chapter Integration** — Native MKV chapter support accessible right from a top-bar glass pill (`🔖`), opening a clean, centered chapter list to jump across arcs effortlessly.
* **Fluid Touch Gestures**:
  * **Double-tap seek** with dynamic time accumulation pills (±5s, ±10s, ±30s) and iOS-style 360° spin feedback.
  * **Horizontal swipe-to-seek** with live timestamp differential preview.
  * **Vertical swipe sliders** for split brightness (left) and volume (right) HUDs.
  * **Long-press** for instant 2.0x speed playback.
* **Decoder Toggle** — Instant on-the-fly switching between Hardware (`HW` via MediaCodec) and Software (`SW` CPU decoding).
* **Subtitle Engine & Delay Sync** — Full subtitle customizer (font size, borders, shadows, scale, position) and millisecond audio/subtitle sync offsets with auto-sync tap timing.
* **AniSkip Integration** — Automatic and one-tap skipping for Openings, Endings, and Recaps.

### 📚 Tracking & Library
* **Browse & Discover** — Trending titles, popular releases, advanced filters, and a real-time 7-day airing calendar powered by AniList.
* **Multi-Service Sync** — Local-first library management with optional two-way sync across **AniList**, **Simkl**, and read-only support for **MyAnimeList**.
* **Smart Auto-Mark** — Automatically marks episodes as watched once you cross the 85% threshold (with private viewing support to pause history tracking).
* **Cross-Episode Auto-Play** — Seamless auto-advance countdown to the next episode upon completion.

### 👥 Multi-Profile & Custom Addons
* **Isolated Profiles** — Create dedicated local profiles, each keeping its own watch history, bookmarks, addon configuration, and UI preferences.
* **Extensible Addon Architecture** — Connect external Stremio-protocol addons to query stream sources. 
* **Cloud Sync (Optional)** — Firebase Auth + Firestore integration to seamlessly back up libraries and profile preferences across devices.

---

## What It Doesn't Do

* **No Stream Hosting or Indexing** — GAnime does not host, provide, scrape, or bundle stream sources out of the box. Users configure their own external addons via standard Stremio manifests.
* **No Mandatory Logins** — 100% functional offline and locally without creating an account.
* **No Ads or Paywalls** — Completely free and open source.

---

## Installation

1. Grab the latest `.apk` from the [Releases](../../releases) section (or download the `ganime-test-apk` artifact from the latest green GitHub Actions workflow run).
2. Install the APK on your Android device (ensure *Install Unknown Apps* permission is enabled for your file manager or browser).
3. Launch GAnime, configure your preferred metadata/addons, and enjoy!

---

## Tech Stack

* **Framework:** Flutter (Dart)
* **Player Core:** `media_kit` (libmpv backend with native Android surface rendering)
* **Metadata & Catalog:** AniList GraphQL API, ani.zip
* **Skipping Engine:** AniSkip REST API
* **Backend / Sync:** Firebase Authentication & Cloud Firestore (optional sync layer)

---

## Credits & Team

* **Isolated** — Product Owner, Architecture & Lead Testing
* **Nounou (Muse)** — Core Implementation & Deployment Pipeline
* **Gemini** — UI/UX & Glassmorphic Design Collaboration
* **Kimi** — Diagnostics & Architecture Review

---

## Disclaimer

*GAnime is an open-source fan project and is not affiliated with AniList, MyAnimeList, or Simkl. All anime metadata, cover art, and episode details belong to their respective copyright holders.*
