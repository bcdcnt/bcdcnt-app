import 'package:flutter/material.dart';
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
  List _melodies = [];
  List _folkCats = [];

  bool get _wantMelodies => widget.mode == FolkIndexMode.melody || widget.mode == FolkIndexMode.both;
  bool get _wantFcats => widget.mode == FolkIndexMode.fcat || widget.mode == FolkIndexMode.both;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
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
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _appBarTitle {
    switch (widget.mode) {
      case FolkIndexMode.melody: return 'LÀN ĐIỆU DÂN CA';
      case FolkIndexMode.fcat: return 'THỂ LOẠI DÂN CA';
      case FolkIndexMode.both: return 'DÂN CA';
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(_appBarTitle, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
      ),
      body: Stack(children: [
        if (_loading)
          const Center(child: CircularProgressIndicator(color: AppColors.accent))
        else
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              if (_wantMelodies && _melodies.isNotEmpty) ...[
                SectionHeader(icon: Icons.graphic_eq, title: 'Làn điệu', count: '(${_melodies.length})'),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _melodies.map((m) {
                    final mm = Map<String, dynamic>.from(m);
                    return _Chip(label: mm['title']?.toString() ?? '', onTap: () => context.push('/lan-dieu/${mm['slug']}'));
                  }).toList(),
                ),
                if (widget.mode == FolkIndexMode.both) const SizedBox(height: 24),
              ],
              if (_wantFcats && _folkCats.isNotEmpty) ...[
                SectionHeader(icon: Icons.category_outlined, title: 'Thể loại dân ca', count: '(${_folkCats.length})'),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _folkCats.map((f) {
                    final ff = Map<String, dynamic>.from(f);
                    return _Chip(label: ff['title']?.toString() ?? '', onTap: () => context.push('/dan-ca/${ff['slug']}'));
                  }).toList(),
                ),
              ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label, style: body(const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500))),
      ),
    );
  }
}
