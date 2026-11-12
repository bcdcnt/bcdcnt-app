import 'package:flutter/material.dart';
import '../constants/theme.dart';
import '../services/api.dart' show formatInt;
import 'ui.dart';

/// A period of Dòng thời gian (desktop): [from, to) years, its short name,
/// the full title and the look of its card. `to` 0 = now.
class Era {
  final String slug, name, title;
  final int from, to;
  final EraStyle style;
  const Era(this.slug, this.from, this.to, this.name, this.title, this.style);

  /// Exclusive upper year, now included for the open-ended last period.
  int get toYear => to == 0 ? DateTime.now().year + 1 : to;
  String get years => '$from–${to == 0 ? 'nay' : to}';
}

const kEras = [
  Era('tien-chien', 1930, 1945, 'Tiền chiến', 'Nhạc tiền chiến', EraStyle.sepia),
  Era('chong-phap', 1945, 1954, 'Chống Pháp', 'Kháng chiến chống Pháp', EraStyle.bw),
  Era('chong-my', 1954, 1975, 'Chống Mỹ', 'Kháng chiến chống Mỹ', EraStyle.red),
  Era('sau-giai-phong', 1975, 1986, 'Sau giải phóng', 'Sau giải phóng', EraStyle.blue),
  Era('doi-moi', 1986, 2000, 'Đổi mới', 'Thời kỳ Đổi mới', EraStyle.baocap),
  Era('sau-2000', 2000, 0, 'Sau 2000', 'Sau năm 2000', EraStyle.now),
];

Era? eraBySlug(String slug) => kEras.where((e) => e.slug == slug).firstOrNull;

/// How each period looks: an old sepia print, rough black and white, the
/// war years in red, blue after 1975, the faded yellow of the subsidy era
/// prints, and today in true colour.
enum EraStyle { sepia, bw, red, blue, baocap, now }

const _gray = <double>[0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0];
const _sepia = <double>[0.393, 0.769, 0.189, 0, -20, 0.349, 0.686, 0.168, 0, -26, 0.272, 0.534, 0.131, 0, -34, 0, 0, 0, 1, 0];

List<double> _contrast(double c, double b) {
  final t = (1 - c) * 128 + b;
  return [c, 0, 0, 0, t, 0, c, 0, 0, t, 0, 0, c, 0, t, 0, 0, 0, 1, 0];
}

List<double> _mul(List<double> a, List<double> b) {
  final o = List<double>.filled(20, 0);
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 5; c++) {
      var v = c == 4 ? a[r * 5 + 4] : 0.0;
      for (var k = 0; k < 4; k++) {
        v += a[r * 5 + k] * b[k * 5 + c];
      }
      o[r * 5 + c] = v;
    }
  }
  return o;
}

/// Background, the colour text sits on, a multiply tint, a colour matrix
/// and the text colour of a period.
(Color, Color, Color?, List<double>?, Color) _look(EraStyle s) => switch (s) {
      EraStyle.sepia => (const Color(0xFF3B2618), const Color(0xFF3B2618), const Color(0xFF8A5A34), _mul(_contrast(1.1, -28), _mul(_sepia, _gray)), const Color(0xFFF6E9D6)),
      EraStyle.bw => (const Color(0xFF1E1D1B), const Color(0xFF1E1D1B), null, _mul(_contrast(1.35, -20), _gray), const Color(0xFFF2EEE6)),
      EraStyle.red => (const Color(0xFF8E1F1F), const Color(0xFF8E1F1F), const Color(0xFF8E1F1F), _gray, Colors.white),
      EraStyle.blue => (const Color(0xFF1F4F6E), const Color(0xFF1F4F6E), const Color(0xFF1F4F6E), _gray, Colors.white),
      EraStyle.baocap => (const Color(0xFFC9A04A), const Color(0xFF8A621E), const Color(0xFFE2B550), _sepia, const Color(0xFFFFF8E8)),
      EraStyle.now => (const Color(0xFFFBF7F4), Colors.white, null, null, const Color(0xFF161112)),
    };

/// A period's picture treated in its style, with the fade text sits on:
/// downward on the home rail's tall cards, sideways on the wide page head.
class EraBackdrop extends StatelessWidget {
  final EraStyle style;
  final String? image;
  final bool wide;
  const EraBackdrop({super.key, required this.style, this.image, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final (_, end, tint, m, _) = _look(style);
    final light = style == EraStyle.now;
    Widget pic = image == null ? const SizedBox.shrink() : NetImage(url: image);
    if (m != null) pic = ColorFiltered(colorFilter: ColorFilter.matrix(m), child: pic);
    if (tint != null) pic = ColorFiltered(colorFilter: ColorFilter.mode(tint.withValues(alpha: style == EraStyle.baocap ? 0.55 : 0.9), BlendMode.multiply), child: pic);
    return Stack(fit: StackFit.expand, children: [
      pic,
      if (style == EraStyle.sepia || style == EraStyle.bw)
        DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(radius: 0.9, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)], stops: const [0.55, 1]))),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: wide
              ? LinearGradient(colors: [end.withValues(alpha: light ? 0.96 : 1), end.withValues(alpha: light ? 0.2 : 0.2)], stops: const [0.35, 1])
              : LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [end.withValues(alpha: 0), end.withValues(alpha: light ? 0.92 : 1)], stops: light ? const [0.2, 0.7] : const [0.3, 0.86]),
        ),
      ),
    ]);
  }
}

Color eraBg(EraStyle s) => _look(s).$1;
Color eraFg(EraStyle s) => _look(s).$5;
Color eraSubFg(EraStyle s) => s == EraStyle.now ? const Color(0xFF665C5E) : eraFg(s).withValues(alpha: 0.85);

/// Home rail card: tap opens the period's page, the round ▶ in the corner
/// plays it straight away.
class EraCard extends StatelessWidget {
  final Era era;
  final int? count;
  final String? image;
  final bool busy;
  final VoidCallback onTap, onPlay;
  const EraCard({super.key, required this.era, this.count, this.image, this.busy = false, required this.onTap, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final fg = eraFg(era.style);
    final sub = TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: eraSubFg(era.style));
    return Semantics(
      button: true,
      label: '${era.name}, ${era.years}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 150,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: eraBg(era.style), borderRadius: BorderRadius.circular(18), border: era.style == EraStyle.now ? Border.all(color: const Color(0xFFECE4E4)) : null),
          child: Stack(fit: StackFit.expand, children: [
            EraBackdrop(style: era.style, image: image),
            Positioned(
              top: 10, right: 10,
              child: Semantics(
                button: true,
                label: 'Phát ${era.name}',
                child: GestureDetector(
                  onTap: onPlay,
                  child: Container(
                    width: 38, height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))]),
                    child: busy
                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.wine))
                        : Icon(Icons.play_arrow_rounded, size: 24, color: AppColors.wine),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12, right: 12, bottom: 12,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(era.years, style: body(sub)),
                const SizedBox(height: 2),
                Text(era.name, maxLines: 2, style: display(TextStyle(fontSize: 18, height: 1.15, letterSpacing: -0.3, fontWeight: FontWeight.w800, color: fg))),
                const SizedBox(height: 4),
                Text(count == null ? ' ' : '${formatInt(count)} bài', style: body(sub.copyWith(fontSize: 11, fontWeight: FontWeight.w700))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
