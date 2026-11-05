import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../constants/theme.dart';

/// Bottom sheet for "Tìm bằng giọng nói": listens in Vietnamese, shows the
/// words as they are recognised and returns the final text (null when
/// cancelled or nothing was heard). Uses the phone's own recogniser
/// (Apple Speech / Google), so nothing extra is sent to BCĐCNT.
Future<String?> showVoiceSearch(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.bg,
      builder: (_) => const _VoiceSheet(),
    );

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();
  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> with SingleTickerProviderStateMixin {
  final _stt = SpeechToText();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  String _text = '';
  String? _error;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _stt.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _text = '';
    });
    bool ok;
    try {
      ok = await _stt.initialize(
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _error = e.errorMsg.contains('no_match') || e.errorMsg.contains('speech_timeout')
                ? 'Chưa nghe rõ. Bấm micro để nói lại.'
                : 'Không nhận dạng được giọng nói. Bấm micro để thử lại.';
          });
        },
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'done' || s == 'notListening') setState(() => _listening = false);
        },
      );
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'Máy chưa cho phép dùng micro hoặc nhận dạng giọng nói. Bật trong Cài đặt của điện thoại rồi thử lại.');
      return;
    }
    // Prefer Vietnamese; fall back to the device default if it's missing.
    final locales = await _stt.locales();
    final vi = locales.where((l) => l.localeId.toLowerCase().startsWith('vi')).toList();
    HapticFeedback.mediumImpact();
    setState(() => _listening = true);
    await _stt.listen(
      onResult: _onResult,
      localeId: vi.isNotEmpty ? vi.first.localeId : null,
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true, listenMode: ListenMode.search),
    );
  }

  void _onResult(SpeechRecognitionResult r) {
    if (!mounted) return;
    setState(() => _text = r.recognizedWords);
    if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
      HapticFeedback.lightImpact();
      Navigator.pop(context, r.recognizedWords.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = _error ?? (_listening ? (_text.isEmpty ? 'Đang nghe… hãy nói tên bài, nhạc sĩ hoặc một câu hát' : _text) : 'Bấm micro để nói');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 5, decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(3))),
            const SizedBox(height: 18),
            Text('Tìm bằng giọng nói', style: display(TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text))),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: _listening ? () => _stt.stop() : _start,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) => Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.wine,
                    shape: BoxShape.circle,
                    boxShadow: _listening
                        ? [BoxShadow(color: AppColors.wine.withValues(alpha: 0.35), blurRadius: 10 + 26 * _pulse.value, spreadRadius: 4 + 14 * _pulse.value)]
                        : null,
                  ),
                  child: child,
                ),
                child: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded, size: 44, color: Colors.white),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: body(TextStyle(
                fontSize: _text.isNotEmpty && _error == null ? 20 : 15,
                height: 1.5,
                fontWeight: _text.isNotEmpty && _error == null ? FontWeight.w700 : FontWeight.w500,
                color: _error != null ? AppColors.error : (_text.isNotEmpty ? AppColors.text : AppColors.textSecondary),
              )),
            ),
            if (!_listening && _text.trim().isNotEmpty && _error == null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context, _text.trim()),
                child: Text('Tìm "${_text.trim()}"', style: body(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentLight))),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
