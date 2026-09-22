import '../models/epg_program.dart';
import '../models/iptv_account.dart';
import '../models/iptv_category.dart';
import '../models/iptv_channel.dart';
import '../models/series_item.dart';
import '../models/vod_item.dart';

class DebugCatalog {
  static const account = IptvAccount(
    type: AccountType.xtream,
    label: 'UI Debug',
    serverUrl: 'https://debug.sbplayer.invalid',
    username: 'debug',
    password: '',
  );

  static const liveCategories = [
    IptvCategory(id: 'news', name: 'News'),
    IptvCategory(id: 'sports', name: 'Sports'),
    IptvCategory(id: 'entertainment', name: 'Entertainment'),
    IptvCategory(id: 'movies', name: 'Movie Channels'),
    IptvCategory(id: 'kids', name: 'Kids'),
  ];

  static const channels = [
    IptvChannel(id: '1', name: 'SB News 24', streamUrl: '', categoryId: 'news', logoUrl: 'https://placehold.co/256x256/0C1426/54C9FF/png?text=SB+NEWS', epgId: 'debug-1'),
    IptvChannel(id: '2', name: 'World News', streamUrl: '', categoryId: 'news', logoUrl: 'https://placehold.co/256x256/0C1426/54C9FF/png?text=WORLD', epgId: 'debug-2'),
    IptvChannel(id: '3', name: 'Sports One', streamUrl: '', categoryId: 'sports', logoUrl: 'https://placehold.co/256x256/0C1426/54C9FF/png?text=SPORTS+1', epgId: 'debug-3'),
    IptvChannel(id: '4', name: 'Premier Sports', streamUrl: '', categoryId: 'sports', logoUrl: 'https://placehold.co/256x256/0C1426/54C9FF/png?text=PREMIER', epgId: 'debug-4'),
    IptvChannel(id: '5', name: 'SB Entertainment', streamUrl: '', categoryId: 'entertainment', logoUrl: 'https://placehold.co/256x256/0C1426/54C9FF/png?text=SB+ENT', epgId: 'debug-5'),
    IptvChannel(id: '6', name: 'Comedy Central Test', streamUrl: '', categoryId: 'entertainment', logoUrl: 'https://placehold.co/256x256/0C1426/54C9FF/png?text=COMEDY', epgId: 'debug-6'),
    IptvChannel(id: '7', name: 'Cinema Premiere', streamUrl: '', categoryId: 'movies', logoUrl: 'https://placehold.co/256x256/0C1426/54C9FF/png?text=CINEMA', epgId: 'debug-7'),
    IptvChannel(id: '8', name: 'Action Movies', streamUrl: '', categoryId: 'movies', logoUrl: 'https://placehold.co/256x256/0C1426/54C9FF/png?text=ACTION', epgId: 'debug-8'),
    IptvChannel(id: '9', name: 'Kids Zone', streamUrl: '', categoryId: 'kids', logoUrl: 'https://placehold.co/256x256/0C1426/54C9FF/png?text=KIDS', epgId: 'debug-9'),
    IptvChannel(id: '10', name: 'Family TV', streamUrl: '', categoryId: 'kids', logoUrl: 'https://placehold.co/256x256/0C1426/54C9FF/png?text=FAMILY', epgId: 'debug-10'),
    IptvChannel(id: '11', name: 'Documentary HD', streamUrl: '', categoryId: 'entertainment', logoUrl: 'https://placehold.co/256x256/0C1426/54C9FF/png?text=DOC+HD', epgId: 'debug-11'),
    IptvChannel(id: '12', name: 'Music Live', streamUrl: '', categoryId: 'entertainment', logoUrl: 'https://placehold.co/256x256/0C1426/54C9FF/png?text=MUSIC', epgId: 'debug-12'),
  ];

  static const movieCategories = [
    IptvCategory(id: 'popular', name: 'Popular'),
    IptvCategory(id: 'action', name: 'Action'),
    IptvCategory(id: 'scifi', name: 'Sci-Fi'),
    IptvCategory(id: 'drama', name: 'Drama'),
  ];

  static const movies = [
    VodItem(id: '101', posterUrl: 'https://picsum.photos/seed/sbmovie1/600/900', name: 'Dune: Part Two', streamUrl: '', categoryId: 'scifi', rating: 8.5, releaseDate: '2024-03-01', plot: 'Debug catalogue item for testing movie layouts.'),
    VodItem(id: '102', posterUrl: 'https://picsum.photos/seed/sbmovie2/600/900', name: 'Oppenheimer', streamUrl: '', categoryId: 'drama', rating: 8.6, releaseDate: '2023-07-21', plot: 'Debug catalogue item for testing movie layouts.'),
    VodItem(id: '103', posterUrl: 'https://picsum.photos/seed/sbmovie3/600/900', name: 'The Batman', streamUrl: '', categoryId: 'action', rating: 7.8, releaseDate: '2022-03-04', plot: 'Debug catalogue item for testing movie layouts.'),
    VodItem(id: '104', posterUrl: 'https://picsum.photos/seed/sbmovie4/600/900', name: 'Top Gun: Maverick', streamUrl: '', categoryId: 'action', rating: 8.2, releaseDate: '2022-05-27'),
    VodItem(id: '105', posterUrl: 'https://picsum.photos/seed/sbmovie5/600/900', name: 'Interstellar', streamUrl: '', categoryId: 'scifi', rating: 8.7, releaseDate: '2014-11-07'),
    VodItem(id: '106', posterUrl: 'https://picsum.photos/seed/sbmovie6/600/900', name: 'Inception', streamUrl: '', categoryId: 'scifi', rating: 8.8, releaseDate: '2010-07-16'),
    VodItem(id: '107', posterUrl: 'https://picsum.photos/seed/sbmovie7/600/900', name: 'The Dark Knight', streamUrl: '', categoryId: 'action', rating: 9.0, releaseDate: '2008-07-18'),
    VodItem(id: '108', posterUrl: 'https://picsum.photos/seed/sbmovie8/600/900', name: 'Gladiator', streamUrl: '', categoryId: 'drama', rating: 8.5, releaseDate: '2000-05-05'),
    VodItem(id: '109', posterUrl: 'https://picsum.photos/seed/sbmovie9/600/900', name: 'Blade Runner 2049', streamUrl: '', categoryId: 'scifi', rating: 8.0, releaseDate: '2017-10-06'),
    VodItem(id: '110', posterUrl: 'https://picsum.photos/seed/sbmovie10/600/900', name: 'Mad Max: Fury Road', streamUrl: '', categoryId: 'action', rating: 8.1, releaseDate: '2015-05-15'),
    VodItem(id: '111', posterUrl: 'https://picsum.photos/seed/sbmovie11/600/900', name: 'The Shawshank Redemption', streamUrl: '', categoryId: 'drama', rating: 9.3, releaseDate: '1994-09-23'),
    VodItem(id: '112', posterUrl: 'https://picsum.photos/seed/sbmovie12/600/900', name: 'The Matrix', streamUrl: '', categoryId: 'scifi', rating: 8.7, releaseDate: '1999-03-31'),
  ];

