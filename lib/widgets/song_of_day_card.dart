import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/theme.dart';
import 'share_card.dart';
import 'package:go_router/go_router.dart';
import '../services/api.dart';
import '../services/auth.dart';
import 'auth_dialogs.dart';
import 'song_row.dart' show SongCover, playOrOpen, songByline;
import 'ui.dart';

/// "Bài hát của ngày": the song the daily push names (API songOfTheDay),
/// with a one-tap question ("Bạn nghe bài này lần đầu khi nào?") and the
/// community's answers once you've voted. A small daily ritual: something new
/// every day, and a reason to come back tomorrow.
class SongOfDayCard extends StatefulWidget {
  const SongOfDayCard({super.key});

  @override
  State<SongOfDayCard> createState() => _SongOfDayCardState();
}

class _SongOfDayCardState extends State<SongOfDayCard> {
  static const _query = r'''query { songOfTheDay {
    lead my_option_ids total_answers
    song { id title slug subtitle play_type thumbnail { url } file { audio_url video_url duration } artists(first: 3) { data { id title slug } } sheet { year composers(first: 2) { data { id slug title } } } }
    poll { id title options(orderBy: [{column: "position", order: ASC}]) { id name total_answer percent } }
  } }''';

  Map<String, dynamic>? _data;
  Set<String> _mine = {};
  String? _sending;
  String? _forUser;
  bool _guestVote = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload on login/logout so "your answer" is right.
    final uid = context.watch<AuthProvider>().user?['id']?.toString();
    if (_data == null || uid != _forUser) {
      _forUser = uid;
      _load();
    }
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    try {
      final d = auth.isAuthenticated ? await auth.authedQuery(_query, null) : await ApiClient.query(_query);
      final s = d['songOfTheDay'];
      if (!mounted || s is! Map || s['song'] == null) return;
      final prefs = await SharedPreferences.getInstance();
      final pid = s['poll']?['id'];
      final local = prefs.getString('sotd_vote_$pid');
      final server = {for (final id in (s['my_option_ids'] as List? ?? const [])) '$id'};
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(s);
        _mine = server.isNotEmpty ? server : (local != null ? {local} : {});
        _guestVote = server.isEmpty && local != null && !auth.isAuthenticated;
      });
      // Answered as a guest, now signed in: send that answer for real.
      if (auth.isAuthenticated && server.isEmpty && local != null) {
        await prefs.remove('sotd_vote_$pid');
        _answer(local);
      }
    } catch (_) {}
  }

  Future<void> _answer(String optionId) async {
    final auth = context.read<AuthProvider>();
    final poll = _data?['poll'];
    if (!auth.isAuthenticated) {
      // Guests: keep the answer on this phone and show the results at once;
      // signing in (offered below the results) is what makes it count.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sotd_vote_${poll?['id']}', optionId);
      if (mounted) setState(() { _mine = {optionId}; _guestVote = true; });
      return;
    }
    if (poll == null || _sending != null) return;
    setState(() => _sending = optionId);
    try {
      final d = await auth.authedMutate(
        r'mutation($p: ID!, $o: [ID]!) { answerPoll(poll_id: $p, option_ids: $o) { id options(orderBy: [{column: "position", order: ASC}]) { id name total_answer percent } } }',
        {'p': poll['id'], 'o': [optionId]},
      );
      final opts = d['answerPoll']?['options'];
      if (!mounted) return;
      setState(() {
        _mine = {optionId};
        if (opts is List) {
          _data = {
            ..._data!,
            'poll': {...Map<String, dynamic>.from(poll as Map), 'options': opts},
            'total_answers': opts.fold<int>(0, (a, o) => a + ((o['total_answer'] as num?)?.toInt() ?? 0)),
          };
        }
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa gửi được câu trả lời. Thử lại sau.')));
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    final song = <String, dynamic>{...Map<String, dynamic>.from(d['song'] as Map), 'file_type': 'song'};
    final lead = d['lead']?.toString();
    final poll = d['poll'] as Map?;
    final options = ((poll?['options'] as List?) ?? const []).whereType<Map>().toList();
    final answered = _mine.isNotEmpty;
    final total = (d['total_answers'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('BÀI HÁT CỦA NGÀY', style: body(TextStyle(fontSize: 12, letterSpacing: 0.9, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
          if (lead != null && lead.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(lead, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
          ],
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: 'Nghe ${song['title']}, ${songByline(song)}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => playOrOpen(context, song, [song], 'Bài hát của ngày'),
              child: Row(children: [
                SongCover(song: song, size: 72, radius: 14),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(noOrphan('${song['title'] ?? ''}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: display(TextStyle(fontSize: 19, height: 1.2, fontWeight: FontWeight.w800, color: AppColors.text))),
                    const SizedBox(height: 4),
                    Text(songByline(song, withComposer: true), maxLines: 2, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                  ]),
                ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                ),
              ]),
            ),
          ),
          if (poll != null && options.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('${poll['title']}', style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text))),
            const SizedBox(height: 10),
            if (!answered)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final o in options)
                  Material(
                    color: AppColors.bg,
                    shape: StadiumBorder(side: BorderSide(color: AppColors.border, width: 1.5)),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => _answer('${o['id']}'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        child: _sending == '${o['id']}'
                            ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                            : Text('${o['name']}', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text))),
                      ),
                    ),
                  ),
              ])
            else ...[
              for (final o in options) _ResultBar(name: '${o['name']}', percent: ((o['percent'] as num?) ?? 0).toDouble(), mine: _mine.contains('${o['id']}')),
              const SizedBox(height: 4),
              Text(_guestVote ? 'Cảm ơn bạn! Đăng nhập để câu trả lời được tính.' : '$total người đã trả lời · Cảm ơn bạn!', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
              const SizedBox(height: 12),
              // Voting is the warm-up: next, tell the memory or pass the song on.
              Row(children: [
                Expanded(
                  child: PillButton(
                    label: _guestVote ? 'Đăng nhập' : 'Kể kỷ niệm',
                    icon: _guestVote ? Icons.login_rounded : Icons.edit_note_rounded,
                    height: 46,
                    onTap: _guestVote
                        ? () => showDialog(context: context, builder: (_) => const LoginDialog())
                        : () => context.push('/song/${song['id']}?binh-luan=1', extra: song),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: PillButton(label: 'Gửi bạn bè', icon: Icons.ios_share_rounded, primary: false, height: 46, onTap: () => showSongShareSheet(context, song))),
              ]),
            ],
          ],
        ]),
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  final String name;
  final double percent;
  final bool mine;
  const _ResultBar({required this.name, required this.percent, required this.mine});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$name: ${percent.round()} phần trăm${mine ? ', bạn chọn' : ''}',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Stack(children: [
            Container(height: 40, decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10))),
            FractionallySizedBox(
              widthFactor: (percent / 100).clamp(0.02, 1.0),
              child: Container(height: 40, decoration: BoxDecoration(color: mine ? AppColors.accent.withValues(alpha: 0.22) : AppColors.surfaceHover, borderRadius: BorderRadius.circular(10))),
            ),
            SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  if (mine) ...[Icon(Icons.check_circle_rounded, size: 18, color: AppColors.accentLight), const SizedBox(width: 6)],
                  Expanded(child: Text(name, style: body(TextStyle(fontSize: 15, fontWeight: mine ? FontWeight.w800 : FontWeight.w600, color: AppColors.text)))),
                  Text('${percent.round()}%', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text))),
                ]),
              ),
            ),
          ]),
        ),
      );
}
