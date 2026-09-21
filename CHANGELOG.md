# Changelog

## 0.4.0 (in progress)

- Added persistent XMLTV EPG caching using the platform application-support directory.
- Cached guide data is scoped to the provider EPG URL and expires after six hours.
- Cache writes prune stale programmes and cap future guide data to seven days to keep disk usage bounded.
- Added force-refresh support for the TV guide.
- Added JSON serialization tests for cached EPG programme data.
- Replaced the basic guide list with a four-hour visual EPG timeline and current-time marker.
- Added two Windows mini-player layouts: Detailed and Video-only.
- Video-only mini-player hides app chrome and reveals controls on hover.
- Mini-player layout preference is remembered between sessions.
- Mini mode now temporarily lowers the Windows minimum-size limit so the player can actually shrink, then restores the normal limit on exit.
- Added TV Guide navigation for Now, ±2 hours and the next seven days.
- Added programme-detail sheets with descriptions and direct Watch actions.
- Added playback aspect modes: Auto, 16:9, 4:3 and Fill/Crop.
- Added desktop keyboard controls: Space play/pause, arrows seek/volume, M mute, A aspect mode, Page Up/Down live channels.
- Added automatic live-stream reconnect attempts with manual retry fallback.
- Added remembered mini-player size and position per mini-player layout.
- Video-only mini-player hides the native title bar and supports drag-to-move.
- Added multiple securely stored IPTV profiles to Open Edition.
- Added profile switching, renaming, removal and Add Account flow.
- Added saved-profile model tests.

## 0.3.0

- Added a dedicated movie details screen with poster, plot, metadata, favorite action and resume button.
- Added audio-track selection from streams that expose multiple audio tracks.
- Added subtitle selection, including automatic/off options when exposed by the playback engine.
- Added buffering feedback during playback.
- Added playback-error overlay and in-player stream retry.
- Kept Windows always-on-top mini-player support and shared Open/SB provider build modes.

## 0.2.0

- Added Xtream VOD movie catalog support.
- Added series, seasons, episode retrieval and playback.
- Added XMLTV EPG loading with Now/Next channel information.
- Added a TV Guide view.
- Added encrypted favorites and recent-history persistence.
- Added resume positions for movies and episodes.
- Added Windows always-on-top mini-player mode.
- Kept Open Edition and SB-locked Edition in one codebase.

## 0.1.0

- Initial Windows-first Flutter scaffold.
- Xtream login and live channels.
- M3U playlists and groups.
- Secure account persistence.
- media_kit playback.
- Open and SB-locked distributions.
