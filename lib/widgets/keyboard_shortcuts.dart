import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/player.dart';
import 'command_palette.dart';

/// Top-level keyboard shortcuts for the desktop app, modelled after
/// Spotify / Apple Music:
///   Space            → play/pause
///   Arrow Left/Right → seek -5s / +5s
///   Shift+Arrow      → previous / next track
///   Cmd+K            → open command palette
///   Cmd+F            → focus the search route
///   Cmd+,            → open settings
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
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
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
      if (key == LogicalKeyboardKey.keyK) {
        CommandPalette.show(context);
        return true;
      }
      if (key == LogicalKeyboardKey.keyF) {
        context.go('/search');
        return true;
      }
      if (key == LogicalKeyboardKey.comma) {
        context.go('/cai-dat');
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
