import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../widgets/brand_logo.dart';
import '../widgets/song_row.dart';
import '../widgets/ui.dart';
import '../main.dart' show TabReselect;

export '../widgets/song_row.dart' show playOrOpen;

// Trang chủ for phone widths (2026-11 brand redesign). Order: today's
// pick → keep listening → occasion playlist → weekly top → newest →
// decades → featured comments → composers / singers → community playlists
// → newest archive photos. Desktop keeps HomeScreen.

const _songFields = 'id slug title subtitle views play_type file_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id slug title } } sheet { year composers(first: 2) { data { id slug title } } }';

const _mainQuery = '''query {
  stickySongs(first: 12, random: true) { data { $_songFields } }
  statisticListen(first: 5, type: "song", period: "week") { data { total object { ... on Song { $_songFields } } } }
  featuredComments(limit: 10) { id snippet likes created_at username user_avatar song_id song_title song_slug song_image audio_url play_type file_type }
}''';

const _peopleFields = 'id slug title avatar { url } total_listens';
const _peopleQuery = '''query(\$composerWhere: WhereConditions, \$artistWhere: WhereConditions) {
  composers(first: 16, random: true, where: \$composerWhere) { data { $_peopleFields } }
  artists(first: 16, random: true, where: \$artistWhere) { data { $_peopleFields } }
}''';

const _peopleVars = {
  'composerWhere': {'AND': [
    {'column': 'type', 'value': 'domestic'},
    {'column': 'total_listens', 'operator': 'GT', 'value': '10000'},
    {'column': 'image_id', 'operator': 'GT', 'value': '0'},
  ]},
  'artistWhere': {'AND': [
    {'column': 'type', 'value': 'domestic'},
    {'column': 'is_group', 'value': '0'},
    {'column': 'total_listens', 'operator': 'GT', 'value': '10000'},
    {'column': 'image_id', 'operator': 'GT', 'value': '0'},
  ]},
};

const _itemObj = '... on Song { id thumbnail { url } } ... on Folk { id thumbnail { url } } ... on Instrumental { id thumbnail { url } } ... on Poem { id thumbnail { url } }';

const _belowQuery = '''query(\$plWhere: WhereConditions, \$docWhere: WhereConditions, \$evWhere: WhereConditions) {
  playlists(first: 8, orderBy: [{column: "id", order: DESC}], where: \$plWhere) {
    data { id slug title thumbnail { url } user { id username } items(first: 4) { paginatorInfo { total } data { object { $_itemObj } } } }
  }
  documents(first: 6, orderBy: [{column: "id", order: DESC}], where: \$docWhere) { data { id slug title thumbnail { url } } }
  events: playlists(first: 3, where: \$evWhere) {
    data { id slug title excerpt thumbnail { url } items(first: 4) { paginatorInfo { total } data { object { $_itemObj } } } }
  }
}''';

class _Cat {
  final String name, slug, query;
  const _Cat(this.name, this.slug, this.query);
}

const _cats = [
  _Cat('Tân nhạc', 'tan-nhac', 'songs'),
  _Cat('Dân ca', 'dan-ca', 'folks'),
  _Cat('Khí nhạc', 'khi-nhac', 'instrumentals'),
  _Cat('Tiếng thơ', 'tieng-tho', 'poems'),
  _Cat('Thành viên hát', 'thanh-vien-hat', 'karaokes'),
];

const _decades = [
  (1950, 'Kháng chiến, hoà bình lập lại'),
  (1960, 'Xây dựng và chiến đấu'),
  (1970, 'Thống nhất đất nước'),
  (1980, 'Những năm Đổi mới'),
];

const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];

/// Fixed-date days the archive has songs for. The home header counts down
/// to the next one within 30 days.
const _occasions = [
  (1, 1, 'Tết Dương lịch'), (3, 2, 'Ngày thành lập Đảng'), (8, 3, 'Quốc tế Phụ nữ'),
  (26, 3, 'Ngày thành lập Đoàn'), (30, 4, 'Ngày Giải phóng miền Nam'), (1, 5, 'Quốc tế Lao động'),
  (7, 5, 'Chiến thắng Điện Biên Phủ'), (19, 5, 'Sinh nhật Bác Hồ'), (1, 6, 'Quốc tế Thiếu nhi'),
  (27, 7, 'Ngày Thương binh Liệt sĩ'), (19, 8, 'Cách mạng Tháng Tám'), (2, 9, 'Quốc khánh'),
  (10, 10, 'Giải phóng Thủ đô'), (20, 10, 'Ngày Phụ nữ Việt Nam'), (20, 11, 'Ngày Nhà giáo Việt Nam'),
  (22, 12, 'Ngày thành lập Quân đội'),
];

