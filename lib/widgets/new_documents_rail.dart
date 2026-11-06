import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api.dart';
import 'ui.dart';

/// "Tư liệu mới": newest archive photos (one card per album/event), shown in
/// Thư viện next to the other things members come back to look things up.
class NewDocumentsRail extends StatefulWidget {
  const NewDocumentsRail({super.key});

  @override
  State<NewDocumentsRail> createState() => _NewDocumentsRailState();
}

class _NewDocumentsRailState extends State<NewDocumentsRail> {
  List<Map<String, dynamic>> _docs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiClient.query(
        r'''query($w: WhereConditions) { documents(first: 60, orderBy: [{column: "id", order: DESC}], where: $w) { data { id title thumbnail { url } } } }''',
        {'w': {'AND': [{'column': 'type', 'value': 'image'}]}},
      );
      final seen = <String>{};
      final list = ((d['documents']?['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e['thumbnail']?['url'] != null && seen.add('${e['title']}'.trim().toLowerCase()))
          .take(10)
          .toList();
      if (mounted) setState(() => _docs = list);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_docs.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Tư liệu mới', action: 'Xem tất cả', onAction: () => context.push('/tu-lieu/hinh-anh')),
      Rail(
        height: 226,
        count: _docs.length,
        builder: (_, i) {
          final d = _docs[i];
          return RailCard(
            width: 220,
            coverHeight: 150,
            cover: NetImage(url: d['thumbnail']?['url']?.toString(), tint: true),
            title: d['title']?.toString() ?? '',
            onTap: () => context.push('/tu-lieu/chi-tiet/${d['id']}'),
          );
        },
      ),
    ]);
  }
}
