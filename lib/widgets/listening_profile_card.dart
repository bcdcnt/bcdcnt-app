import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';

/// "Gu nghe nhạc" card for the signed-in member: favourite decade,
/// composer and singer, minutes listened and how that compares to other
/// members this month. Falls back to all-time when this month is empty;
/// hides itself when the API doesn't offer myListeningProfile yet.
class ListeningProfileCard extends StatefulWidget {
  const ListeningProfileCard({super.key});
  @override
  State<ListeningProfileCard> createState() => _ListeningProfileCardState();
}

class _ListeningProfileCardState extends State<ListeningProfileCard> {
  Map<String, dynamic>? _p;

  static const _q = r'''query($period: String) { myListeningProfile(period: $period) {
    period minutes listens top_kind top_decade decade_share percentile
    top_composers { id title slug } top_artists { id title slug }
  } }''';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    try {
      var d = await auth.authedQuery(_q, {'period': 'month'});
      var p = d['myListeningProfile'] as Map?;
      if (p == null || (p['listens'] ?? 0) == 0) {
        d = await auth.authedQuery(_q, {'period': 'all'});
        p = d['myListeningProfile'] as Map?;
      }
      if (mounted && p != null && (p['listens'] ?? 0) > 0) setState(() => _p = Map<String, dynamic>.from(p!));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return const SizedBox.shrink();
    final month = p['period'] == 'month';
    final composers = ((p['top_composers'] ?? []) as List).whereType<Map>().toList();
    final artists = ((p['top_artists'] ?? []) as List).whereType<Map>().toList();
    final decade = p['top_decade'] is num ? (p['top_decade'] as num).toInt() : null;
    final headline = [
      if (decade != null) 'Thập niên ${decade % 100 == 0 ? decade : decade % 100}',
      if (composers.isNotEmpty) composers.first['title'],
      if (artists.isNotEmpty) artists.first['title'],
    ].join(' · ');
    final minutes = (p['minutes'] as num?)?.toInt() ?? 0;
    final listens = (p['listens'] as num?)?.toInt() ?? 0;
    final pct = (p['percentile'] as num?)?.toInt();
    final time = minutes >= 120 ? '${(minutes / 60).round()} giờ' : '$minutes phút';
    final sub = [
      '$time · ${formatViews(listens)} lượt nghe',
      if (pct != null && pct >= 50) 'nghe nhiều hơn $pct% thành viên',
    ].join(' · ');
    const white = Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [AppColors.wine, AppColors.rose])),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(month ? 'GU NGHE NHẠC THÁNG NÀY' : 'GU NGHE NHẠC CỦA BẠN', style: body(const TextStyle(fontSize: 12, letterSpacing: 0.9, fontWeight: FontWeight.w800, color: Color(0xCCFFFFFF)))),
            const SizedBox(height: 6),
            if (headline.isNotEmpty)
              Text(headline, style: display(const TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w800, color: white))),
            const SizedBox(height: 4),
            Text(sub, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xE6FFFFFF)))),
            if (composers.length + artists.length > 1) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in composers) _chip(context, c['title'], '/nhac-si/${c['slug']}'),
                for (final a in artists) _chip(context, a['title'], '/nghe-si/${a['slug']}'),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, dynamic label, String route) => Material(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text('$label', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
          ),
        ),
      );
}
