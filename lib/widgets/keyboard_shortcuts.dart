import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/player.dart';

/// Top-level keyboard shortcuts for the desktop app, modelled after
/// Spotify / Apple Music:
///   Space            → play/pause
///   Arrow Left/Right → seek -5s / +5s
///   Shift+Arrow      → previous / next track
///   Cmd+F            → focus the search route
///   Cmd+L            → open the full player (lyrics tab)
///   Cmd+,            → open settings
///
/// Wraps a child and intercepts keys via [Focus] + a raw key listener so we
/// can inspect modifiers without paying for an Actions/Intents tree (the set
/// is small and global). Skips handling whenever a text input has focus so
/// typing in search/comments isn't hijacked.
class KeyboardShortcuts extends StatefulWidget {
  final Widget child;
  const KeyboardShortcuts({super.key, required this.child});

  @override
  State<KeyboardShortcuts> createState() => _KeyboardShortcutsState();
}

class _KeyboardShortcutsState extends State<KeyboardShortcuts> {
  final FocusNode _focus = FocusNode(debugLabel: 'KeyboardShortcuts', skipTraversal: true);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool _isTextFieldFocused() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    final ctx = primary.context;
    if (ctx == null) return false;
    // Editable text widgets register themselves in the focus tree; checking
    // their context is the cheapest way to detect "user is typing".
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null
        || primary.debugLabel?.contains('EditableText') == true;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = pressed.contains(LogicalKeyboardKey.metaLeft)
        || pressed.contains(LogicalKeyboardKey.metaRight)
        || pressed.contains(LogicalKeyboardKey.controlLeft)
        || pressed.contains(LogicalKeyboardKey.controlRight);
    final shift = pressed.contains(LogicalKeyboardKey.shiftLeft)
        || pressed.contains(LogicalKeyboardKey.shiftRight);

    final typing = _isTextFieldFocused();
    final player = context.read<PlayerProvider>();

    // Cmd/Ctrl shortcuts always run, even while typing — Cmd+F is the
    // canonical way to jump to search regardless of current focus.
    if (meta) {
      if (key == LogicalKeyboardKey.keyF) {
        context.go('/search');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyL) {
        // TODO(sprint3): open FullPlayer with lyrics tab pre-selected.
        // For now navigate to search as no-op route lookup; replace once
        // FullPlayer accepts an initial-tab argument.
        return KeyEventResult.ignored;
      }
      if (key == LogicalKeyboardKey.comma) {
        context.go('/cai-dat');
        return KeyEventResult.handled;
      }
    }

    if (typing) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.space) {
      player.togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (shift) {
        player.playPrev();
      } else {
        final newPos = player.position - const Duration(seconds: 5);
        player.seek(newPos < Duration.zero ? Duration.zero : newPos);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (shift) {
        player.playNext();
      } else {
        final dur = player.duration;
        final target = player.position + const Duration(seconds: 5);
        player.seek(target > dur ? dur : target);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Only enable on desktop platforms — mobile uses on-screen controls.
    final isDesktop = kIsWeb || defaultTargetPlatform == TargetPlatform.macOS
        || defaultTargetPlatform == TargetPlatform.windows
        || defaultTargetPlatform == TargetPlatform.linux;
    if (!isDesktop) return widget.child;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}