  static const seriesCategories = [
    IptvCategory(id: 'drama', name: 'Drama'),
    IptvCategory(id: 'scifi', name: 'Sci-Fi'),
    IptvCategory(id: 'comedy', name: 'Comedy'),
    IptvCategory(id: 'crime', name: 'Crime'),
  ];

  static const series = [
    SeriesItem(id: '201', coverUrl: 'https://picsum.photos/seed/sbseries1/600/900', name: 'Breaking Bad', categoryId: 'crime', rating: 9.5, releaseDate: '2008-01-20', plot: 'Debug series for UI testing.'),
    SeriesItem(id: '202', coverUrl: 'https://picsum.photos/seed/sbseries2/600/900', name: 'Stranger Things', categoryId: 'scifi', rating: 8.7, releaseDate: '2016-07-15'),
    SeriesItem(id: '203', coverUrl: 'https://picsum.photos/seed/sbseries3/600/900', name: 'The Last of Us', categoryId: 'drama', rating: 8.7, releaseDate: '2023-01-15'),
    SeriesItem(id: '204', coverUrl: 'https://picsum.photos/seed/sbseries4/600/900', name: 'The Office', categoryId: 'comedy', rating: 9.0, releaseDate: '2005-03-24'),
    SeriesItem(id: '205', coverUrl: 'https://picsum.photos/seed/sbseries5/600/900', name: 'Better Call Saul', categoryId: 'crime', rating: 9.0, releaseDate: '2015-02-08'),
    SeriesItem(id: '206', coverUrl: 'https://picsum.photos/seed/sbseries6/600/900', name: 'Black Mirror', categoryId: 'scifi', rating: 8.7, releaseDate: '2011-12-04'),
    SeriesItem(id: '207', coverUrl: 'https://picsum.photos/seed/sbseries7/600/900', name: 'Succession', categoryId: 'drama', rating: 8.8, releaseDate: '2018-06-03'),
    SeriesItem(id: '208', coverUrl: 'https://picsum.photos/seed/sbseries8/600/900', name: 'The Boys', categoryId: 'drama', rating: 8.6, releaseDate: '2019-07-26'),
    SeriesItem(id: '209', coverUrl: 'https://picsum.photos/seed/sbseries9/600/900', name: 'Severance', categoryId: 'scifi', rating: 8.7, releaseDate: '2022-02-18'),
    SeriesItem(id: '210', coverUrl: 'https://picsum.photos/seed/sbseries10/600/900', name: 'Peaky Blinders', categoryId: 'crime', rating: 8.7, releaseDate: '2013-09-12'),
  ];

  static Map<String, List<EpgProgram>> epg(DateTime now) {
    final base = DateTime(now.year, now.month, now.day, now.hour)
        .subtract(const Duration(hours: 3));
    const titles = [
      'Morning Headlines', 'Live Breakfast', 'Newsroom', 'The Big Match',
      'Live Coverage', 'Studio Analysis', 'Movie Premiere', 'Classic Cinema',
      'Family Hour', 'Comedy Night', 'Documentary Special', 'Late Night Music',
    ];
    final result = <String, List<EpgProgram>>{};
    for (var channel = 0; channel < channels.length; channel++) {
      final id = 'debug-${channel + 1}';
      result[id] = List.generate(10, (slot) {
        final start = base.add(Duration(minutes: slot * 60));
        return EpgProgram(
          channelId: id,
          title: '${titles[(channel + slot) % titles.length]} ${slot + 1}',
          start: start,
          stop: start.add(const Duration(hours: 1)),
          description: 'Sample programme information for testing the SB Player TV guide, programme details, timeline and Now/Next UI.',
        );
      });
    }
    return result;
  }

  static SeriesDetails seriesDetails(SeriesItem item) {
    final seasons = <int, List<SeriesEpisode>>{};
    for (var season = 1; season <= 3; season++) {
      seasons[season] = List.generate(8, (index) {
        final episode = index + 1;
        return SeriesEpisode(
          id: '${item.id}-s$season-e$episode',
          title: 'Episode $episode',
          season: season,
          episodeNumber: episode,
          streamUrl: '',
          plot: 'Sample episode description for testing the series detail layout.',
          duration: '52 min',
        );
      });
    }
    return SeriesDetails(series: item, seasons: seasons);
  }
}
