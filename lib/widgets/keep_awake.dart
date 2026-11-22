import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while [controller] is playing, so a video doesn't get
/// cut off by the phone's auto-lock (member report, Oppo A9 2020, 21/11).
/// Wrap the player widget; the lock is released when playback pauses/ends
/// or the widget leaves the tree. Several players share one global count.
class KeepAwakeWhilePlaying extends StatefulWidget {
  const KeepAwakeWhilePlaying({super.key, required this.controller, required this.child});
  final VideoPlayerController controller;
  final Widget child;

  @override
  State<KeepAwakeWhilePlaying> createState() => _KeepAwakeWhilePlayingState();
}

int _awake = 0;

void _apply() {
  try {
    WakelockPlus.toggle(enable: _awake > 0);
  } catch (_) {}
}

class _KeepAwakeWhilePlayingState extends State<KeepAwakeWhilePlaying> {
  bool _holding = false;

  void _set(bool hold) {
    if (hold == _holding) return;
    _holding = hold;
    _awake += hold ? 1 : -1;
    _apply();
  }

  void _onTick() {
    final v = widget.controller.value;
    _set(v.isInitialized && v.isPlaying);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
    _onTick();
  }

  @override
  void didUpdateWidget(KeepAwakeWhilePlaying old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      try { old.controller.removeListener(_onTick); } catch (_) {}
      widget.controller.addListener(_onTick);
      _onTick();
    }
  }

  @override
  void dispose() {
    // The controller may already be disposed by the parent's dispose().
    try { widget.controller.removeListener(_onTick); } catch (_) {}
    _set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
