import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/events.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';

/// "Sự kiện" (/su-kien, canvas "Desktop · Trang Sự kiện"): the year's event
/// playlists. Up top the one running today, else the next; then 12 month
/// tiles to jump with; then every event by month, from this month round the
/// year. [focus] (an event id) scrolls to that event and marks it.
class EventsScreen extends StatefulWidget {
  final String? focus;
  const EventsScreen({super.key, this.focus});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  List<SiteEvent>? _events;
  List<Map<String, dynamic>> _heroSongs = const [];
  final _scroll = ScrollController();
  final Map<int, GlobalKey> _monthKeys = {for (var m = 1; m <= 12; m++) m: GlobalKey()};
  final Map<String, GlobalKey> _eventKeys = {};
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await loadSiteEvents();
      if (!mounted) return;
      setState(() => _events = l);
      final h = _hero;
      if (h != null) {
        final s = await loadEventSongs(h.id, first: 6);
        if (mounted) setState(() => _heroSongs = s);
      }
      if (widget.focus != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _eventKeys[widget.focus]?.currentContext;
          if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _events = const []);
    }
  }

  /// Running today, else the nearest ahead.
  SiteEvent? get _hero {
    final l = _events;
    if (l == null || l.isEmpty) return null;
    final now = DateTime.now();
    final running = l.where((e) => e.runningOn(now)).toList();
    if (running.isNotEmpty) return running.first;
    return ([...l]..sort((a, b) => a.daysUntil(now).compareTo(b.daysUntil(now)))).first;
  }

  Future<void> _playEvent(SiteEvent e) async {
    if (_busy != null) return;
    setState(() => _busy = e.id);
    try {
      final songs = await loadEventSongs(e.id);
      if (mounted && songs.isNotEmpty) playOrOpen(context, songs.first, songs, e.title);
    } catch (_) {}
    if (mounted) setState(() => _busy = null);
  }

  void _jump(int month) {
    final ctx = _monthKeys[month]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    final now = DateTime.now();
    return Material(
      color: AppColors.bg,
      child: LayoutBuilder(builder: (context, c) {
        final pad = c.maxWidth < 700 ? 20.0 : c.maxWidth < 1000 ? 28.0 : 40.0;
        final twoCols = c.maxWidth >= 900;
        return SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(pad, 28, pad, 56),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Sự kiện', style: display(TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: AppColors.text))),
                const SizedBox(height: 6),
                Text(
                  events == null ? 'Các ngày kỷ niệm trong năm' : '${events.length} ngày kỷ niệm trong năm, mỗi ngày một tuyển tập bài hát. Đến ngày, tuyển tập tự hiện ở Trang chủ.',
                  style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                ),
                if (events == null) ...[
                  const SizedBox(height: 28),
                  const Skeleton(height: 240, radius: 24),
                ] else if (events.isNotEmpty) ...[
                  if (_hero case final h?) _heroCard(h, now, c.maxWidth >= 1280),
                  const SizedBox(height: 44),
                  Text('Cả năm', style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text))),
                  const SizedBox(height: 4),
                  Text('Bấm một tháng để nhảy tới · số = số sự kiện', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                  const SizedBox(height: 16),
                  _monthStrip(events, now),
                  for (var i = 0; i < 12; i++) ...[
                    if (events.any((e) => e.month == (now.month - 1 + i) % 12 + 1)) _monthSection(events, (now.month - 1 + i) % 12 + 1, now, twoCols),
                  ],
                ],
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _heroCard(SiteEvent e, DateTime now, bool wide) {
    final date = e.nextDate(now);
    final days = e.daysUntil(now);
    final running = e.runningOn(now);
    final years = e.yearsOn(date);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 28),
      Row(children: [
        Expanded(child: Text(running ? 'Hôm nay' : 'Sắp tới', style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text)))),
        if (!running) Text('${weekdaysVi[date.weekday - 1]} ${e.day}/${e.month} · ${days == 1 ? 'ngày mai' : 'còn $days ngày'}', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
      ]),
      const SizedBox(height: 16),
      Container(
        key: _eventKeys.putIfAbsent(e.id, GlobalKey.new),
        padding: const EdgeInsets.fromLTRB(32, 28, 28, 28),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
        child: Row(children: [
          EventSheet(day: e.day, month: e.month, year: e.year),
          const SizedBox(width: 32),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (years != null && years > 0) Text('$years NĂM TRƯỚC, NGÀY NÀY', style: AppText.eyebrow),
              const SizedBox(height: 6),
              Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 28, height: 1.15, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: AppColors.text))),
              if (e.excerpt.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(e.excerpt, maxLines: 3, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, height: 1.5, fontWeight: FontWeight.w500, color: AppColors.textSecondary))),
              ],
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, children: [
                PillButton(label: 'Phát tất cả · ${e.songCount} bài', icon: Icons.play_arrow_rounded, height: 44, loading: _busy == e.id, onTap: () => _playEvent(e)),
                // White on the grey card (the secondary PillButton is the card's grey).
                Material(
                  color: AppColors.bg,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => context.push('/playlist/${e.id}'),
                    child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 18), alignment: Alignment.center, child: Text('Xem playlist', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text)))),
                  ),
                ),
              ]),
            ]),
          ),
          if (wide && _heroSongs.isNotEmpty) ...[
            const SizedBox(width: 24),
            for (final (i, s) in _heroSongs.take(3).indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              SizedBox(
                width: 124,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => playOrOpen(context, s, _heroSongs, e.title),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    NetImage(url: s['thumbnail']?['url']?.toString(), width: 124, height: 124, radius: 12, tint: true),
                    const SizedBox(height: 8),
                    Text('${s['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text))),
                    Text(songByline(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                  ]),
                ),
              ),
            ],
          ],
        ]),
      ),
    ]);
  }

  Widget _monthStrip(List<SiteEvent> events, DateTime now) => Row(children: [
        for (var m = 1; m <= 12; m++) ...[
          if (m > 1) const SizedBox(width: 8),
          Expanded(child: Builder(builder: (_) {
            final n = events.where((e) => e.month == m).length;
            final cur = m == now.month;
            return Opacity(
              opacity: n == 0 ? 0.45 : 1,
              child: Material(
                color: cur ? AppColors.wine : AppColors.bg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: cur ? BorderSide.none : BorderSide(color: AppColors.border)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: n == 0 ? null : () => _jump(m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(children: [
                      FittedBox(child: Text('THÁNG $m', style: body(TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: cur ? Colors.white : AppColors.textMuted)))),
                      const SizedBox(height: 2),
                      Text('$n', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cur ? Colors.white : AppColors.text))),
                    ]),
                  ),
                ),
              ),
            );
          })),
        ],
      ]);

  Widget _monthSection(List<SiteEvent> events, int m, DateTime now, bool twoCols) {
    final list = events.where((e) => e.month == m).toList();
    final rows = [for (final e in list) _row(e, now)];
    return Padding(
      key: _monthKeys[m],
      padding: const EdgeInsets.only(top: 36),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Tháng $m', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.text))),
          if (m == now.month) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: AppColors.wine, borderRadius: BorderRadius.circular(7)),
              child: Text('Tháng này', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white))),
            ),
          ],
        ]),
        const SizedBox(height: 14),
        if (twoCols)
          for (var i = 0; i < rows.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: rows[i]),
                const SizedBox(width: 12),
                Expanded(child: i + 1 < rows.length ? rows[i + 1] : const SizedBox()),
              ]),
            ),
          ]
        else
          for (final (i, r) in rows.indexed) ...[if (i > 0) const SizedBox(height: 12), r],
      ]),
    );
  }

  Widget _row(SiteEvent e, DateTime now) {
    final years = e.yearsOn(e.nextDate(now));
    final focused = widget.focus == e.id;
    return Material(
      key: _eventKeys.putIfAbsent(e.id, GlobalKey.new),
      color: AppColors.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: focused ? AppColors.wine : AppColors.border, width: focused ? 2 : 1)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/playlist/${e.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            EventSheet(day: e.day, month: e.month, small: true),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: years != null && years > 0 ? '$years năm · ${e.day}/${e.month}/${e.year}' : 'Hằng năm · ${e.day}/${e.month}', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accentFg)),
                    TextSpan(text: ' · ${e.songCount} bài'),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                ),
                if (e.excerpt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(e.excerpt, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary))),
                ],
              ]),
            ),
            const SizedBox(width: 12),
            Material(
              color: AppColors.wine,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _playEvent(e),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: _busy == e.id
                      ? const Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A tear-off calendar page for an event: "THÁNG 11 · 14 · năm 1945", a
/// second sheet peeking behind. [small] is the 64px list version.
class EventSheet extends StatelessWidget {
  final int day, month;
  final int? year;
  final bool small;
  final double size;
  const EventSheet({super.key, required this.day, required this.month, this.year, this.small = false, this.size = 180});

  @override
  Widget build(BuildContext context) {
    final paper = AppColors.isLight ? Colors.white : const Color(0xFF2A2021);
    if (small) {
      return Container(
        width: 64,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: AppColors.isLight ? 0.08 : 0.3), blurRadius: 12, offset: const Offset(0, 4))]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(color: AppColors.wine, width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 4), alignment: Alignment.center, child: Text('TH $month', style: body(const TextStyle(fontSize: 10, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: Colors.white)))),
          Padding(padding: const EdgeInsets.fromLTRB(0, 7, 0, 8), child: Text(day.toString().padLeft(2, '0'), style: display(TextStyle(fontSize: 26, height: 1, letterSpacing: -1, fontWeight: FontWeight.w800, color: AppColors.text)))),
        ]),
      );
    }
    final k = size / 180;
    return SizedBox(
      width: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          left: 8 * k, right: -8 * k, top: -8 * k, bottom: 8 * k,
          child: Transform.rotate(angle: 0.05, child: DecoratedBox(decoration: BoxDecoration(color: AppColors.isLight ? const Color(0xFFE8C9C5) : const Color(0xFF4A2A2A), borderRadius: BorderRadius.circular(18 * k)))),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(18 * k), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: AppColors.isLight ? 0.14 : 0.4), blurRadius: 24, offset: const Offset(0, 10))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(color: AppColors.wine, width: double.infinity, padding: EdgeInsets.symmetric(vertical: 8 * k), alignment: Alignment.center, child: Text('THÁNG $month', style: body(TextStyle(fontSize: 14 * k, letterSpacing: 1, fontWeight: FontWeight.w800, color: Colors.white)))),
            Padding(padding: EdgeInsets.fromLTRB(0, 14 * k, 0, 4 * k), child: Text(day.toString().padLeft(2, '0'), style: display(TextStyle(fontSize: 72 * k, height: 1, letterSpacing: -2, fontWeight: FontWeight.w800, color: AppColors.text)))),
            Padding(padding: EdgeInsets.only(bottom: 14 * k), child: Text(year != null ? 'năm $year' : 'hằng năm', style: body(TextStyle(fontSize: 15 * k, fontWeight: FontWeight.w800, color: AppColors.textMuted)))),
          ]),
        ),
      ]),
    );
  }
}