String? _occasionLine(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  (int, String)? best;
  for (final (d, m, label) in _occasions) {
    var date = DateTime(now.year, m, d);
    if (date.isBefore(today)) date = DateTime(now.year + 1, m, d);
    final days = date.difference(today).inDays;
    if (days <= 30 && (best == null || days < best.$1)) best = (days, label);
  }
  if (best == null) return null;
  return best.$1 == 0 ? 'Hôm nay là ${best.$2}' : 'Còn ${best.$1} ngày đến ${best.$2}';
}

String _greeting(DateTime now) {
  final h = now.hour;
  if (h < 11) return 'Chào buổi sáng';
  if (h < 14) return 'Chào buổi trưa';
  if (h < 18) return 'Chào buổi chiều';
  return 'Chào buổi tối';
}

List<Map<String, dynamic>> _maps(dynamic list) =>
    ((list ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

List<String> _itemThumbs(Map p) => _maps(p['items']?['data'])
    .map((i) => i['object']?['thumbnail']?['url']?.toString())
    .whereType<String>()
    .toList();

class HomeMobileScreen extends StatefulWidget {
  const HomeMobileScreen({super.key});
  @override
  State<HomeMobileScreen> createState() => _HomeMobileScreenState();
}

class _HomeMobileScreenState extends State<HomeMobileScreen> {
  bool _loading = true;
  bool _failed = false;
  List<Map<String, dynamic>> _picks = [];
  List<Map<String, dynamic>> _weekly = [];
  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>> _composers = [];
  List<Map<String, dynamic>> _artists = [];
  List<Map<String, dynamic>> _playlists = [];
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _recent = [];
  int _cat = 0;
  final Map<String, List<Map<String, dynamic>>> _latest = {};
  AuthProvider? _auth;
  String? _recentFor;
  final _scroll = ScrollController();

  void _onReselect() {
    if (TabReselect.tick.value.$1 == 0 && _scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    }
  }

  @override
  void initState() {
    super.initState();
    TabReselect.tick.addListener(_onReselect);
    _fetch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _auth = context.read<AuthProvider>()..addListener(_maybeFetchRecent);
      _maybeFetchRecent();
    });
  }

  @override
  void dispose() {
    TabReselect.tick.removeListener(_onReselect);
    _scroll.dispose();
    _auth?.removeListener(_maybeFetchRecent);
    super.dispose();
  }

  Future<void> _fetch() async {
    Future<Map<String, dynamic>> safe(Future<Map<String, dynamic>> f) => f.catchError((_) => <String, dynamic>{});
    final now = DateTime.now();
    final mmdd = '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    setState(() => _failed = false);
    final r = await Future.wait([
      safe(ApiClient.query(_mainQuery)),
      safe(ApiClient.query(_peopleQuery, _peopleVars)),
      safe(ApiClient.query(_belowQuery, {
        'plWhere': {'AND': [{'column': 'is_public', 'value': '1'}]},
        'docWhere': {'AND': [{'column': 'type', 'value': 'image'}]},
        'evWhere': {'AND': [
          {'column': 'is_system', 'value': '1'},
          {'column': 'is_public', 'value': '1'},
          {'column': 'event_start', 'operator': 'LTE', 'value': mmdd},
          {'column': 'event_end', 'operator': 'GTE', 'value': mmdd},
        ]},
      })),
    ]);
    _latest.clear();
    _fetchLatest(_cats[_cat]);
    if (!mounted) return;
    setState(() {
      _picks = _maps(r[0]['stickySongs']?['data']).where((s) => s['thumbnail']?['url'] != null).toList();
      _weekly = _maps(r[0]['statisticListen']?['data'])
          .where((d) => d['object'] is Map)
          .map((d) => {...Map<String, dynamic>.from(d['object']), 'weeklyListens': d['total']})
          .toList();
      _comments = _maps(r[0]['featuredComments']).where((c) => (c['snippet'] ?? '').toString().trim().isNotEmpty).toList();
      // image_id > 0 doesn't guarantee the image row exists (~10% don't):
      // keep only people with a real photo so the rail stays all faces.
      bool hasPhoto(Map p) => (p['avatar']?['url']?.toString() ?? '').isNotEmpty;
      _composers = _maps(r[1]['composers']?['data']).where(hasPhoto).take(12).toList();
      _artists = _maps(r[1]['artists']?['data']).where(hasPhoto).take(12).toList();
      _playlists = _maps(r[2]['playlists']?['data']).where((p) => p['thumbnail']?['url'] != null || _itemThumbs(p).isNotEmpty).toList();
      _docs = _maps(r[2]['documents']?['data']).where((d) => d['thumbnail']?['url'] != null).toList();
      _events = _maps(r[2]['events']?['data']);
      _loading = false;
      _failed = r[0].isEmpty && r[1].isEmpty;
    });
  }

  void _maybeFetchRecent() {
    final auth = _auth;
    if (auth == null || auth.loading || !mounted) return;
    final uid = auth.user?['id']?.toString();
    if (uid == _recentFor) return;
    _recentFor = uid;
    if (uid == null) {
      setState(() => _recent = []);
      return;
    }
    _fetchRecent(auth, uid);
  }

  Future<void> _fetchRecent(AuthProvider auth, String uid) async {
    const f = 'id title slug play_type thumbnail { url } file { audio_url video_url } artists(first: 2) { data { id title slug } }';
    try {
      final d = await auth.authedQuery('''query(\$id: ID!) { user(id: \$id) { recentListens(first: 12, page: 1, orderBy: [{column: "id", order: DESC}]) { data { object { __typename ... on Song { $f } ... on Folk { $f } ... on Instrumental { $f } ... on Poem { $f } } } } } }''', {'id': uid});
      const tn = {'Song': 'song', 'Folk': 'folk', 'Instrumental': 'instrumental', 'Poem': 'poem'};
      final seen = <String>{};
      final out = <Map<String, dynamic>>[];
      for (final e in _maps(d['user']?['recentListens']?['data'])) {
        final o = e['object'];
        if (o is! Map) continue;
        final m = Map<String, dynamic>.from(o);
        if (!seen.add('${m['__typename']}-${m['id']}')) continue;
        m['file_type'] = tn[m['__typename']] ?? 'song';
        out.add(m);
      }
      if (mounted) setState(() => _recent = out);
    } catch (_) {}
  }

  Future<void> _fetchLatest(_Cat cat) async {
    final people = cat.query == 'karaokes'
        ? 'users(first: 3) { data { id slug: username title: username } }'
        : 'artists(first: 3) { data { id slug title } }';
    final q = '''query {
      ${cat.query}(first: 8, orderBy: [{column: "id", order: DESC}]) {
        data { id slug title subtitle views play_type file_type thumbnail { url } file { audio_url video_url duration } $people }
      }
    }''';
    try {
      final d = await ApiClient.query(q);
      if (!mounted) return;
      setState(() => _latest[cat.slug] = _maps(d[cat.query]?['data']).map((s) {
            if (cat.query == 'karaokes' && s['users'] != null) s['artists'] = s['users'];
            // API file_type is "audio"/"video"; the player needs the table
            // (folks → folk…), or it loads the tân nhạc with the same id.
            s['file_type'] = cat.query.substring(0, cat.query.length - 1);
            return s;
          }).toList());
    } catch (_) {
      if (mounted) setState(() => _latest[cat.slug] = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final user = context.select<AuthProvider, Map<String, dynamic>?>((a) => a.user);
    final unread = (user?['unread'] is num) ? (user!['unread'] as num).toInt() : 0;
    final name = user?['username']?.toString();
    final occasion = _occasionLine(now);
    final cat = _cats[_cat];
    final latest = _latest[cat.slug];

    return ColoredBox(
      color: AppColors.bg,
      child: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: _fetch,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 14, 0),
              child: Row(
                children: [
                  const BrandLogo(height: 30),
                  const Spacer(),
                  RoundIcon(icon: Icons.search_rounded, tooltip: 'Tìm kiếm', onTap: () => context.go('/search')),
                  const SizedBox(width: 8),
                  RoundIcon(icon: Icons.notifications_none_rounded, tooltip: 'Thông báo', dot: unread > 0, onTap: () => context.push('/thong-bao')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name != null && name.isNotEmpty ? '${_greeting(now)}, $name' : _greeting(now),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: display(TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w800, color: AppColors.text))),
                  const SizedBox(height: 6),
                  Text(
                    [
                      '${_weekdays[now.weekday - 1]}, ${now.day}/${now.month}',
                      if (occasion != null) occasion,
                    ].join(' · '),
                    style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  ),
                ],
              ),
            ),
            if (_failed)
              EmptyBlock(
                icon: Icons.wifi_off_rounded,
                title: 'Chưa tải được nội dung',
                message: 'Kiểm tra kết nối mạng rồi thử lại. Các bài đã tải về vẫn nghe được.',
                action: 'Tải lại',
                onAction: _fetch,
              ),
            const SizedBox(height: 18),
            if (_loading)
              const Skeleton(height: 236, radius: 24, margin: EdgeInsets.symmetric(horizontal: 20))
            else if (_picks.isNotEmpty)
              _PickCarousel(picks: _picks),

            if (_recent.isNotEmpty) ...[
              SectionTitle('Nghe tiếp', action: 'Lịch sử', onAction: () => context.push('/nghe-gan-day')),
              Rail(
                height: 226,
                count: _recent.length,
                builder: (_, i) => _songCard(_recent[i], _recent, 'Nghe gần đây'),
              ),
            ],

            if (_events.isNotEmpty) ...[
              SectionTitle(_events.first['title']?.toString() ?? 'Theo dịp', action: 'Mở', onAction: () => context.push('/playlist/${_events.first['id']}')),
              _OccasionCard(playlist: _events.first),
            ],

            SectionTitle('Nghe nhiều tuần này', action: 'BXH', onAction: () => context.push('/bang-xep-hang')),
            if (_loading)
              for (var i = 0; i < 5; i++) const SkeletonSongRow()
            else
              for (var i = 0; i < _weekly.length; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 6),
                  child: SongRow(song: _weekly[i], index: i, showIndex: true, queue: _weekly, sourceLabel: 'Nghe nhiều tuần này'),
                ),

            SectionTitle('Mới cập nhật', onAction: () => context.push('/the-loai/${cat.slug}')),
            ChipStrip(
              labels: [for (final c in _cats) c.name],
              selected: _cat,
              onSelect: (i) {
                setState(() => _cat = i);
                if (!_latest.containsKey(_cats[i].slug)) _fetchLatest(_cats[i]);
              },
            ),
            const SizedBox(height: 14),
            if (latest == null)
              Rail(height: 226, count: 4, builder: (_, __) => const Skeleton(width: 148, height: 148, radius: 18))
            else
              Rail(height: 226, count: latest.length, builder: (_, i) => _songCard(latest[i], latest, 'Mới cập nhật · ${cat.name}')),

            SectionTitle('Nghe theo thập niên', action: null),
            _DecadeGrid(images: [for (final s in _picks.skip(1).take(4)) s['thumbnail']?['url']?.toString()]),

            if (_comments.isNotEmpty) ...[
              SectionTitle('Cảm nhận hay', action: 'Cộng đồng', onAction: () => context.go('/cong-dong')),
              Rail(
                height: 226,
                count: _comments.length,
                builder: (_, i) => _QuoteCard(comment: _comments[i]),
              ),
            ],

            SectionTitle('Nhạc sĩ', onAction: () => context.push('/nhac-si')),
            _PeopleRail(people: _composers, loading: _loading, route: '/nhac-si/'),
            SectionTitle('Giọng ca', onAction: () => context.push('/nghe-si')),
            _PeopleRail(people: _artists, loading: _loading, route: '/nghe-si/'),

            if (_playlists.isNotEmpty) ...[
              SectionTitle('Playlist cộng đồng', onAction: () => context.push('/playlist')),
              Rail(
                height: 226,
                count: _playlists.length,
                builder: (_, i) {
                  final p = _playlists[i];
                  final total = p['items']?['paginatorInfo']?['total'];
                  return RailCard(
                    cover: _PlaylistCover(playlist: p),
                    title: p['title']?.toString() ?? '',
                    subtitle: [if (total != null) '$total bài', if (p['user']?['username'] != null) p['user']['username']].join(' · '),
                    onTap: () => context.push('/playlist/${p['id']}'),
                  );
                },
              ),
            ],

            if (_docs.isNotEmpty) ...[
              SectionTitle('Tư liệu mới', action: 'Kho tư liệu', onAction: () => context.push('/tu-lieu/hinh-anh')),
              Rail(
                height: 226,
                count: _docs.length,
                builder: (_, i) {
                  final d = _docs[i];
                  return RailCard(
                    width: 220,
                    coverHeight: 150,
                    cover: Stack(fit: StackFit.expand, children: [
                      NetImage(url: d['thumbnail']?['url']?.toString(), tint: true),
                      Positioned(left: 10, top: 10, child: _Tag(icon: Icons.photo_outlined, label: 'Ảnh')),
                    ]),
                    title: d['title']?.toString() ?? '',
                    onTap: () => context.push('/tu-lieu/chi-tiet/${d['id']}'),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _songCard(Map<String, dynamic> s, List<Map<String, dynamic>> list, String label) => RailCard(
        cover: SongCover(song: s, size: 148, radius: 0),
        title: s['title']?.toString() ?? '',
        subtitle: songByline(s),
        onTap: () => playOrOpen(context, s, list, label),
      );
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Tag({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppColors.wine),
          const SizedBox(width: 5),
          Text(label, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.wine))),
        ]),
      );
}

