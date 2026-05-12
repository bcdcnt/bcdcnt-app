import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_quill/quill_delta.dart' show Delta;
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart' show QuillDeltaToHtmlConverter;
import '../constants/theme.dart';

/// Thin wrapper around `flutter_quill` so the comment input can hold
/// rich text + inline images while exposing a simple TextField-like
/// API to the parent. The parent stays HTML-native: it gives us HTML
/// in and reads HTML out — keeping the existing comment storage
/// format and the `CommentMedia` viewer untouched.
class QuillCommentInput extends StatelessWidget {
  final QuillCommentController controller;
  final String hintText;
  final bool autofocus;
  final double minHeight;
  final double maxHeight;

  const QuillCommentInput({
    super.key,
    required this.controller,
    this.hintText = 'Viết bình luận...',
    this.autofocus = false,
    this.minHeight = 32,
    this.maxHeight = 320,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight, maxHeight: maxHeight),
      child: q.QuillEditor(
        controller: controller._quill,
        focusNode: controller._focus,
        scrollController: controller._scroll,
        config: q.QuillEditorConfig(
          placeholder: hintText,
          autoFocus: autofocus,
          expands: false,
          padding: const EdgeInsets.symmetric(vertical: 6),
          embedBuilders: [_InlineImageEmbedBuilder()],
          scrollable: true,
          customStyles: q.DefaultStyles(
            paragraph: q.DefaultTextBlockStyle(
              TextStyle(color: AppColors.text, fontSize: 14, height: 1.45),
              const q.HorizontalSpacing(0, 0),
              const q.VerticalSpacing(2, 2),
              const q.VerticalSpacing(0, 0),
              null,
            ),
            placeHolder: q.DefaultTextBlockStyle(
              TextStyle(color: AppColors.textMuted, fontSize: 14),
              const q.HorizontalSpacing(0, 0),
              const q.VerticalSpacing(2, 2),
              const q.VerticalSpacing(0, 0),
              null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Owner-managed handle (modeled after `TextEditingController`).
/// Construct, hand to `QuillCommentInput`, and dispose when done.
class QuillCommentController {
  late final q.QuillController _quill;
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  QuillCommentController({String? initialHtml}) {
    final delta = (initialHtml != null && initialHtml.isNotEmpty)
        ? _htmlToDelta(initialHtml)
        : (Delta()..insert('\n'));
    _quill = q.QuillController(
      document: q.Document.fromDelta(delta),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  /// Returns the editor content as HTML in the same shape the web
  /// produces: `<p>...</p>` per paragraph, `<br>` for soft breaks,
  /// `<img src="...">` for inline images.
  String get html {
    final delta = _quill.document.toDelta();
    final converter = QuillDeltaToHtmlConverter(delta.toJson(), null);
    var out = converter.convert();
    // Quill always trails a `\n` → renders to `<p><br/></p>`. Drop it
    // (and any chain of empty paragraphs) so we don't store noise.
    out = out.replaceAll(RegExp(r'(<p><br/?></p>)+$'), '');
    return out.trim();
  }

  bool get isEmpty => _quill.document.toPlainText().trim().isEmpty;

  void setHtml(String html) {
    final delta = _htmlToDelta(html);
    _quill.document = q.Document.fromDelta(delta);
    _quill.updateSelection(
      TextSelection.collapsed(offset: _quill.document.length - 1),
      q.ChangeSource.local,
    );
  }

  /// Insert an `<img>` at the current selection — used after a
  /// clipboard paste or file pick finishes uploading.
  void insertImageUrl(String url) {
    final idx = _quill.selection.baseOffset;
    final len = _quill.selection.extentOffset - idx;
    _quill.replaceText(
      idx,
      len,
      q.BlockEmbed.image(url),
      TextSelection.collapsed(offset: idx + 1),
    );
    // Add a newline after so the user keeps typing on a fresh line.
    _quill.replaceText(
      _quill.selection.baseOffset,
      0,
      '\n',
      TextSelection.collapsed(offset: _quill.selection.baseOffset + 1),
    );
  }

  void clear() {
    _quill.document = q.Document();
  }

  void requestFocus() => _focus.requestFocus();

  /// Stream of document change events — every keystroke / paste /
  /// replaceText surfaces here. Used by the mention typeahead.
  Stream<dynamic> get documentChanges => _quill.document.changes;

  /// Plain text + cursor offset that match what the user typed,
  /// for mention detection (`@token` substring matching).
  String get plainText => _quill.document.toPlainText();
  int get cursorOffset => _quill.selection.baseOffset;

  /// Replace a range with `text`, then place the caret right after
  /// the inserted text. Used to swap an `@partial` query for the
  /// resolved `@username ` once the user picks an option.
  void replaceTextAt(int start, int length, String text) {
    _quill.replaceText(
      start, length, text,
      TextSelection.collapsed(offset: start + text.length),
    );
  }

  void dispose() {
    _quill.dispose();
    _focus.dispose();
    _scroll.dispose();
  }

  Delta _htmlToDelta(String html) {
    try {
      return HtmlToDelta().convert(html);
    } catch (_) {
      return Delta()
        ..insert(html.replaceAll(RegExp(r'<[^>]+>'), ''))
        ..insert('\n');
    }
  }
}

/// Renders `image` embeds inline. Small rounded thumbnail so the
/// editor doesn't expand vertically while typing.
class _InlineImageEmbedBuilder extends q.EmbedBuilder {
  @override
  String get key => q.BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, q.EmbedContext embedContext) {
    final url = embedContext.node.value.data as String;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          height: 120,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: 120, height: 120,
            color: AppColors.surfaceLight,
            alignment: Alignment.center,
            child: Icon(Icons.broken_image, color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
