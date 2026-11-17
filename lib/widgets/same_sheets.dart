import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/imgcdn.dart';
import 'sheet_lightbox.dart';

/// Bàn làm việc, bài gửi loại bản nhạc — the same view as web /admin/gui-bai
/// "Kiểm tra trùng": the scans being sent (blue box), then the archived
/// sheet of the same title by the same composer: its "Bản gốc" and every
/// "phiên bản" (revision), each as a strip of thumbnails; a tap opens the
/// strip in the lightbox.
class SameSheets extends StatefulWidget {
  final Map<String, dynamic> upload;
  const SameSheets({super.key, required this.upload});

  @override
  State<SameSheets> createState() => _SameSheetsState();
}

List<String> sheetImages(dynamic html) =>
    RegExp(r'''<img[^>]+src=["']([^"']+)["']''', caseSensitive: false).allMatches('${html ?? ''}').map((m) => m.group(1)!).toList();

String _norm(String x) => x.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
String _names(dynamic v) => (((v is Map ? v['data'] : v) as List?) ?? const []).whereType<Map>().map((e) => '${e['title'] ?? ''}').where((t) => t.isNotEmpty).join(', ');
String _dmy(dynamic d) {
  final t = DateTime.tryParse('${d ?? ''}');
  return t == null ? '' : '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
}

class _SameSheetsState extends State<SameSheets> {
  List<Map<String, dynamic>>? _same;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SameSheets old) {
    super.didUpdateWidget(old);
    final u = widget.upload, o = old.upload;
    if (u['id'] != o['id'] || u['title'] != o['title'] || u['composers'] != o['composers']) _load();
  }

  Future<void> _load() async {
    final u = widget.upload;
    final title = '${u['title'] ?? ''}'.trim();
    final want = '${u['composers'] ?? ''}'.split(RegExp(r'[,;]|\s-\s')).map(_norm).where((x) => x.isNotEmpty).toSet();
    setState(() => _same = null);
    if (title.isEmpty) return setState(() => _same = const []);
    final key = '${u['id']}|$title';
    try {
      final d = await ApiClient.query(
        r'query($q: Mixed) { sheets(first: 20, where: {AND: [{column: "title", operator: EQ, value: $q}]}) { data { id title content composers(first: 5) { data { title } } revisions(first: 20) { data { id title content uploader { username } created_at } } } } }',
        {'q': title},
      );
      if (!mounted || key != '${widget.upload['id']}|${'${widget.upload['title'] ?? ''}'.trim()}') return;
      final all = [for (final m in ((d['sheets']?['data'] ?? []) as List).whereType<Map>()) Map<String, dynamic>.from(m)];
      // Exactly the composer's own sheet; no composer typed → every same-title one.
      setState(() => _same = [
            for (final m in all)
              if (want.isEmpty || _names(m['composers']).split(', ').map(_norm).any(want.contains)) m,
          ]);
    } catch (_) {
      if (mounted) setState(() => _same = const []);
    }
  }

  Widget _label(String t, Color c, {double size = 11}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t.toUpperCase(), style: body(TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: c))),
      );

  Widget _strip(List<String> urls, {required Color paper}) {
    if (urls.isEmpty) return Text('(không có ảnh)', style: body(TextStyle(fontSize: 12, color: AppColors.textMuted)));
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) => MouseRegion(
          cursor: SystemMouseCursors.zoomIn,
          child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SheetLightbox(images: urls, initialIndex: i))),
            child: Container(
              decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
              clipBehavior: Clip.antiAlias,
              child: CachedNetworkImage(
                imageUrl: cdnImg(urls[i], 400),
                height: 140,
                fit: BoxFit.fitHeight,
                placeholder: (_, _) => const SizedBox(width: 104, height: 140),
                errorWidget: (_, _, _) => SizedBox(width: 104, height: 140, child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = sheetImages(widget.upload['content']);
    final blue = AppColors.isLight ? const Color(0xFF1D4ED8) : const Color(0xFF93B4FA);
    final blueBg = AppColors.isLight ? const Color(0xFFEEF4FE) : const Color(0xFF16213A);
    final blueBorder = AppColors.isLight ? const Color(0xFFC9DBFB) : const Color(0xFF2B3D66);
    final same = _same;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: blueBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: blueBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('Bản nhạc đang gửi · ${mine.length} ảnh', blue),
          _strip(mine, paper: Colors.white),
        ]),
      ),
      if (same != null && same.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Đã có trong kho', style: body(TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
        for (final s in same) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
            child: Builder(builder: (context) {
              final revs = ((s['revisions']?['data'] ?? []) as List).whereType<Map>().toList();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Bản gốc', AppColors.textMuted, size: 10),
                _strip(sheetImages(s['content']), paper: const Color(0xFFFFFDF7)),
                if (revs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 8),
                  _label('${revs.length} phiên bản', AppColors.textMuted, size: 10),
                  for (final r in revs) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 3),
                      child: Text(
                        '· ${'${r['title'] ?? ''}'.trim().isEmpty ? '(không tên)' : r['title']}'
                        '${'${r['uploader']?['username'] ?? ''}'.isNotEmpty ? ' — ${r['uploader']['username']}' : ''}'
                        '${_dmy(r['created_at']).isNotEmpty ? ' · ${_dmy(r['created_at'])}' : ''}',
                        style: body(TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ),
                    ),
                    _strip(sheetImages(r['content']), paper: const Color(0xFFFFFDF7)),
                  ],
                ],
              ]);
            }),
          ),
        ],
      ],
    ]);
  }
}