/// Big swipeable "Gợi ý hôm nay" cards with brand-tinted photos.
class _PickCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> picks;
  const _PickCarousel({required this.picks});
  @override
  State<_PickCarousel> createState() => _PickCarouselState();
}

class _PickCarouselState extends State<_PickCarousel> {
  static const _maxSlides = 6;
  final _ctrl = PageController(viewportFraction: 0.9);
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      // Count the slides actually shown (build() takes the first 6), else
      // the last slide asks for a page that doesn't exist and stays put.
      final count = widget.picks.length.clamp(0, _maxSlides);
      if (!_ctrl.hasClients || count < 2) return;
      final next = (_index + 1) % count;
      _ctrl.animateToPage(next, duration: Duration(milliseconds: next == 0 ? 700 : 450), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picks = widget.picks.take(_maxSlides).toList();
    return Column(
      children: [
        SizedBox(
          height: 156 + MediaQuery.textScalerOf(context).scale(80),
          child: PageView.builder(
            controller: _ctrl,
            // Centred slides: every card sits on the same margin, not just
            // the first one.
            padEnds: true,
            itemCount: picks.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final s = picks[i];
              final comp = (s['sheet']?['composers']?['data'] as List?)?.whereType<Map>().map((c) => c['title']).join(', ') ?? '';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: GestureDetector(
                  onTap: () => playOrOpen(context, s, picks, 'Gợi ý hôm nay'),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetImage(url: s['thumbnail']?['url']?.toString(), tint: true),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.3, 1],
                              colors: [Color(0x000E0A0A), Color(0xD60E0A0A)],
                            ),
                          ),
                        ),
                        Positioned(left: 14, top: 14, child: _Tag(icon: Icons.star_outline_rounded, label: 'Gợi ý hôm nay')),
                        Positioned(
                          left: 18,
                          right: 18,
                          bottom: 16,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (comp.isNotEmpty)
                                      Text(comp.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 12, letterSpacing: 0.9, fontWeight: FontWeight.w700, color: Color(0xD9FFFFFF)))),
                                    const SizedBox(height: 4),
                                    Text(noOrphan('${s['title'] ?? ''}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800, color: Colors.white))),
                                    const SizedBox(height: 3),
                                    Text(songByline(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xD9FFFFFF)))),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 52,
                                height: 52,
                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                child: const Icon(Icons.play_arrow_rounded, color: AppColors.wine, size: 30),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < picks.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(color: i == _index ? AppColors.wine : AppColors.surfaceLight, borderRadius: BorderRadius.circular(3)),
              ),
          ],
        ),
      ],
    );
  }
}

