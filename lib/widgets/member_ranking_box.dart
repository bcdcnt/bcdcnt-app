import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';

/// Right-column ranking box used on the desktop Home screen — port of
/// bcdcnt-web's `MemberRankingWidget`. Two query modes:
/// - users: ordered by a User column (e.g. `point`).
/// - custom: a top-N query that returns `{username, avatar, user_id, total}`.
class MemberRankingBox extends StatefulWidget {
  final String title;
  final IconData icon;
  final String href;
  final _QueryMode mode;
  final String? field;
  final String? filterClause;
  final String? queryName;
  final int count;

  const MemberRankingBox.users({
    super.key,
    required this.title,
    required this.icon,
    required this.href,
    required this.field,
    this.filterClause,
    this.count = 10,
  })  : mode = _QueryMode.users,
        queryName = null;

  const MemberRankingBox.custom({
    super.key,
    required this.title,
    required this.icon,
    required this.href,
    required this.queryName,
    this.count = 10,
  })  : mode = _QueryMode.custom,
        field = null,
        filterClause = null;

  @override
  State<MemberRankingBox> createState() => _MemberRankingBoxState();
}

enum _QueryMode { users, custom }

class _RankItem {
  final String id;
  final String username;
  final String? avatar;
  final num value;
  _RankItem({required this.id, required this.username, this.avatar, required this.value});
}

class _MemberRankingBoxState extends State<MemberRankingBox> {
  List<_RankItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      List<_RankItem> result = [];
      if (widget.mode == _QueryMode.users) {
        final extra = widget.filterClause ?? '';
        final q = '''query { users(first: ${widget.count}, orderBy: [{column: "${widget.field}", order: DESC}], where: {AND: [{column: "${widget.field}", value: 0, operator: GT}$extra]}) { data { id username avatar { url } ${widget.field} } } }''';
        final res = await ApiClient.query(q, null);
        final raw = (res['users']?['data'] ?? []) as List;
        result = raw.map((u) {
          final m = Map<String, dynamic>.from(u as Map);
          return _RankItem(
            id: m['id'].toString(),
            username: (m['username'] ?? '').toString(),
            avatar: (m['avatar'] is Map ? m['avatar']['url'] : null)?.toString(),
            value: (m[widget.field] as num?) ?? 0,
          );
        }).toList();
      } else {
        final q = '''query { ${widget.queryName}(first: ${widget.count}) { data { username avatar user_id total } } }''';
        final res = await ApiClient.query(q, null);
        final raw = (res[widget.queryName]?['data'] ?? []) as List;
        result = raw.map((u) {
          final m = Map<String, dynamic>.from(u as Map);
          return _RankItem(
            id: m['user_id'].toString(),
            username: (m['username'] ?? '').toString(),
            avatar: m['avatar']?.toString(),
            value: (m['total'] as num?) ?? 0,
          );
        }).toList();
      }
      if (!mounted) return;
      setState(() { _items = result; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  static const _rankColors = [Color(0xFFC9A96E), Color(0xFFA09090), Color(0xFF8B6914)];

  String _formatNumber(num n) {
    if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}B';
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          InkWell(
            onTap: () => context.push(widget.href),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(widget.icon, size: 15, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: display(const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.borderSubtle),
          // List
          if (_loading)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
          else if (_items.isEmpty)
            Padding(padding: const EdgeInsets.all(14), child: Text('Chưa có dữ liệu', style: body(const TextStyle(color: AppColors.textMuted, fontSize: 12))))
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: List.generate(_items.length, (i) => _RankRow(rank: i + 1, item: _items[i], rankColors: _rankColors, format: _formatNumber)),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final int rank;
  final _RankItem item;
  final List<Color> rankColors;
  final String Function(num) format;
  const _RankRow({required this.rank, required this.item, required this.rankColors, required this.format});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/user/${item.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            // Rank badge
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: rank <= 3 ? rankColors[rank - 1] : AppColors.surfaceLight,
              ),
              alignment: Alignment.center,
              child: Text(
                '$rank',
                style: body(TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: rank <= 3 ? Colors.white : AppColors.textMuted)),
              ),
            ),
            const SizedBox(width: 8),
            // Avatar
            ClipOval(
              child: SizedBox(
                width: 28, height: 28,
                child: item.avatar != null && item.avatar!.isNotEmpty
                    ? CachedNetworkImage(imageUrl: item.avatar!, fit: BoxFit.cover, errorWidget: (_, __, ___) => _placeholder())
                    : _placeholder(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: body(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)),
              ),
            ),
            Text(
              format(item.value),
              style: body(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accentLight)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceLight,
        alignment: Alignment.center,
        child: const Icon(Icons.person, size: 14, color: AppColors.textMuted),
      );
}
