import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';
import '../widgets/section_header.dart';

/// Folk-music vocabulary hub. Renders "Làn điệu" (melodies) and/or
/// "Thể loại dân ca" (genres) as chip lists. The library shows two
/// dedicated tiles that route here in `melody` / `fcat` mode; the
/// combined `both` mode is kept for the legacy `/dan-ca-tu-vung` route.
enum FolkIndexMode { melody, fcat, both }

class FolkIndexScreen extends StatefulWidget {
  final FolkIndexMode mode;
  const FolkIndexScreen({super.key, this.mode = FolkIndexMode.both});

  @override
  State<FolkIndexScreen> createState() => _FolkIndexScreenState();
}

class _FolkIndexScreenState extends State<FolkIndexScreen> {
  bool _loading = true;
  bool _failed = false;
  List _melodies = [];
  List _folkCats = [];
  String _query = '';
  final _searchCtl = TextEditingController();

  bool get _wantMelodies => widget.mode == FolkIndexMode.melody || widget.mode == FolkIndexMode.both;
  bool get _wantFcats => widget.mode == FolkIndexMode.fcat || widget.mode == FolkIndexMode.both;

  @override
  void dispose() { _searchCtl.dispose(); super.dispose(); }

  /// Lower-cases and strips Vietnamese diacritics (đ → d) so "cheo" finds
  /// "Chèo" and "ly" finds "Lý".
  static String _fold(String s) {
    const groups = {
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    final buf = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      var out = ch;
      for (final g in groups.entries) {
        if (g.value.contains(ch)) { out = g.key; break; }
      }
      buf.write(out);
    }
    return buf.toString();
  }

  bool _matches(String? title) {
    if (_query.isEmpty) return true;
    if (title == null) return false;
    return _fold(title).contains(_fold(_query));
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (!_loading || _failed) setState(() { _loading = true; _failed = false; });
    try {
      // Fetch only what the active mode needs — saves a round-trip on the
      // dedicated single-list pages.
      final melodyBlock = _wantMelodies
          ? r'melodies(first: 200, orderBy: [{column: "title", order: ASC}]) { data { id slug title } }'
          : '';
      final fcatBlock = _wantFcats
          ? r'fcats(first: 200, orderBy: [{column: "title", order: ASC}]) { data { id slug title } }'
          : '';
      final data = await ApiClient.query('query { $melodyBlock $fcatBlock }', {});
      if (!mounted) return;
      setState(() {
        _melodies = (data['melodies']?['data'] ?? []) as List;
        _folkCats = (data['fcats']?['data'] ?? []) as List;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  String get _appBarTitle {
    switch (widget.mode) {
      case FolkIndexMode.melody: return 'Làn điệu dân ca';
      case FolkIndexMode.fcat: return 'Thể loại dân ca';
      case FolkIndexMode.both: return 'Dân ca';
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(_appBarTitle),
        centerTitle: true,
        leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
      ),
      body: Stack(children: [
        if (_loading)
          Center(child: CircularProgressIndicator(color: AppColors.accent))
        else if (_failed)
          ListView(children: [OfflineBlock(onRetry: _fetch)])
        else
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              // Inline filter — both lists can hold 50+ chips, easier to
              // scan by typing than by scrolling.
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _searchCtl,
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  style: body(TextStyle(fontSize: 16, color: AppColors.text)),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    hintText: 'Lọc theo tên...',
                    hintStyle: body(TextStyle(fontSize: 16, color: AppColors.textMuted)),
                    prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textMuted),
                    suffixIcon: _query.isEmpty ? null : IconButton(
                      tooltip: 'Xoá',
                      icon: Icon(Icons.close, size: 18, color: AppColors.textMuted),
                      onPressed: () { _searchCtl.clear(); setState(() => _query = ''); },
                    ),
                  ),
                ),
              ),
              ...() {
                final filteredMelodies = _melodies.where((m) => _matches((m as Map)['title']?.toString())).toList();
                final filteredFcats = _folkCats.where((f) => _matches((f as Map)['title']?.toString())).toList();
                final showMelodies = _wantMelodies && filteredMelodies.isNotEmpty;
                final showFcats = _wantFcats && filteredFcats.isNotEmpty;
                final widgets = <Widget>[];
                if (showMelodies) {
                  widgets.add(SectionHeader(icon: Icons.graphic_eq, title: 'Làn điệu', count: '(${filteredMelodies.length}${_query.isEmpty ? '' : '/${_melodies.length}'})'));
                  widgets.add(Wrap(
                    spacing: 8, runSpacing: 8,
                    children: filteredMelodies.map((m) {
                      final mm = Map<String, dynamic>.from(m);
                      return _Chip(label: mm['title']?.toString() ?? '', onTap: () => context.push('/lan-dieu/${mm['slug']}'));
                    }).toList(),
                  ));
                  if (widget.mode == FolkIndexMode.both) widgets.add(const SizedBox(height: 24));
                }
                if (showFcats) {
                  widgets.add(SectionHeader(icon: Icons.category_outlined, title: 'Thể loại dân ca', count: '(${filteredFcats.length}${_query.isEmpty ? '' : '/${_folkCats.length}'})'));
                  widgets.add(Wrap(
                    spacing: 8, runSpacing: 8,
                    children: filteredFcats.map((f) {
                      final ff = Map<String, dynamic>.from(f);
                      return _Chip(label: ff['title']?.toString() ?? '', onTap: () => context.push('/dan-ca/${ff['slug']}'));
                    }).toList(),
                  ));
                }
                if (widgets.isEmpty && _query.isNotEmpty) {
                  widgets.add(Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('Không có kết quả cho "${_searchCtl.text}"', textAlign: TextAlign.center, style: body(TextStyle(fontSize: 16, color: AppColors.textMuted)))),
                  ));
                }
                return widgets;
              }(),
            ],
          ),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          // 13 + ~20 text + 13 + border ≈ 48pt tap target.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(label, style: body(TextStyle(fontSize: 15, color: AppColors.text, fontWeight: FontWeight.w500))),
        ),
      ),
    );
  }
}