/// Today's occasion playlist (Ngày Nhà giáo, 30/4…) as a gradient banner.
class _OccasionCard extends StatelessWidget {
  final Map<String, dynamic> playlist;
  const _OccasionCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final total = playlist['items']?['paginatorInfo']?['total'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/playlist/${playlist['id']}'),
          child: Ink(
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.wine, AppColors.rose])),
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PLAYLIST THEO DỊP', style: body(const TextStyle(fontSize: 12, letterSpacing: 0.9, fontWeight: FontWeight.w800, color: Color(0xCCFFFFFF)))),
                      const SizedBox(height: 4),
                      Text(playlist['title']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: display(const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white))),
                      if (total != null) Text('$total bài', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xD9FFFFFF)))),
                    ],
                  ),
                ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, color: AppColors.wine, size: 30),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 2x2 decade tiles with tinted archive photos.
class _DecadeGrid extends StatelessWidget {
  final List<String?> images;
  const _DecadeGrid({required this.images});
  static const _tones = [Color(0xFF711313), Color(0xFF8C3B3A), Color(0xFF5A1D1D), Color(0xFF9C5E5C)];

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < _decades.length; i++)
              Material(
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push('/bai-hat/thap-nien/${_decades[i].$1}'),
                  child: Ink(
                    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_tones[i], const Color(0xFF1B0909)])),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (i < images.length && images[i] != null) Opacity(opacity: 0.5, child: NetImage(url: images[i], tint: true)),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('Thập niên ${_decades[i].$1 % 100}', style: display(const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white))),
                              Text(_decades[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xEBFFFFFF)))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// "Cảm nhận hay" quote card; tap plays the song it was written for.
