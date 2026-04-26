import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import '../services/api.dart';
import '../services/player.dart';
import '../widgets/mini_player.dart';

class StaticPageScreen extends StatefulWidget {
  final String slug;
  const StaticPageScreen({super.key, required this.slug});

  @override
  State<StaticPageScreen> createState() => _StaticPageScreenState();
}

class _StaticPageScreenState extends State<StaticPageScreen> {
  Map<String, dynamic>? _page;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await ApiClient.query(
        r'query($slug: Mixed) { pages(first: 1, where: { column: "slug", value: $slug }) { data { id title slug content } } }',
        {'slug': widget.slug},
      );
      final list = (data['pages']?['data'] ?? []) as List;
      if (!mounted) return;
      setState(() {
        _page = list.isNotEmpty ? Map<String, dynamic>.from(list.first as Map) : null;
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg.withValues(alpha: 0.88),
            title: Text((_page?['title'] ?? '').toString().toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary))),
            centerTitle: true,
            leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.text), onPressed: () => context.pop()),
          ),
          if (_loading)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else if (_page == null)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Không tìm thấy trang', style: AppText.bodyText)))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList(delegate: SliverChildListDelegate([
                Text(_page!['title'] ?? '', style: display(const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.5))),
                const SizedBox(height: 18),
                Html(
                  data: _page!['content'] ?? '',
                  style: {
                    'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero, fontSize: FontSize(14), lineHeight: const LineHeight(1.7), color: AppColors.textSecondary, fontFamily: body().fontFamily),
                    'h1, h2, h3': Style(color: AppColors.text, fontFamily: display().fontFamily),
                    'a': Style(color: AppColors.accentLight, textDecoration: TextDecoration.none),
                    'p': Style(margin: Margins.only(bottom: 10)),
                    'img': Style(width: Width(100, Unit.percent)),
                  },
                  onLinkTap: (url, _, __) {
                    if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                ),
                SizedBox(height: player.currentSong != null ? 90 : 20),
              ])),
            ),
        ]),
        if (player.currentSong != null) const Positioned(left: 0, right: 0, bottom: 8, child: MiniPlayer()),
      ]),
    );
  }
}
