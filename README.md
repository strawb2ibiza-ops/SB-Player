# SB Player v0.6.8

SB Player is a cross-platform Flutter IPTV player with mobile, TV and desktop builds from one codebase.

> Use SB Player only with services and content you are authorized to access or distribute.

## Downloads

The current public build is **v0.6.8**.

- **Android Mobile APK:** [SB-Player-Android-Mobile-v0.6.8.apk](https://github.com/strawb2ibiza-ops/SB-Player/releases/download/v0.6.8/SB-Player-Android-Mobile-v0.6.8.apk)
- **Android TV APK:** [SB-Player-Android-TV-v0.6.8.apk](https://github.com/strawb2ibiza-ops/SB-Player/releases/download/v0.6.8/SB-Player-Android-TV-v0.6.8.apk)
- **Android App Bundle:** [SB-Player-Android-Mobile-v0.6.8.aab](https://github.com/strawb2ibiza-ops/SB-Player/releases/download/v0.6.8/SB-Player-Android-Mobile-v0.6.8.aab)
- **iOS unsigned IPA:** [SB-Player-iOS-v0.6.8-unsigned.ipa](https://github.com/strawb2ibiza-ops/SB-Player/releases/download/v0.6.8/SB-Player-iOS-v0.6.8-unsigned.ipa)
- **Windows installer:** [SB-Player-Setup-v0.6.8.exe](https://github.com/strawb2ibiza-ops/SB-Player/releases/download/v0.6.8/SB-Player-Setup-v0.6.8.exe)
- **LG webOS:** [SB-Player-LG-v0.6.8.ipk](https://github.com/strawb2ibiza-ops/SB-Player/releases/download/v0.6.8/SB-Player-LG-v0.6.8.ipk)

[View the v0.6.8 release](https://github.com/strawb2ibiza-ops/SB-Player/releases/tag/v0.6.8)

The iOS package is unsigned and must be signed before installation.

## v0.6.8 testing build

This is the Android/iOS testing build promoted to the main branch. It includes the current mobile playback and library fixes plus the matching TV/desktop source.

### Mobile playback

- Native Picture-in-Picture integration for Android and iOS
- Continue Watching / resume-position handling
- Subtitle track selection and subtitle rendering support
- Series season and episode loading recovery
- Next-episode autoplay support
- Playback retry and recovery handling
- Mobile-friendly player controls

### Mobile and TV experience

- Android phone and Android TV builds
- TV pairing / remote-control screens
- QR-based TV linking support
- Android TV launcher support
- Dedicated LG webOS package
- Settings and account access in the current navigation

### Browsing and library

- Live TV, Movies and Series sections
- Search and category filtering
- Favorites
- Recently watched
- Continue Watching
- Artwork/poster support where provider metadata is available
- EPG / TV Guide support

## Provider modes

SB Player supports two distributions from the same codebase:

- **Open Edition** — users can sign in with an Xtream-compatible account or an M3U playlist URL.
- **SB Edition** — compiled with a fixed provider endpoint; customers see username/password login without editable server controls.

### Accounts and provider support

- Xtream-compatible authentication through `player_api.php`
- Open Edition server + username + password login
- Open Edition M3U URL support
- Multiple stored provider profiles in Open Edition
- Secure credential persistence with `flutter_secure_storage`
- Account-expiry display when supplied by the service
- SB Edition build-time provider lock

## Live TV

- Live categories and channel logos
- Search and category filtering
- Video playback with `media_kit`
- XMLTV EPG support
- Now/Next programme information
- Timeline-style TV Guide
- Persistent guide cache with manual refresh
- Programme detail views and Watch actions

## Movies and series

- VOD categories and movie catalog
- Movie artwork, rating and release metadata when supplied
- Series categories and catalog
- Season and episode retrieval
- Episode playback
- Resume positions for movies and episodes
- Movie details and resume actions
- Next-episode autoplay

## Library

- Favorites
- Recently watched
- Continue Watching / resume positions
- Local library data stored using platform storage

## Windows playback

- Full player controls through `media_kit_video`
- Audio-track and subtitle selection
- Buffering and playback-error handling
- Hardware-accelerated playback through `media_kit`
- Always-on-top mini-player using `window_manager`
- Detailed and video-only mini-player layouts
- Remembered mini-player size and position
- Auto / 16:9 / 4:3 / Fill display modes
- Keyboard playback shortcuts
- Automatic live-stream reconnect attempts

## Requirements

Install the current stable Flutter SDK and the native toolchains required for the platform you are building.

For Windows development, Visual Studio's **Desktop development with C++** workload is required. The Windows secure-storage implementation may also require Visual Studio C++ ATL components.

From the project directory:

```powershell
.\scripts\bootstrap_windows.ps1
```

## Run Open Edition

```powershell
.\scripts\run_open.ps1
```

## Run SB Edition

```powershell
.\scripts\run_sb.ps1 -ProviderUrl "https://YOUR-AUTHORIZED-SB-PROVIDER.example"
```

## Build Windows releases

Open Edition:

```powershell
.\scripts\build_open_windows.ps1
```

SB Edition:

```powershell
.\scripts\build_sb_windows.ps1 -ProviderUrl "https://YOUR-AUTHORIZED-SB-PROVIDER.example"
```

## Provider-lock security model

The SB Edition removes server/M3U controls from the customer interface and obtains the provider endpoint from a compile-time build value.

A provider URL embedded in a desktop or mobile client is not a secret. Do not embed reseller-panel credentials, administrator passwords, API master secrets, or a shared customer login in the application.

## Build flags

| Flag | Purpose |
|---|---|
| `SB_LOCKED=true` | Enables SB provider-locked mode |
| `SB_PROVIDER_BASE_URL=...` | Fixed authorized SB provider base URL |
| `SB_ANDROID_TV=true` | Builds the Android TV-oriented package |

## Project layout

```text
lib/
  main.dart
  src/
    config/       distribution/build configuration
    models/       account, live, VOD, series, playback and EPG models
    services/     provider, playback, pairing and persistence services
    state/        application/session/catalog controller
    ui/           login, browser, guide, series, settings, pairing and player UI
scripts/          build/bootstrap helpers
test/             parser, model and release-behaviour tests
webos/            LG webOS client
.github/           CI and release workflows
```

## CI

Every push to `main` runs analysis, tests and platform builds for Windows, iOS, Android and LG webOS. Successful main builds are used by the v0.6.8 release publishing workflow.
