import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/player.dart';
import '../main.dart' show rootNavigatorKey;
import 'command_palette.dart';
import 'desktop_shell.dart' show desktopPanelOpen;

typedef AncestorMatcher = bool Function(Widget widget);

/// Top-level keyboard shortcuts for the desktop app, modelled after
/// Spotify / Apple Music:
///   Space            → play/pause
///   Arrow Left/Right → seek -5s / +5s
///   Shift+Arrow      → previous / next track
///   Cmd+K            → open command palette
///   Cmd+F            → focus the search route
///   Cmd+,            → open settings
///   Cmd+I            → toggle the right inspector panel
///
/// Hooks into [HardwareKeyboard] directly instead of relying on the [Focus]
/// tree so the shortcuts keep firing after a [TextField] grabs focus or a
/// modal route pushes on top — those scenarios broke the previous Focus-based
/// implementation. The handler still defers to the focused widget for
/// non-modifier keys (Space, arrows) when a text input is active so typing
/// isn't hijacked.
class KeyboardShortcuts extends StatefulWidget {
  final Widget child;
  const KeyboardShortcuts({super.key, required this.child});

  @override
  State<KeyboardShortcuts> createState() => _KeyboardShortcutsState();
}

class _KeyboardShortcutsState extends State<KeyboardShortcuts> {
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    final isDesktop = kIsWeb || defaultTargetPlatform == TargetPlatform.macOS
        || defaultTargetPlatform == TargetPlatform.windows
        || defaultTargetPlatform == TargetPlatform.linux;
    if (isDesktop) {
      HardwareKeyboard.instance.addHandler(_handler);
      _registered = true;
    }
  }

  @override
  void dispose() {
    if (_registered) HardwareKeyboard.instance.removeHandler(_handler);
    super.dispose();
  }

  bool _isTextFieldFocused() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    final ctx = primary.context;
    if (ctx == null) return false;
    if (ctx.findAncestorWidgetOfExactType<EditableText>() != null) return true;
    // Quill renders its own editor (`QuillRawEditor`) instead of
    // Flutter's `EditableText`, so the ancestor check above misses
    // it — typing space inside a comment would otherwise pause
    // the player. Match by runtime widget type name to avoid
    // pulling flutter_quill into this file.
    AncestorMatcher matcher = (w) {
      final n = w.runtimeType.toString();
      return n == 'QuillRawEditor' || n == 'QuillEditor';
    };
    return _hasAncestorMatching(ctx, matcher);
  }

  bool _hasAncestorMatching(BuildContext ctx, AncestorMatcher matcher) {
    bool found = false;
    ctx.visitAncestorElements((el) {
      if (matcher(el.widget)) { found = true; return false; }
      return true;
    });
    return found;
  }

  bool _handler(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final key = event.logicalKey;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = pressed.contains(LogicalKeyboardKey.metaLeft)
        || pressed.contains(LogicalKeyboardKey.metaRight)
        || pressed.contains(LogicalKeyboardKey.controlLeft)
        || pressed.contains(LogicalKeyboardKey.controlRight);
    final shift = pressed.contains(LogicalKeyboardKey.shiftLeft)
        || pressed.contains(LogicalKeyboardKey.shiftRight);

    final typing = _isTextFieldFocused();

    // Cmd/Ctrl shortcuts run regardless of typing — they're system-style
    // navigation that shouldn't be blocked by a focused TextField.
    if (meta) {
      // Use the root navigator key so we don't depend on the build context
      // having a Navigator ancestor — this widget sits inside MaterialApp's
      // builder which is *above* the navigator subtree.
      final nav = rootNavigatorKey.currentState;
      final navCtx = nav?.context;
      if (key == LogicalKeyboardKey.keyK) {
        if (nav != null) CommandPalette.show(nav.context, navigatorState: nav);
        return true;
      }
      if (key == LogicalKeyboardKey.keyF) {
        if (navCtx != null) navCtx.go('/search');
        return true;
      }
      if (key == LogicalKeyboardKey.comma) {
        if (navCtx != null) navCtx.go('/cai-dat');
        return true;
      }
      if (key == LogicalKeyboardKey.keyI) {
        // Toggle the desktop right inspector panel (Bình luận / Hàng đợi).
        desktopPanelOpen.value = !desktopPanelOpen.value;
        return true;
      }
      return false;
    }

    if (typing) return false;

    final player = context.read<PlayerProvider>();
    if (key == LogicalKeyboardKey.space) {
      player.togglePlay();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (shift) {
        player.playPrev();
      } else {
        final newPos = player.position - const Duration(seconds: 5);
        player.seek(newPos < Duration.zero ? Duration.zero : newPos);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (shift) {
        player.playNext();
      } else {
        final dur = player.duration;
        final target = player.position + const Duration(seconds: 5);
        player.seek(target > dur ? dur : target);
      }
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
