import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  static const _categories = [
    ('listen_song', 'Tân nhạc', Color(0xFF711313)),
    ('listen_folk', 'Dân ca', Color(0xFFC9A96E)),
    ('listen_instrumental', 'Khí nhạc', Color(0xFFB48988)),
    ('listen_poem', 'Tiếng thơ', Color(0xFFD4A84B)),
    ('listen_karaoke', 'Thành viên hát', Color(0xFF6ECF8E)),
    ('listen_playlist', 'Playlist', Color(0xFF7B8EC9)),
  ];

  Map<String, dynamic> _data = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _fetch()); }

  Future<void> _fetch() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.user?['id'];
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final data = await ApiClient.query(r'''query($id: ID!) {
        user(id: $id) {
          point views listen listen_song listen_folk listen_instrumental listen_karaoke listen_poem listen_playlist
          comments(first: 1, where: {AND: [{column: "status", value: 1}]}) { paginatorInfo { total } }
          uploads(first: 1, where: {AND: [{column: "status", value: "approved"}]}) { paginatorInfo { total } }
        }
      }''', {'id': '$uid'});
      if (!mounted) return;
      setState(() { _data = Map<String, dynamic>.from(data['user'] ?? {}); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  String _formatInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) { if (i > 0 && (s.length - i) % 3 == 0) buf.write('.'); buf.write(s[i]); }
    return buf.toString();
  }

  int _intOf(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final commentsTotal = _intOf(_data['comments']?['paginatorInfo']?['total']);
    final uploadsTotal = _intOf(_data['uploads']?['paginatorInfo']?['total']);
    final totalListen = _intOf(_data['listen']);
    final maxListen = _categories.map((c) => _intOf(_data[c.$1])).fold(1, (a, b) => a > b ? a : b);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text('THỐNG KÊ', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          if (_loading)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList(delegate: SliverChildListDelegate([
                // Stat cards grid
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.2,
                  children: [
                    _statCard('Lượt xem', _intOf(_data['views']), Icons.visibility_outlined),
                    _statCard('Bình luận', commentsTotal, Icons.chat_bubble_outline),
                    _statCard('Điểm', _intOf(_data['point']), Icons.star_outline),
                    _statCard('Đóng góp', uploadsTotal, Icons.upload_outlined),
                  ],
                ),
                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.headphones, size: 16, color: AppColors.accentLight),
                      const SizedBox(width: 6),
                      Text('Tổng nghe', style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text))),
                      const Spacer(),
                      Text(_formatInt(totalListen), style: display(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
                    ]),
                    const SizedBox(height: 14),
                    ..._categories.map((c) {
                      final v = _intOf(_data[c.$1]);
                      final pct = maxListen > 0 ? v / maxListen : 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(c.$2, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                            Text(_formatInt(v), style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text))),
                          ]),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct.clamp(0.0, 1.0),
                              minHeight: 6,
                              backgroundColor: AppColors.surfaceLight,
                              valueColor: AlwaysStoppedAnimation(c.$3),
                            ),
                          ),
                        ]),
                      );
                    }),
                  ]),
                ),

                SizedBox(height: player.currentSong != null ? 90 : 20),
              ])),
            ),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }

  Widget _statCard(String label, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.accentSoft)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 11, color: AppColors.textMuted)))),
        ]),
        Text(_formatInt(value), style: display(const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text))),
      ]),
    );
  }
}
