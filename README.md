# SB Player v0.4 development

Windows-first Flutter IPTV player with two distributions from one codebase:

- **Open Edition** — users can sign in with an Xtream-compatible account or an M3U playlist URL.
- **SB Edition** — compiled with a fixed SB provider endpoint; customers see only username/password and cannot edit the server or add M3U sources.

Use only with IPTV services and content you are authorized to access or distribute.

## Implemented

### Accounts and provider modes

- Xtream-compatible authentication through `player_api.php`
- Open Edition server + username + password login
- Open Edition M3U URL support
- SB Edition build-time provider lock
- Secure account credential persistence with `flutter_secure_storage`
- Account-expiry display when provided by the service

### Live TV

- Live categories
- Channel logos
- Search and category filtering
- Video playback with `media_kit`
- XMLTV EPG support
- Now/Next programme information
- TV Guide view
- Six-hour persistent EPG cache with manual force refresh

### Movies and series

- Xtream VOD categories and movie catalog
- Movie artwork, rating and release metadata when supplied
- Series categories and catalog
- Season and episode retrieval
- Episode playback
- Resume positions for movies and episodes
- Movie details screen with overview, metadata and resume action

### Library

- Favorites
- Recently watched
- Continue/resume positions
- Library data stored in platform secure storage because IPTV playback URLs can contain account tokens or credentials

### Windows playback

- Full player controls through `media_kit_video`
- Audio-track and subtitle selection
- Buffering indicator, playback-error overlay and retry action
- Hardware-accelerated playback through `media_kit`
- Always-on-top mini-player mode using `window_manager`

## Requirements

Install the current stable Flutter SDK with Windows desktop support and Visual Studio's **Desktop development with C++** workload. The Windows secure-storage implementation may also require Visual Studio C++ ATL components.

From the project directory:

```powershell
.\scripts\bootstrap_windows.ps1
```

This creates the native Windows/Android runner folders for the installed Flutter version and resolves packages.

## Run the Open Edition

```powershell
.\scripts\run_open.ps1
```

## Run the SB Edition

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

The SB Edition deliberately removes server/M3U controls from the customer interface and obtains the provider endpoint from a compile-time build value.

That prevents normal customers from switching providers inside the application, but **a provider URL embedded in a desktop or mobile client is not a secret**. A determined person can inspect binaries or network traffic. Never embed reseller-panel credentials, administrator passwords, API master secrets, or a shared IPTV customer login in the application.

Customer-specific credentials and local library data are stored through platform secure storage.

## Build flags

| Flag | Purpose |
|---|---|
| `SB_LOCKED=true` | Enables SB provider-locked mode |
| `SB_PROVIDER_BASE_URL=...` | Fixed authorized SB provider base URL |

## Project layout

```text
lib/
  main.dart
  src/
    config/       distribution/build configuration
    models/       account, live, VOD, series, playback and EPG models
    services/     Xtream, M3U, XMLTV and secure persistence
    state/        application/session/catalog controller
    ui/           login, browser, TV guide, series and player UI
scripts/          Windows bootstrap/run/build commands
test/             parser and model tests
.github/           CI checks
```

## Planned next milestones

1. Improved TV Guide timeline layout and EPG caching.
2. Multiple IPTV accounts in the Open Edition.
3. SB production logo/branding assets.
4. Windows installer and code-signing workflow.
5. iOS/Android shells with native Picture-in-Picture and mobile controls.
6. AirPlay / casting where supported by the target platform and playback source.
