import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_html/flutter_html.dart';
import '../constants/theme.dart';
import '../services/api.dart';

String _stripHtml(String html) {
  // Replace block-ish tags with newline, strip the rest
  var s = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  s = s.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'");
  return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

List<String> _tokenize(String text) {
  // Split keeping whitespace as separate tokens to preserve formatting
  final tokens = <String>[];
  final buf = StringBuffer();
  bool inWord = false;
  for (final c in text.split('')) {
    final isSpace = c == ' ' || c == '\t' || c == '\n' || c == '\r';
    if (isSpace != !inWord) {
      if (buf.isNotEmpty) { tokens.add(buf.toString()); buf.clear(); }
      inWord = !isSpace;
    }
    buf.write(c);
  }
  if (buf.isNotEmpty) tokens.add(buf.toString());
  return tokens;
}

String _htmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('\n', '<br>');

/// Produces HTML with <ins> and <del> markers for word-level diff.
String computeDiffHtml(String oldHtml, String newHtml) {
  final oldT = _tokenize(_stripHtml(oldHtml));
  final newT = _tokenize(_stripHtml(newHtml));
  final n = oldT.length, m = newT.length;

  // LCS DP — cap to avoid pathological memory (typical lyric should be small)
  if (n > 2000 || m > 2000) {
    return '<del>${_htmlEscape(oldT.join(''))}</del><br><br><ins>${_htmlEscape(newT.join(''))}</ins>';
  }

  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      if (oldT[i - 1] == newT[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = dp[i - 1][j] >= dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
      }
    }
  }

  // Backtrack
  final ops = <_Op>[];
  var i = n, j = m;
  while (i > 0 && j > 0) {
    if (oldT[i - 1] == newT[j - 1]) {
      ops.add(_Op.same(oldT[i - 1])); i--; j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      ops.add(_Op.del(oldT[i - 1])); i--;
    } else {
      ops.add(_Op.ins(newT[j - 1])); j--;
    }
  }
  while (i > 0) { ops.add(_Op.del(oldT[i - 1])); i--; }
  while (j > 0) { ops.add(_Op.ins(newT[j - 1])); j--; }
  final rev = ops.reversed.toList();

  // Group consecutive ops of same kind
  final out = StringBuffer();
  var k = 0;
  while (k < rev.length) {
    final kind = rev[k].kind;
    final group = StringBuffer();
    while (k < rev.length && rev[k].kind == kind) {
      group.write(rev[k].text);
      k++;
    }
    final esc = _htmlEscape(group.toString());
    if (kind == _OpKind.same) {
      out.write(esc);
    } else if (kind == _OpKind.ins) {
      out.write('<ins>$esc</ins>');
    } else {
      out.write('<del>$esc</del>');
    }
  }
  return out.toString();
}

enum _OpKind { same, ins, del }
class _Op {
  final _OpKind kind;
  final String text;
  _Op.same(this.text) : kind = _OpKind.same;
  _Op.ins(this.text) : kind = _OpKind.ins;
  _Op.del(this.text) : kind = _OpKind.del;
}

class LyricHistoryDialog extends StatefulWidget {
  final String songId;
  final String songType;
  const LyricHistoryDialog({super.key, required this.songId, this.songType = 'song'});

  @override
  State<LyricHistoryDialog> createState() => _LyricHistoryDialogState();
}

class _LyricHistoryDialogState extends State<LyricHistoryDialog> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await ApiClient.query(
        r'''query($where: WhereConditions) {
          activities(first: 50, orderBy: [{column: "id", order: DESC}], where: $where) {
            edges { node { id extra created_at user { id username avatar { url } } } }
          }
        }''',
        {
          'where': {
            'AND': [
              {'column': 'action', 'value': 'update_lyric'},
              {'column': 'object_type', 'value': widget.songType},
              {'column': 'object_id', 'value': widget.songId},
            ]
          }
        },
      );
      final edges = (data['activities']?['edges'] ?? []) as List;
      final items = <Map<String, dynamic>>[];
      for (final e in edges) {
        final node = e['node'] as Map<String, dynamic>;
        Map<String, dynamic> extra = {};
        final raw = node['extra'];
        try {
          if (raw is String) extra = jsonDecode(raw) as Map<String, dynamic>;
          else if (raw is Map) extra = Map<String, dynamic>.from(raw);
        } catch (_) {}
        final oldVal = extra['old_value']?.toString() ?? '';
        final newVal = extra['new_value']?.toString() ?? '';
        items.add({...node, 'diff': computeDiffHtml(oldVal, newVal)});
      }
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _timeAgo(String? s) {
    if (s == null) return '';
    try {
      final d = DateTime.parse(s);
      final now = DateTime.now();
      final diff = now.difference(d).inSeconds;
      if (diff < 60) return 'vừa xong';
      if (diff < 3600) return '${diff ~/ 60} phút trước';
      if (diff < 86400) return '${diff ~/ 3600} giờ trước';
      if (diff < 2592000) return '${diff ~/ 86400} ngày trước';
      if (diff < 31536000) return '${diff ~/ 2592000} tháng trước';
      return '${diff ~/ 31536000} năm trước';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.history_edu, color: AppColors.textSecondary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Lịch sử sửa lời', style: display(const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)))),
                  IconButton(icon: const Icon(Icons.close, color: AppColors.textMuted), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.accent))
            else if (_items.isEmpty)
              Padding(padding: const EdgeInsets.all(30), child: Text('Chưa có lịch sử sửa lời', style: body(const TextStyle(color: AppColors.textMuted))))
            else
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final item = _items[i];
                    final user = item['user'];
                    return Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: AppColors.surface,
                                backgroundImage: user?['avatar']?['url'] != null ? CachedNetworkImageProvider(user['avatar']['url']) : null,
                                child: user?['avatar']?['url'] == null
                                    ? Text((user?['username'] ?? '?').toString().substring(0, 1).toUpperCase(), style: body(const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)))
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Text(user?['username'] ?? '?', style: body(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text))),
                              const SizedBox(width: 8),
                              Text(_timeAgo(item['created_at']?.toString()), style: body(const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.textMuted))),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Html(
                            data: item['diff'] as String,
                            style: {
                              'body': Style(
                                margin: Margins.zero,
                                padding: HtmlPaddings.zero,
                                fontSize: FontSize(13),
                                lineHeight: const LineHeight(1.8),
                                color: AppColors.textSecondary,
                                fontFamily: body().fontFamily,
                              ),
                              'ins': Style(
                                backgroundColor: const Color(0x3366BB6A),
                                color: const Color(0xFFA5D6A7),
                                textDecoration: TextDecoration.none,
                              ),
                              'del': Style(
                                backgroundColor: const Color(0x33E57373),
                                color: const Color(0xFFEF9A9A),
                                textDecoration: TextDecoration.lineThrough,
                              ),
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
