import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import 'ui.dart';

/// "Thành viên tiêu biểu": the members who gave most to the archive
/// (points from approved uploads, stories, lyrics…). Lives in Cộng đồng ›
/// Cảm nhận (moved off the home page, 2026-11). The top 3 keep their
/// medals; ranks 4–20 come in a new order each visit so more names get seen.
class TopMembersRail extends StatefulWidget {
  const TopMembersRail({super.key});
  @override
  State<TopMembersRail> createState() => _TopMembersRailState();
}

class _TopMembersRailState extends State<TopMembersRail> {
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final d = await ApiClient.query('query { topMember(field: "point", first: 20) { data { id username point avatar { url } } } }');
      // Members without a photo stay in (as initials): dropping them shifted
      // every rank after them and hid the real number 2.
      final all = ((d['topMember']?['data'] ?? []) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      for (var i = 0; i < all.length; i++) {
        all[i]['rank'] = i + 1;
      }
      final rest = all.skip(3).toList()..shuffle();
      if (mounted) setState(() => _members = [...all.take(3), ...rest]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_members.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Thành viên tiêu biểu', action: 'Xem tất cả', onAction: () => context.push('/bang-xep-hang/cong-hien'), padding: const EdgeInsets.fromLTRB(20, 18, 12, 10)),
      Rail(
        height: 130,
        textHeight: 52,
        gap: 22,
        count: _members.length,
        builder: (_, i) {
          final m = _members[i];
          final pts = (m['point'] as num?)?.toInt() ?? 0;
          final rank = (m['rank'] as int?) ?? i + 1;
          return Semantics(
            button: true,
            excludeSemantics: true,
            label: 'Thành viên ${m['username']}, hạng $rank, ${formatViews(pts)} điểm',
            child: GestureDetector(
              onTap: () => context.push('/user/${m['id']}'),
              child: SizedBox(
                width: 76,
                child: Column(children: [
                  Stack(clipBehavior: Clip.none, children: [
                    UserAvatar(url: m['avatar']?['url']?.toString(), name: '${m['username'] ?? ''}', size: 76),
                    if (rank <= 3)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: const [Color(0xFFC9A227), Color(0xFF9EA3A8), Color(0xFFB0703C)][rank - 1], shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2)),
                          child: Text('$rank', style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white))),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Text('${m['username']}', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
                  Text('${formatViews(pts)} điểm', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                ]),
              ),
            ),
          );
        },
      ),
    ]);
  }
}
