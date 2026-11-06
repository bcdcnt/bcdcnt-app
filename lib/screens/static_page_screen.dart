import 'package:flutter/material.dart';
import '../widgets/ui.dart' show goBack, OfflineBlock, EmptyBlock;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';
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

/// Known page titles so the app bar is not blank while the page loads.
const _kKnownTitles = {
  'gioi-thieu': 'Giới thiệu',
  'yeu-cau': 'Yêu cầu',
  'dieu-khoan': 'Chính sách & điều khoản',
  'lien-he': 'Liên hệ',
  'tieu-chi': 'Tiêu chí',
  'faq': 'Hỏi đáp',
};

class _StaticPageScreenState extends State<StaticPageScreen> {
  Map<String, dynamic>? _page;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (_error || !_loading) setState(() { _loading = true; _error = false; });
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
    } catch (_) { if (mounted) setState(() { _loading = false; _error = true; }); }
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
            backgroundColor: AppColors.bg,
            title: Text((_page?['title'] ?? _kKnownTitles[widget.slug] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
            centerTitle: true,
            leading: IconButton(tooltip: 'Quay lại', icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.text), onPressed: () => goBack(context)),
          ),
          if (_loading)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
          else if (_error)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: OfflineBlock(onRetry: _fetch)))
          else if (_page == null)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: EmptyBlock(icon: Icons.article_outlined, title: 'Không tìm thấy trang', message: 'Trang này không còn hoặc đã đổi địa chỉ.')))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList(delegate: SliverChildListDelegate([
                Text(_page!['title'] ?? '', style: display(TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.5))),
                const SizedBox(height: 18),
                Html(
                  data: _page!['content'] ?? '',
                  style: {
                    'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero, fontSize: FontSize(16), lineHeight: const LineHeight(1.7), color: AppColors.textSecondary, fontFamily: body().fontFamily),
                    'h1, h2, h3': Style(color: AppColors.text, fontFamily: display().fontFamily),
                    'a': Style(color: AppColors.accentLight, textDecoration: TextDecoration.none),
                    'p': Style(margin: Margins.only(bottom: 10)),
                    'img': Style(width: Width(100, Unit.percent)),
                  },
                  onLinkTap: (url, _, _) {
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
