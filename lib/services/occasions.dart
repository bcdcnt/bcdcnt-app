/// Fixed-date days the archive has songs for. Within two weeks of one, the
/// big "Gợi ý" cards play its songs.
const kOccasions = [
  (1, 1, 'Tết Dương lịch'), (3, 2, 'Ngày thành lập Đảng'), (8, 3, 'Quốc tế Phụ nữ'),
  (26, 3, 'Ngày thành lập Đoàn'), (30, 4, 'Ngày Giải phóng miền Nam'), (1, 5, 'Quốc tế Lao động'),
  (7, 5, 'Chiến thắng Điện Biên Phủ'), (19, 5, 'Sinh nhật Bác Hồ'), (1, 6, 'Quốc tế Thiếu nhi'),
  (27, 7, 'Ngày Thương binh Liệt sĩ'), (19, 8, 'Cách mạng Tháng Tám'), (2, 9, 'Quốc khánh'),
  (10, 10, 'Giải phóng Thủ đô'), (20, 10, 'Ngày Phụ nữ Việt Nam'), (20, 11, 'Ngày Nhà giáo Việt Nam'),
  (22, 12, 'Ngày thành lập Quân đội'),
];

/// Site playlists made for an occasion, used when BQT hasn't set up a
/// dated event playlist for it (playlist.event_start/event_end).
const kOccasionPlaylist = {
  'Quốc tế Phụ nữ': 27, 'Ngày Phụ nữ Việt Nam': 27, 'Ngày thành lập Đoàn': 1558,
  'Ngày Giải phóng miền Nam': 40, 'Sinh nhật Bác Hồ': 18, 'Ngày Nhà giáo Việt Nam': 12,
  'Ngày thành lập Quân đội': 6, 'Quốc khánh': 1, 'Giải phóng Thủ đô': 2,
};

typedef Occasion = ({int days, int day, int month, String label});

/// The nearest occasion within the next 14 days (today included).
Occasion? nextOccasion(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  Occasion? best;
  for (final (d, m, label) in kOccasions) {
    var date = DateTime(now.year, m, d);
    if (date.isBefore(today)) date = DateTime(now.year + 1, m, d);
    final days = date.difference(today).inDays;
    if (days <= 14 && (best == null || days < best.days)) best = (days: days, day: d, month: m, label: label);
  }
  return best;
}
