import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import 'ui.dart';

/// "Ngày này năm xưa" — birthdays and death anniversaries of composers and
/// singers in the coming week. Remembering these days is a habit of the
/// site's listeners, and the row changes every day without anyone editing it.
///
/// People's dob/mob/dod/mod are free text ("8" or "08"), so each month is
/// queried in both spellings and the dates are worked out here.
class AnniversaryRail extends StatefulWidget {
  /// Days ahead (after today) to include.
  final int window;
  const AnniversaryRail({super.key, this.window = 7});

  @override
  State<AnniversaryRail> createState() => _AnniversaryRailState();
}

class _Anniv {
  final Map<String, dynamic> person;
  final String route;
  final String role;
  final bool birth;
  final DateTime date;
  final int years;
  final int inDays;
  _Anniv(this.person, this.route, this.role, this.birth, this.date, this.years, this.inDays);
}

class _AnniversaryRailState extends State<AnniversaryRail> {
  List<_Anniv>? _items;

  late DateTime _loadedDay;
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    _load();
    // Home stays alive in the tab stack: refresh "Hôm nay" after midnight.
    _life = AppLifecycleListener(onResume: () {
      final now = DateTime.now();
      if (now.day != _loadedDay.day || now.month != _loadedDay.month) _load();
    });
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final today = DateTime.now();
    _loadedDay = today;
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(Duration(days: widget.window));
    final months = {start.month, end.month};
    final mVals = [for (final m in months) ...['$m', m.toString().padLeft(2, '0')]];
    const f = 'id title slug views dob mob yob dod mod yod avatar { url }';
    String q(String type, String col) =>
        '$type$col: $type(first: 100, where: {AND: [{column: "$col", operator: IN, value: \$m}]}, orderBy: [{column: "views", order: DESC}]) { data { $f } }';
    try {
      final d = await ApiClient.query(
        'query(\$m: Mixed) { ${q('composers', 'mob')} ${q('composers', 'mod')} ${q('artists', 'mob')} ${q('artists', 'mod')} }',
        {'m': mVals},
      );
      final out = <_Anniv>[];
      final seen = <String>{};
      void scan(String key, String route, String role, bool birth) {
        for (final raw in ((d[key]?['data'] as List?) ?? const []).whereType<Map>()) {
          final p = Map<String, dynamic>.from(raw);
          final day = int.tryParse('${p[birth ? 'dob' : 'dod']}'.trim());
          final month = int.tryParse('${p[birth ? 'mob' : 'mod']}'.trim());
          final year = int.tryParse('${p[birth ? 'yob' : 'yod']}'.trim());
          if (day == null || month == null || day < 1 || day > 31 || month < 1 || month > 12) continue;
          // Only people listeners will recognise: a photo, a known year, and
          // some listening history (skips obscure foreign entries).
          if ((p['avatar']?['url']?.toString() ?? '').isEmpty || year == null || year < 1800) continue;
          if (((p['views'] as num?) ?? 0) < 3000) continue;
          // Try this year's date, and next year's when the week crosses New Year.
          for (final y in [start.year, start.year + 1]) {
            final date = DateTime(y, month, day);
            // 29/2 in a non-leap year (or a typo like 31/11) rolls into the
            // next month: skip instead of showing the wrong day.
            if (date.month != month) break;
            final diff = date.difference(start).inDays;
            if (diff < 0 || date.isAfter(end)) continue;
            if (!seen.add('$route${p['id']}$birth')) break;
            out.add(_Anniv(p, route, role, birth, date, year != null && year > 1800 ? y - year : 0, diff));
            break;
          }
        }
      }

      scan('composersmob', '/nhac-si/', 'Nhạc sĩ', true);
      scan('composersmod', '/nhac-si/', 'Nhạc sĩ', false);
      scan('artistsmob', '/nghe-si/', 'Nghệ sĩ', true);
      scan('artistsmod', '/nghe-si/', 'Nghệ sĩ', false);
      int views(_Anniv a) => (a.person['views'] as num?)?.toInt() ?? 0;
      // Today first, then round anniversaries (100, 90… năm), then the best known.
      out.sort((a, b) {
        if (a.inDays != b.inDays) return a.inDays.compareTo(b.inDays);
        final ra = a.years > 0 && a.years % 10 == 0 ? 1 : 0, rb = b.years > 0 && b.years % 10 == 0 ? 1 : 0;
        if (ra != rb) return rb - ra;
        return views(b).compareTo(views(a));
      });
      if (mounted) setState(() => _items = out.take(10).toList());
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  String _when(_Anniv a) {
    if (a.inDays == 0) return 'Hôm nay';
    if (a.inDays == 1) return 'Ngày mai';
    return '${a.date.day}/${a.date.month}';
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Ngày này năm xưa', action: null),
      SizedBox(
        height: 28 + scale.scale(74),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => _card(items[i]),
        ),
      ),
    ]);
  }

  Widget _card(_Anniv a) {
    final p = a.person;
    final name = '${p['title'] ?? ''}';
    final today = a.inDays == 0;
    final what = a.birth ? 'Ngày sinh' : 'Ngày giỗ';
    // Say plainly which year it counts from: "Kỷ niệm 75 năm ngày sinh"
    // alone read like an age; living people get their age instead.
    // No death year on record is not proof of life: past ~100 we just
    // don't know, so fall back to "X năm ngày sinh".
    final alive = ('${p['yod'] ?? ''}'.trim().isEmpty || '${p['yod']}' == '0') && a.years < 100;
    final born = int.tryParse('${p['yob']}'.trim());
    final died = int.tryParse('${p['yod']}'.trim());
    final years = a.years <= 0
        ? what
        : a.birth
            ? (alive ? 'Tròn ${a.years} tuổi' : '${a.years} năm ngày sinh')
            : '${a.years} năm ngày mất';
    final origin = alive
        ? 'Sinh ${a.date.day}/${a.date.month}/${born ?? ''}'
        : [if (born != null) '$born', if (died != null) '$died'].join(' – ');
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${_when(a)}, ${a.role} $name, $years, $origin',
      hint: 'Mở trang ${a.role.toLowerCase()}',
      child: Material(
        color: today ? AppColors.accent : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('${a.route}${p['slug']}'),
          child: Container(
            width: 272,
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              NetImage(
                url: p['avatar']?['url']?.toString(),
                width: 52,
                height: 52,
                circle: true,
                tint: true,
                fallback: Container(
                  width: 52,
                  height: 52,
                  color: today ? Colors.white24 : AppColors.accentSoft,
                  alignment: Alignment.center,
                  child: Text(name.isEmpty ? '?' : name.characters.first, style: display(TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: today ? Colors.white : AppColors.accentLight))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_when(a).toUpperCase(), style: body(TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: today ? Colors.white70 : AppColors.accentLight))),
                  const SizedBox(height: 2),
                  Text('${a.role} $name', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.25, fontWeight: FontWeight.w800, color: today ? Colors.white : AppColors.text))),
                  const SizedBox(height: 2),
                  Text('$years · $origin', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600, color: today ? Colors.white : AppColors.textSecondary))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
