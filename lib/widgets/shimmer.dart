import 'package:flutter/material.dart';
import '../constants/theme.dart';

/// Animated diagonal sheen sweeping across child to fake skeleton loading.
class Shimmer extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;
  final Duration duration;
  const Shimmer({
    super.key,
    required this.child,
    this.baseColor = AppColors.surfaceLight,
    this.highlightColor = const Color(0xFF302424),
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: widget.duration)..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (ctx, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = bounds.width * 2 * _ctl.value - bounds.width;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [widget.baseColor, widget.highlightColor, widget.baseColor],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideTransform(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlideTransform extends GradientTransform {
  final double dx;
  const _SlideTransform(this.dx);
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// Quick rectangle placeholder.
class SkBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkBox({super.key, this.width, this.height = 14, this.radius = 8});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(radius)),
  );
}

/// Skeleton stand-in for a SongRow list while data is loading. Renders [rows]
/// fake rows with shimmer applied so the page reserves layout instead of
/// flashing a spinner. Uses the same vertical rhythm as SongRow so when real
/// data swaps in, content doesn't jump.
class SongListSkeleton extends StatelessWidget {
  final int rows;
  final bool showIndex;
  const SongListSkeleton({super.key, this.rows = 8, this.showIndex = false});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: List.generate(rows, (i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle, width: 1))),
          child: Row(
            children: [
              if (showIndex) ...[
                const SizedBox(width: 22, child: Center(child: SkBox(width: 12, height: 10, radius: 4))),
                const SizedBox(width: 8),
              ],
              const SkBox(width: 48, height: 48, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkBox(width: (220 - (i * 12).clamp(0, 80)).toDouble(), height: 12, radius: 4),
                    const SizedBox(height: 6),
                    SkBox(width: (140 - (i * 8).clamp(0, 60)).toDouble(), height: 10, radius: 4),
                  ],
                ),
              ),
            ],
          ),
        )),
      ),
    );
  }
}

/// Skeleton for a hero-style detail header (artwork + title + meta).
/// Suitable for song / playlist / person detail screens.
class HeroSkeleton extends StatelessWidget {
  final bool circular;
  const HeroSkeleton({super.key, this.circular = false});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 160, height: 160,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                shape: circular ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: circular ? null : BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 18),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkBox(width: 80, height: 10, radius: 4),
                  SizedBox(height: 12),
                  SkBox(width: 260, height: 22, radius: 6),
                  SizedBox(height: 8),
                  SkBox(width: 180, height: 14, radius: 4),
                  SizedBox(height: 18),
                  Row(children: [
                    SkBox(width: 60, height: 12, radius: 4),
                    SizedBox(width: 18),
                    SkBox(width: 60, height: 12, radius: 4),
                    SizedBox(width: 18),
                    SkBox(width: 60, height: 12, radius: 4),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
