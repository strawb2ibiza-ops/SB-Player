# Changelog

## 0.4.0 (in progress)

- Added persistent XMLTV EPG caching using the platform application-support directory.
- Cached guide data is scoped to the provider EPG URL and expires after six hours.
- Cache writes prune stale programmes and cap future guide data to two days to keep disk usage bounded.
- Added force-refresh support for the TV guide.
- Added JSON serialization tests for cached EPG programme data.

## 0.3.0

- Added a dedicated movie details screen with poster, plot, metadata, favorite action and resume button.
- Added audio-track selection from streams that expose multiple audio tracks.
- Added subtitle selection, including automatic/off options when exposed by the playback engine.
- Added buffering feedback during playback.
- Added playback-error overlay and in-player stream retry.
- Kept Windows always-on-top mini-player support and shared Open/SB provider build modes.

# Changelog

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
