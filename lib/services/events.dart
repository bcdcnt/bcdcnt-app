import 'api.dart';

/// Site event playlists (is_system, with event_start/event_end "MM-DD"):
/// the anniversaries the archive keeps a collection of songs for.
class SiteEvent {
  final Map<String, dynamic> playlist;
  final int day;
  final int month;
  /// The year it happened, when known ("81 năm" needs it).
  final int? year;
  SiteEvent(this.playlist, this.day, this.month, this.year);

  String get id => '${playlist['id']}';
  String get title => '${playlist['title'] ?? ''}';
  String get excerpt => '${playlist['excerpt'] ?? ''}'.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  int get songCount => ((playlist['items']?['paginatorInfo']?['total'] as num?) ?? 0).toInt();
  String? get cover => playlist['thumbnail']?['url']?.toString();

  /// This year's (or next year's, once passed) date of the event.
  DateTime nextDate(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(now.year, month, day);
    return d.isBefore(today) ? DateTime(now.year + 1, month, day) : d;
  }

  int daysUntil(DateTime now) => nextDate(now).difference(DateTime(now.year, now.month, now.day)).inDays;

  /// "81 năm" — years since, on its date this year.
  int? yearsOn(DateTime date) => year == null ? null : date.year - year!;

  bool runningOn(DateTime now) {
    final mmdd = '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final s = '${playlist['event_start'] ?? ''}', e = '${playlist['event_end'] ?? ''}';
    return s.compareTo(mmdd) <= 0 && e.compareTo(mmdd) >= 0;
  }
}

List<SiteEvent>? _cache;

/// Every event playlist, ordered by its date in the year.
Future<List<SiteEvent>> loadSiteEvents() async {
  if (_cache != null) return _cache!;
  final d = await ApiClient.query(r'''query($w: WhereConditions) { playlists(first: 200, orderBy: [{column: "event_start", order: ASC}], where: $w) { data { id slug title excerpt event_start event_end event_date thumbnail { url } items(first: 1) { paginatorInfo { total } } } } }''', {
    'w': {'AND': [
      {'column': 'is_system', 'value': '1'},
      {'column': 'is_public', 'value': '1'},
      {'column': 'event_start', 'operator': 'IS_NOT_NULL'},
    ]},
  });
  final out = <SiteEvent>[];
  for (final raw in ((d['playlists']?['data'] as List?) ?? const []).whereType<Map>()) {
    final p = Map<String, dynamic>.from(raw);
    // The day it's about is the last one: a week-long event leads up to it.
    final end = '${p['event_end'] ?? ''}'.split('-');
    if (end.length != 2) continue;
    final m = int.tryParse(end[0]), day = int.tryParse(end[1]);
    if (m == null || day == null) continue;
    int? year = int.tryParse('${p['event_date'] ?? ''}'.split('-').first);
    // Older entries keep the year only in the text: "Ngày 14/11/1945, …".
    year ??= int.tryParse(RegExp(r'\b\d{1,2}/\d{1,2}/(\d{4})\b').firstMatch('${p['excerpt'] ?? ''}')?.group(1) ?? '');
    out.add(SiteEvent(p, day, m, year));
  }
  out.sort((a, b) => a.month != b.month ? a.month.compareTo(b.month) : a.day.compareTo(b.day));
  return _cache = out;
}

const eventSongFields = 'id slug title subtitle views created_at play_type empty_file thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id slug title } } sheet { year composers(first: 2) { data { id slug title } } }';

/// The event's songs in playlist order, playable ones only.
Future<List<Map<String, dynamic>>> loadEventSongs(String id, {int first = 60}) async {
  // items, not songs: playlist.songs comes back empty for some event playlists.
  final d = await ApiClient.query('query(\$id: ID!) { playlist(id: \$id) { items(first: $first, orderBy: [{column: "position", order: ASC}]) { data { object { ... on Song { $eventSongFields } } } } } }', {'id': id});
  return [
    for (final it in ((d['playlist']?['items']?['data'] as List?) ?? const []).whereType<Map>())
      if (it['object'] is Map && (it['object'] as Map).isNotEmpty) {...Map<String, dynamic>.from(it['object'] as Map), 'file_type': 'song'},
  ].where((s) => s['empty_file'] != 1 && (s['file']?['audio_url'] != null || s['file']?['video_url'] != null)).toList();
}

const weekdaysVi = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
