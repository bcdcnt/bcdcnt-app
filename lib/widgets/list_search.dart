import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/theme.dart';
import 'desktop_page.dart' show isDesk;
import 'ui.dart' show SortTabs, pickSort;

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
  final bool autofocus;
  const ListSearchField({super.key, required this.hint, required this.onChanged, this.padding = EdgeInsets.zero, this.initial = '', this.autofocus = false});

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
        autofocus: widget.autofocus,
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

/// Search + sort above a song list. Desktop keeps the full-width box and the
/// "N bài · Sắp xếp: … ▾" line; phones get [ListControlBar] (canvas PA C).
class ListControls extends StatelessWidget {
  final String hint;
  final String query;
  final ValueChanged<String> onSearch;
  final int total;
  final bool loading;
  final List<String> sorts;
  final int sort;
  final ValueChanged<int> onSort;
  /// Desktop line left of the sort button ("14.107 bài").
  final String? summary;
  /// Phone only: extra round buttons after 🔍 (Tải tất cả).
  final List<Widget> actions;
  const ListControls({super.key, required this.hint, required this.query, required this.onSearch, required this.total, this.loading = false, required this.sorts, required this.sort, required this.onSort, this.summary, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    if (!isDesk(context)) {
      return ListControlBar(hint: hint, query: query, onSearch: onSearch, total: total, loading: loading, sorts: sorts, sort: sort, onSort: onSort, actions: actions);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      ListSearchField(initial: query, hint: hint, onChanged: onSearch),
      ListSearchSummary(query: query, total: total, loading: loading),
      const SizedBox(height: 14),
      SortTabs(summary: query.isEmpty && total > 0 ? summary : null, labels: sorts, selected: sort, padding: EdgeInsets.zero, onSelect: onSort),
    ]);
  }
}

/// Phone list controls (canvas NgheSi / PA C, 22/11): one row — the current
/// sort as a pill ("Nghe nhiều nhất ▾", opens the sort sheet) on the left,
/// round 🔍 (and [actions]) on the right. Tapping 🔍 swaps the row for the
/// search box + "Đóng"; under it "N bài có “…”" with a small sort button,
/// so the order can still change while searching.
class ListControlBar extends StatefulWidget {
  final String hint;
  final String query;
  final ValueChanged<String> onSearch;
  final int total;
  final bool loading;
  final List<String> sorts;
  final int sort;
  final ValueChanged<int> onSort;
  final List<Widget> actions;
  const ListControlBar({super.key, required this.hint, required this.query, required this.onSearch, required this.total, this.loading = false, required this.sorts, required this.sort, required this.onSort, this.actions = const []});

  @override
  State<ListControlBar> createState() => _ListControlBarState();
}

class _ListControlBarState extends State<ListControlBar> {
  // A list rebuilt with words already typed (tab switch) opens searching.
  late bool _open = widget.query.isNotEmpty;

  int get _cur => widget.sorts.isEmpty ? 0 : widget.sort.clamp(0, widget.sorts.length - 1);

  Future<void> _pick() async {
    final i = await pickSort(context, widget.sorts, _cur);
    if (i != null && i != widget.sort) widget.onSort(i);
  }

  void _close() {
    if (widget.query.isNotEmpty) widget.onSearch('');
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final canSort = widget.sorts.length > 1;
    if (_open) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: ListSearchField(initial: widget.query, hint: widget.hint, autofocus: widget.query.isEmpty, onChanged: widget.onSearch)),
          TextButton(
            onPressed: _close,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 10)),
            child: Text('Đóng', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.accentFg))),
          ),
        ]),
        if (widget.query.isNotEmpty || canSort)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Expanded(
                child: widget.query.isEmpty || widget.loading
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Semantics(
                          liveRegion: true,
                          child: Text('${widget.total} bài có “${widget.query}”', maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
                        ),
                      ),
              ),
              if (canSort)
                Semantics(
                  button: true,
                  label: 'Sắp xếp: ${widget.sorts[_cur]}',
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _pick,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 40),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(widget.sorts[_cur], style: body(TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
                          Icon(Icons.arrow_drop_down_rounded, size: 22, color: AppColors.text),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
      ]);
    }
    return Row(children: [
      Expanded(
        child: !canSort ? const SizedBox.shrink() : Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            button: true,
            label: 'Sắp xếp: ${widget.sorts[_cur]}',
            excludeSemantics: true,
            child: Material(
              color: AppColors.surface,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: _pick,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.sort_rounded, size: 20, color: AppColors.text),
                    const SizedBox(width: 8),
                    Flexible(child: Text(widget.sorts[_cur], maxLines: 1, overflow: TextOverflow.ellipsis, style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)))),
                    Icon(Icons.arrow_drop_down_rounded, size: 22, color: AppColors.text),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      RoundIconButton(icon: Icons.search_rounded, tooltip: widget.hint, onTap: () => setState(() => _open = true)),
      for (final a in widget.actions) ...[const SizedBox(width: 8), a],
    ]);
  }
}

/// 48pt round button on the surface colour (🔍, Tải tất cả).
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final Color? background;
  final Widget? child;
  const RoundIconButton({super.key, required this.icon, required this.tooltip, this.onTap, this.color, this.background, this.child});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: background ?? AppColors.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 48, height: 48, child: child ?? Icon(icon, size: 22, color: color ?? AppColors.text)),
          ),
        ),
      ),
    );
  }
}
