import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';

// "Tìm trong danh sách": a name box above the sort chips of every song list
// (thể loại, tag, nghệ sĩ, yêu thích…). The API filters with `q` (accent- and
// đ/d-insensitive); [foldVi] mirrors that rule on the phone, for highlighting
// the match and for lists that live on the phone (Đã tải về).

const _from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
final Map<int, int> _fold = {for (var i = 0; i < _from.length; i++) _from.codeUnitAt(i): _to.codeUnitAt(i)};

/// Lowercase without Vietnamese tone marks, "đ" → "d". One character in,
/// one character out, so positions in the folded text match the original.
String foldVi(String s) => String.fromCharCodes(s.toLowerCase().codeUnits.map((c) => _fold[c] ?? c));

/// Whether [title] contains [query] by the same rule as the API.
bool titleMatches(String title, String query) {
  final q = foldVi(query.trim());
  return q.isEmpty || foldVi(title).contains(q);
}

/// [text] as spans with every match of [query] in bold red.
List<InlineSpan> highlightSpans(String text, String? query, TextStyle hit) {
  final q = foldVi((query ?? '').trim());
  if (q.isEmpty) return [TextSpan(text: text)];
  final f = foldVi(text);
  // toLowerCase may change length on exotic characters: then don't highlight.
  if (f.length != text.length) return [TextSpan(text: text)];
  final out = <InlineSpan>[];
  var i = 0;
  while (true) {
    final j = f.indexOf(q, i);
    if (j < 0) break;
    if (j > i) out.add(TextSpan(text: text.substring(i, j)));
    out.add(TextSpan(text: text.substring(j, j + q.length), style: hit));
    i = j + q.length;
  }
  if (i < text.length) out.add(TextSpan(text: text.substring(i)));
  return out;
}

/// The name box. [onChanged] fires 0.4 s after the reader stops typing (or
/// at once on "Tìm" / clear), so a list is not reloaded on every key.
class ListSearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final EdgeInsetsGeometry padding;
  /// Words to start with (a tab rebuilt after scrolling away keeps them).
  final String initial;
  const ListSearchField({super.key, required this.hint, required this.onChanged, this.padding = EdgeInsets.zero, this.initial = ''});

  @override
  State<ListSearchField> createState() => _ListSearchFieldState();
}

class _ListSearchFieldState extends State<ListSearchField> {
  late final _ctl = TextEditingController(text: widget.initial);
  Timer? _debounce;
  late String _sent = widget.initial;

  @override
  void initState() {
    super.initState();
    // Screenshot/automation hook: BCDCNT_LIST_Q="truong son" (desktop only)
    // types those words into the first list search box. No-op in normal use.
    final shot = kIsWeb || !(Platform.isMacOS || Platform.isWindows || Platform.isLinux) ? null : Platform.environment['BCDCNT_LIST_Q'];
    if (shot != null && shot.isNotEmpty && widget.initial.isEmpty) {
      _ctl.text = shot;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send(shot);
      });
    }
  }

  void _send(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q == _sent) return;
    _sent = q;
    widget.onChanged(q);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    return Padding(
      padding: widget.padding,
      child: TextField(
        controller: _ctl,
        textInputAction: TextInputAction.search,
        style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
        onChanged: (v) {
          setState(() {}); // clear button
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 400), () => _send(v));
        },
        onSubmitted: _send,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          hintMaxLines: 1,
          hintStyle: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          prefixIcon: Icon(Icons.search_rounded, size: 22, color: AppColors.textMuted),
          suffixIcon: _ctl.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Xoá ô tìm',
                  icon: Icon(Icons.cancel_rounded, size: 20, color: AppColors.textMuted),
                  onPressed: () {
                    _ctl.clear();
                    setState(() {});
                    _send('');
                  },
                ),
          border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.accent, width: 2)),
        ),
      ),
    );
  }
}

/// "77 bài có “truong son”" under the box while searching.
class ListSearchSummary extends StatelessWidget {
  final String query;
  final int total;
  final bool loading;
  const ListSearchSummary({super.key, required this.query, required this.total, this.loading = false});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty || loading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
      child: Semantics(
        liveRegion: true,
        child: Text('$total bài có “$query”', style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
      ),
    );
  }
}

/// No song in this list has [query] in its name: offer the site-wide search.
class ListSearchEmpty extends StatelessWidget {
  final String query;
  const ListSearchEmpty({super.key, required this.query});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
      child: Column(children: [
        Text('Không có bài nào tên có “$query”', textAlign: TextAlign.center, style: body(TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
        const SizedBox(height: 4),
        Text('Thử gõ ít chữ hơn, hoặc tìm trên toàn trang', textAlign: TextAlign.center, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
        const SizedBox(height: 12),
        TextButton(
          style: TextButton.styleFrom(
            backgroundColor: AppColors.surface,
            minimumSize: const Size(48, 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: const StadiumBorder(),
          ),
          onPressed: () => context.push('/search?q=${Uri.encodeQueryComponent(query)}'),
          child: Text('Tìm “$query” trên toàn trang', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text))),
        ),
      ]),
    );
  }
}