class _QuoteCard extends StatelessWidget {
  final Map<String, dynamic> comment;
  const _QuoteCard({required this.comment});

  @override
  Widget build(BuildContext context) {
    final song = <String, dynamic>{
      'id': comment['song_id'],
      'title': comment['song_title'],
      'slug': comment['song_slug'],
      'file_type': comment['file_type'] ?? 'song',
      if (comment['song_image'] != null) 'thumbnail': {'url': comment['song_image']},
      if (comment['audio_url'] != null) 'file': {'audio_url': comment['audio_url']},
    };
    return SizedBox(
      width: 300,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            HapticFeedback.selectionClick();
            context.push('/song/${comment['song_id']}', extra: {...song, 'highlightCommentId': comment['id']?.toString()});
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TRONG “${(comment['song_title'] ?? '').toString().toUpperCase()}”', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.eyebrow),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(
                    (comment['snippet'] ?? '').toString(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: body(TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600, color: AppColors.text)),
                  ),
                ),
                Row(
                  children: [
                    UserAvatar(url: comment['user_avatar']?.toString(), name: (comment['username'] ?? '').toString(), size: 28),
                    const SizedBox(width: 10),
                    Expanded(child: Text((comment['username'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)))),
                    if ((comment['likes'] ?? 0) is num && (comment['likes'] as num) > 0) ...[
                      Icon(Icons.favorite_border_rounded, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text('${comment['likes']}', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
                    ],
                    if (comment['audio_url'] != null) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => playOrOpen(context, song, [song], 'Cảm nhận hay'),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(color: AppColors.wine, shape: BoxShape.circle),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistCover extends StatelessWidget {
  final Map<String, dynamic> playlist;
  const _PlaylistCover({required this.playlist});
  @override
  Widget build(BuildContext context) {
    final own = playlist['thumbnail']?['url']?.toString();
    if (own != null) return NetImage(url: own);
    final t = _itemThumbs(playlist);
    if (t.length < 4) return NetImage(url: t.first);
    return GridView.count(
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [for (final u in t.take(4)) NetImage(url: u)],
    );
  }
}

class _PeopleRail extends StatelessWidget {
  final List<Map<String, dynamic>> people;
  final bool loading;
  final String route;
  const _PeopleRail({required this.people, required this.loading, required this.route});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Rail(height: 150, count: 4, gap: 14, builder: (_, __) => const Skeleton(width: 88, height: 88, radius: 44));
    }
    // 88 photo + 8 gap + up to two lines of name, with room for the
    // larger text sizes in Cài đặt.
    return Rail(
      height: 150,
      gap: 14,
      count: people.length,
      builder: (_, i) {
        final p = people[i];
        return PersonBubble(
          name: p['title']?.toString() ?? '',
          image: p['avatar']?['url']?.toString(),
          onTap: () => context.push('$route${p['slug']}'),
        );
      },
    );
  }
}
