/// Group timestamped feed items into "Hôm nay / Hôm qua / Tuần này / Tháng MM/YYYY"
/// buckets in the order they appear, preserving the original sort.
///
/// Returns a flat list of either a [String] header or the original item.
/// Render with: `if (entry is String) renderHeader(entry) else renderRow(entry)`.

const _weekdays = ['Chủ nhật', 'Thứ hai', 'Thứ ba', 'Thứ tư', 'Thứ năm', 'Thứ sáu', 'Thứ bảy'];

String _bucketLabel(DateTime ts, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(ts.year, ts.month, ts.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Hôm nay';
  if (diff == 1) return 'Hôm qua';
  if (diff < 7) return _weekdays[ts.weekday % 7];
  if (ts.year == now.year && ts.month == now.month) return 'Tuần này';
  if (ts.year == now.year) return 'Tháng ${ts.month.toString().padLeft(2, '0')}';
  return 'Tháng ${ts.month.toString().padLeft(2, '0')}/${ts.year}';
}

DateTime? _parse(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toLocal();
  if (raw is String) {
    return DateTime.tryParse(raw)?.toLocal();
  }
  return null;
}

/// Insert section header strings between feed items grouped by day.
/// [getDate] returns the timestamp for an item.
List<Object> groupByDay<T>(List<T> items, dynamic Function(T) getDate) {
  if (items.isEmpty) return [];
  final out = <Object>[];
  final now = DateTime.now();
  String? lastLabel;
  for (final item in items) {
    final ts = _parse(getDate(item));
    final label = ts == null ? 'Khác' : _bucketLabel(ts, now);
    if (label != lastLabel) {
      out.add(label);
      lastLabel = label;
    }
    out.add(item as Object);
  }
  return out;
}
