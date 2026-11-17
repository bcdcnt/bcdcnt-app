import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, SystemUiOverlayStyle;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/theme.dart';

/// Set by the mobile home once its first load answered (data or not), so
/// the intro can leave as soon as there is something to show.
final ValueNotifier<bool> homeReady = ValueNotifier(false);

/// Màn khởi động, phương án C (canvas "Màn khởi động", chốt 17/11).
///
/// The OS splash (flutter_native_splash, kept up with preserve()) shows only
/// the cream background + the mark — Android 12 allows no more. This overlay
/// takes over pixel-for-pixel (same colour, same 104-wide mark, centred),
/// then the "vân đĩa than" rings bloom out of the mark and the name fades
/// in; it holds until the home has loaded (never less than ~0.9 s, never
/// more than 3 s) and fades away. Mobile only.
class SplashIntro extends StatefulWidget {
  const SplashIntro({super.key});

  @override
  State<SplashIntro> createState() => _SplashIntroState();
}

const _cream = Color(0xFFFAF5EB);
const _night = Color(0xFF161112);
const _logoW = 104.0;

class _SplashIntroState extends State<SplashIntro> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  late final AnimationController _out = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  final _started = DateTime.now();
  String? _svg;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/logo_mark.svg').then((s) {
      if (!mounted) return;
      setState(() => _svg = s);
      // The mark is on screen from the next frame: hand over from the OS
      // splash only then, so the swap is invisible.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FlutterNativeSplash.remove();
        _intro.forward();
      });
    }, onError: (_) => _finish());
    homeReady.addListener(_maybeLeave);
    _intro.addStatusListener((s) {
      if (s == AnimationStatus.completed) _maybeLeave();
    });
    Future.delayed(const Duration(seconds: 3), _leave);
  }

  void _maybeLeave() {
    if (!homeReady.value || !_intro.isCompleted) return;
    final left = const Duration(milliseconds: 900) - DateTime.now().difference(_started);
    Future.delayed(left.isNegative ? Duration.zero : left, _leave);
  }

  void _leave() {
    if (!mounted || _out.isAnimating || _gone) return;
    FlutterNativeSplash.remove();
    _out.forward().whenComplete(_finish);
  }

  void _finish() {
    FlutterNativeSplash.remove();
    if (mounted) setState(() => _gone = true);
  }

  @override
  void dispose() {
    homeReady.removeListener(_maybeLeave);
    _intro.dispose();
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    // Same rule as the OS splash: follow the system, not the app theme.
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final bg = dark ? _night : _cream;
    final ring = dark ? const Color(0xFFE6CFCE) : const Color(0xFF711313);
    final title = dark ? const Color(0xFFF4F1F0) : const Color(0xFF711313);
    final sub = dark ? const Color(0xFFA39698) : const Color(0xFF7A6B6D);
    final rule = dark ? const Color(0xFF6B4A4A) : const Color(0xFFC9A9A8);
    final svg = _svg;
    final rings = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    final text = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.35, 1, curve: Curves.easeOut),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: IgnorePointer(
        ignoring: _out.isAnimating,
        child: FadeTransition(
          opacity: ReverseAnimation(_out),
          child: Material(
            color: bg,
            child: LayoutBuilder(
              builder: (context, c) {
                final cx = c.maxWidth / 2, cy = c.maxHeight / 2;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: rings,
                        builder: (_, _) => CustomPaint(painter: _RingsPainter(Offset(cx, cy), ring, rings.value)),
                      ),
                    ),
                    if (svg != null)
                      Positioned(
                        left: cx - _logoW / 2,
                        top: cy - _logoW * 78 / 80 / 2,
                        child: SvgPicture.string(dark ? svg.replaceAll('#711313', '#FFFFFF') : svg, width: _logoW, height: _logoW * 78 / 80),
                      ),
                    Positioned(
                      left: 24,
                      right: 24,
                      top: cy + _logoW * 78 / 80 / 2 + 30,
                      child: FadeTransition(
                        opacity: text,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(text),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Bài ca đi cùng năm tháng',
                                textAlign: TextAlign.center,
                                style: body(TextStyle(fontSize: 18, height: 26 / 18, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: title)),
                              ),
                              const SizedBox(height: 10),
                              Container(width: 28, height: 1, color: rule),
                              const SizedBox(height: 10),
                              Text(
                                'KHO NHẠC VIỆT NAM XƯA',
                                textAlign: TextAlign.center,
                                style: body(TextStyle(fontSize: 11, height: 16 / 11, fontWeight: FontWeight.w600, letterSpacing: 2.6, color: sub)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Six hairline rings round the mark, fading outward ("vân đĩa than").
class _RingsPainter extends CustomPainter {
  final Offset c;
  final Color color;
  final double t;
  _RingsPainter(this.c, this.color, this.t);

  static const _radii = [96.0, 140.0, 192.0, 252.0, 320.0, 396.0];
  static const _alpha = [0.10, 0.08, 0.065, 0.05, 0.04, 0.03];

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < _radii.length; i++) {
      // Inner rings arrive first; each grows from 82% to its place.
      final local = ((t - i * 0.06) / (1 - 0.3)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      p.color = color.withValues(alpha: _alpha[i] * local);
      canvas.drawCircle(c, _radii[i] * (0.82 + 0.18 * math.min(1, local)), p);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter o) => o.t != t || o.color != color || o.c != c;
}
