import 'dart:math' as math;

/// Vietnamese lunar date (âm lịch) for a solar date, Hồ Ngọc Đức's algorithm
/// at UTC+7. Listeners of this site live by the lunar calendar (rằm, mùng
/// một, giỗ), so the home greeting shows it next to the solar date.
class LunarDate {
  final int day, month, year;
  final bool leap;
  const LunarDate(this.day, this.month, this.year, this.leap);

  static int _jd(int dd, int mm, int yy) {
    final a = (14 - mm) ~/ 12;
    final y = yy + 4800 - a;
    final m = mm + 12 * a - 3;
    var jd = dd + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - y ~/ 100 + y ~/ 400 - 32045;
    if (jd < 2299161) jd = dd + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - 32083;
    return jd;
  }

  static int _newMoon(int k, double tz) {
    final t = k / 1236.85, t2 = t * t, t3 = t2 * t, dr = math.pi / 180;
    var jd1 = 2415020.75933 + 29.53058868 * k + 0.0001178 * t2 - 0.000000155 * t3;
    jd1 += 0.00033 * math.sin((166.56 + 132.87 * t - 0.009173 * t2) * dr);
    final m = 359.2242 + 29.10535608 * k - 0.0000333 * t2 - 0.00000347 * t3;
    final mpr = 306.0253 + 385.81691806 * k + 0.0107306 * t2 + 0.00001236 * t3;
    final f = 21.2964 + 390.67050646 * k - 0.0016528 * t2 - 0.00000239 * t3;
    var c1 = (0.1734 - 0.000393 * t) * math.sin(m * dr) + 0.0021 * math.sin(2 * dr * m);
    c1 = c1 - 0.4068 * math.sin(mpr * dr) + 0.0161 * math.sin(dr * 2 * mpr);
    c1 = c1 - 0.0004 * math.sin(dr * 3 * mpr);
    c1 = c1 + 0.0104 * math.sin(dr * 2 * f) - 0.0051 * math.sin(dr * (m + mpr));
    c1 = c1 - 0.0074 * math.sin(dr * (m - mpr)) + 0.0004 * math.sin(dr * (2 * f + m));
    c1 = c1 - 0.0004 * math.sin(dr * (2 * f - m)) - 0.0006 * math.sin(dr * (2 * f + mpr));
    c1 = c1 + 0.0010 * math.sin(dr * (2 * f - mpr)) + 0.0005 * math.sin(dr * (2 * mpr + m));
    final deltat = t < -11 ? 0.001 + 0.000839 * t + 0.0002261 * t2 - 0.00000845 * t3 - 0.000000081 * t * t3 : -0.000278 + 0.000265 * t + 0.000262 * t2;
    return (jd1 + c1 - deltat + 0.5 + tz / 24).floor();
  }

  static int _sunLong(int jdn, double tz) {
    final t = (jdn - 2451545.5 - tz / 24) / 36525, t2 = t * t, dr = math.pi / 180;
    final m = 357.52910 + 35999.05030 * t - 0.0001559 * t2 - 0.00000048 * t * t2;
    final l0 = 280.46645 + 36000.76983 * t + 0.0003032 * t2;
    var dl = (1.914600 - 0.004817 * t - 0.000014 * t2) * math.sin(dr * m);
    dl += (0.019993 - 0.000101 * t) * math.sin(dr * 2 * m) + 0.000290 * math.sin(dr * 3 * m);
    var l = (l0 + dl) * dr;
    l = l - math.pi * 2 * (l / (math.pi * 2)).floor();
    return (l / math.pi * 6).floor();
  }

  static int _month11(int yy, double tz) {
    final off = _jd(31, 12, yy) - 2415021;
    final k = (off / 29.530588853).floor();
    var nm = _newMoon(k, tz);
    if (_sunLong(nm, tz) >= 9) nm = _newMoon(k - 1, tz);
    return nm;
  }

  static int _leapOffset(int a11, double tz) {
    final k = ((a11 - 2415021.076998695) / 29.530588853 + 0.5).floor();
    var i = 1;
    var arc = _sunLong(_newMoon(k + i, tz), tz);
    int last;
    do {
      last = arc;
      i++;
      arc = _sunLong(_newMoon(k + i, tz), tz);
    } while (arc != last && i < 14);
    return i - 1;
  }

  factory LunarDate.fromSolar(DateTime d, {double tz = 7}) {
    final dayNumber = _jd(d.day, d.month, d.year);
    final k = ((dayNumber - 2415021.076998695) / 29.530588853).floor();
    var monthStart = _newMoon(k + 1, tz);
    if (monthStart > dayNumber) monthStart = _newMoon(k, tz);
    var a11 = _month11(d.year, tz);
    var b11 = a11;
    int lunarYear;
    if (a11 >= monthStart) {
      lunarYear = d.year;
      a11 = _month11(d.year - 1, tz);
    } else {
      lunarYear = d.year + 1;
      b11 = _month11(d.year + 1, tz);
    }
    final lunarDay = dayNumber - monthStart + 1;
    final diff = ((monthStart - a11) / 29).floor();
    var leap = false;
    var lunarMonth = diff + 11;
    if (b11 - a11 > 365) {
      final leapDiff = _leapOffset(a11, tz);
      if (diff >= leapDiff) {
        lunarMonth = diff + 10;
        if (diff == leapDiff) leap = true;
      }
    }
    if (lunarMonth > 12) lunarMonth -= 12;
    if (lunarMonth >= 11 && diff < 4) lunarYear -= 1;
    return LunarDate(lunarDay, lunarMonth, lunarYear, leap);
  }

  /// "Rằm tháng Chín", "Mùng 1 tháng Mười", "26 tháng Chín âm lịch".
  String get label {
    const months = ['Giêng', 'Hai', 'Ba', 'Tư', 'Năm', 'Sáu', 'Bảy', 'Tám', 'Chín', 'Mười', 'Một', 'Chạp'];
    final m = 'tháng ${leap ? 'nhuận ' : ''}${months[month - 1]}';
    if (day == 15) return 'Rằm $m';
    if (day <= 10) return 'Mùng $day $m';
    return '$day $m âm lịch';
  }
}
