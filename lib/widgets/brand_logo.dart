import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/theme.dart';

/// The BCĐCNT logo, vector paths taken straight from the brand guideline
/// PDF. [full] = cassette mark + "bcdcnt" wordmark + tagline; otherwise the
/// mark alone. On dark surfaces the wine parts turn white (guideline
/// "logo trên nền tối"), the rose ring stays.
class BrandLogo extends StatelessWidget {
  final double height;
  final bool full;
  /// null = follow the current theme.
  final bool? onDark;
  const BrandLogo({super.key, this.height = 30, this.full = true, this.onDark});

  static final Map<String, Future<String>> _cache = {};

  static Future<String> _load(String asset) =>
      _cache.putIfAbsent(asset, () => rootBundle.loadString(asset));

  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? !AppColors.isLight;
    final asset = full ? 'assets/logo_full.svg' : 'assets/logo_mark.svg';
    // viewBox aspect ratios: full 312x78, mark 80x78.
    final width = height * (full ? 4.0 : 80 / 78);
    return Semantics(
      label: 'Bài ca đi cùng năm tháng',
      image: true,
      child: SizedBox(
        width: width,
        height: height,
        child: FutureBuilder<String>(
          future: _load(asset),
          builder: (context, snap) {
            final raw = snap.data;
            if (raw == null) return const SizedBox.shrink();
            final svg = dark ? raw.replaceAll('#711313', '#FFFFFF') : raw;
            return SvgPicture.string(svg, width: width, height: height);
          },
        ),
      ),
    );
  }
}

/// Spinning cassette mark used as the "đang phát" indicator on the player
/// artwork. Turns only while [spinning].
class SpinningReel extends StatefulWidget {
  final double size;
  final bool spinning;
  const SpinningReel({super.key, this.size = 30, this.spinning = true});

  @override
  State<SpinningReel> createState() => _SpinningReelState();
}

class _SpinningReelState extends State<SpinningReel> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _c.repeat();
  }

  @override
  void didUpdateWidget(SpinningReel old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_c.isAnimating) _c.repeat();
    if (!widget.spinning && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: _c,
        child: BrandLogo(height: widget.size, full: false, onDark: true),
      );
}
